--[[
	CombatData — the DATA half of combat: skills, statuses, enemy archetypes and
	encounters. Pure tables, no logic (that is Combat.lua).

	Everything here is authored from stat-model-v1.md §3.4, §3.6, §3.7, §3.8 and
	§3.10. Where a number comes from the worked example in §3.10 it is marked
	"§3.10" so the harness fidelity check has something to compare against.

	Skills are data, not code (§3.7): { id, name, damageType, coef, power, cost,
	cooldown, targets, riders }. An enemy skill may carry `raw` instead of a
	coefficient — an enemy stat block gives its attack as a flat raw number, which
	is what the §3.10 tables print.

	GEAR IS STUBBED (stat-model §4.2): the player's weapon power, armour and ward
	are hardcoded constants below and live in exactly one place, so step 2.5 can
	replace the constant with a lookup without touching the engine.
]]

local CombatData = {}

-- ===========================================================================
-- Damage types (§1.4). Two defences, three types, and that mismatch is the design.
-- ===========================================================================

CombatData.DamageTypes = {
	physical = { id = "physical", name = "PHYSICAL", defence = "armour" },
	arcane = { id = "arcane", name = "ARCANE", defence = "ward" },
	holy = { id = "holy", name = "HOLY", defence = "ward", wardPierce = 0.5 },
}

-- Creature kinds. Holy is typed against these (§1.4): ×1.5 undead/outsider,
-- ×0.75 living. It is one word on the enemy panel, not a third bar.
CombatData.Kinds = {
	BEAST = { id = "BEAST", living = true },
	HUMAN = { id = "HUMAN", living = true },
	UNDEAD = { id = "UNDEAD", living = false },
	OUTSIDER = { id = "OUTSIDER", living = false },
}

-- ===========================================================================
-- STATUS EFFECTS (§3.6)
--   category: dot | control | debuff | buff
--   resist  : which attribute resists it at application — VIT physical, WIS magical
--   duration decrements at the END of the affected unit's turn
--   identical statuses stack DURATION, never potency, except Bleed (potencyStacks)
-- ===========================================================================

CombatData.Statuses = {
	burn = {
		id = "burn",
		name = "BURNING",
		category = "dot",
		damageType = "arcane",
		resist = "WIS",
		potency = 6, -- §3.10: oil flask Burn 6/3
		duration = 3,
		-- tick line: "The oil takes 6. The rat is at 57."
	},
	bleed = {
		id = "bleed",
		name = "BLEEDING",
		category = "dot",
		damageType = "physical",
		resist = "VIT",
		potency = 4,
		duration = 3,
		potencyStacks = true, -- the physical build's payoff (§3.6)
	},
	stagger = {
		id = "stagger",
		name = "STAGGERED",
		category = "control",
		resist = "WIS",
		skipAction = true,
		duration = 1,
	},
	shaken = {
		id = "shaken",
		name = "SHAKEN",
		category = "debuff",
		resist = "VIT",
		dealtMultiplier = 0.75, -- −25% damage dealt (§3.6)
		duration = 2,
	},
	-- Wounded is DERIVED, never applied as a rider: it is "below 30% health"
	-- (stat-model §5.5) and it is recomputed every time damage lands. Row kept
	-- here so the UI and the engine agree on the name and the multiplier.
	wounded = {
		id = "wounded",
		name = "WOUNDED",
		category = "debuff",
		derived = "lowHealth",
		dealtMultiplier = 0.75,
		duration = 0,
	},
}

-- Chips in the panel read in this order: telegraph-adjacent first, then DoTs.
CombatData.StatusOrder = { "stagger", "shaken", "wounded", "burn", "bleed" }

-- ===========================================================================
-- SKILLS (§3.7). The twelve the design lists, minus the ones step 2 does not
-- need — step 2 builds the six player actions of §4.1 plus the enemy attacks
-- the three archetypes actually use. Holy skills are authored but unplaced:
-- Wren has PIE 4 and correctly has no holy action (§4.2).
-- ===========================================================================

