-- battle/engine.lua -- Callack's canonical continuous autobattle.
--
-- Motion is owned by battle.physics and advances only in exact 1/120 s ticks.
-- This module applies game rules to physical contacts and records snapshots and
-- audit events.  Rendering and replay never invent trajectories.

local RNG = require("battle.rng")
local Log = require("battle.battlelog")
local effects = require("battle.effects")
local formation_mod = require("battle.formation")
local marble_mod = require("battle.marble")
local physics = require("battle.physics")
local rule_ast = require("battle.rule_ast")
local slings = require("battle.content.slings")

local M = {}

M.SCHEMA_VERSION = 2
M.RULES_VERSION = "continuous-v1"
M.FIXED_DT = physics.FIXED_DT
M.DEFAULT_MAX_EXCHANGES = 40
M.DEFAULT_MAX_VOLLEYS = M.DEFAULT_MAX_EXCHANGES -- historical option spelling
M.DEFAULT_EXCHANGE_TICKS = 960
M.FRAME_INTERVAL = 4
M.KEYFRAME_INTERVAL = 120
M.MAX_CHAIN_DEPTH = 3
M.MAX_RELEASE_DEPTH = 3

M.ARENA = {
    width = 70,
    height = 120,
    brick_width = 8,
    brick_height = 5,
    cell_x = 9,
    cell_y = 7,
    top_front_y = 31,
    bottom_front_y = 89,
    top_rack_y = 7,
    bottom_rack_y = 113,
    marble_radius = 1.65,
}

local abs, floor, max, min, sqrt =
    math.abs, math.floor, math.max, math.min, math.sqrt

local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function copy(source, seen)
    if type(source) ~= "table" then return source end
    seen = seen or {}
    if seen[source] then error("canonical state cannot contain cycles") end
    seen[source] = true
    local out = {}
    for key, value in pairs(source) do out[copy(key, seen)] = copy(value, seen) end
    seen[source] = nil
    return out
end

local function quantize(value)
    if type(value) ~= "number" then return value end
    if abs(value) < 0.0000005 then return 0 end
    if value >= 0 then return floor(value * 1000000 + 0.5) / 1000000 end
    return math.ceil(value * 1000000 - 0.5) / 1000000
end

local function remove_from(list, item)
    for index = 1, #list do
        if list[index] == item then
            table.remove(list, index)
            return true
        end
    end
    return false
end

local function contains(list, item)
    for _, value in ipairs(list) do if value == item then return true end end
    return false
end

local function resolve_sling(spec)
    if type(spec) == "table" then
        if not spec.rule_set then
            error("battle sling is missing its canonical RuleSet")
        end
        return slings.runtime(spec.id or spec.content_id, spec.rule_set, spec)
    end
    local id = spec or "training_sling"
    if not slings.has(id) then error("unknown sling: " .. tostring(spec)) end
    return slings.runtime(id)
end

local function sling_attribution_stat(sling)
    local order = {
        "shots_per_volley",
        "ricochet",
        "effect_power",
        "precision",
        "momentum_bonus",
        "damage_bonus",
        "durability_bonus",
        "aim",
        "scatter",
    }
    for _, stat in ipairs(order) do
        if sling._rule_ids and sling._rule_ids[stat] then return stat end
    end
    return nil
end

local function default_lane(index, count, cols)
    return floor(((2 * index - 1) * cols) / (2 * count)) + 1
end

local function lane_x(lane, lanes)
    local total = (lanes - 1) * M.ARENA.cell_x
    return (M.ARENA.width - total) / 2 + (lane - 1) * M.ARENA.cell_x
end

local function brick_position(side_id, row, col, cols)
    local x = lane_x(col, cols)
    if side_id == "A" then
        return x, M.ARENA.bottom_front_y + (row - 1) * M.ARENA.cell_y
    end
    return x, M.ARENA.top_front_y - (row - 1) * M.ARENA.cell_y
end

local function rack_position(side_id, lane, lanes)
    return lane_x(lane, lanes),
        side_id == "A" and M.ARENA.bottom_rack_y or M.ARENA.top_rack_y
end

local function body_id(marble)
    return "marble:" .. tostring(marble.uid)
end

local function box_id(side_id, row, col, brick)
    if brick and brick.uid ~= nil then return "brick:" .. tostring(brick.uid) end
    return string.format("brick:%s:%02d:%02d", side_id, row, col)
end

