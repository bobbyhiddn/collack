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

local TIER_CASES = {
    {
        rarity = "common", marble_id = "chalk_common", rank = 1,
        shell_cap = 1, bonus_release_groups = 0, bonus_release_mcu = 0,
        brick_passive_groups = 0, brick_passive_mcu = 0,
        brick_copy_cap = 4, marble_copy_cap = 3, authored_releases = 0,
    },
    {
        rarity = "uncommon", marble_id = "geode_uncommon", rank = 2,
        shell_cap = 2, bonus_release_groups = 1, bonus_release_mcu = 2,
        brick_passive_groups = 1, brick_passive_mcu = 2,
        brick_copy_cap = 3, marble_copy_cap = 2, authored_releases = 1,
    },
    {
        rarity = "rare", marble_id = "warden_rare", rank = 3,
        shell_cap = 3, bonus_release_groups = 1, bonus_release_mcu = 4,
        brick_passive_groups = 1, brick_passive_mcu = 4,
        brick_copy_cap = 2, marble_copy_cap = 2, authored_releases = 1,
    },
    {
        rarity = "epic", marble_id = "lodestone_epic", rank = 4,
        shell_cap = 4, bonus_release_groups = 2, bonus_release_mcu = 6,
        brick_passive_groups = 2, brick_passive_mcu = 6,
        brick_copy_cap = 1, marble_copy_cap = 1, authored_releases = 1,
    },
    {
        rarity = "legendary", marble_id = "cinder_legendary", rank = 5,
        shell_cap = 5, bonus_release_groups = 2, bonus_release_mcu = 8,
        brick_passive_groups = 2, brick_passive_mcu = 8,
        brick_copy_cap = 1, marble_copy_cap = 1, authored_releases = 1,
    },
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

local function assert_tier_contracts(t, prefix)
    for _, expected in ipairs(TIER_CASES) do
        local tier = assert(ast.tier(expected.rarity))
        t:eq(tier.rank, expected.rank,
            prefix .. " " .. expected.rarity .. " rank remains canonical")
        t:eq(tier.shell_cap, expected.shell_cap,
            prefix .. " " .. expected.rarity .. " shell cap remains canonical")
        t:eq(tier.bonus_release_groups, expected.bonus_release_groups,
            prefix .. " " .. expected.rarity .. " release allowance remains canonical")
        t:eq(tier.bonus_release_mcu, expected.bonus_release_mcu,
            prefix .. " " .. expected.rarity .. " release MCU remains canonical")
        t:eq(tier.brick_passive_groups, expected.brick_passive_groups,
            prefix .. " " .. expected.rarity .. " passive allowance remains canonical")
        t:eq(tier.brick_passive_mcu, expected.brick_passive_mcu,
            prefix .. " " .. expected.rarity .. " passive MCU remains canonical")
        t:eq(tier.brick_copy_cap, expected.brick_copy_cap,
            prefix .. " " .. expected.rarity .. " brick copy cap remains canonical")
        t:eq(tier.marble_copy_cap, expected.marble_copy_cap,
            prefix .. " " .. expected.rarity .. " marble copy cap remains canonical")

        local marble = draft.instantiate_marble(
            { content_id = expected.marble_id }, expected.rank, "player"
        )
        local summary = ast.ability_summary(marble.rule_set)
        t:eq(marble.rarity, expected.rarity,
            prefix .. " " .. expected.marble_id .. " rarity remains canonical")
        t:eq(#marble.shells, expected.shell_cap,
            prefix .. " " .. expected.marble_id .. " has its exact shell cap")
        t:eq(marble.telegraph.beads, expected.rank,
            prefix .. " " .. expected.marble_id .. " beads remain canonical")
        t:eq(marble.telegraph.shell_cap, expected.shell_cap,
            prefix .. " " .. expected.marble_id .. " presents its exact shell cap")
        t:eq(marble.telegraph.passive_ceiling, expected.bonus_release_groups,
            prefix .. " " .. expected.marble_id .. " presents its release ceiling")
        t:eq(marble.telegraph.mcu_ceiling, expected.bonus_release_mcu,
            prefix .. " " .. expected.marble_id .. " presents its release MCU")
        t:eq(marble.compatibility.max_copies, expected.marble_copy_cap,
            prefix .. " " .. expected.marble_id .. " copy cap remains canonical")
        t:eq(summary.count, expected.authored_releases,
            prefix .. " " .. expected.marble_id .. " release count remains canonical")
        t:ok(summary.count <= expected.bonus_release_groups,
            prefix .. " " .. expected.marble_id .. " stays within release allowance")
        t:ok(summary.mcu <= expected.bonus_release_mcu,
            prefix .. " " .. expected.marble_id .. " stays within release MCU")
        if expected.rarity == "common" then
            t:eq(summary.count, 0,
                prefix .. " common remains baseline-only")
        else
            t:ok(summary.count > 0,
                prefix .. " " .. expected.rarity .. " retains a bonus release")
        end
        t:eq(marble.compact_copy, ast.compact(marble.rule_set),
            prefix .. " " .. expected.marble_id .. " compact copy remains canonical")
        t:ok(util.deep_equal(marble.inspection_copy,
            ast.expanded_lines(marble.rule_set)),
            prefix .. " " .. expected.marble_id .. " inspection remains canonical")
        t:ok(util.deep_equal(marble.balance, ast.balance(marble.rule_set)),
            prefix .. " " .. expected.marble_id .. " balance remains canonical")
        t:eq(marble.rule_set.availability.player_draft, true,
            prefix .. " " .. expected.marble_id .. " remains player-legal")
        t:eq(marble.rule_set.availability.legacy_only, false,
            prefix .. " " .. expected.marble_id .. " remains non-legacy")
    end
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
    assert_tier_contracts(t, "before projection attacks")

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

    -- Every adjacent rarity alias pair is attacked in both directions. Each
    -- lookup is its own value, so none of the swaps may survive into either
    -- endpoint of a later read.
    for index = 1, #TIER_CASES - 1 do
        local lower = TIER_CASES[index]
        local higher = TIER_CASES[index + 1]
        local aliases = catalog.marble_by_id
        swap(aliases, lower.marble_id, higher.marble_id)
        t:eq(catalog.marble_by_id[lower.marble_id].id, lower.marble_id,
            lower.rarity .. "-to-" .. higher.rarity .. " alias swap is isolated")
        t:eq(catalog.marble_by_id[higher.marble_id].id, higher.marble_id,
            higher.rarity .. "-to-" .. lower.rarity .. " alias swap is isolated")
    end

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

    -- For all five rarity representatives, attack independent projections in
    -- both directions: inflate them to a forged five-shell/passive-bearing
    -- legendary and collapse them to a forged one-shell/common baseline.
    -- Availability, balance, and copy/presentation caches are attacked too.
    local legendary_projection = catalog.marble_by_id.cinder_legendary
    for _, expected in ipairs(TIER_CASES) do
        local raised = catalog.marble_by_id[expected.marble_id]
        raised.rarity = "legendary"
        raised.rule_set.rarity = "legendary"
        raised.shells = util.deep_copy(legendary_projection.shells)
        raised.rule_set.abilities = util.deep_copy(
            legendary_projection.rule_set.abilities
        )
        raised.telegraph.beads = 5
        raised.telegraph.shell_cap = 5
        raised.telegraph.passive_ceiling = 99
        raised.telegraph.mcu_ceiling = 99
        raised.compatibility.max_copies = 1
        raised.rule_set.compatibility.max_copies = 1
        raised.balance.spent = -999
        raised.availability.player_draft = false
        raised.rule_set.availability.player_draft = false

        local lowered = catalog.marble_by_id[expected.marble_id]
        lowered.rarity = "common"
        lowered.rule_set.rarity = "common"
        lowered.shells = { "chalk_plain" }
        lowered.rule_set.abilities = {}
        lowered.telegraph.beads = 1
        lowered.telegraph.shell_cap = 1
        lowered.telegraph.passive_ceiling = 0
        lowered.telegraph.mcu_ceiling = 0
        lowered.compatibility.max_copies = 3
        lowered.rule_set.compatibility.max_copies = 3
        lowered.balance.spent = 999
        lowered.availability.legacy_only = true
        lowered.rule_set.availability.legacy_only = true
    end

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

    -- Every rule_ast and draft economy tier view is independently attacked in
    -- both numerical directions, including all shell, release, passive, and
    -- copy allowances. The rarity order and reward weights are detached too.
    for _, expected in ipairs(TIER_CASES) do
        local tier_high = ast.tier(expected.rarity)
        local tier_low = ast.tier(expected.rarity)
        local ast_economy_high = ast.economy()
        local ast_economy_low = ast.economy()
        local draft_economy_high = catalog.economy()
        local draft_economy_low = catalog.economy()
        for _, field in ipairs({
            "rank", "shell_cap", "bonus_release_groups", "bonus_release_mcu",
            "brick_passive_groups", "brick_passive_mcu", "brick_copy_cap",
            "marble_copy_cap",
        }) do
            tier_high[field] = 99
            tier_low[field] = 0
            ast_economy_high.tiers[expected.rarity][field] = 99
            ast_economy_low.tiers[expected.rarity][field] = 0
            draft_economy_high.tiers[expected.rarity][field] = 99
            draft_economy_low.tiers[expected.rarity][field] = 0
        end
        for acquisition_id in pairs(ast_economy_high.acquisition) do
            ast_economy_high.acquisition[acquisition_id][expected.rarity] = 999
            ast_economy_low.acquisition[acquisition_id][expected.rarity] = 0
            draft_economy_high.acquisition[acquisition_id][expected.rarity] = 999
            draft_economy_low.acquisition[acquisition_id][expected.rarity] = 0
        end
    end
    local reversed_order = ast.rarity_order()
    for index = 1, math.floor(#reversed_order / 2) do
        swap(reversed_order, index, #reversed_order - index + 1)
    end
    local canonical_order = ast.rarity_order()
    for index, expected in ipairs(TIER_CASES) do
        t:eq(canonical_order[index], expected.rarity,
            "rarity-order projection mutation cannot move " .. expected.rarity)
    end
    t:eq(ast.economy().acquisition.short_run_win_1.legendary, 0,
        "economy projection cannot inject a win-one legendary reward")

    assert_canonical_construction(t)
    assert_tier_contracts(t, "after high/low projection attacks")

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
