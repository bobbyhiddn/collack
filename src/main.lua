-- Callack's LÖVE presentation shell. It renders only value projections from
-- run_loop; canonical movement, collisions, outcomes, and recordings remain in
-- battle.engine.

local art = require("ui.art_tokens")
local battle_presentation = require("presentation")
local procedural_audio = require("ui.procedural_audio")
local run_loop = require("run_loop")

local PHONE_W = art.logical_surface.phone.width
local PHONE_H = art.logical_surface.phone.height
local DESKTOP_W = art.logical_surface.desktop.width
local DESKTOP_H = art.logical_surface.desktop.height
local P = art.palette

local app
local view
local fonts = {}
local audio_bank
local focused_action_id
local pressed_action_id
local drag_action_id
local drag_start_x
local drag_start_y
local touch_guard_until = 0
local recent_touches = {}
local last_pointer_press
local last_screen
local last_cue = "Scout the first rival, arrange three bricks, and order two marbles."
local last_rule_callout
local screen_age = 0
local offer_age = 0
local last_offer_id
local camera = { x = 0, y = 0, age = 1, life = 0 }
local particles = {}
local trails = {}
local telemetry_tick = -100
local last_guidance_signature
local verification_mode = false

local COLORS = {
    shadow = P.shadow.rgb,
    ink = P.paper_ink.rgb,
    walnut = P.walnut_900.rgb,
    walnut_mid = P.walnut_700.rgb,
    walnut_light = P.walnut_500.rgb,
    felt = P.felt_900.rgb,
    felt_mid = P.felt_700.rgb,
    felt_light = P.felt_500.rgb,
    paper = P.paper_100.rgb,
    paper_edge = P.paper_300.rgb,
    chalk = P.chalk.rgb,
    muted = P.muted.rgb,
    brass_dark = P.brass_600.rgb,
    brass_ink = P.brass_ink.rgb,
    brass = P.brass_300.rgb,
    brass_light = P.brass_100.rgb,
    damage = P.damage.rgb,
    restore = P.restore.rgb,
    focus = P.focus.rgb,
    player = P.player_a.rgb,
    opponent = P.player_b.rgb,
    common = P.rarity_common.rgb,
    uncommon = P.rarity_uncommon.rgb,
    rare = P.rarity_rare.rgb,
    epic = P.rarity_epic.rgb,
    legendary = P.rarity_legendary.rgb,
    specialized = P.brass_300.rgb,
    basic = P.family_basic.rgb,
    defensive = P.family_defensive.rgb,
    effect = P.family_effect.rgb,
    utility = P.family_utility.rgb,
}

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function set_color(color, alpha)
    love.graphics.setColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function tint(color, factor)
    return {
        clamp(color[1] * factor, 0, 1),
        clamp(color[2] * factor, 0, 1),
        clamp(color[3] * factor, 0, 1),
    }
end

local function cubic_out(value)
    value = clamp(value, 0, 1)
    return 1 - (1 - value) ^ 3
end

local function mode()
    local width, height = love.graphics.getDimensions()
    if width >= 900 and width / math.max(1, height) >= 1.15 then return "desktop" end
    return "phone"
end

local function base_size()
    if mode() == "desktop" then return DESKTOP_W, DESKTOP_H end
    return PHONE_W, PHONE_H
end

local function screen_frame()
    local width, height = love.graphics.getDimensions()
    local base_width, base_height = base_size()
    local scale = math.min(width / base_width, height / base_height)
    return scale, (width - base_width * scale) / 2, (height - base_height * scale) / 2
end

local function to_base(x, y)
    local scale, offset_x, offset_y = screen_frame()
    return (x - offset_x) / scale, (y - offset_y) / scale
end

local function action_by_id(id)
    for _, action in ipairs(view.actions or {}) do
        if action.id == id then return action end
    end
    return nil
end

local function index_by_action(items, id)
    for index, item in ipairs(items or {}) do
        if item.action_id == id then return index, item end
    end
    return nil
end

local function desktop_action_bounds(action)
    local id = action.id
    if view.screen == "draft" then
        local index = index_by_action(view.draft.cards, id)
        if index then return 308 + (index - 1) * 316, 120, 296, 456 end
        if id == "inspection_prev" then return 836, 592, 112, 56 end
        if id == "inspection_close" then return 308, 592, 156, 56 end
        if id == "inspection_next" then return 960, 592, 112, 56 end
        if id:match("^select:") then return 770, 704, 220, 56 end
        if id == "confirm_offer" then return 1012, 704, 220, 56 end
    elseif view.screen == "setup" then
        local brick_index = index_by_action(view.setup.bricks, id)
        if brick_index then
            return 40 + ((brick_index - 1) % 2) * 128,
                132 + math.floor((brick_index - 1) / 2) * 112,
                112, 96
        end
        local marble_index = index_by_action(view.setup.bag, id)
        if marble_index then return 990, 164 + (marble_index - 1) * 92, 238, 64 end
        if id == "slot:tail" then return 1176, 532, 56, 48 end
        local slot_index = index_by_action(view.setup.insertion_slots, id)
        if slot_index then return 1176, 172 + (slot_index - 1) * 92, 56, 48 end
        local row, col = id:match("^cell:(%d+):(%d+)$")
        if row then
            return 356 + (tonumber(col) - 1) * 80,
                220 + (tonumber(row) - 1) * 80,
                72, 72
        end
        if id == "lock_setup" then return 1012, 704, 220, 56 end
    elseif view.screen == "battle" then
        local controls = {
            battle_pause = { 760, 704, 112, 56 },
            battle_speed = { 884, 704, 112, 56 },
            battle_mute = { 1008, 704, 112, 56 },
            battle_motion = { 1132, 704, 124, 56 },
        }
        if controls[id] then return unpack(controls[id]) end
        if id == "inspection_prev" then return 560, 580, 72, 48 end
        if id == "inspection_next" then return 648, 580, 72, 48 end
        local entity_id = id:match("^entity:(.+)$")
        if entity_id and view.battle.frame then
            for _, entity in ipairs(view.battle.frame.entities or {}) do
                if tostring(entity.id or entity.uid) == entity_id then
                    local x = 40 + entity.y / view.battle.frame.arena.height * 1200
                    local y = 112 + entity.x / view.battle.frame.arena.width * 536
                    return x - 24, y - 24, 48, 48
                end
            end
        end
    elseif view.screen == "result" then
        if id == "new_run" then return 1012, 704, 220, 56 end
        if id == "review_battle" then return 760, 704, 116, 56 end
        if id == "replay_battle" then return 888, 704, 112, 56 end
    elseif view.screen == "replay" then
        if id == "replay_next" then return 1008, 704, 112, 56 end
        if id == "replay_close" then return 1132, 704, 124, 56 end
    end
    local bounds = action.bounds or {}
    return bounds.x or 0, bounds.y or 0, bounds.width or 48, bounds.height or 48
end

local function action_bounds(action)
    if mode() == "desktop" then return desktop_action_bounds(action) end
    local bounds = action and action.bounds or {}
    return bounds.x or 0, bounds.y or 0, bounds.width or 48, bounds.height or 48
end

local function report_action(action)
    print(string.format(
        "CALLACK_ACTION %s seed=%d phase=%s",
        action,
        view.run_seed,
        view.screen
    ))
end

local function update_title()
    love.window.setTitle(string.format(
        "Callack | %s | Seed %d",
        string.upper(view.screen),
        view.run_seed
    ))
end

local function telemetry_value(value)
    return tostring(value or "none"):gsub("%s+", "_"):gsub("[^%w_%-%.]", "")
end

