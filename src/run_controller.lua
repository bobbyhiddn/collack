-- LÖVE-independent interaction controller.  Touch, mouse, keyboard, and
-- headless tests all activate the same semantic action IDs; only a renderer
-- decides which screen coordinates map to those IDs.

local run = require("battle.run")
local util = require("battle.run_util")

local M = {}

M.SCHEMA_VERSION = 1
M.DEFAULT_SEED = 9125

local function fresh_ui(settings)
    settings = settings or {}
    return {
        inspected_choice_id = nil,
        selected_choice_id = nil,
        selected_brick_uid = nil,
        selected_marble_uid = nil,
        inspected_entity_id = nil,
        replay = nil,
        paused = false,
        speed = 1,
        muted = settings.muted == true,
        reduced_motion = settings.reduced_motion == true,
        ledger_expanded = false,
        last_error = nil,
    }
end

function M.new(options)
    options = util.deep_copy(options or {})
    if options.run_seed == nil then options.run_seed = M.DEFAULT_SEED end
    return {
        schema_version = M.SCHEMA_VERSION,
        run = run.new(options),
        ui = fresh_ui(options),
    }
end

function M.snapshot(model)
    return util.deep_copy(model)
end

local function view_error(model, action, code, message, details)
    return {
        schema_version = 1,
        error = true,
        code = code,
        message = message,
        action = action and (action.kind or action.type) or nil,
        phase = model and model.run and model.run.phase or nil,
        details = util.deep_copy(details),
        model_unchanged = true,
    }
end

local function accepted(model, events)
    return { model = model, events = events or {} }
end

local function current_choice(model, choice_id)
    for _, choice in ipairs(
        model.run.draft
        and model.run.draft.offer
        and model.run.draft.offer.choices
        or {}
    ) do
        if choice.choice_id == choice_id then return choice end
    end
    return nil
end

local function apply_run_result(model, run_result)
    local next_model = util.deep_copy(model)
    next_model.run = run_result.state
    next_model.ui.last_error = nil
    return accepted(next_model, run_result.events)
end

local function inspect_offer(model, action)
    if model.run.phase ~= "draft" then
        return nil, view_error(model, action, "inspect_out_of_phase", "Offers exist only during draft.")
    end
    if not current_choice(model, action.choice_id) then
        return nil, view_error(model, action, "choice_unknown", "Inspect one of the visible cards.")
    end
    local next_model = util.deep_copy(model)
    next_model.ui.inspected_choice_id = action.choice_id
    next_model.ui.selected_choice_id = nil
    return accepted(next_model, {
        { schema_version = 1, type = "choice_inspected", choice_id = action.choice_id },
    })
end

local function select_offer(model, action)
    if model.run.phase ~= "draft" then
        return nil, view_error(model, action, "select_out_of_phase", "Offers exist only during draft.")
    end
    if model.ui.inspected_choice_id ~= action.choice_id then
        return nil, view_error(
            model,
            action,
            "choice_not_inspected",
            "Inspect the card before selecting it."
        )
    end
    if not current_choice(model, action.choice_id) then
        return nil, view_error(model, action, "choice_unknown", "Select one of the visible cards.")
    end
    local next_model = util.deep_copy(model)
    next_model.ui.selected_choice_id = action.choice_id
    return accepted(next_model, {
        { schema_version = 1, type = "choice_selected", choice_id = action.choice_id },
    })
end

local function confirm_offer(model, action)
    if model.run.phase ~= "draft" then
        return nil, view_error(model, action, "confirm_out_of_phase", "No draft choice can be confirmed.")
    end
    local choice_id = model.ui.selected_choice_id
    if not choice_id then
        return nil, view_error(
            model,
            action,
            "choice_not_selected",
            "Select an inspected card before confirming."
        )
    end
    local offer = model.run.draft.offer
    local result, command_error = run.dispatch(model.run, {
        kind = "choose_offer",
        offer_id = offer.offer_id,
        choice_id = choice_id,
    })
    if not result then return nil, command_error end
    local next_model = util.deep_copy(model)
    next_model.run = result.state
    next_model.ui.inspected_choice_id = nil
    next_model.ui.selected_choice_id = nil
    next_model.ui.last_error = nil
    return accepted(next_model, result.events)
end

