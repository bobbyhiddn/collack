-- Stable same-build checkpoint signatures for canonical recorded frames.
-- This is verification metadata, not a combat rule or a serialization format.

local M = {}

local MODULUS = 2147483647

local function key_less(left, right)
    local left_type, right_type = type(left), type(right)
    if left_type ~= right_type then return left_type < right_type end
    if left_type == "number" or left_type == "string" then return left < right end
    return tostring(left) < tostring(right)
end

local function append_value(parts, value, seen)
    local kind = type(value)
    if kind == "nil" then
        parts[#parts + 1] = "n;"
    elseif kind == "boolean" then
        parts[#parts + 1] = value and "b1;" or "b0;"
    elseif kind == "number" then
        parts[#parts + 1] = "d" .. string.format("%.17g", value) .. ";"
    elseif kind == "string" then
        parts[#parts + 1] = "s" .. #value .. ":" .. value .. ";"
    elseif kind == "table" then
        if seen[value] then error("checkpoint values cannot contain cycles") end
        seen[value] = true
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, key_less)
        parts[#parts + 1] = "{"
        for _, key in ipairs(keys) do
            append_value(parts, key, seen)
            append_value(parts, value[key], seen)
        end
        parts[#parts + 1] = "};"
        seen[value] = nil
    else
        error("checkpoint values must be plain serializable data")
    end
end

function M.signature(value)
    local parts = {}
    append_value(parts, value, {})
    local encoded = table.concat(parts)
    local hash = 5381
    for index = 1, #encoded do
        hash = (hash * 65599 + encoded:byte(index)) % MODULUS
    end
    return string.format("%08x", hash)
end

function M.from_recording(recording)
    assert(type(recording) == "table", "checkpoint recording is required")
    local out = {}
    for _, frame in ipairs(recording.keyframes or {}) do
        local item = string.format("%06d:%s", frame.tick or 0, M.signature(frame))
        if #out > 0 and out[#out]:sub(1, 7) == item:sub(1, 7) then
            out[#out] = item
        else
            out[#out + 1] = item
        end
    end
    return out
end

return M
