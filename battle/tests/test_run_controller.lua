local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../../src/?.lua",
    here .. "/../?.lua",
    "./?.lua",
    "./src/?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local controller = require("run_controller")
local util = require("battle.run_util")
local fixtures = require("battle.tests.run_fixtures")

local M = { name = "run_controller" }

local function activate(model, id, source)
    local result, action_error = controller.activate(model, id, source)
    assert(result, action_error and action_error.message or ("action failed: " .. id))
    return result.model
end

local function draft_with_actions(model)
    local pointer = 0
    while model.run.phase == "draft" do
        pointer = pointer + 1
        local choice = model.run.draft.offer.choices[((pointer - 1) % 3) + 1]
        local source = pointer % 2 == 0 and "mouse" or "touch"
        model = activate(model, "offer:" .. choice.choice_id, source)
        model = activate(model, "select:" .. choice.choice_id, source)
        model = activate(model, "confirm_offer", source)
    end
    return model
end

function M.run(t)
    local model = controller.new({ run_seed = 9125 })
    t:eq(model.run.phase, "draft", "controller starts at first draft screen")
    t:eq(model.ui.speed, 1, "battle view defaults to 1x")
    t:eq(model.ui.muted, false, "sound starts unmuted")

    local choice = model.run.draft.offer.choices[1]
    local before = controller.snapshot(model)
    local premature, premature_error = controller.activate(
        model,
        "select:" .. choice.choice_id,
        "touch"
    )
    t:eq(premature, nil, "card cannot be selected before inspection")
    t:eq(premature_error.code, "choice_not_inspected", "inspection requirement is explicit")
    t:ok(util.deep_equal(model, before), "illegal view action leaves controller model unchanged")

    local touch = assert(controller.activate(model, "offer:" .. choice.choice_id, "touch"))
    local mouse = assert(controller.activate(model, "offer:" .. choice.choice_id, "mouse"))
    t:ok(util.deep_equal(touch.model, mouse.model),
        "touch and mouse inspection produce identical state")
    t:ok(util.deep_equal(touch.events, mouse.events),
        "touch and mouse inspection produce identical events")
    t:ok(util.deep_equal(touch.model.run, model.run),
        "inspection is a view command and cannot change RunState")

    local inspected = touch.model
    local selected = assert(controller.activate(
        inspected,
        "select:" .. choice.choice_id,
        "touch"
    )).model
    t:ok(util.deep_equal(selected.run, inspected.run),
        "selection remains view-only until explicit confirmation")
    t:eq(selected.ui.selected_choice_id, choice.choice_id,
        "selected choice is visible before confirmation")
    local confirmed = assert(controller.activate(selected, "confirm_offer", "touch"))
    model = confirmed.model
    t:eq(model.run.draft.offer_index, 2, "confirm dispatches the canonical offer choice")
    t:eq(model.ui.inspected_choice_id, nil, "next offer closes the inspect sheet")
    t:eq(model.ui.selected_choice_id, nil, "next offer clears pending selection")

    model = draft_with_actions(model)
    t:eq(model.run.phase, "setup", "touch-equivalent choice loop completes all nine offers")
    t:eq(#model.run.player.marbles, 4, "controller carries four selected marbles")
    t:eq(#model.run.player.bricks, 8, "controller carries eight selected bricks")

    local lock_early, lock_early_error = controller.activate(model, "lock_setup", "touch")
    t:eq(lock_early, nil, "persistent lock action refuses an incomplete formation")
    t:eq(lock_early_error.code, "setup_invalid", "early lock returns setup validation reasons")

    local first_brick = model.run.player.bricks[1].uid
    local selected_touch = assert(controller.activate(model, "brick:" .. first_brick, "touch"))
    local selected_mouse = assert(controller.activate(model, "brick:" .. first_brick, "mouse"))
    t:ok(util.deep_equal(selected_touch.model, selected_mouse.model),
        "touch and mouse brick selection are equivalent")
    local cell_touch = assert(controller.activate(selected_touch.model, "cell:1:1", "touch"))
    local cell_mouse = assert(controller.activate(selected_mouse.model, "cell:1:1", "mouse"))
    t:ok(util.deep_equal(cell_touch.model, cell_mouse.model),
        "touch and mouse placement are equivalent")
    model = cell_touch.model

    for index = 2, #model.run.player.bricks do
        local brick = model.run.player.bricks[index]
        local row = math.floor((index - 1) / 7) + 1
        local col = ((index - 1) % 7) + 1
        model = activate(model, "brick:" .. brick.uid, "touch")
        model = activate(model, string.format("cell:%d:%d", row, col), "touch")
    end
    t:eq(model.run.setup.valid, true, "tap-to-select then tap-cell places a valid formation")

    local tail = model.run.setup.bag_order[4]
    local head = model.run.setup.bag_order[1]
    model = activate(model, "marble:" .. tail, "touch")
    model = activate(model, "slot:" .. head, "touch")
    t:eq(model.run.setup.bag_order[1], tail, "tap marble then insertion slot reorders bag")
    t:eq(model.ui.selected_marble_uid, nil, "successful bag move clears selection")

    local locked = assert(controller.activate(model, "lock_setup", "touch"))
    model = locked.model
    t:eq(model.run.phase, "battle", "lock action reaches automatic battle handoff")
    t:eq(locked.events[2].type, "battle_handoff", "controller forwards handoff payload")

    local run_before_view = util.deep_copy(model.run)
    model = activate(model, "battle_pause", "touch")
    t:eq(model.ui.paused, true, "pause is a battle view control")
    model = activate(model, "battle_speed", "touch")
    t:eq(model.ui.speed, 2, "speed cycles to 2x")
    model = activate(model, "battle_mute", "mouse")
    t:eq(model.ui.muted, true, "mute works through pointer-neutral action")
    model = activate(model, "battle_motion", "touch")
    t:eq(model.ui.reduced_motion, true, "reduced motion is a view setting")
    t:ok(util.deep_equal(model.run, run_before_view),
        "battle view controls cannot change canonical run or combat state")

    local fake_player_completion, fake_error = controller.dispatch(model, {
        kind = "battle_complete",
    })
    t:eq(fake_player_completion, nil, "player cannot press a resolve-battle action")
    t:eq(fake_error.code, "combat_is_automatic", "automatic-combat boundary is explicit")

    local finished = assert(controller.complete_battle(model, fixtures.completion()))
    model = finished.model
    t:eq(model.run.phase, "result", "engine callback reaches result")
    t:eq(model.run.result.winner, "player", "controller shows canonical engine winner")

    local result_before_replay = util.deep_copy(model.run)
    local loaded_engine = package.loaded["battle.engine"]
    package.loaded["battle.engine"] = {
        step = function() error("replay must not step combat") end,
    }
    model = activate(model, "replay_battle", "touch")
    t:eq(model.ui.replay.source, "recording", "replay explicitly consumes immutable recording")
    t:eq(model.ui.replay.cursor, 1, "replay begins at first recorded frame")
    model = activate(model, "replay_next", "touch")
    package.loaded["battle.engine"] = loaded_engine
    t:eq(model.ui.replay.cursor, 2, "replay advances through recorded frames")
    t:ok(util.deep_equal(model.run, result_before_replay),
        "replay navigation cannot mutate result or rerun combat")
    local seek = assert(controller.dispatch(model, { kind = "replay_seek", cursor = 999 }))
    model = seek.model
    t:eq(model.ui.replay.cursor, 3, "replay seek clamps to available recording")
    model = activate(model, "replay_close", "mouse")
    t:eq(model.ui.replay, nil, "replay returns to immutable result")

    local next_touch = assert(controller.activate(model, "new_run", "touch"))
    local next_mouse = assert(controller.activate(model, "new_run", "mouse"))
    t:ok(util.deep_equal(next_touch.model, next_mouse.model),
        "touch and mouse New Run actions are equivalent")
    model = next_touch.model
    t:eq(model.run.phase, "draft", "New Run returns to first offer in a new state")
    t:eq(model.run.run_seed, 9126, "New Run advances the deterministic seed")

    local replay_wrong_phase, replay_wrong_error =
        controller.activate(model, "replay_battle", "touch")
    t:eq(replay_wrong_phase, nil, "replay is illegal during a new draft")
    t:eq(replay_wrong_error.code, "replay_out_of_phase", "illegal replay reports its phase")
    local unknown, unknown_error = controller.activate(model, "does-not-exist", "touch")
    t:eq(unknown, nil, "unknown semantic action is rejected")
    t:eq(unknown_error.code, "action_id_unknown", "unknown action ID has structured error")
end

if arg and arg[0] and arg[0]:find("test_run_controller.lua", 1, true) then
    harness.run_one(M)
end

return M
