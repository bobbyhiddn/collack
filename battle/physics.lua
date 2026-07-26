-- battle/physics.lua -- deterministic fixed-timestep 2D circle physics.
--
-- This module deliberately has no LÖVE dependency.  It is the canonical motion
-- implementation for both headless battle tests and the client.  Bodies and
-- colliders are processed in stable id order and every public snapshot is a
-- value-only copy.

local M = {}
local World = {}
World.__index = World

M.FIXED_DT = 1 / 120
M.SCHEMA_VERSION = 1

local abs, ceil, floor, max, min, sqrt =
    math.abs, math.ceil, math.floor, math.max, math.min, math.sqrt

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
        max_substeps = opts.max_substeps or 64,
        substep_fraction = opts.substep_fraction or 0.35,
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
    if not prior or impulse > prior.impulse then
        contacts[key] = { kind = kind, left = left, right = right, fields = fields, impulse = impulse }
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

local function resolve_wall(world, body, contacts)
    local radius = body.radius
    if body.x < radius then
        body.x = radius
        local incoming = -body.vx
        if body.vx < 0 then body.vx = -body.vx * body.restitution end
        record_contact(world, contacts, "wall", body.id, "left", {
            body = body.id, wall = "left", nx = 1, ny = 0,
            impulse = max(0, incoming * body.mass * (1 + body.restitution)),
        })
    elseif body.x > world.width - radius then
        body.x = world.width - radius
        local incoming = body.vx
        if body.vx > 0 then body.vx = -body.vx * body.restitution end
        record_contact(world, contacts, "wall", body.id, "right", {
            body = body.id, wall = "right", nx = -1, ny = 0,
            impulse = max(0, incoming * body.mass * (1 + body.restitution)),
        })
    end

    if body.y < radius then
        body.y = radius
        local incoming = -body.vy
        if body.vy < 0 then body.vy = -body.vy * body.restitution end
        record_contact(world, contacts, "wall", body.id, "top", {
            body = body.id, wall = "top", nx = 0, ny = 1,
            impulse = max(0, incoming * body.mass * (1 + body.restitution)),
        })
    elseif body.y > world.height - radius then
        body.y = world.height - radius
        local incoming = body.vy
        if body.vy > 0 then body.vy = -body.vy * body.restitution end
        record_contact(world, contacts, "wall", body.id, "bottom", {
            body = body.id, wall = "bottom", nx = 0, ny = -1,
            impulse = max(0, incoming * body.mass * (1 + body.restitution)),
        })
    end
end

local function resolve_box(world, body, box, contacts)
    if not box.alive or not collision_allowed(world, body, box) then return end
    local half_w, half_h = box.width / 2, box.height / 2
    local left, right = box.x - half_w, box.x + half_w
    local top, bottom = box.y - half_h, box.y + half_h
    local nearest_x = clamp(body.x, left, right)
    local nearest_y = clamp(body.y, top, bottom)
    local dx, dy = body.x - nearest_x, body.y - nearest_y
    local distance2 = dx * dx + dy * dy
    if distance2 >= body.radius * body.radius then return end

    local nx, ny, distance
    if distance2 > 1e-18 then
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

    local penetration = body.radius - distance
    if not box.sensor and not body.sensor then
        body.x = body.x + nx * penetration
        body.y = body.y + ny * penetration
        local normal_velocity = body.vx * nx + body.vy * ny
        local restitution = min(body.restitution, box.restitution)
        local impulse = 0
        if normal_velocity < 0 then
            impulse = -(1 + restitution) * normal_velocity * body.mass
            body.vx = body.vx + nx * impulse * body.inv_mass
            body.vy = body.vy + ny * impulse * body.inv_mass
        end
        record_contact(world, contacts, "box", body.id, box.id, {
            body = body.id, box = box.id, nx = quantize(nx), ny = quantize(ny),
            impulse = quantize(impulse), speed = quantize(abs(normal_velocity)),
        })
    else
        record_contact(world, contacts, "sensor", body.id, box.id, {
            body = body.id, box = box.id, nx = quantize(nx), ny = quantize(ny), impulse = 0,
        })
    end
end

local function resolve_pair(world, left, right, contacts)
    if not left.alive or not right.alive or not collision_allowed(world, left, right) then return end
    local dx, dy = right.x - left.x, right.y - left.y
    local radius = left.radius + right.radius
    local distance2 = dx * dx + dy * dy
    if distance2 >= radius * radius then return end

    local fallback = tostring(left.id) < tostring(right.id) and 1 or -1
    local nx, ny, distance = normalise(dx, dy, fallback, 0)
    local inv_left = left.dynamic and left.inv_mass or 0
    local inv_right = right.dynamic and right.inv_mass or 0
    local inv_sum = inv_left + inv_right
    if inv_sum <= 0 then return end
    local penetration = radius - distance
    if not left.sensor and not right.sensor then
        left.x = left.x - nx * penetration * inv_left / inv_sum
        left.y = left.y - ny * penetration * inv_left / inv_sum
        right.x = right.x + nx * penetration * inv_right / inv_sum
        right.y = right.y + ny * penetration * inv_right / inv_sum
    end

    local rvx, rvy = right.vx - left.vx, right.vy - left.vy
    local normal_velocity = rvx * nx + rvy * ny
    local impulse = 0
    if normal_velocity < 0 and not left.sensor and not right.sensor then
        local restitution = min(left.restitution, right.restitution)
        impulse = -(1 + restitution) * normal_velocity / inv_sum
        left.vx = left.vx - nx * impulse * inv_left
        left.vy = left.vy - ny * impulse * inv_left
        right.vx = right.vx + nx * impulse * inv_right
        right.vy = right.vy + ny * impulse * inv_right
        left.asleep, right.asleep = false, false
        left.sleep_counter, right.sleep_counter = 0, 0
    end
    record_contact(world, contacts, "body", left.id, right.id, {
        a = left.id, b = right.id, nx = quantize(nx), ny = quantize(ny),
        impulse = quantize(impulse), speed = quantize(abs(normal_velocity)),
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
    table.sort(keys)
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

    local min_radius, fastest = nil, 0
    for _, body in ipairs(self.bodies) do
        if body.alive and body.dynamic and not body.asleep then
            body.previous_x, body.previous_y = body.x, body.y
            clamp_speed(self, body)
            local speed = sqrt(body.vx * body.vx + body.vy * body.vy)
            if speed > fastest then fastest = speed end
            if not min_radius or body.radius < min_radius then min_radius = body.radius end
        end
    end
    local safe_distance = max(0.05, (min_radius or 1) * self.substep_fraction)
    local substeps = clamp(ceil(fastest * dt / safe_distance), 1, self.max_substeps)
    self.last_substeps = substeps
    local sub_dt = dt / substeps
    local contacts = {}

    for _ = 1, substeps do
        apply_fields(self, sub_dt, contacts)
        for _, body in ipairs(self.bodies) do
            if body.alive and body.dynamic and not body.asleep then
                body.x = body.x + body.vx * sub_dt
                body.y = body.y + body.vy * sub_dt
                resolve_wall(self, body, contacts)
                for _, box in ipairs(self.boxes) do resolve_box(self, body, box, contacts) end
            end
        end
        for left_index = 1, #self.bodies - 1 do
            local left = self.bodies[left_index]
            if left.alive then
                for right_index = left_index + 1, #self.bodies do
                    resolve_pair(self, left, self.bodies[right_index], contacts)
                end
            end
        end
    end

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