local function telemetry_tags(tags, counted)
    local out = {}
    for _, tag in ipairs(tags or {}) do
        local value = telemetry_value(tag.id or tag.label)
        if counted then value = value .. "x" .. tostring(tag.count or 1) end
        out[#out + 1] = value
    end
    return #out > 0 and table.concat(out, ",") or "none"
end

local function telemetry_rule(inspection)
    local rule = inspection and inspection.rule or {}
    local trigger = rule.trigger or {}
    local target = rule.target or {}
    local magnitude = rule.magnitude or {}
    local cadence = rule.cadence or {}
    local drawback = inspection and inspection.drawback or {}
    return string.format(
        "rule=%s page=%d/%d trigger=%s target=%s icon=%s verb=%s magnitude=%s_%s limit=%s drawback=%s",
        telemetry_value(rule.id),
        inspection and inspection.index or 0,
        inspection and inspection.count or 0,
        telemetry_value(trigger.event),
        telemetry_value(target.selector),
        telemetry_value(rule.icon),
        telemetry_value(rule.verb),
        telemetry_value(magnitude.value),
        telemetry_value(magnitude.unit),
        telemetry_value(cadence.label),
        telemetry_value(drawback.label)
    )
end

local function report_guidance()
    local signature
    if view.screen == "draft" and view.draft then
        local counter_cards = 0
        local mechanic_cards = 0
        for _, card in ipairs(view.draft.cards or {}) do
            if #(card.mechanics or {}) > 0 then mechanic_cards = mechanic_cards + 1 end
            if card.synergy and #(card.synergy.counters or {}) > 0 then
                counter_cards = counter_cards + 1
            end
        end
        signature = string.format(
            "screen=draft rival=%s scout=%s pressure=%s counter_cards=%d mechanic_cards=%d offer=%s",
            telemetry_value(view.opponent and view.opponent.name),
            telemetry_tags(view.draft.scout_tags),
            telemetry_value(view.opponent
                and view.opponent.pressure
                and view.opponent.pressure[1]
                and view.opponent.pressure[1].name),
            counter_cards,
            mechanic_cards,
            telemetry_value(view.draft.offer_id)
        )
    elseif view.screen == "setup" and view.setup then
        local active_links = 0
        for _, link in ipairs(view.setup.adjacencies or {}) do
            if link.active_synergy then active_links = active_links + 1 end
        end
        signature = string.format(
            "screen=setup rival=%s scout=%s pressure=%s build=%s active_links=%d",
            telemetry_value(view.opponent and view.opponent.name),
            telemetry_tags(view.opponent and view.opponent.scout_tags),
            telemetry_value(view.opponent
                and view.opponent.pressure
                and view.opponent.pressure[1]
                and view.opponent.pressure[1].name),
            telemetry_tags(view.setup.build_tags, true),
            active_links
        )
    end
    if signature and signature ~= last_guidance_signature then
        last_guidance_signature = signature
        print("CALLACK_GUIDANCE " .. signature)
    end
end

local function refresh_view()
    view = run_loop.project(app)
    if last_screen ~= view.screen then
        last_screen = view.screen
        screen_age = 0
        trails = {}
        if view.screen == "battle" then last_rule_callout = nil end
        update_title()
        report_action("phase_" .. view.screen)
    end
    local offer_id = view.draft and view.draft.offer_id
    if offer_id and offer_id ~= last_offer_id then
        last_offer_id = offer_id
        offer_age = 0
    end
    report_guidance()
end

local function setting_read(name, default)
    local info_ok, info = pcall(love.filesystem.getInfo, name)
    if not info_ok or not info then return default end
    local ok, value = pcall(love.filesystem.read, name)
    if ok and value then return value == "true" end
    return default
end

local function setting_write(name, value)
    pcall(love.filesystem.write, name, value and "true" or "false")
end

local function audio_unlock()
    if audio_bank then procedural_audio.unlock(audio_bank) end
end

local function sync_settings()
    if audio_bank then procedural_audio.set_muted(audio_bank, app.model.ui.muted) end
    setting_write("muted.setting", app.model.ui.muted)
    setting_write("reduced-motion.setting", app.model.ui.reduced_motion)
end

local function activate(action_id, source)
    if view.enabled_actions[action_id] ~= true then return false end
    audio_unlock()
    local accepted, action_error = run_loop.activate(app, action_id, source)
    if not accepted then
        last_cue = action_error and action_error.message or "That action is unavailable."
        report_action("rejected_" .. action_id)
        return false
    end
    focused_action_id = action_id
    refresh_view()
    local inspected_choice = action_id:match("^offer:")
        and view.draft and view.draft.inspected or nil
    if inspected_choice then
        print(string.format(
            "CALLACK_INSPECTION type=choice source=%s name=%s mechanics=%d operation=%s cause=%s counters=%s links=%s adds=%s %s",
            telemetry_value(source),
            telemetry_value(inspected_choice.name),
            #(inspected_choice.mechanics or {}),
            telemetry_value(inspected_choice.operation
                and inspected_choice.operation.kind),
            telemetry_value(inspected_choice.causal_attribution
                and inspected_choice.causal_attribution.cause),
            telemetry_tags(inspected_choice.synergy and inspected_choice.synergy.counters),
            telemetry_tags(inspected_choice.synergy and inspected_choice.synergy.matched),
            telemetry_tags(inspected_choice.synergy and inspected_choice.synergy.introduced),
            telemetry_rule(inspected_choice.rule_inspection)
        ))
    end
    local inspected_entity = action_id:match("^entity:")
        and view.battle and view.battle.inspected or nil
    if inspected_entity then
        print(string.format(
            "CALLACK_INSPECTION type=entity source=%s id=%s name=%s owner=%s mechanic=%s %s",
            telemetry_value(source),
            telemetry_value(inspected_entity.entity_id),
            telemetry_value(inspected_entity.name),
            telemetry_value(inspected_entity.owner_name),
            telemetry_value(inspected_entity.mechanic
                or inspected_entity.core
                or inspected_entity.state),
            telemetry_rule(inspected_entity.rule_inspection)
        ))
    end
    if action_id == "battle_mute" or action_id == "battle_motion" then
        sync_settings()
        print(string.format(
            "CALLACK_SETTING muted=%s reduced_motion=%s source=%s",
            tostring(app.model.ui.muted),
            tostring(app.model.ui.reduced_motion),
            tostring(source)
        ))
    end
    if audio_bank and action_id ~= "battle_mute" then
        procedural_audio.play(audio_bank, "ui_select")
    end
    report_action(action_id)
    return true
end

local function enabled_actions()
    local out = {}
    for _, action in ipairs(view.actions or {}) do
        if action.enabled then out[#out + 1] = action end
    end
    return out
end

local function move_focus(delta)
    local actions = enabled_actions()
    if #actions == 0 then focused_action_id = nil return end
    local selected = 1
    for index, action in ipairs(actions) do
        if action.id == focused_action_id then selected = index break end
    end
    selected = ((selected - 1 + delta) % #actions) + 1
    focused_action_id = actions[selected].id
end

local function draw_walnut(width, height)
    set_color(COLORS.walnut)
    love.graphics.rectangle("fill", 0, 0, width, height)
    love.graphics.setLineWidth(2)
    for line = 0, 18 do
        local y = (line * 53 + 17) % height
        local bend = ((line * 29) % 17) - 8
        set_color(line % 3 == 0 and COLORS.walnut_light or COLORS.walnut_mid, 0.16)
        love.graphics.line(0, y, width * 0.32, y + bend, width * 0.68, y - bend, width, y + 2)
    end
    love.graphics.setLineWidth(1)
end

local function panel(x, y, width, height, surface, radius)
    radius = radius or 14
    set_color(COLORS.shadow, 0.42)
    love.graphics.rectangle("fill", x + 3, y + 5, width, height, radius, radius)
    local fill = surface == "paper" and COLORS.paper
        or surface == "walnut" and COLORS.walnut_mid
        or COLORS.felt
    local edge = surface == "paper" and COLORS.paper_edge
        or surface == "walnut" and COLORS.brass_dark
        or COLORS.felt_light
    set_color(fill)
    love.graphics.rectangle("fill", x, y, width, height, radius, radius)
    set_color(edge, 0.88)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, radius, radius)
    if surface == "felt" and width > 100 and height > 60 then
        set_color(COLORS.chalk, art.material.felt.fibre_alpha)
        for index = 1, 18 do
            local fx = x + 9 + ((index * 47) % math.max(10, math.floor(width - 18)))
            local fy = y + 9 + ((index * 31) % math.max(10, math.floor(height - 18)))
            love.graphics.line(fx, fy, fx + 3 + index % 3, fy + (index % 2))
        end
    end
end

local function draw_beads(rarity, x, y, direction)
    local rarity_token = art.rarity[rarity] or art.rarity.common
    local color = COLORS[rarity] or COLORS.common
    for index = 1, rarity_token.beads do
        set_color(color)
        love.graphics.circle("fill", x + (index - 1) * 9 * (direction or 1), y, 3)
        set_color(COLORS.shadow, 0.45)
        love.graphics.circle("line", x + (index - 1) * 9 * (direction or 1), y, 3)
    end
end

local function infer_mineral(text)
    text = string.lower(tostring(text or ""))
    for _, mineral in ipairs({ "jade", "obsidian", "quartz", "flint", "silver", "granite", "chalk" }) do
        if text:find(mineral, 1, true) then return mineral end
    end
    return "quartz"
end

local function mineral_color(mineral)
    local token = art.material.mineral[mineral or "quartz"] or art.material.mineral.quartz
    return token.base.rgb, token.pattern
end

local function draw_marble(x, y, radius, rarity, mineral, shell_ratio, statuses, show_beads)
    radius = math.max(6, radius)
    local base, pattern = mineral_color(mineral)
    local rarity_color = COLORS[rarity] or COLORS.common
    shell_ratio = clamp(shell_ratio == nil and 1 or shell_ratio, 0, 1)
    set_color(COLORS.shadow, art.material.glass.shadow_alpha)
    love.graphics.circle("fill", x + radius * 0.16, y + radius * 0.22, radius * 1.04)
    set_color(COLORS.brass_dark, 0.9)
    love.graphics.circle("fill", x, y, radius * 0.46)
    set_color(COLORS.brass_light, 0.54)
    love.graphics.circle("line", x, y, radius * 0.28)
    set_color(base, art.material.glass.body_alpha * (0.48 + shell_ratio * 0.52))
    love.graphics.circle("fill", x, y, radius)
    set_color(rarity_color, art.material.glass.edge_alpha)
    love.graphics.setLineWidth((art.rarity[rarity] or art.rarity.common).rim_width)
    love.graphics.circle("line", x, y, radius - 1)
    set_color(COLORS.chalk, art.material.glass.inner_alpha)
    love.graphics.circle("line", x, y, radius * 0.68)
    set_color(COLORS.chalk, art.material.glass.highlight_alpha)
    love.graphics.setLineWidth(math.max(1, radius * 0.10))
    love.graphics.arc("line", x, y, radius * 0.72, 3.55, 4.82)
    love.graphics.setLineWidth(1)
    if pattern == "banded" then
        set_color(COLORS.ink, 0.20)
        love.graphics.arc("line", x, y, radius * 0.48, 0.1, 2.8)
    elseif pattern == "shard" then
        set_color(COLORS.chalk, 0.28)
        love.graphics.line(x - radius * 0.45, y + radius * 0.25, x + radius * 0.32, y - radius * 0.36)
    elseif pattern == "lattice" then
        set_color(COLORS.ink, 0.17)
        love.graphics.line(x - radius * 0.42, y, x + radius * 0.42, y)
        love.graphics.line(x, y - radius * 0.42, x, y + radius * 0.42)
    end
    if statuses and statuses.poison then
        set_color(P.status_poison.rgb)
        love.graphics.circle("fill", x - radius * 0.62, y + radius * 0.56, 3)
        love.graphics.circle("line", x - radius * 0.42, y + radius * 0.70, 2)
    end
    if statuses and statuses.freeze then
        set_color(P.status_freeze.rgb)
        for index = 0, 2 do
            local angle = index * math.pi * 2 / 3
            love.graphics.line(
                x + math.cos(angle) * radius * 0.74,
                y + math.sin(angle) * radius * 0.74,
                x + math.cos(angle) * radius,
                y + math.sin(angle) * radius
            )
        end
    end
    if show_beads ~= false then
        draw_beads(rarity or "common", x - radius * 0.52, y + radius + 5)
    end
end

local FAMILY_MINERAL = {
    basic = "granite",
    defensive = "jade",
    effect = "obsidian",
    utility = "flint",
    rare = "silver",
}

local function draw_brick(x, y, width, height, family, behaviour, hp_ratio, selected)
    family = family or "basic"
    behaviour = behaviour or "inert"
    local mineral = FAMILY_MINERAL[family] or "granite"
    local base, pattern = mineral_color(mineral)
    local edge = COLORS[family] or COLORS.basic
    hp_ratio = clamp(hp_ratio == nil and 1 or hp_ratio, 0, 1)
    set_color(COLORS.shadow, 0.42)
    love.graphics.rectangle("fill", x + 2, y + 3, width, height, 4, 4)
    set_color(tint(base, 0.58 + hp_ratio * 0.42))
    love.graphics.rectangle("fill", x, y, width, height, 4, 4)
    set_color(tint(base, 1.22), 0.72)
    love.graphics.line(x + 3, y + 3, x + width - 3, y + 3)
    love.graphics.line(x + 3, y + 3, x + 3, y + height - 3)
    set_color(selected and COLORS.focus or edge)
    love.graphics.setLineWidth(selected and 3 or 1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, 4, 4)
    love.graphics.setLineWidth(1)
    set_color(COLORS.ink, 0.22)
    if pattern == "mottled" then
        for index = 1, 4 do
            love.graphics.circle("fill", x + ((index * 19) % math.max(8, width - 8)) + 4,
                y + ((index * 13) % math.max(8, height - 8)) + 4, 1.5)
        end
    elseif pattern == "lattice" then
        love.graphics.line(x + width * 0.24, y + 4, x + width * 0.56, y + height - 4)
        love.graphics.line(x + width * 0.58, y + 4, x + width * 0.82, y + height - 4)
    elseif pattern == "shard" then
        love.graphics.line(x + 4, y + height - 5, x + width * 0.48, y + 5, x + width - 4, y + height * 0.62)
    elseif pattern == "spiral" then
        love.graphics.arc("line", x + width / 2, y + height / 2,
            math.min(width, height) * 0.27, 0.2, 5.6)
    elseif pattern == "veined" then
        love.graphics.line(x + 4, y + height * 0.65, x + width * 0.36, y + height * 0.28,
            x + width * 0.70, y + height * 0.54, x + width - 4, y + height * 0.22)
    end
    local token = art.behaviour[behaviour] or art.behaviour.inert
    love.graphics.setFont(fonts.micro)
    set_color((mineral == "silver" or mineral == "chalk" or mineral == "quartz")
        and COLORS.ink or COLORS.chalk)
    love.graphics.printf(token.label, x + 3, y + height / 2 - 6, width - 6, "center")
    local pips = math.max(1, math.floor(hp_ratio * 4 + 0.5))
    for index = 1, 4 do
        set_color(index <= pips and COLORS.brass_light or COLORS.shadow, index <= pips and 0.9 or 0.35)
        love.graphics.rectangle("fill", x + 4 + (index - 1) * math.max(5, (width - 10) / 4),
            y + height - 5, math.max(3, (width - 16) / 4), 2)
    end
end

local function draw_sling(x, y, scale, label)
    scale = scale or 1
    set_color(COLORS.shadow, 0.4)
    love.graphics.setLineWidth(10 * scale)
    love.graphics.line(x - 24 * scale, y + 28 * scale, x - 15 * scale, y - 22 * scale)
    love.graphics.line(x + 24 * scale, y + 28 * scale, x + 15 * scale, y - 22 * scale)
    set_color(COLORS.walnut_light)
    love.graphics.setLineWidth(7 * scale)
    love.graphics.line(x - 24 * scale, y + 26 * scale, x - 15 * scale, y - 22 * scale)
    love.graphics.line(x + 24 * scale, y + 26 * scale, x + 15 * scale, y - 22 * scale)
    set_color(COLORS.brass)
    love.graphics.setLineWidth(2 * scale)
    love.graphics.line(x - 15 * scale, y - 22 * scale, x, y + 2 * scale, x + 15 * scale, y - 22 * scale)
    love.graphics.circle("fill", x - 15 * scale, y - 22 * scale, 4 * scale)
    love.graphics.circle("fill", x + 15 * scale, y - 22 * scale, 4 * scale)
    set_color(COLORS.brass_dark)
    love.graphics.rectangle("fill", x - 29 * scale, y + 23 * scale, 58 * scale, 9 * scale, 3, 3)
    love.graphics.setLineWidth(1)
    if label and scale >= 0.7 then
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.muted)
        love.graphics.printf(string.upper(label), x - 58 * scale, y + 36 * scale, 116 * scale, "center")
    end
end

local function draw_button(id, label, accent)
    local action = action_by_id(id)
    if not action then return end
    local x, y, width, height = action_bounds(action)
    local enabled = action.enabled
    local color = accent or COLORS.brass
    local pressed = pressed_action_id == id and 2 or 0
    y = y + pressed
    set_color(COLORS.shadow, 0.45)
    love.graphics.rectangle("fill", x + 2, y + 4, width, height, 9, 9)
    set_color(color, enabled and 0.30 or 0.08)
    love.graphics.rectangle("fill", x, y, width, height, 9, 9)
    set_color(enabled and tint(color, 1.18) or COLORS.muted, enabled and 1 or 0.28)
    love.graphics.line(x + 8, y + 4, x + width - 8, y + 4)
    set_color(focused_action_id == id and COLORS.focus or color, enabled and 1 or 0.28)
    love.graphics.setLineWidth(focused_action_id == id and 3 or 2)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, 9, 9)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(fonts.label)
    set_color(enabled and COLORS.chalk or COLORS.muted, enabled and 1 or 0.45)
    love.graphics.printf(string.upper(label or action.label), x + 6, y + height / 2 - 8, width - 12, "center")
end

