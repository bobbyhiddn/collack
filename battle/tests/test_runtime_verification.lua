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
    local guard = evidence.splice_guard
    t:eq(guard.recipe_id, "glass_cannon",
        "packaged Splice proof uses the shipped Glass Cannon recipe")
    t:eq(guard.battle_seed, 9125,
        "packaged Splice proof carries the exact deterministic seed")
    t:eq(guard.source_rule_set_id, "brick.splice_node",
        "packaged Splice proof carries canonical source RuleSet identity")
    t:eq(guard.rule_id, "brick.splice.guard",
        "packaged Splice proof carries canonical Guard rule identity")
    t:eq(guard.ability_id, "splice_guard",
        "packaged Splice proof carries canonical ability identity")
    t:eq(guard.magnitude, 1, "packaged Splice proof records one Guard")
    t:eq(guard.cadence_unit, "exchange",
        "packaged Splice proof records exchange cadence")
    t:eq(guard.cadence_interval, 1,
        "packaged Splice proof records once-per-exchange cadence")
    t:eq(guard.duration_ticks, 120,
        "packaged Splice proof records canonical duration")
    t:eq(guard.applied_count, 3,
        "real Glass Cannon layout gives Guard to three adjacent allies")
    t:eq(guard.expired_count, 2,
        "two untouched adjacent Guards expire")
    t:eq(guard.visual_frame.sides.B.name, "Glass Cannon",
        "packaged Splice screenshot frame is the real shipped recipe")
    t:eq(guard.visual_guard_count, 2,
        "packaged Splice screenshot frame visibly retains two Guards")
    t:eq(guard.visual_frame.tick, guard.visual_frame_tick,
        "packaged Splice screenshot tick is explicitly bound")
    local stages = guard.stages
    t:eq(#stages, 4, "packaged Splice proof has four causal stages")
    t:eq(stages[1].type, "splice_triggered",
        "real hostile collision emits the Splice trigger")
    t:eq(stages[2].type, "guard_applied",
        "Splice trigger emits Guard application")
    t:eq(stages[3].type, "guard_prevented",
        "Guard intercepts hostile damage")
    t:eq(stages[4].type, "guard_expired",
        "unspent Guard emits expiry")
    t:ok(stages[1].event_id < stages[2].event_id
        and stages[2].event_id < stages[3].event_id
        and stages[3].event_id < stages[4].event_id,
        "Splice Guard proof remains causally ordered")
    t:eq(stages[3].requested_damage, 2,
        "Guard proof records requested hostile damage")
    t:eq(stages[3].applied_damage, 1,
        "Guard proof records damage after prevention")
    t:ok(guard.trigger_collision_event_id < stages[1].event_id
        and stages[2].event_id < guard.prevention_collision_event_id
        and guard.prevention_collision_event_id < stages[3].event_id,
        "Splice trigger and prevention retain both physical collision roots")
    t:eq(stages[4].tick - stages[1].tick, 120,
        "unspent Guard expires exactly 120 canonical ticks after trigger")
end

if arg and arg[0] and arg[0]:find("test_runtime_verification.lua", 1, true) then
    harness.run_one(M)
end

return M
