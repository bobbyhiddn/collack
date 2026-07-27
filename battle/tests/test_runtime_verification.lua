local harness = require("battle.tests.harness")
local verification = require("battle.runtime_verification")

local M = { name = "runtime_verification" }

function M.run(t)
    local evidence = verification.run()
    t:eq(evidence.schema_version, 1, "packaged evidence schema is versioned")
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
end

if arg and arg[0] and arg[0]:find("test_runtime_verification.lua", 1, true) then
    harness.run_one(M)
end

return M
