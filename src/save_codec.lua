-- A value-only save format. Loading a save never evaluates Lua source.
local M = {}
local MAX_BYTES, MAX_DEPTH, MAX_VALUES = 64 * 1024 * 1024, 96, 8000000

-- Detect damaged storage before passing compressed bytes to the native runtime.
function M.checksum(bytes)
    local value = 7
    for index = 1, #bytes do value = (value * 131 + bytes:byte(index)) % 2147483647 end
    return string.format("%08x", value)
end

function M.encode(value)
    local chunks, blocks, seen, count, size = {}, {}, {}, 0, 0
    local function append(text)
        size = size + #text
        assert(size <= MAX_BYTES, "Save is too large")
        chunks[#chunks + 1] = text
        -- Recordings contain millions of small fields. Flush in bounded
        -- batches rather than retaining millions of string references.
        if #chunks == 512 then
            blocks[#blocks + 1] = table.concat(chunks)
            chunks = {}
        end
    end
    append("COLLACK1\n")
    local function write(item, depth)
        count = count + 1
        assert(depth <= MAX_DEPTH and count <= MAX_VALUES, "Save is too complex")
        local kind = type(item)
        if kind == "nil" then append("z")
        elseif kind == "boolean" then append(item and "t" or "f")
        elseif kind == "number" then
            assert(item == item and math.abs(item) < math.huge, "Invalid save number")
            append("n" .. string.format("%.17g", item) .. ";")
        elseif kind == "string" then
            append("s" .. #item .. ":" .. item)
        elseif kind == "table" then
            assert(not seen[item] and getmetatable(item) == nil, "Invalid save table")
            seen[item] = true
            local keys = {}
            for key in pairs(item) do
                assert(type(key) == "string" or type(key) == "number", "Invalid save key")
                keys[#keys + 1] = key
            end
            table.sort(keys, function(a, b)
                if type(a) ~= type(b) then return type(a) < type(b) end
                return a < b
            end)
            append("a" .. #keys .. ":")
            for _, key in ipairs(keys) do write(key, depth + 1); write(item[key], depth + 1) end
            seen[item] = nil
        else error("Unsupported save value") end
    end
    write(value, 0)
    blocks[#blocks + 1] = table.concat(chunks)
    return table.concat(blocks)
end

function M.decode(bytes)
    assert(type(bytes) == "string" and #bytes <= MAX_BYTES
        and bytes:sub(1, 9) == "COLLACK1\n", "Invalid save header")
    local cursor, count = 10, 0
    local function length()
        local finish = assert(bytes:find(":", cursor, true), "Incomplete save length")
        local text = bytes:sub(cursor, finish - 1)
        assert(text:match("^%d+$") and #text <= 8, "Invalid save length")
        cursor = finish + 1
        return tonumber(text)
    end
    local function read(depth)
        count = count + 1
        assert(depth <= MAX_DEPTH and count <= MAX_VALUES, "Save is too complex")
        local tag = bytes:sub(cursor, cursor)
        cursor = cursor + 1
        if tag == "z" then return nil
        elseif tag == "t" then return true
        elseif tag == "f" then return false
        elseif tag == "n" then
            local finish = assert(bytes:find(";", cursor, true), "Incomplete save number")
            local number = tonumber(bytes:sub(cursor, finish - 1))
            assert(number and number == number and math.abs(number) < math.huge, "Invalid save number")
            cursor = finish + 1
            return number
        elseif tag == "s" then
            local size = length()
            assert(cursor + size - 1 <= #bytes, "Incomplete save string")
            local text = bytes:sub(cursor, cursor + size - 1)
            cursor = cursor + size
            return text
        elseif tag == "a" then
            local size, result = length(), {}
            assert(size <= MAX_VALUES and size <= #bytes - cursor + 1, "Invalid save table length")
            for _ = 1, size do
                local key = read(depth + 1)
                assert(type(key) == "string" or type(key) == "number", "Invalid save key")
                assert(result[key] == nil, "Duplicate save key")
                local value = read(depth + 1)
                assert(value ~= nil, "Invalid empty table value")
                result[key] = value
            end
            return result
        end
        error("Invalid save tag")
    end
    local result = read(0)
    assert(cursor == #bytes + 1, "Unexpected data after save")
    return result
end

return M
