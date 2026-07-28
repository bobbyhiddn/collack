local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../../src/?.lua",
    here .. "/../?.lua",
    "./?.lua",
    "./src/?.lua",
    package.path,
}, ";")

local catalog = require("battle.content.draft")
local harness = require("battle.tests.harness")
local fixtures = require("battle.tests.short_run_fixtures")
local rule_ast = require("battle.rule_ast")
local run = require("battle.run")
local short_run = require("battle.short_run")
local util = require("battle.run_util")

local M = { name = "short_run_state" }

local function no_functions(value, seen)
    local kind = type(value)
    if kind == "function" or kind == "userdata" or kind == "thread" then return false end
    if kind ~= "table" then return true end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, item in pairs(value) do
        if not no_functions(key, seen) or not no_functions(item, seen) then return false end
    end
    seen[value] = nil
    return true
end

local function operation_choice(state, kind)
    for index, choice in ipairs(state.draft.offer.choices) do
        if choice.operation.kind == kind then return index, choice end
    end
    return nil
end

function M.run(t)
    local machine = run.state_machine("short_run")
    t:eq(#machine, 5, "short run publishes setup/battle/refit/repeat/result spine")
    t:eq(machine[1].phase, "setup", "sparse run starts at setup, not a nine-pick draft")
    t:eq(machine[2].phase, "battle", "canonical battle follows setup")
    t:eq(machine[3].label, "refit", "victory opens the one-of-three refit")
    t:eq(machine[5].terminal, true, "result is explicitly terminal")

    local state = run.new({ run_seed = 9125, short_run = true, player_name = "Fen" })
    t:eq(state.mode, short_run.MODE, "new state identifies the three-fight ruleset")
    t:eq(state.phase, "setup", "new state starts on visible setup")
    t:eq(state.player.name, "Fen", "player identity survives sparse construction")
    t:eq(state.player.sling.content_id, "momentum", "approved starting sling is canonical Momentum")
    t:eq(#state.player.marbles, 2, "sparse start has exactly two marbles")
    t:eq(#state.player.bricks, 3, "sparse start has exactly three bricks")
    t:eq(state.limits.marbles, 4, "marble roster cap is four")
    t:eq(state.limits.bricks, 6, "brick roster cap is six")
    t:eq(state.fight.total, 3, "run contains exactly three fights")
    t:eq(#state.fight.route, 3, "all three encounter nodes are visible")
    t:eq(state.fight.route[1].brick_count, 2, "opening scout is deliberately small")
    t:eq(state.fight.route[2].brick_count, 4, "middle encounter grows in formation depth")
    t:eq(state.fight.route[3].brick_count, 5, "terminal encounter is the largest formation")
    t:eq(state.fight.route[1].marble_count, 2, "opening opponent has two marbles")
    t:eq(state.fight.route[2].marble_count, 3, "middle opponent has three marbles")
    t:eq(state.fight.route[3].marble_count, 4, "terminal opponent has four marbles")
    t:ok(no_functions(state), "persistent short-run state is serializer-safe")
    t:eq(state.setup.valid, false, "unplaced sparse bricks keep setup unlocked")

    local pool = short_run.pool_membership()
    t:eq(catalog.COMPREHENSION_POOL_SIZE, 17, "grammar pool remains exactly 17 items")
    t:ok(pool.sling[state.player.sling.content_id], "starting sling belongs to grammar pool")
    for _, marble in ipairs(state.player.marbles) do
        t:ok(pool.marble[marble.content_id], "starting marble belongs to grammar pool")
    end
    for _, brick in ipairs(state.player.bricks) do
        t:ok(pool.brick_kit[brick.kit_id], "starting brick retains grammar-pool kit provenance")
    end
    for _, encounter in ipairs(short_run.encounters()) do
        t:ok(pool.sling[encounter.sling_id], encounter.id .. " uses a pool sling")
        for _, marble_id in ipairs(encounter.marbles) do
            t:ok(pool.marble[marble_id], encounter.id .. " uses only pool marbles")
        end
        for _, brick in ipairs(encounter.bricks) do
            t:ok(pool.brick_kit[brick[1]], encounter.id .. " uses only pool brick kits")
        end
    end

    state = fixtures.place_unplaced(state)
    t:eq(state.setup.valid, true, "placing all three bricks validates sparse setup")
    local tail, head = state.setup.bag_order[2], state.setup.bag_order[1]
    local reordered = assert(run.dispatch(state, {
        kind = "move_bag",
        marble_uid = tail,
        before_uid = head,
    }))
    state = reordered.state
    t:eq(state.setup.bag_order[1], tail, "two-marble bag remains explicitly ordered")

    state = assert(run.dispatch(state, { kind = "lock_setup" })).state
    t:eq(state.phase, "battle", "setup lock reaches canonical autobattle")
    t:eq(state.battle.handoff.fight_index, 1, "handoff identifies the current fight")
    t:eq(#state.battle.handoff.player.marbles, 2, "handoff consumes sparse ordered bag")
    t:eq(#state.battle.handoff.player.bricks, 3, "handoff consumes sparse formation")
    t:eq(#state.battle.handoff.opponent.pool_items > 0, true,
        "scouted opponent exposes approved pool provenance")

    local casualty_uid = state.player.bricks[2].uid
    state = fixtures.complete(state, { destroyed_uids = { casualty_uid } })
    t:eq(state.phase, "draft", "first victory opens refit instead of ending the run")
    t:eq(state.fight.victories, 1, "victory count persists")
    t:eq(#state.fight.history, 1, "first battle recording persists in run history")
    t:eq(#state.player.bricks, 2, "destroyed brick leaves the active formation")
    t:eq(#state.workshop.broken_bricks, 1, "casualty remains available to repair")
    t:eq(state.workshop.broken_bricks[1].brick.uid, casualty_uid,
        "repair record preserves exact brick identity")
    t:eq(#state.draft.offer.choices, 3, "post-battle refit is exactly one of three")
    t:eq(state.draft.offer.next_encounter.index, 2, "reward surface scouts the next fight")
    t:eq(#state.fight.history[1].causal_ledger, 1,
        "attributed battle trigger persists in the causal ledger")
    t:ok(state.fight.history[1].causal_ledger[1].generated_callout ~= "",
        "combat attribution exposes canonical generated language")

    for _, choice in ipairs(state.draft.offer.choices) do
        t:eq(choice.compact_copy, rule_ast.compact(choice.rule_set),
            "reward card compact copy derives from its canonical rules")
        t:eq(choice.mechanics[1], rule_ast.compact_lines(choice.rule_set)[1],
            "reward card mechanics derive from canonical rules")
        t:ok(choice.operation_copy:find(choice.operation_verb, 1, true) == 1,
            "reward operation language is generated from its typed operation")
        t:eq(choice.causal_attribution.source_rule_set_id, choice.rule_set.id,
            "reward causality names its canonical rule set")
        local authority = rule_ast.player_authority(choice.rule_set)
        t:ok(util.deep_equal(
            choice.causal_attribution.source_rule_ids,
            authority.rule_ids
        ), "reward causality exposes exactly the inspectable executable rules")
        t:eq(#choice.causal_attribution.source_rule_ids,
            #authority.balance.lines,
            "reward attribution and accounting expose the same rule count")
        t:ok(util.deep_equal(choice.inspection_copy, authority.inspection_copy),
            "reward inspection shares the exact causal rule authority")
    end

    state = fixtures.choose(state, 1)
    t:eq(state.phase, "setup", "one explicit reward advances to the next setup")
    t:eq(state.fight.index, 2, "fight index advances only after reward confirmation")
    t:eq(#state.player.marbles, 3, "first recommended choice adds one marble")
    t:eq(#state.player.bricks, 2, "casualty persists across the refit boundary")
    t:eq(#state.workshop.reward_history, 1, "chosen refit persists in run history")
    t:eq(state.opponent.recipe_id, "fuse_garden", "second asymmetric encounter is now active")

    state = fixtures.complete(state)
    t:eq(state.phase, "draft", "second victory opens the final refit")
    local repair_index, repair = operation_choice(state, "repair_brick")
    t:ok(repair ~= nil, "a broken brick creates a meaningful repair choice")
    t:ok(repair.operation_copy:find("REPAIR", 1, true) == 1,
        "repair choice states its exact consequence")
    state = fixtures.choose(state, repair_index)
    t:eq(state.fight.index, 3, "repair selection advances to terminal encounter")
    t:eq(#state.workshop.broken_bricks, 0, "repair consumes the casualty record")
    t:eq(#state.player.bricks, 3, "repair restores the exact active brick")
    t:eq(state.opponent.recipe_id, "brass_bastion", "third encounter is the terminal test")

    state = fixtures.complete(state)
    t:eq(state.phase, "result", "third victory terminates the run")
    t:eq(state.result.outcome, "victory", "terminal outcome is a clear win")
    t:eq(state.result.reason, "three_fights_cleared", "win names the three-fight condition")
    t:eq(state.result.fights_cleared, 3, "terminal result reports all cleared fights")
    t:eq(#state.fight.history, 3, "all three immutable battle records persist")
    t:eq(#state.workshop.reward_history, 2, "both build-changing rewards persist")

    local following = assert(run.dispatch(state, { kind = "new_run" }))
    t:eq(following.state.phase, "setup", "new short run returns to sparse setup")
    t:eq(following.state.run_seed, 9126, "new short run advances seed deterministically")
    t:eq(#following.state.player.marbles, 2, "new run resets to two starting marbles")
    t:eq(#following.state.player.bricks, 3, "new run resets to three starting bricks")

    local loss = run.new({ run_seed = 1200, short_run = true })
    loss = fixtures.to_battle(loss)
    loss = fixtures.complete(loss, {
        outcome = "victory",
        winner = "opponent",
        reason = "bricks_destroyed",
    })
    t:eq(loss.phase, "result", "defeat ends the run immediately")
    t:eq(loss.result.outcome, "defeat", "terminal loss is not mislabeled as victory")
    t:eq(loss.result.reason, "run_ended_at_fight_1", "loss identifies the failed encounter")
    t:eq(loss.result.fights_cleared, 0, "loss preserves cleared-fight count")

    local left = run.new({ run_seed = 4444, short_run = true })
    local right = run.new({ run_seed = 4444, short_run = true })
    left = fixtures.complete(left)
    right = fixtures.complete(right)
    t:ok(util.deep_equal(left.draft.offer, right.draft.offer),
        "same seed and result generate byte-equivalent refit offers")
    t:ok(util.deep_equal(left.fight.route, right.fight.route),
        "same seed reproduces the complete encounter route")
end

if arg and arg[0] and arg[0]:find("test_short_run_state.lua", 1, true) then
    harness.run_one(M)
end

return M
