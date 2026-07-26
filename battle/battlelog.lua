-- battle/battlelog.lua — the battle log.
--
-- The log is the engine's output of record. The determinism requirement is
-- stated in terms of it: same seed + same setup => byte-identical log.
--
-- Every event is rendered as one line:
--   0042 v03 A shell_break marble=7 mineral=jade shells_left=1
-- i.e. sequence, volley, side, type, then the event's own fields as key=value
-- pairs sorted by key. Sorting is what makes the rendering independent of Lua's
-- table iteration order, which is NOT stable across runs or builds. Nothing in
-- this file may iterate an event's fields with pairs() and emit in that order.

local Log = {}
Log.__index = Log

local RESERVED = { seq = true, volley = true, side = true, type = true }

function Log.new()
    return setmetatable({ events = {}, seq = 0 }, Log)
end

--- Append an event. `fields` may be nil.
function Log:add(volley, side, kind, fields)
    self.seq = self.seq + 1
    local event = {
        seq = self.seq,
        volley = volley,
        side = side or "-",
        type = kind,
    }
    if fields then
        for key, value in pairs(fields) do
            if RESERVED[key] then
                error("event field shadows a reserved key: " .. key)
            end
            event[key] = value
        end
    end
    self.events[#self.events + 1] = event
    return event
end

local function format_number(value)
    if value == math.floor(value) then
        return string.format("%d", value)
    end
    -- No engine value is fractional today; if one ever is, pin the
    -- formatting so it cannot drift between platforms.
    return string.format("%.6f", value)
end

local function sorted_keys(value)
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        local left_type, right_type = type(left), type(right)
        if left_type ~= right_type then return left_type < right_type end
        if left_type == "number" or left_type == "string" then return left < right end
        if left_type == "boolean" then return left == false and right == true end
        error("event payload table keys must be scalar values")
    end)
    return keys
end

local function is_array(keys)
    for index, key in ipairs(keys) do
        if key ~= index then return false end
    end
    return true
end

local function format_nested(value, visiting)
    local value_type = type(value)
    if value_type == "number" then return format_number(value) end
    if value_type == "boolean" then return value and "true" or "false" end
    if value_type == "string" then return string.format("%q", value) end
    if value_type ~= "table" then
        error("unsupported nested event value type: " .. value_type)
    end
    if visiting[value] then error("event payload tables must not contain cycles") end
    visiting[value] = true

    local keys = sorted_keys(value)
    local parts = {}
    if is_array(keys) then
        for _, item in ipairs(value) do
            parts[#parts + 1] = format_nested(item, visiting)
        end
        visiting[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end

    for _, key in ipairs(keys) do
        parts[#parts + 1] = format_nested(key, visiting)
            .. ":" .. format_nested(value[key], visiting)
    end
    visiting[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local function format_value(value)
    if type(value) == "number" then
        return format_number(value)
    end
    if type(value) == "boolean" then
        return value and "true" or "false"
    end
    if type(value) == "table" then
        return format_nested(value, {})
    end
    return tostring(value)
end

--- Render one event to its canonical line.
function Log.format_event(event)
    local keys = {}
    for key in pairs(event) do
        if not RESERVED[key] then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)

    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = key .. "=" .. format_value(event[key])
    end

    local head = string.format("%04d v%02d %s %s", event.seq, event.volley, event.side, event.type)
    if #parts == 0 then
        return head
    end
    return head .. " " .. table.concat(parts, " ")
end

--- Render the whole log to an array of lines.
function Log:lines()
    local out = {}
    for index, event in ipairs(self.events) do
        out[index] = Log.format_event(event)
    end
    return out
end

--- Render the whole log to one string. This is what the determinism test diffs.
function Log:text()
    return table.concat(self:lines(), "\n")
end

--- Every event of a given type, in order.
function Log:of_type(kind)
    local out = {}
    for _, event in ipairs(self.events) do
        if event.type == kind then
            out[#out + 1] = event
        end
    end
    return out
end

function Log:count(kind)
    return #self:of_type(kind)
end

return Log