local function draw_chrome()
    local desktop = mode() == "desktop"
    local x, y, width, height = desktop and 24 or 12, desktop and 16 or 12,
        desktop and 1232 or 366, desktop and 64 or 52
    panel(x, y, width, height, "walnut", 12)
    love.graphics.setFont(fonts.display)
    set_color(COLORS.chalk)
    love.graphics.print("CALLACK", x + 12, y + (desktop and 14 or 8))
    set_color(COLORS.brass)
    love.graphics.setLineWidth(2)
    love.graphics.line(x + 13, y + height - 10, x + (desktop and 174 or 121), y + height - 10)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass)
    love.graphics.printf(view.labels.phase, x + width - 210, y + 12, 194, "right")
    set_color(COLORS.muted)
    love.graphics.printf(view.labels.seed, x + width - 210, y + 34, 194, "right")
end

local function draw_tag_chips(tags, x, y, width)
    local cursor = x
    love.graphics.setFont(fonts.micro)
    for _, tag in ipairs(tags or {}) do
        local label = string.upper(tag.label or tag.id)
        if tag.count then label = label .. " ×" .. tostring(tag.count) end
        local chip_width = math.min(width, math.max(42, fonts.micro:getWidth(label) + 14))
        if cursor + chip_width > x + width then break end
        set_color(COLORS.felt, 0.84)
        love.graphics.rectangle("fill", cursor, y, chip_width, 20, 4, 4)
        set_color(COLORS.brass, 0.76)
        love.graphics.rectangle("line", cursor + 0.5, y + 0.5, chip_width - 1, 19, 4, 4)
        set_color(COLORS.chalk)
        love.graphics.printf(label, cursor + 4, y + 4, chip_width - 8, "center")
        cursor = cursor + chip_width + 6
    end
end

local function tag_labels(tags, limit)
    local labels = {}
    for index, tag in ipairs(tags or {}) do
        if limit and index > limit then break end
        labels[#labels + 1] = string.upper(tag.label or tag.id)
    end
    return table.concat(labels, " + ")
end

local function synergy_summary(card)
    local synergy = card and card.synergy or {}
    if #(synergy.counters or {}) > 0 then
        return "COUNTERS SCOUT: " .. tag_labels(synergy.counters, 2), COLORS.restore
    end
    if #(synergy.matched or {}) > 0 then
        return "LINKS BUILD: " .. tag_labels(synergy.matched, 2), COLORS.brass
    end
    if #(synergy.introduced or {}) > 0 then
        return "ADDS LINE: " .. tag_labels(synergy.introduced, 2), COLORS.brass
    end
    return "FLEX PICK", COLORS.muted
end

local function canonical_choice_copy(card)
    local mechanics = card.compact_copy
    if not mechanics or mechanics == "" then
        mechanics = table.concat(card.mechanics or {}, " ")
    end
    if card.operation_copy and card.operation_copy ~= "" then
        return card.operation_copy .. " " .. mechanics
    end
    return mechanics
end

local function choice_cause_summary(card)
    local attribution = card and card.causal_attribution or {}
    local rules = #(attribution.source_rule_ids or {})
    local summary = synergy_summary(card)
    summary = summary:gsub(": ", " "):gsub(" %+", "+")
    summary = summary:gsub("^COUNTERS SCOUT ", "COUNTERS ")
        :gsub("^LINKS BUILD ", "LINKS ")
        :gsub("^ADDS LINE ", "ADDS ")
    return string.format(
        "CAUSE POST-BATTLE / %d RULES / %s",
        rules,
        summary
    )
end

local function draw_wrapped_limited(text, x, y, width, max_lines, alignment)
    local font = love.graphics.getFont()
    local normalized = tostring(text or ""):gsub("[\r\n]+", " ")
    local _, wrapped = font:getWrap(normalized, width)
    local shown = {}
    for index = 1, math.min(#wrapped, max_lines) do
        shown[index] = wrapped[index]
    end
    if #wrapped > max_lines and #shown > 0 then
        shown[#shown] = shown[#shown]:gsub("%s+$", "") .. "..."
    end
    local line_height = font:getHeight() * font:getLineHeight()
    for index, line in ipairs(shown) do
        local line_x = x
        if alignment == "right" then
            line_x = x + width - font:getWidth(line)
        elseif alignment == "center" then
            line_x = x + (width - font:getWidth(line)) / 2
        end
        love.graphics.print(line, line_x, y + (index - 1) * line_height)
    end
    return #shown * line_height
end

local function compact_scout_sling(opponent)
    local sling = string.upper(opponent.sling or "UNKNOWN")
    sling = sling:gsub(" SLING$", "")
    if sling == "EFFECT AMPLIFIER" then sling = "AMPLIFIER" end
    return sling
end

local function compact_scout_tags(opponent)
    local tags = {}
    for index, tag in ipairs(opponent.scout_tags or {}) do
        if index > 2 then break end
        tags[#tags + 1] = string.upper(tag.id or tag.label or "")
    end
    return table.concat(tags, "+")
end

local function scout_loadout_copy(opponent, compact)
    if compact then
        return string.format(
            "%dM/%dB  %s  %s",
            opponent.marble_count or 0,
            opponent.brick_count or 0,
            compact_scout_sling(opponent),
            compact_scout_tags(opponent)
        )
    end
    return string.format(
        "%d MARBLES  /  %d BRICKS  /  %s",
        opponent.marble_count or 0,
        opponent.brick_count or 0,
        string.upper(opponent.sling or "UNKNOWN SLING")
    )
end

local function scout_counts_copy(opponent)
    return string.format(
        "%dM / %dB / %s",
        opponent.marble_count or 0,
        opponent.brick_count or 0,
        compact_scout_sling(opponent)
    )
end

local function scout_mechanic_copy(opponent)
    return compact_scout_sling(opponent) .. " / " .. compact_scout_tags(opponent)
end

local function draw_scout_rows(tags, x, y, width, limit)
    love.graphics.setFont(fonts.micro)
    for index, tag in ipairs(tags or {}) do
        if limit and index > limit then break end
        set_color(COLORS.brass)
        love.graphics.print(string.upper(tag.label or tag.id), x, y + (index - 1) * 36)
        set_color(COLORS.muted)
        local label_width = fonts.micro:getWidth(string.upper(tag.label or tag.id)) + 10
        love.graphics.printf("— " .. tostring(tag.description or ""), x + label_width,
            y + (index - 1) * 36, width - label_width, "left")
    end
end

local function draw_draft_card(card, x, y, width, height, large, index)
    local rarity = card.rarity
    local rarity_color = COLORS[rarity] or COLORS.common
    local delay = (index - 1) * art.motion.card_stagger
    local deal = app.model.ui.reduced_motion and 1
        or cubic_out((offer_age - delay) / art.motion.card_deal)
    y = y + (1 - deal) * 12
    local alpha = app.model.ui.reduced_motion and 1 or deal
    set_color(COLORS.shadow, 0.42 * alpha)
    love.graphics.rectangle("fill", x + 4, y + 6, width, height, 12, 12)
    set_color(COLORS.paper, alpha)
    love.graphics.rectangle("fill", x, y, width, height, 12, 12)
    set_color(COLORS.paper_edge, alpha)
    love.graphics.rectangle("line", x + 3.5, y + 3.5, width - 7, height - 7, 9, 9)
    set_color(rarity_color, alpha)
    love.graphics.rectangle("fill", x, y, 5, height, 12, 0)
    love.graphics.setLineWidth(card.inspected and 3 or 1)
    set_color(card.inspected and COLORS.focus or rarity_color, alpha)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, 12, 12)
    love.graphics.setLineWidth(1)

    local art_x = large and x + width / 2 or x + 48
    local art_y = large and y + 112 or y + height / 2
    local art_scale = large and 1.65 or 0.88
    local category = card.category or view.draft.category
    if category == "sling" then
        draw_sling(art_x, art_y, art_scale)
    elseif category == "marble" then
        local first_shell = card.details and card.details.shells
            and card.details.shells[1] or nil
        draw_marble(art_x, art_y, large and 68 or 38, rarity,
            first_shell and first_shell.mineral or infer_mineral(card.art_id), 1)
    else
        local bricks = card.details and card.details.bricks or {}
        local first = bricks[1] or { family = "defensive", behaviour = "fortify" }
        local second = bricks[2] or { family = "effect", behaviour = "shatter" }
        local brick_width = large and 94 or 58
        local brick_height = large and 58 or 34
        draw_brick(art_x - brick_width / 2 - (large and 10 or 0),
            art_y - brick_height / 2 - (large and 8 or 10),
            brick_width, brick_height, first.family, first.behaviour, 1)
        draw_brick(art_x - brick_width / 2 + (large and 10 or 0),
            art_y - brick_height / 2 + (large and 24 or 14),
            brick_width, brick_height, second.family, second.behaviour, 1)
    end

    local text_x = large and x + 18 or x + 94
    local text_y = large and y + 210 or y + 14
    local text_width = large and width - 36 or width - 108
    love.graphics.setFont(fonts.card)
    set_color(COLORS.ink, alpha)
    love.graphics.printf(card.name, text_x, text_y, text_width, large and "center" or "left")
    love.graphics.setFont(fonts.meta)
    set_color(COLORS.ink, 0.72 * alpha)
    love.graphics.printf(
        string.upper(card.operation_verb or card.role or category)
            .. "  /  " .. string.upper(rarity or category or "kit"),
        text_x, text_y + 26, text_width, large and "center" or "left"
    )
    local comparison = card.comparison or {}
    local primary = comparison.primary_rule or {}
    local lines = primary.comparison_lines or {}
    love.graphics.setFont(large and fonts.meta or fonts.micro)
    set_color(COLORS.brass_ink, alpha)
    love.graphics.printf(comparison.operation or "", text_x, text_y + 52,
        text_width, large and "center" or "left")
    set_color(COLORS.ink, alpha)
    love.graphics.printf(lines[1] or "INSPECT FOR CANONICAL RULES",
        text_x, text_y + (large and 88 or 72), text_width,
        large and "center" or "left")
    love.graphics.printf(lines[2] or "",
        text_x, text_y + (large and 116 or 91), text_width,
        large and "center" or "left")
    if large then
        local summary, summary_color = synergy_summary(card)
        if summary_color == COLORS.brass then summary_color = COLORS.brass_dark end
        if summary_color == COLORS.restore then summary_color = COLORS.felt_mid end
        love.graphics.setFont(fonts.micro)
        set_color(summary_color, alpha)
        love.graphics.printf(string.format("%d RULES  /  %s",
            comparison.rule_count or 0, summary),
            text_x, y + height - 73, text_width, "left")
    end
    draw_tag_chips(card.tags, text_x, large and y + height - 48 or y + height - 30, text_width)
    draw_beads(rarity or "common", x + width - 16, y + 16, -1)
    if card.selected then
        set_color(COLORS.focus)
        love.graphics.setFont(fonts.label)
        love.graphics.printf("CHOSEN", x + width - 90, y + height - 27, 76, "right")
    end
end

local function draw_pick_progress(x, y, width)
    panel(x, y, width, 28, "walnut", 7)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.muted)
    if view.draft.refit then
        love.graphics.print(string.format("FIGHT %d CLEARED", view.draft.progress.fight),
            x + 10, y + 8)
        set_color(COLORS.brass)
        love.graphics.printf(string.format("M %d/%d  •  B %d/%d  •  REPAIR %d",
            view.draft.progress.marbles,
            view.draft.progress.marble_cap,
            view.draft.progress.bricks,
            view.draft.progress.brick_cap,
            view.draft.progress.broken),
            x + 128, y + 8, width - 138, "right")
    else
        love.graphics.print(string.format("PICK %d / %d", view.draft.progress.total + 1,
            view.draft.progress.required), x + 10, y + 8)
        set_color(COLORS.brass)
        love.graphics.printf(string.format("S %d/1  •  M %d/4  •  K %d/4",
            view.draft.progress.sling,
            view.draft.progress.marbles,
            view.draft.progress.brick_kits),
            x + 104, y + 8, width - 114, "right")
    end
end

local function draw_rule_mark(rule, x, y, size, paper_surface)
    local fill = paper_surface and COLORS.brass_ink or COLORS.brass
    local ink = paper_surface and COLORS.paper or COLORS.ink
    set_color(COLORS.shadow, 0.30)
    love.graphics.circle("fill", x + 2, y + 3, size / 2)
    set_color(fill)
    love.graphics.circle("fill", x, y, size / 2)
    set_color(paper_surface and COLORS.paper_edge or COLORS.brass_light)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", x, y, size / 2 - 2)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(size >= 52 and fonts.label or fonts.micro)
    set_color(ink)
    love.graphics.printf(rule and rule.icon or "RUL",
        x - size / 2, y - (size >= 52 and 8 or 6), size, "center")
end

local function draw_exact_row(label, value, x, y, width, paper_surface)
    love.graphics.setFont(fonts.micro)
    set_color(paper_surface and COLORS.brass_ink or COLORS.brass)
    love.graphics.print(string.upper(label), x, y)
    local label_width = 76
    set_color(paper_surface and COLORS.ink or COLORS.chalk)
    love.graphics.printf(tostring(value or "NONE"), x + label_width, y,
        width - label_width, "left")
end

local function inspection_effect_copy(rule)
    return string.format(
        "%s %s / %s / %s",
        rule.verb_label or tostring(rule.verb):upper(),
        rule.magnitude and rule.magnitude.label or "NONE",
        tostring(rule.stat or "none"):upper():gsub("_", " "),
        tostring(rule.mode or "set"):upper()
    )
end

local function inspection_trigger_copy(rule)
    local trigger = rule.trigger or {}
    return string.format(
        "%s / IF %s",
        trigger.label or "NONE",
        tostring(trigger.condition or "always"):upper():gsub("_", " ")
    )
end

local function inspection_target_copy(rule)
    local target = rule.target or {}
    local copy = target.label or "NONE"
    if target.relation then
        copy = copy .. " / " .. tostring(target.relation):upper():gsub("_", " ")
    end
    return copy
end

local function draw_pressure_preview(pressure, x, y, width, paper_surface)
    if not pressure then return end
    love.graphics.setFont(fonts.micro)
    set_color(paper_surface and COLORS.brass_ink or COLORS.brass)
    love.graphics.print("SCOUT PRESSURE  /  "
        .. string.upper(pressure.name or pressure.kind or "UNKNOWN"), x, y)
    set_color(paper_surface and COLORS.ink or COLORS.muted)
    draw_wrapped_limited(pressure.compact_copy, x, y + 18, width, 4, "left")
end

local function draw_draft_inspection_phone(card)
    local inspection = card.rule_inspection
    local rule = inspection and inspection.rule or {}
    panel(16, 108, 358, 588, "paper", 14)
    love.graphics.setFont(fonts.section)
    set_color(COLORS.ink)
    love.graphics.print(string.upper(card.name), 30, 124)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass_ink)
    love.graphics.printf(string.format(
        "%s  /  RULE %d OF %d",
        string.upper(card.operation_verb or card.role or "CHOICE"),
        inspection and inspection.index or 0,
        inspection and inspection.count or 0
    ), 190, 130, 168, "right")
    love.graphics.setFont(fonts.meta)
    set_color(COLORS.ink)
    draw_wrapped_limited(card.operation_copy, 30, 160, 328, 3, "left")
    set_color(COLORS.paper_edge)
    love.graphics.rectangle("fill", 30, 214, 328, 2)
    draw_rule_mark(rule, 54, 250, 44, true)
    love.graphics.setFont(fonts.label)
    set_color(COLORS.brass_ink)
    love.graphics.print(rule.verb_label or "CANONICAL RULE", 86, 231)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.ink, 0.72)
    love.graphics.printf(inspection and inspection.rule_set_id or "",
        86, 252, 272, "left")
    draw_exact_row("TRIGGER", inspection_trigger_copy(rule), 30, 290, 328, true)
    draw_exact_row("TARGET", inspection_target_copy(rule), 30, 324, 328, true)
    draw_exact_row("EFFECT", inspection_effect_copy(rule), 30, 358, 328, true)
    draw_exact_row("LIMIT", rule.cadence and rule.cadence.label, 30, 392, 328, true)
    draw_exact_row("DRAWBACK", inspection and inspection.drawback.label,
        30, 426, 328, true)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass_ink)
    love.graphics.print("GENERATED RULE", 30, 468)
    set_color(COLORS.ink)
    draw_wrapped_limited(rule.sentence, 30, 486, 328, 4, "left")
    local summary = synergy_summary(card)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.felt_mid)
    love.graphics.printf(summary, 30, 558, 328, "left")
    local pressure = view.opponent.pressure and view.opponent.pressure[1]
    draw_pressure_preview(pressure, 30, 580, 328, true)
    draw_button("inspection_prev", "PREV", COLORS.brass)
    draw_button("inspection_close", "CLOSE", COLORS.brass)
    draw_button("inspection_next", "NEXT", COLORS.brass)
