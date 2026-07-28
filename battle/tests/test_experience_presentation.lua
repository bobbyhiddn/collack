local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../../src/?.lua",
    here .. "/../?.lua",
    "./?.lua",
    "./src/?.lua",
    package.path,
}, ";")

local art = require("ui.art_tokens")
local controller = require("run_controller")
local engine = require("battle.engine")
local fixtures = require("battle.tests.short_run_fixtures")
local harness = require("battle.tests.harness")
local util = require("battle.run_util")

local M = { name = "experience_presentation" }

local function activate(model, id, source)
    local result, action_error = controller.activate(model, id, source or "touch")
    assert(result, action_error and action_error.message or ("action failed: " .. id))
    return result.model
end

local function action_by_id(projected, id)
    for _, item in ipairs(projected.actions or {}) do
        if item.id == id then return item end
    end
    return nil
end

local function assert_targets(t, projected, context)
    for _, item in ipairs(projected.actions or {}) do
        t:ok(item.bounds.width >= projected.minimum_target,
            context .. " " .. item.id .. " keeps a 48-pixel-class width")
        t:ok(item.bounds.height >= projected.minimum_target,
            context .. " " .. item.id .. " keeps a 48-pixel-class height")
    end
end

local function place_sparse_start(model)
    local cells = { { 1, 2 }, { 1, 4 }, { 1, 6 } }
    for index, brick in ipairs(model.run.player.bricks) do
        model = activate(model, "brick:" .. brick.uid)
        model = activate(model, string.format(
            "cell:%d:%d",
            cells[index][1],
            cells[index][2]
        ))
    end
    return model
end

local function first_visible_rule(rule_set)
    for _, rule in ipairs(rule_set.rules) do
        if rule.visibility ~= "internal" then return rule end
    end
    return nil
end

local function first_compact_rule(rule_set)
    for _, rule in ipairs(rule_set.rules) do
        if rule.visibility == "compact" then return rule end
    end
    return first_visible_rule(rule_set)
end

local function channel(value)
    if value <= 0.04045 then return value / 12.92 end
    return ((value + 0.055) / 1.055) ^ 2.4
end

local function luminance(rgb)
    return 0.2126 * channel(rgb[1])
        + 0.7152 * channel(rgb[2])
        + 0.0722 * channel(rgb[3])
end

local function contrast(left, right)
    local a, b = luminance(left), luminance(right)
    local light, dark = math.max(a, b), math.min(a, b)
    return (light + 0.05) / (dark + 0.05)
end

