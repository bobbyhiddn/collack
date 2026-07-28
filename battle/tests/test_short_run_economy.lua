local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../../src/?.lua",
    here .. "/../?.lua",
    "./?.lua",
    "./src/?.lua",
    package.path,
}, ";")

local draft = require("battle.draft")
local harness = require("battle.tests.harness")
local fixtures = require("battle.tests.short_run_fixtures")
local ast = require("battle.rule_ast")
local run = require("battle.run")
local short_run = require("battle.short_run")
local util = require("battle.run_util")

local M = { name = "short_run_economy" }

local function kinds(offer, out)
    out = out or {}
    for _, choice in ipairs(offer.choices) do out[choice.operation.kind] = true end
    return out
end

local function choice_of_kind(offer, kind)
    for _, choice in ipairs(offer.choices or {}) do
        if choice.operation.kind == kind then return choice end
    end
    return nil
end

local function add_marble(state, id)
    local index = state.next_uid.marble
    local marble = draft.instantiate_marble({ content_id = id }, index, "player")
    state.next_uid.marble = index + 1
    state.player.marbles[#state.player.marbles + 1] = marble
    state.setup.bag_order[#state.setup.bag_order + 1] = marble.uid
end

local function add_brick(state, kit_id, brick_id)
    local index = state.next_uid.brick
    local brick = draft.instantiate_brick(kit_id, brick_id, index, "player")
    state.next_uid.brick = index + 1
    state.player.bricks[#state.player.bricks + 1] = brick
end

function M.run(t)
    local base = run.new({ run_seed = 9125, short_run = true })
    local base_offer = assert(short_run.preview_reward_offer(base))
    local coverage = kinds(base_offer)
    t:ok(coverage.add_marble, "sparse economy can add a marble")
    t:ok(coverage.add_brick, "sparse economy can add a brick")
    t:ok(coverage.replace_brick, "sparse economy can reshape an existing brick")
    local reward_ids = {}
    for _, choice in ipairs(base_offer.choices) do
        local identity = ast.content_identity(choice)
        t:eq(reward_ids[identity], nil,
            "reward offer contains each canonical content identity once")
        reward_ids[identity] = true
    end
    local repeated_offer = assert(short_run.preview_reward_offer(base))
    t:ok(util.deep_equal(base_offer, repeated_offer),
        "fixed run seed reproduces the unique reward offer exactly")

    local tampered_offer_state = util.deep_copy(base)
    tampered_offer_state.phase = "draft"
    tampered_offer_state.draft.offer = util.deep_copy(base_offer)
    tampered_offer_state.draft.offer.choices[2].rule_set =
        util.deep_copy(tampered_offer_state.draft.offer.choices[1].rule_set)
    tampered_offer_state.draft.offer.choices[2].content_id =
        tampered_offer_state.draft.offer.choices[1].content_id
    local tampered_result, tampered_error = run.dispatch(tampered_offer_state, {
        kind = "choose_offer",
        offer_id = tampered_offer_state.draft.offer.offer_id,
        choice_id = tampered_offer_state.draft.offer.choices[1].choice_id,
    })
    t:eq(tampered_result, nil, "duplicate reward-offer tampering fails closed")
    t:eq(tampered_error and tampered_error.code, "reward_authority_changed",
        "duplicate reward-offer tampering reports canonical authority failure")

    local remove_state = util.deep_copy(base)
    add_marble(remove_state, "geode_uncommon")
    remove_state.fight.index = 2
    local remove_offer = assert(short_run.preview_reward_offer(remove_state))
    kinds(remove_offer, coverage)
    t:ok(coverage.remove_marble, "three-marble bag can offer meaningful thinning")
    t:ok(coverage.reshape_sling, "final refit can reshape the sling macro rule")

    local replace_state = util.deep_copy(base)
    replace_state.fight.index = 2
    local replace_offer = assert(short_run.preview_reward_offer(replace_state))
    kinds(replace_offer, coverage)
    t:ok(coverage.replace_marble, "two-marble bag can offer a full marble replacement")

    local authority_state = run.new({ run_seed = 9301, short_run = true })
    authority_state.fight.index = 2
    local canonical_offer = assert(short_run.preview_reward_offer(authority_state))
    local canonical_replace = assert(choice_of_kind(canonical_offer, "replace_marble"))
    t:eq(canonical_replace.operation.target_uid, "player-m01",
        "canonical accounting selects the lower-spend marble")
    t:ok(util.deep_equal(
        canonical_replace.operation.target_authority,
        ast.player_authority(authority_state.player.marbles[1].rule_set)
    ), "replacement records the target's canonical identity, copy, and accounting")
    t:ok(util.deep_equal(
        canonical_replace.causal_attribution.target_authority,
        canonical_replace.operation.target_authority
    ), "visible causal attribution records the exact targeting authority")

    local shadow_mutation = util.deep_copy(authority_state)
    shadow_mutation.player.marbles[1].draft_value = 1000
    shadow_mutation.player.marbles[2].draft_value = -1000
    shadow_mutation.player.marbles[1].balance.spent = 999
    shadow_mutation.player.marbles[2].balance.spent = -999
    shadow_mutation.player.marbles[1].compact_copy = "shadow copy"
    shadow_mutation.player.marbles[1].inspection_copy = { "shadow inspection" }
    local shadow_offer = assert(short_run.preview_reward_offer(shadow_mutation))
    local shadow_replace = assert(choice_of_kind(shadow_offer, "replace_marble"))
    t:eq(shadow_replace.operation.target_uid, canonical_replace.operation.target_uid,
        "mutable draft and cached projections cannot change replacement behavior")
    t:ok(util.deep_equal(
        shadow_replace.operation.target_authority,
        canonical_replace.operation.target_authority
    ), "mutable projections cannot drift target identity, copy, or accounting")
    t:eq(shadow_replace.operation_copy, canonical_replace.operation_copy,
        "mutable projections cannot drift player-facing operation copy")

    local rule_mutation = util.deep_copy(authority_state)
    for _, rule in ipairs(rule_mutation.player.marbles[1].rule_set.rules) do
        if rule.visibility ~= "internal" and rule.operation.stat == "damage" then
            rule.magnitude.value = 3
            break
        end
    end
    local rule_offer = assert(short_run.preview_reward_offer(rule_mutation))
    local rule_replace = assert(choice_of_kind(rule_offer, "replace_marble"))
    t:eq(rule_replace.operation.target_uid, "player-m02",
        "an executable structured-rule change can change replacement behavior")
    local selected_target = rule_mutation.player.marbles[2]
    t:ok(util.deep_equal(
        rule_replace.operation.target_authority,
        ast.player_authority(selected_target.rule_set)
    ), "structured-rule behavior carries matching identity, copy, and accounting")

    local stale_state = util.deep_copy(authority_state)
    stale_state.phase = "draft"
    stale_state.draft.offer = util.deep_copy(canonical_offer)
    for _, rule in ipairs(stale_state.player.marbles[1].rule_set.rules) do
        if rule.visibility ~= "internal" and rule.operation.stat == "damage" then
            rule.magnitude.value = 3
            break
        end
    end
    local stale_result, stale_error = run.dispatch(stale_state, {
        kind = "choose_offer",
        offer_id = stale_state.draft.offer.offer_id,
        choice_id = canonical_replace.choice_id,
    })
    t:eq(stale_result, nil,
        "an offered replacement cannot execute after target authority changes")
    t:eq(stale_error and stale_error.details and stale_error.details.reason,
        "target_authority_changed",
        "stale targeting fails with an explicit canonical-authority reason")

    local repair_state = util.deep_copy(base)
    local broken = table.remove(repair_state.player.bricks, 2)
    repair_state.workshop.broken_bricks = {
        { fight_index = 1, brick = util.deep_copy(broken), cell = nil },
    }
    repair_state.fight.index = 2
    local repair_offer = assert(short_run.preview_reward_offer(repair_state))
    kinds(repair_offer, coverage)
    t:ok(coverage.repair_brick, "casualty creates an exact repair operation")

    for _, kind in ipairs({
        "add_marble",
        "add_brick",
        "replace_marble",
        "replace_brick",
        "repair_brick",
        "remove_marble",
        "reshape_sling",
    }) do
        t:ok(coverage[kind], "economy exposes typed operation " .. kind)
    end

    local capped = util.deep_copy(base)
    add_marble(capped, "geode_uncommon")
    add_marble(capped, "warden_rare")
    add_brick(capped, "living_aegis", "moss_regenerator")
    add_brick(capped, "venom_rime", "venom_glass")
    add_brick(capped, "shatter_keg", "powder_keg")
    t:eq(#capped.player.marbles, 4, "fixture reaches four-marble cap")
    t:eq(#capped.player.bricks, 6, "fixture reaches six-brick cap")
    local capped_offer = assert(short_run.preview_reward_offer(capped))
    kinds(capped_offer, coverage)
    t:eq(#capped_offer.choices, 3, "capped roster still receives three legal choices")
    t:ok(coverage.remove_brick, "cap pressure can offer meaningful brick removal")
    for _, choice in ipairs(capped_offer.choices) do
        t:ok(choice.operation.kind ~= "add_marble",
            "cap pressure replaces illegal marble acquisition")
        t:ok(choice.operation.kind ~= "add_brick",
            "cap pressure replaces illegal brick acquisition")
    end

    capped.phase = "draft"
    capped.draft.offer = capped_offer
    for index, choice in ipairs(capped_offer.choices) do
        local cloned = util.deep_copy(capped)
        local applied, apply_error = run.dispatch(cloned, {
            kind = "choose_offer",
            offer_id = cloned.draft.offer.offer_id,
            choice_id = choice.choice_id,
        })
        t:ok(applied ~= nil, apply_error and apply_error.message
            or ("capped choice " .. index .. " is legal"))
        if applied then
            t:ok(#applied.state.player.marbles <= 4,
                "capped choice cannot exceed marble cap")
            t:ok(#applied.state.player.bricks <= 6,
                "capped choice cannot exceed brick cap")
        end
    end

    local first = short_run.preview_reward_offer(
        run.new({ run_seed = 7001, short_run = true })
    )
    local second = short_run.preview_reward_offer(
        run.new({ run_seed = 7001, short_run = true })
    )
    local varied = short_run.preview_reward_offer(
        run.new({ run_seed = 7002, short_run = true })
    )
    t:ok(util.deep_equal(first, second), "same seed reproduces exact economy offer")
    local left_ids, right_ids = {}, {}
    for _, choice in ipairs(first.choices) do left_ids[#left_ids + 1] = choice.content_id end
    for _, choice in ipairs(varied.choices) do right_ids[#right_ids + 1] = choice.content_id end
    t:ok(not util.deep_equal(left_ids, right_ids),
        "adjacent run seeds vary curated reward content without changing rules")

    local attrition = run.new({ run_seed = 81, short_run = true })
    attrition = fixtures.to_battle(attrition)
    local casualty = attrition.player.bricks[1]
    attrition = fixtures.complete(attrition, { destroyed_uids = { casualty.uid } })
    t:eq(#attrition.player.bricks, 2, "casualty-only attrition removes destroyed brick")
    t:eq(#attrition.workshop.broken_bricks, 1,
        "casualty persists instead of silently healing")
    t:eq(attrition.workshop.broken_bricks[1].brick.content_id, casualty.content_id,
        "repair inventory retains canonical content identity")
end

if arg and arg[0] and arg[0]:find("test_short_run_economy.lua", 1, true) then
    harness.run_one(M)
end

return M
