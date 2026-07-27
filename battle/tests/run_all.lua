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
    require("battle.tests.test_rule_schema"),
    require("battle.tests.test_rule_copy"),
    require("battle.tests.test_rule_execution"),
    require("battle.tests.test_rule_attribution"),
    require("battle.tests.test_rule_compatibility"),
    require("battle.tests.test_rule_migration"),
    require("battle.tests.test_short_run_state"),
    require("battle.tests.test_short_run_economy"),
    require("battle.tests.test_short_run_save_replay"),
    require("battle.tests.test_vslice_contract"),
    require("battle.tests.test_draft_loop"),
    require("battle.tests.test_opponent_loop"),
    require("battle.tests.test_run_state"),
    require("battle.tests.test_run_controller"),
    require("battle.tests.test_run_presentation"),
    require("battle.tests.test_data_model"),
    require("battle.tests.test_event_protocol"),
    require("battle.tests.test_physics"),
    require("battle.tests.test_continuous_battle"),
    require("battle.tests.test_runtime_verification"),
    require("battle.tests.test_determinism"),
    require("battle.tests.test_full_run_integration"),
    require("battle.tests.test_purity"),
})
