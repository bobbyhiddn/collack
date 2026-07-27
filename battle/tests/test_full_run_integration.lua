local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../../src/?.lua",
    here .. "/../?.lua",
    "./?.lua",
    "./src/?.lua",
    package.path,
}, ";")

local engine = require("battle.engine")
local harness = require("battle.tests.harness")
local loop = require("run_loop")
local util = require("battle.run_util")

local M = { name = "full_run_integration" }

local function activate(app, action_id, source)
    local accepted, action_error = loop.activate(app, action_id, source or "touch")
    assert(accepted, action_error and action_error.message or ("action failed: " .. action_id))
end

local function reach_setup(app)
    local choices = 0
    while app.model.run.phase == "draft" do
        local card = app.model.run.draft.offer.choices[1]
        activate(app, "offer:" .. card.choice_id)
        activate(app, "select:" .. card.choice_id)
        activate(app, "confirm_offer")
        choices = choices + 1
    end
    return choices
end

local function reach_battle(app)
    local choices = reach_setup(app)
    for index, brick in ipairs(app.model.run.player.bricks) do
        activate(app, "brick:" .. brick.uid)
        activate(app, string.format(
            "cell:%d:%d",
            math.floor((index - 1) / 7) + 1,
            ((index - 1) % 7) + 1
        ))
    end
    activate(app, "lock_setup")
    return choices
end

local function finish_with_partitions(app, partitions)
    local updates = 0
    while app.model.run.phase == "battle" and updates < 100000 do
        loop.update(app, partitions[(updates % #partitions) + 1])
        updates = updates + 1
    end
    assert(app.model.run.phase == "result", "canonical battle did not finish")
    return updates
end

function M.run(t)
    local first = loop.new({ run_seed = 9125, player_name = "Collector" })
    t:eq(loop.project(first).screen, "draft", "integrated loop starts on the draft surface")
    t:eq(reach_setup(first), 9, "nine semantic touch choices reach setup")
    t:eq(first.model.run.phase, "setup", "draft transitions into setup")

    local original_head = first.model.run.setup.bag_order[1]
    local original_tail = first.model.run.setup.bag_order[4]
    activate(first, "marble:" .. original_tail)
    activate(first, "slot:" .. original_head)
    t:eq(first.model.run.setup.bag_order[1], original_tail,
        "setup interaction changes canonical launch order")
    activate(first, "marble:" .. original_tail)
    activate(first, "slot:tail")
    t:eq(first.model.run.setup.bag_order[1], original_head,
        "bag can be restored through the same semantic controls")

    for index, brick in ipairs(first.model.run.player.bricks) do
        activate(first, "brick:" .. brick.uid)
        activate(first, string.format(
            "cell:%d:%d",
            math.floor((index - 1) / 7) + 1,
            ((index - 1) % 7) + 1
        ))
    end
    local chosen_order = util.deep_copy(first.model.run.setup.bag_order)
    activate(first, "lock_setup")
    t:eq(first.model.run.phase, "battle", "setup lock starts automatic battle")
    t:ok(first.world ~= nil, "handoff creates the canonical physics world")
    t:eq(first.world.rules_version, engine.RULES_VERSION,
        "run and physics use one continuous rules version")

    local initial = first.current_frame
    t:ok(util.deep_equal(initial.sides.A.queue, chosen_order),
        "physics consumes the chosen ordered bag without regeneration")
    t:eq(initial.sides.A.marbles[1].uid, chosen_order[1],
        "drafted marble UID survives into canonical frames")
    t:eq(initial.sides.A.bricks[1].body_id,
        "brick:" .. tostring(initial.sides.A.bricks[1].uid),
        "drafted brick UID survives into physics identity")
    t:eq(loop.project(first).battle.frame.tick, 0,
        "battle presentation consumes the initial canonical frame")

    finish_with_partitions(first, { 1 / 30 })
    t:eq(first.model.run.phase, "result", "automatic engine callback reaches result")
    t:ok(first.model.run.result.winner == "player"
        or first.model.run.result.winner == "opponent"
        or first.model.run.result.winner == nil,
        "product result uses player/opponent ownership")
    t:ok(#first.model.run.battle.recording.frames > 1,
        "result retains immutable canonical replay frames")
    t:ok(#first.model.run.battle.checkpoint_hashes > 1,
        "result retains same-build checkpoint hashes")

    local second = loop.new({ run_seed = 9125, player_name = "Collector" })
    reach_battle(second)
    finish_with_partitions(second, { 1 / 240, 1 / 75, 1 / 24, 1 / 120, 1 / 50 })
    t:ok(util.deep_equal(second.model.run.result, first.model.run.result),
        "render-frame partitions cannot change the canonical result")
    t:ok(util.deep_equal(
        second.model.run.battle.checkpoint_hashes,
        first.model.run.battle.checkpoint_hashes
    ), "render-frame partitions cannot change checkpoint hashes")

    local engine_step = engine.step
    engine.step = function() error("recording replay must not step combat") end
    activate(first, "replay_battle")
    local replay = loop.project(first)
    t:eq(replay.screen, "replay", "result opens the replay surface")
    t:eq(replay.replay.frame.tick, 0, "replay starts from stored frame zero")
    t:ok(#replay.replay.frame.entities > 0,
        "canonical recorded frame projects physical entities")
    activate(first, "replay_next")
    t:eq(loop.project(first).replay.frame.tick,
        first.model.run.battle.recording.frames[2].tick,
        "replay advances only through stored frames")
    engine.step = engine_step

    activate(first, "replay_close")
    activate(first, "new_run")
    t:eq(first.model.run.phase, "draft", "new run returns to a fresh draft")
    t:eq(first.model.run.run_seed, 9126, "new run advances the deterministic seed")

    local renderer = assert(io.open("src/main.lua", "r"))
    local renderer_source = renderer:read("*a")
    renderer:close()
    for _, banned in ipairs({
        "resolve_collision",
        "damage_brick",
        "determine_winner",
        "require(\"battle.setup\")",
        "default_matchup",
    }) do
        t:eq(renderer_source:find(banned, 1, true), nil,
            "shipped LÖVE shell has no alternate combat/demo path: " .. banned)
    end
end

if arg and arg[0] and arg[0]:find("test_full_run_integration.lua", 1, true) then
    harness.run_one(M)
end

return M
