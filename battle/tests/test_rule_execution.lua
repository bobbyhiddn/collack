-- Runtime profiles are compiled from the same RuleSets shown to the player.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local ast = require("battle.rule_ast")
local effects = require("battle.effects")
local rulebook = require("battle.content.rules")
local draft = require("battle.content.draft")
local slings = require("battle.content.slings")
local shells = require("battle.content.shells")
local cores = require("battle.content.cores")
local bricks = require("battle.content.bricks")

local M = { name = "rule_execution" }

function M.run(t)
    local chip = effects.collision_profile("chip")
    t:eq(chip.damage, 1, "collision damage is compiled from its rule")
    t:eq(chip.durability_cost, 1, "shell wear is compiled from its rule")
    t:eq(effects.collision_profile("splinter").splash_behind, 1,
        "depth splash is compiled from its rule")
    t:eq(effects.release_profile("concussion").radius, 2,
        "release radius is compiled from its rule")
    t:eq(effects.release_profile(
        "scorch",
        cores.by_id.cinder_nucleus.rule_set
    ).field_duration, 24,
        "baseline release-field duration is composed into the core RuleSet")
    t:eq(effects.status_profile("poison").duration_ticks, 240,
        "status duration is compiled from its rule")
    t:eq(effects.status_profile("poison")._cadence.shell_wear.interval, 120,
        "status cadence is compiled from its rule")
    t:eq(effects.status_profile("freeze").launch_speed_multiplier, 0.72,
        "status launch modifier is compiled from its rule")
    t:eq(effects.brick_profile("magnetic").field_radius, 13,
        "field radius is compiled from its rule")
    t:eq(effects.brick_profile("magnetic").field_strength, -58,
        "field force is compiled from its rule")
    t:eq(effects.brick_profile("reflect").reflect, 1.08,
        "brick rebound strength is compiled from its rule")
    t:eq(ast.rule(
        rulebook.brick_behaviours.chain,
        "brick.chain.shell_wear"
    ).target.count, 3,
        "enemy-marble chain limit is compiled from its target contract")
    t:eq(effects.brick_profile("chain").death_splash, nil,
        "Chain has no legacy neighbouring-brick damage projection")
    t:eq(effects.brick_profile("splice").collision_splash, nil,
        "Splice has no legacy neighbouring-brick damage projection")
    t:eq(effects.brick_profile("aegis")._cadence.negate_once.charges, 1,
        "one-shot protection is compiled from charges")

    for _, item in ipairs(draft.SLINGS) do
        local runtime = slings.by_id[item.id]
        local projected = ast.project(item.rule_set)
        t:eq(runtime._rule_set_id, projected._rule_set_id,
            item.id .. " sling runtime keeps its rule identity")
        for stat, value in pairs(projected) do
            if stat:sub(1, 1) ~= "_" then
                t:eq(runtime[stat], value, item.id .. " executes " .. stat)
            end
        end
    end

    for _, item in ipairs(draft.MARBLES) do
        for _, shell_id in ipairs(item.shells) do
            t:ok(shells.by_id[shell_id].rule_set ~= nil,
                item.id .. " shell has executable canonical rules")
        end
        t:ok(cores.by_id[item.core].rule_set ~= nil,
            item.id .. " core has executable canonical rules")
    end

    for _, kit in ipairs(draft.BRICK_KITS) do
        for _, brick_id in ipairs(kit.brick_ids) do
            local definition = bricks.by_id[brick_id]
            local runtime = effects.brick_profile(definition.behaviour)
            t:eq(runtime.behaviour, definition.behaviour,
                kit.id .. " executes " .. brick_id .. " behaviour")
        end
    end

    local changed = ast.copy(rulebook.collisions.chip)
    changed.rules[1].magnitude.value = 3
    t:eq(ast.project(changed).damage, 3,
        "changing canonical magnitude changes the executable projection")
    t:eq(ast.balance(changed).lines[1].points, 9,
        "execution and accounting read the same changed node")
end

if arg and arg[0] and arg[0]:find("test_rule_execution.lua", 1, true) then
    harness.run_one(M)
end

return M