end

local function draw_draft_inspection_desktop(card)
    local inspection = card.rule_inspection
    local rule = inspection and inspection.rule or {}
    panel(288, 96, 968, 568, "paper", 16)
    love.graphics.setFont(fonts.display)
    set_color(COLORS.ink)
    love.graphics.print(string.upper(card.name), 320, 126)
    love.graphics.setFont(fonts.label)
    set_color(COLORS.brass_ink)
    love.graphics.print(string.format(
        "%s  /  %d CANONICAL RULES",
        string.upper(card.operation_verb or card.role or "CHOICE"),
        inspection and inspection.count or 0
    ), 320, 172)
    draw_rule_mark(rule, 378, 246, 76, true)
    love.graphics.setFont(fonts.section)
    set_color(COLORS.brass_ink)
    love.graphics.print(rule.verb_label or "CANONICAL RULE", 438, 218)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.ink, 0.68)
    love.graphics.printf(inspection and inspection.rule_set_id or "",
        438, 250, 194, "left")
    love.graphics.setFont(fonts.body)
    set_color(COLORS.ink)
    draw_wrapped_limited(card.operation_copy, 320, 314, 312, 5, "left")
    local summary = synergy_summary(card)
    love.graphics.setFont(fonts.label)
    set_color(COLORS.felt_mid)
    love.graphics.printf(summary, 320, 410, 312, "left")
    draw_pressure_preview(
        view.opponent.pressure and view.opponent.pressure[1],
        320, 448, 312, true
    )

    set_color(COLORS.paper_edge)
    love.graphics.rectangle("fill", 656, 124, 2, 496)
    love.graphics.setFont(fonts.section)
    set_color(COLORS.ink)
    love.graphics.print(string.format(
        "RULE %d OF %d  /  %s",
        inspection and inspection.index or 0,
        inspection and inspection.count or 0,
        rule.verb_label or "RULE"
    ), 692, 132)
    draw_exact_row("TRIGGER", inspection_trigger_copy(rule), 692, 198, 516, true)
    draw_exact_row("TARGET", inspection_target_copy(rule), 692, 244, 516, true)
    draw_exact_row("EFFECT", inspection_effect_copy(rule), 692, 290, 516, true)
    draw_exact_row("LIMIT", rule.cadence and rule.cadence.label, 692, 336, 516, true)
    draw_exact_row("DRAWBACK", inspection and inspection.drawback.label,
        692, 382, 516, true)
    love.graphics.setFont(fonts.label)
    set_color(COLORS.brass_ink)
    love.graphics.print("GENERATED RULE", 692, 438)
    love.graphics.setFont(fonts.body)
    set_color(COLORS.ink)
    draw_wrapped_limited(rule.sentence, 692, 468, 516, 5, "left")
    draw_button("inspection_prev", "PREVIOUS", COLORS.brass)
    draw_button("inspection_close", "CLOSE RULES", COLORS.brass)
    draw_button("inspection_next", "NEXT", COLORS.brass)
end

local function draw_draft_phone()
    draw_chrome()
    draw_pick_progress(16, 72, 358)
    if view.draft.inspected then
        draw_draft_inspection_phone(view.draft.inspected)
    else
        for index, card in ipairs(view.draft.cards) do
            local x, y, width, height = action_bounds(action_by_id(card.action_id))
            draw_draft_card(card, x, y, width, height, false, index)
        end
        panel(16, 584, 358, 112, "felt", 12)
        love.graphics.setFont(fonts.label)
        set_color(COLORS.brass)
        love.graphics.print("RIVAL SCOUT  /  " .. string.upper(view.opponent.name), 28, 594)
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.opponent)
        love.graphics.print(scout_loadout_copy(view.opponent), 28, 614)
        draw_pressure_preview(
            view.opponent.pressure and view.opponent.pressure[1],
            28, 636, 334, false
        )
    end
    if view.draft.inspected then
        draw_button("select:" .. view.draft.inspected.choice_id,
            view.draft.selected_choice_id and "CHOICE SET" or "CHOOSE " .. view.draft.inspected.name,
            COLORS.brass)
    else
        love.graphics.setFont(fonts.meta)
        set_color(COLORS.muted)
        love.graphics.printf("Tap a card for exact trigger, target, effect, limit, and drawback.",
            16, 722, 358, "center")
    end
    local selected_name = "CHOOSE AN OFFER"
    for _, card in ipairs(view.draft.cards) do
        if card.choice_id == view.draft.selected_choice_id then
            selected_name = "CONFIRM " .. card.name
        end
    end
    draw_button("confirm_offer", selected_name, COLORS.player)
end

local function draw_draft_desktop()
    draw_chrome()
    panel(24, 96, 240, 568, "felt", 16)
    love.graphics.setFont(fonts.section)
    set_color(COLORS.chalk)
    love.graphics.print("RIVAL SCOUT", 44, 118)
    love.graphics.setFont(fonts.label)
    set_color(COLORS.opponent)
    love.graphics.print(string.upper(view.opponent.name), 44, 154)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass)
    love.graphics.printf(scout_counts_copy(view.opponent), 44, 176, 200, "left")
    love.graphics.setFont(fonts.body)
    set_color(COLORS.muted)
    love.graphics.printf(view.opponent.description, 44, 200, 200, "left")
    draw_pressure_preview(
        view.opponent.pressure and view.opponent.pressure[1],
        44, 270, 200, false
    )
    draw_tag_chips(view.draft.scout_tags, 44, 354, 200)
    love.graphics.setFont(fonts.label)
    set_color(COLORS.chalk)
    love.graphics.print("YOUR COLLECTION", 44, 390)
    local totals = view.draft.refit and {
        { "SLING", 1, 1 },
        { "MARBLES", view.draft.progress.marbles, view.draft.progress.marble_cap },
        { "BRICKS", view.draft.progress.bricks, view.draft.progress.brick_cap },
    } or {
        { "SLING", view.draft.progress.sling, 1 },
        { "MARBLES", view.draft.progress.marbles, 4 },
        { "BRICK KITS", view.draft.progress.brick_kits, 4 },
    }
    for index, item in ipairs(totals) do
        local y = 420 + (index - 1) * 64
        set_color(COLORS.brass_dark, 0.62)
        love.graphics.rectangle("fill", 44, y, 200, 52, 10, 10)
        set_color(COLORS.brass)
        love.graphics.rectangle("line", 44.5, y + 0.5, 199, 51, 10, 10)
        love.graphics.setFont(fonts.section)
        set_color(COLORS.chalk)
        love.graphics.print(tostring(item[2]) .. "/" .. tostring(item[3]), 60, y + 13)
        love.graphics.setFont(fonts.label)
        set_color(COLORS.muted)
        love.graphics.printf(item[1], 118, y + 18, 108, "right")
    end
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass)
    love.graphics.print(view.draft.refit
        and string.format("REFIT AFTER FIGHT %d • %d CASUALTY",
            view.draft.progress.fight,
            view.draft.progress.broken)
        or string.format("PICK %d OF %d",
            view.draft.progress.total + 1, view.draft.progress.required), 44, 624)
    if view.draft.inspected then
        draw_draft_inspection_desktop(view.draft.inspected)
    else
        for index, card in ipairs(view.draft.cards) do
            local x, y, width, height = action_bounds(action_by_id(card.action_id))
            draw_draft_card(card, x, y, width, height, true, index)
        end
    end
    panel(24, 688, 1232, 88, "walnut", 14)
    if view.draft.inspected then
        local summary, summary_color = synergy_summary(view.draft.inspected)
        love.graphics.setFont(fonts.micro)
        set_color(summary_color)
        love.graphics.printf("EXPANDED RULES OPEN  /  " .. summary, 44, 704, 690, "left")
        set_color(COLORS.restore)
        draw_wrapped_limited(choice_cause_summary(view.draft.inspected),
            318, 704, 416, 1, "right")
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.muted)
        draw_wrapped_limited(view.draft.inspected.operation_copy,
            44, 724, 690, 2, "left")
        draw_button("select:" .. view.draft.inspected.choice_id,
            view.draft.selected_choice_id and "CHOICE SET" or "CHOOSE CARD", COLORS.brass)
    else
        love.graphics.setFont(fonts.body)
        set_color(COLORS.muted)
        love.graphics.printf("Inspect a card to compare its mechanic and scout response.",
            44, 716, 690, "left")
    end
    draw_button("confirm_offer", "CONFIRM PICK", COLORS.player)
end

local function setup_sling()
    assert(view.setup.sling and view.setup.sling.name, "setup projection is missing its drafted sling")
    return view.setup.sling
end

local function setup_brick(uid)
    for _, brick in ipairs(view.setup.bricks or {}) do
        if brick.uid == uid then return brick end
    end
    return nil
end

local function draw_setup_links(origin_x, origin_y, step, cell_size)
    local positions = {}
    for _, brick in ipairs(view.setup.bricks or {}) do
        if brick.cell then
            positions[brick.uid] = {
                x = origin_x + (brick.cell.col - 1) * step + cell_size / 2,
                y = origin_y + (brick.cell.row - 1) * step + cell_size / 2,
            }
        end
    end
    for _, link in ipairs(view.setup.adjacencies or {}) do
        if link.active_synergy then
            local left = positions[link.left_uid]
            local right = positions[link.right_uid]
            if left and right then
                set_color(COLORS.shadow, 0.70)
                love.graphics.setLineWidth(9)
                love.graphics.line(left.x, left.y, right.x, right.y)
                set_color(COLORS.brass, 0.78)
                love.graphics.setLineWidth(4)
                love.graphics.line(left.x, left.y, right.x, right.y)
            end
        end
    end
    love.graphics.setLineWidth(1)
