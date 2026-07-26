local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local opponent = require("battle.opponent")
local run = require("battle.run")
local util = require("battle.run_util")
local fixtures = require("battle.tests.run_fixtures")

local M = { name = "opponent_loop" }

local function signature(spec)
    local parts = { spec.recipe_id, spec.sling_id }
    for _, brick in ipairs(spec.bricks) do parts[#parts + 1] = brick.content_id end
    for _, marble in ipairs(spec.marbles) do parts[#parts + 1] = marble.content_id end
    return table.concat(parts, "|")
end

function M.run(t)
    local recipes = opponent.recipes()
    t:eq(#recipes, 3, "the slice ships three asymmetric CPU recipes")
    local required = {
        bastion = { bricks = 10, marbles = 3 },
        fuse_garden = { bricks = 6, marbles = 4 },
        glass_cannon = { bricks = 5, marbles = 3 },
    }
    for _, recipe in ipairs(recipes) do
        t:ok(required[recipe.id] ~= nil, recipe.id .. " is a documented recipe")
        t:eq(recipe.brick_count, required[recipe.id].bricks,
            recipe.id .. " owns its intentional brick count")
        t:eq(recipe.marble_count, required[recipe.id].marbles,
            recipe.id .. " owns its intentional bag count")
        t:eq(#recipe.scout_tags, 2, recipe.id .. " exposes two honest scout tags")

        local built = opponent.build(700 + recipe.brick_count, recipe.id)
        local valid, message = opponent.validate(built)
        t:ok(valid, message or (recipe.id .. " validates"))
        t:eq(built.recipe_id, recipe.id, recipe.id .. " can be selected explicitly for tests")
        t:eq(#built.bricks, recipe.brick_count, recipe.id .. " build preserves brick count")
        t:eq(#built.marbles, recipe.marble_count, recipe.id .. " build preserves marble count")
        t:eq(#built.bag_order, #built.marbles, recipe.id .. " bag matches its roster")
        t:eq(#built.formation, 3, recipe.id .. " uses the local three-row transform")
        for row = 1, 3 do
            t:eq(#built.formation[row], 7, recipe.id .. " row " .. row .. " has seven cells")
        end
    end

    local one = opponent.build(98765)
    local again = opponent.build(98765)
    t:ok(util.deep_equal(one, again), "same opponent seed builds identical content and placement")
    one.formation[1][1] = "mutated"
    t:eq(again.formation[1][1] == "mutated", false,
        "opponent builds do not share mutable formation tables")

    local recipe_names, variants = {}, {}
    for seed = 1, 90 do
        local spec = opponent.build(seed)
        recipe_names[spec.recipe_id] = true
        variants[signature(spec)] = true
        local valid, message = opponent.validate(spec)
        t:ok(valid, message or ("seed " .. seed .. " opponent validates"))
        t:eq(#spec.scout_tags, 2, "seed " .. seed .. " has two scout tags")

        local roster, bag = {}, {}
        for _, marble in ipairs(spec.marbles) do roster[marble.uid] = true end
        for _, uid in ipairs(spec.bag_order) do
            t:ok(roster[uid], "seed " .. seed .. " bag uses a roster marble")
            t:eq(bag[uid], nil, "seed " .. seed .. " bag has no duplicate")
            bag[uid] = true
        end
    end
    t:eq(#util.sorted_keys(recipe_names), 3, "seed selection reaches all three opponent identities")
    t:ok(#util.sorted_keys(variants) >= 9,
        "same-value substitutions create opponent diversity within recipes")

    local state = fixtures.draft_all(run.new({ run_seed = 222 }))
    t:eq(opponent.is_mirror(state.player, state.opponent), false,
        "a completed player draft is not mirrored by the prebuilt CPU")
    t:eq(#state.player.bricks, 8, "player keeps its eight-brick rule")
    t:neq(#state.opponent.bricks, #state.player.bricks,
        "this seeded CPU demonstrates intentional formation asymmetry")

    local invalid = opponent.build(31, "bastion")
    invalid.bag_order[2] = invalid.bag_order[1]
    local duplicate_ok, duplicate_message = opponent.validate(invalid)
    t:eq(duplicate_ok, false, "duplicate CPU bag entries are rejected")
    t:eq(duplicate_message, "opponent bag contains a duplicate marble",
        "CPU bag error is actionable")

    invalid = opponent.build(31, "bastion")
    local placed_uid = invalid.formation[1][1]
    invalid.formation[3][7] = placed_uid
    local overlap_ok, overlap_message = opponent.validate(invalid)
    t:eq(overlap_ok, false, "overlapping CPU formation entries are rejected")
    t:eq(overlap_message, "opponent brick is placed twice",
        "CPU overlap error is actionable")
end

if arg and arg[0] and arg[0]:find("test_opponent_loop.lua", 1, true) then
    harness.run_one(M)
end

return M
