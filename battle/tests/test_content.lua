-- battle/tests/test_content.lua — documented brick and sling mechanics.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local engine = require("battle.engine")
local effects = require("battle.effects")
local marble_mod = require("battle.marble")
local bricks = require("battle.content.bricks")
local slings = require("battle.content.slings")
local fixtures = require("battle.tests.fixtures")

local M = { name = "content_mechanics" }

local function chipper(lane)
    return {
        name = "Chipper",
        rarity = "common",
        core = "dull_quartz",
        shells = { "quartz_banded" },
        lane = lane,
    }
end

local function target_layout(brick_id)
    return { { ".", brick_id, "." } }
end

local function simulate_target(brick_id, opts)
    opts = opts or {}
    return engine.simulate({
        seed = opts.seed or 17,
        max_volleys = opts.max_volleys or 1,
        sides = {
            A = {
                name = "Probe",
                sling = opts.sling or fixtures.TIGHT_SLING,
                formation = fixtures.tough_wall(3),
                marbles = opts.marbles or { chipper(2) },
            },
            B = {
                name = "Target",
                sling = fixtures.TIGHT_SLING,
                formation = opts.layout or target_layout(brick_id),
                marbles = { chipper(2) },
            },
        },
    })
end

function M.run(t)
    local required = {
        defensive = { "absorb", "reflect", "regenerate", "fortify" },
        effect = { "poison", "freeze", "magnetic", "shatter" },
        utility = { "chain", "vault", "splice", "dummy" },
        rare = { "aegis", "void", "mirror", "temporal" },
    }
    local seen = {}
    for _, brick in ipairs(bricks.list) do
        seen[brick.behaviour] = brick.family
    end
    for family, behaviours in pairs(required) do
        for _, behaviour in ipairs(behaviours) do
            t:eq(seen[behaviour], family, behaviour .. " is present in the " .. family .. " family")
            t:ok(effects.brick_profile(behaviour) ~= nil, behaviour .. " resolves through shared effects")
        end
    end

    local scenarios = {
        { "basalt_absorber", "absorb" },
        { "mirror_pane", "reflect" },
        { "moss_regenerator", "regenerate" },
        {
            "granite_fortifier",
            "fortify",
            { layout = { { "granite_fortifier", "plain_block", "." } } },
        },
        { "venom_glass", "status_applied" },
        { "rime_block", "status_applied" },
        { "lodestone_block", "magnetic" },
        { "shatter_crystal", "shatter" },
        { "powder_keg", "chain_detonate" },
        { "vault_arch", "vault" },
        { "splice_node", "splice" },
        { "training_dummy", "dummy" },
        { "aegis_keystone", "aegis" },
        { "void_prism", "void" },
        { "prismatic_mirror", "mirror" },
        { "temporal_anchor", "temporal" },
    }
    for _, scenario in ipairs(scenarios) do
        local battle = simulate_target(scenario[1], scenario[3])
        t:ok(#harness.of_type(battle.log, scenario[2]) > 0,
            scenario[1] .. " produces " .. scenario[2] .. " in a real cascade")
    end

    local poisoned = simulate_target("venom_glass", { max_volleys = 2 })
    local poison_ticks = harness.select(poisoned.log, function(event)
        return event.type == "status_tick" and event.status == "poison"
    end)
    t:ok(#poison_ticks > 0, "poison persists and wears a shell on the next launch")

    local frozen = simulate_target("rime_block", { max_volleys = 2 })
    local freeze_ticks = harness.select(frozen.log, function(event)
        return event.type == "status_tick" and event.status == "freeze"
    end)
    t:ok(#freeze_ticks > 0, "freeze persists to the next launch")
    local launches = harness.of_type(frozen.log, "launch", "A")
    t:ok(#launches >= 2, "the frozen marble launched twice")
    if #launches >= 2 then
        t:eq(launches[2].momentum, math.max(0, launches[1].momentum - 1),
            "freeze reduces next-launch momentum")
    end

    local named = {
        volley = "volley",
        momentum = "momentum",
        ricochet = "ricochet",
        spread = "spread",
        precision = "precision",
        effect_amplifier = "effect_amplifier",
    }
    for id, archetype in pairs(named) do
        t:eq(slings.by_id[id].archetype, archetype, id .. " is a named archetype")
    end

    local base = marble_mod.build(chipper(2), fixtures.TIGHT_SLING, "A")
    local momentum = marble_mod.build(chipper(2), slings.by_id.momentum, "A")
    local ricochet = marble_mod.build(chipper(2), slings.by_id.ricochet, "A")
    local spread = marble_mod.build(chipper(2), slings.by_id.spread, "A")
    local precision = marble_mod.build(chipper(2), slings.by_id.precision, "A")
    local amplifier = marble_mod.build(chipper(2), slings.by_id.effect_amplifier, "A")
    t:eq(momentum.momentum, base.momentum + 3, "momentum sling adds three cascade steps")
    t:eq(ricochet.ricochet, true, "ricochet sling bends after collisions")
    t:eq(spread.scatter, 2, "spread sling has a two-lane spread")
    t:eq(precision.precision, true, "precision sling uses weak-point targeting")
    t:eq(amplifier.effect_power, 1, "effect amplifier raises collision/release power")

    local volley = engine.simulate({
        seed = 9,
        max_volleys = 1,
        sides = {
            A = {
                name = "Volley",
                sling = "volley",
                formation = fixtures.tough_wall(3),
                marbles = { chipper(1), chipper(3) },
            },
            B = {
                name = "Single",
                sling = fixtures.TIGHT_SLING,
                formation = fixtures.tough_wall(3),
                marbles = { chipper(2) },
            },
        },
    })
    t:eq(#harness.of_type(volley.log, "launch", "A"), 2,
        "volley sling commits and resolves two ordered marbles in one volley")

    local ricochet_battle = simulate_target("plain_block", { sling = "ricochet" })
    t:ok(#harness.of_type(ricochet_battle.log, "ricochet", "A") > 0,
        "ricochet sling changes an actual cascade path")

    local precision_battle = simulate_target("chalk_block", {
        sling = "precision",
        layout = { { "plain_block", ".", "chalk_block" } },
        marbles = { chipper(1) },
    })
    local precision_launch = harness.of_type(precision_battle.log, "launch", "A")[1]
    t:eq(precision_launch.target_col, 3, "precision targets a farther weak brick over a nearer tough one")

    local amplified = simulate_target("void_prism", {
        sling = "effect_amplifier",
        marbles = { fixtures.fragile(2) },
    })
    local releases = harness.of_type(amplified.log, "core_release", "A")
    t:ok(#releases > 0, "amplified marble released its core")
    if #releases > 0 then
        t:eq(releases[1].amplification, 1, "effect amplifier reaches core release mechanics")
    end
end

if arg and arg[0] and arg[0]:find("test_content.lua", 1, true) then
    harness.run_one(M)
end

return M
