-- Adversarial lock -> handoff -> engine coverage for canonical marble selectors.

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
local draft = require("battle.draft")
local engine = require("battle.engine")
local opponent = require("battle.opponent")
local setup_rules = require("battle.setup_rules")
local short = require("battle.short_run")
local fixtures = require("battle.tests.short_run_fixtures")
local util = require("battle.run_util")

local M = { name = "marble_setup_authority" }

local function placed_state()
    return fixtures.place_unplaced(short.new({
        run_seed = 9125,
        short_run = true,
    }))
end

local function replace_first(state, content_id)
    local entity = draft.instantiate_marble(
        { content_id = content_id },
        1,
        "player"
    )
    entity.uid = state.player.marbles[1].uid
    state.player.marbles[1] = entity
    state.setup.bag_order[1] = entity.uid
    return entity
end

local function lock(state)
    return short.dispatch(state, { kind = "lock_setup" })
end

local function valid_handoff(content_id)
    local state = placed_state()
    local entity = replace_first(state, content_id)
    for index = 2, #state.player.marbles do
        if state.player.marbles[index].content_id == content_id then
            local replacement_id = content_id == "chalk_common"
                and "quartz_common"
                or "chalk_common"
            local replacement = draft.instantiate_marble(
                { content_id = replacement_id },
                index,
                "player"
            )
            replacement.uid = state.player.marbles[index].uid
            state.player.marbles[index] = replacement
        end
    end
    local result, command_error = lock(state)
    assert(result, command_error and command_error.message)
    return short.battle_handoff(result.state), entity
end

local function live_by_uid(battle, uid, side_id)
    for _, entity in ipairs(battle.sides[side_id or "A"].roster) do
        if entity.uid == uid then return entity end
    end
    error("missing live marble " .. tostring(uid))
end

local function total_durability(entity)
    local total = 0
    for _, shell in ipairs(entity.shells) do total = total + shell.durability end
    return total
end

local function has_error(errors, code, fragment)
    for _, item in ipairs(errors or {}) do
        if item.code == code
            and (not fragment or tostring(item.message):find(fragment, 1, true)) then
            return true
        end
    end
    return false
end

local function assert_setup_rejects(t, label, content_id, mutate, fragment)
    local state = placed_state()
    local entity = replace_first(state, content_id)
    mutate(entity)
    local valid, errors = short.validate_setup_state(state)
    t:eq(valid, false, label .. " fails setup validation")
    t:ok(has_error(errors, "marble_authority_mismatch", fragment),
        label .. " reports the canonical selector divergence")
    local result, command_error = lock(state)
    t:eq(result, nil, label .. " fails closed before handoff")
    t:eq(command_error and command_error.code, "setup_invalid",
        label .. " reports setup_invalid at lock")
end

local function assert_handoff_rejects(t, label, content_id, mutate, fragment)
    local handoff = valid_handoff(content_id)
    mutate(handoff.player.marbles[1])
    t:raises(function()
        engine.new(handoff)
    end, fragment, label .. " fails closed at the engine boundary")
end

local function mutate_rule(rule_set, rule_id, value)
    local changed = ast.copy(rule_set)
    for _, rule in ipairs(changed.rules) do
        if rule.id == rule_id then
            (rule.magnitude or rule.duration).value = value
            return changed
        end
    end
    error("missing rule " .. tostring(rule_id))
end

local function rule_ids(rule_set)
    return ast.player_authority(rule_set).rule_ids
end

