local run = require("battle.run")
local setup_rules = require("battle.setup_rules")
local util = require("battle.run_util")

local M = {}

local DEFAULT_CELLS = {
    { 1, 2 }, { 1, 4 }, { 1, 6 },
    { 2, 3 }, { 2, 5 }, { 3, 2 },
}

function M.place_unplaced(state)
    local used = {}
    for row = 1, 3 do
        for col = 1, 7 do
            local uid = state.setup.formation[row][col]
            if uid and uid ~= "." then used[row .. ":" .. col] = true end
        end
    end
    for _, brick in ipairs(state.player.bricks) do
        if not setup_rules.find_brick_cell(state.setup.formation, brick.uid) then
            local cell
            for _, candidate in ipairs(DEFAULT_CELLS) do
                local key = candidate[1] .. ":" .. candidate[2]
                if not used[key] then
                    cell = candidate
                    used[key] = true
                    break
                end
            end
            assert(cell, "fixture has no legal formation cell")
            local result, command_error = run.dispatch(state, {
                kind = "place_brick",
                brick_uid = brick.uid,
                row = cell[1],
                col = cell[2],
            })
            assert(result, command_error and command_error.message or "placement failed")
            state = result.state
        end
    end
    return state
end

function M.to_battle(state)
    state = M.place_unplaced(state)
    local result, command_error = run.dispatch(state, { kind = "lock_setup" })
    assert(result, command_error and command_error.message or "lock failed")
    return result.state
end

function M.completion(state, options)
    options = options or {}
    local result = {
        schema_version = 1,
        outcome = options.outcome or "victory",
        winner = options.winner == false and nil or (options.winner or "player"),
        reason = options.reason or "bricks_destroyed",
        exchanges = options.exchanges or 3,
    }
    local destroyed = util.set(options.destroyed_uids or {})
    local final_bricks = {}
    for _, brick in ipairs(state.player.bricks) do
        final_bricks[#final_bricks + 1] = {
            uid = brick.uid,
            name = brick.name,
            hp = destroyed[brick.uid] and 0 or brick.max_hp,
            max_hp = brick.max_hp,
            alive = not destroyed[brick.uid],
        }
    end
    local attributed_event = {
        schema_version = 1,
        seq = 2,
        tick = 12,
        type = "launch",
        side = "A",
        rule_id = state.player.sling.rule_set.rules[1].id,
        rule_source = state.player.sling.name,
        rule_role = state.player.sling.rule_set.role,
        rule_operation = state.player.sling.rule_set.rules[1].operation.verb,
        rule_target = state.player.sling.rule_set.rules[1].target.selector,
        rule_magnitude = state.player.sling.rule_set.rules[1].magnitude.value,
        rule_unit = state.player.sling.rule_set.rules[1].magnitude.unit,
    }
    return {
        final_tick = 120,
        checkpoint_hashes = { "000000:a0", "000120:b1" },
        result = result,
        recording = {
            schema_version = 1,
            sample_every_ticks = 4,
            keyframe_every_ticks = 120,
            final_tick = 120,
            frames = {
                {
                    schema_version = 1,
                    tick = 0,
                    entities = {
                        { id = "player-m01", type = "marble", x = 195, y = 720 },
                    },
                },
                {
                    schema_version = 1,
                    tick = 120,
                    entities = {
                        { id = "player-m01", type = "marble", x = 195, y = 500 },
                    },
                },
            },
            events = {
                { schema_version = 1, seq = 1, tick = 0, type = "battle_start" },
                attributed_event,
                { schema_version = 1, seq = 3, tick = 120, type = "battle_end" },
            },
            keyframes = {
                { schema_version = 1, tick = 0, frame_index = 1 },
                { schema_version = 1, tick = 120, frame_index = 2 },
            },
            result = util.deep_copy(result),
            final = {
                schema_version = 1,
                tick = 120,
                sides = {
                    A = { bricks = final_bricks },
                    B = { bricks = {} },
                },
                result = util.deep_copy(result),
            },
        },
    }
end

function M.complete(state, options)
    state = state.phase == "battle" and state or M.to_battle(state)
    local result, completion_error = run.complete_battle(state, M.completion(state, options))
    assert(result, completion_error and completion_error.message or "completion failed")
    return result.state
end

function M.choose(state, index)
    local offer = assert(state.draft.offer, "refit offer is missing")
    local choice = assert(offer.choices[index or 1], "refit choice is missing")
    local result, command_error = run.dispatch(state, {
        kind = "choose_offer",
        offer_id = offer.offer_id,
        choice_id = choice.choice_id,
    })
    assert(result, command_error and command_error.message or "reward choice failed")
    return result.state, choice
end

return M
