-- Plain-Lua tests for the presentation adapter. No LÖVE runtime is required.

package.path = table.concat({
    "./src/?.lua",
    "./?.lua",
    package.path,
}, ";")

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

local first = presentation.new(presentation.DEFAULT_SEED)
ok(#first.events > 40, "canonical engine produced an animatable event log")
eq(first.events[1].type, "battle_start", "event stream begins with battle_start")
eq(first.events[#first.events].type, "battle_end", "event stream ends with battle_end")
eq(first.cursor, 0, "adapter begins before the first event")
eq(first.view.sides.A.bricks_alive, first.events[1].a_bricks, "A snapshot comes from engine state")
eq(first.view.sides.B.bricks_alive, first.events[1].b_bricks, "B snapshot comes from engine state")

local declared_first = first.view.sides.A.queue[1]
local first_launch = nil
for _, event in ipairs(first.events) do
    if event.type == "launch" and event.side == "A" then
        first_launch = event
        break
    end
end
ok(first_launch ~= nil, "A has a launch in the canonical log")
if first_launch then
    eq(first_launch.marble, declared_first, "displayed queue order matches player-declared order")
end

local replay = presentation.replay(first)
eq(replay.seed, first.seed, "replay keeps the seed")
eq(replay.log_text, first.log_text, "replay keeps the byte-identical engine log")
eq(replay.result.winner, first.result.winner, "replay keeps the winner")
eq(#replay.events, #first.events, "replay keeps the event count")

local next_seed = presentation.next_seed(first)
eq(next_seed.seed, first.seed + 1, "new seed advances deterministically")
ok(next_seed.log_text ~= first.log_text, "new seed produces a distinct canonical log")

presentation.to_end(first)
presentation.to_end(replay)
eq(first.cursor, #first.events, "to_end consumes every event")
eq(first.view.finished, true, "battle_end marks the display finished")
eq(first.view.outcome, first.result.outcome, "displayed outcome matches engine result")
eq(first.view.winner, first.result.winner, "displayed winner matches engine result")
eq(first.view.sides.A.bricks_alive, first.battle.sides.A.formation.alive,
    "A displayed brick count matches final engine state")
eq(first.view.sides.B.bricks_alive, first.battle.sides.B.formation.alive,
    "B displayed brick count matches final engine state")
eq(first.view.sides.A.marbles_alive, #first.battle.sides.A.roster,
    "A displayed marble count matches final engine state")
eq(first.view.sides.B.marbles_alive, #first.battle.sides.B.roster,
    "B displayed marble count matches final engine state")
eq(first.view.seq, replay.view.seq, "same-seed adapters finish on the same event")
eq(first.view.winner, replay.view.winner, "same-seed adapters render the same winner")

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
    }
    for _, item in ipairs(banned) do
        ok(not source:find(item[1], 1, true), item[2])
    end
    ok(source:find('require("battle.engine")', 1, true) ~= nil,
        "adapter delegates battle execution to the canonical engine")
end

if failures == 0 then
    print(string.format("OK: %d presentation checks passed", checks))
    os.exit(0)
end

print(string.format("FAILED: %d of %d presentation checks failed", failures, checks))
os.exit(1)
