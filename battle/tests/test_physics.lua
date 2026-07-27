local harness = require("battle.tests.harness")
local physics = require("battle.physics")

local M = { name = "physics_world" }

local function near(t, actual, expected, tolerance, message)
    t:ok(math.abs(actual - expected) <= tolerance,
        string.format("%s -- expected %.8f +/- %.8f, got %.8f",
            message, expected, tolerance, actual))
end

local function event_of(events, kind)
    for _, event in ipairs(events) do
        if event.type == kind then return event end
    end
    return nil
end

local function advance(world, ticks)
    local events = {}
    world:drain_events()
    for _ = 1, ticks do
        local tick_events = world:step(physics.FIXED_DT)
        for _, event in ipairs(tick_events) do events[#events + 1] = event end
    end
    return events
end

function M.run(t)
    do
        local world = physics.new()
        t:raises(function() world:step(1 / 60) end, "fixed_dt")
    end

    do
        local world = physics.new({ width = 100, height = 20, max_speed = 240, linear_damping = 1 })
        world:add_box({
            id = "barrier", x = 50, y = 10,
            width = 0.001, height = 18, restitution = 1,
        })
        local ball = world:add_body({
            id = "fast", x = 49.02, y = 10, vx = 240, vy = 0,
            radius = 0.001, mass = 1, restitution = 1,
        })
        world:drain_events()
        local hit = event_of(world:step(physics.FIXED_DT), "box_collision")
        t:ok(hit, "a swept impact is emitted for a sub-millimetre barrier")
        near(t, hit.toi, 0.004077, 0.000001, "impact carries canonical within-tick TOI")
        t:ok(ball.x < 49.02, "remaining tick motion continues after the rebound")
        t:ok(ball.vx < 0, "x velocity reflected")
        t:eq(world.last_substeps, 1, "collision safety does not depend on microsteps")
        t:eq(world.last_collision_iterations, 1, "one swept collision resolves in one iteration")
        t:ok(not world.collision_iteration_limit_hit, "ordinary sweep stays below the hard bound")
    end

    do
        local world = physics.new({ width = 100, height = 20, max_speed = 240, linear_damping = 1 })
        local ball = world:add_body({
            id = "wall-fast", x = 0.5, y = 10, vx = -240, vy = 0,
            radius = 0.001, mass = 1, restitution = 1,
        })
        world:drain_events()
        local hit = event_of(world:step(physics.FIXED_DT), "wall_collision")
        t:ok(hit, "fast wall impact emitted")
        near(t, hit.toi, 0.002079, 0.000001, "wall impact reports swept TOI")
        near(t, ball.x, 1.502, 0.000001, "wall rebound consumes the remaining tick time")
        near(t, ball.vx, 240, 0.000001, "wall normal velocity reflects")
    end

    do
        local world = physics.new({ width = 100, height = 20, max_speed = 240, linear_damping = 1 })
        local left = world:add_body({
            id = "tiny-a", x = 49.02, y = 10, vx = 240, vy = 0,
            radius = 0.001, mass = 1, restitution = 1,
        })
        local right = world:add_body({
            id = "tiny-b", x = 50.98, y = 10, vx = -240, vy = 0,
            radius = 0.001, mass = 1, restitution = 1,
        })
        world:drain_events()
        local hit = event_of(world:step(physics.FIXED_DT), "body_collision")
        t:ok(hit, "opposing fast circles collide before swapping sides")
        near(t, hit.toi, 0.004079, 0.000001, "circle pair reports relative-motion TOI")
        near(t, left.vx, -240, 0.000001, "left circle receives reflected velocity")
        near(t, right.vx, 240, 0.000001, "right circle receives reflected velocity")
        t:ok(left.x < 49.02 and right.x > 50.98,
            "both circles consume their post-impact tick motion")
    end

    do
        local world = physics.new({ width = 100, height = 100, max_speed = 1000, linear_damping = 1 })
        world:add_box({
            id = "corner", x = 50, y = 50,
            width = 10, height = 10, restitution = 1,
        })
        local ball = world:add_body({
            id = "diagonal", x = 40, y = 40, vx = 600, vy = 600,
            radius = 1, mass = 1, restitution = 1,
        })
        world:drain_events()
        local hit = event_of(world:step(physics.FIXED_DT), "box_collision")
        t:ok(hit, "rounded AABB corner sweep emits a contact")
        near(t, hit.nx, -0.707107, 0.000001, "corner contact has radial x normal")
        near(t, hit.ny, -0.707107, 0.000001, "corner contact has radial y normal")
        t:ok(ball.vx < 0 and ball.vy < 0, "corner normal produces a genuine rebound")
    end

    do
        local world = physics.new({ width = 100, height = 20, max_speed = 240, linear_damping = 1 })
        world:add_box({ id = "z-early", x = 10.6, y = 5, width = 0.01, height = 2 })
        world:add_box({ id = "a-late", x = 21.8, y = 15, width = 0.01, height = 2 })
        world:add_body({ id = "z-shot", x = 10, y = 5, vx = 240, radius = 0.1 })
        world:add_body({ id = "a-shot", x = 20, y = 15, vx = 240, radius = 0.1 })
        world:drain_events()
        local events = world:step(physics.FIXED_DT)
        local hits = {}
        for _, event in ipairs(events) do
            if event.type == "box_collision" then hits[#hits + 1] = event end
        end
        t:eq(#hits, 2, "independent within-tick impacts are both emitted")
        t:eq(hits[1].box, "z-early", "earlier TOI precedes lexical collider order")
        t:ok(hits[1].toi < hits[2].toi, "collision audit remains ordered by physical TOI")
    end

    do
        local world = physics.new({ width = 30, height = 30, linear_damping = 1 })
        local ball = world:add_body({
            id = "ricochet", x = 3, y = 15, vx = -60, vy = 17,
            radius = 1, mass = 1, restitution = 1,
        })
        local events = advance(world, 8)
        t:ok(event_of(events, "wall_collision"), "wall collision emitted")
        t:ok(ball.vx > 0, "normal component reflected")
        near(t, ball.vy, 17, 0.000001, "tangent component preserved")
    end

    do
        local world = physics.new({ width = 40, height = 20, linear_damping = 1 })
        local left = world:add_body({
            id = "a", x = 12, y = 10, vx = 20, vy = 0,
            radius = 2, mass = 1, restitution = 1,
        })
        local right = world:add_body({
            id = "b", x = 20, y = 10, vx = -10, vy = 0,
            radius = 2, mass = 1, restitution = 1,
        })
        local events = advance(world, 24)
        t:ok(event_of(events, "body_collision"), "marble collision emitted")
        near(t, left.vx, -10, 0.000001, "left receives right velocity")
        near(t, right.vx, 20, 0.000001, "right receives left velocity")
    end

    do
        local world = physics.new({ width = 40, height = 40, linear_damping = 1 })
        local ally = world:add_body({ id = "A:1", owner = "A", x = 18, y = 20, radius = 1, mass = 1 })
        local enemy = world:add_body({ id = "B:1", owner = "B", x = 22, y = 20, radius = 1, mass = 1 })
        world:drain_events()
        local affected = world:apply_radial_impulse(20, 20, 8, 12, { source = "core" })
        t:eq(table.concat(affected, ","), "A:1,B:1", "stable affected order")
        t:ok(ally.vx < 0, "ally blown outward")
        t:ok(enemy.vx > 0, "enemy blown outward")
        world:apply_radial_impulse(20, 20, 8, 12, { source = "magnet", invert = true })
        near(t, ally.vx, 0, 0.000001, "inverted impulse pulls ally inward")
        near(t, enemy.vx, 0, 0.000001, "inverted impulse pulls enemy inward")
    end

    do
        local world = physics.new({ width = 40, height = 40, linear_damping = 1 })
        local ball = world:add_body({ id = "m", x = 25, y = 20, radius = 1, mass = 2 })
        world:add_field({
            id = "magnet", kind = "radial", x = 20, y = 20,
            radius = 10, strength = -24, falloff = false, duration = 2,
        })
        world:drain_events()
        local events = advance(world, 2)
        t:ok(ball.vx < 0, "negative radial field attracts")
        t:ok(event_of(events, "field_contact"), "field contact audited")
        t:ok(not world:get_field("magnet"), "duration expires exactly")
    end

    do
        local world = physics.new({
            width = 20, height = 20, linear_damping = 0.5,
            sleep_speed = 0.2, sleep_ticks = 3,
        })
        local ball = world:add_body({ id = "slow", x = 10, y = 10, vx = 1, vy = 0, radius = 1 })
        local events = advance(world, 8)
        t:ok(ball.asleep, "body settles")
        t:ok(event_of(events, "body_sleep"), "sleep transition audited")
        t:ok(world:is_settled(), "world reports settled")
    end

    do
        local world = physics.new({ width = 40, height = 40 })
        world:add_body({ id = "b", x = 3, y = 4, radius = 1, data = { role = "test" } })
        world:add_body({ id = "a", x = 8, y = 9, radius = 1 })
        world:drain_events()
        local first = world:snapshot()
        first.bodies[1].x = 999
        first.bodies[1].data.role = "changed"
        local second = world:snapshot()
        t:eq(second.bodies[1].id, "a", "stable id ordering")
        t:eq(second.bodies[1].x, 8, "snapshot mutation does not touch world")
        local body_b
        for _, body in ipairs(second.bodies) do if body.id == "b" then body_b = body end end
        t:eq(body_b.data.role, "test", "nested metadata copied")
    end

    do
        local world = physics.new({
            width = 2, height = 10, linear_damping = 1,
            max_collision_iterations = 4,
        })
        local ball = world:add_body({
            id = "impossible", x = 1, y = 5, vx = 1, vy = 0,
            radius = 2, mass = 1,
        })
        world:drain_events()
        local events = world:step(physics.FIXED_DT)
        t:eq(world.last_collision_iterations, 4,
            "pathological contact stops at the configured iteration bound")
        t:ok(world.collision_iteration_limit_hit,
            "pathological contact exposes canonical limit telemetry")
        t:ok(event_of(events, "collision_iteration_limit"),
            "iteration exhaustion is audited")
        t:ok(ball.x == ball.x and ball.y == ball.y and ball.vx == ball.vx and ball.vy == ball.vy,
            "unsatisfiable geometry remains finite")
        local snapshot = world:snapshot()
        t:eq(snapshot.collision_iterations, 4, "snapshot reports bounded work")
        t:ok(snapshot.collision_iteration_limit_hit, "snapshot reports conservative stop")
    end

    do
        local function run()
            local world = physics.new({ width = 60, height = 60 })
            world:add_box({ id = "wall", x = 30, y = 30, width = 3, height = 35 })
            world:add_body({ id = "one", x = 8, y = 22, vx = 90, vy = 7, radius = 1.5, mass = 1.3 })
            world:add_body({ id = "two", x = 49, y = 28, vx = -45, vy = -3, radius = 2, mass = 2 })
            world:drain_events()
            local events = advance(world, 120)
            local snapshot = world:snapshot()
            local parts = {
                snapshot.tick, snapshot.substeps, snapshot.collision_iterations,
                tostring(snapshot.collision_iteration_limit_hit),
            }
            for _, body in ipairs(snapshot.bodies) do
                parts[#parts + 1] = table.concat({
                    body.id, body.x, body.y, body.vx, body.vy, tostring(body.asleep),
                }, ":")
            end
            for _, event in ipairs(events) do
                if event.type == "box_collision"
                    or event.type == "body_collision"
                    or event.type == "wall_collision"
                then
                    parts[#parts + 1] = table.concat({
                        event.type, tostring(event.body or event.a),
                        tostring(event.box or event.b or event.wall),
                        tostring(event.toi), tostring(event.iteration),
                    }, ":")
                end
            end
            return table.concat(parts, "|")
        end
        t:eq(run(), run(), "swept replay, TOIs, and bounded iteration telemetry are deterministic")
    end
end

if arg and arg[0] and arg[0]:find("test_physics.lua", 1, true) then
    harness.run_one(M)
end

return M