end

local function selected_setup_copy()
    local selected = view.setup.selected_detail
    if not selected then
        return string.upper(setup_sling().name),
            "Sling committed • select a brick or marble for its mechanic."
    end
    if selected.type == "brick" then
        return string.upper(selected.name),
            string.upper(selected.mechanic_label or selected.behaviour or "BRICK")
                .. " • " .. tostring(selected.mechanic_description or "")
    end
    return string.format("BAG %d  /  %s", selected.order or 0, string.upper(selected.name)),
        ((selected.mechanics or {})[1] or "Select a MOVE slot to change launch order.")
end

local function active_setup_links()
    local count = 0
    for _, link in ipairs(view.setup.adjacencies or {}) do
        if link.active_synergy then count = count + 1 end
    end
    return count
end

local function setup_progress_text()
    local placed = 0
    for _, brick in ipairs(view.setup.bricks or {}) do
        if brick.cell then placed = placed + 1 end
    end
    if view.setup.valid then
        return string.format("%d / %d BRICKS PLACED  •  READY", placed, #view.setup.bricks)
    end
    return string.format("%d / %d BRICKS PLACED", placed, #view.setup.bricks)
end

local function draw_setup_phone()
    draw_chrome()
    panel(16, 72, 358, 44, "walnut", 8)
    love.graphics.setFont(fonts.label)
    set_color(COLORS.brass)
    love.graphics.print("FORMATION", 30, 87)
    set_color(COLORS.opponent)
    love.graphics.printf(string.format(
        "%s / %dM/%dB",
        string.upper(view.opponent.name),
        view.opponent.marble_count or 0,
        view.opponent.brick_count or 0
    ), 154, 81, 202, "right")
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.muted)
    love.graphics.printf("PRESSURE / " .. string.upper(
        view.opponent.pressure
            and view.opponent.pressure[1]
            and view.opponent.pressure[1].name
            or scout_mechanic_copy(view.opponent)
    ),
        154, 99, 202, "right")
    panel(16, 124, 358, 220, "felt", 12)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass)
    love.graphics.print("FRONT ROW FACES THE ARENA", 24, 136)
    draw_setup_links(22, 158, 49, 44)
    for row = 1, 3 do
        for col = 1, 7 do
            local cell = view.setup.grid[row][col]
            local x, y, width, height = action_bounds(action_by_id(cell.action_id))
            x, y, width, height = 22 + (col - 1) * 49, 158 + (row - 1) * 49, 44, 44
            if cell.brick_uid then
                local brick = setup_brick(cell.brick_uid)
                draw_brick(x, y, width, height, brick and brick.family, brick and brick.behaviour,
                    brick and brick.max_hp > 0 and brick.hp / brick.max_hp or 1,
                    brick and brick.selected)
            else
                set_color(COLORS.felt_mid, 0.78)
                love.graphics.rectangle("fill", x, y, width, height, 5, 5)
                set_color(cell.legal and COLORS.brass or COLORS.felt_light, cell.legal and 1 or 0.56)
                love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, 5, 5)
                set_color(COLORS.muted, 0.28)
                love.graphics.circle("line", x + width / 2, y + height / 2, 5)
            end
        end
    end
    panel(16, 356, 358, 128, "paper", 12)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass)
    love.graphics.print("MINERAL BRICK BENCH", 22, 344)
    for _, brick in ipairs(view.setup.bricks) do
        local x, y, width, height = action_bounds(action_by_id(brick.action_id))
        draw_brick(x, y, width, height, brick.family, brick.behaviour,
            brick.max_hp > 0 and brick.hp / brick.max_hp or 1, brick.selected)
    end
    panel(16, 496, 358, 140, "walnut", 12)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass)
    love.graphics.print("ORDERED BAG  /  FIRST LAUNCHES FIRST", 26, 504)
    for _, marble in ipairs(view.setup.bag) do
        local x, y, width, height = action_bounds(action_by_id(marble.action_id))
        set_color(marble.selected and COLORS.focus or COLORS.brass_dark, 0.76)
        love.graphics.rectangle("fill", x, y, width, height, 10, 10)
        local first_shell = marble.shells and marble.shells[1]
        draw_marble(x + width / 2, y + 23, 18, marble.rarity,
            first_shell and first_shell.mineral or infer_mineral(marble.art_id),
            1, nil, false)
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.chalk)
        love.graphics.printf(tostring(marble.order), x + 3, y + 42, width - 6, "center")
    end
    for _, slot in ipairs(view.setup.insertion_slots) do
        if slot.enabled then
            local x, y, width, height = action_bounds(action_by_id(slot.action_id))
            set_color(COLORS.brass, 0.28)
            love.graphics.rectangle("fill", x, y, width, height, 7, 7)
            set_color(COLORS.brass)
            love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, 7, 7)
            love.graphics.setFont(fonts.label)
            love.graphics.printf("MOVE", x, y + 17, width, "center")
        end
    end
    panel(16, 648, 358, 108, "felt", 10)
    local reward_visible = view.setup.recent_reward and not view.setup.selected_detail
    if reward_visible then
        love.graphics.setFont(fonts.label)
        set_color(COLORS.restore)
        love.graphics.print("REWARD APPLIED  /  REFIT LOCKED", 26, 658)
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.chalk)
        draw_wrapped_limited(view.setup.recent_reward.operation_copy,
            26, 680, 338, 3, "left")
        set_color(COLORS.brass)
        love.graphics.printf("NEXT PRESSURE  /  "
            .. string.upper(view.opponent.pressure[1].name),
            26, 724, 338, "left")
    else
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.brass)
        love.graphics.print("BUILD SYNERGY  /  " .. tostring(active_setup_links())
            .. " ACTIVE LINKS", 26, 658)
        draw_tag_chips(view.setup.build_tags, 26, 676, 338)
        local selected_title, selected_copy = selected_setup_copy()
        love.graphics.setFont(fonts.label)
        set_color(COLORS.chalk)
        love.graphics.print(selected_title, 26, 704)
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.muted)
        love.graphics.printf(selected_copy, 26, 724, 338, "left")
    end
    love.graphics.setFont(fonts.micro)
    set_color(view.setup.valid and COLORS.restore or COLORS.muted)
    love.graphics.printf(setup_progress_text(), 26, 739, 338, "right")
    draw_button("lock_setup", "LOCK FORMATION", COLORS.player)
end

local function draw_setup_desktop()
    draw_chrome()
    panel(24, 96, 280, 568, "paper", 16)
    panel(328, 96, 616, 568, "felt", 16)
    panel(968, 96, 288, 568, "walnut", 16)
    love.graphics.setFont(fonts.section)
    set_color(COLORS.ink)
    love.graphics.print("BRICK CATALOG", 44, 116)
    for _, brick in ipairs(view.setup.bricks) do
        local x, y, width, height = action_bounds(action_by_id(brick.action_id))
        draw_brick(x, y, width, 62, brick.family, brick.behaviour,
            brick.max_hp > 0 and brick.hp / brick.max_hp or 1, brick.selected)
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.ink)
        love.graphics.printf(brick.name, x + 2, y + 69, width - 4, "center")
    end
    love.graphics.setFont(fonts.section)
    set_color(COLORS.chalk)
    love.graphics.print("FORMATION", 352, 120)
    love.graphics.setFont(fonts.body)
    set_color(COLORS.muted)
    love.graphics.print("Front row faces the brass line", 352, 156)
    set_color(COLORS.brass)
    love.graphics.rectangle("fill", 348, 207, 576, 3)
    draw_setup_links(356, 220, 80, 72)
    for row = 1, 3 do
        for col = 1, 7 do
            local cell = view.setup.grid[row][col]
            local x, y, width, height = action_bounds(action_by_id(cell.action_id))
            if cell.brick_uid then
                local brick = setup_brick(cell.brick_uid)
                draw_brick(x, y, width, height, brick and brick.family, brick and brick.behaviour,
                    brick and brick.max_hp > 0 and brick.hp / brick.max_hp or 1,
                    brick and brick.selected)
            else
                set_color(COLORS.felt_mid)
                love.graphics.rectangle("fill", x, y, width, height, 7, 7)
                set_color(cell.legal and COLORS.brass or COLORS.felt_light)
                love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, 7, 7)
            end
        end
    end
    set_color(COLORS.brass_dark, 0.74)
    love.graphics.rectangle("fill", 348, 480, 576, 2)
    love.graphics.setFont(fonts.label)
    set_color(COLORS.brass)
    love.graphics.print("BUILD SYNERGY", 352, 496)
    love.graphics.printf("RIVAL SCOUT  /  " .. string.upper(view.opponent.name),
        642, 496, 278, "right")
    draw_tag_chips(view.setup.build_tags, 352, 520, 270)
    draw_tag_chips(view.opponent.scout_tags, 650, 520, 270)
    local selected_title, selected_copy = selected_setup_copy()
    love.graphics.setFont(fonts.label)
    set_color(COLORS.chalk)
    love.graphics.print(selected_title, 352, 556)
    love.graphics.setFont(fonts.meta)
    set_color(COLORS.muted)
    love.graphics.printf(selected_copy, 352, 580, 270, "left")
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass)
    love.graphics.print(tostring(active_setup_links()) .. " ACTIVE ADJACENCY LINKS", 352, 632)
    set_color(COLORS.opponent)
    love.graphics.printf(scout_loadout_copy(view.opponent),
        650, 540, 270, "right")
    draw_pressure_preview(
        view.opponent.pressure and view.opponent.pressure[1],
        650, 558, 270, false
    )
    love.graphics.setFont(fonts.section)
    set_color(COLORS.brass)
    love.graphics.print("ORDERED BAG", 990, 116)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.muted)
    love.graphics.print("FIRST LAUNCHES FIRST", 990, 144)
    for _, marble in ipairs(view.setup.bag) do
        local x, y, width, height = action_bounds(action_by_id(marble.action_id))
        set_color(marble.selected and COLORS.focus or COLORS.felt_mid)
        love.graphics.rectangle("fill", x, y, width, height, 10, 10)
        local first_shell = marble.shells and marble.shells[1]
        draw_marble(x + 32, y + height / 2, 23, marble.rarity,
            first_shell and first_shell.mineral or infer_mineral(marble.art_id),
            1, nil, false)
        love.graphics.setFont(fonts.label)
        set_color(COLORS.chalk)
        love.graphics.print(tostring(marble.order) .. "  " .. marble.name, x + 68, y + 22)
    end
    for _, slot in ipairs(view.setup.insertion_slots) do
        if slot.enabled then
            local x, y, width, height = action_bounds(action_by_id(slot.action_id))
            set_color(COLORS.brass, 0.34)
            love.graphics.rectangle("fill", x, y, width, height, 7, 7)
            set_color(COLORS.brass)
            love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, 7, 7)
            love.graphics.setFont(fonts.micro)
            love.graphics.printf("MOVE", x, y + 18, width, "center")
        end
    end
    draw_sling(1044, 596, 0.8, setup_sling().name)
    panel(24, 688, 1232, 88, "walnut", 14)
    love.graphics.setFont(fonts.body)
    set_color(view.setup.recent_reward and not view.setup.selected_detail
        and COLORS.restore
        or view.setup.valid and COLORS.restore
        or COLORS.muted)
    local footer_copy
    if view.setup.recent_reward and not view.setup.selected_detail then
        footer_copy = "REWARD APPLIED  /  " .. view.setup.recent_reward.operation_copy
    else
        footer_copy = view.setup.valid
            and "Every mineral is seated. The ordered bag is committed."
            or (setup_progress_text() .. "  /  seat every drafted brick to lock.")
    end
    love.graphics.printf(footer_copy, 48, 716, 900, "left")
    draw_button("lock_setup", "LOCK FORMATION", COLORS.player)
end

local function frame_mapper(frame)
    if mode() == "desktop" then
        return function(x, y)
            return 40 + y / frame.arena.height * 1200,
                112 + x / frame.arena.width * 536
        end
    end
    return function(x, y)
        return 24 + x / frame.arena.width * 342,
            88 + y / frame.arena.height * 632
    end
end

local function side_marble(frame, owner, uid)
    local side = frame.sides and frame.sides[owner]
    return side and side.marbles and side.marbles[uid] or nil
end

local function side_brick(frame, owner, id)
    local side = frame.sides and frame.sides[owner]
    for _, brick in ipairs(side and side.bricks or {}) do
        if brick.body_id == id then return brick end
    end
    return nil
end

