-- LÖVE entry point. love.* calls fenced inside callbacks; logic lives in logic.lua.
local logic = require("logic")

local world
local input = { left = false, right = false }

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("Collack Spike")
    world = logic.new_world()
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    if key == "r" then logic.reset(world) end
    if key == "left" or key == "a" then input.left = true end
    if key == "right" or key == "d" then input.right = true end
    if key == "space" and world.status ~= "playing" then logic.reset(world) end
end

function love.keyreleased(key)
    if key == "left" or key == "a" then input.left = false end
    if key == "right" or key == "d" then input.right = false end
end

-- Touch: simple horizontal-tap follow for iOS Capacitor wrap.
function love.touchpressed(id, x, y)
    if world and world.status == "playing" then
        local target = x
        local p = world.paddle
        p.x = math.max(0, math.min(target - p.w / 2, 800 - p.w))
    end
end

function love.touchmoved(id, x, y)
    if world and world.status == "playing" then
        local p = world.paddle
        p.x = math.max(0, math.min(x - p.w / 2, 800 - p.w))
    end
end

function love.update(dt)
    local dir = 0
    if input.left then dir = dir - 1 end
    if input.right then dir = dir + 1 end
    logic.move_paddle(world, dir, dt)
    logic.update(world, dt)
end

function love.draw()
    love.graphics.clear(0.04, 0.04, 0.08, 1)

    -- Bricks.
    for _, b in ipairs(world.bricks) do
        if b.alive then
            local hue = b.row == 1 and {0.95, 0.35, 0.35} or
                        b.row == 2 and {0.95, 0.75, 0.30} or
                                       {0.40, 0.85, 0.55}
            love.graphics.setColor(hue)
            love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 4, 4)
            love.graphics.setColor(0, 0, 0, 0.25)
            love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 4, 4)
        end
    end

    -- Paddle.
    love.graphics.setColor(0.85, 0.90, 0.95, 1)
    love.graphics.rectangle("fill", world.paddle.x, world.paddle.y, world.paddle.w, world.paddle.h, 6, 6)

    -- Marble.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", world.marble.x, world.marble.y, world.marble.r)
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.circle("line", world.marble.x, world.marble.y, world.marble.r)

    -- HUD.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Score: " .. world.score, 14, 14)
    love.graphics.print("Bricks: " .. world.bricks_remaining, 14, 32)

    if world.status == "won" then
        love.graphics.printf("YOU WIN — press SPACE to replay", 0, 280, 800, "center")
    elseif world.status == "lost" then
        love.graphics.printf("YOU LOST — press SPACE to retry", 0, 280, 800, "center")
    end

    love.graphics.setColor(0.6, 0.6, 0.7, 1)
    love.graphics.printf("←/→ or A/D to move    R: reset    ESC: quit", 0, 580, 800, "center")
end
