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
local battlelog = require("battle.battlelog")
local engine = require("battle.engine")
local effects = require("battle.effects")
local harness = require("battle.tests.harness")
local numeric = require("battle.numeric")
local physics = require("battle.physics")
local presentation = require("presentation")
local rule_ast = require("battle.rule_ast")
local rulebook = require("battle.content.rules")
local util = require("battle.run_util")

local M = { name = "numeric_boundary_safety" }

-- This property suite is intentionally broad enough to exceed some remote
-- command transports' wall-clock limits.  Keep the default as the complete
-- suite while allowing each top-level matrix to be verified independently.
local requested_section = tonumber((arg and arg[1])
    or os.getenv("COLLACK_NUMERIC_SAFETY_SECTION") or "")
local section_index = 0
local requested_section_seen = false

local function section_enabled()
    section_index = section_index + 1
    local enabled = requested_section == nil or requested_section == section_index
    if enabled and requested_section ~= nil then requested_section_seen = true end
    return enabled
end

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
    section_index = 0
    requested_section_seen = false

    if section_enabled() then
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

    if section_enabled() then
        local product, saturated = numeric.limited_product(0.2, 0.5, 0.5, 0.5)
        t:eq(product, 0.125,
            "limited products normalise three-factor mantissas without false saturation")
        t:ok(not saturated, "an in-range three-factor product is not marked saturated")
        product, saturated = numeric.limited_product(0.1, 0.5, 0.5, 0.5)
        t:eq(product, 0.1, "limited products cap at their declared magnitude")
        t:ok(saturated, "an over-limit three-factor product reports saturation")
        product, saturated = numeric.limited_product(0, 0.5, 0.5)
        t:eq(product, 0, "a zero product limit cannot publish a positive value")
        t:ok(saturated, "a nonzero product against a zero limit reports saturation")
        product, saturated = numeric.limited_product(0, 0, math.huge)
        t:eq(product, 0, "a zero limit contains a later non-finite factor")
        t:ok(saturated, "a non-finite factor is reported even when another factor is zero")
    end

    if section_enabled() then
        local masses = { 1e-200, 1e-160, 1e-80, 1, 1e80, 1e160, 1e200 }
        local strengths = { -1e200, -1e160, -1e80, -1, 0, 1, 1e80, 1e160, 1e200 }
        local cases = 0
        for _, kind in ipairs({ "directional", "radial" }) do
            for _, mass in ipairs(masses) do
                for _, strength in ipairs(strengths) do
                    local first = field_run(kind, mass, strength)
                    local second = field_run(kind, mass, strength)
                    assert_canonical(t, first,
                        string.format("%s mass=%g strength=%g", kind, mass, strength))
                    t:ok(speed(first.body) <= 70.000001 and speed(first.body) >= 0.999999,
                        string.format("%s mass=%g strength=%g stays inside motion bounds",
                            kind, mass, strength))
                    t:ok(util.deep_equal(first, second),
                        string.format("%s mass=%g strength=%g replays equally",
                            kind, mass, strength))
                    cases = cases + 1
                end
            end
        end
        t:eq(cases, 126, "field exponent property matrix covers 126 combinations")
    end

    if section_enabled() then
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

    if section_enabled() then
        local masses = { 1e-200, 1e-160, 1, 1e160, 1e200 }
        local impulses = { -1e200, -1e160, -1, 1, 1e160, 1e200 }
        local cases = 0
        for _, mass in ipairs(masses) do
            for _, impulse in ipairs(impulses) do
                local world = physics.new({ width = 100, height = 100, max_speed = 300 })
                local body = world:add_body({
                    id = "impulse:" .. tostring(cases), x = 50, y = 50, vx = 2, radius = 1,
                    mass = mass, motion_active = true, minimum_speed = 2,
                })
                world:drain_events()
                world:apply_impulse(body.id, impulse, -impulse, { source = "matrix" })
                local events = world:step(physics.FIXED_DT)
                assert_canonical(t, { events = events, snapshot = world:snapshot() },
                    string.format("impulse mass=%g impulse=%g", mass, impulse))
                t:ok(speed(body) >= body.minimum_speed and speed(body) <= world.max_speed,
                    string.format("impulse mass=%g impulse=%g stays inside motion bounds",
                        mass, impulse))
                cases = cases + 1
            end
        end
        t:eq(cases, 30, "impulse exponent property matrix covers 30 combinations")
    end

    if section_enabled() then
        local world = physics.new({
            width = 200,
            height = 100,
            max_speed = 70,
            linear_damping = 1,
        })
        local body = world:add_body({
            id = "finite-cap",
            x = 50,
            y = 50,
            vx = 100,
            radius = 1,
            mass = 1,
        })
        t:ok(speed(body) <= world.max_speed,
            "a finite constructor velocity is capped before it can be observed")
        local active_constructor = world:add_body({
            id = "finite-active-floor",
            x = 150,
            y = 50,
            vx = 0,
            vy = 0,
            radius = 1,
            mass = 1,
            motion_active = true,
            minimum_speed = 12,
            asleep = true,
            motion_fallback_x = 0,
            motion_fallback_y = -1,
        })
        t:ok(speed(active_constructor) >= active_constructor.minimum_speed
                and speed(active_constructor) <= world.max_speed
                and not active_constructor.asleep,
            "an active constructor cannot publish a sleeping or sub-floor velocity")
        world:set_velocity(body.id, 0, 100)
        t:ok(speed(body) <= world.max_speed,
            "a finite setter velocity is capped before it can be observed")
        world:set_velocity(body.id, 0, 0)
        world:apply_impulse(body.id, 100, 0, { source = "finite-cap" })
        t:ok(speed(body) <= world.max_speed,
            "a finite direct impulse is capped before it can be observed")
        world:set_velocity(body.id, 0, 0)
        world:apply_radial_impulse(49, 50, 10, 100, {
            source = "finite-cap",
            falloff = false,
        })
        t:ok(speed(body) <= world.max_speed,
            "a finite radial impulse is capped before it can be observed")
        world:set_velocity(body.id, 0, 0)
        world:add_field({
            id = "finite-cap-field",
            kind = "directional",
            x = body.x,
            y = body.y,
            radius = 10,
            strength = 10000,
            dx = 1,
            dy = 0,
            falloff = false,
            duration = 1,
        })
        world:drain_events()
        local prior_x = body.x
        local events = world:step(physics.FIXED_DT)
        t:ok(speed(body) <= world.max_speed,
            "a finite field acceleration stays inside the energy cap")
        t:ok(body.x - prior_x <= world.max_speed * physics.FIXED_DT + 0.000001,
            "the finite field cap applies before fixed-step integration")
        assert_canonical(t, { events = events, snapshot = world:snapshot() },
            "finite sub-saturation energy-cap paths")
    end

    if section_enabled() then
        local world = physics.new({ width = 100, height = 100, max_speed = 240 })
        local body = world:add_body({
            id = "vector-boundary", x = 50, y = 50, radius = 1,
            mass = 1e-200, vx = 1, motion_active = true, minimum_speed = 1,
        })
        world:add_field({
            id = "vector-field", kind = "directional", x = 50, y = 50,
            radius = 20, strength = 1e200, dx = 1e9, dy = -1e9,
            falloff = false, duration = 2,
        })
        world:drain_events()
        local field_events = world:step(physics.FIXED_DT)
        world:apply_radial_impulse(50, 50, 1e9, -1e200, {
            source = "radial-boundary", falloff = false,
        })
        local radial_events = world:drain_events()
        assert_canonical(t, { field_events, radial_events, world:snapshot() },
            "direction-vector and radial-impulse exponent boundaries")
        t:ok(speed(body) >= body.minimum_speed and speed(body) <= world.max_speed + 0.000001,
            "combined extreme effects retain bounded active momentum")
    end

    if section_enabled() then
        local masses = { 1e-200, 1e-160, 1, 1e160, 1e200 }
        local cases = 0
        for _, left_mass in ipairs(masses) do
            for _, right_mass in ipairs(masses) do
                local world = physics.new({
                    width = 200, height = 100, max_speed = 240, linear_damping = 1,
                })
                local left = world:add_body({
                    id = "left", x = 98.5, y = 50, vx = 120, radius = 1,
                    mass = left_mass, restitution = 1,
                    motion_active = true, minimum_speed = 10,
                })
                local right = world:add_body({
                    id = "right", x = 101.5, y = 50, vx = -120, radius = 1,
                    mass = right_mass, restitution = 1,
                    motion_active = true, minimum_speed = 10,
                })
                world:drain_events()
                local events = world:step(physics.FIXED_DT)
                t:ok(event_of(events, "body_collision") ~= nil,
                    string.format("collision resolves for masses=%g/%g",
                        left_mass, right_mass))
                assert_canonical(t, { events = events, snapshot = world:snapshot() },
                    string.format("collision masses=%g/%g", left_mass, right_mass))
                t:ok(speed(left) >= left.minimum_speed and speed(left) <= world.max_speed
                        and speed(right) >= right.minimum_speed and speed(right) <= world.max_speed,
                    string.format("collision masses=%g/%g preserve bounded active momentum",
                        left_mass, right_mass))
                cases = cases + 1
            end
        end
        t:eq(cases, 25, "collision exponent property matrix covers 25 mass pairs")
    end

    if section_enabled() then
        local authored = rule_ast.copy(rulebook.brick_behaviours.magnetic)
        authored.rules[1].cadence.interval = 1e200
        assert_canonical(t, effects.brick_profile("magnetic", authored),
            "effect profiles accept the canonical exponent boundary")
        authored.rules[1].cadence.interval = 1e201
        t:raises(function()
            effects.brick_profile("magnetic", authored)
        end, "no greater", "effect profiles reject finite values beyond the shared boundary")
    end

    if section_enabled() then
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

    if section_enabled() then
        local first = engine_boundary_run()
        local second = engine_boundary_run()
        assert_canonical(t, first.snapshot, "engine exponent snapshot")
        assert_canonical(t, first.events, "engine exponent event log")
        assert_canonical(t, first.recording, "engine exponent recording")
        assert_canonical(t, first.replay_frame, "engine exponent replay frame")
        t:ok(util.deep_equal(first, second),
            "engine snapshot, events, checkpoints, recording, and replay are equal")

        local projected = presentation.project_battle(first.snapshot, first.snapshot, 0 / 0)
        assert_canonical(t, projected,
            "non-finite interpolation input cannot escape the replay projection")
        t:eq(projected.alpha, 1,
            "non-finite interpolation input recovers to the completed canonical frame")

        local contaminated = util.deep_copy(first.recording)
        contaminated.frames[1].tick = math.huge
        local recovered = presentation.from_recording(contaminated)
        assert_canonical(t, recovered.recording,
            "replay boundary deterministically recovers explicit non-finite input")
        t:ok((recovered.recording.numeric_recovery_count or 0) > 0,
            "replay recovery is durable canonical telemetry")
    end

    if section_enabled() then
        local world = physics.new({ width = 40, height = 40, max_speed = 80 })
        local body = world:add_body({
            id = "recovery", x = 20, y = 20, vx = 10, radius = 1,
            motion_active = true, minimum_speed = 8,
            data = { effect = "authored" },
        })
        local field = world:add_field({
            id = "recovery-field", kind = "directional", x = 20, y = 20,
            radius = 30, strength = 10, dx = 1, duration = 2,
            data = { effect = "authored" },
        })
        world:drain_events()
        body.mass, body.inv_mass, body.data.bad = 0, math.huge, 0 / 0
        field.strength, field.dx, field.data.bad = math.huge, 0 / 0, math.huge
        local events = world:step(physics.FIXED_DT)
        t:ok(event_of(events, "non_finite_recovered") ~= nil,
            "fixed-step preflight reports contaminated body and field recovery")
        assert_canonical(t, { events = events, snapshot = world:snapshot() },
            "fixed-step contaminated-state recovery")
        t:ok(speed(body) >= body.minimum_speed and speed(body) <= world.max_speed,
            "fixed-step recovery preserves bounded active momentum")

        world.events[1] = { type = "contaminated", value = math.huge }
        local recovered_events = world:drain_events()
        assert_canonical(t, recovered_events,
            "the event drain boundary contains an explicitly contaminated queue")
        t:ok((recovered_events.numeric_recovery_count or 0) > 0,
            "event queue recovery remains visible at the publication boundary")
    end

    if section_enabled() then
        t:raises(function()
            physics.new({ linear_damping = 1.0001 })
        end, "no greater", "energy-creating damping is rejected")
        t:raises(function()
            physics.new({ max_speed = numeric.MAX_SPEED * 2 })
        end, "no greater", "unbounded authored speed is rejected")
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
            world:add_body({ id = "too-bouncy", restitution = numeric.MAX_RESTITUTION + 0.01 })
        end, "no greater", "unbounded restitution is rejected")
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
        local contaminated_world = physics.new({ width = 40, height = 40 })
        contaminated_world.tick = 0 / 0
        t:raises(function()
            contaminated_world:step(physics.FIXED_DT)
        end, "finite number", "the fixed-step boundary rejects a contaminated world counter")
        local contaminated_config = physics.new({ width = 40, height = 40 })
        contaminated_config.linear_damping = math.huge
        t:raises(function()
            contaminated_config:step(physics.FIXED_DT)
        end, "finite number", "the fixed-step boundary rejects contaminated world configuration")
        local log = battlelog.new()
        log.seq = math.huge
        t:raises(function()
            log:add(1, "A", "contaminated")
        end, "finite number", "the event boundary rejects a contaminated sequence")
        local battle = engine.new({
            seed = 444,
            max_exchanges = 1,
            max_exchange_ticks = 20,
            sides = {
                A = side("A", "basalt_absorber", { "quartz_banded" }),
                B = side("B", "aegis_keystone", { "quartz_banded" }),
            },
        })
        t:raises(function()
            engine.step(battle, math.huge)
        end, "finite number", "the battle boundary rejects a non-finite timestep")
        battle.pending_events[#battle.pending_events + 1] = {
            type = "contaminated",
            value = math.huge,
        }
        local battle_events = engine.drain_events(battle)
        assert_canonical(t, battle_events,
            "the battle event publication boundary contains a contaminated queue")
        t:ok((battle_events.numeric_recovery_count or 0) > 0,
            "battle event queue recovery remains visible at publication")
        t:raises(function()
            checkpoints.signature({ value = 0 / 0 })
        end, "finite and bounded", "checkpointing refuses non-finite replay data")
    end

    if requested_section ~= nil then
        t:ok(requested_section_seen, "requested numeric safety section exists")
    end
end

if arg and arg[0] and arg[0]:find("test_numeric_safety.lua", 1, true) then
    harness.run_one(M)
end

return M
