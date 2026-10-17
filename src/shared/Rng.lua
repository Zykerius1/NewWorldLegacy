--[[
	Rng — small helpers over a seeded Random.

	Every random draw in the game goes through this module, and every draw is
	taken on the SERVER. The client never rolls anything.
]]

local Rng = {}

function Rng.new(seed)
	return Random.new(seed or os.clock() * 1e6)
end

--- Uniform integer in [1, sides].
function Rng.die(rng, sides)
	return rng:NextInteger(1, sides)
end

--- True with probability p (0..1).
function Rng.chance(rng, p)
	return rng:NextNumber() < p
end

--- Uniform pick from an array. Returns nil for an empty array.
function Rng.pick(rng, list)
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

--- Weighted pick. `weightOf` maps an entry to a positive number.
--- Entries with weight <= 0 are skipped. Returns nil if nothing qualifies.
function Rng.weighted(rng, list, weightOf)
	local total = 0
	for _, entry in ipairs(list) do
		local w = weightOf(entry) or 0
		if w > 0 then
			total += w
		end
	end
	if total <= 0 then
		return nil
	end

	local roll = rng:NextNumber() * total
	local running = 0
	for _, entry in ipairs(list) do
		local w = weightOf(entry) or 0
		if w > 0 then
			running += w
			if roll <= running then
				return entry
			end
		end
	end
	-- Floating-point tail: fall back to the last positive-weight entry.
	local last = nil
	for _, entry in ipairs(list) do
		if (weightOf(entry) or 0) > 0 then
			last = entry
		end
	end
	return last
end

return Rng
