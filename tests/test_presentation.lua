-- Plain-Lua tests for the event-only presentation projection. No LÖVE runtime
-- is required.

package.path = table.concat({
    "./src/?.lua",
    "./?.lua",
    package.path,
}, ";")

local engine = require("battle.engine")
local setup = require("battle.setup")
local presentation = require("presentation")

local checks, failures = 0, 0

local function ok(condition, message)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        print("FAIL: " .. message)
    end
end

local function eq(actual, expected, message)
    ok(actual == expected, string.format("%s - expected %s, got %s",
        message, tostring(expected), tostring(actual)))
end

-- This intentionally accepts only the data types a normal event serializer
-- can preserve. It also ensures the projection receives no engine-owned table.
local function serialization_round_trip(value)
    local value_type = type(value)
    if value_type ~= "table" then
        assert(value_type == "nil" or value_type == "number"
            or value_type == "string" or value_type == "boolean",
            "event protocol contains non-serializable " .. value_type)
        return value
    end
    local copy = {}
    for key, item in pairs(value) do
        copy[serialization_round_trip(key)] = serialization_round_trip(item)
    end
    return copy
end

local function first_launch(events, side)
    for _, event in ipairs(events) do
        if event.type == "launch" and event.side == side then return event end
    end
    return nil
end

local first = presentation.new(presentation.DEFAULT_SEED)
ok(#first.events > 40, "canonical engine produced an animatable event log")
eq(first.events[1].type, "battle_start", "event stream begins with battle_start")
eq(first.events[#first.events].type, "battle_end", "event stream ends with battle_end")
eq(first.cursor, 0, "adapter begins before the first event")
eq(first.events[1].initial_state.protocol_version, 1,
    "battle_start identifies the initial-state protocol")
eq(first.view.sides.A.bricks_alive,
    first.events[1].initial_state.sides.A.bricks_alive,
    "A initial display comes from battle_start")
eq(first.view.sides.B.bricks_alive,
    first.events[1].initial_state.sides.B.bricks_alive,
    "B initial display comes from battle_start")
eq(first.battle, nil, "presentation retains no mutable battle snapshot")

local declared_first = first.view.sides.A.queue[1]
local launch = first_launch(first.events, "A")
ok(launch ~= nil, "A has a launch in the canonical log")
if launch then
    eq(launch.marble, declared_first, "displayed queue order matches player-declared order")
end

local replay = presentation.replay(first)
eq(replay.seed, first.seed, "replay keeps the seed")
eq(replay.log_text, first.log_text, "replay keeps the byte-identical engine log")
eq(replay.result.winner, first.result.winner, "replay keeps the winner")
eq(#replay.events, #first.events, "replay keeps the event count")
ok(replay.events ~= first.events, "replay owns a deep-copied event sequence")
ok(replay.events[1].initial_state ~= first.events[1].initial_state,
    "replay does not share its initial-state payload")

local next_seed = presentation.next_seed(first)
eq(next_seed.seed, first.seed + 1, "new seed advances deterministically")
ok(next_seed.log_text ~= first.log_text, "new seed produces a distinct canonical log")

presentation.to_end(first)
presentation.to_end(replay)
eq(first.cursor, #first.events, "to_end consumes every event")
eq(first.view.finished, true, "battle_end marks the display finished")
eq(first.view.outcome, first.result.outcome, "displayed outcome matches event result")
eq(first.view.winner, first.result.winner, "displayed winner matches event result")
eq(first.view.seq, replay.view.seq, "same-seed adapters finish on the same event")
eq(first.view.winner, replay.view.winner, "same-seed adapters render the same winner")

-- Build projections from serializer-safe copies only, then compare their final
-- state to the independently retained canonical engine outcome.
for _, seed in ipairs({ 1, 42, 9125, 20260726 }) do
    local battle = engine.new_battle({ seed = seed, sides = setup.default_matchup() })
    local engine_result = engine.run(battle)
    local decoded_events = serialization_round_trip(battle.log.events)
    local projected = presentation.from_events(decoded_events)

    local original_name = projected.view.sides.A.name
    decoded_events[1].initial_state.sides.A.name = "mutated after decode"
    eq(projected.view.sides.A.name, original_name,
        "seed " .. seed .. ": projection owns its decoded initial state")

    presentation.to_end(projected)
    eq(projected.view.outcome, engine_result.outcome,
        "seed " .. seed .. ": projected outcome matches engine")
    eq(projected.view.winner, engine_result.winner,
        "seed " .. seed .. ": projected winner matches engine")
    eq(projected.view.reason, engine_result.reason,
        "seed " .. seed .. ": projected reason matches engine")
    eq(projected.view.volley, engine_result.volleys,
        "seed " .. seed .. ": projected volley count matches engine")
    eq(projected.view.sides.A.bricks_alive, battle.sides.A.formation.alive,
        "seed " .. seed .. ": A projected brick count matches engine")
    eq(projected.view.sides.B.bricks_alive, battle.sides.B.formation.alive,
        "seed " .. seed .. ": B projected brick count matches engine")
    eq(projected.view.sides.A.marbles_alive, #battle.sides.A.roster,
        "seed " .. seed .. ": A projected marble count matches engine")
    eq(projected.view.sides.B.marbles_alive, #battle.sides.B.roster,
        "seed " .. seed .. ": B projected marble count matches engine")
end

local shell_events = 0
local effect_events = 0
local effect_types = {
    absorb = true, reflect = true, regenerate = true, fortify = true,
    status_applied = true, magnetic = true, shatter = true, chain_detonate = true,
    vault = true, splice = true, dummy = true, aegis = true, void = true,
    mirror = true, temporal = true, ricochet = true,
}
for _, event in ipairs(first.events) do
    if event.type == "shell_damaged" or event.type == "shell_crushed"
        or event.type == "shell_break" then
        shell_events = shell_events + 1
    end
    if effect_types[event.type] then effect_events = effect_events + 1 end
end
ok(shell_events > 0, "event log exposes shell damage for presentation")
ok(effect_events > 0, "event log exposes brick/sling effects for presentation")
ok(#first.view.feed <= 6, "adapter bounds its visible event feed")

local handle = io.open("src/presentation.lua", "r")
ok(handle ~= nil, "presentation adapter source is readable")
if handle then
    local source = handle:read("*a")
    handle:close()
    local banned = {
        { "love.", "adapter has no LÖVE dependency" },
        { "math.random", "adapter has no independent randomness" },
        { "os.time", "adapter has no wall-clock seed" },
        { "damage_brick", "adapter does not implement brick damage" },
        { "resolve_collision", "adapter does not implement collisions" },
        { "battle.content", "adapter does not interpret content rules" },
        { "battle.sides", "adapter never reads a mutable battle snapshot" },
        { "snapshot_side", "adapter has no engine-object snapshot helper" },
    }
    for _, item in ipairs(banned) do
        ok(not source:find(item[1], 1, true), item[2])
    end
    ok(source:find('require("battle.engine")', 1, true) ~= nil,
        "adapter delegates battle execution to the canonical engine")
    ok(source:find("function M.from_events", 1, true) ~= nil,
        "adapter exposes an events-only replay constructor")
end

if failures == 0 then
    print(string.format("OK: %d presentation checks passed", checks))
    os.exit(0)
end

print(string.format("FAILED: %d of %d presentation checks failed", failures, checks))
os.exit(1)
