-- Adversarial closure for exported draft catalogs and the RuleSet/AST facade.

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
local ast = require("battle.rule_ast")
local catalog = require("battle.content.draft")
local bricks = require("battle.content.bricks")
local draft = require("battle.draft")
local run = require("battle.run")
local short_run = require("battle.short_run")
local runtime_verification = require("battle.runtime_verification")
local controller = require("run_controller")
local util = require("battle.run_util")

local M = { name = "authority_facades" }

local TABLE_EXPORTS = {
    "TAGS",
    "SLINGS",
    "MARBLES",
    "LEGACY_MARBLES",
    "ALL_MARBLES",
    "BRICK_KITS",
    "sling_by_id",
    "marble_by_id",
    "brick_kit_by_id",
    "brick_reward_pool",
    "brick_kit_for",
    "COMPREHENSION_POOL",
}

local function poison(value, seen)
    if type(value) ~= "table" then return end
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for key, item in pairs(value) do
        if type(item) == "table" then
            poison(item, seen)
        elseif type(item) == "number" then
            value[key] = item < 1 and 999 or -999
        elseif type(item) == "string" then
            value[key] = "FORGED:" .. item
        elseif type(item) == "boolean" then
            value[key] = not item
        end
    end
    value.__forged_catalog_value = true
end

local function swap(view, left, right)
    view[left], view[right] = view[right], view[left]
end

local function assert_canonical_construction(t)
    local chalk = draft.instantiate_marble(
        { content_id = "chalk_common" }, 1, "player"
    )
    local cinder = draft.instantiate_marble(
        { content_id = "cinder_legendary" }, 2, "player"
    )
    t:eq(chalk.content_id, "chalk_common",
        "common alias attacks cannot change constructed identity")
    t:eq(chalk.rarity, "common",
        "common alias attacks cannot raise constructed rarity")
    t:eq(#chalk.shells, 1,
        "common alias attacks cannot raise the one-shell cap")
    t:eq(chalk.telegraph.beads, 1,
        "common presentation retains one canonical rarity bead")
    t:eq(chalk.compatibility.max_copies, 3,
        "common construction retains its canonical copy cap")
    t:eq(#chalk.rule_set.abilities, 0,
        "common marble retains baseline-only release authority")
    t:eq(cinder.content_id, "cinder_legendary",
        "reverse alias attacks cannot lower legendary identity")
    t:eq(cinder.rarity, "legendary",
        "reverse alias attacks cannot lower legendary rarity")
    t:eq(#cinder.shells, 5,
        "legendary construction retains its five-shell authority")
    t:eq(cinder.telegraph.beads, 5,
        "legendary presentation retains five canonical rarity beads")
    t:eq(#cinder.rule_set.abilities, 1,
        "legendary construction retains its authored bonus release")

    local guard, guard_bricks = draft.instantiate_kit(
        { content_id = "guard_pair" }, 1, "player"
    )
    local splice, splice_bricks = draft.instantiate_kit(
        { content_id = "splice_keg" }, 3, "player"
    )
    t:eq(guard.content_id, "guard_pair",
        "common kit alias attacks cannot change kit identity")
    t:eq(guard.rarity, "common",
        "common kit alias attacks cannot raise kit rarity")
    t:eq(guard_bricks[1].content_id, "basalt_absorber",
        "common kit retains its first inert member")
    t:eq(guard_bricks[2].content_id, "training_dummy",
        "common kit retains its second inert member")
    t:eq(#guard_bricks[1].rule_set.abilities + #guard_bricks[2].rule_set.abilities, 0,
        "common kit cannot acquire passive-bearing members")
    t:eq(splice.content_id, "splice_keg",
        "reverse kit alias attacks cannot change rare kit identity")
    t:eq(splice.rarity, "rare",
        "reverse kit alias attacks cannot lower rare kit rarity")
    t:eq(splice_bricks[1].content_id, "splice_node",
        "Splice kit retains its canonical first member")
    t:eq(splice_bricks[2].content_id, "granite_fortifier",
        "Splice kit retains its canonical second member")

    local splice_profile = bricks.get("splice_node")
    local guard_rule = ast.rule(splice_profile.rule_set, "brick.splice.guard")
    t:eq(guard_rule.magnitude.value, 1,
        "Splice magnitude remains one after high/low projection attacks")
    t:eq(guard_rule.cadence.unit, "exchange",
        "Splice cadence unit remains canonical")
    t:eq(guard_rule.cadence.interval, 1,
        "Splice cadence interval remains one")
    t:eq(guard_rule.duration.value, 120,
        "Splice Guard duration remains 120 ticks")
    t:eq(splice_profile.telegraph.passive_ceiling, 1,
        "rare Splice passive ceiling remains one")
    t:eq(splice_profile.balance.spent, 21.12,
        "Splice balance remains canonical")
    t:eq(splice_profile.compact_copy, ast.compact(splice_profile.rule_set),
        "Splice compact copy remains an AST projection")

    local common = bricks.get("basalt_absorber")
    t:eq(common.telegraph.passive_count, 0,
        "common brick retains zero passives")
    t:eq(common.telegraph.passive_ceiling, 0,
        "common brick retains a zero-passive ceiling")
    t:eq(#common.rule_set.abilities, 0,
        "common RuleSet cannot acquire a forged passive")
