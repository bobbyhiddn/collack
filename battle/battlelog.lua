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

local function format_value(value)
    if type(value) == "number" then
        if value == math.floor(value) then
            return string.format("%d", value)
        end
        -- No engine value is fractional today; if one ever is, pin the
        -- formatting so it cannot drift between platforms.
        return string.format("%.6f", value)
    end
    if type(value) == "boolean" then
        return value and "true" or "false"
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
