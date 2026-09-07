package.path = "src/?.lua;./?.lua;" .. package.path
local codec = require("save_codec")
local session = require("run_session")
local loop = require("run_loop")
local util = require("battle.run_util")
local checks = 0
local function check(value, label)
    checks = checks + 1
    assert(value, label)
end

local values = { flag = false, binary = "a\0\n:b;", float = 1 / 7, empty = {},
    nested = { [1] = "one", [3] = true, name = "collector" } }
check(util.deep_equal(values, codec.decode(codec.encode(values))), "Value and numeric-key roundtrip")
check(codec.encode({ b = 2, a = 1 }) == codec.encode({ a = 1, b = 2 }), "Stable save ordering")
for _, bytes in ipairs({ "return os.execute('oops')", "COLLACK1\ns999999:short",
    "COLLACK1\na99999999:", "COLLACK1\nztrailing", "COLLACK1\nnnan;",
    "COLLACK1\na2:s1:an1;s1:an2;", "COLLACK1\na1:zz" }) do
    check(not pcall(codec.decode, bytes), "Reject malformed save without executing it")
end
local cycle = {}; cycle.self = cycle
check(not pcall(codec.encode, cycle), "Reject cyclic save data")

-- Later fights store over a million scalar fields across recorded snapshots.
-- Exercise that scale without running an expensive additional physics match.
local recording = { frames = {} }
for index = 1, 100001 do
    recording.frames[index] = { tick = index, x = 10, y = 20, vx = 3, vy = -4 }
end
local recording_bytes = codec.encode(recording)
local loaded_recording = codec.decode(recording_bytes)
check(#loaded_recording.frames == #recording.frames
    and util.deep_equal(loaded_recording.frames[100001], recording.frames[100001]),
    "Later-fight recordings roundtrip beyond the opening fight's size")
recording, recording_bytes, loaded_recording = nil, nil, nil
collectgarbage("collect")

local app = loop.new({ short_run = true, run_seed = 9125 })
local uid = app.model.run.player.bricks[1].uid
assert(loop.activate(app, "brick:" .. uid, "test"))
assert(loop.activate(app, "cell:3:7", "test"))
local bag = util.deep_copy(app.model.run.setup.bag_order)
check(session.arrange(app), "Quick arrange completes a legal formation")
check(app.model.run.setup.formation[3][7] == uid, "Quick arrange preserves manual placements")
check(util.deep_equal(bag, app.model.run.setup.bag_order), "Quick arrange preserves bag order")
local journal_size = #app.model.run.journal
check(session.arrange(app), "Already arranged is still valid")
check(#app.model.run.journal == journal_size, "Quick arrange is idempotent")

local bytes = assert(session.encode(app))
local restored = assert(session.restore(bytes, { muted = true, reduced_motion = true }))
check(util.deep_equal(app.model.run, restored.model.run), "Resume preserves canonical setup and journal")
check(restored.model.ui.muted and restored.model.ui.reduced_motion, "Resume applies current settings")
check(restored.world == nil, "Resume does not start an automatic battle prematurely")
check(session.restore("corrupt") == nil, "Corrupt save returns a recoverable error")
local wrong_version = codec.decode(bytes); wrong_version.content_version = "old"
check(session.restore(codec.encode(wrong_version)) == nil, "Incompatible saves cannot silently change rules")

assert(loop.activate(restored, "lock_setup", "test"))
check(session.encode(restored) == nil, "An in-flight battle cannot overwrite its setup checkpoint")
check(session.arrange(restored) == nil, "Quick arrange cannot change an active battle")
local inspected_id
for _, action in ipairs(loop.project(restored).actions) do
    if action.id:match("^entity:") then inspected_id = action.id; break end
end
assert(inspected_id)
local tick = restored.world.tick
assert(loop.activate(restored, inspected_id, "touch"))
check(restored.model.ui.paused, "Inspecting an active battle pauses it")
loop.update(restored, 1)
check(restored.world.tick == tick, "Reading an inspection cannot consume combat time")
assert(loop.activate(restored, inspected_id, "touch"))
check(not restored.model.ui.paused, "Closing inspection restores a running battle")
assert(loop.activate(restored, "battle_pause", "keyboard"))
assert(loop.activate(restored, inspected_id, "touch"))
assert(loop.activate(restored, inspected_id, "touch"))
check(restored.model.ui.paused, "Closing inspection preserves a pre-existing pause")
assert(loop.activate(restored, inspected_id, "touch"))
assert(loop.activate(restored, "battle_pause", "touch"))
check(not restored.model.ui.paused and not restored.model.ui.inspected_entity_id,
    "Resume dismisses the inspection and reveals the arena")
print("OK: " .. checks .. " expedition session checks passed")
