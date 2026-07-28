-- battle/tests/test_data_model.lua — marble/shell/core/brick data model rules.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local marble_mod = require("battle.marble")
local formation_mod = require("battle.formation")
local cores = require("battle.content.cores")
local bricks = require("battle.content.bricks")
local slings = require("battle.content.slings")
local fixtures = require("battle.tests.fixtures")

local M = { name = "data_model" }

function M.run(t)
    -- Rarity caps, exactly as the spec states them.
    t:eq(marble_mod.SHELL_CAP.common, 1, "common cap")
    t:eq(marble_mod.SHELL_CAP.uncommon, 2, "uncommon cap")
    t:eq(marble_mod.SHELL_CAP.rare, 3, "rare cap")
    t:eq(marble_mod.SHELL_CAP.epic, 4, "epic cap")
    t:eq(marble_mod.SHELL_CAP.legendary, 5, "legendary cap")

    -- Shells are ordered, outermost first.
    local built = marble_mod.build(fixtures.sturdy(1), slings.by_id.precision, "A")
    t:eq(#built.shells, 3, "rare marble carries 3 shells")
    t:eq(built.shells[1].mineral, "granite", "shells[1] is the outermost shell")
    t:eq(marble_mod.outer_shell(built).mineral, "granite", "outer_shell agrees")
    t:eq(built.shells[3].mineral, "jade", "shells[3] is the innermost shell")

    -- Over the cap is rejected.
    t:raises(function()
        marble_mod.build({
            name = "Overstuffed", rarity = "common",
            core = "dull_quartz", shells = { "chalk_plain", "jade_lattice" },
        }, slings.by_id.precision, "A")
    end, "at most 1 shell", "a common marble may not carry two shells")

    -- Every marble has at least one shell; a bare core is not a marble.
    t:raises(function()
        marble_mod.build({ name = "Naked", rarity = "rare", core = "dull_quartz", shells = {} },
            slings.by_id.precision, "A")
    end, "no shells", "a marble with no shells is rejected")

    -- Common cores get baseline blowback only — no release effect.
    for _, core in ipairs(cores.list) do
        if core.min_rarity == "common" then
            t:eq(core.release, nil, "common core " .. core.id .. " has no release effect")
        else
            t:neq(core.release, nil, "core " .. core.id .. " above common has a release effect")
        end
    end
    t:raises(function()
        marble_mod.build({ name = "Cheat", rarity = "common", core = "shrapnel_geode", shells = { "chalk_plain" } },
            slings.by_id.precision, "A")
    end, "needs rarity uncommon", "a common marble may not carry an uncommon core")

    -- Trajectory sign convention: negative left, positive right, zero straight.
    t:eq(cores.by_id.cant_pebble.trajectory < 0, true, "cant_pebble biases left")
    t:eq(cores.by_id.skew_flint.trajectory > 0, true, "skew_flint biases right")
    t:eq(cores.by_id.dull_quartz.trajectory, 0, "dull_quartz flies straight")

    -- The sling modifies every marble in hand.
    local durable = marble_mod.build(fixtures.sturdy(1), slings.by_id.tuned_sling, "A")
    t:eq(durable.shells[1].durability, 4, "sling adds durability to every shell")
    t:eq(durable.shells[3].durability, 3, "including the innermost")
    local heavy = marble_mod.build(fixtures.sturdy(1), slings.by_id.heavy_sling, "A")
    t:eq(heavy.damage_bonus, 1, "sling adds damage")
    local raker = marble_mod.build(fixtures.sturdy(1), slings.by_id.raker_sling, "A")
    t:eq(raker.momentum, 5, "sling adds momentum")
    t:eq(raker.core.trajectory, 1, "sling aim shifts the core's trajectory")

    -- Brick archetypes: behaviour, not just hit points, and a do-nothing control.
    local seen = {}
    for _, brick in ipairs(bricks.list) do seen[brick.behaviour] = true end
    t:ok(seen.absorb, "an absorb archetype exists")
    t:ok(seen.reflect, "a reflect archetype exists")
    t:ok(seen.chain, "a chain archetype exists")
    t:ok(seen.inert, "an inert control archetype exists")

    -- Formation geometry.
    local formation = formation_mod.build(fixtures.single_brick(5, 3))
    t:eq(formation.cols, 5, "formation width")
    t:eq(formation.alive, 1, "one live brick")
    t:ok(formation_mod.brick_at(formation, 1, 3) ~= nil, "brick sits where it was placed")
    t:eq(formation_mod.brick_at(formation, 1, 2), nil, "empty cells stay empty")
    t:raises(function() formation_mod.build({ { "plain_block", "." }, { "." } }) end,
        "expected 2", "ragged layouts are rejected")
end

if arg and arg[0] and arg[0]:find("test_data_model.lua", 1, true) then
    harness.run_one(M)
end

return M
