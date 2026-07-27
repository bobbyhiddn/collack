-- battle/physics.lua -- deterministic fixed-timestep continuous 2D circle physics.
--
-- This module deliberately has no LÖVE dependency.  It is the canonical motion
-- implementation for both headless battle tests and the client.  Bodies and
-- colliders are processed in stable id order.  Each fixed tick advances to the
-- earliest swept time of impact, resolves it, and repeats under a hard
-- iteration bound; collision safety never depends on sampled overlap
-- microsteps.  Every public snapshot is a value-only copy.

local M = {}
local World = {}
World.__index = World

M.FIXED_DT = 1 / 120
M.SCHEMA_VERSION = 1

local abs, ceil, floor, max, min, sqrt =
    math.abs, math.ceil, math.floor, math.max, math.min, math.sqrt

local TIME_EPSILON = 1e-12
local GEOMETRY_EPSILON = 1e-12
local VELOCITY_EPSILON = 1e-14
local POSITION_SLOP = 1e-9

local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function copy_table(source)
    local out = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            out[key] = copy_table(value)
        else
            out[key] = value
        end
    end
    return out
end

local function ordered_insert(list, value)
    local at = #list + 1
    for index = 1, #list do
        if tostring(value.id) < tostring(list[index].id) then
            at = index
            break
        end
    end
    table.insert(list, at, value)
end

local function require_number(value, name)
    if type(value) ~= "number" or value ~= value then
        error(name .. " must be a finite number")
    end
    return value
end

local function normalise(x, y, fallback_x, fallback_y)
    local length = sqrt(x * x + y * y)
    if length <= 1e-12 then
        return fallback_x or 1, fallback_y or 0, 0
    end
    return x / length, y / length, length
end

local function quantize(value)
    if abs(value) < 0.0000005 then return 0 end
    if value >= 0 then
        return floor(value * 1000000 + 0.5) / 1000000
    end
    return ceil(value * 1000000 - 0.5) / 1000000
end

