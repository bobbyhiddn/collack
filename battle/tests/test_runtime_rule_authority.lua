-- Mutation probes for runtime RuleSet authority and exact reward membership.

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
local rulebook = require("battle.content.rules")
local catalog = require("battle.content.draft")
local slings = require("battle.content.slings")
local cores = require("battle.content.cores")
local shells = require("battle.content.shells")
local bricks = require("battle.content.bricks")
local effects = require("battle.effects")
local draft = require("battle.draft")
local marble = require("battle.marble")
local formation = require("battle.formation")
local physics = require("battle.physics")
local engine = require("battle.engine")
local short = require("battle.short_run")
local run = require("battle.run")
local fixtures = require("battle.tests.short_run_fixtures")
local util = require("battle.run_util")

local M = { name = "runtime_rule_authority" }

local function mutate_rule(rule_set, rule_id, value)
    local changed = ast.copy(rule_set)
    for _, rule in ipairs(changed.rules) do
        if rule.id == rule_id then
            (rule.magnitude or rule.duration).value = value
            return changed
        end
    end
    error("missing mutation rule: " .. tostring(rule_id))
end

local function ids_as_set(ids)
    local out = {}
    for _, id in ipairs(ids or {}) do out[id] = (out[id] or 0) + 1 end
    return out
end

local function contains_error(errors, code)
    for _, item in ipairs(errors or {}) do
        if item.code == code then return true end
    end
    return false
end

local function measured_field_velocity(profile)
    local world = physics.new({
        width = 40,
        height = 40,
        max_speed = 2000,
        linear_damping = 1,
    })
    local body = world:add_body({
        id = "probe",
        x = 25,
        y = 20,
        radius = 1,
        mass = 1,
    })
    world:add_field({
        id = "release",
        kind = "radial",
        x = 20,
        y = 20,
        radius = 10,
        strength = profile.field_release_strength,
        falloff = false,
    })
    world:drain_events()
    world:step(physics.FIXED_DT)
    return body.vx
end

local function cache_rule_shadow(rule_set, rule_id, value)
    return mutate_rule(rule_set, rule_id, value)
end

