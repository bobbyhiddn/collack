-- battle/tests/test_quality_vs_quantity.lua — real 10-vs-30 simulation proof.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local engine = require("battle.engine")
local setup = require("battle.setup")

local M = { name = "quality_vs_quantity" }

function M.run(t)
    local preview = engine.new_battle({ seed = 9125, sides = setup.quality_vs_quantity() })
    t:eq(preview.sides.A.formation.alive, 10, "quality formation starts with exactly ten bricks")
    t:eq(preview.sides.B.formation.alive, 30, "weak formation starts with exactly thirty bricks")
    t:eq(preview.sides.A.sling.id, preview.sides.B.sling.id, "both sides use the same sling")
    t:eq(#preview.sides.A.roster, #preview.sides.B.roster, "both sides use the same hand size")

    local battle, result = engine.simulate({ seed = 9125, sides = setup.quality_vs_quantity() })
    t:eq(result.outcome, "victory", "the constructed scenario reaches a simulation victory")
    t:eq(result.winner, "A", "the ten positioned quality bricks win")
    t:eq(result.reason, "bricks_destroyed", "victory comes from destroying the thirty-brick formation")
    t:eq(battle.sides.B.formation.alive, 0, "all thirty weak bricks were actually destroyed")
    t:ok(battle.sides.A.formation.alive > 0, "the quality formation survives the battle")
    t:ok(result.volleys > 1, "the assertion covers a resolved multi-volley battle")

    local replay, replay_result = engine.simulate({ seed = 9125, sides = setup.quality_vs_quantity() })
    t:eq(replay_result.winner, result.winner, "the proof replays to the same winner")
    t:eq(replay.log:text(), battle.log:text(), "the entire proof log is deterministic")
end

if arg and arg[0] and arg[0]:find("test_quality_vs_quantity.lua", 1, true) then
    harness.run_one(M)
end

return M
