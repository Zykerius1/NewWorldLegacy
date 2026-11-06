--[[
    Config — every tunable number in the game, in one file.

    Rule of thumb: if a designer might want to change it, it lives here.
    If it is a mechanic, it lives in Attributes / Events / GameState.

    Numbers marked TUNING are first-pass guesses. They are dials, not laws.
    Design references:
      - stat-model-v1.md §1.2  (attribute formulas, derived values)
      - design-brief-v0.md §1  (year tick, death), §4 (events)
]]

local Config = {}

-- ===========================================================================
-- TUNING — first-pass balance block. Everything in this section is a dial.
-- ===========================================================================

Config.Remotes = {
    action = "NWL_Action", -- client -> server: an intent only
    update = "NWL_Update", -- server -> client: the whole view model
}

-- Character creation --------------------------------------------------------
Config.Birth = {
    attrBase = 7, -- TUNING: each attribute rolls attrBase + d(attrDie)  -> 8..11
    attrDie = 4,
    rerolls = 1, -- TUNING: one mercy re-roll per life (design brief §2.1, option C)
    maxNameLength = 18,
}

Config.AttributeMin = 4
Config.AttributeMax = 40

-- Starting purse by family circumstance (rolled at birth, see GameState).
-- TUNING.
Config.Birth.WealthBands = {
    { flag = "family_poor", chance = 0.35, coin = 5, label = "poor" },
    { flag = "family_modest", chance = 0.50, coin = 25, label = "modest" },
    { flag = "family_comfortable", chance = 0.15, coin = 80, label = "comfortable" },
}

-- The eight attributes. ShortName is what the sheet and delta chips show.
Config.Attributes = {
    { key = "STR", name = "Strength", blurb = "Melee damage, labour, intimidation." },
    { key = "VIT", name = "Vitality", blurb = "Health pool and physical defence." },
    { key = "INT", name = "Intelligence", blurb = "Arcane damage, lore, learning." },
    { key = "WIS", name = "Wisdom", blurb = "Mana, magic defence, judgement." },
    { key = "PIE", name = "Piety", blurb = "Holy damage, healing, the Karma ledger." },
    { key = "DEX", name = "Dexterity", blurb = "Dodge, accuracy, initiative." },
    { key = "LUK", name = "Luck", blurb = "Fortune, fate, loot." },
    { key = "CHA", name = "Charisma", blurb = "Persuasion, prices, morale." },
}

-- Ordered list of the four-letter keys, built from the table above.
Config.AttributeOrder = {}
for _, attr in ipairs(Config.Attributes) do
    table.insert(Config.AttributeOrder, attr.key)
end

-- ===========================================================================
-- TUNING — Races. First-pass numbers, exactly as specified by the owner.
-- Applied as a percentage of the FINAL rolled attribute value, rounded down,
-- with a floor of +1 (see Attributes.applyRace).
-- ===========================================================================

Config.RaceOrder = { "human", "dwarf", "elf" }

Config.Races = {
    human = {
        id = "human",
        name = "Human",
        birthWeight = 54,
        -- TUNING: no flat attribute bonus. +25% experience from all sources.
        -- A growth-rate advantage, not a flat one: weakest sheet at fourteen,
        -- widest at sixty, because it compounds.
        attrBonus = {},
        expMultiplier = 1.25,
        healthMultiplier = 1.0,
        blurb = "The weakest sheet at fourteen and the widest at sixty. "
            .. "Everything a human learns, they learn faster.",
    },
    dwarf = {
        id = "dwarf",
        name = "Dwarf",
        birthWeight = 12,
        -- TUNING: +20% STR and VIT, and +10% max health to balance having two
        -- attributes to the elf's three.
        attrBonus = { STR = 0.20, VIT = 0.20 },
        expMultiplier = 1.0,
        healthMultiplier = 1.10,
        blurb = "Strong, hard to kill, and slow to trust. Two attributes instead of three, "
            .. "and a deeper health pool to make up the difference.",
    },
    elf = {
        id = "elf",
        name = "Elf",
        birthWeight = 10,
        -- TUNING: +20% INT, WIS and PIE.
        attrBonus = { INT = 0.20, WIS = 0.20, PIE = 0.20 },
        expMultiplier = 1.0,
        healthMultiplier = 1.0,
        blurb = "Three attributes instead of two, and none of them make you harder to hit.",
    },
}

