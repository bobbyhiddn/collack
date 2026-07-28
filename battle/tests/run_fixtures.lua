local run = require("battle.run")

local M = {}

function M.draft_all(state, choice_index)
    choice_index = choice_index or 1
    while state.phase == "draft" do
        local offer = state.draft.offer
        local choice = offer.choices[math.min(choice_index, #offer.choices)]
        local result, command_error = run.dispatch(state, {
            kind = "choose_offer",
            offer_id = offer.offer_id,
            choice_id = choice.choice_id,
        })
        assert(result, command_error and command_error.message or "draft command failed")
        state = result.state
    end
    return state
end

function M.place_all(state)
    local standard_index, rear_index = 0, 0
    for _, brick in ipairs(state.player.bricks) do
        local rear_row = brick.rule_set.formation
            and brick.rule_set.formation.rear_row
        local row, col
        if rear_row then
            rear_index = rear_index + 1
            row, col = 3, rear_index
        else
            standard_index = standard_index + 1
            row = math.floor((standard_index - 1) / 7) + 1
            col = ((standard_index - 1) % 7) + 1
        end
        local result, command_error = run.dispatch(state, {
            kind = "place_brick",
            brick_uid = brick.uid,
            row = row,
            col = col,
        })
        assert(result, command_error and command_error.message or "placement failed")
        state = result.state
    end
    return state
end

function M.to_battle(state)
    state = M.draft_all(state)
    state = M.place_all(state)
    local result, command_error = run.dispatch(state, { kind = "lock_setup" })
    assert(result, command_error and command_error.message or "lock failed")
    return result.state, result.events
end

function M.completion(options)
    options = options or {}
    local result = {
        schema_version = 1,
        outcome = options.outcome or "victory",
        winner = options.winner or "player",
        reason = options.reason or "formation_destroyed",
        exchanges = options.exchanges or 3,
    }
    return {
        final_tick = 480,
        checkpoint_hashes = { "000120:a1", "000240:b2", "000360:c3", "000480:d4" },
        recording = {
            schema_version = 1,
            sample_every_ticks = 4,
            keyframe_every_ticks = 120,
            final_tick = 480,
            frames = {
                {
                    schema_version = 1,
                    tick = 0,
                    entities = {
                        { id = "player-m01", kind = "marble", x = 195, y = 720, angle = 0 },
                    },
                },
                {
                    schema_version = 1,
                    tick = 4,
                    entities = {
                        { id = "player-m01", kind = "marble", x = 196, y = 690, angle = 0.1 },
                    },
                },
                {
                    schema_version = 1,
                    tick = 8,
                    entities = {
                        { id = "player-m01", kind = "marble", x = 198, y = 660, angle = 0.2 },
                    },
                },
            },
            events = {
                { schema_version = 1, tick = 0, type = "exchange_started", exchange = 1 },
                { schema_version = 1, tick = 480, type = "battle_finished" },
            },
            keyframes = {
                { schema_version = 1, tick = 0, frame_index = 1 },
                { schema_version = 1, tick = 480, frame_index = 3 },
            },
            result = result,
        },
        result = result,
    }
end

function M.complete(state, options)
    state = M.to_battle(state)
    local result, completion_error = run.complete_battle(state, M.completion(options))
    assert(result, completion_error and completion_error.message or "completion failed")
    return result.state
end

return M
