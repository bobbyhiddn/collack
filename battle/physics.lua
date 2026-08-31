-- battle/physics.lua -- deterministic fixed-timestep continuous 2D circle physics.
--
-- This module deliberately has no LÖVE dependency.  It is the canonical motion
-- implementation for both headless battle tests and the client.  Bodies and
-- colliders are processed in stable id order.  Each fixed tick advances to the
-- earliest swept time of impact, resolves it, and repeats under a hard
-- iteration bound; collision safety never depends on sampled overlap
-- microsteps.  Every public snapshot is a value-only copy.

local numeric = require("battle.numeric")

local M = {}
local World = {}
World.__index = World

M.FIXED_DT = 1 / 120
M.SCHEMA_VERSION = 2
M.NUMERIC_LIMITS = {
    max_geometry_magnitude = numeric.MAX_GEOMETRY_MAGNITUDE,
    max_speed = numeric.MAX_SPEED,
    min_mass = numeric.MIN_MASS,
    max_mass = numeric.MAX_MASS,
    max_force_magnitude = numeric.MAX_FORCE_MAGNITUDE,
    max_canonical_magnitude = numeric.MAX_CANONICAL_MAGNITUDE,
}

local abs, ceil, floor, max, min, sqrt =
    math.abs, math.ceil, math.floor, math.max, math.min, math.sqrt

local TIME_EPSILON = 1e-12
local GEOMETRY_EPSILON = 1e-12
local VELOCITY_EPSILON = 1e-14
local POSITION_SLOP = 1e-9
local VALID_RETURN_WALLS = { left = true, right = true, top = true, bottom = true }

local finite = numeric.is_finite

local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function copy_table(source, name)
    return numeric.input_copy(source or {}, name or "physics data")
end

local function copy_output_table(source, name)
    return numeric.canonical_copy(source or {}, name or "physics output")
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

local function require_number(value, name, minimum, maximum)
    return numeric.require_number(value, name, minimum, maximum)
end

local function validate_world_boundary(world)
    require_number(world.width, "world width", 0, numeric.MAX_GEOMETRY_MAGNITUDE)
    require_number(world.height, "world height", 0, numeric.MAX_GEOMETRY_MAGNITUDE)
    require_number(world.fixed_dt, "world fixed_dt", 0, numeric.MAX_FIXED_DT)
    require_number(world.max_speed, "world max_speed", 0, numeric.MAX_SPEED)
    require_number(world.linear_damping, "world linear_damping", 0, 1)
    require_number(world.sleep_speed, "world sleep_speed", 0, numeric.MAX_GEOMETRY_MAGNITUDE)
    numeric.require_integer(world.sleep_ticks, "world sleep_ticks", 1, numeric.MAX_TICKS)
    require_number(world.restitution, "world restitution", 0, numeric.MAX_RESTITUTION)
    numeric.require_integer(
        world.max_collision_iterations,
        "world max_collision_iterations",
        1,
        numeric.MAX_COLLISION_ITERATIONS
    )
    numeric.require_integer(world.tick, "world tick", 0, numeric.MAX_TICKS)
    numeric.require_integer(world.event_seq, "world event sequence", 0, numeric.MAX_TICKS)
    require_number(world.time, "world time", 0, numeric.MAX_GEOMETRY_MAGNITUDE)
    if world.width <= 0 or world.height <= 0 or world.fixed_dt <= 0 or world.max_speed <= 0 then
        error("world dimensions, fixed_dt, and max_speed must remain positive")
    end
    if type(world.bodies) ~= "table"
        or type(world.boxes) ~= "table"
        or type(world.fields) ~= "table"
        or type(world.events) ~= "table"
    then
        error("world collections must remain tables")
    end
    if world.can_collide ~= nil and type(world.can_collide) ~= "function" then
        error("world can_collide must remain a function")
    end
end

local function normalise(x, y, fallback_x, fallback_y)
    return numeric.normalise(x, y, fallback_x, fallback_y, VELOCITY_EPSILON)
end

local quantize = numeric.quantize

