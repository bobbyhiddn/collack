-- Mechanical battle events carry stable rule attribution and generated callouts.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../../src/?.lua",
    here .. "/../?.lua",
    "./?.lua",
    "./src/?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local engine = require("battle.engine")
local fixtures = require("battle.tests.fixtures")
local ast = require("battle.rule_ast")
local presentation = require("presentation")

local M = { name = "rule_attribution" }

function M.run(t)
    local battle = engine.new_battle({ seed = 9125, sides = fixtures.default_matchup() })
    engine.run(battle)

    local attributed = {}
    for _, event in ipairs(battle.log.events) do
        if event.rule_id then attributed[#attributed + 1] = event end
    end
    t:ok(#attributed > 0, "the simulator emits mechanically attributed events")

    local seen = {}
    for _, event in ipairs(attributed) do
        seen[event.type] = true
        t:ok(ast.resolve(event.rule_id) ~= nil,
            event.rule_id .. " resolves to its canonical node")
        t:ok(type(event.rule_source) == "string", event.rule_id .. " names its source")
        t:ok(type(event.rule_operation) == "string", event.rule_id .. " names its operation")
        t:ok(type(event.rule_target) == "string", event.rule_id .. " names its selector")
        local callout = ast.callout(event)
        t:ok(type(callout) == "string" and #callout > 0,
            event.rule_id .. " generates a battle callout")
        t:eq(presentation.event_text(event), callout,
            event.rule_id .. " presentation consumes the generated callout")
    end

    t:ok(seen.launch, "sling launches are attributed")
    t:ok(seen.collision, "shell collisions are attributed")
    t:ok(seen.core_release, "core releases are attributed")

    local replay_attributed = 0
    for _, event in ipairs(battle.recording.events) do
        if event.rule_id then replay_attributed = replay_attributed + 1 end
    end
    t:eq(replay_attributed, #attributed,
        "recorded replay events preserve all attribution")

    local repeated = engine.new_battle({ seed = 9125, sides = fixtures.default_matchup() })
    engine.run(repeated)
    t:eq(repeated.log:text(), battle.log:text(),
        "attributed event streams remain deterministic")
end

if arg and arg[0] and arg[0]:find("test_rule_attribution.lua", 1, true) then
    harness.run_one(M)
end

return M