local function emit(world, kind, fields)
    world.event_seq = world.event_seq + 1
    local event = {
        seq = world.event_seq,
        tick = world.tick,
        time = quantize(world.time),
        type = kind,
    }
    for key, value in pairs(fields or {}) do event[key] = value end
    world.events[#world.events + 1] = event
    return event
end

function M.new(opts)
    opts = opts or {}
    local width = require_number(opts.width or 70, "width")
    local height = require_number(opts.height or 120, "height")
    if width <= 0 or height <= 0 then error("world bounds must be positive") end

    return setmetatable({
        schema_version = M.SCHEMA_VERSION,
        fixed_dt = opts.fixed_dt or M.FIXED_DT,
        width = width,
        height = height,
        max_speed = opts.max_speed or 240,
        -- Retained as value-compatible legacy configuration/snapshot state.
        -- Continuous collision detection always uses one authoritative tick.
        max_substeps = opts.max_substeps or 64,
        substep_fraction = opts.substep_fraction or 0.35,
        max_collision_iterations = max(1, floor(opts.max_collision_iterations or 128)),
        linear_damping = opts.linear_damping or 0.996,
        sleep_speed = opts.sleep_speed or 1.25,
        sleep_ticks = opts.sleep_ticks or 36,
        restitution = opts.restitution or 0.82,
        tick = 0,
        time = 0,
        bodies = {},
        body_by_id = {},
        boxes = {},
        box_by_id = {},
        fields = {},
        field_by_id = {},
        events = {},
        event_seq = 0,
        last_substeps = 1,
        last_collision_iterations = 0,
        collision_iteration_limit_hit = false,
        can_collide = opts.can_collide,
    }, World)
end

function World:add_body(spec)
    assert(type(spec) == "table", "body spec must be a table")
    local id = assert(spec.id, "body id is required")
    if self.body_by_id[id] then error("duplicate body id: " .. tostring(id)) end
    local radius = require_number(spec.radius or 1, "body radius")
    local mass = require_number(spec.mass or 1, "body mass")
    if radius <= 0 or mass <= 0 then error("body radius and mass must be positive") end

    local body = {
        id = id,
        kind = spec.kind or "circle",
        owner = spec.owner,
        x = require_number(spec.x or 0, "body x"),
        y = require_number(spec.y or 0, "body y"),
        previous_x = spec.x or 0,
        previous_y = spec.y or 0,
        vx = require_number(spec.vx or 0, "body vx"),
        vy = require_number(spec.vy or 0, "body vy"),
        radius = radius,
        mass = mass,
        inv_mass = 1 / mass,
        restitution = spec.restitution or self.restitution,
        dynamic = spec.dynamic ~= false,
        sensor = spec.sensor == true,
        asleep = spec.asleep == true,
        sleep_counter = spec.sleep_counter or 0,
        alive = spec.alive ~= false,
        data = copy_table(spec.data),
    }
    self.body_by_id[id] = body
    ordered_insert(self.bodies, body)
    emit(self, "body_added", { body = id })
    return body
end

function World:add_box(spec)
    assert(type(spec) == "table", "box spec must be a table")
    local id = assert(spec.id, "box id is required")
    if self.box_by_id[id] then error("duplicate box id: " .. tostring(id)) end
    local width = require_number(spec.width, "box width")
    local height = require_number(spec.height, "box height")
    if width <= 0 or height <= 0 then error("box dimensions must be positive") end
    local box = {
        id = id,
        kind = spec.kind or "box",
        owner = spec.owner,
        x = require_number(spec.x, "box x"),
        y = require_number(spec.y, "box y"),
        width = width,
        height = height,
        restitution = spec.restitution or self.restitution,
        sensor = spec.sensor == true,
        alive = spec.alive ~= false,
        data = copy_table(spec.data),
    }
    self.box_by_id[id] = box
    ordered_insert(self.boxes, box)
    emit(self, "box_added", { box = id })
    return box
end

function World:add_field(spec)
    assert(type(spec) == "table", "field spec must be a table")
    local id = assert(spec.id, "field id is required")
    if self.field_by_id[id] then error("duplicate field id: " .. tostring(id)) end
    local field = {
        id = id,
        kind = spec.kind or "radial",
        owner = spec.owner,
        x = require_number(spec.x or 0, "field x"),
        y = require_number(spec.y or 0, "field y"),
        radius = require_number(spec.radius or 1, "field radius"),
        strength = require_number(spec.strength or 0, "field strength"),
        dx = spec.dx or 0,
        dy = spec.dy or 0,
        falloff = spec.falloff ~= false,
        duration = spec.duration,
        age = 0,
        alive = true,
        data = copy_table(spec.data),
    }
    if field.radius <= 0 then error("field radius must be positive") end
    self.field_by_id[id] = field
    ordered_insert(self.fields, field)
    emit(self, "field_added", { field = id, kind = field.kind })
    return field
end

local function remove_ordered(list, value)
    for index = 1, #list do
        if list[index] == value then
            table.remove(list, index)
            return
        end
    end
end

function World:remove_body(id, reason)
    local body = self.body_by_id[id]
    if not body then return false end
    self.body_by_id[id] = nil
    body.alive = false
    remove_ordered(self.bodies, body)
    emit(self, "body_removed", { body = id, reason = reason or "removed" })
    return true
end

function World:remove_box(id, reason)
    local box = self.box_by_id[id]
    if not box then return false end
    self.box_by_id[id] = nil
    box.alive = false
    remove_ordered(self.boxes, box)
    emit(self, "box_removed", { box = id, reason = reason or "removed" })
    return true
end

function World:remove_field(id, reason)
    local field = self.field_by_id[id]
    if not field then return false end
    self.field_by_id[id] = nil
    field.alive = false
    remove_ordered(self.fields, field)
    emit(self, "field_removed", { field = id, reason = reason or "expired" })
    return true
end

function World:get_body(id) return self.body_by_id[id] end
function World:get_box(id) return self.box_by_id[id] end
function World:get_field(id) return self.field_by_id[id] end

function World:set_dynamic(id, dynamic)
    local body = assert(self.body_by_id[id], "unknown body: " .. tostring(id))
    body.dynamic = dynamic == true
    if body.dynamic then
        body.asleep = false
        body.sleep_counter = 0
    else
        body.vx, body.vy = 0, 0
        body.asleep = true
    end
    return body
end

function World:set_position(id, x, y)
    local body = assert(self.body_by_id[id], "unknown body: " .. tostring(id))
    body.x, body.y = require_number(x, "body x"), require_number(y, "body y")
    body.previous_x, body.previous_y = body.x, body.y
    return body
end

function World:set_velocity(id, vx, vy)
    local body = assert(self.body_by_id[id], "unknown body: " .. tostring(id))
    body.vx, body.vy = require_number(vx, "body vx"), require_number(vy, "body vy")
    body.asleep = false
    body.sleep_counter = 0
    return body
end

function World:apply_impulse(id, ix, iy, opts)
    local body = self.body_by_id[id]
    if not body or not body.alive then return false end
    opts = opts or {}
    if not body.dynamic and opts.wake_static then body.dynamic = true end
    if not body.dynamic then return false end
    body.vx = body.vx + require_number(ix, "impulse x") * body.inv_mass
    body.vy = body.vy + require_number(iy, "impulse y") * body.inv_mass
    body.asleep = false
    body.sleep_counter = 0
    emit(self, "impulse", { body = id, ix = quantize(ix), iy = quantize(iy), source = opts.source })
    return true
end

function World:apply_radial_impulse(x, y, radius, strength, opts)
    opts = opts or {}
    local affected = {}
    for _, body in ipairs(self.bodies) do
        if body.alive and (body.dynamic or opts.wake_static) then
            local dx, dy = body.x - x, body.y - y
            local nx, ny, distance = normalise(dx, dy,
                tostring(body.id) < tostring(opts.source or "") and -1 or 1, 0)
            if distance <= radius + body.radius then
                local scale = opts.falloff == false and 1 or max(0, 1 - distance / radius)
                local force = strength * scale
                if opts.invert then force = -force end
                if not body.dynamic and opts.wake_static then body.dynamic = true end
                body.vx = body.vx + nx * force * body.inv_mass
                body.vy = body.vy + ny * force * body.inv_mass
                body.asleep = false
                body.sleep_counter = 0
                affected[#affected + 1] = body.id
                emit(self, "radial_impulse", {
                    body = body.id, source = opts.source, strength = quantize(force),
                    nx = quantize(nx), ny = quantize(ny),
                })
            end
        end
    end
    return affected
end

local function collision_allowed(world, body, collider)
    if world.can_collide and not world.can_collide(body, collider) then return false end
    return true
end

local function contact_key(left, right)
    local a, b = tostring(left), tostring(right)
    if a > b then a, b = b, a end
    return a .. "|" .. b
end

local function record_contact(world, contacts, kind, left, right, fields)
    local key = kind .. ":" .. contact_key(left, right)
    local prior = contacts[key]
    local impulse = fields.impulse or 0
    local sort_toi = fields.sort_toi or fields.toi or 0
    fields.sort_toi = nil
    if not prior or impulse > prior.impulse then
        contacts[key] = {
            kind = kind,
            left = left,
            right = right,
            fields = fields,
            impulse = impulse,
            sort_toi = sort_toi,
        }
    end
end

local function clamp_speed(world, body)
    local speed2 = body.vx * body.vx + body.vy * body.vy
    local limit2 = world.max_speed * world.max_speed
    if speed2 > limit2 then
        local scale = world.max_speed / sqrt(speed2)
        body.vx, body.vy = body.vx * scale, body.vy * scale
        emit(world, "speed_clamped", { body = body.id, speed = world.max_speed })
    end
end

local function choose_earlier(best, candidate, remaining)
    if not candidate then return best end
    if candidate.time < -TIME_EPSILON or candidate.time > remaining + TIME_EPSILON then
        return best
    end
    candidate.time = clamp(candidate.time, 0, remaining)
    if not best
        or candidate.time < best.time - TIME_EPSILON
        or (abs(candidate.time - best.time) <= TIME_EPSILON and candidate.key < best.key)
    then
        return candidate
    end
    return best
end

local function body_moves(body)
    return body.alive and body.dynamic and not body.asleep
end

local function swept_wall(world, body, remaining)
    if not body_moves(body) then return nil end
    local best
    local radius = body.radius

    local function add(time, wall, nx, ny, penetration)
        best = choose_earlier(best, {
            time = time,
            key = "1:wall:" .. tostring(body.id) .. ":" .. wall,
            kind = "wall",
            body = body,
            wall = wall,
            nx = nx,
            ny = ny,
            penetration = penetration,
        }, remaining)
    end

    if body.x < radius then
        add(0, "left", 1, 0, radius - body.x)
    elseif body.vx < -VELOCITY_EPSILON then
        add((radius - body.x) / body.vx, "left", 1, 0)
    end
    if body.x > world.width - radius then
        add(0, "right", -1, 0, body.x - (world.width - radius))
    elseif body.vx > VELOCITY_EPSILON then
        add((world.width - radius - body.x) / body.vx, "right", -1, 0)
    end
    if body.y < radius then
        add(0, "top", 0, 1, radius - body.y)
    elseif body.vy < -VELOCITY_EPSILON then
        add((radius - body.y) / body.vy, "top", 0, 1)
    end
    if body.y > world.height - radius then
        add(0, "bottom", 0, -1, body.y - (world.height - radius))
    elseif body.vy > VELOCITY_EPSILON then
        add((world.height - radius - body.y) / body.vy, "bottom", 0, -1)
    end
    return best
end

local function box_overlap(body, box)
    local half_w, half_h = box.width / 2, box.height / 2
    local left, right = box.x - half_w, box.x + half_w
    local top, bottom = box.y - half_h, box.y + half_h
    local nearest_x = clamp(body.x, left, right)
    local nearest_y = clamp(body.y, top, bottom)
    local dx, dy = body.x - nearest_x, body.y - nearest_y
    local distance2 = dx * dx + dy * dy
    if distance2 >= body.radius * body.radius then return nil end

    local nx, ny, distance
    if distance2 > 0 then
        distance = sqrt(distance2)
        nx, ny = dx / distance, dy / distance
    else
        local distances = {
            { body.x - left, -1, 0 },
            { right - body.x, 1, 0 },
            { body.y - top, 0, -1 },
            { bottom - body.y, 0, 1 },
        }
        table.sort(distances, function(a, b)
            if a[1] ~= b[1] then return a[1] < b[1] end
            if a[2] ~= b[2] then return a[2] < b[2] end
            return a[3] < b[3]
        end)
        distance, nx, ny = -distances[1][1], distances[1][2], distances[1][3]
    end
    return nx, ny, body.radius - distance
end

local function swept_box(world, body, box, remaining, ignored_sensors)
    if not body_moves(body)
        or not box.alive
        or not collision_allowed(world, body, box)
    then
        return nil
    end

    local sensor_key = "box:" .. contact_key(body.id, box.id)
    if (body.sensor or box.sensor) and ignored_sensors[sensor_key] then return nil end

    local key = "2:box:" .. contact_key(body.id, box.id)
    local nx, ny, penetration = box_overlap(body, box)
    if nx then
        return {
            time = 0, key = key, kind = "box", body = body, box = box,
            nx = nx, ny = ny, penetration = penetration, sensor_key = sensor_key,
        }
    end

    local half_w, half_h = box.width / 2, box.height / 2
    local left, right = box.x - half_w, box.x + half_w
    local top, bottom = box.y - half_h, box.y + half_h
    local radius = body.radius
    local best

    local function add(time, normal_x, normal_y, feature)
        best = choose_earlier(best, {
            time = time,
            key = key .. ":" .. feature,
            kind = "box",
            body = body,
            box = box,
            nx = normal_x,
            ny = normal_y,
            sensor_key = sensor_key,
        }, remaining)
    end

    if body.vx > VELOCITY_EPSILON then
        local time = (left - radius - body.x) / body.vx
        local y = body.y + body.vy * time
        if y >= top - GEOMETRY_EPSILON and y <= bottom + GEOMETRY_EPSILON then
            add(time, -1, 0, "left")
        end
    elseif body.vx < -VELOCITY_EPSILON then
        local time = (right + radius - body.x) / body.vx
        local y = body.y + body.vy * time
        if y >= top - GEOMETRY_EPSILON and y <= bottom + GEOMETRY_EPSILON then
            add(time, 1, 0, "right")
        end
    end
    if body.vy > VELOCITY_EPSILON then
        local time = (top - radius - body.y) / body.vy
        local x = body.x + body.vx * time
        if x >= left - GEOMETRY_EPSILON and x <= right + GEOMETRY_EPSILON then
            add(time, 0, -1, "top")
        end
    elseif body.vy < -VELOCITY_EPSILON then
        local time = (bottom + radius - body.y) / body.vy
        local x = body.x + body.vx * time
        if x >= left - GEOMETRY_EPSILON and x <= right + GEOMETRY_EPSILON then
            add(time, 0, 1, "bottom")
        end
    end

    local speed2 = body.vx * body.vx + body.vy * body.vy
    if speed2 > VELOCITY_EPSILON * VELOCITY_EPSILON then
        local corners = {
            { left, top, -1, -1, "top_left" },
            { right, top, 1, -1, "top_right" },
            { left, bottom, -1, 1, "bottom_left" },
            { right, bottom, 1, 1, "bottom_right" },
        }
        for _, corner in ipairs(corners) do
            local px, py = body.x - corner[1], body.y - corner[2]
            local projection = px * body.vx + py * body.vy
            local c = px * px + py * py - radius * radius
            local discriminant = projection * projection - speed2 * c
            local discriminant_epsilon = GEOMETRY_EPSILON
                * max(abs(projection * projection), abs(speed2 * c), 1e-24)
            if projection < -VELOCITY_EPSILON
                and discriminant >= -discriminant_epsilon
            then
                local time = (-projection - sqrt(max(0, discriminant))) / speed2
                if time >= -TIME_EPSILON and time <= remaining + TIME_EPSILON then
                    local qx = px + body.vx * time
                    local qy = py + body.vy * time
                    local in_x, in_y
                    if corner[3] < 0 then in_x = qx <= GEOMETRY_EPSILON
                    else in_x = qx >= -GEOMETRY_EPSILON end
                    if corner[4] < 0 then in_y = qy <= GEOMETRY_EPSILON
                    else in_y = qy >= -GEOMETRY_EPSILON end
                    if in_x and in_y then
                        local corner_nx, corner_ny = normalise(qx, qy, corner[3], corner[4])
                        if body.vx * corner_nx + body.vy * corner_ny < -VELOCITY_EPSILON then
                            add(time, corner_nx, corner_ny, corner[5])
                        end
                    end
                end
            end
        end
    end
    return best
end

local function swept_pair(world, left, right, remaining, ignored_sensors)
    if not left.alive or not right.alive or not collision_allowed(world, left, right) then
        return nil
    end
    local inv_left = left.dynamic and left.inv_mass or 0
    local inv_right = right.dynamic and right.inv_mass or 0
    if inv_left + inv_right <= 0 then return nil end

    local sensor_key = "body:" .. contact_key(left.id, right.id)
    if (left.sensor or right.sensor) and ignored_sensors[sensor_key] then return nil end

    local left_vx, left_vy = 0, 0
    local right_vx, right_vy = 0, 0
    if body_moves(left) then left_vx, left_vy = left.vx, left.vy end
    if body_moves(right) then right_vx, right_vy = right.vx, right.vy end
    local dx, dy = right.x - left.x, right.y - left.y
    local rvx, rvy = right_vx - left_vx, right_vy - left_vy
    local radius = left.radius + right.radius
    local c = dx * dx + dy * dy - radius * radius
    local contact_epsilon = GEOMETRY_EPSILON * max(radius * radius, 1e-12)
    local fallback = tostring(left.id) < tostring(right.id) and 1 or -1
    local nx, ny, distance = normalise(dx, dy, fallback, 0)
    local key = "3:body:" .. contact_key(left.id, right.id)

    if c < 0 then
        return {
            time = 0, key = key, kind = "body", left = left, right = right,
            nx = nx, ny = ny, penetration = radius - distance, sensor_key = sensor_key,
        }
    end
    local normal_velocity = rvx * nx + rvy * ny
    if c <= contact_epsilon then
        if normal_velocity < -VELOCITY_EPSILON then
            return {
                time = 0, key = key, kind = "body", left = left, right = right,
                nx = nx, ny = ny, sensor_key = sensor_key,
            }
        end
        return nil
    end

    local speed2 = rvx * rvx + rvy * rvy
    local projection = dx * rvx + dy * rvy
    if speed2 <= VELOCITY_EPSILON * VELOCITY_EPSILON
        or projection >= -VELOCITY_EPSILON
    then
        return nil
    end
    local discriminant = projection * projection - speed2 * c
    local discriminant_epsilon = GEOMETRY_EPSILON
        * max(abs(projection * projection), abs(speed2 * c), 1e-24)
    if discriminant < -discriminant_epsilon then return nil end
    local time = (-projection - sqrt(max(0, discriminant))) / speed2
    if time < -TIME_EPSILON or time > remaining + TIME_EPSILON then return nil end
    local hit_dx, hit_dy = dx + rvx * time, dy + rvy * time
    nx, ny = normalise(hit_dx, hit_dy, fallback, 0)
    if rvx * nx + rvy * ny >= -VELOCITY_EPSILON then return nil end
    return {
        time = clamp(time, 0, remaining), key = key, kind = "body",
        left = left, right = right, nx = nx, ny = ny, sensor_key = sensor_key,
    }
end

local function earliest_collision(world, remaining, ignored_sensors)
    local best
    for _, body in ipairs(world.bodies) do
        if body.alive then
            best = choose_earlier(best, swept_wall(world, body, remaining), remaining)
            for _, box in ipairs(world.boxes) do
                best = choose_earlier(
                    best,
                    swept_box(world, body, box, remaining, ignored_sensors),
                    remaining
                )
            end
        end
    end
    for left_index = 1, #world.bodies - 1 do
        local left = world.bodies[left_index]
        if left.alive then
            for right_index = left_index + 1, #world.bodies do
                best = choose_earlier(
                    best,
                    swept_pair(world, left, world.bodies[right_index], remaining, ignored_sensors),
                    remaining
                )
            end
        end
    end
    return best
end

local function advance_bodies(world, amount)
    if amount <= 0 then return end
    for _, body in ipairs(world.bodies) do
        if body_moves(body) then
            body.x = body.x + body.vx * amount
            body.y = body.y + body.vy * amount
        end
    end
end

local function resolve_collision(world, hit, contacts, ignored_sensors, toi, iteration)
    if hit.kind == "wall" then
        local body = hit.body
        if hit.wall == "left" then body.x = body.radius
        elseif hit.wall == "right" then body.x = world.width - body.radius
        elseif hit.wall == "top" then body.y = body.radius
        else body.y = world.height - body.radius end

        local normal_velocity = body.vx * hit.nx + body.vy * hit.ny
        local impulse = 0
        if normal_velocity < 0 then
            impulse = -(1 + body.restitution) * normal_velocity * body.mass
            body.vx = body.vx + hit.nx * impulse * body.inv_mass
            body.vy = body.vy + hit.ny * impulse * body.inv_mass
        end
        record_contact(world, contacts, "wall", body.id, hit.wall, {
            body = body.id, wall = hit.wall,
            nx = hit.nx, ny = hit.ny,
            impulse = quantize(impulse), speed = quantize(abs(normal_velocity)),
            toi = quantize(toi), sort_toi = toi, iteration = iteration,
        })
        return
    end

    if hit.kind == "box" then
        local body, box = hit.body, hit.box
        local sensor = body.sensor or box.sensor
        if sensor then ignored_sensors[hit.sensor_key] = true end
        if not sensor then
            local correction = (hit.penetration or 0) + POSITION_SLOP
            body.x = body.x + hit.nx * correction
            body.y = body.y + hit.ny * correction
        end
        local normal_velocity = body.vx * hit.nx + body.vy * hit.ny
        local impulse = 0
        if normal_velocity < 0 and not sensor then
            local restitution = min(body.restitution, box.restitution)
            impulse = -(1 + restitution) * normal_velocity * body.mass
            body.vx = body.vx + hit.nx * impulse * body.inv_mass
            body.vy = body.vy + hit.ny * impulse * body.inv_mass
        end
        record_contact(world, contacts, sensor and "sensor" or "box", body.id, box.id, {
            body = body.id, box = box.id,
            nx = quantize(hit.nx), ny = quantize(hit.ny),
            impulse = quantize(impulse), speed = quantize(abs(normal_velocity)),
            toi = quantize(toi), sort_toi = toi, iteration = iteration,
        })
        return
    end

    local left, right = hit.left, hit.right
    local sensor = left.sensor or right.sensor
    if sensor then ignored_sensors[hit.sensor_key] = true end
    local inv_left = left.dynamic and left.inv_mass or 0
    local inv_right = right.dynamic and right.inv_mass or 0
    local inv_sum = inv_left + inv_right
    if not sensor then
        local correction = (hit.penetration or 0) + POSITION_SLOP
        left.x = left.x - hit.nx * correction * inv_left / inv_sum
        left.y = left.y - hit.ny * correction * inv_left / inv_sum
        right.x = right.x + hit.nx * correction * inv_right / inv_sum
        right.y = right.y + hit.ny * correction * inv_right / inv_sum
    end

    local rvx, rvy = right.vx - left.vx, right.vy - left.vy
    local normal_velocity = rvx * hit.nx + rvy * hit.ny
    local impulse = 0
    if normal_velocity < 0 and not sensor then
        local restitution = min(left.restitution, right.restitution)
        impulse = -(1 + restitution) * normal_velocity / inv_sum
        left.vx = left.vx - hit.nx * impulse * inv_left
        left.vy = left.vy - hit.ny * impulse * inv_left
        right.vx = right.vx + hit.nx * impulse * inv_right
        right.vy = right.vy + hit.ny * impulse * inv_right
        left.asleep, right.asleep = false, false
        left.sleep_counter, right.sleep_counter = 0, 0
    end
    record_contact(world, contacts, "body", left.id, right.id, {
        a = left.id, b = right.id,
        nx = quantize(hit.nx), ny = quantize(hit.ny),
        impulse = quantize(impulse), speed = quantize(abs(normal_velocity)),
        toi = quantize(toi), sort_toi = toi, iteration = iteration,
    })
end

local function apply_fields(world, dt, contacts)
    for _, field in ipairs(world.fields) do
        if field.alive then
            local direction_x, direction_y = normalise(field.dx, field.dy, 1, 0)
            for _, body in ipairs(world.bodies) do
                if body.alive and body.dynamic then
                    local dx, dy = body.x - field.x, body.y - field.y
                    local nx, ny, distance = normalise(dx, dy,
                        tostring(body.id) < tostring(field.id) and -1 or 1, 0)
                    if distance <= field.radius + body.radius then
                        local scale = field.falloff and max(0, 1 - distance / field.radius) or 1
                        local fx, fy
                        if field.kind == "directional" then
                            fx, fy = direction_x * field.strength * scale, direction_y * field.strength * scale
                        else
                            fx, fy = nx * field.strength * scale, ny * field.strength * scale
                        end
                        body.vx = body.vx + fx * dt * body.inv_mass
                        body.vy = body.vy + fy * dt * body.inv_mass
                        record_contact(world, contacts, "field", body.id, field.id, {
                            body = body.id, field = field.id, kind = field.kind,
                            fx = quantize(fx), fy = quantize(fy), impulse = 0,
                        })
                    end
                end
            end
        end
    end
end

local EVENT_NAMES = {
    wall = "wall_collision",
    box = "box_collision",
    body = "body_collision",
    sensor = "sensor_contact",
    field = "field_contact",
}

local function flush_contacts(world, contacts)
    local keys = {}
    for key in pairs(contacts) do keys[#keys + 1] = key end
    table.sort(keys, function(left_key, right_key)
        local left_toi = contacts[left_key].sort_toi or 0
        local right_toi = contacts[right_key].sort_toi or 0
        if left_toi ~= right_toi then return left_toi < right_toi end
        return left_key < right_key
    end)
    for _, key in ipairs(keys) do
        local contact = contacts[key]
        emit(world, EVENT_NAMES[contact.kind], contact.fields)
    end
end

local function update_sleep(world)
    local threshold2 = world.sleep_speed * world.sleep_speed
    for _, body in ipairs(world.bodies) do
        if body.alive and body.dynamic then
            local speed2 = body.vx * body.vx + body.vy * body.vy
            if speed2 <= threshold2 then
                body.sleep_counter = body.sleep_counter + 1
                if body.sleep_counter >= world.sleep_ticks and not body.asleep then
                    body.asleep = true
                    body.vx, body.vy = 0, 0
                    emit(world, "body_sleep", { body = body.id })
                end
            else
                body.sleep_counter = 0
                body.asleep = false
            end
        end
    end
end

function World:step(dt)
    dt = require_number(dt or self.fixed_dt, "dt")
    if abs(dt - self.fixed_dt) > 1e-12 then
        error(string.format("physics step must equal fixed_dt %.12f, got %.12f", self.fixed_dt, dt))
    end
    self.tick = self.tick + 1
    self.time = self.tick * self.fixed_dt

    for _, body in ipairs(self.bodies) do
        if body.alive and body.dynamic and not body.asleep then
            body.previous_x, body.previous_y = body.x, body.y
            clamp_speed(self, body)
        end
    end

    -- Fields are a deterministic semi-implicit velocity update for this fixed
    -- tick.  Motion after that update is continuous and piecewise linear.
    local contacts = {}
    apply_fields(self, dt, contacts)

    local remaining = dt
    local elapsed = 0
    local iterations = 0
    local ignored_sensors = {}
    self.last_substeps = 1
    self.collision_iteration_limit_hit = false

    while remaining > TIME_EPSILON do
        if iterations >= self.max_collision_iterations then
            self.collision_iteration_limit_hit = true
            emit(self, "collision_iteration_limit", {
                iterations = iterations,
                remaining = quantize(remaining),
            })
            break
        end

        local hit = earliest_collision(self, remaining, ignored_sensors)
        if not hit then
            advance_bodies(self, remaining)
            elapsed = elapsed + remaining
            remaining = 0
        else
            advance_bodies(self, hit.time)
            elapsed = elapsed + hit.time
            remaining = max(0, remaining - hit.time)
            iterations = iterations + 1
            resolve_collision(self, hit, contacts, ignored_sensors, elapsed, iterations)
        end
    end
    self.last_collision_iterations = iterations

    local damping = self.linear_damping
    for _, body in ipairs(self.bodies) do
        if body.alive and body.dynamic and not body.asleep then
            body.vx, body.vy = body.vx * damping, body.vy * damping
        end
    end
    update_sleep(self)
    flush_contacts(self, contacts)

    local expired = {}
    for _, field in ipairs(self.fields) do
        field.age = field.age + 1
        if field.duration and field.age >= field.duration then expired[#expired + 1] = field.id end
    end
    for _, id in ipairs(expired) do self:remove_field(id, "expired") end
    return self:drain_events()
end

function World:is_settled()
    for _, body in ipairs(self.bodies) do
        if body.alive and body.dynamic and not body.asleep then return false end
    end
    for _, field in ipairs(self.fields) do
        if field.alive and field.duration then return false end
    end
    return true
end

function World:drain_events()
    local out = self.events
    self.events = {}
    return out
end

function World:snapshot()
    local snapshot = {
        schema_version = self.schema_version,
        tick = self.tick,
        time = quantize(self.time),
        fixed_dt = self.fixed_dt,
        width = self.width,
        height = self.height,
        substeps = self.last_substeps,
        collision_iterations = self.last_collision_iterations,
        collision_iteration_limit_hit = self.collision_iteration_limit_hit,
        bodies = {},
        boxes = {},
        fields = {},
    }
    for _, body in ipairs(self.bodies) do
        snapshot.bodies[#snapshot.bodies + 1] = {
            id = body.id, kind = body.kind, owner = body.owner,
            x = quantize(body.x), y = quantize(body.y),
            previous_x = quantize(body.previous_x), previous_y = quantize(body.previous_y),
            vx = quantize(body.vx), vy = quantize(body.vy),
            radius = body.radius, mass = body.mass, restitution = body.restitution,
            dynamic = body.dynamic, asleep = body.asleep, alive = body.alive,
            data = copy_table(body.data),
        }
    end
    for _, box in ipairs(self.boxes) do
        snapshot.boxes[#snapshot.boxes + 1] = {
            id = box.id, kind = box.kind, owner = box.owner,
            x = quantize(box.x), y = quantize(box.y),
            width = box.width, height = box.height,
            restitution = box.restitution, sensor = box.sensor, alive = box.alive,
            data = copy_table(box.data),
        }
    end
    for _, field in ipairs(self.fields) do
        snapshot.fields[#snapshot.fields + 1] = {
            id = field.id, kind = field.kind, owner = field.owner,
            x = quantize(field.x), y = quantize(field.y), radius = field.radius,
            strength = field.strength, dx = field.dx, dy = field.dy,
            duration = field.duration, age = field.age, alive = field.alive,
            data = copy_table(field.data),
        }
    end
    return snapshot
end

M.World = World

return M
