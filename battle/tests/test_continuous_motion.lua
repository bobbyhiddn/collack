local harness = require("battle.tests.harness")
local engine = require("battle.engine")
local physics = require("battle.physics")

local M = { name = "continuous_motion_lifecycle" }

local function speed(body)
    return math.sqrt(body.vx * body.vx + body.vy * body.vy)
end

local function finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function event_of(events, kind)
    for _, event in ipairs(events) do
        if event.type == kind then return event end
    end
    return nil
end

local function log_event(battle, kind)
    for _, event in ipairs(battle.log.events) do
        if event.type == kind then return event end
    end
    return nil
end

local function marble(name, shells, lane, rarity)
    return {
        name = name,
        rarity = rarity or (#shells > 1 and "legendary" or "common"),
        core = "dull_quartz",
        shells = shells,
        lane = lane or 1,
    }
end

local function side(name, brick, marbles, sling)
    return {
        name = name,
        sling = sling or "precision",
        formation = { { brick } },
        marbles = marbles,
    }
end

local function simple_battle(opts)
    opts = opts or {}
    return engine.new({
        seed = opts.seed or 91,
        max_exchanges = opts.max_exchanges or 1,
        max_exchange_ticks = opts.max_exchange_ticks or 700,
        sides = {
            A = side("A", opts.a_brick or "basalt_absorber", {
                marble("A marble", opts.a_shells or { "quartz_banded" }),
            }, opts.a_sling),
            B = side("B", opts.b_brick or "basalt_absorber", {
                marble("B marble", opts.b_shells or { "quartz_banded" }),
            }, opts.b_sling),
        },
    })
end

local function run_bounded(battle, tick_limit)
    local active_seen = false
    local valid = true
    local maximum = 0
    while not battle.result and battle.tick < tick_limit do
        engine.step(battle, engine.FIXED_DT)
        for _, marble in ipairs(battle.active) do
            local body = battle.world:get_body(marble.body_id)
            local value = body and speed(body) or -1
            active_seen = true
            maximum = math.max(maximum, value)
            if not body
                or not body.motion_active
                or body.asleep
                or not finite(body.vx)
                or not finite(body.vy)
                or value + 0.000001 < body.minimum_speed
                or value > battle.world.max_speed + 0.000001
            then
                valid = false
            end
        end
    end
    return active_seen, valid, maximum
end

function M.run(t)
    do
        local world = physics.new({
            width = 60,
            height = 60,
            max_speed = 80,
            linear_damping = 0.2,
            sleep_speed = 50,
            sleep_ticks = 1,
        })
        local active = world:add_body({
            id = "active",
            x = 30,
            y = 30,
            radius = 1,
            motion_fallback_x = 0,
            motion_fallback_y = -1,
        })
        local parked = world:add_body({
            id = "parked",
            x = 10,
            y = 10,
            radius = 1,
            dynamic = false,
            asleep = true,
        })
        world:drain_events()
        world:set_motion_active(active.id, true, { minimum_speed = 12 })
        world:set_velocity(active.id, 0, 0)
        t:ok(math.abs(speed(active) - 12) < 0.000001 and active.vy < 0,
            "exact-zero active velocity recovers along its last canonical direction")
        world:set_velocity(active.id, 0.000000001, 0)
        t:ok(math.abs(speed(active) - 12) < 0.000001 and active.vx > 0,
            "near-zero active velocity preserves its supplied response direction")
        world:apply_impulse(active.id, -12, 0, { source = "exact-cancel" })
        t:ok(math.abs(speed(active) - 12) < 0.000001 and active.vx > 0,
            "an exact cancelling impulse cannot stop an active body")
        for _ = 1, 24 do world:step(physics.FIXED_DT) end
        t:ok(active.motion_active and not active.asleep and speed(active) >= 12,
            "damping and the sleep threshold cannot settle active play")
        t:eq(log_event({ log = { events = world:drain_events() } }, "body_sleep"), nil,
            "active motion never emits a sleep transition")
        world:set_velocity(parked.id, 0, 0)
        world:enforce_motion(parked.id, "inactive_probe")
        t:ok(not parked.motion_active and not parked.dynamic and speed(parked) == 0,
            "the floor does not resurrect a pre-launch inactive body")
    end

    do
        local world = physics.new({
            width = 60,
            height = 30,
            max_speed = 90,
            linear_damping = 0.25,
        })
        local left = world:add_body({
            id = "left", x = 20, y = 15, vx = 60, radius = 1,
            restitution = 1, motion_fallback_x = 1,
        })
        local right = world:add_body({
            id = "right", x = 30, y = 15, vx = -60, radius = 1,
            restitution = 1, motion_fallback_x = -1,
        })
        world:set_motion_active(left.id, true, { minimum_speed = 18 })
        world:set_motion_active(right.id, true, { minimum_speed = 24 })
        world:drain_events()
        local collision
        for _ = 1, 28 do
            collision = collision or event_of(world:step(physics.FIXED_DT), "body_collision")
        end
        t:ok(collision ~= nil and left.vx < 0 and right.vx > 0,
            "marble contact preserves the physical response directions")
        t:ok(speed(left) >= 18 and speed(right) >= 24,
            "collision chains retain each authored speed class")
        t:ok(speed(left) <= 90 and speed(right) <= 90,
            "collision response remains inside the energy bound")

        world:add_field({
            id = "magnet", kind = "radial", x = 30, y = 15,
            radius = 60, strength = -10000, falloff = false, duration = 1,
        })
        world:step(physics.FIXED_DT)
        t:ok(speed(left) >= 18 and speed(right) >= 24,
            "magnetic force cannot cancel an active speed class")
        t:ok(speed(left) <= 90 and speed(right) <= 90,
            "magnetic force is capped by the same energy policy")
    end

    do
        t:raises(function() physics.new({ width = math.huge }) end, "finite number",
            "non-finite world input is rejected")
        local world = physics.new({ width = 40, height = 40, max_speed = 70 })
        local body = world:add_body({
            id = "recover", x = 20, y = 20, vx = 20, radius = 1,
            motion_fallback_x = 1,
        })
        world:set_motion_active(body.id, true, { minimum_speed = 14 })
        t:raises(function() world:set_velocity(body.id, math.huge, 0) end, "finite number",
            "non-finite public velocity input is rejected")
        world:drain_events()
        body.x = math.huge
        body.vx = math.huge
        body.vy = 0 / 0
        local events = world:step(physics.FIXED_DT)
        t:ok(event_of(events, "non_finite_recovered") ~= nil,
            "contaminated internal state recovers deterministically")
        t:ok(finite(body.x) and finite(body.y) and finite(body.vx) and finite(body.vy),
            "recovery leaves only finite canonical state")
        t:ok(speed(body) >= 14 and speed(body) <= 70,
            "recovered active state obeys both energy bounds")
    end

    do
        local battle = simple_battle()
        local initial = battle.world:get_body(battle.sides.A.all_marbles[1].body_id)
        t:ok(not initial.motion_active and not initial.dynamic,
            "pre-launch marbles are explicitly outside the motion invariant")
        engine.step(battle, engine.FIXED_DT)
        local marble_a = battle.sides.A.all_marbles[1]
        local body = battle.world:get_body(marble_a.body_id)
        local authored_floor = body.minimum_speed
        battle.world:set_velocity(body.id, 0, 0)
        t:ok(math.abs(speed(body) - authored_floor) < 0.000001,
            "battle insertion of exact zero recovers at the authored floor")
        battle.world:set_velocity(body.id, 0.000000001, 0)
        t:ok(math.abs(speed(body) - authored_floor) < 0.000001 and body.vx > 0,
            "battle insertion of near zero keeps the response direction")
    end

    do
        local families = {
            { brick = "rime_block", event = "status_applied" },
            { brick = "lodestone_block", event = "magnetic" },
            { brick = "mirror_pane", event = "ricochet", sling = "ricochet" },
        }
        for _, family in ipairs(families) do
            local battle = simple_battle({ b_brick = family.brick, a_sling = family.sling })
            local active_seen, valid, maximum = run_bounded(battle, 710)
            t:ok(battle.result ~= nil and battle.tick <= 700,
                family.brick .. " battle terminates inside its canonical bound")
            t:ok(active_seen and valid and maximum <= battle.world.max_speed,
                family.brick .. " preserves nonzero bounded active motion")
            t:ok(log_event(battle, family.event) ~= nil,
                family.brick .. " exercised its authored effect family")
            t:eq(log_event(battle, "marble_sleep"), nil,
                family.brick .. " never advances through passive sleep")
        end
    end

    local function wall_loop_signature()
        local battle = simple_battle({ seed = 8128, max_exchange_ticks = 700 })
        engine.step(battle, engine.FIXED_DT)
        local a = battle.sides.A.all_marbles[1]
        local b = battle.sides.B.all_marbles[1]
        battle.world:set_position(a.body_id, 35, 60)
        battle.world:set_velocity(a.body_id, 62, 0)
        battle.world:set_position(b.body_id, 10, 10)
        battle.world:set_velocity(b.body_id, 0, -62)
        local _, valid = run_bounded(battle, 710)
        local recovery = log_event(battle, "no_progress_recovery")
        local boundary = log_event(battle, "exchange_end")
        local signature = recovery and table.concat({
            recovery.tick, recovery.marble, recovery.seeded_bias,
            recovery.vx, recovery.vy,
        }, ":") or "missing"
        return signature, battle, recovery, boundary, valid
    end

    do
        local first_signature, battle, recovery, boundary, valid = wall_loop_signature()
        local second_signature = wall_loop_signature()
        t:ok(recovery ~= nil and recovery.reason == "wall_loop",
            "a wall-only no-progress trajectory receives visible physical recovery")
        t:eq(second_signature, first_signature,
            "seeded no-progress recovery is replay deterministic")
        t:ok(valid and battle.result ~= nil and battle.tick <= 700,
            "the recovered wall loop remains finite, energetic, and bounded")
        t:ok(boundary and boundary.reason ~= "settled" and boundary.reason ~= "timeout",
            "wall-loop completion is an explicit lifecycle outcome")
    end

    do
        local shells = {
            "obsidian_shard", "flint_spiral", "granite_mottled",
            "quartz_banded", "jade_lattice",
        }
        local battle = simple_battle({
            seed = 15,
            max_exchanges = 2,
            a_brick = "aegis_keystone",
            b_brick = "aegis_keystone",
            a_shells = shells,
            b_shells = shells,
        })
        engine.run(battle)
        local starts = battle.log:of_type("exchange_start")
        local ends = battle.log:of_type("exchange_end")
        local launches = battle.log:of_type("launch")
        t:eq(#starts, 2, "two explicit volleys launch without waiting for rest")
        t:eq(#ends, 2, "each volley has one explicit lifecycle boundary")
        t:eq(#launches, 4, "both sides commit one launch in each volley")
        t:ok(ends[1].seq < starts[2].seq and ends[1].tick <= starts[2].tick,
            "the next volley starts only after canonical outcomes close the prior one")
        for _, boundary in ipairs(ends) do
            t:ok(boundary.reason == "lifecycle_complete" or boundary.reason == "safety_return",
                "volley boundary names a canonical lifecycle result")
        end
        for _, owner in ipairs({ battle.sides.A, battle.sides.B }) do
            for _, item in ipairs(owner.roster) do
                local body = battle.world:get_body(item.body_id)
                t:ok(item.state == "returned" and body and not body.motion_active
                    and not body.dynamic and speed(body) == 0,
                    "returned terminal marble stays inactive at result")
            end
        end
    end

    do
        local formation_battle, formation_result = engine.simulate({
            seed = 2,
            max_exchanges = 3,
            sides = {
                A = side("Formation winner", "aegis_keystone", {
                    marble("durable", { "quartz_banded" }),
                }),
                B = side("Formation loser", "chalk_block", {
                    marble("deep shell", {
                        "obsidian_shard", "flint_spiral", "granite_mottled",
                        "quartz_banded", "jade_lattice",
                    }),
                }),
            },
        })
        t:ok(formation_result.winner == "A"
            and formation_result.reason:find("bricks_destroyed", 1, true) ~= nil
            and formation_battle.sides.B.formation.alive == 0,
            "formation destruction still produces its win path")

        local roster_battle, roster_result = engine.simulate({
            seed = 4,
            max_exchanges = 3,
            sides = {
                A = side("Roster winner", "basalt_absorber", {
                    marble("durable", {
                        "obsidian_shard", "flint_spiral", "granite_mottled",
                        "quartz_banded", "jade_lattice",
                    }),
                }),
                B = side("Roster loser", "aegis_keystone", {
                    marble("fragile", { "obsidian_shard" }),
                }),
            },
        })
        t:ok(roster_result.winner == "A"
            and roster_result.reason:find("opponent_marbles_destroyed", 1, true) ~= nil
            and #roster_battle.sides.B.roster == 0,
            "marble destruction still produces its independent win path")
        t:raises(function()
            simple_battle({ seed = math.huge })
        end, "finite number", "malformed battle seed is rejected")
    end
end

if arg and arg[0] and arg[0]:find("test_continuous_motion.lua", 1, true) then
    harness.run_one(M)
end

return M
