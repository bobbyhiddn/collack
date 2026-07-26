local harness = require("battle.tests.harness")
local engine = require("battle.engine")
local setup = require("battle.setup")

local M = { name = "continuous_battle" }

local function marble(name, shell, lane, core)
    return {
        name = name,
        rarity = "common",
        core = core or "dull_quartz",
        shells = { shell or "quartz_banded" },
        lane = lane,
    }
end

local function side(name, sling, formation, marbles)
    return {
        name = name,
        sling = sling or "precision",
        formation = formation,
        marbles = marbles,
    }
end

local function events_of(battle, kind)
    return battle.log:of_type(kind)
end

local function has_event(battle, kind, side_id)
    for _, event in ipairs(battle.log.events) do
        if event.type == kind and (not side_id or event.side == side_id) then return event end
    end
    return nil
end

local function simple_target(target, opts)
    opts = opts or {}
    local columns = opts.columns or 1
    local a_layout, b_layout
    local a_lane = opts.lane or 1
    if columns == 1 then
        a_layout = { { opts.a_brick or "plain_block" } }
        b_layout = { { target } }
    else
        a_layout = { { "plain_block", "plain_block" } }
        b_layout = { { target, opts.second_brick or "plain_block" } }
    end
    local battle = engine.new({
        seed = opts.seed or 17,
        max_exchanges = 1,
        max_exchange_ticks = opts.max_exchange_ticks or 700,
        sides = {
            A = side("Attacker", opts.sling or "precision", a_layout, {
                marble("attacker", opts.shell or "quartz_banded", a_lane),
            }),
            B = side("Defender", "precision", b_layout, {
                marble("defender", "quartz_banded", columns),
            }),
        },
    })
    engine.run(battle)
    return battle
end