-- TUNING: a percentage bonus always gives at least this much.
Config.RaceBonusMinimum = 1

-- ===========================================================================
-- TUNING — Derived values. Formulas from stat-model-v1.md §1.2.
-- Nothing here is used by combat yet (step 2), but the layer exists now so
-- step 2 slots in without a rewrite. These are formulas, not dials: changing
-- them changes what an attribute *means*.
-- ===========================================================================

Config.Derived = {
    -- HealthMax = 40 + VIT * 6, then x race health multiplier
    healthMaxBase = 40,
    healthMaxPerVit = 6,
    -- ManaMax = 10 + WIS * 4 + INT
    manaMaxBase = 10,
    manaMaxPerWis = 4,
    manaMaxPerInt = 1,
    -- ManaRegen = 1 + floor(WIS / 2) per combat round
    manaRegenBase = 1,
    manaRegenPerWis = 2,
    -- Armour = gearArmour + floor(VIT / 2); Ward = gearWard + WIS
    armourPerVit = 0.5,
    wardPerWis = 1,
    -- Dodge% = 3 + DEX * 0.6, capped 35
    dodgeBase = 3,
    dodgePerDex = 0.6,
    dodgeCap = 35,
    -- CritRate% = 2 + DEX * 0.8, capped 40
    critBase = 2,
    critPerDex = 0.8,
    critCap = 40,
    -- Damage formulas (step 2)
    physicalRawStrMult = 1.5,
    arcaneRawIntMult = 2.0,
    holyRawPieMult = 1.8,
    -- Carry = STR * 5 kg
    carryPerStr = 5,
    -- FortuneUses = 1 + floor(LUK / 15)
    fortuneBase = 1,
    fortunePerLuk = 15,
    -- Physical/magical status resist% = stat * 1.5, capped 60
    resistPerPoint = 1.5,
    resistCap = 60,
    -- Karma gain/loss is multiplied by 1 + PIE/20
    karmaPietyDivisor = 20,
    -- Rest between fights restores 25% + VIT * 2% of max health (per year)
    restBaseFraction = 0.25,
    restVitFraction = 0.02,
}

-- ===========================================================================
-- TUNING — Level curve. Levels come from experience; experience comes from
-- events and from living. The native ceiling is deliberately real (brief §6.2)
-- and deliberately silent: nothing in the UI announces it.
-- ===========================================================================

Config.Level = {
    baseExp = 100, -- exp needed for level 2
    growth = 1.35, -- each level costs this much more
    cap = 35, -- native ceiling
}

-- ===========================================================================
-- TUNING — The year tick. What happens silently before the event card.
-- ===========================================================================

Config.Year = {
    -- Income minus upkeep by age band. Children earn nothing; adults drift.
    income = {
        { maxAge = 12, income = 0, upkeep = 0 },
        { maxAge = 17, income = 4, upkeep = 0 },
        { maxAge = 54, income = 28, upkeep = 14 },
        { maxAge = 999, income = 10, upkeep = 6 },
    },
    -- Experience for surviving a year, by age band (before race multiplier).
    exp = {
        { maxAge = 17, amount = 20 },
        { maxAge = 40, amount = 30 },
        { maxAge = 999, amount = 10 },
    },
    notorietyDecay = 1, -- per quiet year, from adulthood
    notorietyDecayFrom = 18,
    healthRegenBefore40 = 4, -- passive recovery while young
    healthDeclineFrom = 55, -- passive health loss per year past this age
    healthDeclinePerYear = 2,
    manaRestorePerYear = 0.5, -- fraction of ManaMax restored each year
}

-- Attribute drift: growth through the working years, decay where the design
-- says decay belongs (stat-model §1.2). chance is per year.
-- TUNING.
Config.Growth = {
    STR = { growFrom = 13, growTo = 45, chance = 0.30, decayFrom = 55, decayEvery = 2 },
    VIT = { growFrom = 13, growTo = 45, chance = 0.25, decayFrom = 45, decayEvery = 1 },
    INT = { growFrom = 8, growTo = 60, chance = 0.12 }, -- never decays
    WIS = { growFrom = 8, growTo = 200, chance = 0.15 }, -- grows in old age
    PIE = { growFrom = 8, growTo = 200, chance = 0.05 }, -- only through events; drift is rare
    DEX = { growFrom = 10, growTo = 40, chance = 0.25, decayFrom = 60, decayEvery = 2 },
    LUK = { growFrom = 200, chance = 0 }, -- never grows, never decays
    CHA = { growFrom = 13, growTo = 200, chance = 0.18 }, -- still climbing at 60
}

