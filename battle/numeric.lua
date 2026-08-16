-- battle/numeric.lua -- shared finite/bounded arithmetic and value boundaries.
--
-- Lua 5.1 exposes IEEE-754 doubles directly. Individually finite authored
-- values can still overflow when forces, inverse masses, impulses, and fixed
-- time are combined. This module gives the canonical simulation one numeric
-- policy for public inputs, derived products, events, snapshots, and replay.

local M = {}

-- Geometry participates in fourth-order swept-collision expressions
-- (projection^2 and speed^2 * distance^2). 1e64 leaves ample IEEE-754
-- headroom while remaining far beyond any authored arena value.
M.MAX_GEOMETRY_MAGNITUDE = 1e64

-- Mass and force use a wider range. The exact exponent-boundary regression
-- (1e-160 mass with 1e160 field strength) remains accepted; products involving
-- those values must pass through the saturating helpers below.
M.MIN_MASS = 1e-200
M.MAX_MASS = 1e200
M.MAX_FORCE_MAGNITUDE = 1e200

-- Published derived values (for example a collision impulse) may be larger
-- than any single input. Keeping them below 1e280 also leaves room for the
-- six-decimal quantizer without overflowing.
M.MAX_CANONICAL_MAGNITUDE = 1e280
M.MAX_SAFE_INTEGER = 9007199254740991
M.MAX_RESTITUTION = 4
M.MAX_FIXED_DT = 1

local abs, ceil, floor = math.abs, math.ceil, math.floor

function M.is_finite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function M.require_number(value, name, minimum, maximum)
    name = name or "number"
    if not M.is_finite(value) then
        error(name .. " must be a finite number")
    end
    if minimum ~= nil and value < minimum then
        error(name .. " must be at least " .. tostring(minimum))
    end
    if maximum ~= nil and value > maximum then
        error(name .. " must be no greater than " .. tostring(maximum))
    end
    return value
end

function M.require_integer(value, name, minimum, maximum)
    value = M.require_number(value, name, minimum, maximum)
    if value ~= floor(value) then error((name or "number") .. " must be an integer") end
    return value
end

function M.require_identifier(value, name)
    local kind = type(value)
    if kind == "string" and value ~= "" then return value end
    if kind == "number" then
        return M.require_number(
            value,
            name or "identifier",
            -M.MAX_SAFE_INTEGER,
            M.MAX_SAFE_INTEGER
        )
    end
    error((name or "identifier") .. " must be a non-empty string or bounded number")
end

function M.bound(value, fallback, limit)
    limit = limit or M.MAX_CANONICAL_MAGNITUDE
    fallback = fallback or 0
    if not M.is_finite(value) then return fallback, true end
    if value > limit then return limit, true end
    if value < -limit then return -limit, true end
    return value, false
end

function M.saturating_add(left, right, limit)
    limit = limit or M.MAX_CANONICAL_MAGNITUDE
    local left_recovered, right_recovered
    left, left_recovered = M.bound(left, 0, limit)
    right, right_recovered = M.bound(right, 0, limit)
    if right > 0 and left > limit - right then return limit, true end
    if right < 0 and left < -limit - right then return -limit, true end
    return left + right, left_recovered or right_recovered
end

function M.saturating_product(limit, ...)
    limit = limit or M.MAX_CANONICAL_MAGNITUDE
    local result = 1
    local recovered = false
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if not M.is_finite(value) then return 0, true end
        if value == 0 or result == 0 then return 0, recovered end
        local magnitude = abs(value)
        if abs(result) > limit / magnitude then
            local negative = (result < 0) ~= (value < 0)
            return negative and -limit or limit, true
        end
        result = result * value
    end
    return result, recovered
end

function M.saturating_divide(numerator, denominator, limit)
    limit = limit or M.MAX_CANONICAL_MAGNITUDE
    if not M.is_finite(numerator)
        or not M.is_finite(denominator)
        or denominator == 0
    then
        return 0, true
    end
    if numerator == 0 then return 0, false end
    local quotient_limit = limit * math.min(1, abs(denominator))
    if abs(numerator) > quotient_limit then
        local negative = (numerator < 0) ~= (denominator < 0)
        return negative and -limit or limit, true
    end
    return numerator / denominator, false
end

function M.quantize(value)
    if type(value) ~= "number" then return value end
    value = M.bound(value, 0, M.MAX_CANONICAL_MAGNITUDE)
    if abs(value) < 0.0000005 then return 0 end
    if value >= 0 then return floor(value * 1000000 + 0.5) / 1000000 end
    return ceil(value * 1000000 - 0.5) / 1000000
end

local function canonical_copy(value, seen, path)
    local kind = type(value)
    if kind == "number" then
        local bounded, recovered = M.bound(value, 0, M.MAX_CANONICAL_MAGNITUDE)
        return bounded, recovered and 1 or 0
    end
    if kind == "nil" or kind == "boolean" or kind == "string" then return value, 0 end
    if kind ~= "table" then
        error((path or "canonical value") .. " must contain plain serializable values")
    end
    seen = seen or {}
    if seen[value] then error((path or "canonical value") .. " must not contain cycles") end
    seen[value] = true
    local out, recoveries = {}, 0
    for key, item in pairs(value) do
        local copied_key, key_recoveries = canonical_copy(key, seen, (path or "value") .. " key")
        local copied_item, item_recoveries = canonical_copy(
            item,
            seen,
            (path or "value") .. "." .. tostring(key)
        )
        out[copied_key] = copied_item
        recoveries = recoveries + key_recoveries + item_recoveries
    end
    seen[value] = nil
    return out, recoveries
end

function M.canonical_copy(value, path)
    return canonical_copy(value, {}, path or "canonical value")
end

local function input_copy(value, seen, path, numeric_limit)
    local kind = type(value)
    if kind == "number" then
        return M.require_number(value, path, -numeric_limit, numeric_limit)
    end
    if kind == "nil" or kind == "boolean" or kind == "string" then return value end
    if kind ~= "table" then
        error(path .. " must contain plain serializable values")
    end
    if seen[value] then error(path .. " must not contain cycles") end
    seen[value] = true
    local out = {}
    for key, item in pairs(value) do
        local copied_key = input_copy(key, seen, path .. " key", numeric_limit)
        out[copied_key] = input_copy(item, seen, path .. "." .. tostring(key), numeric_limit)
    end
    seen[value] = nil
    return out
end

function M.input_copy(value, path, numeric_limit)
    return input_copy(
        value,
        {},
        path or "input value",
        numeric_limit or M.MAX_CANONICAL_MAGNITUDE
    )
end

function M.is_canonical_tree(value, seen)
    local kind = type(value)
    if kind == "number" then
        return M.is_finite(value) and abs(value) <= M.MAX_CANONICAL_MAGNITUDE
    end
    if kind == "nil" or kind == "boolean" or kind == "string" then return true end
    if kind ~= "table" then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, item in pairs(value) do
        if not M.is_canonical_tree(key, seen) or not M.is_canonical_tree(item, seen) then
            seen[value] = nil
            return false
        end
    end
    seen[value] = nil
    return true
end

return M
