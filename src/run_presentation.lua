-- Serializable projection for the four run surfaces.  It consumes snapshots
-- and recorded/current battle frames; it never reads mutable engine objects or
-- calculates combat outcomes.

local draft_content = require("battle.content.draft")
local brick_content = require("battle.content.bricks")
local shell_content = require("battle.content.shells")
local rule_ast = require("battle.rule_ast")
local util = require("battle.run_util")
local battle_projection = require("presentation")
local art = require("ui.art_tokens")

local M = {}

M.SCHEMA_VERSION = 1
M.LOGICAL_WIDTH = 390
M.LOGICAL_HEIGHT = 844
M.MIN_TARGET = art.touch.minimum

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function action(id, kind, label, enabled, bounds)
    bounds = bounds or {}
    return {
        id = id,
        kind = kind,
        label = label,
        enabled = enabled ~= false,
        bounds = {
            x = bounds.x or 0,
            y = bounds.y or 0,
            width = math.max(M.MIN_TARGET, bounds.width or M.MIN_TARGET),
            height = math.max(M.MIN_TARGET, bounds.height or M.MIN_TARGET),
        },
    }
end

local function add_action(presentation, descriptor)
    presentation.actions[#presentation.actions + 1] = descriptor
    presentation.enabled_actions[descriptor.id] = descriptor.enabled
end

local function token_bounds(rect)
    return {
        x = rect.x,
        y = rect.y,
        width = rect.w,
        height = rect.h,
    }
end

local function tag_projection(tags)
    local out = {}
    for _, id in ipairs(tags or {}) do
        local definition = draft_content.TAGS[id]
        out[#out + 1] = {
            id = id,
            label = definition and definition.label or id,
            description = definition and definition.description or "",
        }
    end
    return out
end

local function counted_tag_projection(tags)
    local out = {}
    for _, item in ipairs(tags or {}) do
        local definition = draft_content.TAGS[item.id]
        out[#out + 1] = {
            id = item.id,
            count = item.count,
            label = definition and definition.label or item.id,
            description = definition and definition.description or "",
        }
    end
    return out
end

local function synergy_projection(synergy)
    synergy = synergy or {}
    return {
        matched = tag_projection(synergy.matched),
        introduced = tag_projection(synergy.introduced),
        counters = tag_projection(synergy.counters),
    }
end

local SHORT_TRIGGER = {
    build = "BUILD",
    collision = "CONTACT",
    core_release = "CORE RELEASE",
    damaging_collision = "DAMAGE HIT",
    destroyed = "DESTROYED",
    field_contact = "FIELD CONTACT",
    launch = "LAUNCH",
    non_chip_collision = "NON-CHIP HIT",
    passive = "PASSIVE",
    status_tick = "STATUS TICK",
    survives_collision = "SURVIVE HIT",
    wall_or_brick_contact = "WALL/BRICK HIT",
}

local SHORT_TARGET = {
    all_owned_marbles = "ALL OWN MARBLES",
    current_shell = "CURRENT SHELL",
    launch = "LAUNCH",
    nearby_marbles = "NEARBY MARBLES",
    orthogonal_neighbours = "ADJACENT BRICKS",
    release_area = "RELEASE AREA",
    self = "SELF",
    striking_marble = "STRIKING MARBLE",
    struck_brick = "STRUCK BRICK",
    target_column = "TARGET COLUMN",
}

local SHORT_UNIT = {
    count = "",
    damage = "DMG",
    durability = "DURABILITY",
    flag = "",
    hp = "HP",
    id = "",
    launch_force = "FORCE",
    multiplier = "×",
    percent = "%",
    radius = "RADIUS",
    shots = "SHOTS",
    strength = "STRENGTH",
    ticks = "TICKS",
    cells = "CELLS",
}

local function readable_identifier(value)
    return tostring(value or "none"):gsub("_", " "):upper()
end

local function quantity_projection(quantity, kind)
    if not quantity then
        return {
            kind = kind or "none",
            value = nil,
            unit = "none",
            label = "NONE",
        }
    end
    local value = quantity.value
    local value_copy
    if type(value) == "boolean" then
        value_copy = value and "TRUE" or "FALSE"
    else
        value_copy = tostring(value):upper():gsub("_", " ")
    end
    local unit = SHORT_UNIT[quantity.unit] or readable_identifier(quantity.unit)
    local label
    if unit == "×" or unit == "%" then
        label = value_copy .. unit
    elseif unit == "" then
        label = value_copy
    else
        label = value_copy .. " " .. unit
    end
    return {
        kind = kind or "magnitude",
        value = value,
        unit = quantity.unit,
        label = label,
    }
end

local function cadence_projection(cadence)
    cadence = cadence or { unit = "trigger", interval = 1 }
    local interval = tonumber(cadence.interval) or 1
    local label
    local short_label
    if cadence.charges then
        label = string.format("%d CHARGE%s TOTAL", cadence.charges,
            cadence.charges == 1 and "" or "S")
        short_label = string.format("%d CHARGE%s", cadence.charges,
            cadence.charges == 1 and "" or "S")
    elseif cadence.limit then
        label = string.format("CHAIN LIMIT %d", cadence.limit)
        short_label = string.format("CHAIN %d", cadence.limit)
    elseif interval > 1 then
        label = string.format(
            "EVERY %d %s · NO RULE CAP",
            interval,
            readable_identifier(cadence.unit)
        )
        short_label = string.format("EVERY %d %s", interval,
            readable_identifier(cadence.unit))
    else
        label = "EVERY " .. readable_identifier(cadence.unit) .. " · NO RULE CAP"
        short_label = "EACH " .. readable_identifier(cadence.unit)
    end
    return {
        unit = cadence.unit,
        interval = interval,
        charges = cadence.charges,
        limit = cadence.limit,
        label = label,
        short_label = short_label,
    }
end

local function drawback_projection(drawback)
    drawback = drawback or { kind = "none" }
    if drawback.kind == "none" then
        return {
            kind = "none",
            stat = nil,
            magnitude = nil,
            unit = nil,
            label = "NONE",
        }
    end
    local amount = quantity_projection({
        value = drawback.magnitude,
        unit = drawback.unit,
    }, "drawback")
    return {
        kind = drawback.kind,
        stat = drawback.stat,
        magnitude = drawback.magnitude,
        unit = drawback.unit,
        label = string.format(
            "%s · %s · %s",
            readable_identifier(drawback.kind),
            readable_identifier(drawback.stat),
            amount.label
        ),
    }
end

local function rule_identity(rule)
    local operation_token = art.rule_operation[rule.operation.verb] or {
        label = readable_identifier(rule.operation.verb),
        mark = readable_identifier(rule.operation.verb):sub(1, 3),
    }
    local quantity = rule.magnitude
        and quantity_projection(rule.magnitude, "magnitude")
        or quantity_projection(rule.duration, "duration")
    local cadence = cadence_projection(rule.cadence)
    local trigger_label = SHORT_TRIGGER[rule.trigger.event]
        or readable_identifier(rule.trigger.event)
    local target_label = SHORT_TARGET[rule.target.selector]
        or readable_identifier(rule.target.selector)
    return {
        id = rule.id,
        visibility = rule.visibility,
        icon = operation_token.mark,
        verb = rule.operation.verb,
        verb_label = operation_token.label,
        stat = rule.operation.stat,
        mode = rule.operation.mode,
        trigger = {
            event = rule.trigger.event,
            phase = rule.trigger.phase,
            condition = rule.condition.predicate,
            condition_value = rule.condition.value,
            label = readable_identifier(rule.trigger.phase)
                .. " " .. readable_identifier(rule.trigger.event),
            short_label = trigger_label,
        },
        target = {
            selector = rule.target.selector,
            relation = rule.target.relation,
            label = readable_identifier(rule.target.selector),
            short_label = target_label,
        },
        magnitude = quantity,
        cadence = cadence,
        cost = util.deep_copy(rule.cost),
        sentence = rule_ast.rule_sentence(rule),
        comparison_lines = {
            "ON " .. trigger_label .. " · " .. operation_token.label
                .. (quantity.label ~= "NONE" and (" " .. quantity.label) or ""),
            "TO " .. target_label .. " · " .. cadence.short_label,
        },
    }
end

local function visible_rules(rule_set)
    return rule_ast.player_rules(rule_set)
end

local function rule_inspection(rule_set, requested_index)
    if not rule_set then return nil end
    local rules = visible_rules(rule_set)
    if #rules == 0 then return nil end
    local index = math.max(1, math.min(#rules, math.floor(
        tonumber(requested_index) or 1
    )))
    return {
        rule_set_id = rule_set.id,
        source_name = rule_set.name,
        role = rule_set.role,
        index = index,
        count = #rules,
        rule = rule_identity(rules[index]),
        drawback = drawback_projection(rule_set.drawback),
        compatibility = util.deep_copy(rule_set.compatibility),
        rarity = rule_set.rarity,
        abilities = util.deep_copy(rule_set.abilities),
        telegraph = util.deep_copy(rule_ast.player_authority(rule_set).telegraph),
    }
