-- Plain-Lua tests for snapshot projection and canonical-frame replay.

package.path = table.concat({
    "./src/?.lua",
    "./?.lua",
    package.path,
}, ";")

local engine = require("battle.engine")
local setup = require("battle.tests.fixtures")
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

local function serializable(value, seen)
    local kind = type(value)
    if kind ~= "table" then
        return kind == "nil" or kind == "number" or kind == "string" or kind == "boolean"
    end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, item in pairs(value) do
        if not serializable(key, seen) or not serializable(item, seen) then return false end
    end
    seen[value] = nil
    return true
end

local battle = engine.new({
    seed = presentation.DEFAULT_SEED,
    sides = setup.default_matchup(),
    max_exchanges = 1,
    max_exchange_ticks = 180,
})
engine.drain_events(battle)
local previous = engine.snapshot(battle)
local live_events = engine.step(battle, engine.FIXED_DT)
local current = engine.snapshot(battle)
local projected = presentation.project(current, previous, 0.5)

eq(projected.schema_version, 2, "projection schema is versioned")
eq(projected.seed, presentation.DEFAULT_SEED, "projection keeps battle seed")
eq(projected.tick, 1, "projection identifies the completed tick")
eq(projected.exchange, 1, "projection identifies the live exchange")
eq(projected.screen, "battle", "unfinished snapshot projects the battle screen")
eq(projected.sides.A.name, current.sides.A.name, "A display name comes from snapshot")
eq(projected.sides.B.name, current.sides.B.name, "B display name comes from snapshot")
eq(projected.sides.A.bricks_alive, current.sides.A.bricks_alive,
    "brick counts come from canonical snapshot")
eq(#projected.sides.A.queue, #current.sides.A.queue,
    "queue comes from canonical snapshot")
ok(#projected.entities > 20, "projection exposes renderer-ready physical entities")
ok(serializable(projected), "presentation state is serializer-safe")

local active
for _, entity in ipairs(projected.entities) do
    if entity.type == "marble" and entity.owner == "A" and entity.state == "flying" then
        active = entity
        break
    end
end
ok(active ~= nil, "active physical marble is projected")
if active then
    local now, before
    for _, item in ipairs(current.sides.A.marbles) do
        if item.uid == active.uid then now = item end
    end
    for _, item in ipairs(previous.sides.A.marbles) do
        if item.uid == active.uid then before = item end
    end
    ok(active.x >= math.min(before.x, now.x) and active.x <= math.max(before.x, now.x),
        "render x interpolates between completed snapshots")
    ok(active.y >= math.min(before.y, now.y) and active.y <= math.max(before.y, now.y),
        "render y interpolates between completed snapshots")
end

projected.sides.A.bricks[1].hp = -100
local clean = presentation.project(current, previous, 0.5)
ok(clean.sides.A.bricks[1].hp >= 0, "projection owns its brick values")
ok(clean.world.fields ~= current.world.fields, "projection owns field values")

local cues = presentation.cues(live_events)
eq(#cues, #live_events, "every exact-tick event can produce a view cue")
ok(cues[1].tick ~= nil, "cue retains canonical tick")
ok(type(cues[1].text) == "string", "cue supplies accessibility text")

engine.run(battle)
local recording = engine.recording(battle)
local replay = presentation.from_recording(recording)
eq(replay.cursor, 1, "recording replay begins at its first canonical frame")
eq(replay.recording.fixed_dt, engine.FIXED_DT, "replay retains recorded timing")
ok(replay.recording ~= recording, "replay deep-copies recording container")
ok(replay.recording.frames ~= recording.frames, "replay deep-copies canonical frames")

local first_tick = replay.recording.frames[1].tick
recording.frames[1].tick = -99
eq(replay.recording.frames[1].tick, first_tick,
    "caller mutation cannot change replay-owned frames")
presentation.replay_step(replay, 1)
eq(replay.cursor, 2, "replay step advances one recorded frame")
local replay_view = presentation.replay_project(replay)
eq(replay_view.tick, replay.recording.frames[2].tick,
    "replay projection renders the recorded frame")
presentation.replay_seek(replay, 0)
eq(replay.cursor, 1, "replay seeks from canonical frame ticks")
presentation.replay_seek(replay, 1000000)
eq(replay.cursor, #replay.recording.frames, "replay can seek to the final frame")
replay_view = presentation.replay_project(replay)
eq(replay_view.screen, "result", "final recorded frame projects result screen")
eq(replay_view.result.reason, battle.result.reason,
    "recording replay displays canonical outcome")

local handle = io.open("src/presentation.lua", "r")
ok(handle ~= nil, "presentation source is readable")
if handle then
    local source = handle:read("*a")
    handle:close()
    local banned = {
        { "love.", "projector has no LÖVE dependency" },
        { 'require("battle.engine")', "projector never steps a battle" },
        { "damage_brick", "projector does not implement damage" },
        { "resolve_collision", "projector does not implement collisions" },
        { "math.random", "projector has no randomness" },
        { "os.time", "projector has no wall-clock state" },
    }
    for _, item in ipairs(banned) do ok(not source:find(item[1], 1, true), item[2]) end
    ok(source:find("function M.project", 1, true) ~= nil,
        "projector exposes snapshot API")
    ok(source:find("function M.from_recording", 1, true) ~= nil,
        "projector exposes recorded-frame replay API")
end

if failures == 0 then
    print(string.format("OK: %d presentation checks passed", checks))
    os.exit(0)
end

print(string.format("FAILED: %d of %d presentation checks failed", failures, checks))
os.exit(1)
