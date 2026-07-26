-- Pure-Lua test for logic.lua. Run with: `lua tests/test_logic.lua`
-- Requires no LÖVE — proves the logic module is engine-independent.

package.path = package.path .. ";./src/?.lua"
local logic = require("logic")

local failures = 0
local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        failures = failures + 1
        print(string.format("FAIL: %s — expected %s, got %s", msg or "?", tostring(expected), tostring(actual)))
    end
end

local function assert_true(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. (msg or "?"))
    end
end

-- new_world basics
local w = logic.new_world()
assert_eq(w.status, "playing", "fresh world status")
assert_eq(w.score, 0, "fresh score")
assert_eq(w.bricks_remaining, 27, "27 bricks (3x9)")
assert_true(#w.bricks == 27, "27 brick entries")
assert_true(w.marble.r > 0, "marble has radius")
assert_true(w.paddle.w > 0, "paddle has width")

-- paddle movement clamps to field
logic.move_paddle(w, -1, 100)  -- huge dt, would overflow if unclamped
assert_eq(w.paddle.x, 0, "paddle clamped left")
logic.move_paddle(w, 1, 100)
assert_eq(w.paddle.x, 800 - w.paddle.w, "paddle clamped right")

-- update with no-collision tick advances marble
local w2 = logic.new_world()
local ox, oy = w2.marble.x, w2.marble.y
logic.update(w2, 0.016)
assert_true(w2.marble.x ~= ox or w2.marble.y ~= oy, "marble advanced")

-- losing condition: drop marble below floor
local w3 = logic.new_world()
w3.marble.y = 5000  -- well below floor
logic.update(w3, 0.016)
assert_eq(w3.status, "lost", "lost when below floor")

-- winning condition: kill all bricks
local w4 = logic.new_world()
for _, b in ipairs(w4.bricks) do b.alive = false end
w4.bricks_remaining = 0
logic.update(w4, 0.016)
assert_eq(w4.status, "won", "won when no bricks")

-- reset restores fresh state
logic.reset(w4)
assert_eq(w4.status, "playing", "reset restores playing")
assert_eq(w4.bricks_remaining, 27, "reset restores brick count")

-- pointer aiming centres the paddle on the pointer and clamps to the field
local w5 = logic.new_world()
logic.set_paddle_center(w5, 400)
assert_eq(w5.paddle.x, 400 - w5.paddle.w / 2, "paddle centred on pointer")
logic.set_paddle_center(w5, -500)
assert_eq(w5.paddle.x, 0, "paddle clamped left by pointer")
logic.set_paddle_center(w5, 99999)
assert_eq(w5.paddle.x, 800 - w5.paddle.w, "paddle clamped right by pointer")

-- pointer_press while playing aims, and does NOT restart
local w6 = logic.new_world()
w6.score = 70
local restarted = logic.pointer_press(w6, 200)
assert_eq(restarted, false, "press while playing does not restart")
assert_eq(w6.paddle.x, 200 - w6.paddle.w / 2, "press while playing aims paddle")
assert_eq(w6.score, 70, "press while playing keeps score")

-- pointer_press on a finished round restarts it: the only restart path a
-- touch-only device has (R and SPACE are keyboard-bound).
local w7 = logic.new_world()
w7.marble.y = 5000
logic.update(w7, 0.016)
assert_eq(w7.status, "lost", "w7 is lost before the tap")
w7.score = 120
assert_eq(logic.pointer_press(w7, 400), true, "tap after loss reports a restart")
assert_eq(w7.status, "playing", "tap after loss restarts the round")
assert_eq(w7.score, 0, "tap after loss clears the score")
assert_eq(w7.bricks_remaining, 27, "tap after loss restores the bricks")

-- same for a won round
local w8 = logic.new_world()
for _, b in ipairs(w8.bricks) do b.alive = false end
w8.bricks_remaining = 0
logic.update(w8, 0.016)
assert_eq(w8.status, "won", "w8 is won before the tap")
assert_eq(logic.pointer_press(w8, 400), true, "tap after win reports a restart")
assert_eq(w8.status, "playing", "tap after win restarts the round")

-- pointer_move aims while playing, and is ignored on a finished round so a
-- stray drag across the game-over screen cannot silently restart it
local w9 = logic.new_world()
assert_eq(logic.pointer_move(w9, 300), true, "drag while playing moves paddle")
assert_eq(w9.paddle.x, 300 - w9.paddle.w / 2, "drag while playing aims paddle")
w9.status = "lost"
local frozen = w9.paddle.x
assert_eq(logic.pointer_move(w9, 600), false, "drag after loss reports no move")
assert_eq(w9.paddle.x, frozen, "drag after loss leaves paddle alone")
assert_eq(w9.status, "lost", "drag after loss does not restart")

if failures == 0 then
    print("OK: all logic tests passed")
    os.exit(0)
else
    print(string.format("%d test(s) failed", failures))
    os.exit(1)
end
