local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../../src/?.lua",
    here .. "/../?.lua",
    "./?.lua",
    "./src/?.lua",
    package.path,
}, ";")

local checkpoints = require("battle.checkpoints")
local engine = require("battle.engine")
local harness = require("battle.tests.harness")
local numeric = require("battle.numeric")
local physics = require("battle.physics")
local presentation = require("presentation")
local util = require("battle.run_util")

local M = { name = "numeric_boundary_safety" }

local function speed(body)
    local scale = math.max(math.abs(body.vx), math.abs(body.vy))
    if scale == 0 then return 0 end
    local x, y = body.vx / scale, body.vy / scale
    return scale * math.sqrt(x * x + y * y)
end

local function event_of(events, kind)
    for _, event in ipairs(events or {}) do
        if event.type == kind then return event end
    end
    return nil
end

local function assert_canonical(t, value, label)
    t:ok(numeric.is_canonical_tree(value), label .. " is entirely finite and bounded")
end

local function field_run(kind, mass, strength)
    local world = physics.new({
        width = 40,
        height = 40,
        max_speed = 70,
        linear_damping = 1,
    })
    local body = world:add_body({
        id = "extreme",
        x = 20,
        y = 20,
        vx = 1,
        vy = 0,
        radius = 1,
        mass = mass,
        motion_active = true,
        minimum_speed = 1,
        motion_fallback_x = 1,
    })
    world:add_field({
        id = "field",
        kind = kind,
        x = kind == "radial" and 19 or 20,
        y = 20,
        radius = 4,
        strength = strength,
        dx = 1,
        dy = 0,
        falloff = false,
        duration = 1,
        data = { effect = "exponent_property" },
    })
    world:drain_events()
    local events = world:step(physics.FIXED_DT)
    return {
        body = {
            x = body.x,
            y = body.y,
            vx = body.vx,
            vy = body.vy,
            active = body.motion_active,
        },
        events = events,
        snapshot = world:snapshot(),
    }
end

local function marble(name, shells)
    return {
        name = name,
        rarity = #shells > 1 and "legendary" or "common",
        core = "dull_quartz",
        shells = shells,
        lane = 1,
    }
end

local function side(name, brick, shells)
    return {
        name = name,
        sling = "precision",
        formation = { { brick } },
        marbles = { marble(name .. " marble", shells) },
    }
end

local function engine_boundary_run()
    local battle = engine.new({
        seed = 333,
        max_exchanges = 1,
        max_exchange_ticks = 700,
        sides = {
            A = side("A", "basalt_absorber", { "quartz_banded" }),
            B = side("B", "aegis_keystone", { "quartz_banded" }),
        },
    })
    engine.step(battle, engine.FIXED_DT)
    local active = assert(battle.active[1], "battle should launch an active marble")
    local body = assert(battle.world:get_body(active.body_id))
    body.mass = 1e-160
    body.inv_mass = 1e160
    battle.world:add_field({
        id = "field:engine-exponent-boundary",
        kind = "directional",
        owner = active.owner,
        x = body.x,
        y = body.y,
        radius = 4,
        strength = 1e160,
        dx = 1,
        dy = 0,
        falloff = false,
        duration = 1,
        data = { behaviour = "release" },
    })
    for _ = 1, 4 do engine.step(battle, engine.FIXED_DT) end
    local snapshot = engine.snapshot(battle)
    local recording = engine.recording(battle)
    local replay = presentation.from_recording(recording)
    local replay_frame = presentation.replay_project(replay)
    return {
        snapshot = snapshot,
        events = util.deep_copy(battle.log.events),
        recording = recording,
        replay_frame = replay_frame,
        checkpoint = checkpoints.signature(snapshot),
    }
end

