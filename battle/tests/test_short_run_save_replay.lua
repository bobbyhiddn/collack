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
local fixtures = require("battle.tests.short_run_fixtures")
local run = require("battle.run")
local util = require("battle.run_util")

local M = { name = "short_run_save_replay" }

local function win_run(seed)
    local state = run.new({ run_seed = seed, short_run = true, player_name = "Archivist" })
    state = fixtures.complete(state)
    state = fixtures.choose(state, 1)
    state = fixtures.complete(state)
    state = fixtures.choose(state, 1)
    state = fixtures.complete(state)
    return state
end

function M.run(t)
    local state = run.new({ run_seed = 9300, short_run = true })
    state = fixtures.place_unplaced(state)
    local save, save_error = run.save(state)
    t:ok(save ~= nil, save_error and save_error.message or "setup boundary saves")
    t:eq(save.kind, "callack_short_run_save", "save carries stable kind")
    t:eq(save.schema_version, 1, "save is schema-versioned")
    local loaded, load_error = run.load(save)
    t:ok(loaded ~= nil, load_error and load_error.message or "same-build save loads")
    t:ok(util.deep_equal(loaded, state), "save/load preserves complete persistent run state")
    loaded.player.name = "mutated"
    t:eq(save.state.player.name, "Collector", "loaded state owns an independent value copy")

    local battle = fixtures.to_battle(state)
    local battle_save, battle_error = run.save(battle)
    t:eq(battle_save, nil, "mutable engine boundary cannot be saved as a plain RunState")
    t:eq(battle_error.code, "battle_save_unsupported",
        "battle save rejection names the supported boundaries")

    local mismatched = util.deep_copy(save)
    mismatched.content_version = "future-content"
    local bad_load, bad_load_error = run.load(mismatched)
    t:eq(bad_load, nil, "different content build cannot load a save")
    t:eq(bad_load_error.code, "save_version_mismatch",
        "save mismatch has a structured error")

    local terminal = win_run(9301)
    t:eq(terminal.phase, "result", "fixture reaches terminal three-fight result")
    t:eq(terminal.result.outcome, "victory", "fixture records a terminal win")
    local record, record_error = run.record(terminal)
    t:ok(record ~= nil, record_error and record_error.message or "terminal run records")
    t:eq(#record.fights, 3, "record stores all three immutable battle recordings")
    t:eq(#record.final_state.workshop.reward_history, 2,
        "record stores both persistent economy choices")
    for index, fight in ipairs(record.fights) do
        t:ok(#fight.recording.frames > 0, "fight " .. index .. " stores replay frames")
        t:ok(#fight.checkpoint_hashes > 0,
            "fight " .. index .. " stores deterministic checkpoint hashes")
        t:ok(#fight.causal_ledger > 0,
            "fight " .. index .. " stores generated causal attribution")
    end

    local replayed, replay_error = run.replay(record)
    t:ok(replayed ~= nil, replay_error and replay_error.message
        or "three-fight same-build replay succeeds")
    if replayed then
        t:ok(util.deep_equal(replayed.result, terminal.result),
            "replay restores terminal win/loss result")
        t:ok(util.deep_equal(replayed.player, terminal.player),
            "replay restores persistent roster and sling")
        t:ok(util.deep_equal(replayed.setup, terminal.setup),
            "replay restores final formation and ordered bag")
        t:ok(util.deep_equal(replayed.workshop, terminal.workshop),
            "replay restores attrition and economy history")
        t:eq(#replayed.fight.history, 3, "replay reconstructs every fight boundary")
    end

    local tampered = util.deep_copy(record)
    for _, entry in ipairs(tampered.journal) do
        if entry.kind == "command" and entry.command.kind == "choose_offer" then
            entry.command.choice_id = "refit:tampered"
            break
        end
    end
    local bad_replay, bad_replay_error = run.replay(tampered)
    t:eq(bad_replay, nil, "tampered reward journal cannot replay")
    t:eq(bad_replay_error.code, "journal_command_failed",
        "tampered replay fails at exact semantic command")

    local resume = run.new({ run_seed = 9302, short_run = true })
    resume = fixtures.complete(resume)
    resume = fixtures.choose(resume, 1)
    local boundary = assert(run.save(resume))
    local resumed = assert(run.load(boundary))
    local original = fixtures.complete(resume)
    original = fixtures.choose(original, 1)
    original = fixtures.complete(original)
    resumed = fixtures.complete(resumed)
    resumed = fixtures.choose(resumed, 1)
    resumed = fixtures.complete(resumed)
    t:ok(util.deep_equal(original.result, resumed.result),
        "loaded boundary preserves deterministic terminal outcome")
    t:ok(util.deep_equal(original.fight.history, resumed.fight.history),
        "loaded boundary preserves deterministic recordings and attribution")
    t:ok(util.deep_equal(original.workshop, resumed.workshop),
        "loaded boundary preserves economy and attrition")
end

if arg and arg[0] and arg[0]:find("test_short_run_save_replay.lua", 1, true) then
    harness.run_one(M)
end

return M
