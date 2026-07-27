local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local contract = require("battle.vslice_contract")
local run = require("battle.run")
local setup_contract = require("battle.setup")
local setup_rules = require("battle.setup_rules")
local util = require("battle.run_util")
local fixtures = require("battle.tests.run_fixtures")

local M = { name = "run_state" }

local function no_functions(value, seen)
    if type(value) == "function" or type(value) == "userdata" or type(value) == "thread" then
        return false
    end
    if type(value) ~= "table" then return true end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, item in pairs(value) do
        if not no_functions(key, seen) or not no_functions(item, seen) then return false end
    end
    seen[value] = nil
    return true
end

function M.run(t)
    local machine = run.state_machine()
    t:eq(#machine, 4, "controller publishes all four canonical phases")
    t:eq(machine[1].phase, "draft", "state machine begins in draft")
    t:eq(machine[2].phase, "setup", "setup follows draft")
    t:eq(machine[3].phase, "battle", "battle follows setup")
    t:eq(machine[4].phase, "result", "result is terminal for one RunState")
    t:eq(#machine[3].commands, 0, "battle has no canonical player commands")

    local state = run.new({ run_seed = 4567, player_name = "Fen" })
    t:eq(state.schema_version, 1, "RunState carries a schema version")
    t:eq(state.phase, "draft", "new run starts in draft")
    t:eq(state.player.name, "Fen", "new run keeps player identity")
    t:neq(state.domain_seeds.draft, state.domain_seeds.opponent,
        "draft and opponent domains are separate")
    t:neq(state.domain_seeds.draft, state.domain_seeds.battle,
        "draft and battle domains are separate")
    t:ok(no_functions(state), "RunState contains serializable values only")

    local untouched = run.snapshot(state)
    local stale, stale_error = run.dispatch(state, {
        kind = "choose_offer",
        offer_id = "old-offer",
        choice_id = state.draft.offer.choices[1].choice_id,
    })
    t:eq(stale, nil, "stale offer is rejected")
    t:eq(stale_error.code, "offer_stale", "stale offer has a structured code")
    t:eq(stale_error.state_unchanged, true, "invalid command promises unchanged state")
    t:ok(util.deep_equal(state, untouched), "invalid offer command leaves every value unchanged")

    local unknown, unknown_error = run.dispatch(state, {
        kind = "choose_offer",
        offer_id = state.draft.offer.offer_id,
        choice_id = "sling:not-real",
    })
    t:eq(unknown, nil, "unknown card is rejected")
    t:eq(unknown_error.code, "choice_unknown", "unknown card has an actionable code")
    t:eq(#state.journal, 1, "rejected choices are not journaled")

    state = fixtures.draft_all(state)
    t:eq(state.phase, "setup", "complete individual draft reaches setup")
    t:eq(state.setup.valid, false, "empty formation is not lockable")
    t:eq(#state.setup.errors > 0, true, "invalid setup exposes visible reasons")
    t:eq(type(setup_contract.validate(run.loadout(state))), "table",
        "blueprint setup.validate returns ValidationError[] when invalid")

    local skipped, skipped_error = run.dispatch(state, { kind = "lock_setup" })
    t:eq(skipped, nil, "setup cannot lock before placement")
    t:eq(skipped_error.code, "setup_invalid", "premature lock has structured error")

    local brick = state.player.bricks[1]
    local outside, outside_error = run.dispatch(state, {
        kind = "place_brick",
        brick_uid = brick.uid,
        row = 0,
        col = 1,
    })
    t:eq(outside, nil, "out-of-bounds placement is rejected")
    t:eq(outside_error.code, "cell_out_of_bounds", "bounds error identifies the problem")

    local first_place = assert(run.dispatch(state, {
        kind = "place_brick",
        brick_uid = brick.uid,
        row = 1,
        col = 1,
    }))
    state = first_place.state
    t:eq(state.setup.formation[1][1], brick.uid, "brick occupies selected cell")
    local occupied, occupied_error = run.dispatch(state, {
        kind = "place_brick",
        brick_uid = state.player.bricks[2].uid,
        row = 1,
        col = 1,
    })
    t:eq(occupied, nil, "overlapping placement is rejected")
    t:eq(occupied_error.code, "cell_occupied", "overlap error identifies occupied cell")

    local moved = assert(run.dispatch(state, {
        kind = "place_brick",
        brick_uid = brick.uid,
        row = 3,
        col = 7,
    }))
    state = moved.state
    t:eq(state.setup.formation[1][1], ".", "moving clears the previous cell")
    t:eq(state.setup.formation[3][7], brick.uid, "moving fills the new cell")
    t:eq(moved.events[1].type, "brick_moved", "move emits a presentation cue")

    local order_before = util.deep_copy(state.setup.bag_order)
    local tail = state.setup.bag_order[4]
    local head = state.setup.bag_order[1]
    local reordered = assert(run.dispatch(state, {
        kind = "move_bag",
        marble_uid = tail,
        before_uid = head,
    }))
    state = reordered.state
    t:eq(state.setup.bag_order[1], tail, "bag insertion changes launch order explicitly")
    t:eq(#state.setup.bag_order, 4, "bag move preserves all four marbles")
    t:eq(util.deep_equal(order_before, state.setup.bag_order), false,
        "bag ordering is a meaningful setup choice")
    local no_move, no_move_error = run.dispatch(state, {
        kind = "move_bag",
        marble_uid = tail,
        before_uid = tail,
    })
    t:eq(no_move, nil, "no-op bag move is rejected")
    t:eq(no_move_error.code, "bag_order_unchanged", "no-op bag error is explicit")

    -- Start a clean setup for a predictable full placement.
    state = fixtures.draft_all(run.new({ run_seed = 4567, player_name = "Fen" }))
    state = fixtures.place_all(state)
    t:eq(state.setup.valid, true, "eight unique placements and bag permutation validate")
    local setup_ok, setup_errors = setup_rules.validate(run.loadout(state))
    t:ok(setup_ok, setup_errors and setup_errors[1] and setup_errors[1].message or
        "public setup validator accepts loadout")
    t:eq(setup_contract.validate(run.loadout(state)), true,
        "blueprint setup.validate returns true when valid")
    t:eq(#state.setup.adjacencies > 0, true, "setup exposes adjacency previews")
    t:eq(#state.setup.build_tags > 0, true, "setup exposes readable aggregate build tags")

    local locked = assert(run.dispatch(state, { kind = "lock_setup" }))
    local setup_state = state
    state = locked.state
    t:eq(state.phase, "battle", "lock transitions to automatic battle")
    t:eq(state.battle.status, "handoff", "battle begins at the engine handoff boundary")
    t:eq(locked.events[2].type, "battle_handoff", "lock emits an explicit handoff event")
    local handoff = run.battle_handoff(state)
    t:eq(handoff.battle_seed, state.domain_seeds.battle, "handoff uses battle seed domain")
    t:eq(#handoff.player.bricks, 8, "handoff carries eight individual player bricks")
    t:eq(#handoff.player.marbles, 4, "handoff carries ordered player marble roster")
    t:ok(util.deep_equal(handoff.player.bag_order, setup_state.setup.bag_order),
        "handoff preserves chosen bag order")
    t:eq(handoff.opponent.recipe_id, state.opponent.recipe_id,
        "handoff carries the prebuilt opponent")
    handoff.player.name = "mutated"
    t:eq(state.battle.handoff.player.name, "Fen", "handoff accessor returns an owned copy")

    local combat_input, combat_error = run.dispatch(state, {
        kind = "place_brick",
        brick_uid = state.player.bricks[1].uid,
        row = 1,
        col = 1,
    })
    t:eq(combat_input, nil, "battle rejects reflex formation input")
    t:eq(combat_error.code, "command_out_of_phase", "battle rejection is phase-aware")

    local missing_recording, recording_error = run.complete_battle(state, {
        result = { outcome = "victory", reason = "formation_destroyed", exchanges = 1 },
    })
    t:eq(missing_recording, nil, "result without immutable recording is rejected")
    t:eq(recording_error.code, "battle_recording_invalid", "recording requirement is explicit")

    local completed = assert(run.complete_battle(state, fixtures.completion()))
    state = completed.state
    t:eq(state.phase, "result", "engine completion advances to result")
    t:eq(state.result.winner, "player", "result stores canonical winner")
    t:eq(state.result.exchanges, 3, "result stores exchange count")
    t:eq(state.battle.status, "finished", "battle state is terminal")
    t:eq(#state.battle.recording.frames, 3, "immutable visible frames are retained")
    t:eq(completed.events[2].type, "run_result", "completion emits result presentation cue")
    t:ok(no_functions(state), "finished RunState remains serializer-safe")

    local record, record_error = run.record(state)
    t:ok(record ~= nil, record_error and record_error.message or "finished run produces RunRecord")
    t:eq(record.run_seed, state.run_seed, "record stores run seed")
    t:ok(util.deep_equal(record.domain_seeds, state.domain_seeds),
        "record stores all domain-separated seeds")
    t:ok(util.deep_equal(record.player, state.player), "record stores immutable player match spec")
    t:ok(util.deep_equal(record.opponent, state.opponent), "record stores immutable CPU match spec")
    t:eq(#record.battle_recording.frames, 3, "record stores battle playback data")
    t:eq(#record.checkpoint_hashes, 4, "record stores same-build checkpoint hashes")

    local replayed, replay_error = run.replay(record)
    t:ok(replayed ~= nil, replay_error and replay_error.message or "same-build replay succeeds")
    if replayed then
        t:ok(util.deep_equal(replayed.player, state.player), "replay reconstructs player choices")
        t:ok(util.deep_equal(replayed.setup, state.setup), "replay reconstructs formation and bag")
        t:ok(util.deep_equal(replayed.result, state.result), "replay restores recorded result")
    end

    local tampered = util.deep_copy(record)
    for _, entry in ipairs(tampered.journal) do
        if entry.kind == "command" and entry.command.kind == "choose_offer" then
            entry.command.choice_id = "marble:tampered"
            break
        end
    end
    local bad_replay, bad_replay_error = run.replay(tampered)
    t:eq(bad_replay, nil, "tampered journal cannot replay")
    t:eq(bad_replay_error.code, "journal_command_failed", "replay mismatch is explicit")

    local prior = run.snapshot(state)
    local next_run = assert(run.dispatch(state, { kind = "new_run" }))
    t:eq(next_run.state.phase, "draft", "New Run constructs a fresh draft")
    t:eq(next_run.state.run_seed, state.run_seed + 1, "New Run advances seed deterministically")
    t:neq(next_run.state.run_id, state.run_id, "New Run owns a new identity")
    t:ok(util.deep_equal(state, prior), "New Run does not rewind or mutate the result state")
    t:eq(next_run.events[1].previous_run_id, state.run_id, "new-run event links run identities")

    local loop_seed = 7000
    for index = 1, 3 do
        local full = fixtures.complete(run.new({ run_seed = loop_seed + index }))
        t:eq(full.phase, "result", "complete headless loop " .. index .. " reaches result")
        local following = assert(run.dispatch(full, { kind = "new_run" }))
        t:eq(following.state.phase, "draft", "complete loop " .. index .. " starts another run")
    end
end

if arg and arg[0] and arg[0]:find("test_run_state.lua", 1, true) then
    harness.run_one(M)
end

return M