function M.run(t)
    do
        local first = field_run("directional", 1e-160, 1e160)
        local second = field_run("directional", 1e-160, 1e160)
        t:ok(first.body.x == first.body.x and first.body.y == first.body.y,
            "exact 1e-160/1e160 integration cannot publish NaN positions")
        t:ok(first.body.vx == 70 and first.body.vy == 0,
            "exact exponent overflow saturates in field direction at the energy cap")
        t:ok(event_of(first.events, "numeric_saturation") ~= nil,
            "exact exponent overflow is an explicit deterministic recovery")
        local contact = event_of(first.events, "field_contact")
        t:ok(contact and contact.fx == 1e160 and contact.impulse == 0,
            "exact exponent field contact remains finite and truthful")
        assert_canonical(t, first, "exact exponent state/event/snapshot bundle")
        t:ok(util.deep_equal(first, second),
            "exact exponent recovery has state-for-state replay equality")
    end

    do
        local cases = {
            { 1e-200, 1e200 },
            { 1e-160, 1e160 },
            { 1e-80, 1e200 },
            { 1, 1e200 },
            { 1e80, 1e200 },
            { 1e200, 1e200 },
        }
        for _, kind in ipairs({ "directional", "radial" }) do
            for _, sign in ipairs({ -1, 1 }) do
                for index, values in ipairs(cases) do
                    local strength = sign * values[2]
                    local first = field_run(kind, values[1], strength)
                    local second = field_run(kind, values[1], strength)
                    assert_canonical(t, first,
                        string.format("%s exponent case %d sign %d", kind, index, sign))
                    t:ok(speed(first.body) <= 70.000001 and speed(first.body) >= 0.999999,
                        string.format("%s exponent case %d stays inside motion bounds", kind, index))
                    t:ok(util.deep_equal(first, second),
                        string.format("%s exponent case %d replays equally", kind, index))
                end
            end
        end
    end

    do
        local world = physics.new({ width = 50, height = 30, max_speed = 70, linear_damping = 1 })
        local active = world:add_body({
            id = "impulse-active", x = 25, y = 15, radius = 1,
            mass = 1e-200, vx = 1, motion_active = true, minimum_speed = 2,
        })
        local inactive = world:add_body({
            id = "impulse-inactive", x = 10, y = 15, radius = 1,
            mass = 1e-200, dynamic = false, asleep = true,
        })
        world:drain_events()
        world:apply_impulse(active.id, 1e200, -1e200, { source = "property" })
        world:apply_radial_impulse(25, 15, 6, 1e200, { source = "property" })
        world:step(physics.FIXED_DT)
        t:ok(speed(active) >= 2 and speed(active) <= 70.000001,
            "direct and radial extreme impulses share the velocity cap")
        t:ok(not inactive.dynamic and inactive.asleep and speed(inactive) == 0,
            "extreme impulses do not resurrect an inactive terminal body")
        assert_canonical(t, world:snapshot(), "extreme impulse snapshot")
    end

    do
        local wall_world = physics.new({ width = 40, height = 30, max_speed = 70, linear_damping = 1 })
        local wall_body = wall_world:add_body({
            id = "wall-heavy", x = 1.1, y = 15, vx = -70, radius = 1,
            mass = 1e200, restitution = 1,
        })
        wall_world:drain_events()
        local wall_events = wall_world:step(physics.FIXED_DT)
        t:ok(event_of(wall_events, "wall_collision") and wall_body.vx > 0,
            "maximum accepted mass keeps its wall collision direction")
        assert_canonical(t, { wall_events, wall_world:snapshot() },
            "maximum-mass wall contact and snapshot")

        local box_world = physics.new({ width = 40, height = 30, max_speed = 70, linear_damping = 1 })
        box_world:add_box({
            id = "barrier", x = 22, y = 15, width = 1, height = 12, restitution = 1,
        })
        local box_body = box_world:add_body({
            id = "box-light", x = 20, y = 15, vx = 70, radius = 1,
            mass = 1e-200, restitution = 1,
        })
        box_world:drain_events()
        local box_events = box_world:step(physics.FIXED_DT)
        t:ok(event_of(box_events, "box_collision") and box_body.vx < 0,
            "minimum accepted mass keeps its box collision direction")
        assert_canonical(t, { box_events, box_world:snapshot() },
            "minimum-mass box contact and snapshot")

        local pair_world = physics.new({ width = 40, height = 30, max_speed = 70, linear_damping = 1 })
        local light = pair_world:add_body({
            id = "light", x = 19, y = 15, vx = 70, radius = 0.5,
            mass = 1e-200, restitution = 1,
        })
        local heavy = pair_world:add_body({
            id = "heavy", x = 20.1, y = 15, vx = -70, radius = 0.5,
            mass = 1e200, restitution = 1,
        })
        pair_world:drain_events()
        local pair_events = pair_world:step(physics.FIXED_DT)
        t:ok(event_of(pair_events, "body_collision") ~= nil,
            "opposite exponent masses resolve a swept body contact")
        t:ok(light.vx < 0 and heavy.vx < 0,
            "opposite exponent collision preserves its physical response directions")
        t:ok(speed(light) <= 70.000001 and speed(heavy) <= 70.000001,
            "opposite exponent collision cannot escape the energy cap")
        assert_canonical(t, { pair_events, pair_world:snapshot() },
            "opposite exponent collision/event/snapshot")
    end

    do
        local first = engine_boundary_run()
        local second = engine_boundary_run()
        assert_canonical(t, first.snapshot, "engine exponent snapshot")
        assert_canonical(t, first.events, "engine exponent event log")
        assert_canonical(t, first.recording, "engine exponent recording")
        assert_canonical(t, first.replay_frame, "engine exponent replay frame")
        t:ok(util.deep_equal(first, second),
            "engine snapshot, events, checkpoints, recording, and replay are equal")

        local contaminated = util.deep_copy(first.recording)
        contaminated.frames[1].tick = math.huge
        local recovered = presentation.from_recording(contaminated)
        assert_canonical(t, recovered.recording,
            "replay boundary deterministically recovers explicit non-finite input")
        t:ok((recovered.recording.numeric_recovery_count or 0) > 0,
            "replay recovery is durable canonical telemetry")
    end

    do
        t:raises(function()
            physics.new({ width = 1e65 })
        end, "no greater", "geometry beyond the swept-safe exponent is rejected")
        local world = physics.new({ width = 40, height = 40 })
        t:raises(function()
            world:add_body({ id = "too-light", mass = 1e-201 })
        end, "at least", "mass below the inverse-safe exponent is rejected")
        t:raises(function()
            world:add_body({ id = "too-heavy", mass = 1e201 })
        end, "no greater", "mass above the impulse-safe exponent is rejected")
        t:raises(function()
            world:add_field({ id = "too-strong", strength = 1e201 })
        end, "no greater", "field strength beyond the shared force bound is rejected")
        t:raises(function()
            world:add_body({ id = "bad-data", data = { value = math.huge } })
        end, "finite number", "nested non-finite physics input is rejected")
        local body = world:add_body({ id = "bounded", x = 20, y = 20 })
        t:raises(function()
            world:set_velocity(body.id, 1e65, 0)
        end, "no greater", "velocity beyond the geometry-safe exponent is rejected")
        t:raises(function()
            world:apply_impulse(body.id, 1e201, 0)
        end, "no greater", "impulse beyond the shared force bound is rejected")
        t:raises(function()
            checkpoints.signature({ value = 0 / 0 })
        end, "finite and bounded", "checkpointing refuses non-finite replay data")
    end
end

if arg and arg[0] and arg[0]:find("test_numeric_safety.lua", 1, true) then
    harness.run_one(M)
end

return M