local function select_brick(model, action)
    if model.run.phase ~= "setup" then
        return nil, view_error(model, action, "brick_select_out_of_phase", "Bricks move only during setup.")
    end
    local known = false
    for _, brick in ipairs(model.run.player.bricks) do
        if brick.uid == action.brick_uid then known = true break end
    end
    if not known then
        return nil, view_error(model, action, "brick_unknown", "Select one of the drafted bricks.")
    end
    local next_model = util.deep_copy(model)
    next_model.ui.selected_brick_uid = action.brick_uid
    return accepted(next_model, {
        { schema_version = 1, type = "brick_selected", brick_uid = action.brick_uid },
    })
end

local function place_selected(model, action)
    if model.run.phase ~= "setup" then
        return nil, view_error(model, action, "placement_out_of_phase", "Formation is locked.")
    end
    if not model.ui.selected_brick_uid then
        return nil, view_error(model, action, "brick_not_selected", "Select a brick before a cell.")
    end
    local result, command_error = run.dispatch(model.run, {
        kind = "place_brick",
        brick_uid = model.ui.selected_brick_uid,
        row = action.row,
        col = action.col,
    })
    if not result then return nil, command_error end
    return apply_run_result(model, result)
end

local function select_marble(model, action)
    if model.run.phase ~= "setup" then
        return nil, view_error(model, action, "marble_select_out_of_phase", "Bag order is locked.")
    end
    local known = false
    for _, marble in ipairs(model.run.player.marbles) do
        if marble.uid == action.marble_uid then known = true break end
    end
    if not known then
        return nil, view_error(model, action, "marble_unknown", "Select a drafted marble.")
    end
    local next_model = util.deep_copy(model)
    next_model.ui.selected_marble_uid = action.marble_uid
    return accepted(next_model, {
        { schema_version = 1, type = "marble_selected", marble_uid = action.marble_uid },
    })
end

local function insert_selected(model, action)
    if model.run.phase ~= "setup" then
        return nil, view_error(model, action, "bag_move_out_of_phase", "Bag order is locked.")
    end
    if not model.ui.selected_marble_uid then
        return nil, view_error(model, action, "marble_not_selected", "Select a marble before a slot.")
    end
    local result, command_error = run.dispatch(model.run, {
        kind = "move_bag",
        marble_uid = model.ui.selected_marble_uid,
        before_uid = action.before_uid,
    })
    if not result then return nil, command_error end
    local next_model = util.deep_copy(model)
    next_model.run = result.state
    next_model.ui.selected_marble_uid = nil
    next_model.ui.last_error = nil
    return accepted(next_model, result.events)
end

local function lock_setup(model, action)
    if model.run.phase ~= "setup" then
        return nil, view_error(model, action, "lock_out_of_phase", "Setup cannot be locked now.")
    end
    local result, command_error = run.dispatch(model.run, { kind = "lock_setup" })
    if not result then return nil, command_error end
    local next_model = util.deep_copy(model)
    next_model.run = result.state
    next_model.ui.selected_brick_uid = nil
    next_model.ui.selected_marble_uid = nil
    next_model.ui.last_error = nil
    return accepted(next_model, result.events)
end

local function inspect_entity(model, action)
    if model.run.phase ~= "battle" then
        return nil, view_error(model, action, "entity_inspect_out_of_phase", "Battle entities are not active.")
    end
    local next_model = util.deep_copy(model)
    local closing = tostring(next_model.ui.inspected_entity_id) == tostring(action.entity_id)
    if closing then
        next_model.ui.inspected_entity_id = nil
    else
        next_model.ui.inspected_entity_id = action.entity_id
    end
    return accepted(next_model, {
        {
            schema_version = 1,
            type = closing and "entity_inspection_closed" or "entity_inspected",
            entity_id = action.entity_id,
        },
    })
end

