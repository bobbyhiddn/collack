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

if failures == 0 then
    print("OK: all logic tests passed")
    os.exit(0)
else
    print(string.format("%d test(s) failed", failures))
    os.exit(1)
end
