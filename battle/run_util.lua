-- Shared value helpers for the run/draft boundary.  Everything returned by
-- these helpers is a plain Lua value so it can cross the headless/client
-- boundary and survive a serializer round trip.

local M = {}

function M.deep_copy(source, seen)
    if type(source) ~= "table" then return source end
    seen = seen or {}
    if seen[source] then error("run values must not contain cycles") end
    seen[source] = true
    local out = {}
    for key, value in pairs(source) do
        out[M.deep_copy(key, seen)] = M.deep_copy(value, seen)
    end
    seen[source] = nil
    return out
end

function M.deep_equal(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not M.deep_equal(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

function M.contains(list, wanted)
    for _, value in ipairs(list or {}) do
        if value == wanted then return true end
    end
    return false
end

function M.index_of(list, wanted)
    for index, value in ipairs(list or {}) do
        if value == wanted then return index end
    end
    return nil
end

function M.set(list)
    local out = {}
    for _, value in ipairs(list or {}) do out[value] = true end
    return out
end

function M.sorted_keys(map)
    local out = {}
    for key in pairs(map or {}) do out[#out + 1] = key end
    table.sort(out, function(left, right) return tostring(left) < tostring(right) end)
    return out
end

function M.normalize_seed(value, modulus)
    modulus = modulus or 2147483647
    local seed = math.floor(tonumber(value) or 1) % modulus
    if seed < 0 then seed = seed + modulus end
    if seed == 0 then seed = 1 end
    return seed
end

function M.next_seed(value, modulus)
    modulus = modulus or 2147483647
    local seed = M.normalize_seed(value, modulus) + 1
    if seed >= modulus then seed = 1 end
    return seed
end

function M.is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

return M
