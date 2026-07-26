-- Thin LÖVE shell for the product run loop. Rendering and input consume the
-- value-only PresentationState; battle.engine remains the sole combat owner.

local art = require("ui.art_tokens")
local battle_presentation = require("presentation")
local run_loop = require("run_loop")

local BASE_W = art.logical_surface.phone.width
local BASE_H = art.logical_surface.phone.height
local ARENA = { x = 16, y = 86, w = 358, h = 650 }

local app
local view
local fonts = {}
local focused_action_id
local touch_guard = 0
local last_screen
local last_cue = "Choose a card to begin your collection."

local P = art.palette
local COLORS = {
    bg = P.walnut_900.rgb,
    felt = P.felt_900.rgb,
    felt_light = P.felt_700.rgb,
    panel = P.paper_100.rgb,
    panel_edge = P.paper_300.rgb,
    ink = P.paper_ink.rgb,
    text = P.chalk.rgb,
    muted = P.muted.rgb,
    brass = P.brass_300.rgb,
    focus = P.focus.rgb,
    player = P.player_a.rgb,
    opponent = P.player_b.rgb,
    damage = P.damage.rgb,
    common = P.rarity_common.rgb,
    uncommon = P.rarity_uncommon.rgb,
    rare = P.rarity_rare.rgb,
    epic = P.rarity_epic.rgb,
    legendary = P.rarity_legendary.rgb,
    basic = P.family_basic.rgb,
    defensive = P.family_defensive.rgb,
    effect = P.family_effect.rgb,
    utility = P.family_utility.rgb,
}

local function set_color(color, alpha)
    love.graphics.setColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function screen_frame()
    local width, height = love.graphics.getDimensions()
    local scale = math.min(width / BASE_W, height / BASE_H)
    return scale, (width - BASE_W * scale) / 2, (height - BASE_H * scale) / 2
end

local function to_base(x, y)
    local scale, ox, oy = screen_frame()
    return (x - ox) / scale, (y - oy) / scale
end

local function panel(x, y, width, height, dark, radius)
    set_color(dark and COLORS.felt or COLORS.panel)
    love.graphics.rectangle("fill", x, y, width, height, radius or 12, radius or 12)
    set_color(dark and COLORS.felt_light or COLORS.panel_edge)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1,
        radius or 12, radius or 12)
end

local function action_by_id(id)
    for _, action in ipairs(view.actions or {}) do
        if action.id == id then return action end
    end
    return nil
end

local function action_bounds(action)
    local bounds = action and action.bounds or {}
    return bounds.x or 0, bounds.y or 0, bounds.width or 0, bounds.height or 0
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

local function refresh_view()
    view = run_loop.project(app)
    if last_screen ~= view.screen then
        last_screen = view.screen
        update_title()
        report_action("phase_" .. view.screen)
    end
end

local function activate(action_id, source)
    if view.enabled_actions[action_id] ~= true then return false end
    local accepted, action_error = run_loop.activate(app, action_id, source)
    if not accepted then
        last_cue = action_error and action_error.message or "That action is unavailable."
        report_action("rejected_" .. action_id)
        return false
    end
    focused_action_id = action_id
    refresh_view()
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

local function draw_button(id, label, accent)
    local action = action_by_id(id)
    if not action then return end
    local x, y, width, height = action_bounds(action)
    local enabled = action.enabled
    local color = accent or COLORS.brass
    set_color(color, enabled and 0.26 or 0.07)
    love.graphics.rectangle("fill", x, y, width, height, 9, 9)
    set_color(focused_action_id == id and COLORS.focus or color, enabled and 1 or 0.28)
    love.graphics.setLineWidth(focused_action_id == id and 3 or 1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, 9, 9)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(fonts.label)
    set_color(enabled and COLORS.text or COLORS.muted, enabled and 1 or 0.4)
    love.graphics.printf(label or action.label, x + 6, y + height / 2 - 8, width - 12, "center")
end

local function draw_chrome()
    panel(12, 12, 366, 52, true, 12)
    love.graphics.setFont(fonts.display)
    set_color(COLORS.text)
    love.graphics.print("CALLACK", 22, 20)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass)
    love.graphics.printf(view.labels.phase, 188, 20, 176, "right")
    set_color(COLORS.muted)
    love.graphics.printf(view.labels.seed, 188, 40, 176, "right")
end

local function draw_tags(tags, x, y, width)
    local labels = {}
    for _, tag in ipairs(tags or {}) do
        labels[#labels + 1] = string.upper(tag.label or tag.id)
    end
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.muted)
    love.graphics.printf(table.concat(labels, "  ·  "), x, y, width, "left")
end