CombatData.Skills = {
	-- ---- player: the six actions of §4.1 ----------------------------------
	attack = {
		id = "attack",
		name = "Attack",
		kind = "attack",
		damageType = "physical",
		stat = "STR",
		coef = 1.0,
		powerFrom = "weaponPower",
		targets = "one",
		cost = "free", -- never on cooldown, always a legal move (§3.3)
		description = "The floor of the system. Always available, never the best answer.",
	},
	cleave = {
		id = "cleave",
		name = "Cleave",
		kind = "attack",
		damageType = "physical",
		stat = "STR",
		coef = 0.8, -- §3.7: 80% to all enemies
		powerFrom = "weaponPower",
		targets = "all",
		cooldown = 3,
		description = "A wide sweep. Hits every enemy, at a discount.",
	},
	wild_swing = {
		id = "wild_swing",
		name = "Wild Swing",
		kind = "attack",
		damageType = "physical",
		stat = "STR",
		coef = 1.4, -- §3.7/§4.1: the one physical skill that costs mana
		powerFrom = "weaponPower",
		targets = "one",
		manaCost = 30,
		description = "Everything you have behind it. Costs mana, not patience.",
	},
	brace = {
		id = "brace",
		name = "Brace",
		kind = "brace",
		targets = "self",
		description = "Take 40% damage until your next turn, regain double mana, "
			.. "and break a Charged attack — the attacker loses their next action.",
	},
	oil_flask = {
		id = "oil_flask",
		name = "Oil Flask",
		kind = "item",
		item = "oil_flask",
		targets = "one",
		riders = { { status = "burn" } },
		description = "Throw the flask. Applies Burn (6 a round for 3 rounds), resisted by Wisdom.",
	},
	flee = {
		id = "flee",
		name = "Flee",
		kind = "flee",
		targets = "self",
		description = "Break off. The contract fails and you keep the rest of your life.",
	},

	-- ---- enemy skills: the three archetypes (§3.8) ------------------------
	rat_bite = {
		id = "rat_bite",
		name = "Bite",
		kind = "attack",
		damageType = "physical",
		raw = 20, -- TUNING: was 18 (§3.10)
		targets = "one",
	},
	gnaw = {
		id = "gnaw",
		name = "Gnaw",
		kind = "attack",
		damageType = "physical",
		raw = 56, -- TUNING: was 30. The telegraphed blow; unbraced it is half your life.
		charged = true,
		targets = "one",
	},
	swarm_bite = {
		id = "swarm_bite",
		name = "Bite",
		kind = "attack",
		damageType = "physical",
		raw = 6, -- TUNING: was 7. Two attacks, 6 raw each.
		targets = "one",
	},
	reposition = {
		id = "reposition",
		name = "Reposition",
		kind = "reposition",
		targets = "self",
		riders = { { status = "repositioned" } },
	},
	hex = {
		id = "hex",
		name = "Hex",
		kind = "attack",
		damageType = "arcane",
		raw = 8,
		targets = "one",
		riders = { { status = "shaken" } },
	},
	bolt = {
		id = "bolt",
		name = "Bolt",
		kind = "attack",
		damageType = "arcane",
		raw = 16,
		targets = "one",
	},
	soul_nuke = {
		id = "soul_nuke",
		name = "Soul Nuke",
		kind = "attack",
		damageType = "arcane",
		raw = 32,
		charged = true,
		targets = "one",
	},

	-- ---- holy, authored and deliberately unplaced in step 2 (§4.2) --------
	smite = {
		id = "smite",
		name = "Smite",
		kind = "attack",
		damageType = "holy",
		stat = "PIE",
		coef = 1.2,
		powerFrom = "symbolPower",
		manaCost = 10,
		targets = "one",
	},
}

-- Statuses referenced by skills but kept out of the §3.6 five: repositioning is
-- the skirmisher's bonus dodge, not a real status the player should track.
CombatData.Statuses.repositioned = {
	id = "repositioned",
	name = "HARD TO HIT",
	category = "buff",
	dodgeBonus = 12,
	duration = 1,
}