end

-- Pure projection used by both the UI and exact cross-consumer consistency
-- tests. It follows the RuleSet's canonical ordered player-rule authority.
M.inspect_rule_set = rule_inspection

local function comparison_rule(rule_set)
    local inspection = rule_inspection(rule_set, 1)
    if not inspection then return nil end
    for _, rule in ipairs(rule_set.rules or {}) do
        if rule.visibility == "compact" then
            inspection.rule = rule_identity(rule)
            return inspection
        end
    end
    return inspection
end

local function pressure_projection(canonical_scout)
    local out = {}
    if not canonical_scout then return out end
    local function append(item, kind)
        if not item then return end
        out[#out + 1] = {
            kind = kind,
            name = item.name,
            compact_copy = item.compact_copy,
            rule_set_id = item.rule_set_id,
            rule_ids = util.deep_copy(item.rule_ids),
        }
    end
    append(canonical_scout.sling, "sling")
    for _, item in ipairs(canonical_scout.bricks or {}) do append(item, "brick") end
    for _, item in ipairs(canonical_scout.marbles or {}) do append(item, "marble") end
    return out
end

local function opponent_projection(opponent)
    return {
        recipe_id = opponent.recipe_id,
        encounter_index = opponent.encounter_index,
        name = opponent.name,
        description = opponent.description,
        scout_tags = tag_projection(opponent.scout_tags),
        sling = opponent.sling and opponent.sling.name or opponent.sling_id,
        marble_count = #(opponent.marbles or {}),
        brick_count = #(opponent.bricks or {}),
        art_id = "opponent_" .. opponent.recipe_id,
        canonical_scout = util.deep_copy(opponent.canonical_scout),
        pressure = pressure_projection(opponent.canonical_scout),
        pool_items = util.deep_copy(opponent.pool_items),
    }