local function draw_draft()
    draw_chrome()
    love.graphics.setFont(fonts.section)
    set_color(COLORS.text)
    love.graphics.print(view.title, 16, 72)
    love.graphics.setFont(fonts.meta)
    set_color(COLORS.muted)
    love.graphics.printf(
        view.subtitle .. "  //  SCOUT " .. string.upper(view.opponent.name),
        16, 94, 358, "left"
    )

    for _, card in ipairs(view.draft.cards) do
        local action = action_by_id(card.action_id)
        local x, y, width, height = action_bounds(action)
        local rarity = COLORS[card.rarity] or COLORS.common
        panel(x, y, width, height, false, 12)
        set_color(rarity, card.inspected and 0.30 or 0.14)
        love.graphics.rectangle("fill", x + 1, y + 1, width - 2, height - 2, 11, 11)
        set_color(card.inspected and COLORS.focus or rarity)
        love.graphics.setLineWidth(card.inspected and 3 or 1)
        love.graphics.rectangle("line", x + 1.5, y + 1.5, width - 3, height - 3, 11, 11)
        love.graphics.setLineWidth(1)
        love.graphics.setFont(fonts.card)
        set_color(COLORS.ink)
        love.graphics.print(card.name, x + 14, y + 12)
        love.graphics.setFont(fonts.meta)
        set_color(COLORS.ink, 0.74)
        love.graphics.printf(
            string.upper(card.role or "") .. "  ·  " .. string.upper(card.rarity or "kit"),
            x + 14, y + 38, width - 28, "left"
        )
        local mechanics = card.mechanics and card.mechanics[1] or "Inspectable build choice."
        love.graphics.setFont(fonts.body)
        set_color(COLORS.ink)
        love.graphics.printf(mechanics, x + 14, y + 62, width - 28, "left")
        draw_tags(card.tags, x + 14, y + height - 25, width - 28)
    end

    if view.draft.inspected then
        local inspected = view.draft.inspected
        panel(16, 578, 358, 118, true, 10)
        love.graphics.setFont(fonts.label)
        set_color(COLORS.brass)
        love.graphics.print("INSPECTED // " .. string.upper(inspected.name), 28, 588)
        love.graphics.setFont(fonts.meta)
        set_color(COLORS.text)
        love.graphics.printf(
            table.concat(inspected.mechanics or {}, "  "),
            28, 611, 334, "left"
        )
        draw_button("select:" .. inspected.choice_id, "SELECT " .. string.upper(inspected.name))
    else
        love.graphics.setFont(fonts.meta)
        set_color(COLORS.muted)
        love.graphics.printf("Tap a card to inspect its mechanics and synergies.",
            16, 718, 358, "center")
    end
    draw_button("confirm_offer", "CONFIRM CHOICE", COLORS.player)
end

local function draw_setup()
    draw_chrome()
    love.graphics.setFont(fonts.section)
    set_color(COLORS.text)
    love.graphics.print(view.title, 16, 78)
    love.graphics.setFont(fonts.meta)
    set_color(COLORS.muted)
    love.graphics.printf(view.subtitle, 16, 103, 358, "left")

    panel(16, 124, 358, 220, true, 12)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass)
    love.graphics.print("FORMATION // ROW 1 FACES THE ARENA", 24, 136)
    for row = 1, 3 do
        for col = 1, 7 do
            local cell = view.setup.grid[row][col]
            local action = action_by_id(cell.action_id)
            local x, y, width, height = action_bounds(action)
            local selected = cell.brick_uid == view.setup.selected_brick_uid
            set_color(cell.brick_uid and COLORS.utility or COLORS.felt_light,
                cell.brick_uid and 0.72 or 0.42)
            love.graphics.rectangle("fill", x, y, width, height, 6, 6)
            set_color(selected and COLORS.focus or (cell.legal and COLORS.brass or COLORS.felt_light))
            love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, 6, 6)
            if cell.brick_uid then
                love.graphics.setFont(fonts.micro)
                set_color(COLORS.text)
                love.graphics.printf(cell.content_id:gsub("_.*", ""), x + 2, y + 16, width - 4, "center")
            end
        end
    end

    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass)
    love.graphics.print("DRAFTED BRICKS", 20, 346)
    for _, brick in ipairs(view.setup.bricks) do
        local action = action_by_id(brick.action_id)
        local x, y, width, height = action_bounds(action)
        local family = COLORS[brick.family] or COLORS.basic
        set_color(family, brick.selected and 0.95 or 0.66)
        love.graphics.rectangle("fill", x, y, width, height, 7, 7)
        set_color(brick.selected and COLORS.focus or COLORS.panel_edge)
        love.graphics.setLineWidth(brick.selected and 3 or 1)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, 7, 7)
        love.graphics.setLineWidth(1)
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.text)
        love.graphics.printf(brick.name, x + 4, y + 11, width - 8, "center")
    end

    panel(16, 496, 358, 140, true, 12)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.brass)
    love.graphics.print("ORDERED BAG // 1 LAUNCHES FIRST", 26, 503)
    for _, marble in ipairs(view.setup.bag) do
        local action = action_by_id(marble.action_id)
        local x, y, width, height = action_bounds(action)
        local rarity = COLORS[marble.rarity] or COLORS.common
        set_color(rarity, marble.selected and 0.95 or 0.70)
        love.graphics.rectangle("fill", x, y, width, height, 20, 20)
        set_color(marble.selected and COLORS.focus or COLORS.panel_edge)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, 20, 20)
        love.graphics.setFont(fonts.micro)
        set_color(COLORS.ink)
        love.graphics.printf(tostring(marble.order) .. "  " .. marble.name,
            x + 3, y + 17, width - 6, "center")
    end
    for _, slot in ipairs(view.setup.insertion_slots) do
        if slot.enabled then
            local action = action_by_id(slot.action_id)
            local x, y, width, height = action_bounds(action)
            set_color(COLORS.brass, 0.35)
            love.graphics.rectangle("fill", x, y, width, height, 7, 7)
            set_color(COLORS.brass)
            love.graphics.printf("↳", x, y + 14, width, "center")
        end
    end

    panel(16, 648, 358, 92, true, 10)
    love.graphics.setFont(fonts.meta)
    set_color(view.setup.valid and COLORS.player or COLORS.muted)
    love.graphics.print(view.setup.valid and "FORMATION READY" or "SETUP INCOMPLETE", 28, 660)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.muted)
    local error_text = view.setup.errors[1] and view.setup.errors[1].message
        or "Every drafted brick is placed exactly once."
    love.graphics.printf(error_text, 28, 684, 334, "left")
    draw_button("lock_setup", "LOCK FORMATION", COLORS.player)