-- ===========================================================================
-- ENEMY ARCHETYPES (§3.8). Data templates: stat block, behaviour, telegraph.
-- APEX is deliberately absent — never a stat block (§3.8).
--
-- An enemy stat block prints its defence as two flat numbers, so that is what
-- the data carries. DEX/WIS still drive the checks that use them (initiative,
-- resist, the attacker's accuracy term), so the sheet is not decorative.
-- ===========================================================================

CombatData.Archetypes = {
	-- A — BRUISER: high health, high Armour, low Ward, slow, one big telegraphed
	-- attack. Pattern: attack, attack, CHARGE(telegraph) -> HEAVY.  (§3.10)
	bruiser_barrow_rat = {
		id = "bruiser_barrow_rat",
		label = "BRUISER",
		name = "Barrow Rat",
		kind = "BEAST",
		tier = 1,
		health = 48, -- TUNING: was 80 (§3.10)
		armour = 12, -- TUNING: was 20 (§3.10)
		ward = 5, -- §3.10
		dodge = 7, -- §3.10
		crit = 7, -- §3.10
		attrs = { STR = 12, VIT = 12, DEX = 6, WIS = 6, INT = 2, PIE = 2, LUK = 4, CHA = 2 },
		attacksPerTurn = 1,
		damageType = "physical",
		note = "Slow, and it means it. Watch for the plant of its feet.",
		pattern = { "rat_bite", "rat_bite", "CHARGE:gnaw" },
		-- TUNING: every round it stays standing it hits 12% harder. Leaving the
		-- big one up is a choice with a price, which is what stops "stand still
		-- and guard" from being the best answer to every fight.
		ramp = 0.12,
	},
	-- C — CASTER: low health, high Ward, weak in melee, applies Burn/Weaken/Bind.
	-- Authored in step 2 but NEVER PLACED (§4.1 #2, §4.2) — it exists to prove
	-- the framework generalises.
	bruiser_grown_rat = {
		id = "bruiser_grown_rat",
		label = "BRUISER",
		name = "Grown Rat",
		kind = "BEAST",
		tier = 2,
		health = 120,
		armour = 24,
		ward = 6,
		dodge = 6,
		crit = 8,
		attrs = { STR = 16, VIT = 16, DEX = 6, WIS = 6, INT = 2, PIE = 2, LUK = 4, CHA = 2 },
		attacksPerTurn = 1,
		damageType = "physical",
		note = "Bigger than the hole it came through.",
		pattern = { "rat_bite", "rat_bite", "CHARGE:gnaw" },
	},
	caster_hedge_witch = {
		id = "caster_hedge_witch",
		label = "CASTER",
		name = "Hedge-witch",
		kind = "HUMAN",
		tier = 2,
		health = 45,
		armour = 4,
		ward = 22,
		dodge = 8,
		crit = 8,
		attrs = { STR = 5, VIT = 8, DEX = 8, WIS = 16, INT = 14, PIE = 6, LUK = 8, CHA = 10 },
		attacksPerTurn = 1,
		damageType = "arcane",
		note = "WARD 22 is a wall for a hatchet. Smite, or get to her.",
		pattern = { "hex", "bolt", "hex", "CHARGE:soul_nuke" },
	},
	-- C — SKIRMISHER: low health, low Armour, high Dodge, multiple weak attacks,
	-- flees when hurt. Pattern: two attacks, two attacks, reposition.  (§3.8)
	skirmisher_rat_swarm = {
		id = "skirmisher_rat_swarm",
		label = "SKIRMISHER",
		name = "Rat Swarm",
		kind = "BEAST",
		tier = 1,
		health = 24, -- TUNING: was 30 (§3.10)
		armour = 6, -- TUNING: was 8 (§3.10)
		ward = 2, -- §3.10
		dodge = 13, -- §3.10
		crit = 15, -- §3.10
		attrs = { STR = 6, VIT = 6, DEX = 16, WIS = 4, INT = 2, PIE = 2, LUK = 6, CHA = 2 },
		attacksPerTurn = 2, -- §3.10: two attacks per turn
		damageType = "physical",
		note = "Attacks twice. It will leave rather than die.",
		pattern = { "swarm_bite", "swarm_bite", "reposition" },
		flee = { belowHealth = 10 }, -- §3.10: at HP < 10 it attempts to flee
	},
}

-- ===========================================================================
-- The player's loadout, GEAR STUBBED (§4.2). These five numbers are the only
-- place gear enters step 2. They are the §3.10 baseline: an iron hatchet
-- (power 8) and leather (armour 6), so Wren's basic attack is 12×1.5+8 = 26.
-- ===========================================================================

CombatData.PlayerLoadout = {
	gear = {
		weaponPower = 9, -- TUNING: was 8. Iron hatchet; see TUNING block below.
		armour = 6, -- leather, §3.10
		ward = 0,
		focusPower = 0,
		symbolPower = 0,
		critDamageBonus = 0, -- crit DAMAGE lives on gear (§2.1); gear is step 2.5
		weaponName = "iron hatchet",
		armourName = "leather",
	},
	actions = { "attack", "cleave", "wild_swing", "brace", "oil_flask", "flee" },
	items = { oil_flask = 1 },
}

-- ===========================================================================
-- ENCOUNTERS (§3.10 / §4.1 #1). One encounter, two units.
-- `lossSeverity` is shown on the panel before the player commits (§5.4) and is
-- decided by the enemy and the situation, never by dice.
-- ===========================================================================

CombatData.Encounters = {
	ENC_GRANARY_JOB = {
		id = "ENC_GRANARY_JOB",
		title = "The Granary Job",
		-- Order matters: the swarm is faster and acts first (§3.10 initiative).
		enemies = {
			{ id = "swarm", archetype = "skirmisher_rat_swarm" },
			{ id = "rat", archetype = "bruiser_barrow_rat" },
		},
		-- The rats have no reason to finish you, and they could not if they
		-- tried: Defeat, not Dead (§5.4). Dead is never attached to a fair fight.
		lossSeverity = "defeat",
		cornered = false,
		sourceTier = 0, -- loot table tier hook (§2.4); loot itself is step 2.5
		-- TUNING: this fight can be SURVIVED, not only won. Hold six rounds and
		-- the rats have had enough of you, and enough grain to be going on with:
		-- a partial win (the contract and the coin, not the tails). This is what
		-- makes Brace a plan instead of a slower way to lose.
		standoff = {
			round = 6,
			text = "Six rounds of this and they have had enough. The swarm breaks "
				.. "for the hole under the boards and the big one follows it, "
				.. "grudging every step. What is left of the grain is yours.",
		},
		warning = "Something has been in the granary for a month, and it is bigger "
			.. "than the hole it came through.",
		stakes = "If you go down here you wake up robbed, not dead — the rats want the "
			.. "grain, not you.",
	},
}

return CombatData
