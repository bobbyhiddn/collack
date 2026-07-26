-- LÖVE entry point. love.* calls fenced inside callbacks; logic lives in logic.lua.
local logic = require("logic")

-- Single source of truth for the play-area size (was hardcoded as 800 in the
-- touch handlers and again in every draw call).
local C = logic.constants()
local FIELD_W, FIELD_H = C.FIELD_W, C.FIELD_H

local world
local input = { left = false, right = false }

-- Touch-capability flag, used only to pick which on-screen hints to show.
-- love.system.getOS() reports "Web" under love.js -- including inside the
-- Capacitor iOS wrapper -- so the OS string cannot tell a phone from a desktop
-- browser (verified in-browser). Two independent signals instead:
--   1. the web shell passes "--touch" when the browser reports a touchscreen,
--      so the very first frame already shows the right hint;
--   2. any real touch event flips the flag, which covers native mobile builds
--      and any shell that does not pass the argument.
local has_touch = false

-- love.js hands pointer events to us already mapped into the window's pixel
-- space: SDL's emscripten backend subtracts the canvas offset and rescales by
-- the CSS size. Verified in-browser -- on a 390px-wide viewport (canvas CSS
-- width 390, top offset 287) a tap at the canvas centre arrives as x=400 on the
-- 800px-wide window. Converting through the live window width is therefore a
-- no-op today, but keeps the mapping correct if the backing store ever stops
-- matching the logical field (high-DPI, a resizable window, a letterboxed shell).
local function to_field_x(x)
    local w = love.graphics.getWidth()
    if w <= 0 then return x end
    return x * (FIELD_W / w)
end

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("Collack Spike")
    world = logic.new_world()

    local argv = args or arg
    if type(argv) == "table" then
        for _, v in ipairs(argv) do
            if v == "--touch" then has_touch = true end
        end
    end
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

-- Touch: drag to aim the paddle, tap to restart a finished round.
function love.touchpressed(id, x, y)
    has_touch = true
    logic.pointer_press(world, to_field_x(x))
end

function love.touchmoved(id, x, y)
    has_touch = true
    logic.pointer_move(world, to_field_x(x))
end

-- Mouse: same two gestures, so a desktop browser is playable without a keyboard.
-- On touch devices SDL also synthesises mouse events from touches; both paths
-- write the same paddle target, and a doubled restart just resets twice.
function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    logic.pointer_press(world, to_field_x(x))
end

function love.mousemoved(x, y)
    if not love.mouse.isDown(1) then return end
    logic.pointer_move(world, to_field_x(x))
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

    if world.status ~= "playing" then
        local restart = has_touch and "tap to " or "press SPACE to "
        local verb = world.status == "won" and "replay" or "retry"
        local headline = world.status == "won" and "YOU WIN" or "YOU LOST"
        love.graphics.printf(headline .. " — " .. restart .. verb, 0, FIELD_H / 2 - 20, FIELD_W, "center")
    end

    love.graphics.setColor(0.6, 0.6, 0.7, 1)
    -- ASCII only: the default LÖVE font has no glyphs for the arrow characters
    -- the old hint used, so they rendered as tofu boxes in the web build.
    local hint = has_touch and "Drag to move    Tap to restart"
                            or "Arrow keys or A/D to move    R: reset    ESC: quit"
    love.graphics.printf(hint, 0, FIELD_H - 20, FIELD_W, "center")
end