end

local function frame_world_to_screen(frame, x, y)
    return ARENA.x + x / frame.arena.width * ARENA.w,
        ARENA.y + y / frame.arena.height * ARENA.h
end

local function draw_battle_frame(frame)
    panel(ARENA.x, ARENA.y, ARENA.w, ARENA.h, true, 14)
    if not frame or not frame.arena then
        love.graphics.setFont(fonts.body)
        set_color(COLORS.muted)
        love.graphics.printf("Preparing the canonical world…", ARENA.x, 400, ARENA.w, "center")
        return
    end
    love.graphics.setScissor(ARENA.x, ARENA.y, ARENA.w, ARENA.h)
    set_color(COLORS.felt_light, 0.7)
    love.graphics.line(ARENA.x + 8, ARENA.y + ARENA.h / 2,
        ARENA.x + ARENA.w - 8, ARENA.y + ARENA.h / 2)
    for _, field in ipairs(frame.world.fields or {}) do
        local x, y = frame_world_to_screen(frame, field.x, field.y)
        local radius = field.radius / frame.arena.width * ARENA.w
        set_color(COLORS.effect, 0.10)
        love.graphics.circle("fill", x, y, radius)
        set_color(COLORS.effect, 0.32)
        love.graphics.circle("line", x, y, radius)
    end
    for _, entity in ipairs(frame.entities or {}) do
        local x, y = frame_world_to_screen(frame, entity.x, entity.y)
        if entity.type == "brick" and entity.alive then
            local width = entity.width / frame.arena.width * ARENA.w
            local height = entity.height / frame.arena.height * ARENA.h
            local family = COLORS[entity.family] or COLORS.basic
            set_color(family, 0.35 + 0.60 * entity.hp_ratio)
            love.graphics.rectangle("fill", x - width / 2, y - height / 2, width, height, 3, 3)
            set_color(family)
            love.graphics.rectangle("line", x - width / 2, y - height / 2, width, height, 3, 3)
        elseif entity.type == "marble" then
            local radius = math.max(5, entity.radius / frame.arena.width * ARENA.w)
            local owner = entity.owner == "A" and COLORS.player or COLORS.opponent
            set_color(owner, 0.22)
            love.graphics.circle("fill", x, y, radius + 5)
            set_color(owner, 0.55 + 0.45 * entity.shell_ratio)
            love.graphics.circle("fill", x, y, radius)
            set_color(COLORS.text, 0.65)
            love.graphics.circle("line", x, y, radius * 0.58)
        end
    end
    love.graphics.setScissor()
end

local function draw_battle()
    draw_chrome()
    local frame = view.battle.frame
    draw_battle_frame(frame)
    love.graphics.setFont(fonts.micro)
    set_color(COLORS.opponent)
    love.graphics.print(string.upper(view.opponent.name) .. " // CPU", 26, 94)
    set_color(COLORS.player)
    love.graphics.printf("COLLECTOR // PLAYER", 26, 712, 338, "right")
    set_color(COLORS.text)
    love.graphics.printf(
        string.format("EXCHANGE %02d  //  TICK %06d", view.battle.exchange, view.battle.tick),
        26, 68, 338, "center"
    )
    draw_button("battle_pause")
    draw_button("battle_speed")
    draw_button("battle_mute")
    draw_button("battle_motion")
