-- Canonical run controller for draft -> setup -> automatic battle -> result.
--
-- Public command convention:
--   local accepted, err = run.dispatch(state, command)
--   -- accepted = { state = RunState, events = DomainEvent[] }
-- Invalid commands return nil plus a structured error and never mutate state.
-- The battle engine completes through run.complete_battle(), not a player
-- command, which keeps combat automatic and the battle phase input-free.

local contract = require("battle.vslice_contract")
local draft = require("battle.draft")
local opponent = require("battle.opponent")
local setup_rules = require("battle.setup_rules")
local short_run = require("battle.short_run")
local util = require("battle.run_util")

local M = {}

M.SCHEMA_VERSION = 1
M.RULES_VERSION = "continuous-v1"
M.CONTENT_VERSION = draft.CONTENT_VERSION

local function append_journal(state, entry)
    local copy = util.deep_copy(entry)
    copy.seq = #state.journal + 1
    state.journal[#state.journal + 1] = copy
end

local function error_result(state, command, code, message, details)
    return {
        schema_version = 1,
        error = true,
        code = code,
        message = message,
        phase = state and state.phase or nil,
        command = command and (command.kind or command.type) or nil,
        details = util.deep_copy(details),
        state_unchanged = true,
    }
end

local function accepted(state, events)
    return { state = state, events = events or {} }
end

local function refresh_setup_status(state)
    local loadout = {
        sling_id = state.player.sling and state.player.sling.id,
        sling = state.player.sling,
        marbles = state.player.marbles,
        bricks = state.player.bricks,
        formation = state.setup.formation,
        bag_order = state.setup.bag_order,
    }
    local valid, errors = setup_rules.validate(loadout)
    state.setup.valid = valid
    state.setup.errors = errors
    state.setup.build_tags = setup_rules.build_tags(loadout)
    state.setup.adjacencies = setup_rules.adjacency_preview(loadout)
end

local function journal_offer(state)
    append_journal(state, {
        kind = "offer_generated",
        offer = state.draft.offer,
    })
end

local function make_current_offer(state)
    state.draft.offer = draft.make_offer(state)
    if state.draft.offer then
        state.draft.stage = state.draft.offer.category
        state.draft.round = state.draft.offer.round
        journal_offer(state)
    end
end

function M.new(options)
    options = options or {}
    if options.short_run == true or options.mode == short_run.MODE then
        return short_run.new(options)
    end
    local run_seed = util.normalize_seed(options.run_seed, contract.SEED_MODULUS)
    local run_index = math.max(1, math.floor(tonumber(options.run_index) or 1))
    local domain_seeds = {
        draft = contract.derive_seed(run_seed, "draft"),
        opponent = contract.derive_seed(run_seed, "opponent"),
        battle = contract.derive_seed(run_seed, "battle"),
    }
    local state = {
        schema_version = M.SCHEMA_VERSION,
        run_id = string.format("run-%d-%03d", run_seed, run_index),
        run_index = run_index,
        run_seed = run_seed,
        content_version = options.content_version or M.CONTENT_VERSION,
        rules_version = options.rules_version or M.RULES_VERSION,
        phase = contract.PHASE.DRAFT,
        domain_seeds = domain_seeds,
        draft = {
            stage = "sling",
            round = 1,
            offer_index = 1,
            offer = nil,
            picks = {
                sling = nil,
                marbles = {},
                brick_kits = {},
            },
        },
        player = {
            id = "player",
            name = options.player_name or "Collector",
            sling = nil,
            marbles = {},
            bricks = {},
        },
        opponent = opponent.build(domain_seeds.opponent, options.recipe_id),
        setup = {
            formation = setup_rules.empty_formation(),
            bag_order = {},
            valid = false,
            errors = {},
            build_tags = {},
            adjacencies = {},
        },
        battle = nil,
        result = nil,
        journal = {},
    }
    make_current_offer(state)
    refresh_setup_status(state)
    return state
end

function M.snapshot(state)
    return util.deep_copy(state)
end

function M.loadout(state)
    return {
        sling_id = state.player.sling and state.player.sling.id,
        sling = util.deep_copy(state.player.sling),
        marbles = util.deep_copy(state.player.marbles),
        bricks = util.deep_copy(state.player.bricks),
        formation = util.deep_copy(state.setup.formation),
        bag_order = util.deep_copy(state.setup.bag_order),
    }
end

local function command_kind(command)
    if type(command) ~= "table" then return nil end
    return command.kind or command.type
end

local function choice_command(state, command)
    local offer = state.draft.offer
    if command.offer_id ~= offer.offer_id then
        return nil, error_result(
            state,
            command,
            "offer_stale",
            "That offer is no longer active.",
            { expected_offer_id = offer.offer_id }
        )
    end
    local choice = draft.find_choice(offer, command.choice_id)
    if not choice then
        return nil, error_result(
            state,
            command,
            "choice_unknown",
            "Choose one of the three visible cards.",
            { offer_id = offer.offer_id }
        )
    end

    local next_state = util.deep_copy(state)
    local category = next_state.draft.offer.category
    local pick_summary = {
        offer_id = command.offer_id,
        choice_id = command.choice_id,
        content_id = choice.content_id,
        category = category,
    }
    if category == "sling" then
        next_state.player.sling = draft.instantiate_sling(choice)
        next_state.draft.picks.sling = util.deep_copy(pick_summary)
    elseif category == "marble" then
        local index = #next_state.player.marbles + 1
        local marble = draft.instantiate_marble(choice, index, "player")
        next_state.player.marbles[#next_state.player.marbles + 1] = marble
        next_state.setup.bag_order[#next_state.setup.bag_order + 1] = marble.uid
        next_state.draft.picks.marbles[#next_state.draft.picks.marbles + 1] =
            util.deep_copy(pick_summary)
    elseif category == "brick_kit" then
        local first = #next_state.player.bricks + 1
        local kit, instances = draft.instantiate_kit(choice, first, "player")
        pick_summary.tags = util.deep_copy(kit.tags)
        pick_summary.name = kit.name
        next_state.draft.picks.brick_kits[#next_state.draft.picks.brick_kits + 1] =
            util.deep_copy(pick_summary)
        for _, brick in ipairs(instances) do
            next_state.player.bricks[#next_state.player.bricks + 1] = brick
        end
    else
        return nil, error_result(state, command, "draft_complete", "The draft is already complete.")
    end

    append_journal(next_state, {
        kind = "command",
        command = {
            kind = "choose_offer",
            offer_id = command.offer_id,
            choice_id = command.choice_id,
        },
    })

    local events = {
        {
            schema_version = 1,
            type = "offer_chosen",
            offer_id = command.offer_id,
            choice_id = command.choice_id,
            category = category,
            content_id = choice.content_id,
        },
    }
    next_state.draft.offer_index = next_state.draft.offer_index + 1
    local next_stage, next_round = draft.stage_for(next_state.draft.picks)
    if next_stage == "complete" then
        next_state.draft.stage = "complete"
        next_state.draft.round = 1
        next_state.draft.offer = nil
        next_state.phase = contract.PHASE.SETUP
        refresh_setup_status(next_state)
        events[#events + 1] = {
            schema_version = 1,
            type = "phase_changed",
            from = contract.PHASE.DRAFT,
            to = contract.PHASE.SETUP,
        }
    else
        next_state.draft.stage = next_stage
        next_state.draft.round = next_round
        make_current_offer(next_state)
        events[#events + 1] = {
            schema_version = 1,
            type = "offer_generated",
            offer_id = next_state.draft.offer.offer_id,
            category = next_state.draft.offer.category,
            round = next_state.draft.offer.round,
        }
    end
    return accepted(next_state, events)
end

local function setup_loadout(state)
    return {
        sling_id = state.player.sling and state.player.sling.id,
        sling = state.player.sling,
        marbles = state.player.marbles,
        bricks = state.player.bricks,
        formation = state.setup.formation,
        bag_order = state.setup.bag_order,
    }
end

local function place_command(state, command)
    local updated, placement_error, previous = setup_rules.place(
        setup_loadout(state),
        command.brick_uid,
        command.row,
        command.col
    )
    if not updated then
        return nil, error_result(
            state,
            command,
            placement_error.code,
            placement_error.message,
            placement_error
        )
    end
    local next_state = util.deep_copy(state)
    next_state.setup.formation = updated.formation
    refresh_setup_status(next_state)
    append_journal(next_state, {
        kind = "command",
        command = {
            kind = "place_brick",
            brick_uid = command.brick_uid,
            row = command.row,
            col = command.col,
        },
    })
    return accepted(next_state, {
        {
            schema_version = 1,
            type = previous and "brick_moved" or "brick_placed",
            brick_uid = command.brick_uid,
            row = command.row,
            col = command.col,
            previous = util.deep_copy(previous),
        },
    })
end

local function bag_command(state, command)
    local old_index = util.index_of(state.setup.bag_order, command.marble_uid)
    local updated, bag_error = setup_rules.move_bag(
        setup_loadout(state),
        command.marble_uid,
        command.before_uid
    )
    if not updated then
        return nil, error_result(
            state,
            command,
            bag_error.code,
            bag_error.message,
            bag_error
        )
    end
    local next_state = util.deep_copy(state)
    next_state.setup.bag_order = updated.bag_order
    refresh_setup_status(next_state)
    append_journal(next_state, {
        kind = "command",
        command = {
            kind = "move_bag",
            marble_uid = command.marble_uid,
            before_uid = command.before_uid,
        },
    })
    return accepted(next_state, {
        {
            schema_version = 1,
            type = "bag_reordered",
            marble_uid = command.marble_uid,
            from = old_index,
            to = util.index_of(next_state.setup.bag_order, command.marble_uid),
            bag_order = util.deep_copy(next_state.setup.bag_order),
        },
    })
end

local function handoff_payload(state)
    local player = setup_rules.player_spec(setup_loadout(state), state.player.name)
    return {
        schema_version = 1,
        run_id = state.run_id,
        battle_seed = state.domain_seeds.battle,
        rules_version = state.rules_version,
        content_version = state.content_version,
        player = player,
        opponent = util.deep_copy(state.opponent),
    }
end

local function lock_command(state, command)
    local valid, errors = setup_rules.validate(setup_loadout(state))
    if not valid then
        return nil, error_result(
            state,
            command,
            "setup_invalid",
            "Place all eight bricks and keep all four marbles in the ordered bag.",
            errors
        )
    end
    local player = setup_rules.player_spec(setup_loadout(state), state.player.name)
    if opponent.is_mirror(player, state.opponent) then
        return nil, error_result(
            state,
            command,
            "opponent_mirror",
            "The generated opponent must be asymmetric.",
            nil
        )
    end

    local next_state = util.deep_copy(state)
    local handoff = handoff_payload(next_state)
    next_state.phase = contract.PHASE.BATTLE
    next_state.battle = {
        schema_version = 1,
        status = "handoff",
        tick = 0,
        exchange = 0,
        world = nil,
        pending_events = {},
        recording = nil,
        handoff = util.deep_copy(handoff),
    }
    append_journal(next_state, {
        kind = "command",
        command = { kind = "lock_setup" },
    })
    return accepted(next_state, {
        {
            schema_version = 1,
            type = "phase_changed",
            from = contract.PHASE.SETUP,
            to = contract.PHASE.BATTLE,
        },
        {
            schema_version = 1,
            type = "battle_handoff",
            handoff = handoff,
        },
    })
end

local function new_run_command(state)
    local next_state = M.new({
        run_seed = util.next_seed(state.run_seed, contract.SEED_MODULUS),
        run_index = state.run_index + 1,
        content_version = state.content_version,
        rules_version = state.rules_version,
        player_name = state.player.name,
    })
    return accepted(next_state, {
        {
            schema_version = 1,
            type = "new_run",
            previous_run_id = state.run_id,
            run_id = next_state.run_id,
            run_seed = next_state.run_seed,
        },
    })
end

function M.dispatch(state, command)
    if type(state) == "table" and state.mode == short_run.MODE then
        return short_run.dispatch(state, command)
    end
    if type(state) ~= "table" or type(state.phase) ~= "string" then
        return nil, error_result(state, command, "state_invalid", "RunState is required.")
    end
    local kind = command_kind(command)
    if not kind then
        return nil, error_result(state, command, "command_invalid", "Command kind is required.")
    end
    if not contract.command_allowed(state.phase, kind) then
        return nil, error_result(
            state,
            command,
            "command_out_of_phase",
            string.format("%s is not allowed during %s.", tostring(kind), state.phase)
        )
    end
    if kind == "choose_offer" then return choice_command(state, command) end
    if kind == "place_brick" then return place_command(state, command) end
    if kind == "move_bag" then return bag_command(state, command) end
    if kind == "lock_setup" then return lock_command(state, command) end
    if kind == "new_run" then return new_run_command(state) end
    return nil, error_result(state, command, "command_unknown", "Unknown run command.")
end

local function plain_value(value, seen)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then
        return true
    end
    if kind ~= "table" or getmetatable(value) ~= nil then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, item in pairs(value) do
        if not plain_value(key, seen) or not plain_value(item, seen) then return false end
    end
    seen[value] = nil
    return true
end

local function validate_completion(state, completion)
    if state.phase ~= contract.PHASE.BATTLE then
        return nil, error_result(
            state,
            { kind = "battle_complete" },
            "battle_not_active",
            "A battle result is only accepted during the automatic battle phase."
        )
    end
    if type(completion) ~= "table" or type(completion.result) ~= "table" then
        return nil, error_result(
            state,
            { kind = "battle_complete" },
            "battle_result_invalid",
            "The battle engine must provide a result."
        )
    end
    if type(completion.recording) ~= "table"
        or completion.recording.schema_version ~= 1
        or type(completion.recording.frames) ~= "table"
        or type(completion.recording.events) ~= "table"
        or type(completion.recording.keyframes) ~= "table"
        or type(completion.recording.result) ~= "table"
        or #completion.recording.frames == 0
        or #completion.recording.keyframes == 0 then
        return nil, error_result(
            state,
            { kind = "battle_complete" },
            "battle_recording_invalid",
            "The battle engine must provide versioned frames, events, keyframes, and result."
        )
    end
    if not plain_value(completion) then
        return nil, error_result(
            state,
            { kind = "battle_complete" },
            "battle_completion_not_serializable",
            "Battle completion values must be plain serializable data."
        )
    end
    local result = completion.result
    if type(result.outcome) ~= "string" or result.outcome == ""
        or type(result.reason) ~= "string" or result.reason == ""
        or not util.is_integer(result.exchanges or 0)
        or (result.exchanges or 0) < 0 then
        return nil, error_result(
            state,
            { kind = "battle_complete" },
            "battle_result_invalid",
            "Battle result needs outcome, reason, and a non-negative exchange count."
        )
    end
    local recorded_result = completion.recording.result
    if recorded_result.outcome ~= result.outcome
        or recorded_result.winner ~= result.winner
        or recorded_result.reason ~= result.reason
        or recorded_result.exchanges ~= result.exchanges then
        return nil, error_result(
            state,
            { kind = "battle_complete" },
            "battle_recording_mismatch",
            "The recording result must match the canonical battle result."
        )
    end
    return true
end

function M.complete_battle(state, completion)
    if type(state) == "table" and state.mode == short_run.MODE then
        return short_run.complete_battle(state, completion)
    end
    local valid, completion_error = validate_completion(state, completion)
    if not valid then return nil, completion_error end
    local next_state = util.deep_copy(state)
    next_state.battle.status = "finished"
    next_state.battle.tick = completion.final_tick
        or completion.recording.final_tick
        or next_state.battle.tick
    next_state.battle.exchange = completion.result.exchanges
    next_state.battle.world = nil
    next_state.battle.pending_events = {}
    next_state.battle.recording = util.deep_copy(completion.recording)
    next_state.battle.checkpoint_hashes =
        util.deep_copy(completion.checkpoint_hashes or {})
    next_state.result = util.deep_copy(completion.result)
    next_state.result.schema_version = next_state.result.schema_version or 1
    next_state.result.run_id = next_state.run_id
    next_state.phase = contract.PHASE.RESULT
    append_journal(next_state, {
        kind = "battle_completed",
        result = next_state.result,
        checkpoint_hashes = util.deep_copy(completion.checkpoint_hashes or {}),
    })
    return accepted(next_state, {
        {
            schema_version = 1,
            type = "phase_changed",
            from = contract.PHASE.BATTLE,
            to = contract.PHASE.RESULT,
        },
        {
            schema_version = 1,
            type = "run_result",
            result = util.deep_copy(next_state.result),
        },
    })
end

function M.battle_handoff(state)
    if type(state) == "table" and state.mode == short_run.MODE then
        return short_run.battle_handoff(state)
    end
    if not state.battle or not state.battle.handoff then return nil end
    return util.deep_copy(state.battle.handoff)
end

function M.record(state)
    if type(state) == "table" and state.mode == short_run.MODE then
        return short_run.record(state)
    end
    if state.phase ~= contract.PHASE.RESULT or not state.result
        or not state.battle or not state.battle.recording then
        return nil, error_result(
            state,
            { kind = "record" },
            "run_not_finished",
            "A run record is available only after battle resolution."
        )
    end
    return {
        schema_version = 1,
        run_id = state.run_id,
        run_index = state.run_index,
        run_seed = state.run_seed,
        content_version = state.content_version,
        rules_version = state.rules_version,
        domain_seeds = util.deep_copy(state.domain_seeds),
        journal = util.deep_copy(state.journal),
        player = util.deep_copy(state.player),
        opponent = util.deep_copy(state.opponent),
        setup = util.deep_copy(state.setup),
        battle_recording = util.deep_copy(state.battle.recording),
        checkpoint_hashes = util.deep_copy(state.battle.checkpoint_hashes or {}),
        result = util.deep_copy(state.result),
    }
end

local function replay_error(code, message, details)
    return {
        schema_version = 1,
        error = true,
        code = code,
        message = message,
        details = util.deep_copy(details),
    }
end

function M.replay(record)
    if type(record) == "table" and record.mode == short_run.MODE then
        return short_run.replay(record)
    end
    if type(record) ~= "table" or record.schema_version ~= 1 then
        return nil, replay_error("record_invalid", "A version 1 RunRecord is required.")
    end
    local state = M.new({
        run_seed = record.run_seed,
        run_index = record.run_index,
        content_version = record.content_version,
        rules_version = record.rules_version,
        player_name = record.player and record.player.name,
    })
    for _, entry in ipairs(record.journal or {}) do
        if entry.kind == "command" then
            local result, command_error = M.dispatch(state, entry.command)
            if not result then
                return nil, replay_error(
                    "journal_command_failed",
                    "A recorded command is no longer legal.",
                    command_error
                )
            end
            state = result.state
        end
    end
    if state.phase ~= contract.PHASE.BATTLE then
        return nil, replay_error(
            "journal_incomplete",
            "The journal does not reach the battle handoff."
        )
    end
    local completed, completion_error = M.complete_battle(state, {
        result = record.result,
        recording = record.battle_recording,
        checkpoint_hashes = record.checkpoint_hashes or {},
    })
    if not completed then
        return nil, replay_error(
            "recording_rejected",
            "The recorded battle could not be restored.",
            completion_error
        )
    end
    state = completed.state
    if not util.deep_equal(state.player, record.player)
        or not util.deep_equal(state.opponent, record.opponent)
        or not util.deep_equal(state.setup, record.setup)
        or not util.deep_equal(state.result, record.result) then
        return nil, replay_error(
            "replay_mismatch",
            "Same-build replay did not reconstruct the recorded run."
        )
    end
    return state
end

function M.state_machine(mode)
    if mode == short_run.MODE or mode == "short_run" then
        return short_run.state_machine()
    end
    return {
        { phase = "draft", command = "choose_offer", next = "setup", count = 9 },
        {
            phase = "setup",
            commands = { "place_brick", "move_bag", "lock_setup" },
            next = "battle",
        },
        { phase = "battle", commands = {}, completion = "engine", next = "result" },
        { phase = "result", command = "new_run", next = "new RunState(draft)" },
    }
end

function M.save(state)
    if type(state) == "table" and state.mode == short_run.MODE then
        return short_run.save(state)
    end
    return nil, {
        schema_version = 1,
        error = true,
        code = "save_mode_unsupported",
        message = "Boundary saves are implemented for the three-fight run.",
    }
end

function M.load(save)
    if type(save) == "table"
        and type(save.state) == "table"
        and save.state.mode == short_run.MODE then
        return short_run.load(save)
    end
    return nil, {
        schema_version = 1,
        error = true,
        code = "save_invalid",
        message = "A versioned three-fight run save is required.",
    }
end

return M