end

function M.run(t)
    local baseline_exports = {}
    for _, key in ipairs(TABLE_EXPORTS) do
        baseline_exports[key] = catalog[key]
        t:neq(baseline_exports[key], catalog[key],
            key .. " returns a fresh top-level projection")
        t:ok(util.deep_equal(baseline_exports[key], catalog[key]),
            key .. " fresh projections retain equal canonical values")
    end

    local baseline_run = run.new({ run_seed = 8768 })
    local baseline_offer = util.deep_copy(baseline_run.draft.offer)
    local reward_state = run.new({ run_seed = 8768, short_run = true })
    reward_state.fight.index = 2
    local baseline_reward = assert(short_run.preview_reward_offer(reward_state))
    local baseline_evidence = runtime_verification.run()
    local baseline_model = controller.new({ run_seed = 8768 })
    local baseline_presentation = controller.project(baseline_model)

    for _, key in ipairs({
        "SCHEMA_VERSION",
        "copy",
        "validate",
        "assert_valid",
        "rule_value",
        "player_authority",
        "balance",
        "compact",
        "register",
    }) do
        t:raises(function() ast[key] = false end, "read-only",
            "AST facade rejects replacement of " .. key)
    end
    t:raises(function()
        rawset(ast, "rule_value", function() return 999 end)
    end, "table expected", "rawset cannot bypass the AST facade")
    t:raises(function()
        setmetatable(ast, {})
    end, nil, "caller cannot replace the AST facade metatable")
    t:eq(ast.SCHEMA_VERSION, 2,
        "failed schema replacement leaves validation on schema v2")

    for _, key in ipairs({
        "VERSION",
        "MARBLES",
        "marble_by_id",
        "BRICK_KITS",
        "brick_kit_by_id",
        "brick_reward_pool",
        "economy",
    }) do
        t:raises(function() catalog[key] = false end, "read-only",
            "draft facade rejects replacement of " .. key)
    end
    t:raises(function()
        rawset(catalog, "marble_by_id", {})
    end, "table expected", "rawset cannot bypass the draft catalog facade")
    t:raises(function()
        setmetatable(catalog, {})
    end, nil, "caller cannot replace the draft facade metatable")

    -- Top-level alias swaps in both directions must be accepted only by the
    -- caller-owned copy and disappear on the next catalog read.
    local sling_aliases = catalog.sling_by_id
    swap(sling_aliases, "momentum", "effect_amplifier")
    local marble_aliases = catalog.marble_by_id
    swap(marble_aliases, "chalk_common", "cinder_legendary")
    local kit_aliases = catalog.brick_kit_by_id
    swap(kit_aliases, "guard_pair", "splice_keg")
    local all_marbles = catalog.ALL_MARBLES
    all_marbles[1], all_marbles[#all_marbles] = all_marbles[#all_marbles], all_marbles[1]
    local all_kits = catalog.BRICK_KITS
    all_kits[1], all_kits[#all_kits] = all_kits[#all_kits], all_kits[1]
    local rewards = catalog.brick_reward_pool
    rewards[1], rewards[#rewards] = rewards[#rewards], rewards[1]
    local reward_aliases = catalog.brick_kit_for
    swap(reward_aliases, "basalt_absorber", "temporal_anchor")

    t:eq(catalog.sling_by_id.momentum.id, "momentum",
        "sling alias swap is isolated in both directions")
    t:eq(catalog.marble_by_id.chalk_common.id, "chalk_common",
        "common-to-legendary alias swap is isolated")
    t:eq(catalog.marble_by_id.cinder_legendary.id, "cinder_legendary",
        "legendary-to-common alias swap is isolated")
    t:eq(catalog.brick_kit_by_id.guard_pair.id, "guard_pair",
        "common-to-rare kit alias swap is isolated")
    t:eq(catalog.brick_kit_by_id.splice_keg.id, "splice_keg",
        "rare-to-common kit alias swap is isolated")
    t:eq(catalog.ALL_MARBLES[1].id, baseline_exports.ALL_MARBLES[1].id,
        "draft-list endpoint swap cannot reorder later reads")
    t:eq(catalog.BRICK_KITS[1].id, baseline_exports.BRICK_KITS[1].id,
        "kit-list endpoint swap cannot reorder later reads")
    t:eq(catalog.brick_reward_pool[1].id, baseline_exports.brick_reward_pool[1].id,
        "reward endpoint swap cannot retarget selection")
    t:eq(catalog.brick_kit_for.basalt_absorber, "guard_pair",
        "reward provenance alias swap cannot persist")

    -- Mutate every reachable table/scalar in every exported catalog surface.
    -- A new read must reproduce the complete pre-attack value byte-for-value.
    for _, key in ipairs(TABLE_EXPORTS) do
        local attacked = catalog[key]
        poison(attacked)
        t:ok(util.deep_equal(catalog[key], baseline_exports[key]),
            key .. " recursive mutation cannot poison later reads")
    end

    -- Explicit high/low mutations cover the independent rejection values and
    -- the reverse direction, including a schema-valid post-validation edit.
    local high = catalog.marble_by_id.chalk_common
    high.rarity = "legendary"
    high.rule_set.rarity = "legendary"
    high.compatibility.max_copies = 1
    high.rule_set.compatibility.max_copies = 1
    high.shells = util.deep_copy(catalog.marble_by_id.cinder_legendary.shells)
    high.core = "cinder_nucleus"
    high.telegraph.beads = 5
    high.balance.spent = 1
    high.compact_copy = "FORGED LEGENDARY COMMON"
    local high_valid = ast.validate(high.rule_set)
    t:eq(high_valid, true,
        "the exact post-validation rarity rewrite is independently schema-valid")

    local low = catalog.marble_by_id.cinder_legendary
    low.rarity = "common"
    low.rule_set.rarity = "common"
    low.compatibility.max_copies = 3
    low.rule_set.compatibility.max_copies = 3
    low.shells = { "chalk_plain" }
    low.core = "dull_quartz"
    low.telegraph.beads = 1
    low.balance.spent = 999
    low.compact_copy = "FORGED COMMON LEGENDARY"

    local splice_high = catalog.brick_kit_by_id.splice_keg
    splice_high.rarity = "common"
    splice_high.telegraph.passive_ceiling = 99
    splice_high.balance.members[1].ledger.spent = 1
    splice_high.compact_copy = "FORGED SPLICE HIGH"
    for _, rule in ipairs(splice_high.rule_set.rules) do
        if rule.id == "brick.splice.guard" then
            rule.magnitude.value = 99
            rule.cadence.interval = 99
            rule.duration.value = 999
        end
    end
    local splice_low = catalog.brick_kit_by_id.splice_keg
    splice_low.telegraph.passive_ceiling = 0
    splice_low.balance.members[1].ledger.spent = -1
    splice_low.compact_copy = "FORGED SPLICE LOW"
    for _, rule in ipairs(splice_low.rule_set.rules) do
        if rule.id == "brick.splice.guard" then
            rule.magnitude.value = 0
            rule.cadence.interval = 0
            rule.duration.value = 0
        end
    end

    local common_passive = catalog.brick_kit_by_id.guard_pair
    common_passive.rarity = "legendary"
    common_passive.telegraph.passive_ceiling = 99
    common_passive.brick_ids = { "splice_node", "granite_fortifier" }
    common_passive.rule_set.abilities[1] = {
        id = "forged_guard",
        kind = "passive",
        rule_ids = { "brick.splice.guard" },
    }

    local tier_high = ast.tier("common")
    tier_high.shell_cap = 5
    tier_high.brick_passive_groups = 99
    local tier_low = ast.tier("legendary")
    tier_low.shell_cap = 1
    tier_low.brick_passive_groups = 0
    local economy = ast.economy()
    economy.tiers.common.shell_cap = 5
    economy.tiers.legendary.shell_cap = 1
    economy.acquisition.short_run_win_1.common = 0
    economy.acquisition.short_run_win_1.legendary = 100
    t:eq(ast.tier("common").shell_cap, 1,
        "high tier projection mutation cannot raise the common shell cap")
    t:eq(ast.tier("legendary").shell_cap, 5,
        "low tier projection mutation cannot lower the legendary shell cap")
    t:eq(ast.tier("common").brick_passive_groups, 0,
        "tier projection cannot create a common brick passive")
    t:eq(ast.economy().acquisition.short_run_win_1.legendary, 0,
        "economy projection cannot inject a win-one legendary reward")

    assert_canonical_construction(t)

    local momentum = draft.instantiate_sling({ content_id = "momentum" })
    t:eq(momentum.id, "momentum",
        "sling construction ignores mutated alias projections")
    t:eq(momentum.rule_set.id, "sling.momentum",
        "sling runtime retains canonical RuleSet identity")

    local after_run = run.new({ run_seed = 8768 })
    t:ok(util.deep_equal(after_run.draft.offer, baseline_offer),
        "draft selection remains byte-identical after catalog attacks")
    local after_reward = assert(short_run.preview_reward_offer(reward_state))
    t:ok(util.deep_equal(after_reward, baseline_reward),
        "reward selection remains byte-identical after catalog/economy attacks")
    local reward_ids = {}
    for _, choice in ipairs(after_reward.choices) do
        local identity = ast.content_identity(choice)
        t:eq(reward_ids[identity], nil,
            "post-attack reward identities remain unique")
        reward_ids[identity] = true
        t:eq(choice.rule_set.availability.legacy_only, false,
            "post-attack rewards remain player-legal")
    end

    local after_evidence = runtime_verification.run()
    t:ok(util.deep_equal(after_evidence, baseline_evidence),
        "runtime and generated evidence remain identical after facade attacks")
    t:eq(after_evidence.linked_cost.cost_amount, 1,
        "validated linked-cost fixture pays exactly one integrity")
    t:eq(after_evidence.linked_cost.payoff_amount, 2,
        "validated linked-cost fixture grants exactly its scaled payoff")
    t:eq(after_evidence.linked_cost.target_selector, "setup_linked_allied_brick",
        "linked cost remains bound to its exact setup target selector")
    t:eq(after_evidence.linked_cost.charges_before, 2,
        "linked cost reports exact pre-activation cadence state")
    t:eq(after_evidence.linked_cost.charges_after, 1,
        "linked cost atomically spends exactly one charge")
    t:eq(after_evidence.linked_cost.ordered, true,
        "linked cost preserves trigger-cost-payoff atomic ordering")
    t:eq(after_evidence.splice_guard.magnitude, 1,
        "runtime Splice evidence retains one-point Guard")
    t:eq(after_evidence.splice_guard.cadence_interval, 1,
        "runtime Splice evidence retains once-per-exchange cadence")
    t:eq(after_evidence.splice_guard.duration_ticks, 120,
        "runtime Splice evidence retains exact expiry")

    local after_model = controller.new({ run_seed = 8768 })
    local after_presentation = controller.project(after_model)
    t:ok(util.deep_equal(after_presentation, baseline_presentation),
        "UI projection remains byte-identical after catalog/AST attacks")
    for _, card in ipairs(after_presentation.draft.cards) do
        t:eq(card.compact_copy, ast.compact(card.rule_set),
            card.choice_id .. " compact UI copy remains canonical")
        t:ok(util.deep_equal(card.inspection_copy, ast.expanded_lines(card.rule_set)),
            card.choice_id .. " inspection UI copy remains canonical")
        t:ok(util.deep_equal(card.balance, ast.balance(card.rule_set)),
            card.choice_id .. " UI balance remains canonical")
    end
end

if arg and arg[0] and arg[0]:find("test_authority_facades.lua", 1, true) then
    harness.run_one(M)
end

return M