end

local function draw_result()
    draw_chrome()
    panel(16, 80, 358, 196, true, 14)
    love.graphics.setFont(fonts.result)
    set_color(view.result.winner == "player" and COLORS.player
        or view.result.winner == "opponent" and COLORS.opponent
        or COLORS.brass)
    love.graphics.printf(string.upper(view.title), 24, 116, 342, "center")
    love.graphics.setFont(fonts.body)
    set_color(COLORS.text)
    love.graphics.printf(view.subtitle, 38, 176, 314, "center")

    panel(16, 292, 358, 376, false, 14)
    love.graphics.setFont(fonts.section)
    set_color(COLORS.ink)
    love.graphics.print("Run ledger", 30, 310)
    love.graphics.setFont(fonts.body)
    love.graphics.print("Opponent", 30, 356)
    love.graphics.printf(view.opponent.name, 170, 356, 174, "right")
    love.graphics.print("Exchanges", 30, 394)
    love.graphics.printf(tostring(view.result.exchanges), 170, 394, 174, "right")
    love.graphics.print("Recorded frames", 30, 432)
    love.graphics.printf(tostring(view.result.recording_frames), 170, 432, 174, "right")
    love.graphics.setFont(fonts.meta)
    set_color(COLORS.ink, 0.72)
    love.graphics.printf(last_cue, 30, 492, 330, "center")
    draw_tags(view.result.player_tags, 30, 624, 330)
    draw_button("replay_battle", "REPLAY BATTLE", COLORS.brass)
    draw_button("new_run", "NEW RUN", COLORS.player)
end

local function draw_replay()
    draw_chrome()
    draw_battle_frame(view.replay.frame)
    love.graphics.setFont(fonts.meta)
    set_color(COLORS.brass)
    love.graphics.printf(view.subtitle, 16, 68, 358, "center")
    draw_button("replay_next", "NEXT FRAME", COLORS.brass)
    draw_button("replay_close", "BACK TO RESULT", COLORS.player)
end

local function press_at(x, y, source)
    for index = #(view.actions or {}), 1, -1 do
        local action = view.actions[index]
        local ax, ay, width, height = action_bounds(action)
        if action.enabled and x >= ax and x <= ax + width
            and y >= ay and y <= ay + height then
            return activate(action.id, source)
        end
    end
    return false
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    fonts.micro = love.graphics.newFont(art.type_scale.micro)
    fonts.meta = love.graphics.newFont(art.type_scale.meta)
    fonts.label = love.graphics.newFont(art.type_scale.label)
    fonts.body = love.graphics.newFont(art.type_scale.body)
    fonts.card = love.graphics.newFont(art.type_scale.card_title)
    fonts.section = love.graphics.newFont(art.type_scale.section)
    fonts.display = love.graphics.newFont(art.type_scale.display)
    fonts.result = love.graphics.newFont(art.type_scale.result)
    app = run_loop.new({ run_seed = 9125 })
    refresh_view()
    report_action("ready")
end

function love.update(dt)
    touch_guard = math.max(0, touch_guard - dt)
    run_loop.update(app, dt)
    for _, event in ipairs(run_loop.drain_events(app)) do
        if event.type and event.type ~= "phase_changed" and event.type ~= "battle_handoff" then
            local names = {
                A = app.model.run.player.name,
                B = app.model.run.opponent.name,
                player = app.model.run.player.name,
                opponent = app.model.run.opponent.name,
            }
            last_cue = battle_presentation.event_text(event, names)
        end
    end
    refresh_view()
end

function love.draw()
    love.graphics.clear(COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 1)
    local scale, ox, oy = screen_frame()
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(scale, scale)
    set_color(COLORS.bg)
    love.graphics.rectangle("fill", 0, 0, BASE_W, BASE_H)
    if view.screen == "draft" then draw_draft()
    elseif view.screen == "setup" then draw_setup()
    elseif view.screen == "battle" then draw_battle()
    elseif view.screen == "result" then draw_result()
    elseif view.screen == "replay" then draw_replay()
    end
    love.graphics.pop()
end

function love.keypressed(key)
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
    elseif view.screen == "draft" and (key == "1" or key == "2" or key == "3") then
        local card = view.draft.cards[tonumber(key)]
        if card then activate(card.action_id, "keyboard") end
    end
end

function love.touchpressed(_, x, y)
    touch_guard = 1
    local base_x, base_y = to_base(x, y)
    press_at(base_x, base_y, "touch")
end

function love.mousepressed(x, y, button)
    if button == 1 and touch_guard <= 0 then
        local base_x, base_y = to_base(x, y)
        press_at(base_x, base_y, "mouse")
    end
end
