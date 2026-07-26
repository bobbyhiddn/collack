-- battle/tests/run_all.lua — headless test entry point.
--
-- Run from the repository root:
--   lua5.1 battle/tests/run_all.lua
--
-- Individual files also run on their own, e.g.
--   lua5.1 battle/tests/test_determinism.lua

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

harness.run({
    require("battle.tests.test_vslice_contract"),
    require("battle.tests.test_draft_loop"),
    require("battle.tests.test_opponent_loop"),
    require("battle.tests.test_run_state"),
    require("battle.tests.test_run_controller"),
    require("battle.tests.test_run_presentation"),
    require("battle.tests.test_data_model"),
    require("battle.tests.test_event_protocol"),
    require("battle.tests.test_content"),
    require("battle.tests.test_quality_vs_quantity"),
    require("battle.tests.test_resolution"),
    require("battle.tests.test_blowback"),
    require("battle.tests.test_win_conditions"),
    require("battle.tests.test_determinism"),
    require("battle.tests.test_purity"),
})