local function draw_trails(frame, map)
    if app.model.ui.reduced_motion then return end
    for id, trail in pairs(trails) do
        local owner = trail.owner == "A" and COLORS.player or COLORS.opponent
        for index = 2, #trail.points do
            local previous = trail.points[index - 1]
            local point = trail.points[index]
            local x1, y1 = map(previous.x, previous.y)
            local x2, y2 = map(point.x, point.y)
            set_color(owner, clamp(1 - point.age / 0.32, 0, 1) * 0.42)
            love.graphics.setLineWidth(math.max(1, 4 - index * 0.18))
            love.graphics.line(x1, y1, x2, y2)
        end
    end
    love.graphics.setLineWidth(1)
end

local function draw_particles(frame, map)
    if app.model.ui.reduced_motion then return end
    for _, particle in ipairs(particles) do
        local life = clamp(1 - particle.age / particle.life, 0, 1)
        local x, y
        if particle.world and frame then x, y = map(particle.x, particle.y)
        else x, y = particle.x, particle.y end
        x = x + math.cos(particle.angle) * particle.speed * particle.age
        y = y + math.sin(particle.angle) * particle.speed * particle.age
        set_color(particle.color, life)
        if particle.shape == "line" then
            love.graphics.line(x - 4, y - 3, x + 4, y + 3)
        elseif particle.shape == "triangle" then
            love.graphics.polygon("fill", x, y - 3, x - 3, y + 3, x + 3, y + 2)
        else
            love.graphics.circle("fill", x, y, 2)
        end
    end
end

local function draw_battle_world(frame)
    if mode() == "desktop" then
        panel(24, 96, 500, 568, "felt", 16)
        panel(548, 96, 184, 568, "paper", 16)
        panel(756, 96, 500, 568, "felt", 16)
    else
        panel(16, 72, 358, 246, "felt", 14)
        panel(16, 326, 358, 156, "paper", 12)
        panel(16, 490, 358, 246, "felt", 14)
    end
    if not frame or not frame.arena then return end
    local map = frame_mapper(frame)
    for _, field in ipairs(frame.world.fields or {}) do
        local x, y = map(field.x, field.y)
        local radius_x, radius_y
        if mode() == "desktop" then
            radius_x = field.radius / frame.arena.height * 1200
            radius_y = field.radius / frame.arena.width * 536
        else
            radius_x = field.radius / frame.arena.width * 342
            radius_y = field.radius / frame.arena.height * 632
        end
        set_color(P.effect_magnetic.rgb, 0.08)
        love.graphics.ellipse("fill", x, y, radius_x, radius_y)
        set_color(P.effect_magnetic.rgb, 0.34)
        love.graphics.ellipse("line", x, y, radius_x, radius_y)
    end
    draw_trails(frame, map)
    for _, entity in ipairs(frame.entities or {}) do
        local x, y = map(entity.x, entity.y)
        local entity_id = entity.id or entity.uid
        local inspected = view.battle
            and view.battle.inspected_entity_id
            and tostring(view.battle.inspected_entity_id) == tostring(entity_id)
        if entity.type == "brick" and entity.alive then
            local width, height
            if mode() == "desktop" then
                width = entity.height / frame.arena.height * 1200
                height = entity.width / frame.arena.width * 536
            else
                width = entity.width / frame.arena.width * 342
                height = entity.height / frame.arena.height * 632
            end
            if inspected then
                set_color(COLORS.focus, 0.16)
                love.graphics.ellipse("fill", x, y, width * 0.78, height * 0.86)
                set_color(COLORS.focus)
                love.graphics.setLineWidth(3)
                love.graphics.rectangle("line", x - width / 2 - 5, y - height / 2 - 5,
                    width + 10, height + 10, 7, 7)
                love.graphics.setLineWidth(1)
            end
            local brick = side_brick(frame, entity.owner, entity.id)
            draw_brick(x - width / 2, y - height / 2, width, height,
                entity.family, entity.behaviour, entity.hp_ratio, false)
            if brick and brick.status then
                set_color(COLORS.focus)
                love.graphics.circle("line", x, y, math.min(width, height) * 0.34)
            end
        elseif entity.type == "marble" then
            local scale_x = mode() == "desktop" and 1200 / frame.arena.height or 342 / frame.arena.width
            local scale_y = mode() == "desktop" and 536 / frame.arena.width or 632 / frame.arena.height
            local radius = math.max(6, entity.radius * math.min(scale_x, scale_y))
            local marble = side_marble(frame, entity.owner, entity.uid)
            local shell = marble and marble.shells and marble.shells[1]
            if inspected then
                set_color(COLORS.focus, 0.15)
                love.graphics.circle("fill", x, y, radius + 12)
                set_color(COLORS.focus)
                love.graphics.setLineWidth(3)
                love.graphics.circle("line", x, y, radius + 9)
                love.graphics.setLineWidth(1)
            end
            draw_marble(x, y, radius, marble and marble.rarity or "common",
                shell and shell.mineral or "quartz", entity.shell_ratio, entity.statuses)
        end
    end
    draw_particles(frame, map)
end

local function inspection_summary(inspected)
    if inspected.type == "brick" then
        return string.format("%s / %s / %d%%",
            string.upper(inspected.family or ""),
            string.upper(inspected.mechanic or "BASE"),
            inspected.integrity or 0)
    end
    return string.format("%s / %d SHELL%s / %s",
        string.upper(inspected.rarity or ""),
        inspected.shell_count or 0,
        inspected.shell_count == 1 and "" or "S",
        string.upper(inspected.state or "READY"))
end

local function inspection_copy(inspected)
    if inspected.type == "brick" then
        return inspected.mechanic_description or "Static formation brick."
    end
    local statuses = #(inspected.statuses or {}) > 0
        and (" • " .. table.concat(inspected.statuses, " + "))
        or ""
    return string.format("Core: %s  •  shell integrity %d%%%s",
        tostring(inspected.core or "sealed"),
        inspected.shell_integrity or 0,
        statuses)
end

local function callout_amount(callout)
    if not callout or callout.magnitude == nil then return "NO MAGNITUDE" end
    local value = type(callout.magnitude) == "boolean"
        and (callout.magnitude and "TRUE" or "FALSE")
        or tostring(callout.magnitude):upper():gsub("_", " ")
    local unit = tostring(callout.unit or ""):upper():gsub("_", " ")
    return unit == "" and value or (value .. " " .. unit)
end

local function short_drawback(drawback)
    if not drawback or drawback.kind == "none" then return "NONE" end
    local value = drawback.magnitude ~= nil and tostring(drawback.magnitude) or ""
    return string.format("%s %s %s",
        tostring(drawback.kind):upper(),
        tostring(drawback.stat or ""):upper():gsub("_", " "),
        value)
end

local function draw_spine_field(label, value, y)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass_ink)
    love.graphics.printf(label, 560, y, 160, "center")
    set_color(COLORS.ink)
    love.graphics.printf(value or "NONE", 560, y + 14, 160, "center")
end

local function draw_battle_overlay(replay)
    local battle = replay and {
        frame = view.replay.frame,
        exchange = view.replay.frame and view.replay.frame.exchange or 0,
        tick = view.replay.frame and view.replay.frame.tick or 0,
        view = app.model.ui,
    } or view.battle
    local frame = battle.frame
    if mode() == "desktop" then
        love.graphics.setFont(fonts.label)
        set_color(COLORS.opponent)
        love.graphics.print(string.upper(view.opponent.name) .. "  /  RIVAL", 44, 112)
        set_color(COLORS.player)
        love.graphics.printf("COLLECTOR  /  YOU", 780, 112, 452, "right")
        love.graphics.setFont(fonts.display)
        set_color(COLORS.brass_dark)
        love.graphics.printf(string.format("%02d", battle.exchange or 0), 564, 136, 152, "center")
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.ink)
        love.graphics.printf("EXCHANGE", 564, 172, 152, "center")
        local inspected = not replay and battle.inspected or nil
        if inspected then
            local inspection = inspected.rule_inspection or {}
            local rule = inspection.rule or {}
            love.graphics.setFont(fonts.micro)
            set_color(COLORS.brass_ink)
            love.graphics.printf("INSPECTED  /  " .. string.upper(inspected.owner_name),
                560, 216, 160, "center")
            love.graphics.setFont(fonts.body)
            set_color(COLORS.ink)
            love.graphics.printf(inspected.name, 560, 242, 160, "center")
            love.graphics.setFont(fonts.micro)
            set_color(COLORS.ink, 0.64)
            love.graphics.printf(inspection_summary(inspected), 560, 294, 160, "center")
            draw_rule_mark(rule, 640, 342, 40, true)
            love.graphics.setFont(fonts.micro)
            set_color(COLORS.brass_ink)
            love.graphics.printf(string.format("%s  /  RULE %d OF %d",
                rule.verb_label or "RULE",
                inspection.index or 0,
                inspection.count or 0), 560, 366, 160, "center")
            draw_spine_field("TRIGGER",
                rule.trigger and rule.trigger.label or "NONE", 392)
            draw_spine_field("TARGET",
                rule.target and rule.target.label or "NONE", 432)
            draw_spine_field("EFFECT",
                tostring(rule.verb_label or "NONE") .. " "
                    .. tostring(rule.magnitude and rule.magnitude.label or "NONE"),
                472)
            draw_spine_field("LIMIT",
                rule.cadence and rule.cadence.short_label or "NONE", 512)
            draw_spine_field("DRAWBACK",
                short_drawback(inspection.drawback), 552)
            draw_button("inspection_prev", "PREV", COLORS.brass)
            draw_button("inspection_next", "NEXT", COLORS.brass)
        else
            if not replay and last_rule_callout then
                love.graphics.setFont(fonts.micro)
                set_color(COLORS.brass_ink)
                love.graphics.printf("LIVE MIDLINE", 560, 216, 160, "center")
                set_color(COLORS.ink, 0.42)
                love.graphics.printf("RULE CALLOUT BELOW", 560, 560, 160, "center")
            else
                love.graphics.setFont(fonts.body)
                set_color(COLORS.ink)
                love.graphics.printf(replay and view.subtitle or last_cue,
                    564, 236, 152, "center")
            end
            if not replay and not last_rule_callout then
                love.graphics.setFont(fonts.micro)
                set_color(COLORS.ink, 0.50)
                love.graphics.printf("CLICK A PIECE TO INSPECT", 560, 560, 160, "center")
            end
        end
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.ink, 0.62)
        love.graphics.printf(string.format("TICK %06d", battle.tick or 0), 564, 640, 152, "center")
        panel(24, 688, 1232, 88, "walnut", 14)
        if replay then
            love.graphics.setFont(fonts.body)
            set_color(COLORS.muted)
            love.graphics.print("Immutable canonical recording", 48, 719)
            draw_button("replay_next", "NEXT FRAME", COLORS.brass)
            draw_button("replay_close", "RESULT", COLORS.player)
        else
            if last_rule_callout and not inspected then
                draw_rule_mark(last_rule_callout, 70, 732, 38, false)
                love.graphics.setFont(fonts.micro)
                set_color(COLORS.brass)
                love.graphics.print("CANONICAL TRIGGER  /  "
                    .. string.upper(last_rule_callout.source), 102, 704)
                love.graphics.setFont(fonts.meta)
                set_color(COLORS.chalk)
                love.graphics.printf(last_rule_callout.text, 102, 724, 620, "left")
                love.graphics.setFont(fonts.micro)
                set_color(COLORS.restore)
                love.graphics.printf(string.format("%s %s  /  %s",
                    last_rule_callout.verb_label,
                    callout_amount(last_rule_callout),
                    tostring(last_rule_callout.target):upper():gsub("_", " ")),
                    102, 748, 620, "left")
            else
                love.graphics.setFont(fonts.body)
                set_color(COLORS.muted)
                love.graphics.printf(
                    "Click any marble or brick to inspect  /  outcomes stay automatic",
                    48, 719, 680, "left")
            end
            draw_button("battle_pause", battle.view.paused and "RESUME" or "PAUSE")
            draw_button("battle_speed", tostring(battle.view.speed) .. "X")
            draw_button("battle_mute", battle.view.muted and "MUTED" or "SOUND ON")
            draw_button("battle_motion", battle.view.reduced_motion and "REDUCED" or "FULL MOTION")
        end
    else
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.opponent)
        love.graphics.print(string.upper(view.opponent.name) .. "  /  RIVAL", 28, 86)
        set_color(COLORS.player)
        love.graphics.printf("COLLECTOR  /  YOU", 28, 710, 334, "right")
        local inspected = not replay and battle.inspected or nil
        love.graphics.setFont(fonts.section)
        set_color(COLORS.ink)
        love.graphics.printf(replay and "RECORDED BATTLE"
            or inspected and string.format("INSPECTED  •  EXCHANGE %02d", battle.exchange or 0)
            or string.format("EXCHANGE %02d", battle.exchange or 0), 28, 340, 334, "center")
        if inspected then
            local inspection = inspected.rule_inspection or {}
            local rule = inspection.rule or {}
            love.graphics.setFont(fonts.body)
            set_color(COLORS.ink)
            love.graphics.printf(inspected.name, 92, 366, 206, "center")
            draw_rule_mark(rule, 62, 402, 34, true)
            love.graphics.setFont(fonts.micro)
            set_color(COLORS.brass_ink)
            love.graphics.printf(string.format("%s  /  %d OF %d",
                rule.verb_label or "RULE",
                inspection.index or 0,
                inspection.count or 0), 98, 390, 194, "left")
            set_color(COLORS.ink)
            love.graphics.printf("TRG " .. tostring(
                rule.trigger and rule.trigger.short_label or "NONE"),
                98, 403, 194, "left")
            love.graphics.printf("TGT " .. tostring(
                rule.target and rule.target.short_label or "NONE"),
                98, 416, 194, "left")
            love.graphics.printf(string.format("FX %s %s",
                rule.verb_label or "NONE",
                rule.magnitude and rule.magnitude.label or "NONE"),
                98, 429, 194, "left")
            love.graphics.printf("LIM "
                .. tostring(rule.cadence and rule.cadence.short_label or "NONE"),
                98, 442, 194, "left")
            love.graphics.printf("DRAW " .. short_drawback(inspection.drawback),
                98, 455, 194, "left")
            draw_button("inspection_prev", "PREV", COLORS.brass)
            draw_button("inspection_next", "NEXT", COLORS.brass)
        else
            if not replay and last_rule_callout then
                draw_rule_mark(last_rule_callout, 62, 404, 42, true)
                love.graphics.setFont(fonts.micro)
                set_color(COLORS.brass_ink)
                love.graphics.print("CANONICAL TRIGGER  /  "
                    .. string.upper(last_rule_callout.source), 92, 374)
                love.graphics.setFont(fonts.meta)
                set_color(COLORS.ink)
                love.graphics.printf(last_rule_callout.text, 92, 398, 260, "left")
                love.graphics.setFont(fonts.micro)
                set_color(COLORS.brass_ink)
                love.graphics.printf(string.format("%s %s  /  %s",
                    last_rule_callout.verb_label,
                    callout_amount(last_rule_callout),
                    tostring(last_rule_callout.target):upper():gsub("_", " ")),
                    92, 452, 260, "left")
            else
                love.graphics.setFont(fonts.body)
                set_color(COLORS.ink)
                love.graphics.printf(replay and view.subtitle or last_cue,
                    38, 378, 314, "center")
            end
            if not replay and not last_rule_callout then
                love.graphics.setFont(fonts.micro)
                set_color(COLORS.ink, 0.52)
                love.graphics.printf("TAP A PIECE FOR THE SAME RULE IDENTITY",
                    38, 430, 314, "center")
            end
        end
        if not inspected then
            love.graphics.setFont(fonts.micro)
            set_color(COLORS.ink, 0.65)
            love.graphics.printf(string.format("CANONICAL TICK %06d", battle.tick or 0),
                28, 466, 334, "center")
        end
        if replay then
            draw_button("replay_next", "NEXT FRAME", COLORS.brass)
            draw_button("replay_close", "BACK TO RESULT", COLORS.player)
        else
            draw_button("battle_pause", battle.view.paused and "RESUME" or "PAUSE")
            draw_button("battle_speed", tostring(battle.view.speed) .. "X")
            draw_button("battle_mute", battle.view.muted and "MUTED" or "SOUND")
            draw_button("battle_motion", battle.view.reduced_motion and "REDUCED" or "MOTION")
        end
    end
    if frame and frame.sides then
        local sling_a = frame.sides.A and frame.sides.A.sling_name
        local sling_b = frame.sides.B and frame.sides.B.sling_name
        if mode() == "desktop" then
            draw_sling(74, 612, 0.62, sling_b)
            draw_sling(1206, 612, 0.62, sling_a)
        else
            draw_sling(338, 122, 0.45)
            draw_sling(52, 687, 0.45)
        end
    end
    -- The world pass already renders pieces in the event spine. Keep the
    -- canonical copy last so live physics stays visible without covering the
    -- shared trigger/target/effect identity.
