--[[
    GameState — the authoritative life. One instance per player, owned by the
    server. Nothing here trusts the client: the client sends intents, this
    module decides outcomes, and the client is only ever sent a view model.

    The loop:
        create  -> race + name + a rolled sheet, shown before play begins
        play    -> Age Up advances a year silently (drift, growth, ageing)
        event   -> at most one event card a year, with 2-3 choices
        outcome -> deltas applied, one paragraph, then back to play
        dead    -> epitaph; play again resets to create

    Step 1 has no combat, no persistence and no party. The attribute layer and
    its derived values are built in full so step 2 can slot combat in.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared.Config)
local Attributes = require(Shared.Attributes)
local Events = require(Shared.Events)
local Rng = require(Shared.Rng)
local Types = require(Shared.Types)
local Combat = require(Shared.Combat)
local CombatData = require(Shared.CombatData)

local GameState = {}
GameState.__index = GameState

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

--- First entry in an age-banded table whose maxAge covers this age.
local function yearBand(bands, age)
    for _, band in ipairs(bands) do
        if age <= band.maxAge then
            return band
        end
    end
    return bands[#bands]
end

-- Flags that are worth a clause in the epitaph, in plain past tense.
-- Order in state.notable is chronological: the epitaph reads as a life.
local NOTABLE_CLAUSES = {
    has_dog = "kept a dog that was not theirs",
    heard_the_news = "heard the news late",
    father_literate_late = "taught a father to read",
    learned_to_trim = "learned early how to leave out the last line",
    declined_to_help = "declined to help when it was asked",
    known_to_the_shrine = "was known to the shrine",
    kept_the_coin = "kept a coin that was not theirs",
    adventurer = "took the copper plate",
    stayed_home = "stayed home and worked",
    knows_the_number = "read the number on the wall",
    took_the_bad_job = "took the job nobody else would take",
    lost_a_party = "came back without all of them",
    still_alive = "was the only one of their intake still alive",
    saw_the_line = "took the metal and did not look at the line",
    knows_the_line = "walked the line of the dead, one to nine",
    broke_at_the_line = "broke at the line and left the metal",
    marked_the_place = "piled stones over nine strangers",
    temple_favour_used = "was owed a favour by a shrine",
    knows_what_passes = "saw what passes on the road and told nobody",
    ran_from_it = "ran, and never knew whether that was why",
    stood_in_the_road = "stood in the road",
    signed_the_roll = "signed the roll",
    read_the_page = "read the page with the column for the reason",
    refused_the_roll = "refused to sign",
    left_the_crowd = "left the crowd before it mattered",
    the_gate = "let go of the gate",
    wanted_in_that_city = "was wanted in that city",
    the_fall = "fell on the sixth stair",
    kept_climbing = "kept climbing them",
    the_house_given = "gave the house away",
    -- step 2: combat leaves marks (stat-model §5.4, §7.4)
    did_the_granary_job = "cleared the granary and was paid by the tail",
    failed_the_granary_contract = "failed a contract in a granary",
    beaten_in_the_granary = "was beaten in a granary and kept the scars",
    came_back_from_the_other_side = "was brought back from the other side, owing",
}

-- ===========================================================================
-- Construction
-- ===========================================================================

function GameState.new(rng)
    local self = setmetatable({}, GameState)
    self.rng = rng or Rng.new()
    self:reset()
    return self
end

--- Clean state, back at character creation. Used at join and by "Play again".
function GameState:reset()
    self.phase = "create"
    self.name = Rng.pick(self.rng, Config.Names.human)
    self.raceKey = nil
    self.baseRoll = Attributes.rollBase(self.rng)
    self.rerollsLeft = Config.Birth.rerolls

    self.age = 0
    self.attrs = nil
    self.health = 0
    self.mana = 0
    self.healthMaxAdjust = 0
    self.exp = 0
    self.level = 1
    self.coin = 0
    self.karma = 0
    self.notoriety = 0
    self.lifespan = nil

    self.flags = {}
    self.fired = {} -- authored tier: one firing per run, never recycled
    self.firedAt = {} -- repeatable tier: the age each generic last fired at
    self.chainQueue = {}
    self.notable = {}
    self.history = {}

    -- step 2: combat
    self.combat = nil
    self.combatContext = nil
    self.combatRecord = nil
    self.items = {}
    self.inventory = {}
    self.injuredUntilAge = nil
    self.marks = {}
    self.threat = nil
    self.fights = 0
    self.fightWins = 0
    self.fightLosses = 0

    self.alive = true
    self.deathCause = nil
    self.pendingEvent = nil
    self.outcome = nil
    self.quietLine = nil
    self.yearLine = nil

    self.derived = Attributes.derived(
        self.baseRoll,
        "human",
        self.healthMaxAdjust
    )
    return self
end

-- ===========================================================================
-- Character creation
-- ===========================================================================

--- Choose a race. Applies that race's percentage bonuses to the SAME base
--- roll — choosing a race never re-rolls the sheet.
function GameState:setRace(raceKey)
    if self.phase ~= "create" then
        return false, "not_creating"
    end
    if not Config.Races[raceKey] then
        return false, "unknown_race"
    end
    self.raceKey = raceKey
    self.attrs = Attributes.applyRace(self.baseRoll, raceKey)
    self:refreshDerived()
    return true
end

--- Sanitise a player-typed name. Anything that is not a letter, space,
--- apostrophe or hyphen is dropped; length is capped.
function GameState:setName(rawName)
    if self.phase ~= "create" or type(rawName) ~= "string" then
        return false, "not_creating"
    end
    local cleaned = rawName:gsub("[^%a%s'%-]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #cleaned == 0 then
        return false, "empty_name"
    end
    self.name = string.sub(cleaned, 1, Config.Birth.maxNameLength)
    return true
end

--- One mercy re-roll per life (design brief §2.1, option C).
function GameState:reroll()
    if self.phase ~= "create" then
        return false, "not_creating"
    end
    if self.rerollsLeft <= 0 then
        return false, "no_rerolls"
    end
    self.rerollsLeft -= 1
    self.baseRoll = Attributes.rollBase(self.rng)
    if self.raceKey then
        self.attrs = Attributes.applyRace(self.baseRoll, self.raceKey)
    end
    self:refreshDerived()
    return true
end

--- Commit to the life. Rolls the family circumstances that the rest of the
--- run hangs off, fills the pools, and hands control to the year loop.
function GameState:begin()
    if self.phase ~= "create" then
        return false, "not_creating"
    end
    if not self.raceKey then
        return false, "no_race"
    end

    -- Family circumstance: a birth variable, locked here and never re-rolled.
    local roll = self.rng:NextNumber()
    local cumulative = 0
    local band = Config.Birth.WealthBands[#Config.Birth.WealthBands]
    for _, candidate in ipairs(Config.Birth.WealthBands) do
        cumulative += candidate.chance
        if roll <= cumulative then
            band = candidate
            break
        end
    end
    self.flags[band.flag] = true
    self.coin = band.coin
    self.history[#self.history + 1] = string.format("Born %s, to a %s house.", self.name, band.label)

    self.age = 0
    self.exp = 0
    self.level = 1
    self.karma = 0
    self.notoriety = 0
    self.healthMaxAdjust = 0
    self.lifespan = Attributes.lifespan(self.attrs)
    self:refreshDerived()
    self.health = self.derived.healthMax
    self.mana = self.derived.manaMax

    self.alive = true
    self.deathCause = nil
    self.pendingEvent = nil
    self.outcome = nil
    self.quietLine = nil
    -- Gear is stubbed for step 2 (stat-model §4.2): one oil flask is the only
    -- item the first encounter knows about, and it is what the player carries.
    self.items = {}
    for id, count in pairs(CombatData.PlayerLoadout.items) do
        self.items[id] = count
    end
    self.inventory = {}
    self.injuredUntilAge = nil
    self.marks = {}
    self.fights = 0
    self.fightWins = 0
    self.fightLosses = 0
    self.yearLine = string.format("Born. %d coin in the house.", band.coin)
    self.phase = "play"
    return true
end

-- ===========================================================================
-- Derived values
-- ===========================================================================

--- Recompute everything derived from the current attributes.
function GameState:refreshDerived()
    if not self.attrs then
        self.attrs = Attributes.applyRace(self.baseRoll, self.raceKey or "human")
    end
    self.derived = Attributes.derived(self.attrs, self.raceKey or "human", self.healthMaxAdjust)
    self.level = Attributes.levelFromExp(self.exp)
end

-- ===========================================================================
-- The year tick
-- ===========================================================================

--- Advance one year. Silent resolution first (drift, growth, ageing, death
--- checks), then at most one event card.
function GameState:ageUp()
    if self.phase ~= "play" then
        return false, "not_now"
    end
    if not self.alive then
        return false, "dead"
    end

    self.age += 1
    local notes = {}

    -- 1. Coin: income minus upkeep. Children earn nothing; adults drift.
    local band = yearBand(Config.Year.income, self.age)
    local net = band.income - band.upkeep
    if net ~= 0 then
        self.coin = math.max(0, self.coin + net)
        notes[#notes + 1] = string.format("%+d coin", net)
    end
    -- (Upkeep is already netted off above; there is no separate debt in step 1.)

    -- 2. Experience for surviving the year (race multiplier applied inside).
    local expGain = yearBand(Config.Year.exp, self.age).amount
    self:gainExp(expGain)
    notes[#notes + 1] = string.format("+%d exp", Attributes.applyExpMultiplier(expGain, self.raceKey))

    -- 3. Health drift: recovery while young, decline in old age.
    local healthDrift = 0
    if self.age >= Config.Year.healthDeclineFrom then
        healthDrift = -Config.Year.healthDeclinePerYear
    elseif self.health < self.derived.healthMax then
        healthDrift = Config.Year.healthRegenBefore40
        -- stat-model §5.5: a year restores 25% + VIT × 2% of max, if fed, housed
        -- and not Wounded. Combat damage is life damage (§5.2), so this is what
        -- makes a fighting life survivable at all. An unhealed wound halves it.
        if Config.Combat.useFractionalRecovery then
            local fraction = Config.Derived.restBaseFraction
                + self.attrs.VIT * Config.Derived.restVitFraction
            local recovering = math.floor(self.derived.healthMax * fraction)
            if self.injuredUntilAge and self.age < self.injuredUntilAge then
                recovering = math.floor(recovering * 0.5) -- TUNING: a wound slows it
            end
            healthDrift = math.max(healthDrift, recovering)
        end
    end
    if healthDrift ~= 0 then
        self.health += healthDrift
        notes[#notes + 1] = string.format("%+d health", healthDrift)
    end

    -- 4. Mana recovers between fights; step 2 will spend it.
    self.mana = clamp(
        self.mana + math.ceil(self.derived.manaMax * Config.Year.manaRestorePerYear),
        0,
        self.derived.manaMax
    )

    -- 5. Notoriety decays when you are quiet.
    if self.notoriety > 0 and self.age >= Config.Year.notorietyDecayFrom then
        self.notoriety = math.max(0, self.notoriety - Config.Year.notorietyDecay)
    end

    -- 6. Attributes grow, and in old age some of them decay.
    local grown = self:growAttributes()
    if grown then
        notes[#notes + 1] = grown
    end

    -- 7. Ageing recomputes the pools: VIT loss is visible on the health bar.
    self:refreshDerived()
    self.health = math.min(self.health, self.derived.healthMax)

    -- 8. Death checks, before the card: a year can kill without a choice.
    if self.health <= 0 then
        self:kill("their body gave out")
        return true
    end
    local naturalDeath = self:naturalDeathChance()
    if self.age >= Config.Death.hardAgeLimit or (naturalDeath > 0 and Rng.chance(self.rng, naturalDeath)) then
        self:kill("age")
        return true
    end

    -- 9. Event draw: a due chain overrides everything, otherwise weighted.
    self.yearLine = table.concat(notes, " · ")
    local event = Events.dueChain(self) or Events.draw(self, self.rng)
    if event then
        self.pendingEvent = event
        -- Anti-repetition, per tier: an authored event fires once a run, a
        -- generic records the year so its cooldown can hold it back.
        self.fired[event.id] = true
        self.firedAt[event.id] = self.age
        self.quietLine = nil
        self.phase = "event"
    else
        self.pendingEvent = nil
        self.quietLine = Rng.pick(self.rng, Config.QuietYearLines)
        self.phase = "play"
    end
    return true
end

--- Chance of dying of age this year. Zero until the lifespan rolled at birth.
function GameState:naturalDeathChance()
    if not self.lifespan then
        return 0
    end
    local past = self.age - self.lifespan
    if past <= Config.Death.naturalDeathGrace then
        return 0
    end
    return math.min(Config.Death.naturalDeathMaxChance, past * Config.Death.naturalDeathRamp)
end

--- Per-year attribute drift: growth bands from Config.Growth, plus decay.
--- Returns a short note for the "year in numbers" line, or nil.
function GameState:growAttributes()
    local grown = {}
    for _, key in ipairs(Config.AttributeOrder) do
        local rule = Config.Growth[key]
        if rule then
            local grows = false
            if self.age >= rule.growFrom and self.age <= rule.growTo and rule.chance > 0 then
                grows = Rng.chance(self.rng, rule.chance)
            end
            local decays = false
            if rule.decayFrom and self.age >= rule.decayFrom then
                local every = rule.decayEvery or 1
                decays = (self.age - rule.decayFrom) % every == 0
            end

            local delta = (grows and 1 or 0) - (decays and 1 or 0)
            if delta ~= 0 then
                local next_ = clamp(
                    self.attrs[key] + delta,
                    Config.AttributeMin,
                    Config.AttributeMax
                )
                if next_ ~= self.attrs[key] then
                    self.attrs[key] = next_
                    grown[#grown + 1] = string.format("%+d %s", delta, key)
                end
            end
        end
    end
    if #grown == 0 then
        return nil
    end
    return table.concat(grown, ", ")
end

--- Experience, always through the race multiplier (Human +25%).
function GameState:gainExp(amount)
    if amount <= 0 then
        return
    end
    self.exp += Attributes.applyExpMultiplier(amount, self.raceKey)
    local newLevel = Attributes.levelFromExp(self.exp)
    if newLevel > self.level then
        self.history[#self.history + 1] = string.format("Reached level %d.", newLevel)
    end
    self.level = newLevel
end

-- ===========================================================================
-- Choices and deltas
-- ===========================================================================

--- Resolve the player's choice. Checks are rolled here, on the server.
function GameState:choose(index)
    if self.phase ~= "event" or not self.pendingEvent then
        return false, "no_event"
    end

    local event = self.pendingEvent
    local choice = type(index) == "number" and event.choices[index] or nil
    if not choice then
        return false, "bad_choice"
    end

    -- A choice can lead into a fight (§5.1). The fight IS the resolution of this
    -- year's decision: the card was the preamble, and the aftermath becomes the
    -- year's outcome paragraph. Combat does not consume a year.
    if choice.startsCombat and event.combat then
        self.pendingEvent = nil
        self:enterCombat(event.combat.encounter, event.combat)
        return true
    end

    local text, deltas, branch, checkLine
    if choice.check then
        local check = Attributes.check(self.rng, self.attrs, choice.check.attr, choice.check.dc)
        branch = check.success and choice.success or choice.failure
        if branch then
            text = branch.text
            deltas = branch.deltas
        else
            text = choice.text
            deltas = choice.deltas
        end
        checkLine = string.format(
            "%s check: d20 %d %+d = %d vs %d — %s",
            choice.check.attr,
            check.roll,
            check.modifier,
            check.total,
            check.dc,
            check.success and "success" or "failure"
        )
    else
        text = choice.text or ""
        deltas = choice.deltas
    end

    local chips = self:applyDeltas(deltas)
    local chainSource = branch or choice

    self.outcome = {
        eventTitle = event.title,
        text = text,
        chips = chips,
        check = checkLine,
    }
    self.pendingEvent = nil
    self.history[#self.history + 1] = string.format("Age %d: %s", self.age, event.title)

    -- Chains: consequence with a delay. The player forgets; the world does not.
    local nextId = chainSource.next or choice.next
    if nextId then
        local delay = chainSource.delayYears or choice.delayYears or 0
        table.insert(self.chainQueue, { id = nextId, atAge = self.age + delay })
    end

    -- A choice can end a run. It is the one card that can, and it never warns.
    if self.health <= 0 then
        self:kill(event.deathText or "wounds taken in a year that was otherwise ordinary")
        return true
    end

    self:refreshDerived()
    self.health = math.min(self.health, self.derived.healthMax)
    self.phase = "outcome"
    return true
end

--- Apply a Deltas block and return display chips. Karma is scaled by Piety:
--- a devout character's acts are worth more in the ledger, for good and ill.
function GameState:applyDeltas(deltas)
    local chips = {}
    if not deltas then
        return chips
    end

    if deltas.health then
        self.health += deltas.health
        chips[#chips + 1] = string.format("%+d health", deltas.health)
    end
    if deltas.healthMaxAdjust then
        self.healthMaxAdjust += deltas.healthMaxAdjust
        chips[#chips + 1] = string.format("%+d health max", deltas.healthMaxAdjust)
    end
    if deltas.exp then
        local before = self.level
        self:gainExp(deltas.exp)
        chips[#chips + 1] = string.format("+%d exp", Attributes.applyExpMultiplier(deltas.exp, self.raceKey))
        if self.level > before then
            chips[#chips + 1] = string.format("level %d", self.level)
        end
    end
    if deltas.coin then
        self.coin = math.max(0, self.coin + deltas.coin)
        chips[#chips + 1] = string.format("%+d coin", deltas.coin)
    end
    if deltas.karma then
        local scale = Attributes.karmaScale(self.attrs)
        local scaled = deltas.karma > 0 and math.floor(deltas.karma * scale)
            or -math.floor(-deltas.karma * scale)
        self.karma += scaled
        chips[#chips + 1] = string.format("Karma %+d", scaled)
    end
    if deltas.notoriety then
        self.notoriety = math.max(0, self.notoriety + deltas.notoriety)
        chips[#chips + 1] = string.format("Notoriety %+d", deltas.notoriety)
    end
    for key, delta in pairs(deltas.attr or {}) do
        if self.attrs[key] ~= nil and delta ~= 0 then
            local before = self.attrs[key]
            self.attrs[key] = clamp(before + delta, Config.AttributeMin, Config.AttributeMax)
            local applied = self.attrs[key] - before
            if applied ~= 0 then
                chips[#chips + 1] = string.format("%+d %s", applied, key)
            end
        end
    end
    for _, flag in ipairs(deltas.flags or {}) do
        if not self.flags[flag] then
            self.flags[flag] = true
            local clause = NOTABLE_CLAUSES[flag]
            if clause then
                self.notable[#self.notable + 1] = clause
            end
        end
    end
    for _, flag in ipairs(deltas.clearFlags or {}) do
        self.flags[flag] = nil
    end

    -- Keep the sheet's derived values honest after any of the above.
    self:refreshDerived()
    self.health = math.min(self.health, self.derived.healthMax)
    return chips
end

--- Back to the main screen after an outcome paragraph.
function GameState:continue()
    if self.phase ~= "outcome" then
        return false, "not_resolving"
    end
    self.outcome = nil
    self.phase = "play"
    return true
end

-- ===========================================================================
-- Combat — a fight is a MODE the year loop enters and leaves (§5.1)
--
-- The event card leads in, the fight resolves INSIDE the same year, and the
-- aftermath is the year's outcome paragraph. Damage is life damage: there is
-- one health pool (§5.2).
-- ===========================================================================

--- Wounded: below 30% of max health, or carrying a wound from a lost fight
--- (§5.5). It is worth −25% damage dealt and it is visible on the main screen.
function GameState:isWounded()
    if self.injuredUntilAge and self.age < self.injuredUntilAge then
        return true
    end
    if self.alive and self.derived and self.derived.healthMax > 0 then
        return self.health <= self.derived.healthMax * Config.Combat.woundedThreshold
    end
    return false
end

--- The player's side of the fight, built from the real sheet (§4.1 #7).
function GameState:combatSpec()
    local gear = CombatData.PlayerLoadout.gear
    return {
        name = self.name,
        level = self.level,
        vocation = self:vocation(),
        attrs = self.attrs,
        health = self.health,
        healthMax = self.derived.healthMax,
        mana = self.mana,
        manaMax = self.derived.manaMax,
        manaRegen = self.derived.manaRegen,
        gear = gear,
        actions = CombatData.PlayerLoadout.actions,
        items = self.items,
        fortune = self.derived.fortune,
        injured = self:isWounded(),
        damageType = "physical",
    }
end

--- Enter a fight. `encounter` may be an id (the game) or a table (the harness).
--- `context` is the event's combat block: the prose for each exit (§5.1).
function GameState:enterCombat(encounter, context)
    local def = type(encounter) == "string" and CombatData.Encounters[encounter] or encounter
    if not def then
        return false, "unknown_encounter"
    end
    if self.phase ~= "play" and self.phase ~= "event" then
        return false, "not_now"
    end
    if not self.attrs then
        return false, "no_sheet"
    end

    -- The design rule, enforced in code: severity `dead` is never attached to a
    -- fair fight (§5.4). If an encounter in data ever tries, say so loudly.
    local severity = def.lossSeverity or "defeat"
    if severity == "dead" and Config.Combat.forbidDeadOnWinnableFight and not def.explicitlyFatal then
        warn(string.format(
            "[NWL] encounter %s has lossSeverity='dead' on a fightable enemy. "
            .. "Dead belongs to events, not to fights you can win (stat-model §5.4).",
            tostring(def.id)
        ))
    end

    self.health = math.max(1, self.health)
    local fight = Combat.new(self.rng, self:combatSpec(), def)
    fight:begin()
    self.combat = fight
    self.combatContext = context or {}
    self.threat = fight.player.threat
    self.fights += 1
    self.phase = "combat"
    self.pendingEvent = nil
    self.history[#self.history + 1] = string.format("Age %d: %s (a fight)", self.age, fight.title)
    if fight.status ~= "active" then
        self:resolveCombat()
    end
    return true
end

--- The player's intent inside a fight: an action, or spending Fortune.
--- Returns ok, reason.
function GameState:combatAction(data)
    if self.phase ~= "combat" or not self.combat then
        return false, "no_fight"
    end
    local action = type(data) == "table" and data.action or nil
    if action == "fortune" then
        local ok, reason = self.combat:armFortune()
        if not ok then
            return false, reason
        end
        return true
    end
    if type(action) ~= "string" then
        return false, "no_action"
    end
    local target = type(data) == "table" and data.target or nil
    local ok, reason = self.combat:playerAction(action, target)
    if not ok then
        return false, reason
    end
    if self.combat.status ~= "active" then
        self:resolveCombat()
    end
    return true
end

--- The fight is over. Work out what it cost, in the life sim's terms (§5.4).
function GameState:resolveCombat()
    local fight = self.combat
    if not fight then
        return false, "no_fight"
    end
    local context = self.combatContext or {}
    local chips = {}
    local text, severity
    local summary = {
        result = fight.status,
        rounds = fight.round,
        health = math.max(0, fight.player.health),
        healthMax = fight.player.healthMax,
        mana = math.floor(fight.player.mana),
        manaMax = fight.player.manaMax,
        enemies = {},
        title = fight.title,
        partial = fight.partial or false,
    }
    for _, enemy in ipairs(fight.enemies) do
        summary.enemies[#summary.enemies + 1] = {
            name = enemy.name,
            downed = enemy.health <= 0,
            fled = enemy.fled or false,
            health = math.max(0, enemy.health),
            healthMax = enemy.healthMax,
        }
    end
    summary.log = {}
    for index = math.max(1, #fight.log - 6), #fight.log do
        summary.log[#summary.log + 1] = fight.log[index]
    end

    -- One health pool: whatever the fight left you on is what you are on (§5.2).
    self.health = math.max(0, fight.player.health)
    self.mana = math.max(0, fight.player.mana)
    self.items = fight.player.items

    if fight.status == "won" then
        self.fightWins += 1
        local reward = Config.Combat.VictoryReward
        local win = context.onWin or {}
        text = win.text or "The job is done and the guild pays by the tail."
        self.coin = math.max(0, self.coin + reward.coin)
        chips[#chips + 1] = string.format("+%d coin", reward.coin)
        self:gainExp(reward.exp)
        chips[#chips + 1] = string.format("+%d exp", Attributes.applyExpMultiplier(reward.exp, self.raceKey))
        self.inventory[#self.inventory + 1] = reward.item
        self.flags[reward.repFlag] = true
        self.notable[#self.notable + 1] = NOTABLE_CLAUSES[reward.repFlag] or "did the job"
        local applied = self:applyDeltas(win.deltas)
        for _, chip in ipairs(applied) do
            chips[#chips + 1] = chip
        end
        if summary.partial then
            text = text .. " One of them got away, and the tail money is short for it."
        end
    elseif fight.status == "fled" then
        local flee = context.onFlee or {}
        text = flee.text
            or "You get out. The contract does not: you are alive, unpaid, and known for leaving."
        self.flags[Config.Combat.FleeCost.flag] = true
        if not self.flags.failed_the_granary_contract then
            self.flags.failed_the_granary_contract = true
        end
        self.notable[#self.notable + 1] = NOTABLE_CLAUSES.failed_the_granary_contract
        local applied = self:applyDeltas(flee.deltas)
        for _, chip in ipairs(applied) do
            chips[#chips + 1] = chip
        end
    else
        -- Lost. The severity comes from the encounter, never from a die (§5.4).
        self.fightLosses += 1
        local lose = context.onLose or {}
        severity = lose.severity or fight.lossSeverity or "defeat"

        if severity == Config.Combat.Severities.dead then
            self:kill(lose.deathText or string.format("killed by %s", fight.title:lower()))
            return true
        end

        if severity == Config.Combat.Severities.downed then
            local cost = Config.Combat.DownedCost
            self.health = math.max(1, math.floor(self.derived.healthMax * cost.healthFraction))
            self.level = math.max(1, self.level - cost.levelsLost)
            self.exp = math.min(self.exp, Attributes.expForLevel(self.level))
            self:refreshDerived()
            self.flags.resurrection_debt = true
            self.flags.came_back_from_the_other_side = true
            self.notable[#self.notable + 1] = NOTABLE_CLAUSES.came_back_from_the_other_side
            text = lose.text or string.format(
                "You wake on a table you did not pay for. %s", cost.debtText
            )
            chips[#chips + 1] = "level down"
            chips[#chips + 1] = string.format("health %d", self.health)
            -- The debt is a chain event years later (§5.4: obligation is the
            -- most interesting cost and the cheapest to build).
            table.insert(self.chainQueue, {
                id = "E_DEBT_CALLED",
                atAge = self.age + cost.debtYears + math.floor(self.rng:NextNumber() * 8),
            })
        else
            local cost = Config.Combat.DefeatCost
            local lost = math.floor(self.coin * cost.coinLossFraction)
            self.coin = math.max(0, self.coin - lost)
            self.health = cost.healthFloor
            self.injuredUntilAge = self.age + cost.injuredYears
            self.flags[cost.mark] = true
            self.marks[#self.marks + 1] = cost.mark
            self.notable[#self.notable + 1] = NOTABLE_CLAUSES[cost.mark] or "was beaten and kept the scars"
            text = lose.text or string.format(
                "You come round on the floor with your purse lighter by %d coin and your "
                .. "ribs telling you something you will not hear from anyone else: they had "
                .. "no reason to finish you, and they did not. You will be carrying this for "
                .. "%d years.",
                lost, cost.injuredYears
            )
            chips[#chips + 1] = string.format("-%d coin", lost)
            chips[#chips + 1] = string.format("Wounded for %d years", cost.injuredYears)
        end
        local applied = self:applyDeltas(lose.deltas)
        for _, chip in ipairs(applied) do
            chips[#chips + 1] = chip
        end
    end

    self.combatRecord = summary
    self.outcome = {
        eventTitle = fight.title,
        text = text,
        chips = chips,
        combat = summary,
    }
    self.combat = nil
    self.combatContext = nil
    self:refreshDerived()
    self.health = math.min(self.health, self.derived.healthMax)
    if self.health <= 0 then
        self:kill("wounds taken in a year that was otherwise ordinary")
        return true
    end
    self.phase = "outcome"
    return true
end

-- ===========================================================================
-- Death
-- ===========================================================================

function GameState:kill(cause)
    self.alive = false
    self.phase = "dead"
    self.deathCause = cause
    self.pendingEvent = nil
    self.quietLine = nil
    self.history[#self.history + 1] = string.format("Died at %d (%s).", self.age, cause)
end

--- What they were, for the death screen.
function GameState:vocation()
    if self.flags.adventurer then
        return "adventurer"
    elseif self.flags.stayed_home then
        return "farmer"
    elseif self.attrs and self.attrs.CHA >= self.attrs.STR then
        return "talker"
    end
    return "nobody in particular"
end

--- The epitaph never comforts the player. It reports (design brief §1.6).
function GameState:epitaph()
    local race = Config.Races[self.raceKey]
    local raceName = race and race.name:lower() or "person"
    local article = (raceName:sub(1, 1):match("[aeiou]")) and "an" or "a"

    local lines = {}
    lines[#lines + 1] = string.format("%s was %s %s.", self.name, article, raceName)

    if #self.notable > 0 then
        local clauses = {}
        for index = 1, math.min(3, #self.notable) do
            clauses[#clauses + 1] = self.notable[index]
        end
        lines[#lines + 1] = "They " .. table.concat(clauses, ", ") .. "."
    end

    lines[#lines + 1] = string.format(
        "They died at %d, %s, with %d coin to their name.",
        self.age,
        self:vocation(),
        self.coin
    )

    if self.karma >= 20 then
        lines[#lines + 1] = "The ledger said they were a decent sort, which is not the same as being missed."
    elseif self.karma <= -20 then
        lines[#lines + 1] = "The ledger had more entries against them than for them, and it is a long ledger."
    else
        lines[#lines + 1] = "The ledger had little to say, which is the ordinary condition."
    end

    if self.notoriety >= 40 then
        lines[#lines + 1] = "People who had never met them had opinions about them anyway."
    end

    lines[#lines + 1] = "No one wrote any of this down."
    return table.concat(lines, " ")
end

-- ===========================================================================
-- View model — the only thing the client is ever sent
-- ===========================================================================

function GameState:view()
    local race = self.raceKey and Config.Races[self.raceKey] or nil
    local into, span, fraction = Attributes.levelProgress(self.exp)

    local view = {
        phase = self.phase,
        name = self.name,
        age = self.age,
        raceKey = self.raceKey,
        raceName = race and race.name or nil,
        stage = Events.stageFor(self.age),
        alive = self.alive,
        lifespan = self.lifespan,
        yearLine = self.yearLine,
        quietLine = self.quietLine,
        attrs = self.attrs,
        attributeMeta = Config.Attributes,
        attributeOrder = Config.AttributeOrder,
        derived = self.derived,
        notable = self.notable,
        history = self.history,
        vocation = self.attrs and self:vocation() or nil,
        resources = {
            health = self.health,
            mana = self.mana,
            level = self.level,
            expIntoLevel = into,
            expForLevel = span,
            expFraction = fraction,
            coin = self.coin,
            karma = self.karma,
            notoriety = self.notoriety,
            wounded = self:isWounded(),
            injuredUntilAge = self.injuredUntilAge,
            threat = self.threat,
            fights = self.fights,
            items = self.items,
            inventory = self.inventory,
            marks = self.marks,
        },
    }

    if self.phase == "combat" and self.combat then
        view.combat = self.combat:view()
    end

    if self.phase == "create" then
        local races = {}
        for _, key in ipairs(Config.RaceOrder) do
            local definition = Config.Races[key]
            local bonuses = {}
            for attrKey, pct in pairs(definition.attrBonus) do
                bonuses[#bonuses + 1] = string.format("+%d%% %s", math.floor(pct * 100), attrKey)
            end
            table.sort(bonuses)
            local extra = {}
            if definition.expMultiplier > 1 then
                extra[#extra + 1] = string.format("+%d%% experience from all sources", math.floor((definition.expMultiplier - 1) * 100))
            end
            if definition.healthMultiplier > 1 then
                extra[#extra + 1] = string.format("+%d%% max health", math.floor((definition.healthMultiplier - 1) * 100))
            end
            races[#races + 1] = {
                id = key,
                name = definition.name,
                blurb = definition.blurb,
                bonuses = bonuses,
                extra = extra,
            }
        end

        view.create = {
            birthParagraph = Config.BirthParagraph,
            instruction = Config.BirthInstruction,
            races = races,
            name = self.name,
            baseRoll = self.baseRoll,
            preview = self.attrs or self.baseRoll,
            selectedRace = self.raceKey,
            rerollsLeft = self.rerollsLeft,
            previewDerived = self.derived,
        }
    end

    if self.phase == "event" and self.pendingEvent then
        local choices = {}
        for index, choice in ipairs(self.pendingEvent.choices) do
            choices[#choices + 1] = {
                index = index,
                label = choice.label,
                warn = choice.warn,
                startsCombat = choice.startsCombat or false,
            }
        end
        view.event = {
            id = self.pendingEvent.id,
            title = self.pendingEvent.title,
            stage = self.pendingEvent.stage,
            text = self.pendingEvent.text,
            choices = choices,
        }
        -- The fairness rule made structural (§5.1): an event that leads to a
        -- fight says so, in prose, before the player chooses — and the card
        -- shows the health they would be taking in with them.
        local block = self.pendingEvent.combat
        if block then
            view.event.combat = {
                warning = block.warning or self.pendingEvent.combatWarning,
                stakes = block.stakes,
                severity = block.severity,
                cornered = block.cornered or false,
                health = self.health,
                healthMax = self.derived.healthMax,
                mana = self.mana,
                lowHealth = (not block.severity or block.severity ~= "dead")
                    and self:isWounded() and Config.Combat.lowHealthWarning or nil,
            }
        end
    end

    if self.phase == "outcome" and self.outcome then
        view.outcome = self.outcome
    end
    -- Combat (§6.2): the whole panel, as data, built server-side. The client
    -- draws it and sends intents back; it never computes a number of its own,
    -- so the projected damage on a button is the damage the log will print.
    if self.phase == "combat" and self.combat then
        view.combat = self.combat:view()
    end

    if self.phase == "dead" then
        view.death = {
            epitaph = self:epitaph(),
            cause = self.deathCause,
            summary = {
                { "Name", self.name },
                { "Race", race and race.name or "—" },
                { "Age at death", tostring(self.age) },
                { "Level", tostring(self.level) },
                { "Coin", tostring(self.coin) },
                { "Karma", tostring(self.karma) },
                { "Notoriety", tostring(self.notoriety) },
                { "What they were", self:vocation() },
            },
            notable = self.notable,
            attrs = self.attrs,
            attributeOrder = Config.AttributeOrder,
        }
    end

    return view
end

-- Expose the intent allow-list so the server entry point stays thin.
GameState.Intents = Types.Intents

return GameState