local function ordered_marble_defs(def)
    local defs = def.marbles or {}
    local order = def.bag_order
    if not order then return defs end
    if #order ~= #defs then
        error(string.format(
            "player %s bag has %d entries for %d marbles",
            tostring(def.name or def.id or "?"),
            #order,
            #defs
        ))
    end
    local by_uid = {}
    for _, marble in ipairs(defs) do
        if marble.uid == nil then error("ordered battle marble is missing uid") end
        if by_uid[marble.uid] then
            error("battle marble roster contains duplicate uid: " .. tostring(marble.uid))
        end
        by_uid[marble.uid] = marble
    end
    local ordered, used = {}, {}
    for _, uid in ipairs(order) do
        local marble = by_uid[uid]
        if not marble then error("battle bag contains unknown marble: " .. tostring(uid)) end
        if used[uid] then error("battle bag repeats marble: " .. tostring(uid)) end
        used[uid] = true
        ordered[#ordered + 1] = marble
    end
    return ordered
end

local function build_player(id, def, cols)
    local sling = resolve_sling(def.sling or def.sling_id)
    local player = {
        id = id,
        name = def.name or id,
        sling = sling,
        formation = formation_mod.build(def.formation, def.bricks),
        rack = {},
        roster = {},
        all_marbles = {},
        queue = {},
        bag = {},
        lanes = cols,
    }
    local defs = ordered_marble_defs(def)
    if #defs < 1 then error(string.format("player %s has no marbles", id)) end
    if #defs > cols then
        error(string.format("player %s has %d marbles but only %d lanes", id, #defs, cols))
    end
    for index, marble_def in ipairs(defs) do
        local marble = marble_mod.build(marble_def, sling, id)
        local lane = marble_def.lane or default_lane(index, #defs, cols)
        if lane < 1 or lane > cols then error("marble lane is outside formation width") end
        if player.rack[lane] then error("two marbles assigned to lane " .. lane) end
        marble.lane = lane
        marble.home_lane = lane
        marble.body_id = body_id(marble)
        marble.state = "ready"
        marble.statuses = {}
        player.rack[lane] = marble
        player.roster[#player.roster + 1] = marble
        player.all_marbles[#player.all_marbles + 1] = marble
        player.queue[#player.queue + 1] = marble
    end
    return player
end

local function initial_side(player)
    local side = {
        id = player.id,
        name = player.name,
        sling_id = player.sling.id,
        sling_name = player.sling.name or player.sling.id,
        rows = player.formation.rows,
        cols = player.formation.cols,
        bricks_alive = player.formation.alive,
        marbles_alive = #player.roster,
        bricks = {},
        marbles = {},
        queue = {},
    }
    for row = 1, player.formation.rows do
        for col = 1, player.formation.cols do
            local brick = player.formation.grid[row][col]
            if brick then
                local x, y = brick_position(player.id, row, col, player.formation.cols)
                side.bricks[#side.bricks + 1] = {
                    id = brick.id, name = brick.name, family = brick.family,
                    behaviour = brick.behaviour, row = row, col = col,
                    hp = brick.hp, max_hp = brick.max_hp, alive = brick.alive,
                    x = x, y = y, width = M.ARENA.brick_width, height = M.ARENA.brick_height,
                }
            end
        end
    end
    for _, marble in ipairs(player.all_marbles) do
        local x, y = rack_position(player.id, marble.lane, player.lanes)
        local item = {
            uid = marble.uid, content_id = marble.content_id,
            name = marble.name, rarity = marble.rarity,
            core = marble.core.name, lane = marble.lane, state = marble.state,
            alive = true, x = x, y = y, radius = M.ARENA.marble_radius, shells = {},
        }
        for _, shell in ipairs(marble.shells) do
            item.shells[#item.shells + 1] = {
                mineral = shell.mineral, pattern = shell.pattern,
                durability = shell.durability, max_durability = shell.max_durability,
            }
        end
        side.marbles[#side.marbles + 1] = item
    end
    for _, marble in ipairs(player.queue) do side.queue[#side.queue + 1] = marble.uid end
    return side
end

local function physics_filter(body, collider)
    if collider.kind == "brick" and body.owner == collider.owner then return false end
    if collider.kind == "marble" and body.owner == collider.owner
        and (not body.dynamic or not collider.dynamic) then
        return false
    end
    return true
end

local function append_event(battle, side, kind, fields)
    fields = fields or {}
    fields.tick = fields.tick or battle.tick
    fields.exchange = fields.exchange or battle.exchange
    fields.schema_version = M.SCHEMA_VERSION
    local event = battle.log:add(battle.exchange, side or "-", kind, fields)
    battle.pending_events[#battle.pending_events + 1] = event
    battle.recording.events[#battle.recording.events + 1] = copy(event)
    return event
end

local function append_rule_event(battle, side, kind, fields, source, stat, source_name)
    rule_ast.attribute(fields, source, stat, { source_name = source_name })
    return append_event(battle, side, kind, fields)
end

local function add_recorded_frame(battle, keyframe)
    local frame = M.snapshot(battle)
    frame.keyframe = keyframe == true
    battle.recording.frames[#battle.recording.frames + 1] = frame
    if keyframe then
        battle.recording.keyframes[#battle.recording.keyframes + 1] = copy(frame)
    end
end

local function create_world(battle)
    local world = physics.new({
        width = M.ARENA.width,
        height = M.ARENA.height,
        fixed_dt = M.FIXED_DT,
        max_speed = 240,
        linear_damping = 0.992,
        sleep_speed = 1.35,
        sleep_ticks = 30,
        restitution = 0.84,
        can_collide = physics_filter,
    })
    for _, side_id in ipairs({ "A", "B" }) do
        local player = battle.sides[side_id]
        for row = 1, player.formation.rows do
            for col = 1, player.formation.cols do
                local brick = player.formation.grid[row][col]
                if brick then
                    local x, y = brick_position(side_id, row, col, player.formation.cols)
                    local profile = effects.brick_profile(brick.behaviour, brick.rule_set)
                    brick.body_id = box_id(side_id, row, col, brick)
                    brick.x, brick.y = x, y
                    world:add_box({
                        id = brick.body_id, kind = "brick", owner = side_id,
                        x = x, y = y, width = M.ARENA.brick_width,
                        height = M.ARENA.brick_height,
                        restitution = profile.reflect and 1.0 or 0.82,
                        data = {
                            row = row, col = col, brick_id = brick.id,
                            brick_name = brick.name,
                            behaviour = brick.behaviour, hp = brick.hp, max_hp = brick.max_hp,
                        },
                    })
                    if profile.field_radius ~= nil then
                        world:add_field({
                            id = "field:" .. brick.body_id, kind = "radial", owner = side_id,
                            x = x, y = y,
                            radius = profile.field_radius,
                            strength = profile.field_strength or 0,
                            duration = nil,
                            data = {
                                behaviour = profile.status or brick.behaviour,
                                brick = brick.body_id,
                                brick_name = brick.name,
                            },
                        })
                    end
                end
            end
        end
        for _, marble in ipairs(player.roster) do
            local x, y = rack_position(side_id, marble.lane, player.lanes)
            local mass = 0.8 + #marble.shells * 0.32 + (marble.momentum or 0) * 0.04
            world:add_body({
                id = marble.body_id, kind = "marble", owner = side_id,
                x = x, y = y, radius = M.ARENA.marble_radius,
                mass = mass, restitution = marble.ricochet and 0.98 or 0.84,
                dynamic = false, asleep = true,
                data = { marble = marble.uid, state = marble.state, shells = #marble.shells },
            })
        end
    end
    world:drain_events()
    return world
end

function M.new(opts)
    assert(type(opts) == "table", "battle.new needs an options table")
    local sides = opts.sides
    local product_handoff = not sides and opts.player and opts.opponent
    if not sides and opts.player and opts.opponent then
        sides = { A = opts.player, B = opts.opponent }
    end
    assert(sides and sides.A and sides.B, "battle.new needs player/opponent or sides A/B")
    marble_mod.reset_uids()
    local a_cols = #sides.A.formation[1]
    local b_cols = #sides.B.formation[1]
    if a_cols ~= b_cols then error("both formations must have the same width") end

    local battle = {
        schema_version = M.SCHEMA_VERSION,
        rules_version = opts.rules_version or M.RULES_VERSION,
        seed = floor(tonumber(opts.battle_seed or opts.seed) or 1),
        rng = RNG.new(opts.battle_seed or opts.seed),
        log = Log.new(),
        tick = 0,
        exchange = 0,
        volley = 0,
        max_exchanges = opts.max_exchanges or opts.max_volleys or M.DEFAULT_MAX_EXCHANGES,
        max_volleys = opts.max_exchanges or opts.max_volleys or M.DEFAULT_MAX_EXCHANGES,
        max_exchange_ticks = opts.max_exchange_ticks or M.DEFAULT_EXCHANGE_TICKS,
        exchange_started_tick = 0,
        lanes = a_cols,
        order = { "A", "B" },
        result_ids = copy(opts.result_ids or (
            product_handoff and { A = "player", B = "opponent" }
            or { A = "A", B = "B" }
        )),
        sides = {},
        active = {},
        active_by_body = {},
        brick_by_body = {},
        marble_by_body = {},
        contact_cooldown = {},
        state = "boundary",
        result = nil,
        pending_events = {},
        recording = {
            schema_version = 1,
            rules_version = opts.rules_version or M.RULES_VERSION,
            battle_seed = floor(tonumber(opts.battle_seed or opts.seed) or 1),
            fixed_dt = M.FIXED_DT,
            frame_interval = M.FRAME_INTERVAL,
            keyframe_interval = M.KEYFRAME_INTERVAL,
            frames = {},
            keyframes = {},
            events = {},
            final = nil,
            result = nil,
        },
    }
    battle.sides.A = build_player("A", sides.A, a_cols)
    battle.sides.B = build_player("B", sides.B, b_cols)
    battle.world = create_world(battle)

    for _, side_id in ipairs(battle.order) do
        local player = battle.sides[side_id]
        for _, marble in ipairs(player.all_marbles) do
            battle.marble_by_body[marble.body_id] = { owner = player, marble = marble }
        end
        for row = 1, player.formation.rows do
            for col = 1, player.formation.cols do
                local brick = player.formation.grid[row][col]
                if brick then battle.brick_by_body[brick.body_id] = { owner = player, brick = brick } end
            end
        end
    end

    append_event(battle, "-", "battle_start", {
        seed = battle.seed, lanes = battle.lanes,
        a_marbles = #battle.sides.A.roster, b_marbles = #battle.sides.B.roster,
        a_bricks = battle.sides.A.formation.alive, b_bricks = battle.sides.B.formation.alive,
        max_exchanges = battle.max_exchanges, fixed_dt = M.FIXED_DT,
        initial_state = {
            protocol_version = 2,
            sides = { A = initial_side(battle.sides.A), B = initial_side(battle.sides.B) },
        },
    })
    add_recorded_frame(battle, true)
    return battle
end

M.new_battle = M.new

local function opponent_of(battle, player)
    return player.id == "A" and battle.sides.B or battle.sides.A
end

local function adjacent_protection(owner, brick)
    local reduction = 0
    local first
    for _, neighbour in ipairs(formation_mod.neighbours(owner.formation, brick.row, brick.col)) do
        local profile = effects.brick_profile(neighbour.behaviour, neighbour.rule_set)
        local amount = profile.protect_adjacent or 0
        reduction = reduction + amount
        if amount > 0 and not first then first = { brick = neighbour, profile = profile } end
    end
    return reduction, first
end

local damage_brick

local function destroy_brick(battle, owner, brick, source, depth)
    if not formation_mod.kill(owner.formation, brick) then return false end
    battle.world:remove_box(brick.body_id, source)
    battle.brick_by_body[brick.body_id] = nil
    local field_id = "field:" .. brick.body_id
    if battle.world:get_field(field_id) then battle.world:remove_field(field_id, "brick_destroyed") end
    append_event(battle, owner.id, "brick_destroyed", {
        brick = brick.id, row = brick.row, col = brick.col,
        source = source, bricks_left = owner.formation.alive,
        x = brick.x, y = brick.y,
    })
    local profile = effects.brick_profile(brick.behaviour, brick.rule_set)
    if (profile.death_splash or 0) > 0 then
        local cadence = profile._cadence and profile._cadence.death_splash or {}
        local chain_limit = cadence.limit or M.MAX_CHAIN_DEPTH
        if (depth or 0) >= chain_limit then
            append_event(battle, owner.id, "chain_capped", {
                row = brick.row, col = brick.col, depth = depth or 0,
            })
        else
            append_rule_event(battle, owner.id, "chain_detonate", {
                brick = brick.id, row = brick.row, col = brick.col,
                damage = profile.death_splash, depth = (depth or 0) + 1,
            }, profile, "death_splash", brick.name)
            battle.world:apply_radial_impulse(brick.x, brick.y, 10, 24, {
                source = brick.body_id, falloff = true,
            })
            for _, neighbour in ipairs(formation_mod.neighbours(owner.formation, brick.row, brick.col)) do
                damage_brick(battle, owner, neighbour, profile.death_splash, "chain", (depth or 0) + 1)
            end
        end
    end
    return true
end

function damage_brick(battle, owner, brick, amount, source, depth)
    if not brick.alive or amount <= 0 then return false end
    brick.hp = brick.hp - amount
    local box = battle.world:get_box(brick.body_id)
    if box then box.data.hp = max(0, brick.hp) end
    append_event(battle, owner.id, "brick_damaged", {
        brick = brick.id, row = brick.row, col = brick.col,
        damage = amount, hp_left = max(0, brick.hp), source = source,
        x = brick.x, y = brick.y,
    })
    if brick.hp <= 0 then return destroy_brick(battle, owner, brick, source, depth) end
    return false
end

local release_core

local function destroy_marble(battle, owner, marble, cause, x, y)
    if marble.state == "destroyed" then return false end
    marble.state = "destroyed"
    if marble.lane and owner.rack[marble.lane] == marble then owner.rack[marble.lane] = nil end
    remove_from(owner.roster, marble)
    remove_from(owner.queue, marble)
    remove_from(battle.active, marble)
    battle.active_by_body[marble.body_id] = nil
    battle.world:remove_body(marble.body_id, cause)
    owner.bag[#owner.bag + 1] = marble.core.id
    append_event(battle, owner.id, "marble_destroyed", {
        marble = marble.uid, name = marble.name, cause = cause,
        marbles_left = #owner.roster, core_bagged = marble.core.id,
        x = quantize(x or 0), y = quantize(y or 0),
    })
    return true
end

local function wear_shell(battle, owner, marble, amount, cause, x, y, depth)
    if marble.state == "destroyed" or amount <= 0 then return false end
    local shell = marble.shells[1]
    if not shell then return false end
    shell.durability = shell.durability - amount
    append_event(battle, owner.id, "shell_damaged", {
        marble = marble.uid, mineral = shell.mineral, damage = amount,
        durability_left = max(0, shell.durability), cause = cause,
        x = quantize(x or 0), y = quantize(y or 0),
    })
    if shell.durability > 0 then return false end
    table.remove(marble.shells, 1)
    local body = battle.world:get_body(marble.body_id)
    if body then body.data.shells = #marble.shells end
    append_event(battle, owner.id, "shell_break", {
        marble = marble.uid, mineral = shell.mineral,
        shells_left = #marble.shells, cause = cause,
        x = quantize(x or 0), y = quantize(y or 0),
    })
    if #marble.shells == 0 then
        release_core(battle, owner, opponent_of(battle, owner), marble, x, y, depth or 1)
        return true
    end
    return false
end

release_core = function(battle, owner, other, marble, x, y, depth)
    if marble.state == "destroyed" then return end
    depth = depth or 1
    if depth > M.MAX_RELEASE_DEPTH then
        append_event(battle, owner.id, "release_capped", {
            marble = marble.uid, x = quantize(x), y = quantize(y), depth = depth,
        })
        destroy_marble(battle, owner, marble, "release_depth_cap", x, y)
        return
    end
    local base = effects.release_profile(marble.core.release, marble.core.rule_set)
    local amplification = marble.effect_power or 0
    local radius = 7 + (base.radius + amplification) * 5
    local strength = 36 + (base.radius + amplification) * 12
    append_rule_event(battle, owner.id, "core_release", {
        marble = marble.uid, core = marble.core.id, release = base.id,
        x = quantize(x), y = quantize(y), radius = radius,
        strength = strength, invert = base.invert, depth = depth,
        amplification = amplification,
    }, base, "radius", marble.core.name)
    destroy_marble(battle, owner, marble, "core_released", x, y)

    local affected = battle.world:apply_radial_impulse(x, y, radius, strength, {
        source = "core:" .. marble.uid,
        invert = base.invert,
        wake_static = true,
        falloff = true,
    })
    append_rule_event(battle, owner.id, "blowback", {
        marble = marble.uid, x = quantize(x), y = quantize(y),
        radius = radius, affected = copy(affected), ally = true, enemy = true,
        invert = base.invert, release = base.id,
    }, base, "radius", marble.core.name)
    for _, affected_id in ipairs(affected) do
        local entry = battle.marble_by_body[affected_id]
        if entry and entry.marble.state ~= "destroyed" then
            local affected_marble = entry.marble
            if affected_marble.state == "ready" then
                affected_marble.state = "blown"
                battle.active[#battle.active + 1] = affected_marble
                battle.active_by_body[affected_id] = affected_marble
            end
            append_event(battle, entry.owner.id, "blowback_impulse", {
                marble = affected_marble.uid,
                source_marble = marble.uid,
                allied = entry.owner.id == owner.id,
            })
            if base.scorch > 0 then
                wear_shell(battle, entry.owner, affected_marble, base.scorch, "scorch",
                    battle.world:get_body(affected_id).x, battle.world:get_body(affected_id).y, depth + 1)
            end
        end
    end

    battle.world:add_field({
        id = string.format("release:%s:%d", tostring(marble.uid), battle.tick),
        kind = "radial", owner = owner.id, x = x, y = y,
        radius = radius,
        strength = base.invert
            and -math.abs(base.field_release_strength or 10)
            or (base.field_release_strength or 10),
        duration = base.field_duration or 24,
        falloff = true,
        data = { behaviour = "release", release = base.id, source_marble = marble.uid },
    })

    if base.shrapnel > 0 then
        local closest, closest_distance
        for _, side_id in ipairs(battle.order) do
            local side = battle.sides[side_id]
            for row = 1, side.formation.rows do
                for col = 1, side.formation.cols do
                    local brick = formation_mod.brick_at(side.formation, row, col)
                    if brick then
                        local dx, dy = brick.x - x, brick.y - y
                        local distance = dx * dx + dy * dy
                        if not closest_distance or distance < closest_distance then
                            closest, closest_distance = { owner = side, brick = brick }, distance
                        end
                    end
                end
            end
        end
        if closest and closest_distance <= 180 then
            damage_brick(battle, closest.owner, closest.brick,
                base.shrapnel + amplification, "shrapnel", 0)
            for _, neighbour in ipairs(formation_mod.neighbours(
                closest.owner.formation, closest.brick.row, closest.brick.col)) do
                damage_brick(battle, closest.owner, neighbour,
                    base.shrapnel + amplification, "shrapnel", 0)
            end
        end
    end
end

local function choose_target(defender, lane, precision)
    local best, best_key
    for row = 1, defender.formation.rows do
        for col = 1, defender.formation.cols do
            local brick = formation_mod.brick_at(defender.formation, row, col)
            if brick then
                local key
                if precision then key = { brick.hp, abs(col - lane), row, col }
                else key = { abs(col - lane), row, col, brick.hp } end
                if not best_key
                    or key[1] < best_key[1]
                    or (key[1] == best_key[1] and key[2] < best_key[2])
                    or (key[1] == best_key[1] and key[2] == best_key[2] and key[3] < best_key[3])
                    or (key[1] == best_key[1] and key[2] == best_key[2]
                        and key[3] == best_key[3] and key[4] < best_key[4]) then
                    best, best_key = brick, key
                end
            end
        end
    end
    return best
end

local function rotate(x, y, angle)
    local cosine, sine = math.cos(angle), math.sin(angle)
    return x * cosine - y * sine, x * sine + y * cosine
end

local function start_marble(battle, player, marble, shot)
    if not marble or marble.state == "destroyed" then
        append_event(battle, player.id, marble and "launch_aborted" or "no_marble", {
            marble = marble and marble.uid or nil,
            reason = marble and "destroyed_before_launch" or "queue_empty",
            shot = shot,
        })
        return
    end
    local defender = opponent_of(battle, player)
    local target = choose_target(defender, marble.lane, marble.precision)
    local start_x, start_y = rack_position(player.id, marble.lane, player.lanes)
    -- Two physical launch rails keep the routine paired shots legible without
    -- disabling marble/marble contacts.  Deflections and blowback can still
    -- cross the rails and collide later in the exchange.
    local rail_offset = player.id == "A" and 2 or -2
    start_x = clamp(start_x + rail_offset, M.ARENA.marble_radius,
        M.ARENA.width - M.ARENA.marble_radius)
    local target_x, target_y
    if target then target_x, target_y = target.x + rail_offset, target.y
    else target_x, target_y = start_x, player.id == "A" and 4 or M.ARENA.height - 4 end
    local dx, dy = target_x - start_x, target_y - start_y
    local length = sqrt(dx * dx + dy * dy)
    dx, dy = dx / length, dy / length
    local scatter = marble.scatter and marble.scatter > 0
        and battle.rng:int(-marble.scatter, marble.scatter) or 0
    -- Core bias is defined in the owner's local facing.  The top side's local
    -- left/right axis is mirrored in world space.
    local facing = player.id == "A" and 1 or -1
    local bias = ((marble.core.trajectory or 0) * 0.055 + scatter * 0.035) * facing
    dx, dy = rotate(dx, dy, bias)
    local freeze = marble.statuses.freeze and marble.statuses.freeze.expires > battle.tick
    local speed = 62 + (marble.momentum or 0) * 7
    if freeze then
        speed = speed * (
            effects.status_profile("freeze", marble.statuses.freeze.rule_set)
                .launch_speed_multiplier
            or 1
        )
    end
    local body = battle.world:get_body(marble.body_id)
    battle.world:set_position(marble.body_id, start_x, start_y)
    battle.world:set_dynamic(marble.body_id, true)
    battle.world:set_velocity(marble.body_id, dx * speed, dy * speed)
    body.data.state = "flying"
    marble.state = "flying"
    if player.rack[marble.lane] == marble then player.rack[marble.lane] = nil end
    battle.active[#battle.active + 1] = marble
    battle.active_by_body[marble.body_id] = marble
    append_rule_event(battle, player.id, "launch", {
        marble = marble.uid, name = marble.name, rarity = marble.rarity,
        lane = marble.lane, target_row = target and target.row or -1,
        target_col = target and target.col or -1,
        x = start_x, y = start_y, vx = quantize(body.vx), vy = quantize(body.vy),
        speed = quantize(speed), shells = #marble.shells,
        trajectory = marble.core.trajectory, core = marble.core.id,
        shot = shot, scatter = scatter, precision = marble.precision,
    }, player.sling, sling_attribution_stat(player.sling), player.sling.name)
end

local function start_exchange(battle)
    if battle.result then return false end
    if battle.exchange >= battle.max_exchanges then
        battle.result = {
            outcome = "draw", winner = nil, reason = "exchange_limit",
            exchanges = battle.exchange, volleys = battle.exchange,
        }
        return false
    end
    battle.exchange = battle.exchange + 1
    battle.volley = battle.exchange
    battle.exchange_started_tick = battle.tick
    battle.state = "running"
    append_event(battle, "-", "exchange_start", {
        a_marbles = #battle.sides.A.roster, b_marbles = #battle.sides.B.roster,
        a_bricks = battle.sides.A.formation.alive, b_bricks = battle.sides.B.formation.alive,
    })
    append_event(battle, "-", "volley_start", {
        a_marbles = #battle.sides.A.roster, b_marbles = #battle.sides.B.roster,
        a_bricks = battle.sides.A.formation.alive, b_bricks = battle.sides.B.formation.alive,
    })
    local launchers, max_shots = {}, 1
    for _, side_id in ipairs(battle.order) do
        local player = battle.sides[side_id]
        local shots = max(1, player.sling.shots_per_volley or 1)
        max_shots = max(max_shots, shots)
        launchers[side_id] = {}
        for shot = 1, shots do launchers[side_id][shot] = table.remove(player.queue, 1) end
    end
    -- Every head is removed before any velocity is applied: commitment is
    -- simultaneous even though stable side ordering is used for bookkeeping.
    for shot = 1, max_shots do
        for _, side_id in ipairs(battle.order) do
            local player = battle.sides[side_id]
            if shot <= max(1, player.sling.shots_per_volley or 1) then
                start_marble(battle, player, launchers[side_id][shot], shot)
            end
        end
    end
    return true
end

local function apply_status_from_field(battle, field_event)
    local entry = battle.marble_by_body[field_event.body]
    local field = battle.world:get_field(field_event.field)
    if not entry or not field or entry.marble.state == "destroyed" then return end
    local behaviour = field.data.behaviour
    local source_entry = battle.brick_by_body[field.data.brick]
    local source_rule_set = source_entry
        and source_entry.brick
        and source_entry.brick.rule_set
    if behaviour ~= "release" and not source_rule_set then
        error("live effect field lost its canonical brick RuleSet")
    end
    if behaviour == "magnetic" then
        local profile = effects.brick_profile(behaviour, source_rule_set)
        local key = "field|" .. field.id .. "|" .. entry.marble.body_id
        if (battle.contact_cooldown[key] or -1000) + 30 <= battle.tick then
            battle.contact_cooldown[key] = battle.tick
            append_rule_event(battle, field.owner, "magnetic", {
                brick = field.data.brick,
                marble = entry.marble.uid,
                field = field.id,
                fx = field_event.fx,
                fy = field_event.fy,
            }, profile, "field_strength", field.data.brick_name)
        end
        return
    end
    if behaviour ~= "poison" and behaviour ~= "freeze" then return end
    if field.owner == entry.owner.id then return end
    local marble = entry.marble
    local status = marble.statuses[behaviour]
    local status_profile = effects.status_profile(behaviour, source_rule_set)
    local brick_profile = effects.brick_profile(behaviour, source_rule_set)
    local tick_cadence = status_profile._cadence and status_profile._cadence.shell_wear
    local expiry = battle.tick + status_profile.duration_ticks
    if not status or status.expires < expiry then
        marble.statuses[behaviour] = {
            expires = expiry,
            next_tick = tick_cadence
                and battle.tick + tick_cadence.interval
                or nil,
            rule_set = rule_ast.copy(source_rule_set),
        }
        append_rule_event(battle, entry.owner.id, "status_applied", {
            marble = marble.uid, status = behaviour,
            expires = expiry, source = field.data.brick,
        }, brick_profile, "status", field.data.brick_name)
    end
    if behaviour == "freeze" then
        local body = battle.world:get_body(marble.body_id)
        local multiplier = status_profile.velocity_multiplier or 1
        if body then body.vx, body.vy = body.vx * multiplier, body.vy * multiplier end
    end
end

local function handle_wall_contact(battle, event)
    local entry = battle.marble_by_body[event.body]
    if not entry or entry.marble.state == "destroyed" then return end
    append_event(battle, entry.owner.id, "wall_collision", {
        marble = entry.marble.uid, wall = event.wall,
        nx = event.nx, ny = event.ny, impulse = event.impulse,
    })
    if entry.marble.ricochet then
        local sling = entry.owner.sling
        append_rule_event(battle, entry.owner.id, "ricochet", {
            marble = entry.marble.uid, surface = "wall",
            nx = event.nx, ny = event.ny,
        }, sling, "ricochet", sling and sling.name)
    end
end

local function handle_body_contact(battle, event)
    local left = battle.marble_by_body[event.a]
    local right = battle.marble_by_body[event.b]
    if not left or not right then return end
    append_event(battle, "-", "marble_collision", {
        a = left.marble.uid, b = right.marble.uid,
        a_owner = left.owner.id, b_owner = right.owner.id,
        nx = event.nx, ny = event.ny, impulse = event.impulse,
    })
end

local function collision_damage(battle, attacker, defender, marble, brick, event)
    if marble.state == "destroyed" or not brick.alive then return end
    local key = marble.body_id .. "|" .. brick.body_id
    if (battle.contact_cooldown[key] or -1000) + 5 > battle.tick then return end
    if (event.impulse or 0) < 2 then return end
    battle.contact_cooldown[key] = battle.tick
    local shell = marble.shells[1]
    if not shell then return end
    local collision = effects.collision_profile(shell.collision, shell.rule_set)
    local profile = effects.brick_profile(brick.behaviour, brick.rule_set)
    local impact_bonus = min(2, floor((event.impulse or 0) / 95))
    local damage = collision.damage + (marble.damage_bonus or 0) + impact_bonus
    if marble.effect_power > 0 and collision.id ~= "chip" then
        damage = damage + marble.effect_power
    end
    local adjacent_armour, protector = adjacent_protection(defender, brick)
    local armour = (profile.damage_reduction or 0) + adjacent_armour
    if armour > 0 and not collision.pierces_absorb then
        damage = max(0, damage - armour)
        local source_profile = (profile.damage_reduction or 0) > 0
            and profile
            or protector.profile
        local source_brick = (profile.damage_reduction or 0) > 0
            and brick
            or protector.brick
        local stat = (profile.damage_reduction or 0) > 0
            and "damage_reduction"
            or "protect_adjacent"
        append_rule_event(battle, defender.id, stat == "damage_reduction" and "absorb" or "fortify", {
            brick = brick.id, row = brick.row, col = brick.col,
            marble = marble.uid, reduction = armour,
        }, source_profile, stat, source_brick.name)
    end
    local aegis_cadence = profile._cadence and profile._cadence.negate_once or {}
    local aegis_charges = aegis_cadence.charges or 1
    local aegis_spent = brick.aegis_spent == true and 1
        or tonumber(brick.aegis_spent)
        or 0
    if profile.negate_once and aegis_spent < aegis_charges and damage > 0 then
        brick.aegis_spent = aegis_spent + 1
        damage = 0
        append_rule_event(battle, defender.id, "aegis", {
            brick = brick.id, row = brick.row, col = brick.col, marble = marble.uid,
        }, profile, "negate_once", brick.name)
    end
    append_rule_event(battle, attacker.id, "collision", {
        marble = marble.uid, effect = collision.id, brick = brick.id,
        row = brick.row, col = brick.col, damage = damage,
        mineral = shell.mineral, pattern = shell.pattern,
        x = quantize(brick.x), y = quantize(brick.y),
        nx = event.nx, ny = event.ny, impulse = event.impulse,
    }, collision, "damage", shell.mineral)
    local hp_before = brick.hp
    damage_brick(battle, defender, brick, damage, "collision", 0)

    if collision.splash_behind > 0 then
        local direction = attacker.id == "A" and -1 or 1
        local behind = formation_mod.brick_at(defender.formation, brick.row + direction, brick.col)
        if behind then damage_brick(battle, defender, behind, collision.splash_behind, "splinter", 0) end
    end
    if (profile.collision_splash or 0) > 0 then
        for _, neighbour in ipairs(formation_mod.neighbours(defender.formation, brick.row, brick.col)) do
            damage_brick(battle, defender, neighbour, profile.collision_splash, "splice", 0)
        end
        append_rule_event(battle, defender.id, "splice", {
            brick = brick.id, row = brick.row, col = brick.col,
            damage = profile.collision_splash,
        }, profile, "collision_splash", brick.name)
    end
    if brick.alive and (profile.heal_after_hit or 0) > 0 then
        local old = brick.hp
        brick.hp = min(brick.max_hp, brick.hp + profile.heal_after_hit)
        local box = battle.world:get_box(brick.body_id)
        if box then box.data.hp = brick.hp end
        if brick.hp > old then
            append_rule_event(battle, defender.id, "regenerate", {
                brick = brick.id, row = brick.row, col = brick.col,
                healed = brick.hp - old, hp_left = brick.hp,
            }, profile, "heal_after_hit", brick.name)
        end
    end
    if brick.alive and profile.rewind and brick.hp < hp_before then
        brick.hp = hp_before
        local box = battle.world:get_box(brick.body_id)
        if box then box.data.hp = brick.hp end
        append_rule_event(battle, defender.id, "temporal", {
            brick = brick.id, row = brick.row, col = brick.col, hp_left = brick.hp,
        }, profile, "rewind", brick.name)
    end
    if profile.reflect and brick.alive then
        local body = battle.world:get_body(marble.body_id)
        if body then
            body.vx, body.vy = body.vx * profile.reflect, body.vy * profile.reflect
        end
        append_rule_event(
            battle,
            defender.id,
            brick.behaviour == "mirror" and "mirror" or "reflect",
            {
            brick = brick.id, row = brick.row, col = brick.col,
            marble = marble.uid, nx = event.nx, ny = event.ny,
            },
            profile,
            "reflect",
            brick.name
        )
    end
    if marble.ricochet then
        local sling = attacker.sling
        append_rule_event(battle, attacker.id, "ricochet", {
            marble = marble.uid, row = brick.row, col = brick.col,
            nx = event.nx, ny = event.ny,
        }, sling, "ricochet", sling and sling.name)
    end
    if (profile.field_strength or 0) < 0 then
        append_rule_event(battle, defender.id, "magnetic", {
            brick = brick.id, row = brick.row, col = brick.col, marble = marble.uid,
        }, profile, "field_strength", brick.name)
    end
    if (profile.shell_wear or 0) > 1 then
        append_rule_event(battle, defender.id, "shatter", {
            brick = brick.id, row = brick.row, col = brick.col,
            marble = marble.uid, wear = profile.shell_wear,
        }, profile, "shell_wear", brick.name)
    end
    if (profile.momentum_delta or 0) > 0 then
        append_rule_event(battle, defender.id, "vault", {
            brick = brick.id, row = brick.row, col = brick.col,
            marble = marble.uid, impulse_delta = profile.momentum_delta or 0,
        }, profile, "momentum_delta", brick.name)
    end
    if profile.harmless then
        append_rule_event(battle, defender.id, "dummy", {
            brick = brick.id, row = brick.row, col = brick.col, marble = marble.uid,
        }, profile, "harmless", brick.name)
    end
    if profile.break_shell then
        append_rule_event(battle, defender.id, "void", {
            brick = brick.id, row = brick.row, col = brick.col, marble = marble.uid,
        }, profile, "break_shell", brick.name)
    end
    if (profile.momentum_delta or 0) ~= 0 then
        local body = battle.world:get_body(marble.body_id)
        if body then
            local speed = sqrt(body.vx * body.vx + body.vy * body.vy)
            if speed > 0 then
                local change = profile.momentum_delta * 7
                local next_speed = max(0, speed + change)
                body.vx, body.vy = body.vx / speed * next_speed, body.vy / speed * next_speed
            end
        end
    end

    local wear = collision.durability_cost + (profile.shell_wear or 0)
    if profile.harmless then wear = 0 end
    if profile.break_shell then wear = max(wear, shell.durability) end
    wear_shell(battle, attacker, marble, wear, "collision", brick.x, brick.y, 1)
end

local function handle_box_contact(battle, event)
    local attacker = battle.marble_by_body[event.body]
    local defender = battle.brick_by_body[event.box]
    if not attacker or not defender then return end
    collision_damage(battle, attacker.owner, defender.owner, attacker.marble, defender.brick, event)
end

local function process_physics_events(battle, events)
    for _, event in ipairs(events) do
        if event.type == "box_collision" then handle_box_contact(battle, event)
        elseif event.type == "body_collision" then handle_body_contact(battle, event)
        elseif event.type == "wall_collision" then handle_wall_contact(battle, event)
        elseif event.type == "field_contact" then apply_status_from_field(battle, event)
        elseif event.type == "speed_clamped" then
            local entry = battle.marble_by_body[event.body]
            append_event(battle, entry and entry.owner.id or "-", "speed_clamped", {
                marble = entry and entry.marble.uid or nil, speed = event.speed,
            })
        elseif event.type == "body_sleep" then
            local entry = battle.marble_by_body[event.body]
            if entry then
                append_event(battle, entry.owner.id, "marble_sleep", { marble = entry.marble.uid })
            end
        end
    end
end

local function tick_statuses(battle)
    for _, side_id in ipairs(battle.order) do
        local owner = battle.sides[side_id]
        local roster = {}
        for _, marble in ipairs(owner.roster) do roster[#roster + 1] = marble end
        for _, marble in ipairs(roster) do
            local poison = marble.statuses.poison
            if poison and poison.expires <= battle.tick then
                marble.statuses.poison = nil
                append_event(battle, owner.id, "status_expired", {
                    marble = marble.uid, status = "poison",
                })
            elseif poison and poison.next_tick and poison.next_tick <= battle.tick then
                local body = battle.world:get_body(marble.body_id)
                local profile = effects.status_profile("poison", poison.rule_set)
                append_rule_event(battle, owner.id, "status_tick", {
                    marble = marble.uid, status = "poison",
                }, profile, "shell_wear", "Poison")
                poison.next_tick = poison.next_tick + profile._cadence.shell_wear.interval
                wear_shell(battle, owner, marble, profile.shell_wear, "poison",
                    body and body.x or 0, body and body.y or 0, 1)
            end
            local freeze = marble.statuses.freeze
            if freeze and freeze.expires <= battle.tick then
                marble.statuses.freeze = nil
                append_event(battle, owner.id, "status_expired", {
                    marble = marble.uid, status = "freeze",
                })
            end
        end
    end
end

local function evaluate(battle)
    local a, b = battle.sides.A, battle.sides.B
    local a_reasons, b_reasons = {}, {}
    if b.formation.alive == 0 then a_reasons[#a_reasons + 1] = "bricks_destroyed" end
    if #b.roster == 0 then a_reasons[#a_reasons + 1] = "opponent_marbles_destroyed" end
    if a.formation.alive == 0 then b_reasons[#b_reasons + 1] = "bricks_destroyed" end
    if #a.roster == 0 then b_reasons[#b_reasons + 1] = "opponent_marbles_destroyed" end
    if #a_reasons > 0 and #b_reasons > 0 then
        return {
            outcome = "draw", winner = nil, reason = "mutual",
            a_reason = table.concat(a_reasons, "+"),
            b_reason = table.concat(b_reasons, "+"),
            exchanges = battle.exchange, volleys = battle.exchange,
        }
    end
    if #a_reasons > 0 then
        return {
            outcome = "victory", winner = battle.result_ids.A,
            reason = table.concat(a_reasons, "+"),
            exchanges = battle.exchange, volleys = battle.exchange,
        }
    end
    if #b_reasons > 0 then
        return {
            outcome = "victory", winner = battle.result_ids.B,
            reason = table.concat(b_reasons, "+"),
            exchanges = battle.exchange, volleys = battle.exchange,
        }
    end
    return nil
end

local function park_marble(battle, marble, timeout)
    if marble.state == "destroyed" then return end
    local entry = battle.marble_by_body[marble.body_id]
    if not entry then return end
    local owner = entry.owner
    local lane = marble.lane or marble.home_lane
    if owner.rack[lane] and owner.rack[lane] ~= marble then
        for offset = 1, owner.lanes do
            local left, right = lane - offset, lane + offset
            if left >= 1 and not owner.rack[left] then lane = left break end
            if right <= owner.lanes and not owner.rack[right] then lane = right break end
        end
    end
    marble.lane = lane
    marble.state = "ready"
    owner.rack[lane] = marble
    local x, y = rack_position(owner.id, lane, owner.lanes)
    battle.world:set_position(marble.body_id, x, y)
    battle.world:set_dynamic(marble.body_id, false)
    local body = battle.world:get_body(marble.body_id)
    body.data.state = "ready"
    if not contains(owner.queue, marble) then owner.queue[#owner.queue + 1] = marble end
    append_event(battle, owner.id, "rack_return", {
        marble = marble.uid, lane = lane, shells_left = #marble.shells,
        timeout = timeout == true,
    })
end

local function finish_battle(battle)
    if not battle.result then return end
    battle.state = "finished"
    append_event(battle, "-", "battle_end", {
        outcome = battle.result.outcome, winner = battle.result.winner or "none",
        reason = battle.result.reason, exchanges = battle.result.exchanges,
        volleys = battle.result.exchanges,
        a_bricks = battle.sides.A.formation.alive,
        b_bricks = battle.sides.B.formation.alive,
        a_marbles = #battle.sides.A.roster,
        b_marbles = #battle.sides.B.roster,
    })
    battle.recording.result = copy(battle.result)
    battle.recording.final = M.snapshot(battle)
    add_recorded_frame(battle, true)
end

local function complete_exchange(battle, timeout)
    local active = {}
    for _, marble in ipairs(battle.active) do active[#active + 1] = marble end
    battle.active, battle.active_by_body = {}, {}
    for _, marble in ipairs(active) do park_marble(battle, marble, timeout) end
    battle.state = "boundary"
    append_event(battle, "-", "exchange_end", {
        reason = timeout and "timeout" or "settled",
        duration_ticks = battle.tick - battle.exchange_started_tick,
        a_bricks = battle.sides.A.formation.alive,
        b_bricks = battle.sides.B.formation.alive,
        a_marbles = #battle.sides.A.roster,
        b_marbles = #battle.sides.B.roster,
    })
    battle.result = evaluate(battle)
    if not battle.result and battle.exchange >= battle.max_exchanges then
        battle.result = {
            outcome = "draw", winner = nil, reason = "exchange_limit",
            exchanges = battle.exchange, volleys = battle.exchange,
        }
    end
    if battle.result then finish_battle(battle) end
end

function M.step(battle, dt)
    assert(type(battle) == "table" and battle.world, "battle.step needs a BattleWorld")
    if battle.result then return {} end
    dt = dt or M.FIXED_DT
    if abs(dt - M.FIXED_DT) > 1e-12 then
        error(string.format("battle step must equal fixed dt %.12f", M.FIXED_DT))
    end
    if battle.state == "boundary" and not start_exchange(battle) then
        if battle.result then finish_battle(battle) end
        return M.drain_events(battle)
    end

    local physics_events = battle.world:step(M.FIXED_DT)
    battle.tick = battle.world.tick
    process_physics_events(battle, physics_events)
    tick_statuses(battle)
    if battle.tick % M.FRAME_INTERVAL == 0 then
        add_recorded_frame(battle, battle.tick % M.KEYFRAME_INTERVAL == 0)
    end

    local timeout = battle.tick - battle.exchange_started_tick >= battle.max_exchange_ticks
    local settled = #battle.active == 0 or battle.world:is_settled()
    if timeout or settled then complete_exchange(battle, timeout) end
    return M.drain_events(battle)
end

function M.run(battle)
    while not battle.result do M.step(battle, M.FIXED_DT) end
    return battle.result
end

function M.simulate(opts)
    local battle = M.new(opts)
    local result = M.run(battle)
    return battle, result
end

function M.result(battle)
    return battle.result and copy(battle.result) or nil
end

function M.drain_events(battle)
    local events = battle.pending_events
    battle.pending_events = {}
    return events
end

local function snapshot_side(battle, player)
    local side = {
        id = player.id, name = player.name,
        sling_id = player.sling.id, sling_name = player.sling.name or player.sling.id,
        rows = player.formation.rows, cols = player.formation.cols,
        bricks_alive = player.formation.alive, marbles_alive = #player.roster,
        bricks = {}, marbles = {}, queue = {}, bag = copy(player.bag),
    }
    for row = 1, player.formation.rows do
        for col = 1, player.formation.cols do
            local brick = player.formation.grid[row][col]
            if brick then
                side.bricks[#side.bricks + 1] = {
                    body_id = brick.body_id, id = brick.id, uid = brick.uid,
                    name = brick.name,
                    family = brick.family, behaviour = brick.behaviour,
                    row = row, col = col, hp = brick.hp, max_hp = brick.max_hp,
                    alive = brick.alive, x = brick.x, y = brick.y,
                    width = M.ARENA.brick_width, height = M.ARENA.brick_height,
                }
            end
        end
    end
    for _, marble in ipairs(player.all_marbles) do
        local body = battle.world:get_body(marble.body_id)
        local item = {
            body_id = marble.body_id, uid = marble.uid, content_id = marble.content_id,
            name = marble.name,
            rarity = marble.rarity, core = marble.core.name, core_id = marble.core.id,
            lane = marble.lane, state = marble.state,
            alive = marble.state ~= "destroyed", radius = M.ARENA.marble_radius,
            statuses = copy(marble.statuses), shells = {},
        }
        if body then
            item.x, item.y = quantize(body.x), quantize(body.y)
            item.previous_x, item.previous_y = quantize(body.previous_x), quantize(body.previous_y)
            item.vx, item.vy = quantize(body.vx), quantize(body.vy)
            item.asleep = body.asleep
        end
        for _, shell in ipairs(marble.shells) do
            item.shells[#item.shells + 1] = {
                mineral = shell.mineral, pattern = shell.pattern,
                durability = shell.durability, max_durability = shell.max_durability,
            }
        end
        side.marbles[#side.marbles + 1] = item
    end
    for _, marble in ipairs(player.queue) do side.queue[#side.queue + 1] = marble.uid end
    return side
end

function M.snapshot(battle)
    return {
        schema_version = M.SCHEMA_VERSION,
        rules_version = battle.rules_version,
        seed = battle.seed,
        tick = battle.tick,
        time = quantize(battle.tick * M.FIXED_DT),
        fixed_dt = M.FIXED_DT,
        exchange = battle.exchange,
        volley = battle.exchange,
        phase = battle.result and "result" or "battle",
        state = battle.state,
        arena = copy(M.ARENA),
        world = battle.world:snapshot(),
        sides = {
            A = snapshot_side(battle, battle.sides.A),
            B = snapshot_side(battle, battle.sides.B),
        },
        result = battle.result and copy(battle.result) or nil,
    }
end

function M.recording(battle)
    local recording = copy(battle.recording)
    if battle.result and not recording.final then recording.final = M.snapshot(battle) end
    return recording
end

return M
