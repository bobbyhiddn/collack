local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local contract = require("battle.vslice_contract")
local run = require("battle.run")
local draft = require("battle.draft")
local content = require("battle.content.draft")
local util = require("battle.run_util")

local M = { name = "draft_loop" }

local function choose(state, index)
    local offer = state.draft.offer
    local choice = offer.choices[index or 1]
    local result, command_error = run.dispatch(state, {
        kind = "choose_offer",
        offer_id = offer.offer_id,
        choice_id = choice.choice_id,
    })
    assert(result, command_error and command_error.message or "choice failed")
    return result.state
end

local function has_values(list)
    return type(list) == "table" and #list > 0
end

function M.run(t)
    local summary = draft.catalog_summary()
    t:eq(summary.slings, 3, "the slice exposes exactly three supported slings")
    t:eq(summary.marbles, 6, "the comprehension pool exposes six approved marbles")
    t:eq(summary.brick_kits, 8, "all eight initial positional kit ideas ship")
    t:eq(summary.comprehension_pool, 17, "the approved pool remains exactly seventeen items")
    t:eq(summary.legacy_marbles, 6, "six CPU recipe marbles stay quarantined from offers")
    t:ok(summary.brick_archetypes >= 18, "kits draw from the complete brick vocabulary")
    t:ok(summary.tags >= 10, "synergy vocabulary is broad enough to describe builds")

    for _, sling in ipairs(content.SLINGS) do
        t:ok(has_values(sling.mechanics), sling.id .. " has readable mechanics")
        t:ok(has_values(sling.tags), sling.id .. " has synergy tags")
        t:eq(type(sling.draft_value), "number", sling.id .. " has a comparable draft value")
        t:eq(type(sling.art_id), "string", sling.id .. " has a presentation art ID")
    end
    for _, marble in ipairs(content.MARBLES) do
        t:ok(has_values(marble.shells), marble.id .. " exposes ordered shells")
        t:eq(type(marble.core), "string", marble.id .. " exposes its core")
        t:eq(type(marble.role), "string", marble.id .. " exposes a physical role")
        t:ok(has_values(marble.mechanics), marble.id .. " has mechanics copy")
        t:ok(has_values(marble.tags), marble.id .. " has tags")
        t:eq(type(marble.draft_value), "number", marble.id .. " has draft value")
    end
    for _, kit in ipairs(content.BRICK_KITS) do
        t:eq(#kit.brick_ids, 2, kit.id .. " contains two bricks")
        t:ok(has_values(kit.mechanics), kit.id .. " explains both behaviours")
        t:ok(has_values(kit.tags), kit.id .. " has synergy tags")
        t:eq(type(kit.suggested_placement), "string", kit.id .. " suggests relative placement")
    end

    local first = run.new({ run_seed = 9125 })
    local same = run.new({ run_seed = 9125 })
    t:ok(util.deep_equal(first.draft.offer, same.draft.offer),
        "same seed produces the same first offer")
    t:ok(util.deep_equal(first.opponent, same.opponent),
        "same seed produces the same prebuilt opponent")
    t:eq(first.domain_seeds.battle, same.domain_seeds.battle,
        "same seed preserves the battle domain")

    local expected = {
        "sling",
        "marble", "marble", "marble", "marble",
        "brick_kit", "brick_kit", "brick_kit", "brick_kit",
    }
    local state = first
    local opponent_before = util.deep_copy(state.opponent)
    local battle_seed_before = state.domain_seeds.battle
    local picked_marbles, picked_kits = {}, {}
    for offer_index, category in ipairs(expected) do
        local offer = state.draft.offer
        t:eq(offer.category, category, "offer " .. offer_index .. " has the required category")
        t:eq(#offer.choices, contract.DRAFT.OFFER_SIZE,
            "offer " .. offer_index .. " contains three real choices")
        local offer_ok, offer_error = contract.validate_offer(offer)
        t:ok(offer_ok, offer_error or ("offer " .. offer_index .. " validates"))

        local seen, minimum, maximum = {}, math.huge, -math.huge
        local shared, introduced = false, false
        for _, choice in ipairs(offer.choices) do
            t:eq(seen[choice.choice_id], nil, "choice IDs are unique in offer " .. offer_index)
            seen[choice.choice_id] = true
            minimum = math.min(minimum, choice.draft_value)
            maximum = math.max(maximum, choice.draft_value)
            shared = shared or #choice.synergy.matched > 0
            introduced = introduced or #choice.synergy.introduced > 0
            t:ok(has_values(choice.tag_metadata), choice.name .. " projects readable tag metadata")
            t:ok(type(choice.details) == "table", choice.name .. " exposes inspectable details")
        end
        t:ok(maximum - minimum <= 4, "offer " .. offer_index .. " stays in one value band")
        if offer_index > 1 then
            t:ok(shared, "offer " .. offer_index .. " contains a current-build synergy")
            t:ok(introduced, "offer " .. offer_index .. " contains a new direction")
        end

        local selected = offer.choices[2]
        if category == "marble" then
            t:eq(picked_marbles[selected.content_id], nil,
                "drafted marble blueprint does not repeat")
            picked_marbles[selected.content_id] = true
        elseif category == "brick_kit" then
            t:eq(picked_kits[selected.content_id], nil, "drafted kit does not repeat")
            picked_kits[selected.content_id] = true
        end
        state = choose(state, 2)
    end

    t:eq(state.phase, "setup", "ninth choice advances to setup")
    t:eq(state.player.sling.id, state.draft.picks.sling.content_id,
        "the selected sling becomes an individual loadout item")
    t:eq(#state.player.marbles, 4, "four selected marble blueprints become four instances")
    t:eq(#state.player.bricks, 8, "four selected kits become eight brick instances")
    t:eq(#state.setup.bag_order, 4, "the drafted marble order seeds the editable bag")
    t:ok(util.deep_equal(state.opponent, opponent_before),
        "draft draws cannot alter the already-built opponent")
    t:eq(state.domain_seeds.battle, battle_seed_before,
        "draft draws cannot consume the battle seed stream")

    local marble_uids, brick_uids = {}, {}
    for _, marble in ipairs(state.player.marbles) do
        t:eq(marble_uids[marble.uid], nil, "player marble instances have unique stable IDs")
        marble_uids[marble.uid] = true
    end
    for _, brick in ipairs(state.player.bricks) do
        t:eq(brick_uids[brick.uid], nil, "player brick instances have unique stable IDs")
        brick_uids[brick.uid] = true
    end

    local build_a = run.new({ run_seed = 404 })
    local build_b = run.new({ run_seed = 404 })
    while build_a.phase == "draft" do build_a = choose(build_a, 1) end
    while build_b.phase == "draft" do build_b = choose(build_b, 3) end
    t:eq(util.deep_equal(build_a.player, build_b.player), false,
        "choice paths produce different valid individual loadouts")
    t:eq(#build_a.player.marbles, #build_b.player.marbles,
        "different choice paths preserve required loadout counts")
    t:eq(#build_a.player.bricks, #build_b.player.bricks,
        "different choice paths preserve required kit counts")

    local offer_signatures = {}
    for seed = 1, 18 do
        local seeded = run.new({ run_seed = seed })
        seeded = choose(seeded, 1)
        local ids = {}
        for _, choice in ipairs(seeded.draft.offer.choices) do ids[#ids + 1] = choice.content_id end
        offer_signatures[table.concat(ids, ",")] = true
    end
    t:ok(#util.sorted_keys(offer_signatures) >= 3,
        "different seeds produce multiple meaningful marble offers")
end

if arg and arg[0] and arg[0]:find("test_draft_loop.lua", 1, true) then
    harness.run_one(M)
end

return M
