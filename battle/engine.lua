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
local setup_rules = require("battle.setup_rules")
local slings = require("battle.content.slings")

local M = {}

-- Capability keys and state never enter battle snapshots, replay, logs, or
-- caller-owned tables. Deserialised or recursively copied operation payloads
-- therefore cannot manufacture engine authority.
local PRIVATE = setmetatable({}, { __mode = "k" })
local AUTHORITY_KEY, SOURCE_KEY = {}, {}
local HOSTILE_AUTHORITY, COST_AUTHORITY = {}, {}

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
M.MAX_CASCADE_GENERATION = 3
M.MAX_CASCADE_ACTIVATIONS = 16
M.MAX_BRICK_HARM_ATTEMPTS = 32

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

local function equal_values(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not equal_values(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
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

local function build_player(id, def, cols, canonical_handoff)
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
        if canonical_handoff and marble_def.lane ~= nil then
            error("product battle marble lane must derive from canonical bag order")
        end
        local marble = marble_mod.build(marble_def, sling, id, canonical_handoff)
        local lane = canonical_handoff
            and default_lane(index, #defs, cols)
            or marble_def.lane
            or default_lane(index, #defs, cols)
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
                    behaviour = brick.behaviour, rarity = brick.rarity,
                    row = row, col = col,
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
    if fields.rule_id then
        rule_ast.attribute_rule_id(fields, fields.rule_id)
        fields.amount = fields.amount
            or fields.applied_damage
            or fields.damage
            or fields.rule_magnitude
        fields.unit = fields.unit or fields.rule_unit
        if fields.target_relation == nil then
            local entry = rule_ast.resolve(fields.rule_id)
            fields.target_relation = entry
                and entry.rule
                and entry.rule.target
                and entry.rule.target.relation
                or nil
        end
    end
    fields.tick = fields.tick or battle.tick
    fields.exchange = fields.exchange or battle.exchange
    fields.schema_version = M.SCHEMA_VERSION
    local event = battle.log:add(battle.exchange, side or "-", kind, fields)
    event.event_id = event.event_id or event.seq
    event.root_event_id = event.root_event_id or event.event_id
    event.parent_event_id = event.parent_event_id or event.root_event_id
    event.generation = event.generation or 0
    battle.pending_events[#battle.pending_events + 1] = event
    battle.recording.events[#battle.recording.events + 1] = copy(event)
    return event
end

local function cascade_state(battle, root_event_id)
    if root_event_id == nil then return nil end
    local state = battle.cascade_attempts[root_event_id]
    if not state then
        state = {
            ability_activations = 0,
            brick_harm_attempts = 0,
            capped = {},
        }
        battle.cascade_attempts[root_event_id] = state
    end
    return state
end

local function cascade_refused(battle, side, root_event_id, cap_reason, fields)
    local state = cascade_state(battle, root_event_id)
    if state and state.capped[cap_reason] then return false end
    if state then state.capped[cap_reason] = true end
    fields = fields or {}
    fields.root_event_id = root_event_id
    fields.cap_reason = cap_reason
    append_event(battle, side, "cascade_capped", fields)
    return false
end

local function cascade_has_room(battle, root_event_id, counter, limit)
    local state = cascade_state(battle, root_event_id)
    return not state or state[counter] < limit
end

local function reserve_cascade(battle, side, root_event_id, counter, limit, fields)
    local state = cascade_state(battle, root_event_id)
    if not state then return true end
    if state[counter] >= limit then
        return cascade_refused(battle, side, root_event_id, counter, fields)
    end
    state[counter] = state[counter] + 1
    return true
end

local CASCADE_PHASE_ORDER = {
    before = 1,
    during = 2,
    after = 3,
}

local function cascade_work_less(left, right)
    local left_keys = {
        left.tick or 0,
        CASCADE_PHASE_ORDER[left.phase] or CASCADE_PHASE_ORDER.after,
        left.generation or 0,
        tostring(left.source_owner or "-"),
        left.source_row or 0,
        left.source_col or 0,
        tostring(left.source_uid or ""),
        tostring(left.ability_id or ""),
        left.payoff_index or 0,
        tostring(left.target_uid or ""),
        left.enqueue_index or 0,
    }
    local right_keys = {
        right.tick or 0,
        CASCADE_PHASE_ORDER[right.phase] or CASCADE_PHASE_ORDER.after,
        right.generation or 0,
        tostring(right.source_owner or "-"),
        right.source_row or 0,
        right.source_col or 0,
        tostring(right.source_uid or ""),
        tostring(right.ability_id or ""),
        right.payoff_index or 0,
        tostring(right.target_uid or ""),
        right.enqueue_index or 0,
    }
    for index = 1, #left_keys do
        if left_keys[index] ~= right_keys[index] then
            return left_keys[index] < right_keys[index]
        end
    end
    return false
end

local function enqueue_cascade(battle, work)
    battle.next_cascade_work_id = (battle.next_cascade_work_id or 0) + 1
    work.enqueue_index = battle.next_cascade_work_id
    work.tick = work.tick or battle.tick
    work.phase = work.phase or "after"
    battle.cascade_queue[#battle.cascade_queue + 1] = work
end

local function drain_cascade(battle)
    if battle.cascade_draining then return end
    battle.cascade_draining = true
    while #battle.cascade_queue > 0 do
        table.sort(battle.cascade_queue, cascade_work_less)
        local work = table.remove(battle.cascade_queue, 1)
        work.run()
    end
    battle.cascade_draining = false
end

local function append_rule_event(battle, side, kind, fields, source, stat, source_name)
    rule_ast.attribute(fields, source, stat, { source_name = source_name })
    fields.source_owner = fields.source_owner or (side ~= "-" and side or nil)
    fields.amount = fields.amount or fields.rule_magnitude
    fields.unit = fields.unit or fields.rule_unit
    if fields.target_relation == nil and fields.rule_id then
        local entry = rule_ast.resolve(fields.rule_id)
        fields.target_relation = entry
            and entry.rule
            and entry.rule.target
            and entry.rule.target.relation
            or nil
    end
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
                        restitution = brick.restitution or profile.restitution or 0.82,
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

local function verified_handoff_links(def)
    if not def.bricks then return {} end
    local links, errors = setup_rules.resolve_ability_links(def)
    if #errors > 0 then
        error("battle handoff has unresolved allied-cost link: " .. errors[1].code)
    end
    local supplied = def.ability_links or {}
    local function canonical(value)
        local function scalar(item)
            if type(item) == "string" then return string.format("%q", item) end
            if type(item) ~= "table" then return tostring(item) end
            local keys = {}
            for key in pairs(item) do keys[#keys + 1] = key end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            local out = {}
            for _, key in ipairs(keys) do
                out[#out + 1] = tostring(key) .. ":" .. scalar(item[key])
            end
            return "{" .. table.concat(out, ",") .. "}"
        end
        return scalar(value)
    end
    if canonical(supplied) ~= canonical(links) then
        error("battle handoff allied-cost links are stale, retargeted, or altered")
    end
    return links
end

function M.new(opts)
    assert(type(opts) == "table", "battle.new needs an options table")
    local sides = opts.sides
    local product_handoff = not sides and opts.player and opts.opponent
    if not sides and opts.player and opts.opponent then
        sides = { A = opts.player, B = opts.opponent }
    end
    assert(sides and sides.A and sides.B, "battle.new needs player/opponent or sides A/B")
    local handoff_links = {
        A = verified_handoff_links(sides.A),
        B = verified_handoff_links(sides.B),
    }
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
        ability_links = {},
        authorizations = {},
        next_activation_id = 0,
        cascade_attempts = {},
        cascade_queue = {},
        cascade_draining = false,
        next_cascade_work_id = 0,
        rule_set_identities = {},
        enforce_rule_set_identity = true,
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
    battle.sides.A = build_player("A", sides.A, a_cols, product_handoff)
    battle.sides.B = build_player("B", sides.B, b_cols, product_handoff)
    local security = {
        authorizations = {},
        owner_by_entity = setmetatable({}, { __mode = "k" }),
        owner_by_brick = setmetatable({}, { __mode = "k" }),
        identities = setmetatable({}, { __mode = "k" }),
        sources_by_id = {},
    }
    PRIVATE[battle] = security
    for _, side_id in ipairs(battle.order) do
        for _, link in ipairs(handoff_links[side_id]) do
            battle.ability_links[
                side_id .. "|" .. tostring(link.source_uid) .. "|" .. link.ability_id
            ] = copy(link)
        end
    end
    battle.world = create_world(battle)

    for _, side_id in ipairs(battle.order) do
        local player = battle.sides[side_id]
        for _, marble in ipairs(player.all_marbles) do
            battle.marble_by_body[marble.body_id] = { owner = player, marble = marble }
            security.owner_by_entity[marble] = player
            security.identities[marble] = {
                rule_set = marble.rule_set and rule_ast.canonical(marble.rule_set) or nil,
                core = rule_ast.canonical(marble.core.rule_set),
                sling = rule_ast.canonical(marble.sling_rule_set),
                shells = setmetatable({}, { __mode = "k" }),
            }
            for _, shell in ipairs(marble.shells) do
                security.identities[marble].shells[shell] =
                    rule_ast.canonical(shell.rule_set)
            end
            for _, identity in ipairs({
                marble.uid, marble.body_id, tostring(marble.uid), tostring(marble.body_id),
            }) do
                security.sources_by_id[identity] = security.sources_by_id[identity] or {}
                security.sources_by_id[identity][#security.sources_by_id[identity] + 1] = marble
            end
        end
        for row = 1, player.formation.rows do
            for col = 1, player.formation.cols do
                local brick = player.formation.grid[row][col]
                if brick then
                    battle.brick_by_body[brick.body_id] = { owner = player, brick = brick }
                    security.owner_by_entity[brick] = player
                    security.owner_by_brick[brick] = player
                    security.identities[brick] = rule_ast.canonical(brick.rule_set)
                    battle.rule_set_identities[
                        side_id .. "|" .. tostring(brick.uid)
                    ] = security.identities[brick]
                    for _, identity in ipairs({
                        brick.uid, brick.body_id, tostring(brick.uid), tostring(brick.body_id),
                    }) do
                        security.sources_by_id[identity] =
                            security.sources_by_id[identity] or {}
                        security.sources_by_id[identity][
                            #security.sources_by_id[identity] + 1
                        ] = brick
                    end
                end
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

local apply_brick_harm
local wear_shell
local brick_by_uid

local function chain_contract(profile, cause)
    for _, ability in ipairs(profile._abilities or {}) do
        if ability.id == "chain" then
            for _, accepted in ipairs((ability.recursion and ability.recursion.accepts_causes) or {}) do
                if accepted == cause then return ability end
            end
        end
    end
    return nil
end

local function destroy_brick(battle, owner, brick, request)
    if not formation_mod.kill(owner.formation, brick) then return false end
    request = request or {}
    local source_owner_known = request.source_owner ~= nil
        and battle.sides[request.source_owner] ~= nil
    local target_relation = request.source_owner == owner.id and "allied"
        or source_owner_known and "enemy"
        or "unknown"
    battle.world:remove_box(brick.body_id, request.cause)
    battle.brick_by_body[brick.body_id] = nil
    local field_id = "field:" .. brick.body_id
    if battle.world:get_field(field_id) then battle.world:remove_field(field_id, "brick_destroyed") end
    local destroyed_event = append_event(battle, owner.id, "brick_destroyed", {
        brick = brick.id, row = brick.row, col = brick.col,
        source = request.cause, cause = request.cause,
        source_owner = request.source_owner,
        source_entity_id = request.source_entity_id,
        source_rule_set_id = request.source_rule_set_id,
        rule_id = request.rule_id,
        ability_id = request.ability_id,
        operation = request.operation or "deal",
        target_selector = request.target_selector or "struck_brick",
        target_owner = owner.id,
        target_entity_id = brick.uid or brick.body_id,
        target_relation = target_relation,
        amount = request.applied_damage or request.requested_damage or 0,
        unit = request.unit or "damage",
        root_event_id = request.root_event_id,
        parent_event_id = request.parent_event_id,
        generation = request.generation or 0,
        activation_id = request.activation_id,
        authorization_id = request.authorization_id,
        linked_source_uid = request.linked_source_uid,
        linked_target_uid = request.linked_target_uid,
        bricks_left = owner.formation.alive,
        x = brick.x, y = brick.y,
    })
    local profile = effects.brick_profile(brick.behaviour, brick.rule_set)
    local chain = chain_contract(profile, request.cause)
    if (profile.chain_shell_wear or 0) > 0 and chain then
        local chain_rule = rule_ast.rule(brick.rule_set, "brick.chain.shell_wear")
        local max_generation = chain.recursion.max_generation
        local radius = chain_rule.target.radius
        local max_targets = chain_rule.target.count
        local generation = (request.generation or 0) + 1
        local root_event_id = request.root_event_id or destroyed_event.root_event_id
        if generation > max_generation or generation > M.MAX_CASCADE_GENERATION then
            cascade_refused(battle, owner.id, root_event_id, "generation", {
                brick = brick.id,
                source_owner = owner.id,
                source_entity_id = brick.uid or brick.body_id,
                source_rule_set_id = brick.rule_set.id,
                rule_id = "brick.chain.shell_wear",
                ability_id = "chain",
                parent_event_id = destroyed_event.event_id,
                generation = generation,
            })
        elseif not reserve_cascade(
            battle,
            owner.id,
            root_event_id,
            "ability_activations",
            M.MAX_CASCADE_ACTIVATIONS,
            {
                brick = brick.id,
                source_owner = owner.id,
                source_entity_id = brick.uid or brick.body_id,
                source_rule_set_id = brick.rule_set.id,
                rule_id = "brick.chain.shell_wear",
                ability_id = "chain",
                parent_event_id = destroyed_event.event_id,
                generation = generation,
            }
        ) then
            -- The cap event is the complete, attributed refusal.
        else
            enqueue_cascade(battle, {
                generation = generation,
                source_owner = owner.id,
                source_row = brick.row,
                source_col = brick.col,
                source_uid = brick.uid or brick.body_id,
                ability_id = "chain",
                run = function()
                    local enemy = opponent_of(battle, owner)
                    local causal = request.source_marble
                    local targets, seen = {}, {}
                    if causal and causal.state ~= "destroyed"
                        and request.source_owner == enemy.id then
                        targets[#targets + 1] = causal
                        seen[causal.body_id] = true
                    end
                    local nearby = {}
                    for _, marble in ipairs(enemy.roster) do
                        local body = battle.world:get_body(marble.body_id)
                        if body and not seen[marble.body_id] then
                            local dx, dy = body.x - brick.x, body.y - brick.y
                            local distance = dx * dx + dy * dy
                            if distance <= radius * radius then
                                nearby[#nearby + 1] = { marble = marble, distance = distance }
                            end
                        end
                    end
                    table.sort(nearby, function(left, right)
                        if left.distance ~= right.distance then
                            return left.distance < right.distance
                        end
                        return tostring(left.marble.body_id) < tostring(right.marble.body_id)
                    end)
                    for _, candidate in ipairs(nearby) do
                        if #targets >= max_targets then break end
                        targets[#targets + 1] = candidate.marble
                    end
                    append_rule_event(battle, owner.id, "chain_retaliate", {
                        brick = brick.id,
                        target_count = #targets,
                        source_owner = owner.id,
                        source_entity_id = brick.uid or brick.body_id,
                        source_rule_set_id = brick.rule_set.id,
                        target_owner = enemy.id,
                        target_relation = "enemy",
                        root_event_id = root_event_id,
                        parent_event_id = destroyed_event.event_id,
                        generation = generation,
                        ability_id = "chain",
                    }, profile, "chain_shell_wear", brick.name)
                    for _, marble in ipairs(targets) do
                        local body = battle.world:get_body(marble.body_id)
                        local targeted_event = append_event(battle, owner.id, "chain_targeted", {
                            source_owner = owner.id,
                            source_entity_id = brick.uid or brick.body_id,
                            source_rule_set_id = brick.rule_set.id,
                            rule_id = "brick.chain.shell_wear",
                            ability_id = "chain",
                            operation = "wear",
                            target_selector = "chain_enemy_marbles",
                            target_owner = enemy.id,
                            target_entity_id = marble.uid,
                            target_relation = "enemy",
                            amount = profile.chain_shell_wear,
                            unit = "durability",
                            root_event_id = root_event_id,
                            parent_event_id = destroyed_event.event_id,
                            generation = generation,
                            cause = "chain",
                            x = body and body.x or brick.x,
                            y = body and body.y or brick.y,
                        })
                        wear_shell(
                            battle,
                            enemy,
                            marble,
                            profile.chain_shell_wear,
                            "chain",
                            body and body.x or brick.x,
                            body and body.y or brick.y,
                            generation,
                            {
                                source_owner = owner.id,
                                source_entity_id = brick.uid or brick.body_id,
                                source_rule_set_id = brick.rule_set.id,
                                rule_id = "brick.chain.shell_wear",
                                ability_id = "chain",
                                operation = "wear",
                                target_selector = "chain_enemy_marbles",
                                target_relation = "enemy",
                                root_event_id = root_event_id,
                                parent_event_id = targeted_event.event_id,
                                generation = generation,
                            }
                        )
                    end
                end,
            })
        end
    end
    return true
end

local function entity_identity_valid(security, entity)
    local expected = security.identities[entity]
    if type(expected) == "string" then
        local ok, current = pcall(rule_ast.canonical, entity.rule_set)
        return ok and current == expected
    end
    if type(expected) ~= "table" then return false end
    local function same(rule_set, canonical)
        local ok, current = pcall(rule_ast.canonical, rule_set)
        return ok and current == canonical
    end
    if expected.rule_set
        and not same(entity.rule_set, expected.rule_set) then return false end
    if not same(entity.core and entity.core.rule_set, expected.core)
        or not same(entity.sling_rule_set, expected.sling) then return false end
    for _, shell in ipairs(entity.shells or {}) do
        local canonical = expected.shells[shell]
        if not canonical or not same(shell.rule_set, canonical) then
            return false
        end
    end
    return true
end

local function resolve_source(battle, request)
    local security = PRIVATE[battle]
    if not security then return nil, nil, "engine_state_missing" end
    local entity = request[SOURCE_KEY] or request.source_marble
    if not entity then
        local identity = request.source_entity_id or request.source_uid
        local candidates = security.sources_by_id[identity]
            or security.sources_by_id[tostring(identity)]
        if candidates then
            for _, candidate in ipairs(candidates) do
                if not entity then entity = candidate
                elseif entity ~= candidate then return nil, nil, "source_ambiguous" end
            end
        end
    end
    local owner = entity and security.owner_by_entity[entity] or nil
    if not owner then return nil, nil, "source_entity_unknown" end
    if request.source_owner ~= nil and request.source_owner ~= owner.id then
        return nil, nil, "source_owner_mismatch"
    end
    if not entity_identity_valid(security, entity) then
        return nil, nil, "source_rule_set_changed"
    end
    return entity, owner
end

local function authorization_valid(battle, request, owner, brick, amount)
    if request[AUTHORITY_KEY] ~= COST_AUTHORITY then return false end
    local security = PRIVATE[battle]
    local authorization = request.authorization_id
        and security and security.authorizations[request.authorization_id] or nil
    if not authorization or authorization.used then return false end
    return authorization.root_event_id == request.root_event_id
        and authorization.activation_id == request.activation_id
        and authorization.ability_id == request.ability_id
        and authorization.source_uid == request.source_uid
        and authorization.source_rule_set_id == request.source_rule_set_id
        and authorization.cost_rule_id == request.rule_id
        and authorization.target_uid == brick.uid
        and authorization.target_owner == owner.id
        and authorization.amount == amount
        and request.cause == "ability_cost"
        and request.operation == "deal"
        and request.target_selector == "setup_linked_allied_brick"
end

local function guard_valid(battle, brick)
    return brick.guard
        and brick.guard.amount > 0
        and brick.guard.expires_tick > battle.tick
end

apply_brick_harm = function(battle, owner, brick, amount, request)
    request = request or {}
    amount = floor(tonumber(amount) or 0)
    if not brick or not brick.alive or amount <= 0 then return false, 0 end
    local security = PRIVATE[battle]
    local actual_owner = security and security.owner_by_brick[brick] or nil
    local source_entity, source_owner, source_error = resolve_source(battle, request)
    local relation = source_owner and actual_owner
        and source_owner.id == actual_owner.id and "allied"
        or source_owner and actual_owner and "enemy"
        or "unknown"
    local boundary_error
    if not actual_owner then
        boundary_error = "target_entity_unknown"
    elseif owner ~= actual_owner then
        boundary_error = "target_owner_mismatch"
    elseif not entity_identity_valid(security, brick) then
        boundary_error = "target_rule_set_changed"
    elseif source_error then
        boundary_error = source_error
    elseif request[AUTHORITY_KEY] == HOSTILE_AUTHORITY and relation ~= "enemy" then
        boundary_error = "hostile_authority_relation_mismatch"
    end
    owner = actual_owner or owner
    request.source_owner = source_owner and source_owner.id or nil
    request.source_entity_id = source_entity
        and (source_entity.uid or source_entity.body_id) or request.source_entity_id
    request.root_event_id = request.root_event_id or string.format(
        "root:%d:%s:%s:%s",
        battle.tick,
        tostring(request.source_entity_id or request.source_uid or "unknown"),
        tostring(brick.uid or brick.body_id),
        tostring(request.cause or "unknown")
    )
    local generation = request.generation or 0
    if generation > M.MAX_CASCADE_GENERATION then
        cascade_refused(battle, owner.id, request.root_event_id, "generation", {
            source_owner = request.source_owner,
            source_entity_id = request.source_entity_id or request.source_uid,
            source_rule_set_id = request.source_rule_set_id,
            rule_id = request.rule_id,
            ability_id = request.ability_id,
            target_owner = owner.id,
            target_entity_id = brick.uid or brick.body_id,
            generation = generation,
        })
        return false, 0
    end
    if not reserve_cascade(
        battle,
        owner.id,
        request.root_event_id,
        "brick_harm_attempts",
        M.MAX_BRICK_HARM_ATTEMPTS,
        {
            source_owner = request.source_owner,
            source_entity_id = request.source_entity_id or request.source_uid,
            source_rule_set_id = request.source_rule_set_id,
            rule_id = request.rule_id,
            ability_id = request.ability_id,
            target_owner = owner.id,
            target_entity_id = brick.uid or brick.body_id,
            generation = generation,
        }
    ) then
        return false, 0
    end
    local authorized = relation == "allied"
        and authorization_valid(battle, request, owner, brick, amount)
    if boundary_error or relation == "unknown"
        or (relation == "allied" and not authorized) then
        append_event(battle, owner.id, "brick_harm_denied", {
            brick = brick.id,
            target_entity_id = brick.uid or brick.body_id,
            target_owner = owner.id,
            target_relation = relation,
            requested_damage = amount,
            amount = amount,
            unit = request.unit or "damage",
            source_owner = request.source_owner,
            source_entity_id = request.source_entity_id or request.source_uid,
            source_rule_set_id = request.source_rule_set_id,
            rule_id = request.rule_id,
            ability_id = request.ability_id,
            operation = request.operation or "deal",
            target_selector = request.target_selector,
            cause = request.cause or "unknown",
            root_event_id = request.root_event_id,
            parent_event_id = request.parent_event_id,
            generation = request.generation or 0,
            reason = boundary_error
                or (relation == "unknown" and "source_entity_unknown")
                or "allied_harm_not_authorized",
        })
        return false, 0
    end
    if authorized then
        local authorization = security.authorizations[request.authorization_id]
        if brick.hp < amount or (not authorization.lethal and brick.hp - amount <= 0) then
            append_event(battle, owner.id, "ability_blocked", {
                activation_id = request.activation_id,
                ability_id = request.ability_id,
                source_owner = request.source_owner,
                source_entity_id = request.source_uid,
                target_owner = owner.id,
                target_entity_id = brick.uid,
                target_relation = "allied",
                root_event_id = request.root_event_id,
                parent_event_id = request.parent_event_id,
                generation = request.generation or 0,
                reason = "target_cannot_pay_exactly",
            })
            return false, 0
        end
        authorization.used = true
    elseif guard_valid(battle, brick) then
        local prevented = min(amount, brick.guard.amount)
        amount = amount - prevented
        brick.guard.amount = brick.guard.amount - prevented
        local guard_source = brick_by_uid(owner, brick.guard.source_uid)
        local guard_profile = guard_source
            and effects.brick_profile(guard_source.behaviour, guard_source.rule_set)
            or nil
        append_rule_event(battle, owner.id, "guard_prevented", {
            brick = brick.id,
            prevented = prevented,
            source_owner = brick.guard.source_owner,
            source_entity_id = brick.guard.source_uid,
            source_rule_set_id = brick.guard.source_rule_set_id,
            rule_id = brick.guard.rule_id,
            ability_id = brick.guard.ability_id,
            operation = brick.guard.operation,
            target_selector = brick.guard.target_selector,
            target_owner = owner.id,
            target_entity_id = brick.uid or brick.body_id,
            target_relation = "allied",
            root_event_id = request.root_event_id,
            parent_event_id = request.parent_event_id,
            generation = request.generation or 0,
        }, guard_profile, "guard", guard_source and guard_source.name or "Splice")
        if brick.guard.amount <= 0 then brick.guard = nil end
        if amount <= 0 then return false, 0 end
    end
    local before = brick.hp
    local applied = min(amount, before)
    brick.hp = before - applied
    local box = battle.world:get_box(brick.body_id)
    if box then box.data.hp = max(0, brick.hp) end
    append_event(battle, owner.id, "brick_damaged", {
        brick = brick.id, row = brick.row, col = brick.col,
        damage = applied,
        requested_damage = amount,
        applied_damage = applied,
        hp_before = before,
        hp_left = max(0, brick.hp),
        integrity_before = before,
        integrity_after = max(0, brick.hp),
        source = request.cause,
        cause = request.cause,
        source_owner = request.source_owner,
        source_entity_id = request.source_entity_id or request.source_uid,
        source_rule_set_id = request.source_rule_set_id,
        rule_id = request.rule_id,
        ability_id = request.ability_id,
        operation = request.operation or "deal",
        target_selector = request.target_selector,
        target_owner = owner.id,
        target_entity_id = brick.uid or brick.body_id,
        target_relation = relation,
        root_event_id = request.root_event_id,
        parent_event_id = request.parent_event_id,
        generation = request.generation or 0,
        activation_id = request.activation_id,
        authorization_id = request.authorization_id,
        amount = applied,
        unit = request.unit or "damage",
        x = brick.x, y = brick.y,
    })
    -- Linked ability costs are atomic. A lethal payment records its exact
    -- integrity mutation here, but destruction (and any descendant trigger)
    -- waits until every promised payoff has completed.
    request.applied_damage = applied
    if brick.hp <= 0 and request.defer_destruction then return false, applied end
    if brick.hp <= 0 then
        local destroyed = destroy_brick(battle, owner, brick, request)
        if not request.defer_cascade_drain then drain_cascade(battle) end
        return destroyed, applied
    end
    return false, applied
end

-- Public/direct callers cross the same engine-owned identity boundary. They
-- can damage an actual enemy using an actual registered source, but can never
-- obtain the private capability needed to spend allied HP.
M.apply_brick_harm = apply_brick_harm

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

wear_shell = function(battle, owner, marble, amount, cause, x, y, depth, context)
    if marble.state == "destroyed" or amount <= 0 then return false end
    context = context or {}
    local shell = marble.shells[1]
    if not shell then return false end
    shell.durability = shell.durability - amount
    local damaged_event = append_event(battle, owner.id, "shell_damaged", {
        marble = marble.uid, mineral = shell.mineral, damage = amount,
        durability_left = max(0, shell.durability), cause = cause,
        source_owner = context.source_owner,
        source_entity_id = context.source_entity_id,
        source_rule_set_id = context.source_rule_set_id,
        rule_id = context.rule_id,
        ability_id = context.ability_id,
        operation = context.operation or "wear",
        target_selector = context.target_selector or "current_shell",
        target_owner = owner.id,
        target_entity_id = marble.uid,
        target_relation = context.target_relation,
        amount = amount,
        unit = "durability",
        root_event_id = context.root_event_id,
        parent_event_id = context.parent_event_id,
        generation = context.generation or depth or 0,
        x = quantize(x or 0), y = quantize(y or 0),
    })
    if shell.durability > 0 then return false end
    table.remove(marble.shells, 1)
    local body = battle.world:get_body(marble.body_id)
    if body then body.data.shells = #marble.shells end
    local break_event = append_event(battle, owner.id, "shell_break", {
        marble = marble.uid, mineral = shell.mineral,
        shells_left = #marble.shells, cause = cause,
        source_owner = context.source_owner,
        source_entity_id = context.source_entity_id,
        source_rule_set_id = context.source_rule_set_id,
        rule_id = context.rule_id,
        ability_id = context.ability_id,
        operation = context.operation or "wear",
        target_selector = context.target_selector or "current_shell",
        target_owner = owner.id,
        target_entity_id = marble.uid,
        target_relation = context.target_relation,
        amount = amount,
        unit = "durability",
        root_event_id = context.root_event_id or damaged_event.root_event_id,
        parent_event_id = damaged_event.event_id,
        generation = context.generation or depth or 0,
        x = quantize(x or 0), y = quantize(y or 0),
    })
    if #marble.shells == 0 then
        local generation = (depth or 0) + 1
        local release_context = {
            root_event_id = context.root_event_id or damaged_event.root_event_id,
            parent_event_id = break_event.event_id,
            generation = generation,
            source_owner = owner.id,
            source_entity_id = marble.uid,
            source_rule_set_id = marble.core.rule_set.id,
        }
        local release_ability =
            tostring(marble.core.release or "baseline") .. "_release"
        local permitted = generation <= M.MAX_CASCADE_GENERATION
        if not permitted then
            cascade_refused(
                battle,
                owner.id,
                release_context.root_event_id,
                "generation",
                {
                    source_owner = owner.id,
                    source_entity_id = marble.uid,
                    source_rule_set_id = marble.core.rule_set.id,
                    ability_id = release_ability,
                    target_owner = owner.id,
                    target_entity_id = marble.uid,
                    generation = generation,
                }
            )
        elseif not reserve_cascade(
            battle,
            owner.id,
            release_context.root_event_id,
            "ability_activations",
            M.MAX_CASCADE_ACTIVATIONS,
            {
                source_owner = owner.id,
                source_entity_id = marble.uid,
                source_rule_set_id = marble.core.rule_set.id,
                ability_id = release_ability,
                target_owner = owner.id,
                target_entity_id = marble.uid,
                generation = generation,
            }
        ) then
            permitted = false
        end
        if permitted then
            enqueue_cascade(battle, {
                generation = generation,
                source_owner = owner.id,
                source_uid = marble.uid,
                ability_id = release_ability,
                target_uid = marble.uid,
                run = function()
                    release_core(
                        battle,
                        owner,
                        opponent_of(battle, owner),
                        marble,
                        x,
                        y,
                        generation,
                        release_context
                    )
                end,
            })
        else
            destroy_marble(
                battle,
                owner,
                marble,
                "release_cascade_cap",
                x,
                y
            )
        end
        if not context.defer_drain then drain_cascade(battle) end
        return true
    end
    return false
end

release_core = function(battle, owner, other, marble, x, y, depth, context)
    if marble.state == "destroyed" then return end
    context = context or {}
    depth = depth or 1
    if depth > M.MAX_RELEASE_DEPTH then
        cascade_refused(battle, owner.id, context.root_event_id, "generation", {
            marble = marble.uid,
            source_owner = owner.id,
            source_entity_id = marble.uid,
            source_rule_set_id = marble.core.rule_set.id,
            ability_id = tostring(marble.core.release or "baseline") .. "_release",
            target_owner = owner.id,
            target_entity_id = marble.uid,
            generation = depth,
            x = quantize(x),
            y = quantize(y),
        })
        destroy_marble(battle, owner, marble, "release_generation_cap", x, y)
        return
    end
    local base = effects.release_profile(marble.core.release, marble.core.rule_set)
    local amplification = marble.effect_power or 0
    local radius = 7 + (base.radius + amplification) * 5
    local strength = 36 + (base.radius + amplification) * 12
    local release_event = append_rule_event(battle, owner.id, "core_release", {
        marble = marble.uid, core = marble.core.id, release = base.id,
        x = quantize(x), y = quantize(y), radius = radius,
        strength = strength, invert = base.invert, depth = depth,
        amplification = amplification,
        root_event_id = context.root_event_id,
        parent_event_id = context.parent_event_id,
        generation = context.generation or depth,
    }, base, "radius", marble.core.name)
    destroy_marble(battle, owner, marble, "core_released", x, y)

    local affected = battle.world:apply_radial_impulse(x, y, radius, strength, {
        source = "core:" .. marble.uid,
        invert = base.invert,
        wake_static = true,
        falloff = true,
    })
    local blowback_event = append_rule_event(battle, owner.id, "blowback", {
        marble = marble.uid, x = quantize(x), y = quantize(y),
        radius = radius, affected = copy(affected), ally = true, enemy = true,
        invert = base.invert, release = base.id,
        root_event_id = release_event.root_event_id,
        parent_event_id = release_event.event_id,
        generation = depth,
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
                source_owner = owner.id,
                source_entity_id = marble.uid,
                source_rule_set_id = marble.core.rule_set.id,
                rule_id = "release.baseline.radius",
                ability_id = tostring(marble.core.release or "baseline") .. "_release",
                operation = "push",
                target_selector = "nearby_marbles",
                target_owner = entry.owner.id,
                target_entity_id = affected_marble.uid,
                target_relation = entry.owner.id == owner.id and "allied" or "enemy",
                amount = strength,
                unit = "strength",
                root_event_id = release_event.root_event_id,
                parent_event_id = blowback_event.event_id,
                generation = depth,
                cause = "core_release",
            })
            if base.scorch > 0 then
                wear_shell(battle, entry.owner, affected_marble, base.scorch, "scorch",
                    battle.world:get_body(affected_id).x,
                    battle.world:get_body(affected_id).y,
                    depth + 1,
                    {
                        source_owner = owner.id,
                        source_entity_id = marble.uid,
                        source_rule_set_id = marble.core.rule_set.id,
                        rule_id = "release.scorch.wear",
                        ability_id = "scorch",
                        operation = "scorch",
                        target_selector = "nearby_marbles",
                        target_relation = entry.owner.id == owner.id and "allied" or "enemy",
                        root_event_id = release_event.root_event_id,
                        parent_event_id = release_event.event_id,
                        generation = depth + 1,
                    })
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
        for row = 1, other.formation.rows do
            for col = 1, other.formation.cols do
                local brick = formation_mod.brick_at(other.formation, row, col)
                if brick then
                    local dx, dy = brick.x - x, brick.y - y
                    local distance = dx * dx + dy * dy
                    if not closest_distance or distance < closest_distance
                        or (distance == closest_distance
                            and (row < closest.brick.row
                                or (row == closest.brick.row
                                    and (col < closest.brick.col
                                        or (col == closest.brick.col
                                            and tostring(brick.uid or brick.body_id)
                                                < tostring(closest.brick.uid
                                                    or closest.brick.body_id)))))) then
                        closest, closest_distance = { owner = other, brick = brick }, distance
                    end
                end
            end
        end
        if closest and closest_distance <= 180 then
            local request = {
                source_owner = owner.id,
                source_entity_id = marble.uid,
                source_rule_set_id = marble.core.rule_set.id,
                rule_id = "release.shrapnel.damage",
                operation = "splash",
                target_selector = "nearest_enemy_brick_cluster",
                cause = "shrapnel",
                root_event_id = release_event.root_event_id,
                parent_event_id = release_event.event_id,
                generation = depth,
                source_marble = marble,
            }
            request[AUTHORITY_KEY] = HOSTILE_AUTHORITY
            request[SOURCE_KEY] = marble
            apply_brick_harm(battle, closest.owner, closest.brick,
                base.shrapnel + amplification, request)
            for _, neighbour in ipairs(formation_mod.neighbours(
                closest.owner.formation, closest.brick.row, closest.brick.col)) do
                apply_brick_harm(battle, closest.owner, neighbour,
                    base.shrapnel + amplification, request)
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
            source_owner = field.owner,
            source_entity_id = field.data.brick,
            source_rule_set_id = source_rule_set.id,
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

brick_by_uid = function(owner, uid)
    for row = 1, owner.formation.rows do
        for col = 1, owner.formation.cols do
            local brick = formation_mod.brick_at(owner.formation, row, col)
            if brick and brick.uid == uid then return brick end
        end
    end
    return nil
end

local function ability_group(rule_set, ability_id)
    for _, ability in ipairs(rule_set.abilities or {}) do
        if ability.id == ability_id then return ability end
    end
    return nil
end

local function accepts_cause(ability, cause)
    for _, accepted in ipairs((ability.recursion and ability.recursion.accepts_causes) or {}) do
        if accepted == cause then return true end
    end
    return false
end

function M.activate_linked_cost(battle, owner_id, source_uid, ability_id, cause, striking_marble,
    event_context)
    local owner = type(owner_id) == "table" and owner_id or battle.sides[owner_id]
    local source = owner and brick_by_uid(owner, source_uid) or nil
    local ability = source and ability_group(source.rule_set, ability_id) or nil
    local link = owner and battle.ability_links[
        owner.id .. "|" .. tostring(source_uid) .. "|" .. tostring(ability_id)
    ] or nil
    event_context = event_context or {}
    local function blocked(reason)
        append_event(battle, owner and owner.id or "-", "ability_blocked", {
            activation_id = nil,
            ability_id = ability_id,
            source_owner = owner and owner.id or nil,
            source_entity_id = source_uid,
            target_owner = owner and owner.id or nil,
            target_entity_id = link and link.target_uid or nil,
            target_relation = "allied",
            root_event_id = event_context.root_event_id,
            parent_event_id = event_context.parent_event_id,
            generation = event_context.generation or 1,
            reason = reason,
        })
        return false, reason
    end
    if not owner or not source or not source.alive then return blocked("source_dead") end
    if not ability or ability.kind ~= "allied_brick_cost" then return blocked("ability_missing") end
    if not link then return blocked("link_missing") end
    if not entity_identity_valid(PRIVATE[battle], source) then
        return blocked("rule_set_identity_changed")
    end
    local valid_cost, cost_rule = pcall(rule_ast.rule, source.rule_set, ability.cost_rule_id)
    if not valid_cost or not cost_rule then return blocked("cost_rule_invalid") end
    if link.source_uid ~= source_uid
        or link.source_rule_set_id ~= source.rule_set.id
        or link.cost_rule_id ~= ability.cost_rule_id
        or not equal_values(link.payoff_rule_ids, ability.payoff_rule_ids)
        or link.cost_amount ~= cost_rule.magnitude.value
        or link.lethal ~= cost_rule.lethal
        or not equal_values(link.cadence, cost_rule.cadence)
        or not equal_values(link.source_cell, { row = source.row, col = source.col }) then
        return blocked("link_authority_changed")
    end
    if not accepts_cause(ability, cause) then return blocked("cause_denied") end
    local target = brick_by_uid(owner, link.target_uid)
    if not target or not target.alive then return blocked("linked_target_dead") end
    if not equal_values(link.target_cell, { row = target.row, col = target.col })
        or math.abs(source.row - target.row) + math.abs(source.col - target.col) ~= 1 then
        return blocked("link_target_changed")
    end
    local amount = cost_rule and cost_rule.magnitude.value or nil
    if amount ~= link.cost_amount or target.hp < amount
        or (not cost_rule.lethal and target.hp - amount <= 0) then
        return blocked("target_cannot_pay_exactly")
    end
    source.ability_state = source.ability_state or {}
    local state = source.ability_state[ability_id] or {
        spent = 0,
        last_exchange = nil,
        last_tick = nil,
        trigger_count = 0,
    }
    source.ability_state[ability_id] = state
    local charges = cost_rule.cadence.charges
    if state.spent >= charges then return blocked("charges_spent") end
    local cadence = cost_rule.cadence
    if cadence.unit == "exchange" then
        if state.last_exchange ~= nil
            and battle.exchange - state.last_exchange < cadence.interval then
            return blocked("cadence")
        end
    elseif cadence.unit == "ticks" then
        if state.last_tick ~= nil
            and battle.tick - state.last_tick < cadence.interval then
            return blocked("cadence")
        end
    else
        state.trigger_count = (state.trigger_count or 0) + 1
        if (state.trigger_count - 1) % cadence.interval ~= 0 then
            return blocked("cadence")
        end
    end
    local generation = event_context.generation or 1
    local root_event_id = event_context.root_event_id
        or ("root:" .. tostring(battle.tick) .. ":" .. tostring(battle.next_activation_id + 1))
    event_context.root_event_id = root_event_id
    if generation > M.MAX_CASCADE_GENERATION
        or generation > ability.recursion.max_generation then
        cascade_refused(battle, owner.id, root_event_id, "generation", {
            ability_id = ability_id,
            source_owner = owner.id,
            source_entity_id = source_uid,
            source_rule_set_id = source.rule_set.id,
            target_owner = owner.id,
            target_entity_id = target.uid,
            generation = generation,
        })
        return blocked("generation_capped")
    end
    local enemy = opponent_of(battle, owner)
    for _, payoff_id in ipairs(ability.payoff_rule_ids) do
        local payoff = rule_ast.rule(source.rule_set, payoff_id)
        if payoff.target.selector == "current_shell"
            and (not striking_marble
                or striking_marble.state == "destroyed"
                or not striking_marble.shells[1]
                or not contains(enemy.all_marbles, striking_marble)
                or not battle.world:get_body(striking_marble.body_id)) then
            return blocked("payoff_target_invalid")
        end
    end
    if not cascade_has_room(
        battle,
        root_event_id,
        "brick_harm_attempts",
        M.MAX_BRICK_HARM_ATTEMPTS
    ) then
        cascade_refused(battle, owner.id, root_event_id, "brick_harm_attempts", {
            ability_id = ability_id,
            source_owner = owner.id,
            source_entity_id = source_uid,
            source_rule_set_id = source.rule_set.id,
            target_owner = owner.id,
            target_entity_id = target.uid,
            generation = generation,
        })
        return blocked("harm_cap")
    end
    if not reserve_cascade(
        battle,
        owner.id,
        root_event_id,
        "ability_activations",
        M.MAX_CASCADE_ACTIVATIONS,
        {
            ability_id = ability_id,
            source_owner = owner.id,
            source_entity_id = source_uid,
            source_rule_set_id = source.rule_set.id,
            target_owner = owner.id,
            target_entity_id = target.uid,
            generation = generation,
        }
    ) then
        return blocked("activation_cap")
    end
    battle.next_activation_id = battle.next_activation_id + 1
    local activation_id = string.format(
        "activation:%s:%s:%06d",
        owner.id,
        tostring(source_uid),
        battle.next_activation_id
    )
    local authorization_id = activation_id .. ":cost"
    local authorization = {
        root_event_id = root_event_id,
        activation_id = activation_id,
        ability_id = ability_id,
        source_uid = source_uid,
        source_rule_set_id = source.rule_set.id,
        cost_rule_id = ability.cost_rule_id,
        target_uid = target.uid,
        target_owner = owner.id,
        amount = amount,
        lethal = cost_rule.lethal,
        used = false,
    }
    PRIVATE[battle].authorizations[authorization_id] = authorization
    -- This public projection is audit-only. Runtime never reads it as
    -- authority, so mutation, replay, or deserialisation cannot grant access.
    battle.authorizations[authorization_id] = copy(authorization)
    local before = target.hp
    local charges_before = charges - state.spent
    append_event(battle, owner.id, "ability_triggered", {
        activation_id = activation_id,
        ability_id = ability_id,
        source_owner = owner.id,
        source_entity_id = source_uid,
        source_rule_set_id = source.rule_set.id,
        rule_id = ability.cost_rule_id,
        operation = "deal",
        target_selector = "setup_linked_allied_brick",
        target_owner = owner.id,
        target_entity_id = target.uid,
        target_relation = "allied",
        amount = amount,
        unit = cost_rule.magnitude.unit,
        linked_source_uid = source_uid,
        linked_target_uid = target.uid,
        cadence_index = state.spent + 1,
        charges_before = charges_before,
        charges_after = charges_before - 1,
        root_event_id = root_event_id,
        parent_event_id = event_context.parent_event_id or root_event_id,
        generation = event_context.generation or 1,
        cause = cause,
    })
    local cost_request = {
        source_owner = owner.id,
        source_entity_id = source_uid,
        source_uid = source_uid,
        source_rule_set_id = source.rule_set.id,
        rule_id = ability.cost_rule_id,
        ability_id = ability_id,
        operation = "deal",
        target_selector = "setup_linked_allied_brick",
        cause = "ability_cost",
        root_event_id = root_event_id,
        parent_event_id = event_context.parent_event_id or root_event_id,
        generation = event_context.generation or 1,
        activation_id = activation_id,
        authorization_id = authorization_id,
        defer_destruction = true,
    }
    cost_request[AUTHORITY_KEY] = COST_AUTHORITY
    cost_request[SOURCE_KEY] = source
    local _, applied = apply_brick_harm(battle, owner, target, amount, cost_request)
    if applied ~= amount then
        PRIVATE[battle].authorizations[authorization_id] = nil
        battle.authorizations[authorization_id] = nil
        return blocked("atomic_cost_failed")
    end
    battle.authorizations[authorization_id].used = true
    state.spent = state.spent + 1
    state.last_exchange = battle.exchange
    state.last_tick = battle.tick
    local cost_event = append_event(battle, owner.id, "ability_cost_paid", {
        activation_id = activation_id,
        authorization_id = authorization_id,
        ability_id = ability_id,
        source_owner = owner.id,
        source_entity_id = source_uid,
        source_rule_set_id = source.rule_set.id,
        rule_id = ability.cost_rule_id,
        operation = "deal",
        target_selector = "setup_linked_allied_brick",
        target_owner = owner.id,
        target_entity_id = target.uid,
        target_relation = "allied",
        linked_source_uid = source_uid,
        linked_target_uid = target.uid,
        requested_damage = amount,
        applied_damage = applied,
        amount = applied,
        unit = cost_rule.magnitude.unit,
        lethal = cost_rule.lethal,
        integrity_before = before,
        integrity_after = target.hp,
        cadence_index = state.spent,
        charges_before = charges_before,
        charges_after = charges_before - 1,
        root_event_id = root_event_id,
        parent_event_id = event_context.parent_event_id or root_event_id,
        generation = event_context.generation or 1,
        cause = "ability_cost",
    })
    for payoff_index, payoff_id in ipairs(ability.payoff_rule_ids) do
        local payoff = rule_ast.rule(source.rule_set, payoff_id)
        local scaling = payoff.scaling
        local magnitude = min(
            scaling.cap,
            floor(applied * scaling.numerator / scaling.denominator)
        )
        local applied_payoff = 0
        if payoff.target.selector == "current_shell" and striking_marble
            and striking_marble.state ~= "destroyed" then
            local enemy = opponent_of(battle, owner)
            local shell = striking_marble.shells[1]
            local before_shell = shell and shell.durability or 0
            wear_shell(
                battle,
                enemy,
                striking_marble,
                magnitude,
                "ability_payoff",
                source.x,
                source.y,
                (event_context.generation or 1) + 1,
                {
                    source_owner = owner.id,
                    source_entity_id = source_uid,
                    source_rule_set_id = source.rule_set.id,
                    rule_id = payoff_id,
                    ability_id = ability_id,
                    operation = payoff.operation.verb,
                    target_selector = payoff.target.selector,
                    target_relation = "enemy",
                    root_event_id = root_event_id,
                    parent_event_id = cost_event.event_id,
                    generation = (event_context.generation or 1) + 1,
                    defer_drain = true,
                }
            )
            applied_payoff = min(magnitude, before_shell)
        end
        append_event(battle, owner.id, "ability_payoff_applied", {
            activation_id = activation_id,
            ability_id = ability_id,
            source_owner = owner.id,
            source_entity_id = source_uid,
            source_rule_set_id = source.rule_set.id,
            rule_id = payoff_id,
            operation = payoff.operation.verb,
            target_selector = payoff.target.selector,
            target_owner = opponent_of(battle, owner).id,
            target_entity_id = striking_marble and striking_marble.uid or nil,
            target_relation = "enemy",
            linked_source_uid = source_uid,
            linked_target_uid = target.uid,
            amount = applied_payoff,
            unit = payoff.magnitude and payoff.magnitude.unit or nil,
            payoff_index = payoff_index,
            cadence_index = state.spent,
            charges_before = charges_before,
            charges_after = charges_before - 1,
            root_event_id = root_event_id,
            parent_event_id = cost_event.event_id,
            generation = (event_context.generation or 1) + 1,
            cause = "ability_cost_paid",
        })
    end
    if target.hp <= 0 and target.alive then
        destroy_brick(battle, owner, target, {
            source_owner = owner.id,
            source_entity_id = source_uid,
            source_uid = source_uid,
            source_rule_set_id = source.rule_set.id,
            rule_id = ability.cost_rule_id,
            ability_id = ability_id,
            operation = "deal",
            target_selector = "setup_linked_allied_brick",
            cause = "ability_cost",
            root_event_id = root_event_id,
            parent_event_id = cost_event.event_id,
            generation = event_context.generation or 1,
            activation_id = activation_id,
            authorization_id = authorization_id,
            linked_source_uid = source_uid,
            linked_target_uid = target.uid,
            applied_damage = amount,
            unit = cost_rule.magnitude.unit,
        })
    end
    if not event_context.defer_cascade_drain then drain_cascade(battle) end
    return true, activation_id
end

local function splice_contract(source)
    for _, ability in ipairs(source.rule_set.abilities or {}) do
        if ability.kind == "passive" then
            for _, rule_id in ipairs(ability.rule_ids or {}) do
                local rule = rule_ast.rule(source.rule_set, rule_id)
                if rule.operation.stat == "guard" then return ability, rule end
            end
        end
    end
    return nil, nil
end

local function cadence_ready(battle, source, ability, rule)
    source.ability_state = source.ability_state or {}
    local state = source.ability_state[ability.id] or { trigger_count = 0 }
    source.ability_state[ability.id] = state
    local cadence = rule.cadence
    if cadence.unit == "exchange" then
        if state.last_exchange ~= nil
            and battle.exchange - state.last_exchange < cadence.interval then
            return false
        end
    elseif cadence.unit == "ticks" then
        if state.last_tick ~= nil
            and battle.tick - state.last_tick < cadence.interval then
            return false
        end
    else
        state.trigger_count = state.trigger_count + 1
        if (state.trigger_count - 1) % cadence.interval ~= 0 then return false end
    end
    return true, state
end

local function apply_splice_guard(battle, owner, source, profile, root_event)
    if not entity_identity_valid(PRIVATE[battle], source) then
        return false, "rule_set_identity_changed"
    end
    local ability, rule = splice_contract(source)
    if not ability or not rule then return false, "guard_ability_missing" end
    local ready, state = cadence_ready(battle, source, ability, rule)
    if not ready then return false, "cadence" end
    local duration = rule.duration.value
    local amount = rule.magnitude.value
    local neighbours = formation_mod.neighbours(
        owner.formation,
        source.row,
        source.col
    )
    local limit = rule.target.count or #neighbours
    for index, neighbour in ipairs(neighbours) do
        if index > limit then break end
        neighbour.guard = {
            amount = amount,
            expires_tick = battle.tick + duration,
            exchange = battle.exchange,
            source_owner = owner.id,
            source_uid = source.uid or source.body_id,
            source_rule_set_id = source.rule_set.id,
            rule_id = rule.id,
            ability_id = ability.id,
            operation = rule.operation.verb,
            target_selector = rule.target.selector,
        }
        append_rule_event(battle, owner.id, "guard_applied", {
            brick = neighbour.id,
            source_owner = owner.id,
            source_entity_id = source.uid or source.body_id,
            source_rule_set_id = source.rule_set.id,
            rule_id = rule.id,
            ability_id = ability.id,
            operation = rule.operation.verb,
            target_selector = rule.target.selector,
            target_owner = owner.id,
            target_entity_id = neighbour.uid or neighbour.body_id,
            target_relation = "allied",
            amount = amount,
            unit = rule.magnitude.unit,
            expires_tick = battle.tick + duration,
            x = neighbour.x,
            y = neighbour.y,
            root_event_id = root_event.root_event_id,
            parent_event_id = root_event.event_id,
            generation = 1,
        }, profile, "guard", source.name)
    end
    state.last_exchange = battle.exchange
    state.last_tick = battle.tick
    return true
end

function M.trigger_splice_guard(battle, owner_id, source_uid)
    local owner = type(owner_id) == "table" and owner_id or battle.sides[owner_id]
    local source = owner and brick_by_uid(owner, source_uid) or nil
    if not source or not source.alive then return false, "source_dead" end
    local profile = effects.brick_profile(source.behaviour, source.rule_set)
    local ability, rule = splice_contract(source)
    if not ability or not rule then return false, "guard_ability_missing" end
    local root = append_event(battle, owner.id, "splice_triggered", {
        source_owner = owner.id,
        source_entity_id = source.uid or source.body_id,
        source_rule_set_id = source.rule_set.id,
        rule_id = rule.id,
        ability_id = ability.id,
        operation = rule.operation.verb,
        target_selector = rule.target.selector,
        amount = rule.magnitude.value,
        unit = rule.magnitude.unit,
    })
    return apply_splice_guard(battle, owner, source, profile, root)
end

local function collision_damage(battle, attacker, defender, marble, brick, event)
    if marble.state == "destroyed" or not brick.alive then return end
    local security = PRIVATE[battle]
    if not entity_identity_valid(security, marble)
        or not entity_identity_valid(security, brick) then
        append_event(battle, defender.id, "collision_denied", {
            source_owner = attacker.id,
            source_entity_id = marble.uid,
            target_owner = defender.id,
            target_entity_id = brick.uid or brick.body_id,
            reason = "rule_set_identity_changed",
        })
        return
    end
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
    local collision_event = append_rule_event(battle, attacker.id, "collision", {
        marble = marble.uid, effect = collision.id, brick = brick.id,
        row = brick.row, col = brick.col, damage = damage,
        mineral = shell.mineral, pattern = shell.pattern,
        x = quantize(brick.x), y = quantize(brick.y),
        nx = event.nx, ny = event.ny, impulse = event.impulse,
    }, collision, "damage", shell.mineral)
    local hp_before = brick.hp
    local guard_before = copy(brick.guard)
    local collision_request = {
        source_owner = attacker.id,
        source_entity_id = marble.uid,
        source_rule_set_id = shell.rule_set.id,
        rule_id = collision._rule_ids.damage and collision._rule_ids.damage[1] or nil,
        operation = "deal",
        target_selector = "struck_brick",
        cause = "hostile_collision",
        root_event_id = collision_event.event_id,
        parent_event_id = collision_event.event_id,
        generation = 0,
        source_marble = marble,
        defer_cascade_drain = true,
    }
    collision_request[AUTHORITY_KEY] = HOSTILE_AUTHORITY
    collision_request[SOURCE_KEY] = marble
    local _, applied_damage = apply_brick_harm(
        battle, defender, brick, damage, collision_request
    )

    if collision.splash_behind > 0 then
        local direction = attacker.id == "A" and -1 or 1
        local behind = formation_mod.brick_at(defender.formation, brick.row + direction, brick.col)
        if behind then
            local splash_request = {
                source_owner = attacker.id,
                source_entity_id = marble.uid,
                source_rule_set_id = shell.rule_set.id,
                rule_id = collision._rule_ids.splash_behind
                    and collision._rule_ids.splash_behind[1] or nil,
                operation = "splash",
                target_selector = "target_column",
                cause = "hostile_collision",
                root_event_id = collision_event.event_id,
                parent_event_id = collision_event.event_id,
                generation = 1,
                source_marble = marble,
                defer_cascade_drain = true,
            }
            splash_request[AUTHORITY_KEY] = HOSTILE_AUTHORITY
            splash_request[SOURCE_KEY] = marble
            apply_brick_harm(
                battle, defender, behind, collision.splash_behind, splash_request
            )
        end
    end
    if brick.alive and applied_damage > 0 and (profile.guard or 0) > 0 then
        apply_splice_guard(battle, defender, brick, profile, collision_event)
    end
    if brick.alive and applied_damage > 0 and (profile.heal_after_hit or 0) > 0
        and brick.regenerate_exchange ~= battle.exchange then
        brick.regenerate_exchange = battle.exchange
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
    if brick.alive and applied_damage > 0 and profile.rewind and brick.hp < hp_before
        and not brick.temporal_spent then
        brick.temporal_spent = true
        brick.hp = hp_before
        brick.guard = guard_before
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
    if brick.alive and applied_damage > 0 then
        for _, linked in ipairs(rule_ast.linked_cost_groups(brick.rule_set)) do
            M.activate_linked_cost(
                battle,
                defender,
                brick.uid,
                linked.id,
                "hostile_collision",
                marble,
                {
                    root_event_id = collision_event.event_id,
                    parent_event_id = collision_event.event_id,
                    generation = 1,
                    defer_cascade_drain = true,
                }
            )
        end
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

    local passive_wear = profile.shell_wear or 0
    if brick.behaviour == "mirror" and not brick.alive then passive_wear = 0 end
    local wear = collision.durability_cost + passive_wear
    if profile.harmless then wear = 0 end
    if profile.break_shell then wear = max(wear, shell.durability) end
    local passive_source = passive_wear > 0 or profile.break_shell
    wear_shell(
        battle,
        attacker,
        marble,
        wear,
        "collision",
        brick.x,
        brick.y,
        0,
        {
            source_owner = passive_source and defender.id or attacker.id,
            source_entity_id = passive_source
                and (brick.uid or brick.body_id)
                or marble.uid,
            source_rule_set_id = passive_source
                and brick.rule_set.id
                or shell.rule_set.id,
            rule_id = passive_source
                and ((profile._rule_ids.shell_wear
                        and profile._rule_ids.shell_wear[1])
                    or (profile._rule_ids.break_shell
                        and profile._rule_ids.break_shell[1]))
                or (collision._rule_ids.durability_cost
                    and collision._rule_ids.durability_cost[1]),
            ability_id = passive_source and brick.behaviour or shell.collision,
            operation = passive_source and (profile.break_shell and "break" or "wear")
                or "wear",
            target_selector = "current_shell",
            target_relation = passive_source and "enemy" or "self",
            root_event_id = collision_event.event_id,
            parent_event_id = collision_event.event_id,
            generation = 0,
            defer_drain = true,
        }
    )
    drain_cascade(battle)
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
                local tick_event = append_rule_event(battle, owner.id, "status_tick", {
                    marble = marble.uid,
                    status = "poison",
                    source_owner = poison.source_owner,
                    source_entity_id = poison.source_entity_id,
                    source_rule_set_id = poison.source_rule_set_id,
                    target_owner = owner.id,
                    target_entity_id = marble.uid,
                    target_relation = "enemy",
                    generation = 0,
                }, profile, "shell_wear", "Poison")
                poison.next_tick = poison.next_tick + profile._cadence.shell_wear.interval
                wear_shell(battle, owner, marble, profile.shell_wear, "poison",
                    body and body.x or 0, body and body.y or 0, 0, {
                        source_owner = poison.source_owner,
                        source_entity_id = poison.source_entity_id,
                        source_rule_set_id = poison.source_rule_set_id,
                        rule_id = "status.poison.wear",
                        ability_id = "poison_field",
                        operation = "wear",
                        target_selector = "current_shell",
                        target_relation = "enemy",
                        root_event_id = tick_event.event_id,
                        parent_event_id = tick_event.event_id,
                        generation = 0,
                    })
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

local function expire_guards(battle)
    for _, side_id in ipairs(battle.order) do
        local owner = battle.sides[side_id]
        for row = 1, owner.formation.rows do
            for col = 1, owner.formation.cols do
                local brick = formation_mod.brick_at(owner.formation, row, col)
                if brick and brick.guard
                    and brick.guard.expires_tick <= battle.tick then
                    append_event(battle, owner.id, "guard_expired", {
                        brick = brick.id,
                        source_owner = brick.guard.source_owner,
                        source_entity_id = brick.guard.source_uid,
                        source_rule_set_id = brick.guard.source_rule_set_id,
                        rule_id = brick.guard.rule_id,
                        ability_id = brick.guard.ability_id,
                        operation = brick.guard.operation,
                        target_selector = brick.guard.target_selector,
                        target_owner = owner.id,
                        target_entity_id = brick.uid or brick.body_id,
                        target_relation = "allied",
                        reason = "duration",
                    })
                    brick.guard = nil
                end
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
    expire_guards(battle, true)
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
    expire_guards(battle, false)
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
                    rarity = brick.rarity,
                    row = row, col = col, hp = brick.hp, max_hp = brick.max_hp,
                    alive = brick.alive, x = brick.x, y = brick.y,
                    guard = brick.guard and {
                        amount = brick.guard.amount,
                        expires_tick = brick.guard.expires_tick,
                        source_uid = brick.guard.source_uid,
                        ability_id = brick.guard.ability_id,
                    } or nil,
                    ability_state = copy(brick.ability_state),
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