end

local function draw_battle()
    draw_chrome()
    draw_battle_world(view.battle.frame)
    draw_battle_overlay(false)
end

local function result_side(frame)
    if not frame or not frame.sides then return nil end
    if view.result.winner == "player" then return frame.sides.A end
    if view.result.winner == "opponent" then return frame.sides.B end
    return frame.sides.A
end

local function draw_still_life(frame, x, y, width, height)
    panel(x, y, width, height, "felt", 16)
    local side = result_side(frame)
    local marble = side and side.marble_list and side.marble_list[1]
    draw_sling(x + width * 0.38, y + height * 0.57,
        math.min(width / 300, height / 190) * 1.5, side and side.sling_name)
    draw_marble(x + width * 0.67, y + height * 0.52,
        math.min(width, height) * 0.18,
        marble and marble.rarity or "rare",
        marble and marble.shells and marble.shells[1] and marble.shells[1].mineral or "quartz",
        marble and 1 or 0.65,
        marble and marble.statuses)
    set_color(COLORS.brass, 0.18)
    love.graphics.ellipse("fill", x + width * 0.54, y + height * 0.77, width * 0.27, height * 0.055)
end

local function ledger_text(event)
    local names = {
        A = app.model.run.player.name,
        B = app.model.run.opponent.name,
        player = app.model.run.player.name,
        opponent = app.model.run.opponent.name,
    }
    return battle_presentation.event_text(event, names)
end

