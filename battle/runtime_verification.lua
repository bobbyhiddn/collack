-- Focused packaged-runtime evidence for merge-gate verification.
--
-- This module constructs deterministic scenarios through the same physics and
-- engine modules used by the game. It contains no collision or battle rules of
-- its own and runs only when the web shell supplies --verify-canonical.

local engine = require("battle.engine")
local physics = require("battle.physics")

local M = { SCHEMA_VERSION = 1 }

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

function M.run()
    return {
        schema_version = M.SCHEMA_VERSION,
        sweep = swept_collision(),
        blowback = allied_enemy_blowback(),
    }
end

return M
