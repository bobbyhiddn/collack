-- Serializable projection for the four run surfaces.  It consumes snapshots
-- and recorded/current battle frames; it never reads mutable engine objects or
-- calculates combat outcomes.

local draft_content = require("battle.content.draft")
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

local function opponent_projection(opponent)
    return {
        recipe_id = opponent.recipe_id,
        name = opponent.name,
        description = opponent.description,
        scout_tags = tag_projection(opponent.scout_tags),
        sling = opponent.sling and opponent.sling.name or opponent.sling_id,
        marble_count = #(opponent.marbles or {}),
        brick_count = #(opponent.bricks or {}),
        art_id = "opponent_" .. opponent.recipe_id,
    }
end

local function choice_card(choice, ui, index)
    return {
        choice_id = choice.choice_id,
        content_id = choice.content_id,
        name = choice.name,
        role = choice.role,
        rarity = choice.rarity,
        draft_value = choice.draft_value,
        mechanics = util.deep_copy(choice.mechanics),
        tags = tag_projection(choice.tags),
        synergy = util.deep_copy(choice.synergy),
        details = util.deep_copy(choice.details),
        suggested_placement = choice.suggested_placement,
        art_id = choice.art_id,
        inspected = ui.inspected_choice_id == choice.choice_id,
        selected = ui.selected_choice_id == choice.choice_id,
        action_id = "offer:" .. choice.choice_id,
        layout_index = index,
    }
end

local function project_draft(presentation, state, ui)
    local offer = state.draft.offer
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
    presentation.draft = {
        offer_id = offer.offer_id,
        category = offer.category,
        round = offer.round,
        cards = {},
        build_tags = tag_projection(offer.build_tags),
        scout_tags = tag_projection(offer.scout_tags),
        inspected = nil,
        selected_choice_id = ui.selected_choice_id,
        progress = {
            sling = state.draft.picks.sling and 1 or 0,
            marbles = #state.draft.picks.marbles,
            brick_kits = #state.draft.picks.brick_kits,
            total = state.draft.offer_index - 1,
            required = 9,
        },
    }
    for index, choice in ipairs(offer.choices) do
        local card = choice_card(choice, ui, index)
        presentation.draft.cards[#presentation.draft.cards + 1] = card
        add_action(presentation, action(
            card.action_id,
            "inspect_offer",
            "Inspect " .. choice.name,
            true,
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

local function project_setup(presentation, state, ui)
    presentation.title = "Arrange your collection"
    presentation.subtitle = "Tap a brick, then a legal cell. Bag index 1 launches first."
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
        valid = state.setup.valid,
        errors = util.deep_copy(state.setup.errors),
        build_tags = counted_tag_projection(state.setup.build_tags),
        adjacencies = util.deep_copy(state.setup.adjacencies),
        sling = state.player.sling and {
            id = state.player.sling.id,
            name = state.player.sling.name,
            archetype = state.player.sling.archetype,
        } or nil,
        selected_brick_uid = ui.selected_brick_uid,
        selected_marble_uid = ui.selected_marble_uid,
        grid = {},
        bricks = {},
        bag = {},
        insertion_slots = {},
    }

    for index, brick in ipairs(state.player.bricks) do
        presentation.setup.bricks[#presentation.setup.bricks + 1] = {
            uid = brick.uid,
            content_id = brick.content_id,
            name = brick.name,
            behaviour = brick.behaviour,
            family = brick.family,
            hp = brick.hp,
            max_hp = brick.max_hp,
            tags = tag_projection(brick.tags),
            art_id = brick.art_id,
            selected = ui.selected_brick_uid == brick.uid,
            cell = util.deep_copy(placement[brick.uid]),
            action_id = "brick:" .. brick.uid,
        }
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
        presentation.setup.bag[#presentation.setup.bag + 1] = {
            order = order,
            uid = uid,
            content_id = marble.content_id,
            name = marble.name,
            role = marble.role,
            rarity = marble.rarity,
            tags = tag_projection(marble.tags),
            art_id = marble.art_id,
            selected = ui.selected_marble_uid == uid,
            action_id = "marble:" .. uid,
        }
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
            { x = 16 + (order - 1) * 89, y = 584, width = 48, height = 48 }
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
        { x = 326, y = 584, width = 48, height = 48 }
    ))
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

local function project_battle(presentation, state, ui, previous_frame, current_frame, alpha)
    presentation.title = "Automatic battle"
    presentation.subtitle = "Both bags commit together. No reflex input changes combat."
    presentation.opponent = opponent_projection(state.opponent)
    local frame = projected_frame(
        previous_frame,
        current_frame,
        ui.reduced_motion and 1 or alpha
    )
    presentation.battle = {
        status = frame and (frame.finished and "finished" or "running")
            or (state.battle and state.battle.status or "handoff"),
        exchange = frame and frame.exchange or (state.battle and state.battle.exchange or 0),
        tick = frame and frame.tick or (state.battle and state.battle.tick or 0),
        frame = frame,
        inspected_entity_id = ui.inspected_entity_id,
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
        if id then
            local bounds = {
                x = 20 + ((index - 1) % 7) * 50,
                y = 250,
                width = 48,
                height = 48,
            }
            if frame.arena and type(entity.x) == "number" and type(entity.y) == "number" then
                bounds.x = clamp(16 + entity.x / frame.arena.width * 358 - 24, 16, 326)
                bounds.y = clamp(86 + entity.y / frame.arena.height * 650 - 24, 86, 688)
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
end

local function recent_events(events, count)
    local out = {}
    local first = math.max(1, #(events or {}) - count + 1)
    for index = first, #(events or {}) do
        out[#out + 1] = util.deep_copy(events[index])
    end
    return out
end

local function project_result(presentation, state, ui, previous_frame, current_frame)
    presentation.title = state.result.outcome == "draw" and "Draw" or
        (state.result.winner == "player" and "Victory" or "Defeat")
    presentation.subtitle = tostring(state.result.reason):gsub("_", " ")
    presentation.opponent = opponent_projection(state.opponent)
    presentation.result = {
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
        "Draft Again",
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
    return presentation
end

return M
