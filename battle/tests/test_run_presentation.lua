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
local presentation = require("run_presentation")
local legacy_boundary = require("presentation")
local util = require("battle.run_util")
local fixtures = require("battle.tests.run_fixtures")

local M = { name = "run_presentation" }

local function serializable(value, seen)
    local kind = type(value)
    if kind == "function" or kind == "userdata" or kind == "thread" then return false end
    if kind ~= "table" then return true end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, item in pairs(value) do
        if not serializable(key, seen) or not serializable(item, seen) then return false end
    end
    seen[value] = nil
    return true
end

local function action_by_id(projected, id)
    for _, item in ipairs(projected.actions) do
        if item.id == id then return item end
    end
    return nil
end

local function activate(model, id)
    local result, action_error = controller.activate(model, id, "touch")
    assert(result, action_error and action_error.message or ("action failed: " .. id))
    return result.model
end

local function complete_draft(model)
    while model.run.phase == "draft" do
        local choice = model.run.draft.offer.choices[1]
        model = activate(model, "offer:" .. choice.choice_id)
        model = activate(model, "select:" .. choice.choice_id)
        model = activate(model, "confirm_offer")
    end
    return model
end

function M.run(t)
    local model = controller.new({ run_seed = 77 })
    local projected = controller.project(model)
    t:eq(projected.schema_version, 1, "PresentationState carries schema version")
    t:eq(projected.screen, "draft", "new run projects draft surface")
    t:eq(projected.logical_size.width, 390, "projection targets phone width")
    t:eq(projected.logical_size.height, 844, "projection targets phone height")
    t:eq(projected.minimum_target, 44, "projection pins 44-pixel touch minimum")
    t:eq(projected.art_direction, "warm_handcrafted_tabletop",
        "all screens carry the accepted tabletop direction")
    t:eq(#projected.draft.cards, 3, "draft projects three individual cards")
    t:eq(#projected.opponent.scout_tags, 2, "first screen projects honest CPU scouting")
    t:eq(projected.draft.progress.required, 9, "draft progress exposes nine decisions")
    t:ok(serializable(projected), "draft projection is serializer-safe")

    for _, card in ipairs(projected.draft.cards) do
        t:eq(type(card.name), "string", card.choice_id .. " has a readable name")
        t:eq(type(card.role), "string", card.choice_id .. " has a physical role")
        t:eq(#card.mechanics > 0, true, card.choice_id .. " has mechanics copy")
        t:eq(#card.tags > 0, true, card.choice_id .. " has readable synergy metadata")
        t:eq(type(card.art_id), "string", card.choice_id .. " has an art lookup ID")
        t:ok(action_by_id(projected, card.action_id) ~= nil,
            card.choice_id .. " has an inspect action")
    end
    for _, item in ipairs(projected.actions) do
        t:ok(item.bounds.width >= 44, item.id .. " target is at least 44 pixels wide")
        t:ok(item.bounds.height >= 44, item.id .. " target is at least 44 pixels high")
        t:eq(projected.enabled_actions[item.id], item.enabled,
            item.id .. " enabled state is indexed for input adapters")
    end
    t:eq(action_by_id(projected, "confirm_offer").enabled, false,
        "confirm is visibly disabled before selection")

    local choice = model.run.draft.offer.choices[1]
    model = activate(model, "offer:" .. choice.choice_id)
    projected = controller.project(model)
    t:eq(projected.draft.inspected.choice_id, choice.choice_id,
        "tap card opens an inspectable bottom-sheet payload")
    t:ok(action_by_id(projected, "select:" .. choice.choice_id) ~= nil,
        "inspect sheet has an explicit Select action")
    model = activate(model, "select:" .. choice.choice_id)
    projected = controller.project(model)
    t:eq(action_by_id(projected, "confirm_offer").enabled, true,
        "explicit selection enables confirmation")

    local boundary_projection = legacy_boundary.project(model.run, nil, nil, 1)
    t:eq(boundary_projection.screen, "draft",
        "presentation.project contract is available at the blueprint boundary")
    t:ok(serializable(boundary_projection), "blueprint projection uses values only")

    model = complete_draft(model)
    projected = controller.project(model)
    t:eq(projected.screen, "setup", "complete draft projects setup surface")
    t:eq(#projected.setup.bricks, 8, "setup projects eight separately selectable bricks")
    t:eq(#projected.setup.bag, 4, "setup projects explicit four-marble order")
    t:eq(#projected.setup.insertion_slots, 5, "bag projects before-each and tail slots")
    t:eq(#projected.setup.grid, 3, "formation projects three rows")
    for row = 1, 3 do
        t:eq(#projected.setup.grid[row], 7, "formation row " .. row .. " projects seven cells")
    end
    t:eq(projected.setup.valid, false, "empty formation projects validation state")
    t:eq(action_by_id(projected, "lock_setup").enabled, false,
        "persistent lock is visibly disabled with reasons")
    t:eq(#projected.setup.errors > 0, true, "setup projection carries readable lock reasons")

    for index, brick in ipairs(model.run.player.bricks) do
        model = activate(model, "brick:" .. brick.uid)
        local row = math.floor((index - 1) / 7) + 1
        local col = ((index - 1) % 7) + 1
        model = activate(model, string.format("cell:%d:%d", row, col))
    end
    projected = controller.project(model)
    t:eq(projected.setup.valid, true, "placed formation projects valid state")
    t:eq(action_by_id(projected, "lock_setup").enabled, true,
        "valid formation enables persistent lock")
    t:eq(#projected.setup.build_tags > 0, true, "setup projects aggregate synergy counts")
    t:eq(#projected.setup.adjacencies > 0, true, "setup projects adjacency previews")

    model = activate(model, "lock_setup")
    local completion = fixtures.completion()
    local previous = completion.recording.frames[1]
    local current = completion.recording.frames[2]
    projected = controller.project(model, previous, current, 0.5)
    t:eq(projected.screen, "battle", "lock projects battle surface")
    t:eq(projected.battle.status, "handoff", "battle surface exposes handoff status")
    t:eq(projected.battle.frame.entities[1].x, 195.5,
        "renderer interpolation uses adjacent canonical frames")
    t:eq(projected.battle.frame.entities[1].y, 705,
        "interpolated Y comes from recorded/canonical transforms")
    t:eq(projected.battle.frame.interpolation_alpha, 0.5,
        "projection exposes clamped interpolation alpha")
    t:ok(action_by_id(projected, "entity:player-m01") ~= nil,
        "battle entity is inspectable without becoming a combat command")
    t:ok(action_by_id(projected, "battle_pause") ~= nil,
        "battle projects pause as a view control")
    t:ok(action_by_id(projected, "battle_speed") ~= nil,
        "battle projects 1x/2x view speed")
    t:ok(action_by_id(projected, "battle_mute") ~= nil,
        "battle projects mute control")
    t:ok(action_by_id(projected, "battle_motion") ~= nil,
        "battle projects reduced-motion control")

    model = assert(controller.complete_battle(model, completion)).model
    projected = controller.project(model)
    t:eq(projected.screen, "result", "engine result projects result surface")
    t:eq(projected.title, "Victory", "result copy derives from canonical winner")
    t:eq(projected.result.exchanges, 3, "result projects exchange count")
    t:eq(projected.result.recording_frames, 3, "result reports replay breadth")
    t:ok(action_by_id(projected, "replay_battle").enabled,
        "result enables Replay Battle from recording")
    t:ok(action_by_id(projected, "new_run").enabled, "result enables New Run")

    local run_before = util.deep_copy(model.run)
    model = activate(model, "replay_battle")
    projected = controller.project(model)
    t:eq(projected.screen, "replay", "replay is a presentation surface")
    t:eq(projected.replay.source, "recording", "replay declares immutable recording source")
    t:eq(projected.replay.frame.tick, 0, "replay begins at stored frame zero")
    t:ok(util.deep_equal(model.run, run_before), "replay projection leaves RunState unchanged")
    model = activate(model, "replay_next")
    projected = controller.project(model)
    t:eq(projected.replay.frame.tick, 4, "replay next reads the next stored frame")
    t:eq(projected.replay.cursor, 2, "replay projection tracks recording cursor")
    t:ok(serializable(projected), "replay projection remains serializer-safe")

    local handle = io.open("src/run_presentation.lua", "r")
    t:ok(handle ~= nil, "run presentation source is readable")
    if handle then
        local source = handle:read("*a")
        handle:close()
        local banned = {
            { "love.", "projection has no LÖVE dependency" },
            { "math.random", "projection has no independent randomness" },
            { "damage_brick", "projection does not calculate brick damage" },
            { "battle.step", "recording replay never steps combat" },
            { "determine_winner", "projection does not determine a winner" },
        }
        for _, item in ipairs(banned) do
            t:eq(source:find(item[1], 1, true), nil, item[2])
        end
    end
end

if arg and arg[0] and arg[0]:find("test_run_presentation.lua", 1, true) then
    harness.run_one(M)
end

return M
