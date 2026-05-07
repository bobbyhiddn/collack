-- Pure-logic module. NO love.* calls. Unit-testable from plain Lua.
-- Owns the world state: marble, paddle, bricks, score, status.

local M = {}

local FIELD_W, FIELD_H = 800, 600
local PADDLE_W, PADDLE_H = 110, 14
local PADDLE_Y = 560
local PADDLE_SPEED = 480
local MARBLE_R = 9
local MARBLE_SPEED = 360
local BRICK_W, BRICK_H = 78, 22
local BRICK_COLS, BRICK_ROWS = 9, 3
local BRICK_PADDING_X, BRICK_PADDING_Y = 6, 8
local BRICK_X_OFFSET = (FIELD_W - (BRICK_COLS * BRICK_W + (BRICK_COLS - 1) * BRICK_PADDING_X)) / 2
local BRICK_Y_OFFSET = 60

function M.constants()
    return {
        FIELD_W = FIELD_W, FIELD_H = FIELD_H,
        PADDLE_W = PADDLE_W, PADDLE_H = PADDLE_H,
        MARBLE_R = MARBLE_R,
        BRICK_W = BRICK_W, BRICK_H = BRICK_H,
    }
end

function M.new_world()
    local w = {
        paddle = { x = (FIELD_W - PADDLE_W) / 2, y = PADDLE_Y, w = PADDLE_W, h = PADDLE_H },
        marble = { x = FIELD_W / 2, y = FIELD_H / 2, vx = MARBLE_SPEED * 0.6, vy = -MARBLE_SPEED * 0.8, r = MARBLE_R },
        bricks = {},
        score = 0,
        status = "playing", -- "playing" | "won" | "lost"
        bricks_remaining = BRICK_COLS * BRICK_ROWS,
    }
    for row = 1, BRICK_ROWS do
        for col = 1, BRICK_COLS do
            local x = BRICK_X_OFFSET + (col - 1) * (BRICK_W + BRICK_PADDING_X)
            local y = BRICK_Y_OFFSET + (row - 1) * (BRICK_H + BRICK_PADDING_Y)
            table.insert(w.bricks, { x = x, y = y, w = BRICK_W, h = BRICK_H, alive = true, row = row })
        end
    end
    return w
end

local function aabb(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local function circle_aabb_collide(cx, cy, cr, bx, by, bw, bh)
    local nx = math.max(bx, math.min(cx, bx + bw))
    local ny = math.max(by, math.min(cy, by + bh))
    local dx, dy = cx - nx, cy - ny
    if dx * dx + dy * dy <= cr * cr then
        -- Resolve by closer axis (heuristic).
        local overlap_x = (bw / 2 + cr) - math.abs(cx - (bx + bw / 2))
        local overlap_y = (bh / 2 + cr) - math.abs(cy - (by + bh / 2))
        local axis = overlap_x < overlap_y and "x" or "y"
        return true, axis
    end
    return false, nil
end

function M.move_paddle(world, direction, dt)
    -- direction: -1 (left), 0 (none), 1 (right)
    local p = world.paddle
    p.x = p.x + direction * PADDLE_SPEED * dt
    if p.x < 0 then p.x = 0 end
    if p.x + p.w > FIELD_W then p.x = FIELD_W - p.w end
end

function M.update(world, dt)
    if world.status ~= "playing" then return end

    local m = world.marble
    m.x = m.x + m.vx * dt
    m.y = m.y + m.vy * dt

    -- Wall collisions.
    if m.x - m.r < 0 then m.x = m.r; m.vx = -m.vx end
    if m.x + m.r > FIELD_W then m.x = FIELD_W - m.r; m.vx = -m.vx end
    if m.y - m.r < 0 then m.y = m.r; m.vy = -m.vy end

    -- Floor: lose.
    if m.y - m.r > FIELD_H then
        world.status = "lost"
        return
    end

    -- Paddle collision.
    local p = world.paddle
    if aabb(m.x - m.r, m.y - m.r, m.r * 2, m.r * 2, p.x, p.y, p.w, p.h) and m.vy > 0 then
        m.y = p.y - m.r
        m.vy = -m.vy
        -- English: hit-position influences horizontal velocity.
        local hit_pos = (m.x - (p.x + p.w / 2)) / (p.w / 2)
        m.vx = m.vx + hit_pos * 120
        -- Clamp velocity magnitude.
        local sp = math.sqrt(m.vx * m.vx + m.vy * m.vy)
        local target = MARBLE_SPEED
        if sp > 0 then
            m.vx = m.vx / sp * target
            m.vy = m.vy / sp * target
        end
    end

    -- Brick collisions.
    for _, b in ipairs(world.bricks) do
        if b.alive then
            local hit, axis = circle_aabb_collide(m.x, m.y, m.r, b.x, b.y, b.w, b.h)
            if hit then
                b.alive = false
                world.bricks_remaining = world.bricks_remaining - 1
                world.score = world.score + (4 - b.row) * 10  -- top rows worth more
                if axis == "x" then m.vx = -m.vx else m.vy = -m.vy end
                break -- one brick per frame keeps physics readable
            end
        end
    end

    if world.bricks_remaining <= 0 then
        world.status = "won"
    end
end

function M.reset(world)
    local fresh = M.new_world()
    for k, v in pairs(fresh) do world[k] = v end
end

return M
