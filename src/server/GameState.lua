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
        },
    }

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
            }
        end
        view.event = {
            id = self.pendingEvent.id,
            title = self.pendingEvent.title,
            stage = self.pendingEvent.stage,
            text = self.pendingEvent.text,
            choices = choices,
        }
    end

    if self.phase == "outcome" and self.outcome then
        view.outcome = self.outcome
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
