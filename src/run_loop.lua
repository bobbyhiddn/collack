-- LÖVE-independent integration loop for one complete Callack run.
--
-- RunController owns draft/setup/result state. battle.engine is the only
-- combat implementation. This module only carries the mutable engine world
-- between the handoff and the value-only completion callback.

local checkpoints = require("battle.checkpoints")
local contract = require("battle.vslice_contract")
local engine = require("battle.engine")
local controller = require("run_controller")

local M = {}

M.SCHEMA_VERSION = 1
M.MAX_STEPS_PER_UPDATE = contract.PHYSICS.MAX_STEPS_PER_UPDATE

local function append_events(loop, events)
    for _, event in ipairs(events or {}) do
        loop.events[#loop.events + 1] = event
    end
end

local function clear_battle_runtime(loop)
    loop.world = nil
    loop.previous_frame = nil
    loop.current_frame = nil
    loop.accumulator = 0
end

local function start_battle(loop)
    local handoff = loop.model.run.battle and loop.model.run.battle.handoff
    assert(handoff, "battle phase is missing its canonical handoff")
    loop.world = engine.new({
        battle_seed = handoff.battle_seed,
        rules_version = handoff.rules_version,
        player = handoff.player,
        opponent = handoff.opponent,
    })
    loop.previous_frame = engine.snapshot(loop.world)
    loop.current_frame = engine.snapshot(loop.world)
    loop.accumulator = 0
    append_events(loop, engine.drain_events(loop.world))
end

local function finish_battle(loop)
    if not loop.world or not engine.result(loop.world) then return false end
    local recording = engine.recording(loop.world)
    local completed, completion_error = controller.complete_battle(loop.model, {
        final_tick = loop.world.tick,
        result = engine.result(loop.world),
        recording = recording,
        checkpoint_hashes = checkpoints.from_recording(recording),
    })
    assert(completed, completion_error and completion_error.message
        or "canonical battle completion was rejected")
    loop.model = completed.model
    append_events(loop, completed.events)
    loop.completed_runs = loop.completed_runs + 1
    loop.world = nil
    loop.accumulator = 0
    return true
end

local function step_once(loop)
    if not loop.world or engine.result(loop.world) then return false end
    loop.previous_frame = loop.current_frame
    append_events(loop, engine.step(loop.world, engine.FIXED_DT))
    loop.current_frame = engine.snapshot(loop.world)
    if engine.result(loop.world) then finish_battle(loop) end
    return true
end

function M.new(options)
    return {
        schema_version = M.SCHEMA_VERSION,
        model = controller.new(options),
        world = nil,
        previous_frame = nil,
        current_frame = nil,
        accumulator = 0,
        events = {},
        last_error = nil,
        completed_runs = 0,
    }
end

function M.activate(loop, action_id, source)
    local accepted, action_error = controller.activate(loop.model, action_id, source)
    if not accepted then
        loop.last_error = action_error
        return nil, action_error
    end
    local prior_phase = loop.model.run.phase
    loop.model = accepted.model
    loop.last_error = nil
    append_events(loop, accepted.events)

    if prior_phase ~= "battle" and loop.model.run.phase == "battle" then
        start_battle(loop)
    elseif loop.model.run.phase == "draft"
        or (prior_phase == "draft" and loop.model.run.phase == "setup")
        or (prior_phase == "result" and loop.model.run.phase ~= "battle") then
        clear_battle_runtime(loop)
    end
    return { loop = loop, events = accepted.events }
end

function M.update(loop, dt)
    if loop.model.run.phase ~= "battle" then return 0 end
    if not loop.world then start_battle(loop) end
    if loop.model.ui.paused or engine.result(loop.world) then
        finish_battle(loop)
        return 0
    end

    loop.accumulator = loop.accumulator
        + math.max(0, tonumber(dt) or 0) * (loop.model.ui.speed or 1)
    local steps = 0
    while loop.accumulator >= engine.FIXED_DT
        and steps < M.MAX_STEPS_PER_UPDATE
        and loop.model.run.phase == "battle" do
        loop.accumulator = loop.accumulator - engine.FIXED_DT
        step_once(loop)
        steps = steps + 1
    end
    return steps
end

-- Exact-tick advancement for headless integration tests and keyboard
-- single-step. It invokes the same engine step and completion path as update.
function M.advance(loop, ticks)
    ticks = math.max(0, math.floor(tonumber(ticks) or 1))
    if loop.model.run.phase ~= "battle" then return 0 end
    if not loop.world then start_battle(loop) end
    local advanced = 0
    while advanced < ticks and loop.model.run.phase == "battle" do
        if not step_once(loop) then break end
        advanced = advanced + 1
    end
    return advanced
end

function M.project(loop)
    return controller.project(
        loop.model,
        loop.previous_frame,
        loop.current_frame,
        engine.FIXED_DT > 0 and math.min(1, loop.accumulator / engine.FIXED_DT) or 1
    )
end

function M.drain_events(loop)
    local events = loop.events
    loop.events = {}
    return events
end

return M
