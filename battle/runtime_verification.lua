-- Focused packaged-runtime evidence for merge-gate verification.
--
-- This module constructs deterministic scenarios through the same physics and
-- engine modules used by the game. It contains no collision or battle rules of
-- its own and runs only when the web shell supplies --verify-canonical.

local engine = require("battle.engine")
local physics = require("battle.physics")
local ast = require("battle.rule_ast")
local draft = require("battle.draft")
local opponent = require("battle.opponent")
local setup_rules = require("battle.setup_rules")

local M = { SCHEMA_VERSION = 2 }

local function event_of(events, kind)
    for _, event in ipairs(events or {}) do
        if event.type == kind then return event end
    end
    return nil
end

local function log_event(battle, kind)
    for _, event in ipairs(battle.log.events or {}) do
        if event.type == kind then return event end
    end
    return nil
end

local function log_events(battle, kind)
    local out = {}
    for _, event in ipairs(battle.log.events or {}) do
        if event.type == kind then out[#out + 1] = event end
    end
    return out
end

local function require_evidence(condition, message)
    if not condition then error("canonical runtime verification failed: " .. message, 2) end
end

local function marble(name, shell, lane)
    return {
        name = name,
        rarity = "common",
        core = "dull_quartz",
        shells = { shell },
        lane = lane,
    }
end

local function side(name, sling, formation, marbles)
    return {
        name = name,
        sling = sling,
        formation = formation,
        marbles = marbles,
    }
end

local function linked_rule(id, trigger, target, verb, stat, value, unit, options)
    options = options or {}
    return {
        id = id,
        trigger = { event = trigger, phase = options.phase or "during" },
        condition = {
            predicate = options.condition or "always",
            value = options.condition_value,
        },
        target = options.target or { selector = target, relation = options.relation },
        operation = { verb = verb, stat = stat, mode = options.mode or "set" },
        magnitude = { value = value, unit = unit },
        cadence = {
            unit = options.cadence_unit or trigger,
            interval = options.interval or 1,
            charges = options.charges,
        },
        cost = { kind = "none" },
        visibility = options.visibility or "compact",
        scaling = options.scaling,
        lethal = options.lethal,
    }
end

local function linked_cost_rule_set()
    return {
        schema_version = ast.SCHEMA_VERSION,
        kind = "rule_set",
        id = "brick.plain_block",
        name = "Bloodstone Relay Verification Fixture",
        role = "sacrificial shell bolster",
        content_kind = "brick",
        rarity = "rare",
        rarity_budget = 100,
        availability = {
            player_draft = false, player_reward = false,
            cpu_recipe = false, legacy_only = false,
        },
        components = {},
        abilities = {{
            id = "bloodstone_relay",
            kind = "allied_brick_cost",
            cost_rule_id = "fixture.relay.cost",
            payoff_rule_ids = { "fixture.relay.payoff" },
            recursion = {
                accepts_causes = { "hostile_collision" },
                max_generation = 1,
            },
        }},
        rules = {
            linked_rule("brick.plain_block.hp", "build", "self",
                "protect", "hp", 2, "hp", { visibility = "expanded" }),
            linked_rule("brick.plain_block.restitution", "build", "self",
                "set", "restitution", 0.72, "multiplier", { visibility = "expanded" }),
            linked_rule("brick.plain_block.behaviour", "build", "self",
                "set", "behaviour", "inert", "id", { visibility = "expanded" }),
            linked_rule("fixture.relay.cost", "damaging_collision",
                "setup_linked_allied_brick", "deal", "damage", 1, "damage", {
                    phase = "after", cadence_unit = "exchange", charges = 2,
                    lethal = false,
                    target = {
                        selector = "setup_linked_allied_brick",
                        relation = "allied", topology = "orthogonal", count = 1,
                        exclude_self = true, require_alive = true,
                        required_tags = {}, excluded_tags = {},
                        order = "local_row_col_uid",
                    },
                }),
            linked_rule("fixture.relay.payoff", "ability_cost_paid",
                "current_shell", "wear", "shell_wear", 2, "durability", {
                    phase = "after", relation = "enemy",
                    condition_value = "bloodstone_relay",
                    scaling = {
                        basis = "cost_damage_applied", numerator = 2,
                        denominator = 1, cap = 2, rounding = "floor",
                    },
                }),
        },
        drawback = { kind = "reduce", stat = "hp", magnitude = 1, unit = "hp" },
        compatibility = { requires = {}, excludes = {}, max_copies = 2 },
        synergy_tags = { "retaliation" },
    }
end

local function linked_cost()
    local relay_rules = linked_cost_rule_set()
    ast.assert_valid(relay_rules)
    local relay = {
        uid = "relay", content_id = "plain_block", id = "plain_block",
        name = "Bloodstone Relay Verification Fixture", behaviour = "inert",
        rarity = "rare", hp = 2, max_hp = 2, restitution = 0.72,
        rule_set = relay_rules,
    }
    local ally = draft.instantiate_brick(
        "guard_pair", "basalt_absorber", 1, "A"
    )
    ally.uid = "ally"
    local formation = {
        { "relay", "ally", ".", ".", ".", ".", "." },
        { ".", ".", ".", ".", ".", ".", "." },
        { ".", ".", ".", ".", ".", ".", "." },
    }
    local player = {
        name = "Fixture", sling = "momentum", formation = formation,
        bricks = { relay, ally },
        marbles = {{
            name = "Fixture", rarity = "common", core = "dull_quartz",
            shells = { "chalk_plain" },
        }},
    }
    local links, errors = setup_rules.resolve_ability_links(player)
    require_evidence(#errors == 0 and #links == 1,
        "linked-cost fixture did not resolve exactly one setup target")
    player.ability_links = links
    local enemy_formation = {
        { "plain_block", ".", ".", ".", ".", ".", "." },
        { ".", ".", ".", ".", ".", ".", "." },
        { ".", ".", ".", ".", ".", ".", "." },
    }
    local battle = engine.new({
        seed = 17019,
        sides = {
            A = player,
            B = side("Enemy", "momentum", enemy_formation, {{
                name = "Enemy", rarity = "common", core = "dull_quartz",
                shells = { "quartz_banded" },
            }}),
        },
    })
    battle.exchange = 1
    local source = battle.sides.A.formation.grid[1][1]
    local target = battle.sides.A.formation.grid[1][2]
    local striking = battle.sides.B.all_marbles[1]
    local activated = engine.activate_linked_cost(
        battle, "A", source.uid, "bloodstone_relay",
        "hostile_collision", striking
    )
    local triggered = log_event(battle, "ability_triggered")
    local paid = log_event(battle, "ability_cost_paid")
    local payoff = log_event(battle, "ability_payoff_applied")
    require_evidence(activated and triggered and paid and payoff,
        "linked-cost fixture did not emit its atomic event triple")
    require_evidence(triggered.activation_id == paid.activation_id
        and paid.activation_id == payoff.activation_id
        and triggered.seq < paid.seq and paid.seq < payoff.seq,
        "linked-cost fixture attribution/order diverged")
    return {
        compact_copy = ast.compact(relay_rules, 2),
        source_rule_set_id = relay_rules.id,
        ability_id = paid.ability_id,
        activation_id = paid.activation_id,
        cost_rule_id = paid.rule_id,
        cost_amount = paid.amount,
        cost_unit = paid.unit,
        target_selector = paid.target_selector,
        target_relation = paid.target_relation,
        target_uid = target.uid,
        cadence_index = paid.cadence_index,
        charges_before = paid.charges_before,
        charges_after = paid.charges_after,
        payoff_rule_id = payoff.rule_id,
        payoff_amount = payoff.amount,
        payoff_unit = payoff.unit,
        ordered = triggered.seq < paid.seq and paid.seq < payoff.seq,
    }
end

local function swept_collision()
    local world = physics.new({
        width = 100,
        height = 20,
        max_speed = 240,
        linear_damping = 1,
    })
    world:add_box({
        id = "runtime-thin-barrier",
        x = 50,
        y = 10,
        width = 0.001,
        height = 18,
        restitution = 1,
    })
    local ball = world:add_body({
        id = "runtime-fast-marble",
        x = 49.02,
        y = 10,
        vx = 240,
        vy = 0,
        radius = 0.001,
        mass = 1,
        restitution = 1,
    })
    local start_x = ball.x
    world:drain_events()
    local hit = event_of(world:step(physics.FIXED_DT), "box_collision")

    require_evidence(hit, "fast marble crossed a thin AABB without contact")
    require_evidence(hit.toi > 0 and hit.toi < physics.FIXED_DT,
        "thin-AABB contact did not carry a within-tick TOI")
    require_evidence(hit.speed >= 240, "thin-AABB contact was not high speed")
    require_evidence(ball.vx < 0 and ball.x < start_x,
        "fast marble did not rebound through the remainder of the tick")
    require_evidence(world.last_substeps == 1,
        "collision safety depended on motion sampling")
    require_evidence(world.last_collision_iterations == 1,
        "single thin-AABB impact did not resolve in one bounded iteration")

    return {
        kind = hit.type,
        speed = hit.speed,
        toi = hit.toi,
        reflected = ball.vx < 0,
        tunneled = ball.x >= 50,
        substeps = world.last_substeps,
        iterations = world.last_collision_iterations,
    }
end

local function allied_enemy_blowback()
    local battle = engine.new({
        seed = 33,
        max_exchanges = 1,
        max_exchange_ticks = 700,
        sides = {
            A = side("Release", "effect_amplifier", {
                { "plain_block", "plain_block", "plain_block" },
            }, {
                marble("fragile", "obsidian_shard", 2),
                marble("ally", "quartz_banded", 1),
            }),
            B = side("Cluster", "precision", {
                { "chalk_block", "chalk_block", "chalk_block" },
            }, {
                marble("enemy", "quartz_banded", 3),
            }),
        },
    })
    engine.step(battle, engine.FIXED_DT)

    local fragile = battle.sides.A.all_marbles[1]
    local ally = battle.sides.A.all_marbles[2]
    local enemy = battle.sides.B.all_marbles[1]
    local target = battle.sides.B.formation.grid[1][2]
    battle.world:set_position(fragile.body_id, target.x, target.y + 4.2)
    battle.world:set_velocity(fragile.body_id, 0, -220)
    battle.world:set_position(ally.body_id, target.x - 7, target.y + 7)
    battle.world:set_position(enemy.body_id, target.x + 7, target.y + 7)
    battle.world:set_velocity(enemy.body_id, 0, 0)

    local ally_body = battle.world:get_body(ally.body_id)
    local enemy_body = battle.world:get_body(enemy.body_id)
    local ally_before_x, enemy_before_x = ally_body.x, enemy_body.x
    for _ = 1, 12 do
        if fragile.state == "destroyed" then break end
        engine.step(battle, engine.FIXED_DT)
    end

    local blowback = log_event(battle, "blowback")
    local allied, enemy_hit = false, false
    for _, event in ipairs(battle.log:of_type("blowback_impulse")) do
        if event.allied then allied = true else enemy_hit = true end
    end
    local release_substeps = battle.world.last_substeps
    local release_iterations = battle.world.last_collision_iterations
    engine.step(battle, engine.FIXED_DT)
    local ally_dx = ally_body.x - ally_before_x
    local enemy_dx = enemy_body.x - enemy_before_x

    require_evidence(fragile.state == "destroyed",
        "high-speed collision did not expose the fragile core")
    require_evidence(blowback and #blowback.affected >= 2,
        "core release did not affect the clustered physical bodies")
    require_evidence(allied and enemy_hit,
        "core release did not audit both allied and enemy impulses")
    require_evidence(ally_dx < 0 and enemy_dx > 0,
        "allied and enemy marbles were not physically displaced outward")
    require_evidence(release_substeps == 1 and release_iterations >= 1,
        "release collision did not use bounded canonical sweep work")

    return {
        allied = allied,
        enemy = enemy_hit,
        affected = #blowback.affected,
        ally_dx = ally_dx,
        enemy_dx = enemy_dx,
        substeps = release_substeps,
        iterations = release_iterations,
        tick = blowback.tick,
    }
end

local function splice_guard()
    local seed = 9125
    local glass_cannon = opponent.build(seed, "glass_cannon")
    local empty_row = { ".", ".", ".", ".", ".", ".", "." }
    local battle = engine.new({
        seed = seed,
        max_exchanges = 2,
        max_exchange_ticks = 500,
        sides = {
            A = side("Guard Striker", "momentum", {
                { "plain_block", ".", ".", ".", ".", ".", "." },
                empty_row,
                empty_row,
            }, {
                marble("hostile", "quartz_banded", 3),
            }),
            B = glass_cannon,
        },
    })

    -- The shipped Glass Cannon recipe intentionally gives Splice three real
    -- orthogonal allies: Shatter above, Powder Keg left, and Mirror right.
    engine.step(battle, engine.FIXED_DT)
    local owner = battle.sides.B
    local source = owner.formation.grid[2][3]
    local applied_target = owner.formation.grid[1][3]
    local prevented_target = owner.formation.grid[2][4]
    local expiry_target = applied_target
    require_evidence(source and source.id == "splice_node",
        "Glass Cannon did not place its canonical Splice Node")
    require_evidence(applied_target and prevented_target and expiry_target,
        "Glass Cannon did not retain three adjacent Guard targets")

    local guard_rule = ast.rule(source.rule_set, "brick.splice.guard")
    require_evidence(guard_rule
        and guard_rule.magnitude.value == 1
        and guard_rule.duration.value == 120
        and guard_rule.cadence.unit == "exchange"
        and guard_rule.cadence.interval == 1,
    "Splice probe did not read the accepted canonical Guard rule")

    -- Drive a real hostile marble into the protected rear Splice Node. The
    -- low-impact Quartz shell deals one canonical damage, leaving Splice alive
    -- so its collision-triggered passive can protect the three real allies.
    local hostile = battle.sides.A.all_marbles[1]
    battle.world:set_position(hostile.body_id, source.x, source.y - 4.2)
    battle.world:set_velocity(hostile.body_id, 0, 30)
    for _ = 1, 12 do
        if log_event(battle, "splice_triggered") then break end
        engine.step(battle, engine.FIXED_DT)
    end
    local collision = log_event(battle, "collision")
    local triggered = log_event(battle, "splice_triggered")
    local applied = log_events(battle, "guard_applied")
    require_evidence(collision
        and collision.brick == "splice_node"
        and triggered
        and triggered.parent_event_id == collision.event_id
        and #applied == 3,
    "Glass Cannon Splice did not trigger from a real collision onto three neighbours")
    require_evidence(applied[1].target_entity_id == applied_target.uid
        and applied[1].amount == 1
        and applied[1].expires_tick == battle.tick + 120
        and applied[1].parent_event_id == triggered.event_id,
    "Splice Guard application diverged from canonical order/magnitude/expiry")

    -- Reuse the same canonical hostile marble for a second, harder physical
    -- collision against a guarded neighbour. Higher impact adds one canonical
    -- damage to Chip, so Guard must intercept exactly one of two requested
    -- damage before the ordinary brick-harm boundary applies the remainder.
    local hp_before = prevented_target.hp
    local collision_count = #log_events(battle, "collision")
    battle.world:set_position(
        hostile.body_id,
        prevented_target.x,
        prevented_target.y - 4.2
    )
    battle.world:set_velocity(hostile.body_id, 0, 60)
    for _ = 1, 12 do
        if log_event(battle, "guard_prevented") then break end
        engine.step(battle, engine.FIXED_DT)
    end
    local prevented = log_event(battle, "guard_prevented")
    local collisions = log_events(battle, "collision")
    local prevention_collision = collisions[collision_count + 1]
    local applied_damage = hp_before - prevented_target.hp
    require_evidence(prevention_collision
        and prevention_collision.brick == prevented_target.id
        and prevention_collision.damage == 2
        and applied_damage == 1
        and prevented and prevented.prevented == 1
        and prevented.parent_event_id == prevention_collision.event_id
        and prevented.target_entity_id == prevented_target.uid
        and prevented_target.hp == hp_before - 1
        and prevented_target.guard == nil,
    string.format(
        "Splice Guard physical prevention diverged: collisions=%d, prevention=%s, brick=%s, requested=%s, prevented=%s, applied=%s, hp=%s",
        #collisions,
        tostring(prevention_collision and prevention_collision.event_id),
        tostring(prevention_collision and prevention_collision.brick),
        tostring(prevention_collision and prevention_collision.damage),
        tostring(prevented and prevented.prevented),
        tostring(applied_damage),
        tostring(prevented_target.hp)
    ))

    local visual_frame = engine.snapshot(battle)
    local visual_guard_count = 0
    for _, brick in ipairs(visual_frame.sides.B.bricks) do
        if brick.guard and brick.guard.amount == 1 then
            visual_guard_count = visual_guard_count + 1
        end
    end
    require_evidence(visual_frame.sides.B.name == "Glass Cannon"
        and visual_guard_count == 2,
    "Splice visual frame did not preserve the real Glass Cannon Guard state")

    local expiry_tick = expiry_target.guard and expiry_target.guard.expires_tick
    require_evidence(expiry_tick
        and expiry_tick - triggered.tick == guard_rule.duration.value,
        "unspent Splice Guard did not retain its canonical 120-tick expiry")
    -- Advance the ordinary fixed-step engine to the authored expiry tick. No
    -- tick jump or direct Guard mutation is accepted as packaged evidence.
    for _ = 1, guard_rule.duration.value + 4 do
        if #log_events(battle, "guard_expired") > 0 then break end
        engine.step(battle, engine.FIXED_DT)
    end
    local expired = log_events(battle, "guard_expired")
    require_evidence(#expired == 2
        and expired[1].target_entity_id == expiry_target.uid
        and expired[1].tick == expiry_tick
        and expired[1].reason == "duration"
        and expiry_target.guard == nil,
    "unspent Glass Cannon Guard did not expire canonically at tick 120")
    require_evidence(triggered.seq < applied[1].seq
        and applied[#applied].seq < prevented.seq
        and prevented.seq < expired[1].seq,
    "Splice trigger/apply/prevent/expiry records are not causally ordered")

    local common = require("battle.content.bricks").canonical_rule_set(
        "basalt_absorber"
    )
    require_evidence(ast.ability_summary(common).count == 0,
        "Splice verification accidentally created a common passive")

    return {
        recipe_id = glass_cannon.recipe_id,
        battle_seed = seed,
        source_uid = source.uid,
        source_rule_set_id = source.rule_set.id,
        rule_id = guard_rule.id,
        ability_id = applied[1].ability_id,
        magnitude = guard_rule.magnitude.value,
        cadence_unit = guard_rule.cadence.unit,
        cadence_interval = guard_rule.cadence.interval,
        duration_ticks = guard_rule.duration.value,
        applied_count = #applied,
        expired_count = #expired,
        trigger_collision_event_id = collision.event_id,
        prevention_collision_event_id = prevention_collision.event_id,
        visual_frame = visual_frame,
        visual_frame_tick = visual_frame.tick,
        visual_guard_count = visual_guard_count,
        stages = {
            {
                order = 1,
                stage = "triggered",
                type = triggered.type,
                event_id = triggered.event_id,
                tick = triggered.tick,
                target_uid = "none",
                amount = triggered.amount,
                unit = triggered.unit,
                reason = "hostile_collision",
            },
            {
                order = 2,
                stage = "applied",
                type = applied[1].type,
                event_id = applied[1].event_id,
                tick = applied[1].tick,
                target_uid = applied[1].target_entity_id,
                amount = applied[1].amount,
                unit = applied[1].unit,
                expires_tick = applied[1].expires_tick,
                reason = "adjacent_allied_guard",
            },
            {
                order = 3,
                stage = "prevented",
                type = prevented.type,
                event_id = prevented.event_id,
                tick = prevented.tick,
                target_uid = prevented.target_entity_id,
                amount = prevented.prevented,
                unit = prevented.unit,
                requested_damage = 2,
                applied_damage = applied_damage,
                integrity_before = hp_before,
                integrity_after = prevented_target.hp,
                reason = "hostile_damage",
            },
            {
                order = 4,
                stage = "expired",
                type = expired[1].type,
                event_id = expired[1].event_id,
                tick = expired[1].tick,
                target_uid = expired[1].target_entity_id,
                amount = expired[1].amount,
                unit = expired[1].unit,
                expires_tick = expired[1].expires_tick,
                reason = expired[1].reason,
            },
        },
    }
end

function M.run()
    return {
        schema_version = M.SCHEMA_VERSION,
        sweep = swept_collision(),
        blowback = allied_enemy_blowback(),
        linked_cost = linked_cost(),
        splice_guard = splice_guard(),
    }
end

return M