function M.run(t)
    -- Valid edits execute and change the same authority; over-budget edits
    -- fail before a runtime profile can exist.
    local baseline = rulebook.releases.baseline
    local eleven = mutate_rule(baseline, "release.baseline.field_strength", 11)
    local before = ast.player_authority(baseline)
    local after = ast.player_authority(eleven)
    local eleven_profile = effects.release_profile("baseline", eleven)
    t:eq(eleven_profile.field_release_strength, 11,
        "valid 10-to-11 edit compiles from its RuleSet")
    t:neq(before.canonical_rule_set, after.canonical_rule_set,
        "valid edit changes canonical identity bytes")
    t:neq(table.concat(before.inspection_copy, "\n"),
        table.concat(after.inspection_copy, "\n"),
        "valid edit changes generated inspection copy")
    t:neq(before.balance.spent, after.balance.spent,
        "valid edit changes balance accounting")
    t:ok(measured_field_velocity(eleven_profile) > measured_field_velocity(
        effects.release_profile("baseline", baseline)
    ), "valid edit changes fixed-step mechanics")

    local extreme = mutate_rule(baseline, "release.baseline.field_strength", 999)
    local valid, errors = ast.validate(extreme)
    t:eq(valid, false, "10-to-999 edit is rejected by canonical validation")
    t:ok(table.concat(errors or {}, "; "):find("exceeds rarity budget", 1, true),
        "10-to-999 edit reports the budget authority")
    t:raises(function()
        effects.release_profile("baseline", extreme)
    end, "exceeds rarity budget", "over-budget release cannot compile")

    -- Every formerly mutable compiled content table is ignored on canonical
    -- construction and rejected when handed across a live boundary as a
    -- claimed cache.
    local momentum_cache = slings.by_id.momentum
    local old_momentum = momentum_cache.momentum_bonus
    local old_momentum_rules = momentum_cache.rule_set
    momentum_cache.momentum_bonus = 999
    momentum_cache.rule_set = cache_rule_shadow(
        old_momentum_rules,
        "sling.momentum.force",
        999
    )
    local canonical_sling = draft.instantiate_sling({ content_id = "momentum" })
    local starting = short.new({ run_seed = 9125, short_run = true })
    t:eq(canonical_sling.momentum_bonus, 3,
        "draft ignores the mutable sling mechanics cache")
    t:eq(starting.player.sling.momentum_bonus, 3,
        "short-run setup derives the sling from canonical rules")
    t:raises(function()
        slings.runtime("momentum", catalog.sling_by_id.momentum.rule_set, momentum_cache)
    end, "diverges from canonical RuleSet",
    "claimed divergent sling cache fails closed")
    momentum_cache.momentum_bonus = old_momentum
    momentum_cache.rule_set = old_momentum_rules

    local sling_fields = {
        "shots_per_volley", "damage_bonus", "durability_bonus",
        "momentum_bonus", "aim", "scatter", "ricochet", "precision",
        "effect_power",
    }
    for _, field in ipairs(sling_fields) do
        local shadow = util.deep_copy(slings.by_id.momentum)
        shadow[field] = 999
        t:raises(function()
            slings.runtime("momentum", catalog.sling_by_id.momentum.rule_set, shadow)
        end, "diverges from canonical RuleSet",
        "every sling projection rejects shadow field " .. field)
    end
    local rule_only_shadow = util.deep_copy(slings.by_id.momentum)
    rule_only_shadow.rule_set = mutate_rule(
        rule_only_shadow.rule_set,
        "sling.momentum.force",
        4
    )
    t:raises(function()
        slings.runtime(
            "momentum",
            catalog.sling_by_id.momentum.rule_set,
            rule_only_shadow
        )
    end, "compiled RuleSet diverges",
    "a rule-only sling cache mutation fails closed")

    local core_cache = cores.by_id.dull_quartz
    local shell_cache = shells.by_id.chalk_plain
    local old_trajectory, old_core_rules = core_cache.trajectory, core_cache.rule_set
    local old_durability, old_shell_rules = shell_cache.durability, shell_cache.rule_set
    core_cache.trajectory = 999
    core_cache.rule_set = cache_rule_shadow(
        old_core_rules,
        "core.dull_quartz.trajectory",
        999
    )
    shell_cache.durability = 999
    shell_cache.rule_set = cache_rule_shadow(
        old_shell_rules,
        "shell.chalk_plain.durability",
        999
    )
    local canonical_marble = marble.build(
        catalog.marble_by_id.chalk_common,
        draft.instantiate_sling({ content_id = "momentum" }),
        "A"
    )
    t:eq(canonical_marble.core.trajectory, 0,
        "live core trajectory ignores the mutable compiled cache")
    t:eq(canonical_marble.shells[1].durability, 1,
        "live shell durability ignores the mutable compiled cache")
    t:raises(function()
        cores.runtime("dull_quartz", catalog.marble_by_id.chalk_common.rule_set, core_cache)
    end, "diverges from canonical RuleSet",
    "claimed divergent core cache fails closed")
    t:raises(function()
        shells.runtime("chalk_plain", catalog.marble_by_id.chalk_common.rule_set, shell_cache)
    end, "diverges from canonical RuleSet",
    "claimed divergent shell cache fails closed")
    core_cache.trajectory, core_cache.rule_set = old_trajectory, old_core_rules
    shell_cache.durability, shell_cache.rule_set = old_durability, old_shell_rules
    for _, mutation in ipairs({
        { module = cores, id = "dull_quartz", rules = catalog.marble_by_id.chalk_common.rule_set,
            field = "release" },
        { module = cores, id = "dull_quartz", rules = catalog.marble_by_id.chalk_common.rule_set,
            field = "min_rarity" },
        { module = shells, id = "chalk_plain", rules = catalog.marble_by_id.chalk_common.rule_set,
            field = "collision" },
    }) do
        local shadow = util.deep_copy(mutation.module.by_id[mutation.id])
        shadow[mutation.field] = 999
        t:raises(function()
            mutation.module.runtime(mutation.id, mutation.rules, shadow)
        end, "diverges from canonical RuleSet",
        mutation.id .. " rejects shadow field " .. mutation.field)
    end

    local brick_cache = bricks.by_id.basalt_absorber
    local old_hp, old_brick_rules = brick_cache.hp, brick_cache.rule_set
    brick_cache.hp = 999
    brick_cache.rule_set = cache_rule_shadow(
        old_brick_rules,
        "brick.basalt_absorber.hp",
        999
    )
    local canonical_brick = draft.instantiate_brick(
        "guard_pair",
        "basalt_absorber",
        1,
        "probe"
    )
    local canonical_formation = formation.build(
        { { canonical_brick.uid } },
        { canonical_brick }
    )
    t:eq(canonical_brick.hp, 4,
        "drafted brick HP ignores the mutable compiled cache")
    t:eq(canonical_formation.grid[1][1].hp, 4,
        "live formation HP derives from the entity RuleSet")
    t:raises(function()
        bricks.runtime("basalt_absorber", canonical_brick.rule_set, brick_cache)
    end, "diverges from canonical RuleSet",
    "claimed divergent brick cache fails closed")
    brick_cache.hp, brick_cache.rule_set = old_hp, old_brick_rules
    for _, field in ipairs({ "behaviour", "hp", "max_hp", "restitution", "rarity" }) do
        local shadow = util.deep_copy(bricks.by_id.basalt_absorber)
        shadow[field] = 999
        t:raises(function()
            bricks.runtime(
                "basalt_absorber",
                bricks.canonical_rule_set("basalt_absorber"),
                shadow
            )
        end, "diverges from canonical RuleSet",
        "brick projection rejects shadow field " .. field)
    end

    local release_shadow = effects.release_profile("baseline")
    release_shadow.field_release_strength = 999
    t:eq(effects.release_profile("baseline").field_release_strength, 10,
        "release profiles are fresh RuleSet projections")
    t:eq(measured_field_velocity(effects.release_profile("baseline")), 10 / 120,
        "release cache mutation cannot change fixed-step velocity")
    local collision_shadow = effects.collision_profile("chip")
    collision_shadow.damage = 999
    t:eq(effects.collision_profile("chip").damage, 1,
        "collision profiles are fresh RuleSet projections")
    local brick_shadow = effects.brick_profile(
        canonical_brick.behaviour,
        canonical_brick.rule_set
    )
    brick_shadow.damage_reduction = 999
    t:eq(effects.brick_profile(
        canonical_brick.behaviour,
        canonical_brick.rule_set
    ).damage_reduction, nil,
    "common Basalt profiles remain passive-free fresh RuleSet projections")

    local setup_state = fixtures.place_unplaced(short.new({
        run_seed = 9125,
        short_run = true,
    }))
    setup_state.player.sling.momentum_bonus = 999
    local locked, lock_error = run.dispatch(setup_state, { kind = "lock_setup" })
    t:eq(locked, nil, "short-run setup rejects a divergent compiled sling")
    t:eq(lock_error and lock_error.code, "setup_invalid",
        "setup divergence fails at the setup boundary")
    t:ok(contains_error(lock_error and lock_error.details, "sling_runtime_mismatch"),
        "setup reports the canonical runtime mismatch")

    local battle_state = fixtures.to_battle(short.new({
        run_seed = 9125,
        short_run = true,
    }))
    local handoff = short.battle_handoff(battle_state)
    handoff.player.sling.momentum_bonus = 999
    t:raises(function()
        engine.new(handoff)
    end, "diverges from canonical RuleSet",
    "battle handoff rejects a divergent compiled sling")

    -- All two members of every approved kit map to their exact entity rules.
    -- No single-brick operation may inherit absent companion mechanics.
    local variants = 0
    for _, kit in ipairs(catalog.BRICK_KITS) do
        local kit_ids = ids_as_set(ast.player_rule_ids(kit.rule_set))
        for _, brick_id in ipairs(kit.brick_ids) do
            variants = variants + 1
            local entity = draft.instantiate_brick(
                kit.id,
                brick_id,
                variants,
                "reward"
            )
            local operation = {
                kind = "add_brick",
                kit_id = kit.id,
                content_id = brick_id,
            }
            local authority = short.reward_rule_authority(operation, entity)
            local entity_authority = ast.player_authority(entity.rule_set)
            local authority_ids = ids_as_set(authority.rule_ids)
            t:eq(authority.rule_set_id, entity.rule_set.id,
                kit.id .. "/" .. brick_id .. " attributes the applied entity")
            t:ok(util.deep_equal(authority.rule_ids, entity_authority.rule_ids),
                kit.id .. "/" .. brick_id .. " has exact rule membership")
            t:eq(#authority.rule_ids, #authority.rules,
                kit.id .. "/" .. brick_id .. " has no helper inflation")
            t:eq(
                #authority.balance.lines,
                #authority.rule_ids + #entity.rule_set.abilities,
                kit.id .. "/" .. brick_id .. " accounts exact membership and MCU"
            )
            for _, rule_id in ipairs(authority.rule_ids) do
                t:eq(authority_ids[rule_id], 1,
                    kit.id .. "/" .. brick_id .. " maps each rule once")
                t:ok(kit_ids[rule_id] ~= nil,
                    kit.id .. "/" .. brick_id .. " stays within kit provenance")
            end
            local companion_rules = 0
            for rule_id in pairs(kit_ids) do
                if authority_ids[rule_id] == nil then companion_rules = companion_rules + 1 end
            end
            t:ok(companion_rules > 0,
                kit.id .. "/" .. brick_id .. " excludes absent companion rules")

            local relabelled = util.deep_copy(entity)
            relabelled.rule_set = util.deep_copy(kit.rule_set)
            t:raises(function()
                short.reward_rule_authority(operation, relabelled)
            end, "RuleSet must match the applied entity",
            kit.id .. "/" .. brick_id .. " rejects kit relabelling")
            local wrong = util.deep_copy(operation)
            wrong.content_id = kit.brick_ids[1] == brick_id
                and kit.brick_ids[2]
                or kit.brick_ids[1]
            t:raises(function()
                short.reward_rule_authority(wrong, entity)
            end, "identity must match",
            kit.id .. "/" .. brick_id .. " rejects a different applied brick")
        end
    end
    t:eq(variants, 16, "exact membership covers all sixteen kit/brick variants")

    -- Fight-one rarity law excludes legendary rewards while the selected
    -- individual brick still has exact entity-only attribution.
    local reward_state = fixtures.complete(short.new({
        run_seed = 7,
        short_run = true,
    }))
    local reward_brick
    for _, choice in ipairs(reward_state.draft.offer.choices) do
        t:neq(choice.operation.content_id, "temporal_anchor",
            "win-one reward cannot contain a legendary brick")
        if choice.operation.kind == "add_brick" then reward_brick = choice end
    end
    t:ok(reward_brick ~= nil, "seed 7 offers one legal individual add-brick operation")
    if reward_brick then
        local reward_id = reward_brick.operation.content_id
        local expected = ast.player_rule_ids(
            bricks.canonical_rule_set(reward_id)
        )
        t:ok(util.deep_equal(
            reward_brick.causal_attribution.source_rule_ids,
            expected
        ), "individual reward attribution is exact")
        t:eq(#reward_brick.causal_attribution.applied_content_ids, 1,
            "individual reward records one applied entity")
        t:eq(reward_brick.causal_attribution.applied_content_ids[1],
            reward_id,
            "individual attribution names only the applied brick")
        local kit = catalog.brick_kit_by_id[reward_brick.operation.kit_id]
        local companion = kit.brick_ids[1] == reward_id
            and kit.brick_ids[2] or kit.brick_ids[1]
        local companion_rule = "brick." .. companion .. ".hp"
        t:eq(ids_as_set(reward_brick.causal_attribution.source_rule_ids)
            [companion_rule], nil,
            "individual reward excludes absent companion rules")

        local inflated = util.deep_copy(reward_state)
        local inflated_choice = draft.find_choice(
            inflated.draft.offer,
            reward_brick.choice_id
        )
        inflated_choice.causal_attribution.source_rule_ids[#inflated_choice
            .causal_attribution.source_rule_ids + 1] = companion_rule
        local inflated_result, inflated_error = run.dispatch(inflated, {
            kind = "choose_offer",
            offer_id = inflated.draft.offer.offer_id,
            choice_id = reward_brick.choice_id,
        })
        t:eq(inflated_result, nil,
            "hidden companion attribution cannot cross the apply boundary")
        t:eq(inflated_error and inflated_error.code, "reward_authority_changed",
            "hidden companion inflation fails with an authority error")

        local duplicated = util.deep_copy(reward_state)
        local duplicated_choice = draft.find_choice(
            duplicated.draft.offer,
            reward_brick.choice_id
        )
        duplicated_choice.causal_attribution.source_rule_ids[#duplicated_choice
            .causal_attribution.source_rule_ids + 1] = duplicated_choice
            .causal_attribution.source_rule_ids[1]
        local duplicate_result, duplicate_error = run.dispatch(duplicated, {
            kind = "choose_offer",
            offer_id = duplicated.draft.offer.offer_id,
            choice_id = reward_brick.choice_id,
        })
        t:eq(duplicate_result, nil,
            "duplicate reward attribution cannot cross the apply boundary")
        t:eq(duplicate_error and duplicate_error.code, "reward_authority_changed",
            "duplicate reward mapping fails with an authority error")

        local retargeted = util.deep_copy(reward_state)
        local retargeted_choice = draft.find_choice(
            retargeted.draft.offer,
            reward_brick.choice_id
        )
        retargeted_choice.operation.content_id = companion
        local retargeted_result, retargeted_error = run.dispatch(retargeted, {
            kind = "choose_offer",
            offer_id = retargeted.draft.offer.offer_id,
            choice_id = reward_brick.choice_id,
        })
        t:eq(retargeted_result, nil,
            "operation retargeting cannot preserve stale attribution")
        t:eq(retargeted_error and retargeted_error.code, "reward_authority_changed",
            "retargeting fails before applying the wrong entity")

        local before_count = #reward_state.player.bricks
        local chosen, choose_error = run.dispatch(reward_state, {
            kind = "choose_offer",
            offer_id = reward_state.draft.offer.offer_id,
            choice_id = reward_brick.choice_id,
        })
        t:ok(chosen ~= nil, choose_error and choose_error.message
            or "individual brick reward applies")
        if chosen then
            t:eq(#chosen.state.player.bricks, before_count + 1,
                "add-brick operation applies exactly one brick")
            local applied = chosen.state.player.bricks[#chosen.state.player.bricks]
            t:eq(applied.content_id, reward_id,
                "the attributed brick is the applied entity")
            t:ok(util.deep_equal(
                ast.player_rule_ids(applied.rule_set),
                reward_brick.causal_attribution.source_rule_ids
            ), "applied entity rules equal reward attribution")
        end
    end
end

if arg and arg[0]
    and arg[0]:find("test_runtime_rule_authority.lua", 1, true) then
    harness.run_one(M)
end

return M