function M.run(t)
    do
        local battle = engine.new({ seed = 9125, sides = setup.default_matchup() })
        t:eq(#battle.log.events, 1, "new battle emits only initialization, not a scripted outcome")
        t:eq(battle.tick, 0, "new world starts at tick zero")
        t:eq(battle.exchange, 0, "no exchange is pre-resolved")
        local before = engine.snapshot(battle)
        t:eq(before.schema_version, 2, "snapshot schema identifies continuous state")
        t:eq(before.fixed_dt, 1 / 120, "snapshot exposes canonical fixed dt")
        t:eq(#before.world.bodies, 8, "all roster marbles live in the shared world")
        t:ok(#before.world.boxes > 20, "both formations are physical AABBs")
        local events = engine.step(battle, engine.FIXED_DT)
        local launches = {}
        for _, event in ipairs(events) do
            if event.type == "launch" then launches[#launches + 1] = event end
        end
        t:eq(#launches, 2, "both sides launch on the first canonical step")
        t:eq(launches[1].tick, launches[2].tick, "paired launches commit on the same tick")
        t:eq(launches[1].exchange, launches[2].exchange, "paired launches share one exchange")
        t:ok(#battle.log.events > 1, "audit log grows as the world advances")
        t:raises(function() engine.step(battle, 1 / 60) end, "fixed dt",
            "battle rejects variable simulation time")

        local mutable = engine.snapshot(battle)
        mutable.sides.A.bricks[1].hp = -999
        mutable.world.bodies[1].x = -999
        local clean = engine.snapshot(battle)
        t:ok(clean.sides.A.bricks[1].hp >= 0, "snapshot brick mutation cannot touch rules state")
        t:ok(clean.world.bodies[1].x >= 0, "snapshot transform mutation cannot touch physics")
    end

    do
        local expected = {
            basalt_absorber = "absorb",
            mirror_pane = "reflect",
            moss_regenerator = "regenerate",
            venom_glass = "status_applied",
            rime_block = "status_applied",
            lodestone_block = "magnetic",
            shatter_crystal = "shatter",
            powder_keg = "chain_detonate",
            vault_arch = "vault",
            splice_node = "splice",
            training_dummy = "dummy",
            aegis_keystone = "aegis",
            void_prism = "void",
            prismatic_mirror = "mirror",
            temporal_anchor = "temporal",
        }
        local ids = {}
        for id in pairs(expected) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local battle = simple_target(id)
            t:ok(has_event(battle, expected[id]),
                id .. " resolves its behaviour from a physical contact")
        end

        local fortified = simple_target("granite_fortifier", {
            columns = 2,
            lane = 2,
            second_brick = "plain_block",
        })
        t:ok(has_event(fortified, "fortify"),
            "fortifier reduces damage to an adjacent physical brick")
    end

    do
        local ricochet = simple_target("mirror_pane", {
            sling = "ricochet",
            shell = "quartz_banded",
        })
        local reflection = has_event(ricochet, "reflect")
        local rebound = has_event(ricochet, "ricochet")
        t:ok(reflection, "surviving mirror reflects the physical velocity")
        t:ok(rebound, "ricochet sling audits its physical rebound")
        t:ok(reflection and reflection.nx ~= nil and reflection.ny ~= nil,
            "reflection event carries the collision normal")

        local magnetic = simple_target("lodestone_block")
        local field
        for _, item in ipairs(engine.snapshot(magnetic).world.fields) do
            if item.data and item.data.behaviour == "magnetic" then field = item end
        end
        t:ok(field, "lodestone creates a fixed-step radial field in the same world")
        t:ok(has_event(magnetic, "magnetic"), "magnetic contact is audited")
    end

    do
        local battle = engine.new({
            seed = 33,
            max_exchanges = 1,
            max_exchange_ticks = 700,
            sides = {
                A = side("Release", "effect_amplifier", { { "plain_block", "plain_block", "plain_block" } }, {
                    marble("fragile", "obsidian_shard", 2),
                    marble("ally", "quartz_banded", 1),
                }),
                B = side("Cluster", "precision", { { "chalk_block", "chalk_block", "chalk_block" } }, {
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
        battle.world:set_position(ally.body_id, target.x - 7, target.y)
        battle.world:set_position(enemy.body_id, target.x + 7, target.y)
        battle.world:set_velocity(enemy.body_id, 0, 0)
        for _ = 1, 12 do
            if fragile.state == "destroyed" then break end
            engine.step(battle, engine.FIXED_DT)
        end
        t:eq(fragile.state, "destroyed", "fast impact exposes and releases the fragile core")
        t:eq(#battle.sides.A.bag, 1, "released core returns to its owner's bag")
        local blowback = has_event(battle, "blowback")
        t:ok(blowback and #blowback.affected >= 2,
            "one radial release affects a clustered set in the physical world")
        local allied, enemy_hit = false, false
        for _, event in ipairs(events_of(battle, "blowback_impulse")) do
            if event.allied then allied = true else enemy_hit = true end
        end
        t:ok(allied, "release applies allied blowback")
        t:ok(enemy_hit, "release applies enemy blowback")
        t:eq(ally.state, "blown", "a queued ally wakes into the active physical exchange")
        t:ok(battle.world.last_substeps >= 4, "fast collision engages anti-tunnelling microsteps")
    end

    do
        local sides = {
            A = side("A", "precision", { { "chalk_block" } }, {
                marble("A shot", "obsidian_shard", 1),
            }),
            B = side("B", "precision", { { "chalk_block" } }, {
                marble("B shot", "obsidian_shard", 1),
            }),
        }
        local battle, result = engine.simulate({
            seed = 1, sides = sides, max_exchanges = 2,
        })
        t:eq(result.outcome, "draw", "simultaneous formation destruction is a draw")
        t:eq(result.reason, "mutual", "mutual result is explicit")
        t:eq(battle.sides.A.formation.alive, 0, "A formation is destroyed")
        t:eq(battle.sides.B.formation.alive, 0, "B formation is destroyed")
        local destroyed = events_of(battle, "brick_destroyed")
        t:eq(#destroyed, 2, "both physical destructions are audited")
        t:eq(destroyed[1].tick, destroyed[2].tick,
            "both sides resolve their winning hit on the same tick")
    end

    do
        local battle, result = engine.simulate({
            seed = 2,
            max_exchanges = 3,
            sides = {
                A = side("Survivor", "precision", { { "aegis_keystone" } }, {
                    marble("durable", "quartz_banded", 1),
                }),
                B = side("Fragile", "precision", { { "chalk_block" } }, {
                    {
                        name = "deeply shelled",
                        rarity = "legendary",
                        core = "cinder_nucleus",
                        shells = {
                            "obsidian_shard", "flint_spiral", "granite_mottled",
                            "quartz_banded", "jade_lattice",
                        },
                        lane = 1,
                    },
                }),
            },
        })
        t:eq(result.outcome, "victory", "one-sided physical finish produces victory")
        t:eq(result.winner, "A", "surviving side wins")
        t:ok(result.reason:find("bricks_destroyed", 1, true) ~= nil,
            "formation win condition is reported")
        t:eq(battle.sides.B.formation.alive, 0, "losing formation reaches zero")
        t:ok(#battle.sides.A.roster > 0, "winner retains a live marble")
    end

    do
        local function replay_signature()
            local battle = engine.new({
                seed = 20260726,
                sides = setup.default_matchup(),
                max_exchanges = 2,
                max_exchange_ticks = 180,
            })
            engine.run(battle)
            local recording = engine.recording(battle)
            local frame_parts = {}
            for _, frame in ipairs(recording.frames) do
                frame_parts[#frame_parts + 1] = string.format("%d:%d:%d:%d",
                    frame.tick, frame.exchange,
                    frame.sides.A.bricks_alive, frame.sides.B.bricks_alive)
            end
            return battle.log:text(), table.concat(frame_parts, "|"), battle, recording
        end
        local log_a, frames_a, battle, recording = replay_signature()
        local log_b, frames_b = replay_signature()
        t:eq(log_a, log_b, "seeded continuous audit is deterministic")
        t:eq(frames_a, frames_b, "recorded canonical frames are deterministic")
        t:ok(#recording.frames > 2, "battle records visible frames at 30 Hz")
        t:ok(#recording.keyframes >= 1, "battle records seekable keyframes")
        t:eq(recording.final.result.reason, battle.result.reason,
            "recording final frame carries the canonical result")
        recording.frames[1].tick = -1
        t:eq(engine.recording(battle).frames[1].tick, 0,
            "recording API returns value-only copies")
    end

    do
        local battle, result = engine.simulate({
            seed = 9,
            max_exchanges = 1,
            max_exchange_ticks = 1,
            sides = {
                A = side("A", "precision", { { "basalt_absorber" } }, {
                    marble("A", "quartz_banded", 1),
                }),
                B = side("B", "precision", { { "basalt_absorber" } }, {
                    marble("B", "quartz_banded", 1),
                }),
            },
        })
        t:eq(result.reason, "exchange_limit", "battle cap produces an explicit draw")
        local boundary = has_event(battle, "exchange_end")
        t:eq(boundary.reason, "timeout", "per-exchange simulated-time cap is explicit")
        t:eq(boundary.duration_ticks, 1, "timeout is measured in canonical ticks")
    end
end

if arg and arg[0] and arg[0]:find("test_continuous_battle.lua", 1, true) then
    harness.run_one(M)
end

return M
