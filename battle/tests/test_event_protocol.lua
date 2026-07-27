-- battle_start carries the complete value-only state needed by consumers to
-- initialize without reading the mutable battle object.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local engine = require("battle.engine")
local setup = require("battle.tests.fixtures")

local M = { name = "event_protocol" }

local function serializable(value, seen)
    local value_type = type(value)
    if value_type ~= "table" then
        return value_type == "nil" or value_type == "number"
            or value_type == "string" or value_type == "boolean"
    end
    if seen[value] then return false end
    seen[value] = true
    for key, item in pairs(value) do
        if not serializable(key, seen) or not serializable(item, seen) then
            return false
        end
    end
    seen[value] = nil
    return true
end

function M.run(t)
    local battle = engine.new_battle({ seed = 9125, sides = setup.default_matchup() })
    local event = battle.log.events[1]
    t:eq(event.type, "battle_start", "first event initializes the battle")
    t:eq(event.initial_state.protocol_version, 2, "continuous initial-state protocol is versioned")
    t:ok(serializable(event, {}), "battle_start contains serializer-safe values only")

    for _, id in ipairs({ "A", "B" }) do
        local player = battle.sides[id]
        local side = event.initial_state.sides[id]
        t:eq(side.id, player.id, id .. " identity is present")
        t:eq(side.name, player.name, id .. " display name is present")
        t:eq(side.sling_id, player.sling.id, id .. " sling identity is present")
        t:eq(side.rows, player.formation.rows, id .. " row count is present")
        t:eq(side.cols, player.formation.cols, id .. " column count is present")
        t:eq(#side.bricks, player.formation.alive, id .. " every brick is present")
        t:eq(#side.marbles, #player.roster, id .. " every marble is present")
        t:eq(#side.queue, #player.queue, id .. " declared queue is present")
        t:eq(#side.marbles[1].shells, #player.roster[1].shells,
            id .. " every shell layer is present")
        t:ok(side.marbles[1] ~= player.roster[1],
            id .. " marble payload does not alias engine state")
        t:ok(side.marbles[1].shells[1] ~= player.roster[1].shells[1],
            id .. " shell payload does not alias engine state")
    end

    local initial_hp = event.initial_state.sides.A.bricks[1].hp
    battle.sides.A.formation.grid[1][1].hp = initial_hp - 1
    t:eq(event.initial_state.sides.A.bricks[1].hp, initial_hp,
        "mutating engine state cannot mutate the initial event")

    local second = engine.new_battle({ seed = 9125, sides = setup.default_matchup() })
    t:eq(second.log:lines()[1], battle.log:lines()[1],
        "nested initial payload has a canonical deterministic rendering")
end

if arg and arg[0] and arg[0]:find("test_event_protocol.lua", 1, true) then
    harness.run_one(M)
end

return M