local function battle_view_action(model, action)
    if model.run.phase ~= "battle" then
        return nil, view_error(
            model,
            action,
            "battle_view_out_of_phase",
            "Battle view controls are available only during battle."
        )
    end
    local next_model = util.deep_copy(model)
    if action.kind == "toggle_pause" then
        next_model.ui.paused = not next_model.ui.paused
    elseif action.kind == "cycle_speed" then
        next_model.ui.speed = next_model.ui.speed == 2 and 1 or 2
    elseif action.kind == "toggle_mute" then
        next_model.ui.muted = not next_model.ui.muted
    elseif action.kind == "toggle_reduced_motion" then
        next_model.ui.reduced_motion = not next_model.ui.reduced_motion
    end
    return accepted(next_model, {
        {
            schema_version = 1,
            type = "battle_view_changed",
            paused = next_model.ui.paused,
            speed = next_model.ui.speed,
            muted = next_model.ui.muted,
            reduced_motion = next_model.ui.reduced_motion,
        },
    })
end

local function replay_battle(model, action)
    if model.run.phase ~= "result" then
        return nil, view_error(model, action, "replay_out_of_phase", "Finish the battle before replaying it.")
    end
    local recording = model.run.battle and model.run.battle.recording
    if not recording or #(recording.frames or {}) == 0 then
        return nil, view_error(model, action, "recording_missing", "No battle recording is available.")
    end
    local next_model = util.deep_copy(model)
    next_model.ui.replay = {
        cursor = 1,
        frame_count = #recording.frames,
        playing = false,
        source = "recording",
    }
    return accepted(next_model, {
        { schema_version = 1, type = "replay_opened", frame_count = #recording.frames },
    })
end

local function replay_step(model, action)
    if not model.ui.replay then
        return nil, view_error(model, action, "replay_closed", "Open the battle replay first.")
    end
    local next_model = util.deep_copy(model)
    local delta = math.floor(tonumber(action.delta) or 1)
    next_model.ui.replay.cursor = math.max(
        1,
        math.min(next_model.ui.replay.frame_count, next_model.ui.replay.cursor + delta)
    )
    return accepted(next_model, {
        {
            schema_version = 1,
            type = "replay_cursor",
            cursor = next_model.ui.replay.cursor,
        },
    })
end

local function replay_seek(model, action)
    if not model.ui.replay then
        return nil, view_error(model, action, "replay_closed", "Open the battle replay first.")
    end
    local next_model = util.deep_copy(model)
    local cursor = math.floor(tonumber(action.cursor) or 1)
    next_model.ui.replay.cursor =
        math.max(1, math.min(next_model.ui.replay.frame_count, cursor))
    return accepted(next_model, {
        {
            schema_version = 1,
            type = "replay_cursor",
            cursor = next_model.ui.replay.cursor,
        },
    })
end

local function replay_close(model)
    if not model.ui.replay then
        return nil, view_error(model, { kind = "replay_close" }, "replay_closed", "Replay is not open.")
    end
    local next_model = util.deep_copy(model)
    next_model.ui.replay = nil
    return accepted(next_model, {
        { schema_version = 1, type = "replay_closed" },
    })
end

local function new_run(model, action)
    if model.run.phase ~= "result" then
        return nil, view_error(model, action, "new_run_out_of_phase", "Finish this run first.")
    end
    local result, command_error = run.dispatch(model.run, { kind = "new_run" })
    if not result then return nil, command_error end
    local next_model = {
        schema_version = M.SCHEMA_VERSION,
        run = result.state,
        ui = fresh_ui({
            muted = model.ui.muted,
            reduced_motion = model.ui.reduced_motion,
        }),
    }
    return accepted(next_model, result.events)
end

local function review_ledger(model, action)
    if model.run.phase ~= "result" then
        return nil, view_error(
            model,
            action,
            "ledger_out_of_phase",
            "The battle ledger is available after the result."
        )
    end
    local next_model = util.deep_copy(model)
    next_model.ui.ledger_expanded = not next_model.ui.ledger_expanded
    return accepted(next_model, {
        {
            schema_version = 1,
            type = "ledger_toggled",
            expanded = next_model.ui.ledger_expanded,
        },
    })
end

function M.dispatch(model, action)
    if type(model) ~= "table" or type(model.run) ~= "table" then
        return nil, view_error(model, action, "model_invalid", "RunController model is required.")
    end
    local kind = type(action) == "table" and (action.kind or action.type) or nil
    if kind == "inspect_offer" then return inspect_offer(model, action) end
    if kind == "select_offer" then return select_offer(model, action) end
    if kind == "confirm_offer" then return confirm_offer(model, action) end
    if kind == "select_brick" then return select_brick(model, action) end
    if kind == "place_selected" then return place_selected(model, action) end
    if kind == "select_marble" then return select_marble(model, action) end
    if kind == "insert_selected" then return insert_selected(model, action) end
    if kind == "lock_setup" then return lock_setup(model, action) end
    if kind == "inspect_entity" then return inspect_entity(model, action) end
    if kind == "toggle_pause" or kind == "cycle_speed"
        or kind == "toggle_mute" or kind == "toggle_reduced_motion" then
        return battle_view_action(model, action)
    end
    if kind == "replay_battle" then return replay_battle(model, action) end
    if kind == "replay_step" then return replay_step(model, action) end
    if kind == "replay_seek" then return replay_seek(model, action) end
    if kind == "replay_close" then return replay_close(model, action) end
    if kind == "review_ledger" then return review_ledger(model, action) end
    if kind == "new_run" then return new_run(model, action) end
    if kind == "battle_complete" then
        return nil, view_error(
            model,
            action,
            "combat_is_automatic",
            "Battle completion is an engine callback, never a player action."
        )
    end
    return nil, view_error(model, action, "action_unknown", "Unknown presentation action.")
end

-- Engine-only callback used by the integration loop after it consumes the
-- battle_handoff event.  It is intentionally not reachable through activate().
function M.complete_battle(model, completion)
    local result, completion_error = run.complete_battle(model.run, completion)
    if not result then return nil, completion_error end
    local next_model = util.deep_copy(model)
    next_model.run = result.state
    next_model.ui.inspected_entity_id = nil
    next_model.ui.replay = nil
    return accepted(next_model, result.events)
end

local function parse_cell(action_id)
    local row, col = action_id:match("^cell:(%d+):(%d+)$")
    if row then return tonumber(row), tonumber(col) end
    return nil
end

-- Pointer-neutral action activation.  `source` is retained only for telemetry;
-- touch and mouse follow exactly the same branch and produce identical state.
function M.activate(model, action_id, source)
    if type(action_id) ~= "string" then
        return nil, view_error(model, nil, "action_id_invalid", "Action ID must be a string.")
    end
    local row, col = parse_cell(action_id)
    if row then
        return M.dispatch(model, { kind = "place_selected", row = row, col = col, source = source })
    end
    local choice_id = action_id:match("^offer:(.+)$")
    if choice_id then
        return M.dispatch(model, { kind = "inspect_offer", choice_id = choice_id, source = source })
    end
    choice_id = action_id:match("^select:(.+)$")
    if choice_id then
        return M.dispatch(model, { kind = "select_offer", choice_id = choice_id, source = source })
    end
    local brick_uid = action_id:match("^brick:(.+)$")
    if brick_uid then
        return M.dispatch(model, { kind = "select_brick", brick_uid = brick_uid, source = source })
    end
    local marble_uid = action_id:match("^marble:(.+)$")
    if marble_uid then
        return M.dispatch(model, { kind = "select_marble", marble_uid = marble_uid, source = source })
    end
    local before_uid = action_id:match("^slot:(.+)$")
    if before_uid then
        if before_uid == "tail" then before_uid = nil end
        return M.dispatch(model, {
            kind = "insert_selected",
            before_uid = before_uid,
            source = source,
        })
    end
    local entity_id = action_id:match("^entity:(.+)$")
    if entity_id then
        return M.dispatch(model, { kind = "inspect_entity", entity_id = entity_id, source = source })
    end
    local simple = {
        confirm_offer = "confirm_offer",
        lock_setup = "lock_setup",
        replay_battle = "replay_battle",
        replay_next = "replay_step",
        replay_close = "replay_close",
        review_battle = "review_ledger",
        new_run = "new_run",
        battle_pause = "toggle_pause",
        battle_speed = "cycle_speed",
        battle_mute = "toggle_mute",
        battle_motion = "toggle_reduced_motion",
    }
    if simple[action_id] then
        return M.dispatch(model, { kind = simple[action_id], source = source })
    end
    return nil, view_error(
        model,
        { kind = "activate" },
        "action_id_unknown",
        "No enabled action uses that ID.",
        { action_id = action_id }
    )
end

function M.project(model, previous_frame, current_frame, alpha)
    return require("run_presentation").project(
        model.run,
        previous_frame,
        current_frame,
        alpha,
        model.ui
    )
end

return M