local function emit(world, kind, fields)
    if world.event_seq >= numeric.MAX_TICKS then
        error("physics event sequence exceeded its canonical bound")
    end
    world.event_seq = world.event_seq + 1
    local event = {
        seq = world.event_seq,
        tick = world.tick,
        time = quantize(world.time),
        type = kind,
    }
    local canonical_fields, recoveries = numeric.canonical_copy(
        fields or {},
        "physics event " .. tostring(kind)
    )
    for key, value in pairs(canonical_fields) do event[key] = value end
    if recoveries > 0 then event.numeric_recovery_count = recoveries end
    world.events[#world.events + 1] = event
    return event
end

function M.new(opts)
    opts = opts or {}
    local geometry_limit = numeric.MAX_GEOMETRY_MAGNITUDE
    local width = require_number(opts.width or 70, "width", 0, geometry_limit)
    local height = require_number(opts.height or 120, "height", 0, geometry_limit)
    local fixed_dt = require_number(
        opts.fixed_dt or M.FIXED_DT,
        "fixed_dt",
        0,
        numeric.MAX_FIXED_DT
    )
    local max_speed = require_number(opts.max_speed or 240, "max_speed", 0, numeric.MAX_SPEED)
    local linear_damping = require_number(
        opts.linear_damping or 0.996,
        "linear_damping",
        0,
        1
    )
    local sleep_speed = require_number(opts.sleep_speed or 1.25, "sleep_speed", 0, geometry_limit)
    local sleep_ticks = require_number(
        opts.sleep_ticks or 36,
        "sleep_ticks",
        1,
        numeric.MAX_TICKS
    )
    local restitution = require_number(
        opts.restitution or 0.82,
        "restitution",
        0,
        numeric.MAX_RESTITUTION
    )
    local max_collision_iterations = require_number(
        opts.max_collision_iterations or 128,
        "max_collision_iterations",
        1,
        numeric.MAX_COLLISION_ITERATIONS
    )
    if width <= 0 or height <= 0 then error("world bounds must be positive") end
    if fixed_dt <= 0 then error("fixed_dt must be positive") end
    if max_speed <= 0 then error("max_speed must be positive") end
    if linear_damping < 0 then error("linear_damping must be non-negative") end
    if sleep_speed < 0 or sleep_ticks < 1 then
        error("sleep settings must be non-negative with at least one tick")
    end
    if restitution < 0 then error("restitution must be non-negative") end

    return setmetatable({
        schema_version = M.SCHEMA_VERSION,
        fixed_dt = fixed_dt,
        width = width,
        height = height,
        max_speed = max_speed,
        -- Retained as value-compatible legacy configuration/snapshot state.
        -- Continuous collision detection always uses one authoritative tick.
        max_substeps = floor(require_number(
            opts.max_substeps or 64,
            "max_substeps",
            1,
            numeric.MAX_COLLISION_ITERATIONS
        )),
        substep_fraction = require_number(
            opts.substep_fraction or 0.35,
            "substep_fraction",
            0,
            1
        ),
        max_collision_iterations = max(1, floor(max_collision_iterations)),
        linear_damping = linear_damping,
        sleep_speed = sleep_speed,
        sleep_ticks = floor(sleep_ticks),
        restitution = restitution,
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
    local id = numeric.require_identifier(assert(spec.id, "body id is required"), "body id")
    if self.body_by_id[id] then error("duplicate body id: " .. tostring(id)) end
    local geometry_limit = numeric.MAX_GEOMETRY_MAGNITUDE
    local radius = require_number(spec.radius or 1, "body radius", 0, geometry_limit)
    local mass = require_number(
        spec.mass or 1,
        "body mass",
        numeric.MIN_MASS,
        numeric.MAX_MASS
    )
    if radius <= 0 or mass <= 0 then error("body radius and mass must be positive") end

    local restitution = require_number(
        spec.restitution or self.restitution,
        "body restitution",
        0,
        numeric.MAX_RESTITUTION
    )
    local fallback_x = require_number(
        spec.motion_fallback_x or 1,
        "motion fallback x",
        -geometry_limit,
        geometry_limit
    )
    local fallback_y = require_number(
        spec.motion_fallback_y or 0,
        "motion fallback y",
        -geometry_limit,
        geometry_limit
    )
    fallback_x, fallback_y = normalise(fallback_x, fallback_y, 1, 0)
    local minimum_speed = require_number(spec.minimum_speed or 0, "minimum speed", 0, self.max_speed)
    if minimum_speed < 0 or minimum_speed > self.max_speed then
        error("minimum speed must be between zero and max_speed")
    end
    if spec.return_wall ~= nil and not VALID_RETURN_WALLS[spec.return_wall] then
        error("return_wall must name a world wall")
    end
    local body = {
        id = id,
        kind = spec.kind or "circle",
        owner = spec.owner,
        x = require_number(spec.x or 0, "body x", -geometry_limit, geometry_limit),
        y = require_number(spec.y or 0, "body y", -geometry_limit, geometry_limit),
        previous_x = spec.x or 0,
        previous_y = spec.y or 0,
        vx = require_number(spec.vx or 0, "body vx", -geometry_limit, geometry_limit),
        vy = require_number(spec.vy or 0, "body vy", -geometry_limit, geometry_limit),
        radius = radius,
        mass = mass,
        inv_mass = 1 / mass,
        restitution = restitution,
        dynamic = spec.dynamic ~= false,
        sensor = spec.sensor == true,
        asleep = spec.asleep == true,
        sleep_counter = floor(require_number(
            spec.sleep_counter or 0,
            "body sleep_counter",
            0,
            numeric.MAX_TICKS
        )),
        alive = spec.alive ~= false,
        motion_active = spec.motion_active == true,
        minimum_speed = minimum_speed,
        motion_fallback_x = fallback_x,
        motion_fallback_y = fallback_y,
        return_wall = spec.return_wall,
        floor_limited = false,
        data = copy_table(spec.data, "body data"),
    }
    if body.motion_active and not body.dynamic then
        error("an active motion body must be dynamic")
    end
    if body.motion_active and body.minimum_speed <= 0 then
        error("an active motion body must have a positive minimum speed")
    end
    self.body_by_id[id] = body
    ordered_insert(self.bodies, body)
    emit(self, "body_added", { body = id })
    local initial_nx, initial_ny, initial_speed = normalise(
        body.vx,
        body.vy,
        body.motion_fallback_x,
        body.motion_fallback_y
    )
    if initial_speed > self.max_speed then
        body.vx, body.vy = initial_nx * self.max_speed, initial_ny * self.max_speed
        initial_speed = self.max_speed
        emit(self, "speed_clamped", { body = id, speed = self.max_speed })
    end
    if body.motion_active then
        body.asleep = false
        body.sleep_counter = 0
        if initial_speed < body.minimum_speed then
            body.vx, body.vy = initial_nx * body.minimum_speed, initial_ny * body.minimum_speed
            body.floor_limited = true
            emit(self, "motion_floor_applied", {
                body = id,
                minimum_speed = quantize(body.minimum_speed),
                prior_speed = quantize(initial_speed),
                reason = "added",
            })
        end
        body.motion_fallback_x, body.motion_fallback_y = normalise(
            body.vx,
            body.vy,
            body.motion_fallback_x,
            body.motion_fallback_y
        )
    end
    return body
end

function World:add_box(spec)
    assert(type(spec) == "table", "box spec must be a table")
    local id = numeric.require_identifier(assert(spec.id, "box id is required"), "box id")
    if self.box_by_id[id] then error("duplicate box id: " .. tostring(id)) end
    local geometry_limit = numeric.MAX_GEOMETRY_MAGNITUDE
    local width = require_number(spec.width, "box width", 0, geometry_limit)
    local height = require_number(spec.height, "box height", 0, geometry_limit)
    local restitution = require_number(
        spec.restitution or self.restitution,
        "box restitution",
        0,
        numeric.MAX_RESTITUTION
    )
    if width <= 0 or height <= 0 then error("box dimensions must be positive") end
    if restitution < 0 then error("box restitution must be non-negative") end
    local box = {
        id = id,
        kind = spec.kind or "box",
        owner = spec.owner,
        x = require_number(spec.x, "box x", -geometry_limit, geometry_limit),
        y = require_number(spec.y, "box y", -geometry_limit, geometry_limit),
        width = width,
        height = height,
        restitution = restitution,
        sensor = spec.sensor == true,
        alive = spec.alive ~= false,
        data = copy_table(spec.data, "box data"),
    }
    self.box_by_id[id] = box
    ordered_insert(self.boxes, box)
    emit(self, "box_added", { box = id })
    return box
end

function World:add_field(spec)
    assert(type(spec) == "table", "field spec must be a table")
    local id = numeric.require_identifier(assert(spec.id, "field id is required"), "field id")
    if self.field_by_id[id] then error("duplicate field id: " .. tostring(id)) end
    local geometry_limit = numeric.MAX_GEOMETRY_MAGNITUDE
    local field = {
        id = id,
        kind = spec.kind or "radial",
        owner = spec.owner,
        x = require_number(spec.x or 0, "field x", -geometry_limit, geometry_limit),
        y = require_number(spec.y or 0, "field y", -geometry_limit, geometry_limit),
        radius = require_number(spec.radius or 1, "field radius", 0, geometry_limit),
        strength = require_number(
            spec.strength or 0,
            "field strength",
            -numeric.MAX_FORCE_MAGNITUDE,
            numeric.MAX_FORCE_MAGNITUDE
        ),
        dx = require_number(spec.dx or 0, "field dx", -geometry_limit, geometry_limit),
        dy = require_number(spec.dy or 0, "field dy", -geometry_limit, geometry_limit),
        falloff = spec.falloff ~= false,
        duration = spec.duration and floor(require_number(
            spec.duration,
            "field duration",
            1,
            numeric.MAX_TICKS
        )) or nil,
        age = 0,
        alive = true,
        data = copy_table(spec.data, "field data"),
    }
    if field.radius <= 0 then error("field radius must be positive") end
    if field.duration and field.duration < 1 then error("field duration must be positive") end
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
        body.motion_active = false
        body.floor_limited = false
    end
    return body
end

function World:set_position(id, x, y)
    local body = assert(self.body_by_id[id], "unknown body: " .. tostring(id))
    local limit = numeric.MAX_GEOMETRY_MAGNITUDE
    body.x, body.y = require_number(x, "body x", -limit, limit),
        require_number(y, "body y", -limit, limit)
    body.previous_x, body.previous_y = body.x, body.y
    return body
end

function World:set_velocity(id, vx, vy)
    local body = assert(self.body_by_id[id], "unknown body: " .. tostring(id))
    local limit = numeric.MAX_GEOMETRY_MAGNITUDE
    body.vx, body.vy = require_number(vx, "body vx", -limit, limit),
        require_number(vy, "body vy", -limit, limit)
    body.asleep = false
    body.sleep_counter = 0
    self:enforce_motion(id, "set_velocity")
    return body
end

function World:set_motion_active(id, active, profile)
    local body = assert(self.body_by_id[id], "unknown body: " .. tostring(id))
    profile = profile or {}
    if active then
        local minimum_speed = require_number(
            profile.minimum_speed or body.minimum_speed,
            "minimum speed",
            0,
            self.max_speed
        )
        if minimum_speed <= 0 or minimum_speed > self.max_speed then
            error("active minimum speed must be positive and no greater than max_speed")
        end
        local return_wall = profile.return_wall or body.return_wall
        if return_wall ~= nil and not VALID_RETURN_WALLS[return_wall] then
            error("return_wall must name a world wall")
        end
        if profile.fallback_x ~= nil or profile.fallback_y ~= nil then
            local fallback_x = require_number(
                profile.fallback_x or body.motion_fallback_x,
                "motion fallback x",
                -numeric.MAX_GEOMETRY_MAGNITUDE,
                numeric.MAX_GEOMETRY_MAGNITUDE
            )
            local fallback_y = require_number(
                profile.fallback_y or body.motion_fallback_y,
                "motion fallback y",
                -numeric.MAX_GEOMETRY_MAGNITUDE,
                numeric.MAX_GEOMETRY_MAGNITUDE
            )
            body.motion_fallback_x, body.motion_fallback_y = normalise(
                fallback_x,
                fallback_y,
                body.motion_fallback_x,
                body.motion_fallback_y
            )
        end
        body.minimum_speed = minimum_speed
        body.return_wall = return_wall
        body.dynamic = true
        body.motion_active = true
        body.asleep = false
        body.sleep_counter = 0
        self:enforce_motion(id, "activated")
    else
        body.motion_active = false
        body.return_wall = nil
        body.floor_limited = false
    end
    return body
end

function World:set_motion_floor(id, minimum_speed)
    local body = assert(self.body_by_id[id], "unknown body: " .. tostring(id))
    minimum_speed = require_number(minimum_speed, "minimum speed", 0, self.max_speed)
    if minimum_speed <= 0 or minimum_speed > self.max_speed then
        error("active minimum speed must be positive and no greater than max_speed")
    end
    body.minimum_speed = minimum_speed
    if body.motion_active then self:enforce_motion(id, "floor_changed") end
    return body
end

function World:apply_impulse(id, ix, iy, opts)
    local body = self.body_by_id[id]
    if not body or not body.alive then return false end
    opts = opts or {}
    if not body.dynamic and opts.wake_static then body.dynamic = true end
    if not body.dynamic then return false end
    ix = require_number(
        ix,
        "impulse x",
        -numeric.MAX_FORCE_MAGNITUDE,
        numeric.MAX_FORCE_MAGNITUDE
    )
    iy = require_number(
        iy,
        "impulse y",
        -numeric.MAX_FORCE_MAGNITUDE,
        numeric.MAX_FORCE_MAGNITUDE
    )
    local delta_x, recovered_x = numeric.saturating_product(
        numeric.MAX_CANONICAL_MAGNITUDE,
        ix,
        body.inv_mass
    )
    local delta_y, recovered_y = numeric.saturating_product(
        numeric.MAX_CANONICAL_MAGNITUDE,
        iy,
        body.inv_mass
    )
    local added_x, add_recovered_x = numeric.saturating_add(
        body.vx,
        delta_x,
        numeric.MAX_CANONICAL_MAGNITUDE
    )
    local added_y, add_recovered_y = numeric.saturating_add(
        body.vy,
        delta_y,
        numeric.MAX_CANONICAL_MAGNITUDE
    )
    body.vx, body.vy = added_x, added_y
    body.asleep = false
    body.sleep_counter = 0
    local recovered = recovered_x or recovered_y or add_recovered_x or add_recovered_y
    self:enforce_motion(id, "impulse")
    if recovered then
        emit(self, "numeric_saturation", { body = id, component = "impulse_velocity" })
    end
    emit(self, "impulse", { body = id, ix = quantize(ix), iy = quantize(iy), source = opts.source })
    return true
end

function World:apply_radial_impulse(x, y, radius, strength, opts)
    opts = opts or {}
    local geometry_limit = numeric.MAX_GEOMETRY_MAGNITUDE
    x = require_number(x, "radial impulse x", -geometry_limit, geometry_limit)
    y = require_number(y, "radial impulse y", -geometry_limit, geometry_limit)
    radius = require_number(radius, "radial impulse radius", 0, geometry_limit)
    strength = require_number(
        strength,
        "radial impulse strength",
        -numeric.MAX_FORCE_MAGNITUDE,
        numeric.MAX_FORCE_MAGNITUDE
    )
    if radius <= 0 then error("radial impulse radius must be positive") end
    local affected = {}
    for _, body in ipairs(self.bodies) do
        if body.alive and (body.dynamic or opts.wake_static) then
            local dx, dy = body.x - x, body.y - y
            local nx, ny, distance = normalise(dx, dy,
                tostring(body.id) < tostring(opts.source or "") and -1 or 1, 0)
            if distance <= radius + body.radius then
                local scale = opts.falloff == false and 1 or max(0, 1 - distance / radius)
                local force, force_recovered = numeric.saturating_product(
                    numeric.MAX_FORCE_MAGNITUDE,
                    strength,
                    scale
                )
                if opts.invert then force = -force end
                if abs(force) > VELOCITY_EPSILON then
                    if not body.dynamic and opts.wake_static then body.dynamic = true end
                    local delta_x, recovered_x = numeric.saturating_product(
                        numeric.MAX_CANONICAL_MAGNITUDE,
                        nx,
                        force,
                        body.inv_mass
                    )
                    local delta_y, recovered_y = numeric.saturating_product(
                        numeric.MAX_CANONICAL_MAGNITUDE,
                        ny,
                        force,
                        body.inv_mass
                    )
                    local added_x, add_recovered_x = numeric.saturating_add(
                        body.vx,
                        delta_x,
                        numeric.MAX_CANONICAL_MAGNITUDE
                    )
                    local added_y, add_recovered_y = numeric.saturating_add(
                        body.vy,
                        delta_y,
                        numeric.MAX_CANONICAL_MAGNITUDE
                    )
                    body.vx, body.vy = added_x, added_y
                    body.asleep = false
                    body.sleep_counter = 0
                    local recovered = force_recovered or recovered_x or recovered_y
                        or add_recovered_x or add_recovered_y
                    self:enforce_motion(body.id, "radial_impulse")
                    if recovered then
                        emit(self, "numeric_saturation", {
                            body = body.id,
                            component = "radial_impulse_velocity",
                        })
                    end
                    affected[#affected + 1] = body.id
                    emit(self, "radial_impulse", {
                        body = body.id, source = opts.source, strength = quantize(force),
                        nx = quantize(nx), ny = quantize(ny),
                    })
                end
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
    local impulse, impulse_recovered = numeric.bound(
        fields.impulse or 0,
        0,
        numeric.MAX_CANONICAL_MAGNITUDE
    )
    local sort_toi, toi_recovered = numeric.bound(
        fields.sort_toi or fields.toi or 0,
        0,
        numeric.MAX_FIXED_DT
    )
    fields.sort_toi = nil
    fields.impulse = impulse
    local canonical_fields, recovery_count = numeric.canonical_copy(
        fields,
        "physics contact " .. tostring(kind)
    )
    fields = canonical_fields
    if not impulse_recovered and not toi_recovered and recovery_count == 0 then
        fields.numeric_recovery_count = nil
    else
        fields.numeric_recovery_count = recovery_count
            + (impulse_recovered and 1 or 0)
            + (toi_recovered and 1 or 0)
    end
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

-- The fixed-step boundary audits every mutable numeric carrier before any
-- force, collision, or integration arithmetic. Public constructors reject
-- invalid inputs; this recovery path deterministically contains later state
-- contamination before it can enter a derived value.
local function recover_body_parameters(world, body)
    local recovered = false
    if not numeric.is_bounded(body.radius, numeric.MAX_GEOMETRY_MAGNITUDE)
        or body.radius <= 0
    then
        body.radius = 1
        recovered = true
    end
    if not numeric.is_bounded(body.mass, numeric.MAX_MASS)
        or body.mass < numeric.MIN_MASS
    then
        body.mass = 1
        recovered = true
    end
    local inverse_mass = 1 / body.mass
    if body.inv_mass ~= inverse_mass then
        body.inv_mass = inverse_mass
        recovered = true
    end
    if not numeric.is_bounded(body.restitution, numeric.MAX_RESTITUTION)
        or body.restitution < 0
    then
        body.restitution = world.restitution
        recovered = true
    end
    if not numeric.is_bounded(body.minimum_speed, world.max_speed)
        or body.minimum_speed < 0
        or (body.motion_active and body.minimum_speed <= 0)
    then
        body.minimum_speed = body.motion_active and min(world.max_speed, 1) or 0
        recovered = true
    end
    local fallback_x, fallback_y, fallback_length = normalise(
        body.motion_fallback_x,
        body.motion_fallback_y,
        1,
        0
    )
    if not numeric.is_bounded(body.motion_fallback_x, numeric.MAX_GEOMETRY_MAGNITUDE)
        or not numeric.is_bounded(body.motion_fallback_y, numeric.MAX_GEOMETRY_MAGNITUDE)
        or fallback_length == 0
        or abs(fallback_length - 1) > 1e-12
    then
        body.motion_fallback_x, body.motion_fallback_y = fallback_x, fallback_y
        recovered = true
    end
    if not numeric.is_bounded(body.sleep_counter, numeric.MAX_TICKS)
        or body.sleep_counter < 0
    then
        body.sleep_counter = 0
        recovered = true
    end
    local data, data_recoveries = numeric.canonical_copy(body.data, "body data")
    if data_recoveries > 0 then
        body.data = data
        recovered = true
    end
    if recovered then
        emit(world, "non_finite_recovered", { body = body.id, component = "parameters" })
    end
end

local function recover_colliders(world)
    for _, box in ipairs(world.boxes) do
        local recovered = false
        if not numeric.is_bounded(box.x, numeric.MAX_GEOMETRY_MAGNITUDE) then
            box.x, recovered = world.width / 2, true
        end
        if not numeric.is_bounded(box.y, numeric.MAX_GEOMETRY_MAGNITUDE) then
            box.y, recovered = world.height / 2, true
        end
        if not numeric.is_bounded(box.width, numeric.MAX_GEOMETRY_MAGNITUDE)
            or box.width <= 0
        then
            box.width, recovered = 1, true
        end
        if not numeric.is_bounded(box.height, numeric.MAX_GEOMETRY_MAGNITUDE)
            or box.height <= 0
        then
            box.height, recovered = 1, true
        end
        if not numeric.is_bounded(box.restitution, numeric.MAX_RESTITUTION)
            or box.restitution < 0
        then
            box.restitution, recovered = world.restitution, true
        end
        local data, data_recoveries = numeric.canonical_copy(box.data, "box data")
        if data_recoveries > 0 then box.data, recovered = data, true end
        if recovered then
            emit(world, "non_finite_recovered", { box = box.id, component = "box" })
        end
    end

    for _, field in ipairs(world.fields) do
        local recovered = false
        if not numeric.is_bounded(field.x, numeric.MAX_GEOMETRY_MAGNITUDE) then
            field.x, recovered = world.width / 2, true
        end
        if not numeric.is_bounded(field.y, numeric.MAX_GEOMETRY_MAGNITUDE) then
            field.y, recovered = world.height / 2, true
        end
        if not numeric.is_bounded(field.radius, numeric.MAX_GEOMETRY_MAGNITUDE)
            or field.radius <= 0
        then
            field.radius, recovered = 1, true
        end
        if not numeric.is_bounded(field.strength, numeric.MAX_FORCE_MAGNITUDE) then
            field.strength, recovered = 0, true
        end
        if not numeric.is_bounded(field.dx, numeric.MAX_GEOMETRY_MAGNITUDE) then
            field.dx, recovered = 1, true
        end
        if not numeric.is_bounded(field.dy, numeric.MAX_GEOMETRY_MAGNITUDE) then
            field.dy, recovered = 0, true
        end
        if field.duration ~= nil
            and (not numeric.is_bounded(field.duration, numeric.MAX_TICKS)
                or field.duration < 1)
        then
            field.duration, recovered = 1, true
        end
        if not numeric.is_bounded(field.age, numeric.MAX_TICKS) or field.age < 0 then
            field.age, recovered = 0, true
        end
        local data, data_recoveries = numeric.canonical_copy(field.data, "field data")
        if data_recoveries > 0 then field.data, recovered = data, true end
        if recovered then
            emit(world, "non_finite_recovered", { field = field.id, component = "field" })
        end
    end
end

local function recover_position(world, body)
    local recovered = false
    if not numeric.is_bounded(body.x, numeric.MAX_GEOMETRY_MAGNITUDE) then
        body.x = numeric.is_bounded(body.previous_x, numeric.MAX_GEOMETRY_MAGNITUDE)
            and body.previous_x or world.width / 2
        recovered = true
    end
    if not numeric.is_bounded(body.y, numeric.MAX_GEOMETRY_MAGNITUDE) then
        body.y = numeric.is_bounded(body.previous_y, numeric.MAX_GEOMETRY_MAGNITUDE)
            and body.previous_y or world.height / 2
        recovered = true
    end
    body.x = clamp(body.x, body.radius, world.width - body.radius)
    body.y = clamp(body.y, body.radius, world.height - body.radius)
    if not numeric.is_bounded(body.previous_x, numeric.MAX_GEOMETRY_MAGNITUDE) then
        body.previous_x = body.x
        recovered = true
    end
    if not numeric.is_bounded(body.previous_y, numeric.MAX_GEOMETRY_MAGNITUDE) then
        body.previous_y = body.y
        recovered = true
    end
    if recovered then emit(world, "non_finite_recovered", { body = body.id, component = "position" }) end
end

local function enforce_motion(world, body, reason)
    if not finite(body.vx) or not finite(body.vy) then
        if body.motion_active then
            body.vx = body.motion_fallback_x * body.minimum_speed
            body.vy = body.motion_fallback_y * body.minimum_speed
            body.asleep = false
        else
            body.vx, body.vy = 0, 0
            body.asleep = true
        end
        emit(world, "non_finite_recovered", { body = body.id, component = "velocity" })
    end

    local nx, ny, speed = normalise(
        body.vx,
        body.vy,
        body.motion_fallback_x,
        body.motion_fallback_y
    )
    if speed > world.max_speed then
        body.vx, body.vy = nx * world.max_speed, ny * world.max_speed
        speed = world.max_speed
        emit(world, "speed_clamped", { body = body.id, speed = world.max_speed })
    end
    if body.motion_active then
        body.asleep = false
        body.sleep_counter = 0
        if speed < body.minimum_speed then
            body.vx, body.vy = nx * body.minimum_speed, ny * body.minimum_speed
            local should_emit = not body.floor_limited or speed <= VELOCITY_EPSILON
            body.floor_limited = true
            if should_emit then
                emit(world, "motion_floor_applied", {
                    body = body.id,
                    minimum_speed = quantize(body.minimum_speed),
                    prior_speed = quantize(speed),
                    reason = reason,
                })
            end
        elseif speed > body.minimum_speed + VELOCITY_EPSILON then
            body.floor_limited = false
        end
        body.motion_fallback_x, body.motion_fallback_y = normalise(
            body.vx,
            body.vy,
            body.motion_fallback_x,
            body.motion_fallback_y
        )
    end
end

function World:enforce_motion(id, reason)
    local body = assert(self.body_by_id[id], "unknown body: " .. tostring(id))
    recover_body_parameters(self, body)
    recover_position(self, body)
    enforce_motion(self, body, reason or "explicit")
    return body
end

-- Derived velocity must respect the canonical energy ceiling before any more
-- movement in this tick.  Keep the playable momentum floor on its established
-- pre/post-step boundary, though: applying that floor between contacts changes
-- ordinary authored collision timing and released deterministic replays.
local function enforce_velocity_ceiling(world, body, reason)
    if not finite(body.vx) or not finite(body.vy) then
        enforce_motion(world, body, reason)
        return
    end
    local nx, ny, speed = normalise(
        body.vx,
        body.vy,
        body.motion_fallback_x,
        body.motion_fallback_y
    )
    if speed > world.max_speed then
        body.vx, body.vy = nx * world.max_speed, ny * world.max_speed
        emit(world, "speed_clamped", { body = body.id, speed = world.max_speed })
    end
end

local function add_velocity(world, body, delta_x, delta_y, reason)
    local next_x, recovered_x = numeric.saturating_add(
        body.vx,
        delta_x,
        numeric.MAX_CANONICAL_MAGNITUDE
    )
    local next_y, recovered_y = numeric.saturating_add(
        body.vy,
        delta_y,
        numeric.MAX_CANONICAL_MAGNITUDE
    )
    body.vx, body.vy = next_x, next_y
    local recovered = recovered_x or recovered_y
    enforce_velocity_ceiling(world, body, reason)
    if recovered then
        emit(world, "numeric_saturation", {
            body = body.id,
            component = reason or "velocity",
        })
    end
end

local function dot_product(ax, ay, bx, by)
    local x, recovered_x = numeric.saturating_product(
        numeric.MAX_CANONICAL_MAGNITUDE,
        ax,
        bx
    )
    local y, recovered_y = numeric.saturating_product(
        numeric.MAX_CANONICAL_MAGNITUDE,
        ay,
        by
    )
    local value, recovered_add = numeric.saturating_add(
        x,
        y,
        numeric.MAX_CANONICAL_MAGNITUDE
    )
    return value, recovered_x or recovered_y or recovered_add
end

local function choose_earlier(best, candidate, remaining)
    if not candidate then return best end
    if not finite(candidate.time) then return best end
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
    if inv_left <= 0 and inv_right <= 0 then return nil end

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
            local displacement_x, recovered_x = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE,
                body.vx,
                amount
            )
            local displacement_y, recovered_y = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE,
                body.vy,
                amount
            )
            local next_x, recovered_add_x = numeric.saturating_add(
                body.x,
                displacement_x,
                numeric.MAX_CANONICAL_MAGNITUDE
            )
            local next_y, recovered_add_y = numeric.saturating_add(
                body.y,
                displacement_y,
                numeric.MAX_CANONICAL_MAGNITUDE
            )
            body.x, body.y = next_x, next_y
            if recovered_x or recovered_y or recovered_add_x or recovered_add_y then
                recover_position(world, body)
                emit(world, "numeric_saturation", {
                    body = body.id,
                    component = "displacement",
                })
            end
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

        local normal_velocity, velocity_recovered = dot_product(
            body.vx,
            body.vy,
            hit.nx,
            hit.ny
        )
        local impulse = 0
        local returned = body.motion_active and body.return_wall == hit.wall
        if returned then
            body.vx, body.vy = 0, 0
            body.dynamic = false
            body.asleep = true
            body.sleep_counter = 0
            body.motion_active = false
            body.floor_limited = false
        elseif normal_velocity < 0 then
            local impulse_recovered
            impulse, impulse_recovered = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE,
                -(1 + body.restitution),
                normal_velocity,
                body.mass
            )
            local delta_x, delta_recovered_x = numeric.limited_product(
                numeric.MAX_CANONICAL_MAGNITUDE,
                hit.nx,
                -(1 + body.restitution),
                normal_velocity,
                body.mass,
                body.inv_mass
            )
            local delta_y, delta_recovered_y = numeric.limited_product(
                numeric.MAX_CANONICAL_MAGNITUDE,
                hit.ny,
                -(1 + body.restitution),
                normal_velocity,
                body.mass,
                body.inv_mass
            )
            add_velocity(world, body, delta_x, delta_y, "wall_collision")
            if impulse_recovered or delta_recovered_x or delta_recovered_y then
                emit(world, "numeric_saturation", {
                    body = body.id,
                    component = "wall_impulse",
                })
            end
        end
        if velocity_recovered then
            emit(world, "numeric_saturation", { body = body.id, component = "wall_velocity" })
        end
        record_contact(world, contacts, "wall", body.id, hit.wall, {
            body = body.id, wall = hit.wall,
            nx = hit.nx, ny = hit.ny,
            impulse = quantize(impulse), speed = quantize(abs(normal_velocity)),
            toi = quantize(toi), sort_toi = toi, iteration = iteration,
            returned = returned,
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
        local normal_velocity, velocity_recovered = dot_product(
            body.vx,
            body.vy,
            hit.nx,
            hit.ny
        )
        local impulse = 0
        if normal_velocity < 0 and not sensor then
            local restitution = min(body.restitution, box.restitution)
            local impulse_recovered
            impulse, impulse_recovered = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE,
                -(1 + restitution),
                normal_velocity,
                body.mass
            )
            local delta_x, delta_recovered_x = numeric.limited_product(
                numeric.MAX_CANONICAL_MAGNITUDE,
                hit.nx,
                -(1 + restitution),
                normal_velocity,
                body.mass,
                body.inv_mass
            )
            local delta_y, delta_recovered_y = numeric.limited_product(
                numeric.MAX_CANONICAL_MAGNITUDE,
                hit.ny,
                -(1 + restitution),
                normal_velocity,
                body.mass,
                body.inv_mass
            )
            add_velocity(world, body, delta_x, delta_y, "box_collision")
            if impulse_recovered or delta_recovered_x or delta_recovered_y then
                emit(world, "numeric_saturation", {
                    body = body.id,
                    component = "box_impulse",
                })
            end
        end
        if velocity_recovered then
            emit(world, "numeric_saturation", { body = body.id, component = "box_velocity" })
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
    local inv_sum
    if inv_left <= numeric.MAX_CANONICAL_MAGNITUDE - inv_right then
        inv_sum = inv_left + inv_right
    end
    local inv_scale = max(inv_left, inv_right)
    local scaled_left = inv_scale > 0 and inv_left / inv_scale or 0
    local scaled_right = inv_scale > 0 and inv_right / inv_scale or 0
    local scaled_sum = scaled_left + scaled_right
    local left_share = scaled_sum > 0 and scaled_left / scaled_sum or 0
    local right_share = scaled_sum > 0 and scaled_right / scaled_sum or 0
    if not sensor then
        local correction = (hit.penetration or 0) + POSITION_SLOP
        local direct_correction = inv_sum
            and inv_sum > 0
            and (inv_left == 0 or abs(correction) <= numeric.MAX_CANONICAL_MAGNITUDE / inv_left)
            and (inv_right == 0 or abs(correction) <= numeric.MAX_CANONICAL_MAGNITUDE / inv_right)
        if direct_correction then
            left.x = left.x - hit.nx * correction * inv_left / inv_sum
            left.y = left.y - hit.ny * correction * inv_left / inv_sum
            right.x = right.x + hit.nx * correction * inv_right / inv_sum
            right.y = right.y + hit.ny * correction * inv_right / inv_sum
        else
            left.x = left.x - hit.nx * correction * left_share
            left.y = left.y - hit.ny * correction * left_share
            right.x = right.x + hit.nx * correction * right_share
            right.y = right.y + hit.ny * correction * right_share
        end
    end

    local rvx = numeric.saturating_add(
        right.vx,
        -left.vx,
        numeric.MAX_CANONICAL_MAGNITUDE
    )
    local rvy = numeric.saturating_add(
        right.vy,
        -left.vy,
        numeric.MAX_CANONICAL_MAGNITUDE
    )
    local normal_velocity, velocity_recovered = dot_product(rvx, rvy, hit.nx, hit.ny)
    local impulse = 0
    if normal_velocity < 0 and not sensor then
        local restitution = min(left.restitution, right.restitution)
        local response = -(1 + restitution) * normal_velocity
        local direct_impulse = inv_sum
            and inv_sum > 0
            and inv_sum >= abs(response) / numeric.MAX_CANONICAL_MAGNITUDE
        local left_delta_x, left_delta_y, right_delta_x, right_delta_y
        local saturated = false
        if direct_impulse then
            impulse = response / inv_sum
            left_delta_x = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE, -hit.nx, impulse, inv_left)
            left_delta_y = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE, -hit.ny, impulse, inv_left)
            right_delta_x = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE, hit.nx, impulse, inv_right)
            right_delta_y = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE, hit.ny, impulse, inv_right)
        else
            local impulse_recovered
            impulse, impulse_recovered = numeric.limited_product(
                numeric.MAX_CANONICAL_MAGNITUDE,
                response,
                inv_scale > 0 and 1 / inv_scale or 0,
                scaled_sum > 0 and 1 / scaled_sum or 0
            )
            left_delta_x = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE, -hit.nx, response, left_share)
            left_delta_y = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE, -hit.ny, response, left_share)
            right_delta_x = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE, hit.nx, response, right_share)
            right_delta_y = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE, hit.ny, response, right_share)
            saturated = impulse_recovered
        end
        add_velocity(world, left, left_delta_x, left_delta_y, "body_collision")
        add_velocity(world, right, right_delta_x, right_delta_y, "body_collision")
        if saturated then
            emit(world, "numeric_saturation", {
                body = tostring(left.id) .. "|" .. tostring(right.id),
                component = "body_impulse",
            })
        end
        left.asleep, right.asleep = false, false
        left.sleep_counter, right.sleep_counter = 0, 0
    end
    if velocity_recovered then
        emit(world, "numeric_saturation", {
            body = tostring(left.id) .. "|" .. tostring(right.id),
            component = "body_velocity",
        })
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
                        local fx, fy, force_recovered_x, force_recovered_y
                        if field.kind == "directional" then
                            fx, force_recovered_x = numeric.saturating_product(
                                numeric.MAX_FORCE_MAGNITUDE,
                                direction_x,
                                field.strength,
                                scale
                            )
                            fy, force_recovered_y = numeric.saturating_product(
                                numeric.MAX_FORCE_MAGNITUDE,
                                direction_y,
                                field.strength,
                                scale
                            )
                        else
                            fx, force_recovered_x = numeric.saturating_product(
                                numeric.MAX_FORCE_MAGNITUDE,
                                nx,
                                field.strength,
                                scale
                            )
                            fy, force_recovered_y = numeric.saturating_product(
                                numeric.MAX_FORCE_MAGNITUDE,
                                ny,
                                field.strength,
                                scale
                            )
                        end
                        local delta_x, delta_recovered_x = numeric.saturating_product(
                            numeric.MAX_CANONICAL_MAGNITUDE,
                            fx,
                            dt,
                            body.inv_mass
                        )
                        local delta_y, delta_recovered_y = numeric.saturating_product(
                            numeric.MAX_CANONICAL_MAGNITUDE,
                            fy,
                            dt,
                            body.inv_mass
                        )
                        add_velocity(world, body, delta_x, delta_y, "field")
                        if force_recovered_x or force_recovered_y
                            or delta_recovered_x or delta_recovered_y
                        then
                            emit(world, "numeric_saturation", {
                                body = body.id,
                                field = field.id,
                                component = "field_acceleration",
                            })
                        end
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
        if body.alive and body.dynamic and body.motion_active then
            body.asleep = false
            body.sleep_counter = 0
        elseif body.alive and body.dynamic then
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
    validate_world_boundary(self)
    dt = require_number(dt or self.fixed_dt, "dt", 0, numeric.MAX_FIXED_DT)
    if abs(dt - self.fixed_dt) > 1e-12 then
        error(string.format("physics step must equal fixed_dt %.12f, got %.12f", self.fixed_dt, dt))
    end
    if self.tick >= numeric.MAX_TICKS then
        error("physics tick exceeded its canonical bound")
    end
    self.tick = self.tick + 1
    self.time = self.tick * self.fixed_dt

    for _, body in ipairs(self.bodies) do
        if body.alive then
            recover_body_parameters(self, body)
            recover_position(self, body)
            enforce_motion(self, body, "pre_step")
        end
        if body.alive and body.dynamic and not body.asleep then
            body.previous_x, body.previous_y = body.x, body.y
        end
    end
    recover_colliders(self)

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
            body.vx = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE,
                body.vx,
                damping
            )
            body.vy = numeric.saturating_product(
                numeric.MAX_CANONICAL_MAGNITUDE,
                body.vy,
                damping
            )
            enforce_motion(self, body, "post_step")
        end
        if body.alive then recover_position(self, body) end
    end
    update_sleep(self)
    flush_contacts(self, contacts)

    local expired = {}
    for _, field in ipairs(self.fields) do
        field.age = min(numeric.MAX_TICKS, field.age + 1)
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
    local out, recoveries = numeric.canonical_copy(self.events, "physics event queue")
    self.events = {}
    if recoveries > 0 then out.numeric_recovery_count = recoveries end
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
            motion_active = body.motion_active,
            minimum_speed = body.minimum_speed,
            motion_fallback_x = quantize(body.motion_fallback_x),
            motion_fallback_y = quantize(body.motion_fallback_y),
            return_wall = body.return_wall,
            data = copy_output_table(body.data, "body snapshot data"),
        }
    end
    for _, box in ipairs(self.boxes) do
        snapshot.boxes[#snapshot.boxes + 1] = {
            id = box.id, kind = box.kind, owner = box.owner,
            x = quantize(box.x), y = quantize(box.y),
            width = box.width, height = box.height,
            restitution = box.restitution, sensor = box.sensor, alive = box.alive,
            data = copy_output_table(box.data, "box snapshot data"),
        }
    end
    for _, field in ipairs(self.fields) do
        snapshot.fields[#snapshot.fields + 1] = {
            id = field.id, kind = field.kind, owner = field.owner,
            x = quantize(field.x), y = quantize(field.y), radius = field.radius,
            strength = field.strength, dx = field.dx, dy = field.dy,
            duration = field.duration, age = field.age, alive = field.alive,
            data = copy_output_table(field.data, "field snapshot data"),
        }
    end
    local canonical, recoveries = numeric.canonical_copy(snapshot, "physics snapshot")
    if recoveries > 0 then canonical.numeric_recovery_count = recoveries end
    return canonical
end

M.World = World

return M
