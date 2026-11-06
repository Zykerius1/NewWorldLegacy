--[[
    Combat — the turn-based tactical layer. Server-authoritative, pure logic:
    given an rng, a player spec and an encounter table it produces a fight, and
    a fight is only ever advanced by a call to :playerAction(). Nothing here
    touches Roblox APIs, so the headless harness runs this exact code.

    Design source: stat-model-v1.md §3 (the system), §4.1 (step 2's scope),
    §5 (hand-off to the life sim) and §6 (what the player sees).

    The three things that must be right, in order of importance:
      1. BRACE. It costs the attack, cuts incoming damage to 40%, and breaks a
         Charged attack, staggering the attacker (§3.3). If Brace is bad the
         fight is a dice roll.
      2. THE TELEGRAPH. A Charged attack is announced on the panel BEFORE the
         player chooses (§3.8, §6.1). The player always gets an action in
         between seeing the chip and eating the attack — if the enemy is faster
         than the player, it spends its turn charging instead, so the warning is
         a round long either way.
      3. THE PIPELINE. Eleven steps, in the order written in §3.5, every time.

    Damage is LIFE damage: the fight does not carry its own health pool (§5.2).
]]

local CombatData = require(script.Parent.CombatData)
local Config = require(script.Parent.Config)
local Attributes = require(script.Parent.Attributes)

local Combat = {}
Combat.__index = Combat

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

Combat.clamp = clamp

-- ===========================================================================
-- Unit construction
-- ===========================================================================

--- Everything derived, for the player. Gear is stubbed (CombatData.PlayerLoadout)
--- but every attribute on the sheet feeds a formula, even where it is worth zero
--- (stat-model §4.1 #7).
function Combat.playerUnit(spec)
    local attrs = spec.attrs
    local gear = spec.gear or CombatData.PlayerLoadout.gear
    local c = Config.Combat

    local unit = {
        id = "player",
        side = "player",
        name = spec.name or "You",
        level = spec.level or 1,
        vocation = spec.vocation,
        kind = spec.kind or "HUMAN",
        label = "YOU",
        attrs = attrs,
        gear = gear,
        health = spec.health,
        healthMax = spec.healthMax,
        mana = spec.mana,
        manaMax = spec.manaMax,
        manaRegen = spec.manaRegen,
        armour = math.floor((gear.armour or 0) + Attributes.armour(attrs)),
        ward = math.floor((gear.ward or 0) + Attributes.ward(attrs)),
        dodge = Attributes.dodge(attrs),
        crit = Attributes.critRate(attrs),
        critMult = c.critDamageBase + (gear.critDamageBonus or 0),
        dex = attrs.DEX,
        wis = attrs.WIS,
        luck = attrs.LUK,
        armourPenalty = gear.armourPenalty or 0,
        statuses = {},
        actions = spec.actions or CombatData.PlayerLoadout.actions,
        items = spec.items or {},
        cooldowns = {},
        fortune = spec.fortune or 0,
        fortuneMax = spec.fortune or 0,
        damageType = spec.damageType or "physical",
        note = spec.note,
    }
    unit.threat = Combat.threat(unit)
    return unit
end

--- An enemy from an archetype template. Stat blocks print flat defences (§3.10),
--- so the archetype carries them; DEX and WIS still drive initiative, resist and
--- the attacker's accuracy term.
function Combat.enemyUnit(archetypeId, instanceId)
    local def = CombatData.Archetypes[archetypeId]
    assert(def, "unknown archetype: " .. tostring(archetypeId))
    local unit = {
        id = instanceId,
        side = "enemy",
        archetypeId = archetypeId,
        name = def.name,
        label = def.label,
        kind = def.kind,
        tier = def.tier,
        attrs = def.attrs,
        health = def.health,
        healthMax = def.health,
        mana = 0,
        manaMax = 0,
        manaRegen = 0,
        armour = def.armour,
        ward = def.ward,
        dodge = def.dodge,
        crit = def.crit,
        critMult = Config.Combat.critDamageBase,
        dex = def.attrs.DEX,
        wis = def.attrs.WIS,
        luck = def.attrs.LUK,
        armourPenalty = def.armourPenalty or 0,
        statuses = {},
        attacksPerTurn = def.attacksPerTurn or 1,
        pattern = def.pattern,
        patternIndex = 1,
        damageType = def.damageType,
        note = def.note,
        flee = def.flee,
        -- How much this enemy's blows grow per round it stays standing
        -- (+10% raw per round at 0.10). 0 means it never gets worse.
        ramp = def.ramp or 0,
    }
    unit.threat = Combat.threat(unit)
    return unit
end

--- Threat, per gear-v1.md §3.5's recommended formula. STORED, never balanced
--- against — gear does not exist yet, so this is a display value only.
function Combat.threat(unit)
    local sum = 0
    for _, value in pairs(unit.attrs or {}) do
        sum += value
    end
    local gearBonus = 0
    if unit.gear then
        gearBonus = (unit.gear.weaponPower or 0) + (unit.gear.armour or 0) + (unit.gear.ward or 0)
    end
    return (unit.level or 1) * 4 + sum + gearBonus
end

-- ===========================================================================
-- Construction
-- ===========================================================================

--- Start a fight. `encounter` is a table (see CombatData.Encounters) so the
--- harness can build a test encounter without authoring one into the game.
function Combat.new(rng, playerSpec, encounter)
    local self = setmetatable({}, Combat)
    self.rng = rng
    self.encounter = encounter
    self.title = encounter.title or "A fight"
    self.lossSeverity = encounter.lossSeverity or "defeat"
    self.cornered = encounter.cornered or false
    self.warning = encounter.warning
    self.stakes = encounter.stakes
    self.sourceTier = encounter.sourceTier or 0
    -- Standoff (§3.10): a fight that can be SURVIVED rather than only won, so
    -- that holding the line is a real plan and not a slow way to lose. The
    -- round and the wording live on the encounter, never here.
    self.standoff = encounter.standoff
    -- Which unit-turn we are on. Used to decide whether a control status
    -- applied during a unit's OWN turn has had its one turn yet (see
    -- Combat:decayStatuses and Config.Combat.staggerSurvivesOwnTurn).
    self.turnSerial = 0
    self.round = 0
    self.status = "active" -- active | won | fled | lost
    self.awaitingPlayer = false
    self.log = {}
    self.turnIndex = 0
    self.order = {}
    self.units = {}
    self.fortuneArmed = false

    self.player = Combat.playerUnit(playerSpec)
    self.enemies = {}
    for _, entry in ipairs(encounter.enemies or {}) do
        local unit = Combat.enemyUnit(entry.archetype, entry.id)
        unit.name = entry.name or unit.name
        self.enemies[#self.enemies + 1] = unit
    end

    self.units[#self.units + 1] = self.player
    for _, unit in ipairs(self.enemies) do
        self.units[#self.units + 1] = unit
    end
    return self
end

--- Roll initiative ONCE (§3.2), fix the order for the whole fight, and run
--- forward until the player must choose or the fight is over. Ties go to Luck.
function Combat:begin()
    if self.started then
        return
    end
    self.started = true

    for _, unit in ipairs(self.units) do
        unit.initiativeRoll = self:rollDie(Config.Combat.initiativeDie, "initiative")
        unit.initiative = unit.initiativeRoll + unit.dex + math.floor(unit.wis / 2) - (unit.armourPenalty or 0)
    end
    table.sort(self.units, function(a, b)
        if a.initiative ~= b.initiative then
            return a.initiative > b.initiative
        end
        return (a.luck or 0) > (b.luck or 0) -- ties: higher LUK first (§3.2)
    end)
    -- Telegraph lead (§3.2/§6.1 #2, and the fairness law): an enemy that acts
    -- before the player cannot telegraph and fire in the same round without
    -- robbing the player of their turn, so it charges for a full round instead.
    -- An enemy slower than the player telegraphs at the start of the round it
    -- fires in, because the player acts first in that round — which is exactly
    -- what §3.10 does with the Barrow Rat.
    for _, unit in ipairs(self.enemies) do
        unit.telegraphLead = unit.initiative > self.player.initiative and 1 or 0
    end

    for index, unit in ipairs(self.units) do
        self.order[index] = unit.id
    end
    self.unitById = {}
    for _, unit in ipairs(self.units) do
        self.unitById[unit.id] = unit
    end

    local orderNames = {}
    for _, unit in ipairs(self.units) do
        orderNames[#orderNames + 1] = string.format("%s (%d)", unit.name, unit.initiative)
    end
    self:logLine("Initiative: " .. table.concat(orderNames, " > ") .. ".")

    self.turnIndex = 0
    self:startRound()
    self:step()
end

--- Shortest-form unit name for the log: the player is "you".
function Combat:nameOf(unit)
    if unit.side == "player" then
        return unit.name == "You" and "you" or unit.name
    end
    return "the " .. unit.name:lower()
end

function Combat:logLine(text)
    self.log[#self.log + 1] = string.format("R%d %s", math.max(1, self.round), text)
end

-- ===========================================================================
-- Dice
-- ===========================================================================

--- Every random draw in a fight goes through here, and only the server's rng
--- is ever touched.
function Combat:rollDie(sides, purpose)
    return self.rng:NextInteger(1, sides)
end

--- A d100, with the Fortune hook attached. Fortune is the only way the player
--- gets to touch a die (§1.2): if it is armed and this roll goes against them,
--- the roll is discarded and replaced, once.
function Combat:rollD100(opts)
    opts = opts or {}
    local roll = self.rng:NextInteger(1, 100)
    if self.fortuneArmed and opts.againstPlayer then
        self.fortuneArmed = false
        local replacement = self.rng:NextInteger(1, 100)
        self:logLine(string.format(
            "Fortune spent: %d becomes %d. You take the second one.",
            roll, replacement
        ))
        return replacement, true
    end
    return roll, false
end

--- Arm Fortune (1 Action? No — it is a per-fight resource, free to use; see
--- §1.2: it rerolls a die just rolled, it is not an action).
function Combat:armFortune()
    if self.player.fortune <= 0 then
        return false, "no_fortune"
    end
    self.player.fortune -= 1
    self.fortuneArmed = true
    self:logLine("You hold your breath and refuse the moment. Fortune is spent.")
    return true
end

-- ===========================================================================
-- Damage maths — one function, used by the pipeline AND by the action buttons,
-- so the number on the button is the number the log will print (§6.2).
-- ===========================================================================

--- Raw damage before anything else (pipeline step 4).
function Combat.rawDamage(attacker, skill)
    if skill.raw then
        return tonumber(skill.raw) or 0
    end
    -- Every one of these is a table lookup on unauthored-shape data, so each is
    -- coerced: a typo in CombatData (`stat = "Strenght"`) must yield 0 damage
    -- from that term, not a string that poisons the arithmetic four steps later
    -- in math.floor. luau-analyze caught exactly this hole; it was right.
    local statValue = 0
    if attacker.attrs and skill.stat then
        statValue = tonumber(attacker.attrs[skill.stat]) or 0
    end
    local power = tonumber(skill.power) or 0
    if skill.powerFrom and attacker.gear then
        power = tonumber(attacker.gear[skill.powerFrom]) or 0
    end
    return statValue * (tonumber(skill.coef) or 1) + power
end

--- The defence a damage type runs into, and its name for the log (step 5).
function Combat.defenceAgainst(target, damageType)
    local dt = CombatData.DamageTypes[damageType] or CombatData.DamageTypes.physical
    if dt.defence == "armour" then
        return target.armour, "ARM"
    end
    local ward = target.ward
    if dt.wardPierce then
        ward = ward * dt.wardPierce -- holy pierces half of Ward (§1.4)
    end
    return ward, "WARD"
end

--- Typed modifier (step 6): holy vs creature kind, arcane vs a target with no Ward.
function Combat.typedModifier(target, damageType)
    local c = Config.Combat
    if damageType == "holy" then
        local kind = CombatData.Kinds[target.kind]
        if kind and kind.living then
            return c.holyVsLiving, "holy vs the living"
        end
        return c.holyVsUndeadOutsider, "holy vs undead"
    end
    if damageType == "arcane" and (target.ward or 0) <= 0 then
        return c.arcaneVsZeroWard, "arcane vs no ward"
    end
    return 1, nil
end

--- Dealt modifiers (step 7, attacker side): Wounded, Shaken, Weakened.
function Combat.dealtMultiplier(unit)
    local mult = 1
    if Combat.isWounded(unit) then
        mult *= Config.Combat.woundedDamageMultiplier
    end
    -- Ramp: an enemy that has been left standing gets angrier (§3.8). Set on
    -- the enemy's turn by Combat:enemyTurn; 1 otherwise.
    if unit.rampMult and unit.rampMult ~= 1 then
        mult *= unit.rampMult
    end
    for _, status in ipairs(unit.statuses) do
        local def = CombatData.Statuses[status.id]
        if def and def.dealtMultiplier then
            mult *= def.dealtMultiplier
        end
    end
    return mult
end

--- Incoming modifiers (step 7, defender side): Brace, Warded.
function Combat.incomingMultiplier(unit, skill)
    local mult = 1
    if unit.braceActive and (skill == nil or not skill.ignoresBrace) then
        mult *= Config.Combat.braceDamageMultiplier
    end
    for _, status in ipairs(unit.statuses) do
        local def = CombatData.Statuses[status.id]
        if def and def.incomingMultiplier then
            mult *= def.incomingMultiplier
        end
    end
    return mult
end

--- Wounded is derived, never applied (§5.5): below 30% health you deal 25% less.
function Combat.isWounded(unit)
    if unit.injured then
        return true
    end
    if not unit.healthMax or unit.healthMax <= 0 then
        return false
    end
    return unit.health < unit.healthMax * Config.Combat.woundedThreshold
end

--- The whole of steps 4–7, with no dice. Returns the numbers and the label of
--- the interesting one, so the panel can show a projection and the log can
--- explain itself.
function Combat.calculateDamage(attacker, target, skill, opts)
    opts = opts or {}
    local damageType = skill.damageType or "physical"
    local raw = Combat.rawDamage(attacker, skill)
    local defence, defenceName = Combat.defenceAgainst(target, damageType)
    local mitigation = 100 / (100 + math.max(0, defence))
    local typed, typedNote = Combat.typedModifier(target, damageType)
    local dealt = Combat.dealtMultiplier(attacker)
    local incoming = Combat.incomingMultiplier(target, skill)
    local critMult = opts.crit and (attacker.critMult or Config.Combat.critDamageBase) or 1
    local damage = math.floor(raw * mitigation * typed * dealt * incoming * critMult)
    return {
        raw = raw,
        defence = defence,
        defenceName = defenceName,
        mitigation = mitigation,
        typed = typed,
        typedNote = typedNote,
        dealt = dealt,
        incoming = incoming,
        crit = opts.crit or false,
        damage = damage,
        damageType = damageType,
    }
end

--- Projected damage for the action list (§6.2). Point value, not a range:
--- §6.2 recommends point values for step 2 and ranges in v1.1.
function Combat.project(attacker, target, skill)
    if not target or target.health <= 0 then
        return nil
    end
    return Combat.calculateDamage(attacker, target, skill).damage
end

-- ===========================================================================
-- Statuses (§3.6)
-- ===========================================================================

function Combat.findStatus(unit, id)
    for index, status in ipairs(unit.statuses) do
        if status.id == id then
            return status, index
        end
    end
    return nil, nil
end

function Combat.hasStatus(unit, id)
    return Combat.findStatus(unit, id) ~= nil
end

--- Apply a status, running the resist check first. Identical statuses stack
--- DURATION, never potency — except Bleed, which stacks potency.
function Combat:applyStatus(target, statusId, source)
    local def = CombatData.Statuses[statusId]
    if not def then
        return false
    end
    if def.derived then
        return false -- derived statuses are never applied
    end

    -- Resist at application only, once, never per tick (§3.5).
    local resistAttr = def.resist
    local resisted = false
    if resistAttr and target.attrs and target.attrs[resistAttr] then
        local resist = Attributes.resist(target.attrs[resistAttr])
        if resist > 0 then
            -- Fortune rerolls a die rolled AGAINST the player, never one rolled
            -- for them. `x and false or true` is always true in Lua, so this
            -- used to arm on the player's own resist roll too and burn the
            -- reroll on a result already in their favour.
            local roll = self:rollD100({ againstPlayer = target.side ~= "player" })
            if roll <= resist then
                resisted = true
                self:logLine(string.format(
                    "%s shrugs off the %s (%s resist %d%%, rolled %d).",
                    self:headline(target), def.name:lower(), resistAttr, resist, roll
                ))
            end
        end
    end
    if resisted then
        return false
    end

    -- Magical debuffs are shortened by Wisdom: duration - floor(WIS/12), min 1.
    local duration = def.duration or 1
    if def.category == "debuff" and target.wis then
        duration = math.max(1, duration - math.floor(target.wis / Config.Combat.debuffDurationWisDivisor))
    end

    local existing = Combat.findStatus(target, statusId)
    if existing then
        if def.potencyStacks then
            existing.potency = (existing.potency or 0) + (def.potency or 0)
            self:logLine(string.format("%s is bleeding worse (%d a round).", self:headline(target), existing.potency))
        else
            existing.duration = existing.duration + duration
            self:logLine(string.format("%s is %s again (%d rounds).", self:headline(target), def.name:lower(), existing.duration))
        end
        return true
    end

    if #target.statuses >= Config.Combat.maxStatuses then
        -- Five chips is the cap (§3.6); the oldest non-control status falls off.
        for index, status in ipairs(target.statuses) do
            local sdef = CombatData.Statuses[status.id]
            if sdef and sdef.category == "dot" then
                table.remove(target.statuses, index)
                break
            end
        end
    end

    target.statuses[#target.statuses + 1] = {
        id = statusId,
        name = def.name,
        category = def.category,
        potency = def.potency,
        duration = duration,
        source = source and source.id or nil,
    }
    self:logLine(string.format("%s is %s.", self:headline(target), def.name:lower()))
    return true
end

function Combat:headline(unit)
    if unit.side == "player" then
        return "You"
    end
    return "The " .. unit.name:lower()
end

--- Damage from a status. DoTs never miss, never crit, ignore Armour (§3.5),
--- and tick at the START of the affected unit's turn.
function Combat:tickStatuses(unit)
    if unit.health <= 0 then
        return
    end
    local expired = {}
    for index, status in ipairs(unit.statuses) do
        local def = CombatData.Statuses[status.id]
        if def and def.category == "dot" then
            local amount = math.floor((status.potency or 0) * Combat.incomingMultiplier(unit, nil))
            if amount < 1 then
                amount = 1
            end
            unit.health -= amount
            local label = status.id == "burn" and "The oil takes" or "The bleeding takes"
            self:logLine(string.format(
                "%s %d. %s is at %d.",
                label, amount, self:headline(unit), math.max(0, unit.health)
            ))
            self:checkDown(unit)
        end
    end
    return expired
end

--- Duration decrements at the END of the affected unit's turn (§3.6).
function Combat:decayStatuses(unit)
    local kept = {}
    for _, status in ipairs(unit.statuses) do
        if status.derived then
            kept[#kept + 1] = status
        elseif Config.Combat.staggerSurvivesOwnTurn
            and status.appliedSerial ~= nil and status.appliedSerial == self.turnSerial then
            -- It arrived during this unit's own turn and has not cost it a
            -- turn yet. It keeps its full duration and decays next round.
            kept[#kept + 1] = status
        else
            status.duration -= 1
            if status.duration > 0 then
                kept[#kept + 1] = status
            elseif status.category == "dot" or status.category == "debuff" then
                local def = CombatData.Statuses[status.id]
                self:logLine(string.format("%s is no longer %s.", self:headline(unit), (def and def.name or status.id):lower()))
            end
        end
    end
    unit.statuses = kept
end

-- ===========================================================================
-- The resolution pipeline (§3.5). Eleven steps, in order, every time.
-- ===========================================================================

--- Resolve one damaging action from `attacker` onto `target`.
--- Returns a table with what happened, for the log and for the caller.
function Combat:attack(attacker, target, skill)
    local steps = {}

    -- 1. TARGETING ---------------------------------------------------------
    if not target or target.health <= 0 or target.fled then
        if skill.targets == "all" then
            return nil -- nothing legal to hit; a multi-target skill simply fizzles
        end
        self:logLine("There is nothing left to hit.")
        return nil
    end
    steps.targeting = true

    -- 2. HIT CHECK ---------------------------------------------------------
    -- d100 vs (100 - (targetDodge - (attackerDEX - 10)))  (§3.5 step 2)
    local missPercent = clamp(target.dodge - ((attacker.dex or 10) - 10), 0, 100)
    local hitRoll = self:rollD100({ againstPlayer = attacker.side == "player" })
    if hitRoll <= missPercent then
        if target.side == "player" then
            self:logLine("You get out of the way.")
        elseif attacker.side == "player" then
            self:logLine(string.format("You miss the %s (it dodges; %d%%).", target.name:lower(), missPercent))
        else
            self:logLine(string.format("The %s misses you.", attacker.name:lower()))
        end
        -- A charge that is broken by a raised guard breaks whether or not it
        -- lands: the guard is up, and the attacker has overcommitted.
        self:chargedBreak(attacker, target, skill)
        return { miss = true, hitRoll = hitRoll, missPercent = missPercent }
    end

    -- 3. CRIT CHECK --------------------------------------------------------
    local critRoll = self:rollD100({ againstPlayer = attacker.side == "enemy" })
    local isCrit = critRoll <= (attacker.crit or 0)

    -- 4-7. RAW, MITIGATION, TYPED, FLAT ------------------------------------
    local calc = Combat.calculateDamage(attacker, target, skill, { crit = isCrit })
    local damage = calc.damage

    -- 8. APPLY -------------------------------------------------------------
    if damage < Config.Combat.minimumHitDamage then
        damage = Config.Combat.minimumHitDamage
    end
    target.health -= damage

    local typeName = (CombatData.DamageTypes[calc.damageType] or {}).name or string.upper(calc.damageType)
    local whoTarget = self:nameOf(target)
    local critNote = isCrit and " CRITICAL" or ""
    if attacker.side == "player" then
        self:logLine(string.format(
            "You hit %s for %d %s%s.", whoTarget, damage, typeName:lower(), critNote
        ))
    else
        self:logLine(string.format(
            "The %s hits you for %d %s%s.", attacker.name:lower(), damage, typeName:lower(), critNote
        ))
    end
    -- The receipt: the arithmetic is reconstructable from the log (§4.3 #2).
    self:logLine(string.format(
        "    %d raw vs %s %d (x%.2f) -> %d%s",
        math.floor(calc.raw), calc.defenceName, math.floor(calc.defence), calc.mitigation, damage,
        calc.incoming < 1 and "  [guarded]" or ""
    ))

    -- 9. DEATH CHECK -------------------------------------------------------
    self:checkDown(target)

    -- 10. ON-HIT STATUS ----------------------------------------------------
    if skill.riders then
        for _, rider in ipairs(skill.riders) do
            if rider.status then
                self:applyStatus(target, rider.status, attacker)
            end
        end
    end

    -- 11. POST-HIT TRIGGERS ------------------------------------------------
    self:chargedBreak(attacker, target, skill)
    return { damage = damage, crit = isCrit, calc = calc }
end

--- Step 11's load-bearing trigger: a Charged attack that runs into a raised
--- guard is broken and the attacker is Staggered, losing their next action.
function Combat:chargedBreak(attacker, target, skill)
    if not skill.charged then
        return false
    end
    if not (target.braceActive and Config.Combat.braceInterruptsCharged) then
        return false
    end
    if not Config.Combat.braceStaggersAttacker then
        return false
    end
    self:logLine(string.format(
        "%s hits your guard and the shock goes up your arm — it does not get a second bite. %s is off balance.",
        "it", self:headline(attacker)
    ))
    self:applyStagger(attacker)
    return true
end

function Combat:applyStagger(unit)
    local existing = Combat.findStatus(unit, "stagger")
    if existing then
        existing.duration = math.max(existing.duration, 1)
        return
    end
    unit.statuses[#unit.statuses + 1] = {
        id = "stagger",
        name = CombatData.Statuses.stagger.name,
        category = "control",
        duration = 1,
        -- The turn it arrived on. A Stagger that lands on the victim's own
        -- turn has not cost it anything YET, so it must survive that turn's
        -- decay to be worth the next one (Config.Combat.staggerSurvivesOwnTurn).
        appliedSerial = self.turnSerial,
    }
end

--- Anything at or below zero health is Downed and out of the fight (§5.4).
function Combat:checkDown(unit)
    if unit.health > 0 then
        return false
    end
    unit.health = 0
    unit.downed = true
    self:logLine(string.format("%s goes down.", self:headline(unit)))
    return true
end

-- ===========================================================================
-- Rounds and turns
-- ===========================================================================

function Combat:livingEnemies()
    local out = {}
    for _, unit in ipairs(self.enemies) do
        if unit.health > 0 and not unit.fled then
            out[#out + 1] = unit
        end
    end
    return out
end

function Combat:enemyById(id)
    for _, unit in ipairs(self.enemies) do
        if unit.id == id then
            return unit
        end
    end
    return nil
end

--- The next enemy in the order that is still standing.
function Combat:defaultTarget()
    local living = self:livingEnemies()
    return living[1]
end

--- Round start: announce every telegraph BEFORE anyone acts (§6.1 #2).
--- `telegraphLead` is per-enemy and decided by initiative: an enemy faster than
--- the player charges for a round (so the player always gets an action while
--- the chip is up); an enemy slower than the player telegraphs and fires in the
--- same round, because the player acts first in that round (§3.10).
function Combat:startRound()
    self.round += 1
    for _, unit in ipairs(self.enemies) do
        if unit.health > 0 and not unit.fled and (unit.telegraphLead or 0) == 0 then
            local step = unit.pattern and unit.pattern[unit.patternIndex]
            if step and step:sub(1, 7) == "CHARGE:" then
                self:announceCharge(unit, step:sub(8), self.round)
                unit.patternIndex = unit.patternIndex % #unit.pattern + 1
            end
        end
    end
end

function Combat:announceCharge(unit, skillId, fireRound)
    local skill = CombatData.Skills[skillId]
    unit.charge = { skill = skillId, fireRound = fireRound }
    self:logLine(string.format("The %s plants its feet. %s, and it is coming.", unit.name:lower(), skill.name:upper()))
end

--- Run the machine: enemies act until it is the player's turn or the fight ends.
function Combat:step()
    local guard = 0
    while self.status == "active" and not self.awaitingPlayer do
        guard += 1
        if guard > 200 then
            self:logLine("The fight grinds to a halt. (guard)")
            self.status = "fled"
            break
        end
        if self:checkEnd() then
            break
        end

        if self.turnIndex >= #self.order then
            self.turnIndex = 0
            self:startRound()
            if self:checkEnd() then
                break
            end
        end
        self.turnIndex += 1
        local unit = self.unitById[self.order[self.turnIndex]]
        if not unit or unit.health <= 0 or unit.fled then
            -- skip
        elseif unit.side == "player" then
            self.turnSerial += 1
            self:beginPlayerTurn(unit)
        else
            self.turnSerial += 1
            self:enemyTurn(unit)
        end
    end
    return self.status
end

--- Victory is "all enemies Downed or fled" (§3.9).
function Combat:checkEnd()
    if self.status ~= "active" then
        return true
    end
    if self.player.health <= 0 then
        self.status = "lost"
        self.lossReason = "downed in the fight"
        return true
    end
    if #self:livingEnemies() == 0 then
        local anyFled = false
        for _, unit in ipairs(self.enemies) do
            if unit.fled then
                anyFled = true
            end
        end
        self.status = "won"
        self.partial = anyFled
        self:logLine(anyFled and "The rest of it breaks apart and goes. The job is half done."
            or "It stops moving.")
        return true
    end
    -- Standoff (§3.10): some fights are about how long you stand, not how many
    -- you put down. If the encounter says so, outlasting the round is a win.
    if self.standoff and self.round > (self.standoff.round or math.huge) then
        self.status = "won"
        self.partial = true
        self.standoffEnded = true
        self:logLine(self.standoff.text
            or "They have had enough of this. The rest of them go, and they do not look back.")
        return true
    end
    if self.round > Config.Combat.maxRounds then
        self:logLine("You have been at this too long. You break off.")
        self.status = "fled"
        self.forcedFlee = true
        return true
    end
    return false
end

--- Turn start for the player: the guard comes down, DoTs tick, mana returns.
function Combat:beginPlayerTurn(unit)
    unit.braceActive = false
    self:tickStatuses(unit)
    if self:checkEnd() then
        return
    end
    if unit.manaRegen and unit.manaMax then
        local regen = unit.manaRegen
        unit.mana = clamp(unit.mana + regen, 0, unit.manaMax)
    end
    if Combat.hasStatus(unit, "stagger") then
        local status = Combat.findStatus(unit, "stagger")
        status.duration -= 1
        if status.duration <= 0 then
            local _, index = Combat.findStatus(unit, "stagger")
            table.remove(unit.statuses, index)
        end
        self:logLine("You are still off balance — you lose this turn to it.")
        self:endPlayerTurn()
        return
    end
    self.awaitingPlayer = true
end

--- Enemy turn: DoT tick, then Stagger check, then the pattern step.
function Combat:enemyTurn(unit)
    self:tickStatuses(unit)
    if unit.health <= 0 then
        return
    end

    -- Ramp (§3.8): a fight the player lets run gets worse. Set here so every
    -- blow this turn — basic, charged or not — carries it.
    if (unit.ramp or 0) > 0 then
        unit.rampMult = 1 + unit.ramp * math.max(0, self.round - 1)
    end

    -- A hurt skirmisher would rather leave (§3.8).
    if unit.flee and unit.health < unit.flee.belowHealth then
        if self:attemptEnemyFlee(unit) then
            return
        end
    end

    if Combat.hasStatus(unit, "stagger") then
        local status = Combat.findStatus(unit, "stagger")
        status.duration -= 1
        if status.duration <= 0 then
            local _, index = Combat.findStatus(unit, "stagger")
            table.remove(unit.statuses, index)
        end
        self:logLine(string.format("The %s is off balance and loses its turn.", unit.name:lower()))
        self:decayStatuses(unit)
        return
    end

    local fired = false
    if unit.charge and unit.charge.fireRound == self.round then
        local skill = CombatData.Skills[unit.charge.skill]
        unit.charge = nil
        if skill then
            self:enemyAttack(unit, skill)
            fired = true
        end
    end

    if not fired then
        local pattern = unit.pattern or {}
        local step = pattern[unit.patternIndex]
        if step then
            if step:sub(1, 7) == "CHARGE:" then
                local skillId = step:sub(8)
                local lead = unit.telegraphLead or 0
                if lead > 0 then
                    -- Faster than the player: spend this turn charging, visibly.
                    self:announceCharge(unit, skillId, self.round + lead)
                    unit.patternIndex = unit.patternIndex % #pattern + 1
                    self:logLine(string.format("The %s is winding up. You have one round.", unit.name:lower()))
                else
                    self:enemyAttack(unit, CombatData.Skills[skillId])
                    unit.patternIndex = unit.patternIndex % #pattern + 1
                end
            else
                local skill = CombatData.Skills[step]
                if skill then
                    if skill.kind == "reposition" then
                        unit.repositioning = true
                        self:logLine(string.format("The %s scatters and is hard to hit.", unit.name:lower()))
                    else
                        self:enemyAttack(unit, skill)
                    end
                end
                unit.patternIndex = unit.patternIndex % #pattern + 1
            end
        end
    end

    self:decayStatuses(unit)
    self:checkEnd()
end

--- An enemy attack, repeated `attacksPerTurn` times (the swarm bites twice).
function Combat:enemyAttack(unit, skill)
    if not skill then
        return
    end
    local times = skill.kind == "attack" and (unit.attacksPerTurn or 1) or 1
    if skill.charged then
        times = 1
    end
    for _ = 1, times do
        if self.player.health <= 0 then
            break
        end
        self:attack(unit, self.player, skill)
    end
end

--- An enemy trying to leave. Contested, and it takes its loot with it (§3.9).
function Combat:attemptEnemyFlee(unit)
    local roll = self:rollD100()
    local dc = (self.player.dex or 10) + 8
    local total = self:rollDie(20, "enemy flee") + unit.dex
    if total >= dc and roll > 15 then
        unit.fled = true
        self:logLine(string.format("The %s breaks apart and goes. It is not worth a tail.", unit.name:lower()))
        self:checkEnd()
        return true
    end
    return false
end

--- End of the player's turn: durations, cooldowns, and hand the turn on.
function Combat:endPlayerTurn()
    self:decayStatuses(self.player)
    for _, unit in ipairs(self.units) do
        local cooldowns = unit.cooldowns
        if cooldowns then
            for id, remaining in pairs(cooldowns) do
                if remaining <= 1 then
                    cooldowns[id] = nil
                    self:logLine(string.format("%s is ready again.", CombatData.Skills[id].name))
                else
                    cooldowns[id] = remaining - 1
                end
            end
        end
    end
    self:step()
end

-- ===========================================================================
-- Player actions (the six of §4.1)
-- ===========================================================================

--- Is this action legal right now? Returns ok, reason.
function Combat:canUse(actionId)
    local unit = self.player
    local skill = CombatData.Skills[actionId]
    if not skill then
        return false, "unknown"
    end
    if skill.kind == "flee" and self.cornered then
        return false, "You are cornered. There is nowhere to go."
    end
    if skill.manaCost and unit.mana < skill.manaCost then
        return false, string.format("not enough mana (%d needed)", skill.manaCost)
    end
    if skill.item and (unit.items[skill.item] or 0) <= 0 then
        return false, "none left"
    end
    local remaining = unit.cooldowns[actionId]
    if remaining then
        return false, string.format("ready in %d round%s", remaining, remaining == 1 and "" or "s")
    end
    return true, nil
end

function Combat:actionCostLabel(actionId)
    local skill = CombatData.Skills[actionId]
    local unit = self.player
    local parts = {}
    if skill.manaCost then
        parts[#parts + 1] = string.format("%d mana (you have %d)", skill.manaCost, math.floor(unit.mana))
    end
    if skill.item then
        parts[#parts + 1] = string.format("%d left", unit.items[skill.item] or 0)
    end
    local remaining = unit.cooldowns[actionId]
    if remaining then
        parts[#parts + 1] = string.format("ready in %d round%s", remaining, remaining == 1 and "" or "s")
    end
    if #parts == 0 then
        return "—"
    end
    return table.concat(parts, ", ")
end

--- The player's move. The only entry point that changes a fight (§5: the
--- client sends intents, the server resolves them).
function Combat:playerAction(actionId, targetId)
    if self.status ~= "active" then
        return false, "over"
    end
    if not self.awaitingPlayer then
        return false, "not_your_turn"
    end
    local skill = CombatData.Skills[actionId]
    if not skill then
        return false, "unknown_action"
    end
    local ok, reason = self:canUse(actionId)
    if not ok then
        return false, reason
    end

    self.awaitingPlayer = false
    self.player.braceActive = false

    if skill.kind == "attack" then
        if skill.cooldown then
            self.player.cooldowns[actionId] = skill.cooldown + 1
        end
        if skill.manaCost then
            self.player.mana -= skill.manaCost
        end
        if skill.targets == "all" then
            local targets = self:livingEnemies()
            for _, unit in ipairs(targets) do
                self:attack(self.player, unit, skill)
                if self.player.health <= 0 then
                    break
                end
            end
        else
            local target = (targetId and self:enemyById(targetId)) or self:defaultTarget()
            if target and target.health > 0 then
                self:attack(self.player, target, skill)
            end
        end
    elseif skill.kind == "brace" then
        self.player.braceActive = true
        local bonus = (self.player.manaRegen or 0) * Config.Combat.braceManaMultiplier
        self.player.mana = clamp(self.player.mana + bonus, 0, self.player.manaMax)
        self:logLine(string.format(
            "You set your feet. 40%% damage until your next turn, and %+d mana.", bonus
        ))
    elseif skill.kind == "item" then
        if skill.item then
            self.player.items[skill.item] = (self.player.items[skill.item] or 0) - 1
        end
        local target = (targetId and self:enemyById(targetId)) or self:defaultTarget()
        if target then
            self:logLine(string.format("You throw the %s at the %s.", skill.name:lower(), target.name:lower()))
            if skill.riders then
                for _, rider in ipairs(skill.riders) do
                    self:applyStatus(target, rider.status, self.player)
                end
            end
        end
    elseif skill.kind == "flee" then
        local living = self:livingEnemies()
        local dc = 0
        for _, unit in ipairs(living) do
            dc = math.max(dc, unit.dex + 8)
        end
        local roll = self:rollDie(20, "flee")
        local total = roll + (self.player.dex or 10)
        self:logLine(string.format("You break for the door — d20 %d + %d = %d vs %d.", roll, self.player.dex or 10, total, dc))
        if total >= dc then
            self.status = "fled"
            self:logLine("You are out, and you are alive, and the job is not done.")
            return true
        end
        self:logLine("You do not make it. They get a free swing at your back.")
        for _, unit in ipairs(living) do
            local skillBite = CombatData.Skills[(unit.pattern and unit.pattern[1]) or "rat_bite"] or CombatData.Skills.rat_bite
            if skillBite and skillBite.kind == "attack" then
                self:attack(unit, self.player, skillBite)
            end
        end
    end

    self:checkEnd()
    if self.status ~= "active" then
        return true
    end
    self:endPlayerTurn()
    return true
end

-- ===========================================================================
-- The view model — everything §6.2 says must be on the screen, and nothing else
-- ===========================================================================

function Combat:statusChips(unit)
    local chips = {}
    for _, id in ipairs(CombatData.StatusOrder) do
        if id == "wounded" then
            if Combat.isWounded(unit) then
                chips[#chips + 1] = { id = "wounded", label = "WOUNDED (−25% dealt)", order = 3 }
            end
        else
            local status = Combat.findStatus(unit, id)
            if status then
                local def = CombatData.Statuses[id]
                local label = def.name
                if def.category == "dot" then
                    label = string.format("%s %d (%d rd%s)", def.name, status.potency, status.duration, status.duration == 1 and "" or "s")
                elseif def.category == "control" then
                    label = def.name
                else
                    label = string.format("%s (%d rd%s)", def.name, status.duration, status.duration == 1 and "" or "s")
                end
                chips[#chips + 1] = { id = id, label = label, order = (id == "stagger") and 1 or 4 }
            end
        end
    end
    return chips
end

--- What a blow would actually cost YOU, unbraced and braced (§6.1 law: the
--- player must be able to tell whether the next hit hurts more BEFORE pressing
--- anything). Read-only — the braced case is probed through a stand-in that
--- inherits every field from the live unit, so no combat state is touched.
function Combat:probeIncoming(attacker, skill)
    if not skill then
        return nil
    end
    local braced = setmetatable({ braceActive = true }, { __index = self.player })
    local plain = Combat.calculateDamage(attacker, self.player, skill).damage
    local guarded = Combat.calculateDamage(attacker, braced, skill).damage
    return {
        damageType = skill.damageType or "physical",
        youTake = plain,
        youTakeBraced = guarded,
        braceSaves = math.max(0, plain - guarded),
    }
end

--- One enemy, as the panel needs it (§6.2).
function Combat:enemyView(unit)
    local telegraph = nil
    if unit.charge then
        local skill = CombatData.Skills[unit.charge.skill]
        local firesThisRound = unit.charge.fireRound == self.round
        telegraph = {
            label = string.format("CHARGING: %s", string.upper(skill.name)),
            detail = firesThisRound and "next action" or "next round",
            damageType = skill.damageType,
            raw = skill.raw,
            firesThisRound = firesThisRound,
            incoming = self:probeIncoming(unit, skill),
        }
    end
    return {
        id = unit.id,
        name = unit.name,
        archetype = unit.label,
        kind = unit.kind,
        tier = unit.tier,
        health = math.max(0, unit.health),
        healthMax = unit.healthMax,
        healthFraction = clamp(unit.health / unit.healthMax, 0, 1),
        armour = math.floor(unit.armour),
        ward = math.floor(unit.ward),
        dodge = unit.dodge,
        threat = unit.threat,
        downed = unit.health <= 0,
        fled = unit.fled or false,
        deals = string.format("Deals %s.", string.upper(unit.damageType or "physical")),
        note = unit.note,
        telegraph = telegraph,
        statuses = self:statusChips(unit),
    }
end

--- One action button (numbered, with the numbers pre-computed — §6.2).
function Combat:actionView(index, actionId)
    local skill = CombatData.Skills[actionId]
    local ok, reason = self:canUse(actionId)
    local targets = {}
    if skill.kind == "attack" or skill.kind == "item" then
        local list = skill.targets == "all" and self:livingEnemies()
            or { (self.selectedTarget and self:enemyById(self.selectedTarget)) or self:defaultTarget() }
        for _, unit in ipairs(list) do
            if unit and unit.health > 0 then
                local projected = nil
                if skill.kind == "attack" then
                    projected = Combat.project(self.player, unit, skill)
                end
                targets[#targets + 1] = {
                    id = unit.id,
                    name = unit.name,
                    projected = projected,
                    armour = math.floor(unit.armour),
                    ward = math.floor(unit.ward),
                }
            end
        end
    end

    local detail = ""
    if skill.kind == "attack" then
        local projected = {}
        for _, target in ipairs(targets) do
            if target.projected then
                projected[#projected + 1] = string.format("%s %d", target.name, target.projected)
            end
        end
        detail = string.format("%s — %s", skill.description or "",
            #projected > 0 and table.concat(projected, " | ") or "no legal target")
    elseif skill.kind == "brace" then
        detail = string.format("%d%% damage taken, %+d mana, staggers a Charged attack",
            math.floor(Config.Combat.braceDamageMultiplier * 100), (self.player.manaRegen or 0) * 2)
    elseif skill.kind == "flee" then
        local dc = 0
        for _, unit in ipairs(self:livingEnemies()) do
            dc = math.max(dc, unit.dex + 8)
        end
        detail = string.format("d20 + %d vs %d — the contract fails if you make it", self.player.dex or 10, dc)
    end

    return {
        id = actionId,
        key = tostring(index),
        label = skill.name,
        kind = skill.kind,
        detail = detail,
        cost = self:actionCostLabel(actionId),
        enabled = ok and self.awaitingPlayer,
        reason = (not ok) and reason or nil,
        targets = targets,
    }
end

--- The whole combat screen, as data (§6.2).
function Combat:view()
    local player = self.player
    local actions = {}
    for index, actionId in ipairs(player.actions) do
        actions[#actions + 1] = self:actionView(index, actionId)
    end

    local enemies = {}
    for _, unit in ipairs(self.enemies) do
        enemies[#enemies + 1] = self:enemyView(unit)
    end

    local recent = {}
    local from = math.max(1, #self.log - 7)
    for index = from, #self.log do
        recent[#recent + 1] = self.log[index]
    end

    local orderNames = {}
    for _, id in ipairs(self.order) do
        local unit = self.unitById[id]
        if unit then
            orderNames[#orderNames + 1] = unit.side == "player" and "You" or unit.name
        end
    end

    return {
        title = self.title,
        round = self.round,
        roundLabel = string.format("Round %d", self.round),
        status = self.status,
        awaitingAction = self.awaitingPlayer and self.status == "active",
        stakes = self.stakes,
        warning = self.warning,
        cornered = self.cornered,
        order = table.concat(orderNames, " > "),
        partial = self.partial or false,
        forcedFlee = self.forcedFlee or false,
        player = {
            name = player.name,
            level = player.level,
            vocation = player.vocation,
            health = math.max(0, player.health),
            healthMax = player.healthMax,
            healthFraction = clamp(player.health / player.healthMax, 0, 1),
            mana = math.floor(player.mana),
            manaMax = player.manaMax,
            manaRegen = player.manaRegen,
            armour = math.floor(player.armour),
            ward = math.floor(player.ward),
            crit = player.crit,
            critMult = player.critMult,
            dodge = player.dodge,
            fortune = player.fortune,
            fortuneArmed = self.fortuneArmed,
            wounded = Combat.isWounded(player),
            statuses = self:statusChips(player),
            threat = player.threat,
            weapon = player.gear and player.gear.weaponName or nil,
        },
        enemies = enemies,
        actions = actions,
        log = recent,
        fullLog = self.log,
    }
end

return Combat