local function draw_result_phone()
    draw_chrome()
    draw_still_life(view.result.final_frame, 16, 80, 358, 196)
    panel(16, 292, 358, 170, "paper", 14)
    love.graphics.setFont(fonts.result)
    set_color(view.result.winner == "player" and COLORS.player
        or view.result.winner == "opponent" and COLORS.opponent
        or COLORS.brass_dark)
    love.graphics.printf(string.upper(view.title), 30, 310, 330, "center")
    love.graphics.setFont(fonts.body)
    set_color(COLORS.ink)
    love.graphics.printf(view.subtitle, 36, 356, 318, "center")
    love.graphics.setFont(fonts.meta)
    set_color(COLORS.ink, 0.72)
    local result_meta = view.result.short_run
        and string.format("%d/%d FIGHTS  /  %d FINAL EXCHANGES",
            view.result.fights_cleared or 0,
            view.result.fight_total or 3,
            view.result.exchanges)
        or string.format("%d EXCHANGES  /  SEED %d",
            view.result.exchanges, view.run_seed)
    love.graphics.printf(result_meta, 32, 414, 326, "center")
    panel(16, 478, 358, 190, "walnut", 12)
    love.graphics.setFont(fonts.label)
    set_color(COLORS.brass)
    love.graphics.print(view.result.ledger_expanded and "BATTLE LEDGER" or "FINAL THREE EVENTS", 28, 492)
    local events = view.result.ledger or {}
    local first = math.max(1, #events - (view.result.ledger_expanded and 6 or 3) + 1)
    local line = 0
    for index = first, #events do
        line = line + 1
        love.graphics.setFont(fonts.meta)
        set_color(COLORS.muted)
        love.graphics.printf(ledger_text(events[index]), 28, 520 + (line - 1) * 36, 334, "left")
    end
    draw_button("new_run", view.result.short_run and "RUN AGAIN" or "DRAFT AGAIN",
        COLORS.player)
    draw_button("review_battle", view.result.ledger_expanded and "CLOSE LEDGER" or "REVIEW BATTLE", COLORS.brass)
    draw_button("replay_battle", "REPLAY SEED", COLORS.brass)
end

local function draw_result_desktop()
    draw_chrome()
    draw_still_life(view.result.final_frame, 24, 96, 596, 568)
    panel(644, 96, 612, 568, "paper", 16)
    love.graphics.setFont(fonts.result)
    set_color(view.result.winner == "player" and COLORS.player
        or view.result.winner == "opponent" and COLORS.opponent
        or COLORS.brass_dark)
    love.graphics.print(string.upper(view.title), 680, 132)
    love.graphics.setFont(fonts.section)
    set_color(COLORS.ink)
    love.graphics.print(view.subtitle, 680, 188)
    love.graphics.setFont(fonts.body)
    set_color(COLORS.ink, 0.72)
    local result_meta = view.result.short_run
        and string.format("%d/%d fights cleared  /  %d final exchanges  /  %d frames",
            view.result.fights_cleared or 0,
            view.result.fight_total or 3,
            view.result.exchanges,
            view.result.recording_frames)
        or string.format("%d exchanges  /  seed %d  /  %d recorded frames",
            view.result.exchanges, view.run_seed, view.result.recording_frames)
    love.graphics.print(result_meta, 680, 226)
    set_color(COLORS.brass_dark)
    love.graphics.rectangle("fill", 680, 274, 540, 2)
    love.graphics.setFont(fonts.section)
    set_color(COLORS.ink)
    love.graphics.print("CANONICAL LEDGER", 680, 304)
    local events = view.result.ledger or {}
    local first = math.max(1, #events - 6 + 1)
    local line = 0
    for index = first, #events do
        line = line + 1
        love.graphics.setFont(fonts.body)
        set_color(COLORS.ink, 0.78)
        love.graphics.printf(ledger_text(events[index]), 680, 350 + (line - 1) * 44, 532, "left")
    end
    panel(24, 688, 1232, 88, "walnut", 14)
    love.graphics.setFont(fonts.body)
    set_color(COLORS.muted)
    love.graphics.print(view.result.short_run
        and "All fight results, casualties, rewards, and canonical recordings are preserved."
        or "The final material state and recording are preserved.", 48, 719)
    draw_button("review_battle", view.result.ledger_expanded and "CLOSE" or "LEDGER", COLORS.brass)
    draw_button("replay_battle", "REPLAY", COLORS.brass)
    draw_button("new_run", view.result.short_run and "RUN AGAIN" or "DRAFT AGAIN",
        COLORS.player)
end

local function draw_result()
    if mode() == "desktop" then draw_result_desktop() else draw_result_phone() end
end

local function draw_replay()
    draw_chrome()
    draw_battle_world(view.replay.frame)
    draw_battle_overlay(true)
end

local function action_at(x, y)
    for index = #(view.actions or {}), 1, -1 do
        local action = view.actions[index]
        local ax, ay, width, height = action_bounds(action)
        if action.enabled and x >= ax and x <= ax + width
            and y >= ay and y <= ay + height then
            return action
        end
    end
    return nil
end

local function pointer_pressed(x, y, source)
    audio_unlock()
    local action = action_at(x, y)
    if not action then
        print(string.format("CALLACK_POINTER miss x=%.1f y=%.1f phase=%s", x, y, view.screen))
        return false
    end
    local now = love.timer.getTime()
    if last_pointer_press then
        local elapsed = now - last_pointer_press.at
        local same_position =
            (x - last_pointer_press.x) ^ 2 + (y - last_pointer_press.y) ^ 2 < 256
        local repeated_action =
            action.id == last_pointer_press.action_id and elapsed < 0.35
        local synthetic_cross_source =
            source ~= last_pointer_press.source and elapsed < 1.5
        if same_position and (repeated_action or synthetic_cross_source) then
            return true
        end
    end
    last_pointer_press = {
        action_id = action.id,
        source = source,
        x = x,
        y = y,
        at = now,
    }
    pressed_action_id = action.id
    drag_start_x, drag_start_y = x, y
    if action.id:match("^brick:") or action.id:match("^marble:") then
        drag_action_id = action.id
    else
        drag_action_id = nil
    end
    return activate(action.id, source)
end

local function pointer_released(x, y, source)
    local moved = drag_start_x
        and ((x - drag_start_x) ^ 2 + (y - drag_start_y) ^ 2) ^ 0.5 > 10
    if moved and drag_action_id then
        local action = action_at(x, y)
        if action and (action.id:match("^cell:") or action.id:match("^slot:")) then
            activate(action.id, source .. "_drag")
        end
    end
    pressed_action_id = nil
    drag_action_id = nil
end

local function local_random(seed)
    seed = math.max(1, math.floor(seed) % 2147483647)
    return function()
        seed = (seed * 48271) % 2147483647
        return seed / 2147483647
    end
end

local function spawn_event_particles(event)
    if app.model.ui.reduced_motion then return end
    local recipes = {
        collision = { 5, 0.18, "triangle", COLORS.damage },
        brick_destroyed = { 6, 0.20, "triangle", COLORS.brass_dark },
        shell_break = { 9, 0.22, "line", COLORS.chalk },
        core_release = { 6, 0.28, "dot", COLORS.brass_light },
        battle_end = { 8, 0.40, "triangle", COLORS.brass },
    }
    local recipe = recipes[event.type]
    if not recipe then return end
    local random = local_random((event.seq or event.tick or 1) * 97 + #(event.marble or event.brick or ""))
    for index = 1, recipe[1] do
        local world = event.x ~= nil and event.y ~= nil and event.type ~= "battle_end"
        particles[#particles + 1] = {
            x = world and event.x or (mode() == "desktop" and 322 or 195),
            y = world and event.y or (mode() == "desktop" and 370 or 180),
            world = world,
            age = 0,
            life = recipe[2],
            shape = recipe[3],
            color = recipe[4],
            angle = random() * math.pi * 2,
            speed = 22 + random() * 52,
        }
    end
    local cap = mode() == "desktop" and art.motion.particle_cap_desktop
        or art.motion.particle_cap_phone
    while #particles > cap do table.remove(particles, 1) end
end

local function handle_event(event)
    if event.type and event.type ~= "phase_changed" and event.type ~= "battle_handoff" then
        local names = {
            A = app.model.run.player.name,
            B = app.model.run.opponent.name,
            player = app.model.run.player.name,
            opponent = app.model.run.opponent.name,
        }
        last_cue = battle_presentation.event_text(event, names)
    end
    if event.rule_id then
        local operation = art.rule_operation[event.rule_operation] or {
            label = tostring(event.rule_operation or "trigger"):upper():gsub("_", " "),
            mark = tostring(event.rule_operation or "rule"):upper():sub(1, 3),
        }
        last_rule_callout = {
            rule_id = event.rule_id,
            source = event.rule_source or "Rule",
            role = event.rule_role,
            verb = event.rule_operation,
            verb_label = operation.label,
            icon = operation.mark,
            target = event.rule_target,
            magnitude = event.rule_magnitude,
            unit = event.rule_unit,
            text = battle_presentation.event_text(event, {
                A = app.model.run.player.name,
                B = app.model.run.opponent.name,
                player = app.model.run.player.name,
                opponent = app.model.run.opponent.name,
            }),
        }
        print(string.format(
            "CALLACK_RULE_CALLOUT rule=%s source=%s icon=%s verb=%s target=%s magnitude=%s unit=%s",
            telemetry_value(last_rule_callout.rule_id),
            telemetry_value(last_rule_callout.source),
            telemetry_value(last_rule_callout.icon),
            telemetry_value(last_rule_callout.verb),
            telemetry_value(last_rule_callout.target),
            telemetry_value(last_rule_callout.magnitude),
            telemetry_value(last_rule_callout.unit)
        ))
    end
    spawn_event_particles(event)
    if not app.model.ui.reduced_motion
        and (event.type == "collision" or event.type == "brick_destroyed"
            or event.type == "shell_break") then
        camera.x = clamp((event.nx or 0.7) * art.motion.camera_nudge, -3, 3)
        camera.y = clamp((event.ny or -0.4) * art.motion.camera_nudge, -3, 3)
        camera.age = 0
        camera.life = art.motion.camera_nudge_seconds
    end
    if audio_bank then
        if event.type == "launch" then procedural_audio.play(audio_bank, "sling_release")
        elseif event.type == "collision" then procedural_audio.play(audio_bank, "brick_hit")
        elseif event.type == "brick_destroyed" then procedural_audio.play(audio_bank, "brick_hit", 0.82)
        elseif event.type == "shell_break" then procedural_audio.play(audio_bank, "shell_break")
        elseif event.type == "core_release" then procedural_audio.play(audio_bank, "core_release")
        elseif event.type == "battle_end" then procedural_audio.play(audio_bank, "result") end
    end
end

local function update_effects(dt)
    for index = #particles, 1, -1 do
        particles[index].age = particles[index].age + dt
        if particles[index].age >= particles[index].life then table.remove(particles, index) end
    end
    for id, trail in pairs(trails) do
        for index = #trail.points, 1, -1 do
            trail.points[index].age = trail.points[index].age + dt
            if trail.points[index].age > 0.32 then table.remove(trail.points, index) end
        end
        if #trail.points == 0 then trails[id] = nil end
    end
    camera.age = camera.age + dt
    screen_age = screen_age + dt
    offer_age = offer_age + dt
    if audio_bank then procedural_audio.update(audio_bank, dt) end
end

local function capture_motion()
    if view.screen ~= "battle" or not view.battle.frame then return end
    if app.model.ui.reduced_motion then trails = {} return end
    local tick = view.battle.tick or 0
    local telemetry_entity
    for _, entity in ipairs(view.battle.frame.entities or {}) do
        if entity.type == "marble" and (entity.state == "flying" or entity.state == "blown") then
            local id = tostring(entity.uid or entity.id)
            local trail = trails[id] or { owner = entity.owner, points = {} }
            trails[id] = trail
            local previous = trail.points[#trail.points]
            if not previous or math.abs(previous.x - entity.x) + math.abs(previous.y - entity.y) > 0.08 then
                trail.points[#trail.points + 1] = { x = entity.x, y = entity.y, age = 0 }
                if #trail.points > 10 then table.remove(trail.points, 1) end
            end
            telemetry_entity = telemetry_entity or entity
        end
    end
    if telemetry_entity and tick - telemetry_tick >= 120 then
        telemetry_tick = tick
        print(string.format(
            "CALLACK_PHYSICS tick=%d entity=%s x=%.3f y=%.3f",
            tick,
            tostring(telemetry_entity.uid or telemetry_entity.id),
            telemetry_entity.x,
            telemetry_entity.y
        ))
    end
end

local function has_argument(args, wanted)
    for _, value in ipairs(args or {}) do
        if value == wanted then return true end
    end
    for _, value in ipairs(arg or {}) do
        if value == wanted then return true end
    end
    return false
end

function love.load(args)
    local touch = has_argument(args, "--touch")
    local desktop = has_argument(args, "--desktop")
    local reduced_default = has_argument(args, "--reduced-motion")
    verification_mode = has_argument(args, "--verify-canonical")
    if verification_mode then
        local runtime_verification = require("battle.runtime_verification")
        local evidence = runtime_verification.run()
        print(string.format(
            "CALLACK_CANONICAL_SWEEP kind=%s speed=%.3f toi=%.6f reflected=%s tunneled=%s substeps=%d iterations=%d",
            evidence.sweep.kind,
            evidence.sweep.speed,
            evidence.sweep.toi,
            tostring(evidence.sweep.reflected),
            tostring(evidence.sweep.tunneled),
            evidence.sweep.substeps,
            evidence.sweep.iterations
        ))
        print(string.format(
            "CALLACK_CANONICAL_BLOWBACK allied=%s enemy=%s affected=%d ally_dx=%.6f enemy_dx=%.6f substeps=%d iterations=%d tick=%d",
            tostring(evidence.blowback.allied),
            tostring(evidence.blowback.enemy),
            evidence.blowback.affected,
            evidence.blowback.ally_dx,
            evidence.blowback.enemy_dx,
            evidence.blowback.substeps,
            evidence.blowback.iterations,
            evidence.blowback.tick
        ))
    end
    if not touch and not desktop and love.system.getOS() ~= "Web" then
        local desktop_width, desktop_height = love.window.getDesktopDimensions()
        desktop = desktop_width >= 1024 and desktop_width / desktop_height >= 1.15
    end
    if desktop then
        love.window.setMode(DESKTOP_W, DESKTOP_H, {
            resizable = true, minwidth = 900, minheight = 640, vsync = 1,
        })
    elseif touch then
        love.window.setMode(PHONE_W, PHONE_H, {
            resizable = true, minwidth = 320, minheight = 568, vsync = 1,
        })
    end
    love.graphics.setDefaultFilter("linear", "linear")
    love.graphics.setLineStyle("rough")
    fonts.micro = love.graphics.newFont(art.type_scale.micro)
    fonts.meta = love.graphics.newFont(art.type_scale.meta)
    fonts.label = love.graphics.newFont(art.type_scale.label)
    fonts.body = love.graphics.newFont(art.type_scale.body)
    fonts.card = love.graphics.newFont(art.type_scale.card_title)
    fonts.section = love.graphics.newFont(art.type_scale.section)
    fonts.display = love.graphics.newFont(art.type_scale.display)
    fonts.result = love.graphics.newFont(art.type_scale.result)
    for _, font in pairs(fonts) do font:setLineHeight(art.type_scale.line_height) end
    local muted = setting_read("muted.setting", false)
    local reduced = setting_read("reduced-motion.setting", reduced_default)
    app = run_loop.new({
        run_seed = 9125,
        short_run = true,
        muted = muted,
        reduced_motion = reduced,
    })
    local ok, bank = pcall(procedural_audio.new, art.audio)
    if ok then
        audio_bank = bank
        procedural_audio.set_muted(audio_bank, muted)
        print("CALLACK_AUDIO ready")
    else
        print("CALLACK_AUDIO unavailable=" .. tostring(bank))
    end
    refresh_view()
    report_action("ready")
end

function love.update(dt)
    update_effects(dt)
    if verification_mode
        and app.model.run.phase == "battle"
        and not app.model.ui.paused then
        -- Packaged verification must not depend on a headless host's WebGL
        -- frame rate. This advances the same fixed-step engine in bounded
        -- batches; ordinary builds keep the real-time accumulator path.
        run_loop.advance(app, 16 * (app.model.ui.speed or 1))
    else
        run_loop.update(app, dt)
    end
    for _, event in ipairs(run_loop.drain_events(app)) do handle_event(event) end
    refresh_view()
    capture_motion()
end

function love.draw()
    love.graphics.clear(COLORS.shadow[1], COLORS.shadow[2], COLORS.shadow[3], 1)
    local scale, offset_x, offset_y = screen_frame()
    local width, height = base_size()
    love.graphics.push()
    love.graphics.translate(offset_x, offset_y)
    love.graphics.scale(scale, scale)
    local camera_amount = camera.life > 0 and clamp(1 - camera.age / camera.life, 0, 1) or 0
    if not app.model.ui.reduced_motion then
        love.graphics.translate(camera.x * camera_amount, camera.y * camera_amount)
    end
    draw_walnut(width, height)
    if view.screen == "draft" then
        if mode() == "desktop" then draw_draft_desktop() else draw_draft_phone() end
    elseif view.screen == "setup" then
        if mode() == "desktop" then draw_setup_desktop() else draw_setup_phone() end
    elseif view.screen == "battle" then draw_battle()
    elseif view.screen == "result" then draw_result()
    elseif view.screen == "replay" then draw_replay()
    end
    love.graphics.pop()
end

function love.keypressed(key)
    audio_unlock()
    if key == "escape" then
        love.event.quit()
    elseif key == "tab" or key == "down" then
        move_focus(1)
    elseif key == "up" then
        move_focus(-1)
    elseif key == "return" or key == "kpenter" then
        if focused_action_id then activate(focused_action_id, "keyboard") end
    elseif key == "space" and view.screen == "battle" then
        activate("battle_pause", "keyboard")
    elseif key == "right" and view.screen == "battle" then
        if not app.model.ui.paused then activate("battle_pause", "keyboard") end
        run_loop.advance(app, 1)
        refresh_view()
    elseif key == "right" and view.screen == "replay" then
        activate("replay_next", "keyboard")
    elseif key == "r" and view.screen == "result" then
        activate("replay_battle", "keyboard")
    elseif key == "n" and view.screen == "result" then
        activate("new_run", "keyboard")
    elseif key == "m" then
        if view.screen == "battle" then
            activate("battle_mute", "keyboard")
        else
            app.model.ui.muted = not app.model.ui.muted
            sync_settings()
            refresh_view()
            report_action("toggle_mute")
        end
    elseif key == "v" then
        if view.screen == "battle" then
            activate("battle_motion", "keyboard")
        else
            app.model.ui.reduced_motion = not app.model.ui.reduced_motion
            sync_settings()
            refresh_view()
            report_action("toggle_reduced_motion")
        end
    elseif view.screen == "draft" and (key == "1" or key == "2" or key == "3") then
        local card = view.draft.cards[tonumber(key)]
        if card then activate(card.action_id, "keyboard") end
    end
end

function love.touchpressed(_, x, y)
    touch_guard_until = love.timer.getTime() + 1.25
    local base_x, base_y = to_base(x, y)
    local now = love.timer.getTime()
    for index = #recent_touches, 1, -1 do
        if now - recent_touches[index].at >= 5 then table.remove(recent_touches, index) end
    end
    recent_touches[#recent_touches + 1] = { x = base_x, y = base_y, at = now }
    pointer_pressed(base_x, base_y, "touch")
end

function love.touchreleased(_, x, y)
    local base_x, base_y = to_base(x, y)
    pointer_released(base_x, base_y, "touch")
end

function love.mousepressed(x, y, button)
    if button == 1 then
        local base_x, base_y = to_base(x, y)
        local now = love.timer.getTime()
        local synthetic = false
        for _, touch in ipairs(recent_touches) do
            if now - touch.at < 5
                and (base_x - touch.x) ^ 2 + (base_y - touch.y) ^ 2 < 256 then
                synthetic = true
                break
            end
        end
        if love.timer.getTime() >= touch_guard_until and not synthetic then
            pointer_pressed(base_x, base_y, "mouse")
        end
    end
end

function love.mousereleased(x, y, button)
    if button == 1 then
        local base_x, base_y = to_base(x, y)
        local now = love.timer.getTime()
        local synthetic = false
        for _, touch in ipairs(recent_touches) do
            if now - touch.at < 5
                and (base_x - touch.x) ^ 2 + (base_y - touch.y) ^ 2 < 256 then
                synthetic = true
                break
            end
        end
        if love.timer.getTime() >= touch_guard_until and not synthetic then
            pointer_released(base_x, base_y, "mouse")
        end
    end
end