-- ===========================================================================
-- TUNING — Death. Health <= 0 ends the run; so does being old. There is no
-- resurrection in step 1 (the brief's soft death is a step-2 concern).
-- ===========================================================================

Config.Death = {
    lifespanBase = 74,
    lifespanPerVit = 0.6, -- extra years per point of VIT above 10
    lifespanPerLuck = 0.2,
    naturalDeathGrace = 0, -- no natural-death chance at or below lifespan
    naturalDeathRamp = 0.15, -- chance per year beyond lifespan = yearsPast * ramp
    naturalDeathMaxChance = 0.9,
    hardAgeLimit = 110,
}

-- ===========================================================================
-- Names. Deliberately plain and setting-appropriate; the player may type
-- their own (server-sanitised).
-- ===========================================================================

Config.Names = {
    human = {
        "Corin", "Maud", "Tobiah", "Ellis", "Renn", "Hesta", "Bram", "Sela",
        "Perrin", "Adda", "Osric", "Linnet", "Hale", "Mira", "Dunstan", "Wren",
    },
    dwarf = {
        "Borin", "Halda", "Durn", "Greta", "Korrig", "Thessa", "Branka", "Odrum",
        "Ilsa", "Torvald", "Marn", "Hekka",
    },
    elf = {
        "Silwen", "Aerith", "Nael", "Ithara", "Vaehl", "Loriel", "Sera", "Thalen",
        "Cael", "Miriel", "Onwe", "Elluin",
    },
}

-- ===========================================================================
-- TUNING — Event density. Two tiers of content sit behind the draw:
--   * the authored events (Events.All) are the beats of a life. They fire
--     whenever they are eligible, once per run, and are never recycled.
--   * the repeatable tier (Events.Repeatable) is ordinary life — work, weather,
--     illness, money, a neighbour, a debt. Each entry carries a `cooldown` in
--     years, so it can come round again without reading as recycled.
-- `repeatChance` is the per-year odds that a year the authored tier did not
-- claim still offers a repeatable card. Every other year is a quiet year
-- (Config.QuietYearLines) — never a blank one. Bands are read top-down; the
-- first band whose maxAge the character has not passed wins.
-- The target percentages are the ones the headless harness measures.
-- ===========================================================================
Config.EventDraw = {
    repeatChance = {
        { maxAge = 2, chance = 0.00 }, -- infancy is not a card
        { maxAge = 12, chance = 0.34 }, -- target 50-60%: a quiet childhood is intended
        { maxAge = 17, chance = 0.92 }, -- target 80-100%
        { maxAge = 55, chance = 0.58 }, -- target 60-70%
        { maxAge = 999, chance = 0.43 }, -- target 40-50%
    },
    cooldownDefault = 4, -- years before the same generic may come round again
    -- Floor rule: if every generic for this age is still cooling, serve the one
    -- seen longest ago rather than leave an adult year with nothing.
    respectCooldownAsFloor = true,
}
-- Quiet years: the world is mostly uneventful and that is the point
-- (design brief §4.2). One line, no choice.
Config.QuietYearLines = {
    "Nothing happens. The season turns, the road dries, and no one asks anything of you.",
    "A quiet year. You do the work in front of you and it is enough.",
    "Nothing worth writing down. That is most years.",
    "You are mostly indoors. The weather is the only news.",
    "The year passes the way a fence gets mended: a little at a time, and then it is done.",
    "Nothing happens. You will not remember this year, which is a kind of good fortune.",
    "An uneventful year. The prices are steady and nobody is angry with you.",
    "Nothing happens, and nothing happening is not nothing. It is a year you got to keep.",
}

-- The birth paragraph — the character-creation screen wearing a story's
-- clothes (design brief §4.5, E01). Shown while the player picks a race.
Config.BirthParagraph = "You are born in a room with a low ceiling, in the season when the "
    .. "roads are bad. The midwife is experienced and tired and does not say much. Your mother "
    .. "does not die. This is not guaranteed and everyone in the room knows it, so for a while "
    .. "the only sound is the fire.\n\nOutside, someone is arguing about the price of a goat. "
    .. "The argument will outlast three of the people currently in this room."

Config.BirthInstruction = "You did not choose this. Choose what you can."

-- ===========================================================================
-- TUNING — Combat (stat-model-v1.md §3, §4, §5). Every number here comes from
-- the design document; the FLAGS are the four owner-decided defaults, each
-- isolated so it can be flipped without a rewrite.
-- ===========================================================================

Config.Combat = {
    -- Action economy (§3.3)
    actionsPerTurn = 1,
    reactionsPerRound = 1, -- Riposte/Brace-and-hold; step 2 has no reaction skills
    freeInspect = true, -- inspecting never costs anything (§6.1)

    -- Brace (§3.3). The load-bearing action. Flipping `braceInterruptsCharged`
    -- to false turns Brace into a wasted turn and the fight into a dice roll.
    braceDamageMultiplier = 0.40,
    braceManaMultiplier = 2, -- plus ManaRegen × 2
    braceInterruptsCharged = true,
    braceStaggersAttacker = true,
    -- A Stagger that lands on the victim's OWN turn has not cost it anything
    -- yet, so it must survive that turn's decay or Brace's whole payoff — "the
    -- attacker loses their next action" — silently evaporates and Brace becomes
    -- a trap. This is the flag that makes the guard worth a turn.
    staggerSurvivesOwnTurn = true,

    -- Crit (§2.1). Crit RATE is on DEX; crit DAMAGE lives on gear and is a
    -- placeholder here until step 2.5 (decision 1 of the four).
    critDamageBase = 1.5,
    critDamageFromGearIsStub = true,

    -- Resolution (§3.5)
    holyVsLiving = 0.75,
    holyVsUndeadOutsider = 1.5,
    arcaneVsZeroWard = 1.25,
    woundedThreshold = 0.30, -- below this fraction of max health (§5.5)
    woundedDamageMultiplier = 0.75,
    minimumHitDamage = 1, -- a hit never does less than 1
    initiativeDie = 10,
    maxRounds = 30, -- a safety net, not a balance lever: fights target 4–9 rounds
    maxStatuses = 5, -- chips are capped (§3.6)
    debuffDurationWisDivisor = 12, -- duration − floor(WIS/12), min 1

    -- One health pool (§5.2, decision 3): fight damage is life damage.
    sharedHealthPool = true,

    -- The three loss severities (§5.4). `dead` is NEVER attached to a winnable
    -- fight (decision 4) — enforce() below warns loudly if an encounter tries.
    Severities = {
        defeat = "defeat",
        downed = "downed",
        dead = "dead",
    },
    forbidDeadOnWinnableFight = true,

    -- Defeat: robbed, patched up, and marked (§5.4).
    DefeatCost = {
        coinLossFraction = 0.5, -- they take half of what you carry
        healthFloor = 1,
        injuredYears = 2, -- Wounded for two years
        mark = "beaten_in_the_granary",
    },
    -- Downed: the death window, and a debt to whoever paid (§5.4).
    DownedCost = {
        healthFraction = 0.25, -- patched to 25% of max
        levelsLost = 1,
        debtYears = 8, -- the chain event lands 5–20 years later; TUNING
        debtText = "Someone paid to bring you back, and they have not forgotten it.",
    },
    -- Victory (§4.2: fixed coin + a fixed item; the loot TABLE is step 2.5).
    VictoryReward = {
        coin = 30,
        exp = 60,
        item = "rat tail",
        repFlag = "did_the_granary_job",
    },
    -- Flee: the contract fails. Reputation is a stub flag for now.
    FleeCost = {
        exp = 0,
        coin = 0,
        flag = "failed_the_granary_contract",
    },

    -- Wounded from a previous fight, or from being torn up in one, is a status
    -- the whole life sim can see (§5.5).
    lowHealthWarning = "You are not in a condition for this.",

    -- Yearly recovery (§5.5): 25% + VIT × 2% of max, if fed and not Wounded.
    -- This REPLACES the flat step-1 regen when the flag is on. It is generous
    -- on purpose: §5.2 says combat damage is life damage, so the recovery rate
    -- is what makes a combat build playable at all.
    useFractionalRecovery = true,
}

-- Vocations, used by the death screen's "what they were" line.
Config.Vocations = {
    adventurer = "adventurer",
    stayed_home = "farmer",
}

return Config
