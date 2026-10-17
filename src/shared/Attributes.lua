--[[
	Attributes — the attribute layer and everything derived from it.

	Step 1 does not fight, but the whole layer is built now so that step 2
	(one combat encounter, end to end) can read real numbers off a real
	character without touching this module.

	All formulas are from stat-model-v1.md §1.2. Ranges are 4–40, ordinary
	adult is 10.
]]

local Config = require(script.Parent.Config)

local Attributes = {}

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

Attributes.clamp = clamp

-- Character creation ------------------------------------------------------

--- Roll a base sheet: each attribute is attrBase + d(attrDie), e.g. 7 + d4.
--- This is the "born into it" roll — narrow on purpose (stat-model §1.1).
function Attributes.rollBase(rng)
	local sheet = {}
	for _, key in ipairs(Config.AttributeOrder) do
		local value = Config.Birth.attrBase + rng:NextInteger(1, Config.Birth.attrDie)
		sheet[key] = clamp(value, Config.AttributeMin, Config.AttributeMax)
	end
	return sheet
end

--- Apply one race's percentage bonuses to a base sheet.
--- Percentage is taken of the final rolled value, rounded down, minimum +1.
function Attributes.applyRace(baseSheet, raceKey)
	local race = Config.Races[raceKey]
	local sheet = {}
	for _, key in ipairs(Config.AttributeOrder) do
		local value = baseSheet[key] or Config.AttributeMin
		local pct = race and race.attrBonus[key]
		if pct then
			local bonus = math.max(Config.RaceBonusMinimum, math.floor(value * pct))
			value = value + bonus
		end
		sheet[key] = clamp(value, Config.AttributeMin, Config.AttributeMax)
	end
	return sheet
end

--- The bonus a race would give, per attribute, for display at creation.
function Attributes.raceBonuses(raceKey)
	local race = Config.Races[raceKey]
	local out = {}
	for _, key in ipairs(Config.AttributeOrder) do
		out[key] = (race and race.attrBonus[key]) or 0
	end
	return out
end

-- Derived values ----------------------------------------------------------

--- HealthMax = (40 + VIT * 6) * race health multiplier, plus permanent
--- adjustments earned in play (scars, mostly downward).
function Attributes.healthMax(attrs, raceKey, permanentAdjust)
	local race = Config.Races[raceKey]
	local mult = (race and race.healthMultiplier) or 1
	local raw = Config.Derived.healthMaxBase + attrs.VIT * Config.Derived.healthMaxPerVit
	return math.floor(raw * mult) + (permanentAdjust or 0)
end

--- ManaMax = 10 + WIS * 4 + INT.
function Attributes.manaMax(attrs)
	local d = Config.Derived
	return d.manaMaxBase + attrs.WIS * d.manaMaxPerWis + attrs.INT * d.manaMaxPerInt
end

--- ManaRegen = 1 + floor(WIS / 2) per combat round.
function Attributes.manaRegen(attrs)
	local d = Config.Derived
	return d.manaRegenBase + math.floor(attrs.WIS / d.manaRegenPerWis)
end

--- Armour = gearArmour + floor(VIT / 2). Gear is step 2.
function Attributes.armour(attrs)
	return math.floor(attrs.VIT * Config.Derived.armourPerVit)
end

--- Ward = gearWard + WIS. Gear is step 2.
function Attributes.ward(attrs)
	return attrs.WIS * Config.Derived.wardPerWis
end

--- Dodge% = 3 + DEX * 0.6, capped 35.
function Attributes.dodge(attrs)
	local d = Config.Derived
	return math.floor(math.min(d.dodgeCap, d.dodgeBase + attrs.DEX * d.dodgePerDex))
end

--- CritRate% = 2 + DEX * 0.8, capped 40.
function Attributes.critRate(attrs)
	local d = Config.Derived
	return math.floor(math.min(d.critCap, d.critBase + attrs.DEX * d.critPerDex))
end

--- Carry capacity in kg = STR * 5.
function Attributes.carryCapacity(attrs)
	return attrs.STR * Config.Derived.carryPerStr
end

--- FortuneUses = 1 + floor(LUK / 15).
function Attributes.fortuneUses(attrs)
	local d = Config.Derived
	return d.fortuneBase + math.floor(attrs.LUK / d.fortunePerLuk)
end

--- Status resist% = stat * 1.5, capped 60. Physical resists use VIT,
--- magical ones use WIS.
function Attributes.resist(value)
	local d = Config.Derived
	return math.floor(math.min(d.resistCap, value * d.resistPerPoint))
end

--- Karma is worth more to a devout character, for good and ill.
function Attributes.karmaScale(attrs)
	return 1 + attrs.PIE / Config.Derived.karmaPietyDivisor
end

--- Everything derived, in one table, for the view model.
function Attributes.derived(attrs, raceKey, permanentAdjust)
	return {
		healthMax = Attributes.healthMax(attrs, raceKey, permanentAdjust),
		manaMax = Attributes.manaMax(attrs),
		manaRegen = Attributes.manaRegen(attrs),
		armour = Attributes.armour(attrs),
		ward = Attributes.ward(attrs),
		dodge = Attributes.dodge(attrs),
		crit = Attributes.critRate(attrs),
		carry = Attributes.carryCapacity(attrs),
		fortune = Attributes.fortuneUses(attrs),
		physicalResist = Attributes.resist(attrs.VIT),
		magicResist = Attributes.resist(attrs.WIS),
	}
end

-- Level and experience ----------------------------------------------------

--- Total experience required to reach `level` (level 1 costs nothing).
function Attributes.expForLevel(level)
	local total = 0
	local step = Config.Level.baseExp
	for _ = 2, level do
		total += math.floor(step)
		step *= Config.Level.growth
	end
	return total
end

--- Level derived from total experience, capped at the native ceiling.
function Attributes.levelFromExp(exp)
	local level = 1
	while level < Config.Level.cap and exp >= Attributes.expForLevel(level + 1) do
		level += 1
	end
	return level
end

--- Progress toward the next level, for a bar. Returns current, needed, fraction.
function Attributes.levelProgress(exp)
	local level = Attributes.levelFromExp(exp)
	if level >= Config.Level.cap then
		return 1, 1, 1
	end
	local floorExp = Attributes.expForLevel(level)
	local ceilExp = Attributes.expForLevel(level + 1)
	local into = exp - floorExp
	local span = math.max(1, ceilExp - floorExp)
	return into, span, into / span
end

--- Experience gained, after the character's race multiplier (Human +25%).
function Attributes.applyExpMultiplier(amount, raceKey)
	local race = Config.Races[raceKey]
	local mult = (race and race.expMultiplier) or 1
	return math.floor(amount * mult)
end

-- Lifespan ----------------------------------------------------------------

--- The year the character is expected to die, fixed at birth.
function Attributes.lifespan(attrs)
	local d = Config.Death
	return math.floor(
		d.lifespanBase
			+ math.max(0, attrs.VIT - 10) * d.lifespanPerVit
			+ attrs.LUK * d.lifespanPerLuck
	)
end

-- Checks ------------------------------------------------------------------

--- d20 + floor(attr / 2) vs a difficulty class. The one non-combat check
--- implemented in step 1; step 2 extends this rather than replacing it.
function Attributes.check(rng, attrs, attrKey, dc)
	local value = attrs[attrKey] or 0
	local roll = rng:NextInteger(1, 20)
	local total = roll + math.floor(value / 2)
	return {
		roll = roll,
		modifier = math.floor(value / 2),
		total = total,
		dc = dc,
		success = total >= dc,
	}
end

return Attributes
