-- battle/rng.lua — deterministic pseudo-random source.
--
-- Pure Lua, no love.*, no math.random. math.random is deliberately NOT used:
-- its implementation is the host C library's, so the same seed produces
-- different streams on different platforms and Lua builds. A battle log has to
-- be byte-identical on a dev laptop and on a CI runner, so the generator lives
-- here where we control it exactly.
--
-- Algorithm: Lehmer / MINSTD, x' = (16807 * x) mod (2^31 - 1).
-- Every intermediate stays below 2^45, well inside the 53-bit exact-integer
-- range of a double, so the arithmetic is exact on any conforming Lua 5.1+.

local RNG = {}
RNG.__index = RNG

local MODULUS = 2147483647 -- 2^31 - 1
local MULTIPLIER = 16807

--- Create a generator. Any integer seed is accepted and normalised into the
--- generator's valid range (1 .. MODULUS-1); 0 is not a legal MINSTD state.
function RNG.new(seed)
    seed = math.floor(tonumber(seed) or 1)
    seed = seed % MODULUS
    if seed < 0 then seed = seed + MODULUS end
    if seed == 0 then seed = 1 end
    return setmetatable({ seed = seed, state = seed, draws = 0 }, RNG)
end

--- Raw draw in 1 .. MODULUS-1.
function RNG:next()
    self.state = (MULTIPLIER * self.state) % MODULUS
    self.draws = self.draws + 1
    return self.state
end

--- Inclusive integer in [lo, hi]. Integer-only arithmetic, so there is no
--- float rounding anywhere in the path from state to result.
function RNG:int(lo, hi)
    if hi <= lo then return lo end
    return lo + (self:next() % (hi - lo + 1))
end

--- True with the given percentage probability (0..100).
function RNG:chance(percent)
    return self:int(1, 100) <= percent
end

--- Pick one element of a sequence. Returns nil for an empty sequence.
function RNG:pick(list)
    if #list == 0 then return nil end
    return list[self:int(1, #list)]
end

--- Either -1 or 1. Used when a direction is genuinely undetermined, e.g. a
--- marble sitting exactly on a blowback epicentre.
function RNG:sign()
    if self:int(0, 1) == 0 then return -1 end
    return 1
end

return RNG