function M.run(t)
    local model = controller.new({ run_seed = 9125, short_run = true })
    local projected = controller.project(model)
    t:eq(projected.screen, "setup", "experience pass begins at sparse setup")
    t:ok(#projected.opponent.pressure >= 3,
        "scout projects the rival sling and physical pressure sources")
    t:eq(projected.opponent.pressure[1].kind, "sling",
        "scout leads with the rival macro pressure")
    t:ok(#projected.opponent.pressure[1].compact_copy > 20,
        "scout pressure carries canonical generated copy")
    assert_targets(t, projected, "setup")

    model = place_sparse_start(model)
    model = activate(model, "lock_setup")
    local handoff = model.run.battle.handoff
    local world = engine.new({
        battle_seed = handoff.battle_seed,
        rules_version = handoff.rules_version,
        player = handoff.player,
        opponent = handoff.opponent,
    })
    local frame = engine.snapshot(world)
    projected = controller.project(model, frame, frame, 1)
    assert_targets(t, projected, "battle")
    local entity_action
    for _, entity in ipairs(projected.battle.frame.entities) do
        if entity.type == "brick" and entity.alive then
            entity_action = "entity:" .. tostring(entity.id)
            break
        end
    end
    local entity_touch = assert(controller.activate(model, entity_action, "touch"))
    local entity_mouse = assert(controller.activate(model, entity_action, "mouse"))
    t:ok(util.deep_equal(entity_touch.model, entity_mouse.model),
        "touch and mouse open the same battle rule inspector")
    local battle_inspection = controller.project(
        entity_touch.model,
        frame,
        frame,
        1
    ).battle.inspected.rule_inspection
    t:ok(battle_inspection.rule.trigger.event ~= nil,
        "battle inspector exposes the canonical trigger")
    t:ok(battle_inspection.rule.target.selector ~= nil,
        "battle inspector exposes the canonical target")
    t:ok(battle_inspection.rule.magnitude.value ~= nil,
        "battle inspector exposes the canonical magnitude")
    t:ok(battle_inspection.rule.cadence.label:find("NO RULE CAP", 1, true)
            or battle_inspection.rule.cadence.limit
            or battle_inspection.rule.cadence.charges,
        "battle inspector makes the exact limit explicit")
    t:eq(battle_inspection.rule.icon,
        art.rule_operation[battle_inspection.rule.verb].mark,
        "battle inspector reuses the card operation mark")
    t:ok(util.deep_equal(entity_touch.model.run, model.run),
        "battle inspection cannot alter canonical physics or run state")
    local mute_touch = assert(controller.activate(model, "battle_mute", "touch"))
    local mute_mouse = assert(controller.activate(model, "battle_mute", "mouse"))
    t:ok(util.deep_equal(mute_touch.model, mute_mouse.model),
        "touch and mouse toggle the same mute state")
    t:eq(mute_touch.model.ui.muted, true,
        "battle mute remains a pointer-accessible view setting")
    local motion_touch = assert(controller.activate(model, "battle_motion", "touch"))
    local motion_mouse = assert(controller.activate(model, "battle_motion", "mouse"))
    t:ok(util.deep_equal(motion_touch.model, motion_mouse.model),
        "touch and mouse toggle the same reduced-motion state")
    t:eq(motion_touch.model.ui.reduced_motion, true,
        "reduced motion remains a pointer-accessible view setting")

    model = assert(controller.complete_battle(
        model,
        fixtures.completion(model.run)
    )).model
    projected = controller.project(model)
    t:eq(projected.screen, "draft", "victory opens the compact refit comparison")
    t:eq(#projected.draft.cards, 3, "refit keeps exactly three comparable cards")
    assert_targets(t, projected, "refit")

    for _, card in ipairs(projected.draft.cards) do
        local comparison = card.comparison
        local source = first_compact_rule(card.rule_set)
        t:eq(comparison.no_ellipsis, true,
            card.name .. " declares a no-ellipsis compact contract")
        t:eq(#comparison.primary_rule.comparison_lines, 2,
            card.name .. " has two stable comparison rows")
        for _, line in ipairs(comparison.primary_rule.comparison_lines) do
            t:eq(line:find("...", 1, true), nil,
                card.name .. " comparison row is not clipped with ellipsis")
            t:ok(#line <= 64, card.name .. " comparison row stays within the phone budget")
        end
        t:eq(comparison.primary_rule.trigger.event, source.trigger.event,
            card.name .. " comparison trigger comes from the canonical rule")
        t:eq(comparison.primary_rule.target.selector, source.target.selector,
            card.name .. " comparison target comes from the canonical rule")
        t:eq(comparison.primary_rule.verb, source.operation.verb,
            card.name .. " comparison verb comes from the canonical rule")
        t:eq(comparison.primary_rule.icon,
            art.rule_operation[source.operation.verb].mark,
            card.name .. " uses the shared rule-operation mark")
    end

    local choice = model.run.draft.offer.choices[1]
    local touch = assert(controller.activate(
        model,
        "offer:" .. choice.choice_id,
        "touch"
    ))
    local mouse = assert(controller.activate(
        model,
        "offer:" .. choice.choice_id,
        "mouse"
    ))
    t:ok(util.deep_equal(touch.model, mouse.model),
        "touch and mouse open the same expanded rule state")
    t:ok(util.deep_equal(touch.model.run, model.run),
        "expanded inspection cannot mutate the run")
    model = touch.model
    projected = controller.project(model)
    assert_targets(t, projected, "expanded refit")
    local inspection = projected.draft.inspected.rule_inspection
    local source = first_visible_rule(choice.rule_set)
    t:eq(inspection.index, 1, "expanded rules open on the first visible rule")
    t:eq(inspection.rule.trigger.event, source.trigger.event,
        "expanded state exposes the exact trigger")
    t:eq(inspection.rule.target.selector, source.target.selector,
        "expanded state exposes the exact target")
    t:eq(inspection.rule.verb, source.operation.verb,
        "expanded state exposes the exact operation")
    t:eq(inspection.rule.magnitude.value,
        (source.magnitude or source.duration).value,
        "expanded state exposes the exact magnitude or duration")
    t:eq(inspection.rule.cadence.interval, source.cadence.interval,
        "expanded state exposes the exact cadence")
    t:eq(inspection.rule.cadence.limit, source.cadence.limit,
        "expanded state exposes the exact chain limit")
    t:eq(inspection.rule.cadence.charges, source.cadence.charges,
        "expanded state exposes the exact charge limit")
    t:eq(inspection.drawback.kind, choice.rule_set.drawback.kind,
        "expanded state exposes the exact item drawback")
    t:ok(action_by_id(projected, "inspection_close") ~= nil,
        "expanded state has a pointer-close action")
    for _, id in ipairs({ "inspection_prev", "inspection_close", "inspection_next" }) do
        local action = action_by_id(projected, id)
        t:ok(action.bounds.width >= 48 and action.bounds.height >= 48,
            id .. " retains a 48-pixel-class target")
    end

    if inspection.count > 1 then
        local next_touch = assert(controller.activate(model, "inspection_next", "touch"))
        local next_mouse = assert(controller.activate(model, "inspection_next", "mouse"))
        t:ok(util.deep_equal(next_touch.model, next_mouse.model),
            "touch and mouse page the same canonical rule")
        model = next_touch.model
        projected = controller.project(model)
        t:eq(projected.draft.inspected.rule_inspection.index, 2,
            "next action advances exactly one visible rule")
    end
    local closed = activate(model, "inspection_close", "touch")
    t:eq(closed.ui.inspected_choice_id, nil, "close returns to three-card comparison")
    t:ok(util.deep_equal(closed.run, model.run),
        "closing expanded rules leaves the run unchanged")

    model = activate(closed, "offer:" .. choice.choice_id)
    model = activate(model, "select:" .. choice.choice_id)
    model = activate(model, "confirm_offer")
    projected = controller.project(model)
    t:eq(projected.screen, "setup", "confirmed reward returns to setup")
    assert_targets(t, projected, "reward setup")
    t:eq(projected.setup.recent_reward.operation_copy, choice.operation_copy,
        "setup announces the exact applied reward")
    t:eq(projected.opponent.pressure[1].name,
        model.run.opponent.canonical_scout.sling.name,
        "post-reward setup previews the next rival pressure")

    local palette = art.palette
    local contrast_pairs = {
        { palette.paper_ink.rgb, palette.paper_100.rgb, "paper body text" },
        { palette.brass_ink.rgb, palette.paper_100.rgb, "paper rule labels" },
        { palette.chalk.rgb, palette.walnut_900.rgb, "walnut primary text" },
        { palette.muted.rgb, palette.walnut_900.rgb, "walnut secondary text" },
        { palette.chalk.rgb, palette.felt_900.rgb, "felt primary text" },
        { palette.muted.rgb, palette.felt_900.rgb, "felt secondary text" },
        { palette.restore.rgb, palette.felt_900.rgb, "felt success text" },
        { palette.player_b.rgb, palette.felt_900.rgb, "felt rival text" },
    }
    for _, pair in ipairs(contrast_pairs) do
        t:ok(contrast(pair[1], pair[2]) >= 4.5,
            pair[3] .. " meets WCAG AA normal-text contrast")
    end
end

if arg and arg[0] and arg[0]:find("test_experience_presentation.lua", 1, true) then
    harness.run_one(M)
end

return M