function M.run(t)
    -- Canonical baseline for the four independently reported counterexamples.
    local baseline_handoff, baseline_def = valid_handoff("geode_uncommon")
    local baseline_battle = engine.new(baseline_handoff)
    local baseline_live = live_by_uid(baseline_battle, baseline_def.uid)
    t:eq(baseline_live.shells[1].id, "obsidian_shard",
        "canonical geode keeps obsidian outermost")
    t:eq(baseline_live.shells[1].collision, "cleave",
        "canonical geode outer shell cleaves")
    t:eq(total_durability(baseline_live), 3,
        "canonical geode has exact ordered-shell durability")

    assert_setup_rejects(t, "reordered geode", "geode_uncommon", function(entity)
        entity.shells = { "jade_lattice", "obsidian_shard" }
    end, "shells diverges")
    assert_handoff_rejects(t, "post-lock reordered geode", "geode_uncommon",
        function(entity)
            entity.shells = { "jade_lattice", "obsidian_shard" }
        end, "shells diverges")

    assert_setup_rejects(t, "duplicated jade", "geode_uncommon", function(entity)
        entity.shells = { "jade_lattice", "jade_lattice" }
    end, "shells diverges")
    assert_handoff_rejects(t, "post-lock duplicated jade", "geode_uncommon",
        function(entity)
            entity.shells = { "jade_lattice", "jade_lattice" }
        end, "shells diverges")

    assert_setup_rejects(t, "legendary five-shell chalk", "chalk_common", function(entity)
        entity.rarity = "legendary"
        entity.shells = {
            "chalk_plain",
            "chalk_plain",
            "chalk_plain",
            "chalk_plain",
            "chalk_plain",
        }
    end, "diverges from canonical")
    assert_handoff_rejects(t, "post-lock legendary five-shell chalk", "chalk_common",
        function(entity)
            entity.rarity = "legendary"
            entity.shells = {
                "chalk_plain",
                "chalk_plain",
                "chalk_plain",
                "chalk_plain",
                "chalk_plain",
            }
        end, "diverges from canonical")

    assert_setup_rejects(t, "injected lane", "chalk_common", function(entity)
        entity.lane = 7
    end, "unknown selector or field lane")
    assert_handoff_rejects(t, "post-lock injected lane", "chalk_common",
        function(entity) entity.lane = 7 end,
        "lane must derive from canonical bag order")

    -- The catalog's selector projections are not a mutable shadow authority:
    -- component identities and shell order derive from the RuleSet itself.
    local geode_catalog = catalog.marble_by_id.geode_uncommon
    geode_catalog.shells = { "jade_lattice", "obsidian_shard" }
    local shell_isolated = draft.instantiate_marble(
        { content_id = "geode_uncommon" }, 1, "catalog"
    )
    t:ok(util.deep_equal(shell_isolated.shells, {
        "obsidian_shard", "jade_lattice",
    }), "mutable catalog shell reordering is isolated from live construction")

    geode_catalog.core = "dull_quartz"
    local core_isolated = draft.instantiate_marble(
        { content_id = "geode_uncommon" }, 1, "catalog"
    )
    t:eq(core_isolated.core, "shrapnel_geode",
        "mutable catalog core replacement is isolated from live construction")

    geode_catalog.rarity = "legendary"
    local rarity_isolated = draft.instantiate_marble(
        { content_id = "geode_uncommon" }, 1, "catalog"
    )
    t:eq(rarity_isolated.rarity, "uncommon",
        "mutable catalog rarity replacement cannot raise the shell cap")

    -- Missing, extra, replaced, duplicated, unknown, sparse, and reordered
    -- shell selectors all die at both mutable boundaries.
    local shell_attacks = {
        { "missing shell", {} },
        { "extra shell", { "obsidian_shard", "jade_lattice", "chalk_plain" } },
        { "replaced shell", { "obsidian_shard", "quartz_banded" } },
        { "duplicate outer shell", { "obsidian_shard", "obsidian_shard" } },
        { "unknown shell", { "obsidian_shard", "unknown_shell" } },
        { "invalid reverse order", { "jade_lattice", "obsidian_shard" } },
        { "invalid sparse order", { [1] = "obsidian_shard", [3] = "jade_lattice" } },
    }
    for _, attack in ipairs(shell_attacks) do
        assert_setup_rejects(t, attack[1], "geode_uncommon", function(entity)
            entity.shells = util.deep_copy(attack[2])
        end, "shells diverges")
        assert_handoff_rejects(t, "post-lock " .. attack[1], "geode_uncommon",
            function(entity) entity.shells = util.deep_copy(attack[2]) end,
            "shells diverges")
    end

    for _, attack in ipairs({
        { "replaced core", "dull_quartz" },
        { "unknown core", "unknown_core" },
        { "missing core", nil },
    }) do
        assert_setup_rejects(t, attack[1], "geode_uncommon",
            function(entity) entity.core = attack[2] end,
            "core diverges")
        assert_handoff_rejects(t, "post-lock " .. attack[1], "geode_uncommon",
            function(entity) entity.core = attack[2] end,
            "core diverges")
    end
    for _, rarity in ipairs({ "common", "rare", "epic", "legendary", "unknown" }) do
        assert_setup_rejects(t, "mutated rarity " .. rarity, "geode_uncommon",
            function(entity) entity.rarity = rarity end,
            "rarity diverges")
    end

    assert_setup_rejects(t, "unknown content identity", "chalk_common",
        function(entity) entity.content_id = "unknown_marble" end,
        "unknown marble content identity")
    assert_handoff_rejects(t, "post-lock missing content identity", "chalk_common",
        function(entity) entity.content_id = nil end,
        "missing canonical content identity")
    assert_setup_rejects(t, "content identity replacement", "chalk_common",
        function(entity) entity.content_id = "quartz_common" end,
        "diverges from canonical")

    for _, field in ipairs({ "id", "core_id", "shell_ids", "rarity_id", "selector" }) do
        assert_setup_rejects(t, "selector alias " .. field, "chalk_common",
            function(entity) entity[field] = entity.content_id end,
            "unknown selector or field " .. field)
        assert_handoff_rejects(t, "post-lock selector alias " .. field, "chalk_common",
            function(entity) entity[field] = entity.content_id end,
            "unknown selector or field " .. field)
    end

    for _, attack in ipairs({
        {
            label = "opponent core replacement",
            mutate = function(entity) entity.core = "unknown_core" end,
            error = "core diverges",
        },
        {
            label = "opponent shell duplication",
            mutate = function(entity)
                entity.shells = { entity.shells[1], entity.shells[1] }
            end,
            error = "shells diverges",
        },
        {
            label = "opponent rarity replacement",
            mutate = function(entity) entity.rarity = "legendary" end,
            error = "rarity diverges",
        },
        {
            label = "opponent lane injection",
            mutate = function(entity) entity.lane = 7 end,
            error = "lane must derive from canonical bag order",
        },
    }) do
        local handoff = valid_handoff("chalk_common")
        attack.mutate(handoff.opponent.marbles[1])
        t:raises(function()
            engine.new(handoff)
        end, attack.error, attack.label .. " fails at the shared engine boundary")
    end

    local tampered_opponent = opponent.build(9125)
    tampered_opponent.marbles[1].core = "unknown_core"
    local opponent_valid, opponent_error = opponent.validate(tampered_opponent)
    t:eq(opponent_valid, false, "opponent validation rejects selector tampering")
    t:ok(tostring(opponent_error):find("canonical authority", 1, true) ~= nil,
        "opponent validation reports the shared authority boundary")

    -- Every field projected into setup or consumed downstream is compared, not
    -- just the four selectors from the initial report.
    local adjacent_attacks = {
        name = function(entity) entity.name = entity.name .. " tampered" end,
        role = function(entity) entity.role = entity.role .. " tampered" end,
        mechanics = function(entity) entity.mechanics[1] = "tampered" end,
        compact_copy = function(entity) entity.compact_copy = "tampered" end,
        inspection_copy = function(entity) entity.inspection_copy[1] = "tampered" end,
        rule_set = function(entity) entity.rule_set.id = "tampered.rule_set" end,
        compatibility = function(entity)
            entity.compatibility.max_copies = entity.compatibility.max_copies + 1
        end,
        balance = function(entity) entity.balance.spent = entity.balance.spent + 1 end,
        tags = function(entity) entity.tags[1] = "tampered" end,
        art_id = function(entity) entity.art_id = entity.art_id .. "_tampered" end,
    }
    for field, mutate in pairs(adjacent_attacks) do
        assert_setup_rejects(t, "adjacent field " .. field, "chalk_common",
            mutate, field .. " diverges")
        assert_handoff_rejects(t, "post-lock adjacent field " .. field, "chalk_common",
            mutate, field .. " diverges")
    end

    local metatable_state = placed_state()
    setmetatable(metatable_state.player.marbles[1], { __index = {} })
    local metatable_valid, metatable_errors = short.validate_setup_state(metatable_state)
    t:eq(metatable_valid, false, "metatable selector aliases fail closed")
    t:ok(has_error(
        metatable_errors,
        "marble_authority_mismatch",
        "plain canonical value"
    ), "metatable alias reports the plain-value guard")

    -- A mutation made after an earlier successful validation is checked again
    -- by both handoff construction and lock.
    local post_validation = placed_state()
    local was_valid = short.validate_setup_state(post_validation)
    t:eq(was_valid, true, "control setup validates before mutation")
    post_validation.player.marbles[1].core = "skew_flint"
    t:raises(function()
        setup_rules.player_spec({
            sling_id = post_validation.player.sling.id,
            sling = post_validation.player.sling,
            marbles = post_validation.player.marbles,
            bricks = post_validation.player.bricks,
            formation = post_validation.setup.formation,
            bag_order = post_validation.setup.bag_order,
        }, post_validation.player.name)
    end, "marble_authority_mismatch",
    "handoff construction rechecks post-validation mutation")
    local post_result, post_error = lock(post_validation)
    t:eq(post_result, nil, "post-validation mutation cannot lock")
    t:eq(post_error and post_error.code, "setup_invalid",
        "post-validation mutation fails closed before battle")

    -- Exercise the handoff materializer independently of its preceding
    -- validation call so weakening either defense is mutation-visible.
    local materializer_state = placed_state()
    materializer_state.player.marbles[1].core = "skew_flint"
    local original_validate = setup_rules.validate
    setup_rules.validate = function() return true, {} end
    t:raises(function()
        setup_rules.player_spec({
            sling_id = materializer_state.player.sling.id,
            sling = materializer_state.player.sling,
            marbles = materializer_state.player.marbles,
            bricks = materializer_state.player.bricks,
            formation = materializer_state.setup.formation,
            bag_order = materializer_state.setup.bag_order,
        }, materializer_state.player.name)
    end, "core diverges",
    "handoff materialization independently rejects a mutable selector")
    setup_rules.validate = original_validate

    -- All six playable marble cards make an exact canonical trip through
    -- lock, handoff, construction, initial physics identity, and lane derivation.
    local marble_cards = 0
    for _, item in ipairs(catalog.MARBLES) do
        marble_cards = marble_cards + 1
        local handoff, setup_entity = valid_handoff(item.id)
        local handed = handoff.player.marbles[1]
        local canonical = draft.canonical_marble(setup_entity)
        t:ok(util.deep_equal(handed, canonical),
            item.id .. " handoff is freshly materialized from canonical authority")
        t:eq(handed.lane, nil, item.id .. " handoff carries no lane override")
        local battle = engine.new(handoff)
        local live = live_by_uid(battle, setup_entity.uid)
        t:eq(live.content_id, item.id, item.id .. " keeps canonical content identity")
        t:eq(live.rarity, item.rarity, item.id .. " keeps canonical rarity")
        t:eq(live.core.id, item.core, item.id .. " constructs canonical core")
        t:eq(#live.shells, #item.shells, item.id .. " constructs exact shell cardinality")
        for index, shell_id in ipairs(item.shells) do
            t:eq(live.shells[index].id, shell_id,
                item.id .. " keeps canonical shell order " .. index)
        end
        t:eq(live.lane, 2, item.id .. " derives first launch lane from bag order")
        t:eq(
            ast.player_authority(handed.rule_set).canonical_rule_set,
            ast.player_authority(item.rule_set).canonical_rule_set,
            item.id .. " preserves exact canonical RuleSet bytes"
        )
    end
    t:eq(marble_cards, 6, "all six playable marble cards cross the live boundary")

    local all_marble_variants = 0
    for _, item in ipairs(catalog.ALL_MARBLES) do
        all_marble_variants = all_marble_variants + 1
        local handoff = valid_handoff("chalk_common")
        local target = handoff.opponent.marbles[1]
        local entity = draft.instantiate_marble(
            { content_id = item.id },
            all_marble_variants,
            "opponent"
        )
        entity.uid = target.uid
        handoff.opponent.marbles[1] = entity
        local battle = engine.new(handoff)
        local live = live_by_uid(battle, entity.uid, "B")
        t:eq(live.content_id, item.id,
            item.id .. " crosses product engine construction canonically")
        t:eq(live.core.id, item.core,
            item.id .. " keeps its RuleSet-derived core in the engine")
        t:eq(#live.shells, #item.shells,
            item.id .. " keeps RuleSet-derived shell cardinality in the engine")
        for index, shell_id in ipairs(item.shells) do
            t:eq(live.shells[index].id, shell_id,
                item.id .. " keeps RuleSet-derived engine shell order " .. index)
        end
    end
    t:eq(all_marble_variants, 12,
        "all playable and quarantined CPU marble variants share the boundary")

    -- The complete 17-item packet retains exact identity/copy/accounting
    -- projections, and all 16 brick variants retain exact reward attribution.
    local item_count = 0
    for _, entry in ipairs(catalog.COMPREHENSION_POOL) do
        item_count = item_count + 1
        local item = entry.category == "sling" and catalog.sling_by_id[entry.id]
            or entry.category == "marble" and catalog.marble_by_id[entry.id]
            or catalog.brick_kit_by_id[entry.id]
        local authority = ast.player_authority(item.rule_set)
        t:eq(item.compact_copy, authority.compact_copy,
            entry.category .. ":" .. entry.id .. " keeps canonical compact copy")
        t:ok(util.deep_equal(item.inspection_copy, authority.inspection_copy),
            entry.category .. ":" .. entry.id .. " keeps canonical inspection")
        if entry.category == "brick_kit" then
            t:eq(item.balance.packaging_only, true,
                entry.category .. ":" .. entry.id .. " keeps member-only accounting")
            t:eq(#item.balance.members, 2,
                entry.category .. ":" .. entry.id .. " reports both member ledgers")
        else
            t:ok(util.deep_equal(item.balance, authority.balance),
                entry.category .. ":" .. entry.id .. " keeps canonical accounting")
        end
    end
    t:eq(item_count, 17, "the live authority proof covers all seventeen items")

    local brick_variants = 0
    for _, kit in ipairs(catalog.BRICK_KITS) do
        for _, brick_id in ipairs(kit.brick_ids) do
            brick_variants = brick_variants + 1
            local entity = draft.instantiate_brick(
                kit.id,
                brick_id,
                brick_variants,
                "authority"
            )
            local reward = short.reward_rule_authority({
                kind = "add_brick",
                kit_id = kit.id,
                content_id = brick_id,
            }, entity)
            t:ok(util.deep_equal(reward.rule_ids, rule_ids(entity.rule_set)),
                kit.id .. "/" .. brick_id .. " attributes only the applied brick")
        end
    end
    t:eq(brick_variants, 16, "all sixteen brick variants retain exact attribution")

    -- Even a schema-valid edit to an exported RuleSet is only a caller-owned
    -- projection. It cannot become canonical mechanics, copy, identity, or
    -- accounting after validation. Invalid edits are isolated in the same way.
    local geode = catalog.marble_by_id.geode_uncommon
    local original_rules = geode.rule_set
    local edited_rules = mutate_rule(
        original_rules,
        "shell.jade_lattice.durability",
        2.001
    )
    local edited_valid, edited_errors = ast.validate(edited_rules)
    t:eq(edited_valid, true,
        "small canonical RuleSet edit remains valid: " .. table.concat(edited_errors or {}, "; "))
    if edited_valid then
        geode.rule_set = edited_rules
        local edited_ok, edited_error = pcall(function()
            local edited_entity = draft.instantiate_marble(
                { content_id = "geode_uncommon" },
                1,
                "edited"
            )
            local before = ast.player_authority(original_rules)
            local after = ast.player_authority(edited_entity.rule_set)
            t:eq(after.canonical_rule_set, before.canonical_rule_set,
                "validated projection edit cannot change canonical identity")
            t:eq(table.concat(after.inspection_copy, "\n"),
                table.concat(before.inspection_copy, "\n"),
                "validated projection edit cannot change inspection copy")
            t:ok(util.deep_equal(after.balance, before.balance),
                "validated projection edit cannot change balance accounting")
            t:ok(util.deep_equal(edited_entity.inspection_copy, before.inspection_copy),
                "fresh entity copy derives from protected canonical authority")
            t:ok(util.deep_equal(edited_entity.balance, before.balance),
                "fresh entity accounting derives from protected canonical authority")
            local live = require("battle.marble").build(
                edited_entity,
                draft.instantiate_sling({ content_id = "momentum" }),
                "A",
                true
            )
            t:eq(live.shells[2].durability, 2,
                "validated projection edit cannot reach live shell mechanics")
        end)
        geode.rule_set = original_rules
        if not edited_ok then error(edited_error) end
    end

    local over_budget = mutate_rule(
        original_rules,
        "shell.jade_lattice.durability",
        999
    )
    local over_budget_valid = ast.validate(over_budget)
    t:eq(over_budget_valid, false,
        "over-budget caller projection remains invalid under canonical validation")
    geode.rule_set = over_budget
    local protected_entity = draft.instantiate_marble(
        { content_id = "geode_uncommon" }, 1, "invalid"
    )
    t:eq(protected_entity.shells[2], "jade_lattice",
        "budget-invalid projection cannot poison later canonical construction")
end

if arg and arg[0]
    and arg[0]:find("test_marble_setup_authority.lua", 1, true) then
    harness.run_one(M)
end

return M
