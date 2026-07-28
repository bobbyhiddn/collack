local harness = require("battle.tests.harness")
local verification = require("battle.runtime_verification")

local M = { name = "runtime_verification" }

function M.run(t)
    local evidence = verification.run()
    t:eq(evidence.schema_version, 2, "packaged evidence schema is versioned")
    t:eq(evidence.sweep.kind, "box_collision", "packaged probe uses a physical AABB contact")
    t:ok(evidence.sweep.speed >= 240, "packaged probe records a high-speed impact")
    t:ok(evidence.sweep.toi > 0 and evidence.sweep.toi < 1 / 120,
        "packaged probe records a within-tick swept TOI")
    t:ok(evidence.sweep.reflected and not evidence.sweep.tunneled,
        "packaged probe records rebound without tunnelling")
    t:eq(evidence.sweep.substeps, 1, "packaged probe uses one authoritative tick")
    t:ok(evidence.blowback.allied, "packaged probe records allied blowback")
    t:ok(evidence.blowback.enemy, "packaged probe records enemy blowback")
    t:ok(evidence.blowback.ally_dx < 0, "packaged probe records allied displacement")
    t:ok(evidence.blowback.enemy_dx > 0, "packaged probe records enemy displacement")
    t:eq(evidence.linked_cost.cost_amount, 1,
        "packaged proof records the exact allied integrity cost")
    t:eq(evidence.linked_cost.target_selector, "setup_linked_allied_brick",
        "packaged proof records the dedicated canonical selector")
    t:eq(evidence.linked_cost.target_relation, "allied",
        "packaged proof records the exact target relation")
    t:eq(evidence.linked_cost.charges_before, 2,
        "packaged proof records canonical cadence charges")
    t:eq(evidence.linked_cost.charges_after, 1,
        "packaged proof records atomic charge consumption")
    t:eq(evidence.linked_cost.payoff_amount, 2,
        "packaged proof records the exact canonical payoff")
    t:ok(evidence.linked_cost.ordered,
        "packaged proof records trigger-cost-payoff order")
    t:ok(evidence.linked_cost.compact_copy:find(
        "COST 1 linked allied integrity", 1, true
    ) ~= nil, "packaged proof carries generated cost copy")
end

if arg and arg[0] and arg[0]:find("test_runtime_verification.lua", 1, true) then
    harness.run_one(M)
end

return M