end

local function operation_comparison(choice, state)
    local operation = choice.operation or {}
    local kind = operation.kind
    if kind == "add_marble" then
        return string.format("ADD · BAG %d>%d / CAP %d",
            #state.player.marbles, #state.player.marbles + 1, state.limits.marbles)
    elseif kind == "add_brick" then
        return string.format("ADD · FORMATION %d>%d / CAP %d",
            #state.player.bricks, #state.player.bricks + 1, state.limits.bricks)
    elseif kind == "replace_marble" then
        return "REPLACE · BAG COUNT HOLDS"
    elseif kind == "replace_brick" then
        return "RESHAPE · CELL HOLDS"
    elseif kind == "repair_brick" then
        return "REPAIR · RESTORE CASUALTY"
    elseif kind == "remove_marble" then
        return string.format("REMOVE · BAG %d>%d",
            #state.player.marbles, #state.player.marbles - 1)
    elseif kind == "remove_brick" then
        return string.format("REMOVE · FORMATION %d>%d",
            #state.player.bricks, #state.player.bricks - 1)
    elseif kind == "reshape_sling" then
        return "RESHAPE · SLING RULE CHANGES"
    end
    return "ROLE · " .. readable_identifier(choice.role)
end

local function choice_card(choice, ui, index, state)
    local first_rule = comparison_rule(choice.rule_set)
    return {
        choice_id = choice.choice_id,
        content_id = choice.content_id,
        category = choice.category,
        name = choice.name,
        role = choice.role,
        rarity = choice.rarity,
        draft_value = choice.draft_value,
        mechanics = util.deep_copy(choice.mechanics),
        compact_copy = choice.compact_copy,
        inspection_copy = util.deep_copy(choice.inspection_copy),
        rule_set = util.deep_copy(choice.rule_set),
        compatibility = util.deep_copy(choice.compatibility),
        balance = util.deep_copy(choice.balance),
        telegraph = util.deep_copy(choice.telegraph),
        availability = util.deep_copy(choice.availability),
        tags = tag_projection(choice.tags),
        synergy = synergy_projection(choice.synergy),
        details = util.deep_copy(choice.details),
        suggested_placement = choice.suggested_placement,
        art_id = choice.art_id,
        operation = util.deep_copy(choice.operation),
        operation_verb = choice.operation_verb,
        operation_copy = choice.operation_copy,
        causal_attribution = util.deep_copy(choice.causal_attribution),
        comparison = {
            operation = operation_comparison(choice, state),
            rule_count = first_rule and first_rule.count or 0,
            primary_rule = first_rule and first_rule.rule or nil,
            no_ellipsis = true,
        },
        inspected = ui.inspected_choice_id == choice.choice_id,
        selected = ui.selected_choice_id == choice.choice_id,
        action_id = "offer:" .. choice.choice_id,
        layout_index = index,
    }
end

local function project_draft(presentation, state, ui)
    local offer = state.draft.offer
    local short = state.mode == "comprehension_first_three_fight"
    if short then
        presentation.title = string.format("Refit after fight %d", state.fight.index)
        presentation.subtitle = string.format(
            "Choose one change, then set up for %s.",
            offer.next_encounter.name
        )
        presentation.opponent = {
            recipe_id = offer.next_encounter.recipe_id,
            encounter_index = offer.next_encounter.index,
            name = offer.next_encounter.name,
            description = offer.next_encounter.description,
            scout_tags = tag_projection(offer.scout_tags),
            sling = offer.next_encounter.canonical_scout
                and offer.next_encounter.canonical_scout.sling.name
                or nil,
            marble_count = offer.next_encounter.marble_count,
            brick_count = offer.next_encounter.brick_count,
            art_id = "opponent_" .. tostring(offer.next_encounter.recipe_id),
            canonical_scout = util.deep_copy(offer.next_encounter.canonical_scout),
            pressure = pressure_projection(offer.next_encounter.canonical_scout),
        }
    else
        presentation.title = "Choose your " ..
            (offer.category == "brick_kit" and "brick kit" or offer.category)
        presentation.subtitle = string.format(
            "Offer %d of %d · %s %d",
            state.draft.offer_index,
            1 + 4 + 4,
            offer.category == "brick_kit" and "kit" or offer.category,
            offer.round
        )
        presentation.opponent = opponent_projection(state.opponent)
    end
    presentation.draft = {
        offer_id = offer.offer_id,
        category = offer.category,
        refit = short,
        round = offer.round,
        cards = {},
        build_tags = tag_projection(offer.build_tags),
        scout_tags = tag_projection(offer.scout_tags),
        inspected = nil,
        selected_choice_id = ui.selected_choice_id,
        next_encounter = util.deep_copy(offer.next_encounter),
        progress = short and {
            fight = state.fight.index,
            fights_cleared = state.fight.victories,
            total = state.fight.victories,
            required = state.fight.total,
            sling = 1,
            marbles = #state.player.marbles,
            marble_cap = state.limits.marbles,
            bricks = #state.player.bricks,
            brick_cap = state.limits.bricks,
            broken = #state.workshop.broken_bricks,
        } or {
            sling = state.draft.picks.sling and 1 or 0,
            marbles = #state.draft.picks.marbles,
            brick_kits = #state.draft.picks.brick_kits,
            total = state.draft.offer_index - 1,
            required = 9,
        },
    }
    for index, choice in ipairs(offer.choices) do
        local card = choice_card(choice, ui, index, state)
        if card.inspected then
            card.rule_inspection = rule_inspection(
                card.rule_set,
                ui.inspection_rule_index
            )
        end
        presentation.draft.cards[#presentation.draft.cards + 1] = card
        add_action(presentation, action(
            card.action_id,
            "inspect_offer",
            "Inspect " .. choice.name,
            ui.inspected_choice_id == nil,
            token_bounds(art.layout.phone.draft.offers[index])
        ))
        if card.inspected then
            presentation.draft.inspected = util.deep_copy(card)
            add_action(presentation, action(
                "select:" .. choice.choice_id,
                "select_offer",
                "Select " .. choice.name,
                true,
                { x = 16, y = 708, width = 358, height = 48 }
            ))
            local inspection = card.rule_inspection
            add_action(presentation, action(
                "inspection_prev",
                "page_inspection",
                "Previous canonical rule",
                inspection and inspection.index > 1,
                { x = 28, y = 640, width = 104, height = 48 }
            ))
            add_action(presentation, action(
                "inspection_close",
                "close_inspection",
                "Close expanded rules",
                true,
                { x = 143, y = 640, width = 104, height = 48 }
            ))
            add_action(presentation, action(
                "inspection_next",
                "page_inspection",
                "Next canonical rule",
                inspection and inspection.index < inspection.count,
                { x = 258, y = 640, width = 104, height = 48 }
            ))
        end
    end
    add_action(presentation, action(
        "confirm_offer",
        "confirm_offer",
        "Confirm choice",
        ui.selected_choice_id ~= nil,
        token_bounds(art.layout.phone.draft.primary)
    ))
end

local function map_bricks(bricks)
    local out = {}
    for _, brick in ipairs(bricks or {}) do out[brick.uid] = brick end
    return out
end

local function map_marbles(marbles)
    local out = {}
    for _, marble in ipairs(marbles or {}) do out[marble.uid] = marble end
    return out
end

local function shell_projection(shell_ids)
    local out = {}
    for _, shell_id in ipairs(shell_ids or {}) do
        local shell = shell_content.by_id[shell_id]
        out[#out + 1] = shell and {
            id = shell.id,
            mineral = shell.mineral,
            pattern = shell.pattern,
            collision = shell.collision,
        } or { id = shell_id }
    end
    return out
end

local function project_setup(presentation, state, ui)
    local short = state.mode == "comprehension_first_three_fight"
    presentation.title = short
        and string.format("Fight %d of %d · %s",
            state.fight.index, state.fight.total, state.opponent.name)
        or "Arrange your collection"
    presentation.subtitle = short
        and string.format(
            "Scout %d marbles / %d bricks. Place every active brick; bag index 1 launches first.",
            #state.opponent.marbles,
            #state.opponent.bricks
        )
        or "Tap a brick, then a legal cell. Bag index 1 launches first."
    presentation.opponent = opponent_projection(state.opponent)
    local brick_by_uid = map_bricks(state.player.bricks)
    local marble_by_uid = map_marbles(state.player.marbles)
    local placement = {}
    for row = 1, 3 do
        for col = 1, 7 do
            local uid = state.setup.formation[row][col]
            if uid and uid ~= "." then placement[uid] = { row = row, col = col } end
        end
    end
    presentation.setup = {
        short_run = short,
        fight_index = short and state.fight.index or nil,
        fight_total = short and state.fight.total or nil,
        route = short and util.deep_copy(state.fight.route) or nil,
        limits = short and util.deep_copy(state.limits) or nil,
        broken_bricks = short and util.deep_copy(state.workshop.broken_bricks) or nil,
        valid = state.setup.valid,
        errors = util.deep_copy(state.setup.errors),
        build_tags = counted_tag_projection(state.setup.build_tags),
        adjacencies = util.deep_copy(state.setup.adjacencies),
        ability_links = util.deep_copy(state.setup.ability_links),
        sling = state.player.sling and {
            id = state.player.sling.id,
            name = state.player.sling.name,
            archetype = state.player.sling.archetype,
            mechanics = util.deep_copy(state.player.sling.mechanics),
            compact_copy = state.player.sling.compact_copy,
            inspection_copy = util.deep_copy(state.player.sling.inspection_copy),
            rule_set = util.deep_copy(state.player.sling.rule_set),
            compatibility = util.deep_copy(state.player.sling.compatibility),
            balance = util.deep_copy(state.player.sling.balance),
            tags = tag_projection(state.player.sling.tags),
        } or nil,
        selected_brick_uid = ui.selected_brick_uid,
        selected_marble_uid = ui.selected_marble_uid,
        grid = {},
        bricks = {},
        bag = {},
        insertion_slots = {},
        selected_detail = nil,
        recent_reward = state.workshop
            and state.workshop.reward_history
            and util.deep_copy(state.workshop.reward_history[
                #state.workshop.reward_history
            ])
            or nil,
    }

    for index, brick in ipairs(state.player.bricks) do
        local behaviour = art.behaviour[brick.behaviour] or art.behaviour.inert
        local definition = brick_content.by_id[brick.content_id]
        local projected_brick = {
            uid = brick.uid,
            content_id = brick.content_id,
            name = brick.name,
            behaviour = brick.behaviour,
            rarity = brick.rarity
                or (definition and definition.rarity),
            mechanic_label = behaviour.label,
            mechanic_description = brick.compact_copy
                or (definition and definition.compact_copy)
                or "",
            inspection_copy = util.deep_copy(
                brick.inspection_copy or (definition and definition.inspection_copy)
            ),
            rule_set = util.deep_copy(brick.rule_set or (definition and definition.rule_set)),
            compatibility = util.deep_copy(
                brick.compatibility
                    or (definition and definition.rule_set.compatibility)
            ),
            balance = util.deep_copy(brick.balance or (definition and definition.balance)),
            telegraph = util.deep_copy(
                brick.telegraph or (definition and definition.telegraph)
            ),
            family = brick.family,
            hp = brick.hp,
            max_hp = brick.max_hp,
            tags = tag_projection(brick.tags),
            art_id = brick.art_id,
            selected = ui.selected_brick_uid == brick.uid,
            cell = util.deep_copy(placement[brick.uid]),
            action_id = "brick:" .. brick.uid,
        }
        presentation.setup.bricks[#presentation.setup.bricks + 1] = projected_brick
        if projected_brick.selected then
            presentation.setup.selected_detail = util.deep_copy(projected_brick)
            presentation.setup.selected_detail.type = "brick"
            presentation.setup.selected_detail.rule_inspection =
                rule_inspection(projected_brick.rule_set, ui.inspection_rule_index)
        end
        add_action(presentation, action(
            "brick:" .. brick.uid,
            "select_brick",
            "Select " .. brick.name,
            true,
            {
                x = 20 + ((index - 1) % 4) * 89,
                y = 360 + math.floor((index - 1) / 4) * 60,
                width = 80,
                height = 52,
            }
        ))
    end

    for row = 1, 3 do
        presentation.setup.grid[row] = {}
        for col = 1, 7 do
            local uid = state.setup.formation[row][col]
            local brick = uid ~= "." and brick_by_uid[uid] or nil
            local cell = {
                row = row,
                col = col,
                brick_uid = brick and brick.uid or nil,
                content_id = brick and brick.content_id or nil,
                art_id = brick and brick.art_id or "formation_cell",
                legal = ui.selected_brick_uid ~= nil
                    and (uid == "." or uid == ui.selected_brick_uid),
                action_id = string.format("cell:%d:%d", row, col),
            }
            presentation.setup.grid[row][col] = cell
            add_action(presentation, action(
                cell.action_id,
                "place_selected",
                string.format("Formation row %d column %d", row, col),
                cell.legal,
                { x = 22 + (col - 1) * 49, y = 158 + (row - 1) * 49, width = 44, height = 44 }
            ))
        end
    end

    for order, uid in ipairs(state.setup.bag_order) do
        local marble = marble_by_uid[uid]
        local projected_marble = {
            order = order,
            uid = uid,
            content_id = marble.content_id,
            name = marble.name,
            role = marble.role,
            rarity = marble.rarity,
            core = marble.core,
            shells = shell_projection(marble.shells),
            mechanics = util.deep_copy(marble.mechanics),
            compact_copy = marble.compact_copy,
            inspection_copy = util.deep_copy(marble.inspection_copy),
            rule_set = util.deep_copy(marble.rule_set),
            compatibility = util.deep_copy(marble.compatibility),
            balance = util.deep_copy(marble.balance),
            telegraph = util.deep_copy(marble.telegraph),
            tags = tag_projection(marble.tags),
            art_id = marble.art_id,
            selected = ui.selected_marble_uid == uid,
            action_id = "marble:" .. uid,
        }
        presentation.setup.bag[#presentation.setup.bag + 1] = projected_marble
        if projected_marble.selected then
            presentation.setup.selected_detail = util.deep_copy(projected_marble)
            presentation.setup.selected_detail.type = "marble"
            presentation.setup.selected_detail.rule_inspection =
                rule_inspection(projected_marble.rule_set, ui.inspection_rule_index)
        end
        add_action(presentation, action(
            "marble:" .. uid,
            "select_marble",
            "Select " .. marble.name,
            true,
            { x = 20 + (order - 1) * 89, y = 520, width = 78, height = 56 }
        ))
        local slot = {
            before_uid = uid,
            action_id = "slot:" .. uid,
            enabled = ui.selected_marble_uid ~= nil and ui.selected_marble_uid ~= uid,
        }
        presentation.setup.insertion_slots[#presentation.setup.insertion_slots + 1] = slot
        add_action(presentation, action(
            slot.action_id,
            "insert_selected",
            "Insert before " .. marble.name,
            slot.enabled,
            { x = 16 + (order - 1) * 73, y = 584, width = 48, height = 48 }
        ))
    end
    presentation.setup.insertion_slots[#presentation.setup.insertion_slots + 1] = {
        before_uid = nil,
        action_id = "slot:tail",
        enabled = ui.selected_marble_uid ~= nil,
    }
    add_action(presentation, action(
        "slot:tail",
        "insert_selected",
        "Move to bag tail",
        ui.selected_marble_uid ~= nil,
        { x = 308, y = 584, width = 48, height = 48 }
    ))
    local adjacencies = {}
    for _, adjacency in ipairs(state.setup.adjacencies or {}) do
        adjacencies[#adjacencies + 1] = {
            left_uid = adjacency.left_uid,
            right_uid = adjacency.right_uid,
            active_synergy = adjacency.active_synergy == true,
            tags = tag_projection(adjacency.tags),
        }
    end
    presentation.setup.adjacencies = adjacencies
    add_action(presentation, action(
        "lock_setup",
        "lock_setup",
        state.setup.valid and "Lock formation" or "Formation incomplete",
        state.setup.valid,
        token_bounds(art.layout.phone.formation.primary)
    ))
end

local function entity_map(frame)
    local out = {}
    for _, entity in ipairs((frame and frame.entities) or {}) do
        out[entity.id or entity.uid] = entity
    end
    return out
end

local function projected_frame(previous_frame, current_frame, alpha)
    if not current_frame then return previous_frame and util.deep_copy(previous_frame) or nil end
    if current_frame.sides and current_frame.arena and current_frame.world then
        return battle_projection.project_battle(current_frame, previous_frame, alpha)
    end
    local previous = entity_map(previous_frame)
    local projected = util.deep_copy(current_frame)
    projected.entities = {}
    local mix = clamp(tonumber(alpha) or 1, 0, 1)
    for _, entity in ipairs(current_frame.entities or {}) do
        local copy = util.deep_copy(entity)
        local old = previous[entity.id or entity.uid]
        if old then
            if type(old.x) == "number" and type(entity.x) == "number" then
                copy.x = old.x + (entity.x - old.x) * mix
            end
            if type(old.y) == "number" and type(entity.y) == "number" then
                copy.y = old.y + (entity.y - old.y) * mix
            end
            if type(old.angle) == "number" and type(entity.angle) == "number" then
                copy.angle = old.angle + (entity.angle - old.angle) * mix
            end
        end
        projected.entities[#projected.entities + 1] = copy
    end
    projected.interpolation_alpha = mix
    return projected
end

local function readable_title(value)
    value = tostring(value or ""):gsub("_", " ")
    return (value:gsub("(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end))
end

local function entity_inspection(frame, inspected_id, requested_rule_index)
    if not frame or inspected_id == nil then return nil end
    for _, entity in ipairs(frame.entities or {}) do
        local id = entity.id or entity.uid
        if id and tostring(id) == tostring(inspected_id) then
            local side = frame.sides and frame.sides[entity.owner] or nil
            local fallback_name = readable_title(entity.type)
            if fallback_name == "" then fallback_name = "Unknown piece" end
            local inspected = {
                entity_id = tostring(id),
                type = entity.type,
                name = entity.name or fallback_name,
                owner = entity.owner,
                owner_name = side and side.name
                    or (entity.owner and tostring(entity.owner) or "Arena"),
            }
            if entity.type == "brick" then
                local definition = brick_content.by_id[entity.content_id]
                inspected.family = readable_title(entity.family)
                inspected.mechanic = readable_title(entity.behaviour)
                inspected.rarity = readable_title(entity.rarity
                    or (definition and definition.rarity))
                inspected.mechanic_description = definition and definition.compact_copy or ""
                inspected.inspection_copy = definition
                    and util.deep_copy(definition.inspection_copy)
                    or nil
                inspected.rule_set = definition and util.deep_copy(definition.rule_set) or nil
                inspected.balance = definition and util.deep_copy(definition.balance) or nil
                inspected.telegraph = definition
                    and util.deep_copy(definition.telegraph) or nil
                inspected.guard = util.deep_copy(entity.guard)
                inspected.rule_inspection = definition
                    and rule_inspection(definition.rule_set, requested_rule_index)
                    or nil
                inspected.hp = entity.hp
                inspected.max_hp = entity.max_hp
                inspected.integrity = math.floor(clamp((entity.hp_ratio or 0) * 100, 0, 100) + 0.5)
            elseif entity.type == "marble" then
                local definition = draft_content.marble_by_id[entity.content_id]
                inspected.rarity = readable_title(entity.rarity)
                inspected.core = entity.core
                inspected.shell_count = entity.shell_count or #(entity.shells or {})
                inspected.shell_integrity =
                    math.floor(clamp((entity.shell_ratio or 0) * 100, 0, 100) + 0.5)
                inspected.state = readable_title(entity.state)
                inspected.statuses = {}
                for _, status in ipairs(util.sorted_keys(entity.statuses or {})) do
                    inspected.statuses[#inspected.statuses + 1] = readable_title(status)
                end
                inspected.mechanic_description = definition and definition.compact_copy or ""
                inspected.inspection_copy = definition
                    and util.deep_copy(definition.inspection_copy)
                    or nil
                inspected.rule_set = definition and util.deep_copy(definition.rule_set) or nil
                inspected.balance = definition and util.deep_copy(definition.balance) or nil
                inspected.compatibility = definition
                    and util.deep_copy(definition.compatibility) or nil
                inspected.telegraph = definition
                    and util.deep_copy(definition.telegraph) or nil
                inspected.rule_inspection = definition
                    and rule_inspection(definition.rule_set, requested_rule_index)
                    or nil
            end
            return inspected
        end
    end
    return nil
end

local function project_battle(presentation, state, ui, previous_frame, current_frame, alpha)
    local short = state.mode == "comprehension_first_three_fight"
    presentation.title = short
        and string.format("Fight %d of %d · Automatic battle",
            state.fight.index, state.fight.total)
        or "Automatic battle"
    presentation.subtitle = short
        and (state.opponent.name
            .. " was fully scouted. Both ordered bags now resolve canonically.")
        or "Both bags commit together. No reflex input changes combat."
    presentation.opponent = opponent_projection(state.opponent)
    local frame = projected_frame(
        previous_frame,
        current_frame,
        ui.reduced_motion and 1 or alpha
    )
    presentation.battle = {
        fight_index = short and state.fight.index or nil,
        fight_total = short and state.fight.total or nil,
        status = frame and (frame.finished and "finished" or "running")
            or (state.battle and state.battle.status or "handoff"),
        exchange = frame and frame.exchange or (state.battle and state.battle.exchange or 0),
        tick = frame and frame.tick or (state.battle and state.battle.tick or 0),
        frame = frame,
        inspected_entity_id = ui.inspected_entity_id,
        inspected = entity_inspection(
            frame,
            ui.inspected_entity_id,
            ui.inspection_rule_index
        ),
        view = {
            paused = ui.paused == true,
            speed = ui.speed or 1,
            muted = ui.muted == true,
            reduced_motion = ui.reduced_motion == true,
        },
    }
    for index, entity in ipairs(
        frame
        and frame.entities
        or {}
    ) do
        local id = entity.id or entity.uid
        if id and (entity.type ~= "brick" or entity.alive) then
            local bounds = {
                x = 20 + ((index - 1) % 7) * 50,
                y = 250,
                width = 48,
                height = 48,
            }
            if frame.arena and type(entity.x) == "number" and type(entity.y) == "number" then
                bounds.x = clamp(24 + entity.x / frame.arena.width * 342 - 24, 16, 326)
                bounds.y = clamp(88 + entity.y / frame.arena.height * 632 - 24, 72, 688)
            end
            add_action(presentation, action(
                "entity:" .. tostring(id),
                "inspect_entity",
                "Inspect " .. tostring(entity.name or entity.kind or id),
                true,
                bounds
            ))
        end
    end
    add_action(presentation, action(
        "battle_pause",
        "toggle_pause",
        ui.paused and "Resume" or "Pause",
        true,
        { x = 16, y = 768, width = 82, height = 56 }
    ))
    add_action(presentation, action(
        "battle_speed",
        "cycle_speed",
        (ui.speed or 1) .. "×",
        true,
        { x = 106, y = 768, width = 82, height = 56 }
    ))
    add_action(presentation, action(
        "battle_mute",
        "toggle_mute",
        ui.muted and "Unmute" or "Mute",
        true,
        { x = 196, y = 768, width = 82, height = 56 }
    ))
    add_action(presentation, action(
        "battle_motion",
        "toggle_reduced_motion",
        "Motion",
        true,
        { x = 286, y = 768, width = 88, height = 56 }
    ))
    if presentation.battle.inspected
        and presentation.battle.inspected.rule_inspection then
        local inspection = presentation.battle.inspected.rule_inspection
        add_action(presentation, action(
            "inspection_prev",
            "page_inspection",
            "Previous canonical rule",
            inspection.index > 1,
            { x = 28, y = 426, width = 64, height = 48 }
        ))
        add_action(presentation, action(
            "inspection_next",
            "page_inspection",
            "Next canonical rule",
            inspection.index < inspection.count,
            { x = 298, y = 426, width = 64, height = 48 }
        ))
    end
end

local function recent_events(events, count)
    local out = {}
    local first = math.max(1, #(events or {}) - count + 1)
    for index = first, #(events or {}) do
        out[#out + 1] = util.deep_copy(events[index])
    end
    return out
end

local function fight_history_projection(history)
    local out = {}
    for _, fight in ipairs(history or {}) do
        local callouts = {}
        local ledger = fight.causal_ledger or {}
        local first = math.max(1, #ledger - 4)
        for index = first, #ledger do
            callouts[#callouts + 1] = ledger[index].generated_callout
        end
        local casualties = {}
        for _, casualty in ipairs(fight.casualties or {}) do
            casualties[#casualties + 1] = {
                uid = casualty.brick and casualty.brick.uid,
                name = casualty.brick and casualty.brick.name,
                kit_id = casualty.brick and casualty.brick.kit_id,
            }
        end
        out[#out + 1] = {
            fight_index = fight.fight_index,
            encounter_id = fight.encounter_id,
            opponent_name = fight.opponent and fight.opponent.name,
            result = util.deep_copy(fight.result),
            casualties = casualties,
            attributed_trigger_count = #ledger,
            recent_generated_callouts = callouts,
        }
    end
    return out
end

local function project_result(presentation, state, ui, previous_frame, current_frame)
    presentation.title = state.result.outcome == "draw" and "Draw" or
        (state.result.winner == "player" and "Victory" or "Defeat")
    presentation.subtitle = tostring(state.result.reason):gsub("_", " ")
    presentation.opponent = opponent_projection(state.opponent)
    presentation.result = {
        short_run = state.mode == "comprehension_first_three_fight",
        terminal = state.result.terminal == true,
        fights_cleared = state.result.fights_cleared,
        fight_total = state.fight and state.fight.total,
        fight_history = state.fight and fight_history_projection(state.fight.history) or nil,
        reward_history = state.workshop
            and util.deep_copy(state.workshop.reward_history)
            or nil,
        broken_bricks = state.workshop
            and util.deep_copy(state.workshop.broken_bricks)
            or nil,
        outcome = state.result.outcome,
        winner = state.result.winner,
        reason = state.result.reason,
        exchanges = state.result.exchanges,
        player_tags = util.deep_copy(state.setup.build_tags),
        recording_frames = #(state.battle.recording.frames or {}),
        final_frame = projected_frame(previous_frame, current_frame, 1),
        ledger = recent_events(state.battle.recording.events, ui.ledger_expanded and 9 or 3),
        ledger_expanded = ui.ledger_expanded == true,
    }
    add_action(presentation, action(
        "new_run",
        "new_run",
        state.mode == "comprehension_first_three_fight" and "Run Again" or "Draft Again",
        true,
        { x = 16, y = 692, width = 358, height = 56 }
    ))
    add_action(presentation, action(
        "review_battle",
        "review_ledger",
        ui.ledger_expanded and "Close Ledger" or "Review Battle",
        true,
        { x = 16, y = 760, width = 174, height = 56 }
    ))
    add_action(presentation, action(
        "replay_battle",
        "replay_battle",
        "Replay Battle",
        #(state.battle.recording.frames or {}) > 0,
        { x = 200, y = 760, width = 174, height = 56 }
    ))
end

local function project_replay(presentation, state, ui)
    local replay = ui.replay
    local recording = state.battle.recording
    presentation.screen = "replay"
    presentation.title = "Battle replay"
    presentation.subtitle = string.format("Recorded frame %d of %d", replay.cursor, replay.frame_count)
    presentation.opponent = opponent_projection(state.opponent)
    local current = recording.frames[replay.cursor]
    local previous = recording.frames[math.max(1, replay.cursor - 1)]
    presentation.replay = {
        source = replay.source,
        cursor = replay.cursor,
        frame_count = replay.frame_count,
        frame = projected_frame(previous, current, 1),
        events = util.deep_copy(recording.events),
        result = util.deep_copy(state.result),
    }
    add_action(presentation, action(
        "replay_next",
        "replay_step",
        "Next frame",
        replay.cursor < replay.frame_count,
        { x = 16, y = 760, width = 174, height = 56 }
    ))
    add_action(presentation, action(
        "replay_close",
        "replay_close",
        "Back to result",
        true,
        { x = 200, y = 760, width = 174, height = 56 }
    ))
end

-- Blueprint contract:
-- presentation.project(run_snapshot, previous_frame, current_frame, alpha)
--   -> PresentationState
-- A fifth optional view_state carries inspect/selection controls without
-- polluting canonical RunState.
function M.project(run_snapshot, previous_frame, current_frame, alpha, view_state)
    -- Projection never mutates its inputs; each table exposed below is built or
    -- copied explicitly. Avoid cloning a potentially large finished recording
    -- on every result/replay render frame.
    local state = run_snapshot
    local ui = util.deep_copy(view_state or {})
    local presentation = {
        schema_version = M.SCHEMA_VERSION,
        run_id = state.run_id,
        run_seed = state.run_seed,
        screen = state.phase,
        logical_size = { width = M.LOGICAL_WIDTH, height = M.LOGICAL_HEIGHT },
        safe_area = { top = 0, right = 0, bottom = 0, left = 0 },
        minimum_target = M.MIN_TARGET,
        labels = {
            product = "CALLACK",
            seed = string.format("SEED %d", state.run_seed),
            phase = string.upper(state.phase),
        },
        art_direction = "warm_handcrafted_tabletop",
        short_run = state.mode == "comprehension_first_three_fight" and {
            fight_index = state.fight.index,
            fight_total = state.fight.total,
            victories = state.fight.victories,
            route = util.deep_copy(state.fight.route),
            marble_count = #state.player.marbles,
            brick_count = #state.player.bricks,
            marble_cap = state.limits.marbles,
            brick_cap = state.limits.bricks,
            casualties = #state.workshop.broken_bricks,
        } or nil,
        actions = {},
        enabled_actions = {},
    }
    if ui.replay then
        project_replay(presentation, state, ui)
    elseif state.phase == "draft" then
        project_draft(presentation, state, ui)
    elseif state.phase == "setup" then
        project_setup(presentation, state, ui)
    elseif state.phase == "battle" then
        project_battle(presentation, state, ui, previous_frame, current_frame, alpha)
    elseif state.phase == "result" then
        project_result(presentation, state, ui, previous_frame, current_frame)
    end
    if presentation.short_run then
        if state.phase == "draft" then
            presentation.labels.phase = string.format(
                "REFIT %d/%d",
                state.fight.index,
                state.fight.total
            )
        elseif state.phase == "result" then
            presentation.labels.phase = "RUN COMPLETE"
        else
            presentation.labels.phase = string.format(
                "FIGHT %d/%d · %s",
                state.fight.index,
                state.fight.total,
                string.upper(state.phase)
            )
        end
    end
    return presentation
end

return M
