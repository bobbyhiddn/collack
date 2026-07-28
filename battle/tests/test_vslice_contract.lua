-- Contract tests shared by draft, setup, continuous battle, and presentation.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local contract = require("battle.vslice_contract")
local content = require("battle.content.draft")
local rule_ast = require("battle.rule_ast")

local M = { name = "vslice_contract" }

local function choice(id, content_ids)
    local source = content.BRICK_KITS[1]
    return {
        choice_id = id,
        content_ids = content_ids,
        mechanics = rule_ast.compact_lines(source.rule_set),
        compact_copy = rule_ast.compact(source.rule_set),
        rule_set = rule_ast.copy(source.rule_set),
        tags = { "example" },
    }
end

local function valid_setup()
    local marbles, bag = {}, {}
    for index = 1, 4 do
        marbles[index] = { uid = "m" .. index }
        bag[index] = "m" .. index
    end
    local bricks = {}
    for index = 1, 8 do bricks[index] = { uid = "b" .. index } end
    return {
        sling_id = "ricochet",
        marbles = marbles,
        bricks = bricks,
        bag_order = bag,
        formation = {
            { "b1", "b2", "b3", ".", ".", ".", "." },
            { ".", "b4", "b5", "b6", ".", ".", "." },
            { ".", ".", "b7", "b8", ".", ".", "." },
        },
    }
end

function M.run(t)
    t:ok(contract.can_transition("draft", "setup"), "draft advances to setup")
    t:ok(contract.can_transition("setup", "battle"), "setup advances to battle")
    t:ok(contract.can_transition("battle", "result"), "battle advances to result")
    t:eq(contract.can_transition("result", "draft"), false,
        "new_run creates a state instead of rewinding one")
    t:eq(contract.can_transition("draft", "battle"), false, "setup cannot be skipped")

    t:ok(contract.command_allowed("draft", "choose_offer"), "draft accepts a choice")
    t:ok(contract.command_allowed("setup", "place_brick"), "setup accepts placement")
    t:ok(contract.command_allowed("setup", "move_bag"), "setup accepts bag ordering")
    t:eq(contract.command_allowed("battle", "place_brick"), false,
        "autobattle accepts no reflex placement")
    t:eq(contract.command_allowed("result", "replay_battle"), false,
        "replay is explicitly a view command")

    t:eq(contract.PHYSICS.FIXED_HZ, 120, "canonical simulation runs at 120 Hz")
    t:eq(contract.PHYSICS.RECORD_EVERY_TICKS, 4, "recording samples at 30 Hz")
    t:eq(contract.PHYSICS.KEYFRAME_EVERY_TICKS, 120, "recording keyframes each second")
    t:eq(contract.PHYSICS.MAX_EXCHANGES, 40, "battle exhaustion cap is explicit")

    local draft = contract.derive_seed(9125, "draft")
    local opponent = contract.derive_seed(9125, "opponent")
    local battle = contract.derive_seed(9125, "battle")
    t:eq(contract.derive_seed(9125, "draft"), draft, "seed derivation is stable")
    t:neq(draft, opponent, "draft and opponent streams are separate")
    t:neq(draft, battle, "draft and battle streams are separate")
    t:neq(opponent, battle, "opponent and battle streams are separate")

    local offer = {
        offer_id = "brick-1",
        category = "brick_kit",
        choices = {
            choice("guard", { "absorber", "fortifier" }),
            choice("mirror", { "mirror", "anchor" }),
            choice("burst", { "shatter", "keg" }),
        },
    }
    local offer_ok, offer_error = contract.validate_offer(offer)
    t:ok(offer_ok, offer_error or "a complete offer validates")
    offer.choices[3].tags = {}
    local bad_offer, bad_offer_error = contract.validate_offer(offer)
    t:eq(bad_offer, false, "an unlabelled offer is rejected")
    t:eq(bad_offer_error, "every choice needs synergy tags", "offer rejection is actionable")

    local setup = valid_setup()
    local setup_ok, setup_error = contract.validate_setup(setup)
    t:ok(setup_ok, setup_error or "a complete setup validates")

    setup.bag_order[4] = setup.bag_order[3]
    local bad_bag, bag_error = contract.validate_setup(setup)
    t:eq(bad_bag, false, "a duplicate bag entry is rejected")
    t:eq(bag_error, "bag contains a duplicate marble", "bag rejection is actionable")

    setup = valid_setup()
    setup.formation[3][4] = "b7"
    local duplicate_brick, brick_error = contract.validate_setup(setup)
    t:eq(duplicate_brick, false, "a duplicate brick placement is rejected")
    t:eq(brick_error, "a brick is placed more than once", "placement rejection is actionable")
end

if arg and arg[0] and arg[0]:find("test_vslice_contract.lua", 1, true) then
    harness.run_one(M)
end

return M
