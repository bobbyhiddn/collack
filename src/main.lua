-- LÖVE controller/rendering shell for the canonical continuous battle.

local engine = require("battle.engine")
local setup = require("battle.setup")
local presentation = require("presentation")

local BASE_W, BASE_H = 390, 844
local ARENA_X, ARENA_Y, ARENA_W, ARENA_H = 20, 102, 350, 566
local model
local fonts = {}
local touch_guard = 0

local COLORS = {
    bg = { 0.025, 0.035, 0.065 },
    panel = { 0.055, 0.075, 0.12 },
    panel_edge = { 0.16, 0.22, 0.34 },
    text = { 0.92, 0.94, 0.98 },
    muted = { 0.52, 0.59, 0.69 },
    A = { 1.00, 0.61, 0.25 },
    B = { 0.22, 0.78, 0.95 },
    damage = { 1.00, 0.28, 0.30 },
    defensive = { 0.20, 0.56, 0.82 },
    effect = { 0.63, 0.34, 0.82 },
    utility = { 0.84, 0.50, 0.18 },
    rare = { 0.93, 0.72, 0.20 },
    basic = { 0.38, 0.43, 0.52 },
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

local function panel(x, y, width, height, radius)
    set_color(COLORS.panel)
    love.graphics.rectangle("fill", x, y, width, height, radius or 8, radius or 8)
    set_color(COLORS.panel_edge)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1,
        radius or 8, radius or 8)
end

local function world_to_screen(x, y)
    return ARENA_X + x / model.view.arena.width * ARENA_W,
        ARENA_Y + y / model.view.arena.height * ARENA_H
end

local function push_events(events)
    local names = {
        A = model.view and model.view.sides.A.name or "A",
        B = model.view and model.view.sides.B.name or "B",
    }
    for _, event in ipairs(events or {}) do
        if event.type ~= "volley_start" then
            model.last_cue = presentation.event_text(event, names)
            model.cues[#model.cues + 1] = event
            while #model.cues > 12 do table.remove(model.cues, 1) end
        end
    end
end

local function report_action(action)
    love.window.setTitle(string.format("Callack Continuous Battle | Seed %d", model.seed))
    print(string.format("CALLACK_ACTION %s seed=%d", action, model.seed))
end

local function new_live(seed)
    local battle = engine.new({
        battle_seed = seed,
        sides = setup.default_matchup(),
    })
    local frame = engine.snapshot(battle)
    local next_model = {
        seed = seed,
        mode = "live",
        battle = battle,
        previous = frame,
        current = frame,
        view = presentation.project(frame, frame, 1),
        accumulator = 0,
        playing = true,
        speed = 1,
        cues = {},
        last_cue = "Both formations are locked.",
        replay = nil,
    }
    model = next_model
    push_events(engine.drain_events(battle))
    return next_model
end

local function begin_replay()
    if not model.battle or not model.battle.result then return false end
    local recording = engine.recording(model.battle)
    model.mode = "replay"
    model.replay = presentation.from_recording(recording)
    model.playing = true
    model.cues = {}
    model.last_cue = "Recorded battle replay."
    model.view = presentation.replay_project(model.replay)
    return true
end

local function update_live(dt)
    if model.playing and not model.battle.result then
        model.accumulator = model.accumulator + math.max(0, dt) * model.speed
        local steps = 0
        while model.accumulator >= engine.FIXED_DT and steps < 8 do
            model.previous = model.current
            local events = engine.step(model.battle, engine.FIXED_DT)
            model.current = engine.snapshot(model.battle)
            model.accumulator = model.accumulator - engine.FIXED_DT
            steps = steps + 1
            push_events(events)
        end
        -- A slow render frame can leave debt here; it is intentionally carried
        -- into the next update rather than dropping canonical simulation time.
        if model.battle.result then model.playing = false end
    end
    local alpha = model.accumulator / engine.FIXED_DT
    model.view = presentation.project(model.current, model.previous, alpha)
end

local function update_replay(dt)
    model.replay.playing = model.playing
    presentation.replay_update(model.replay, dt, model.speed)
    model.playing = model.replay.playing
    model.view = presentation.replay_project(model.replay)
    local events = model.replay.recording.events
    while model.replay.event_cursor < #events
        and events[model.replay.event_cursor + 1].tick <= model.view.tick do
        model.replay.event_cursor = model.replay.event_cursor + 1
        push_events({ events[model.replay.event_cursor] })
    end
end

local function draw_header()
    set_color(COLORS.text)
    love.graphics.setFont(fonts.title)
    love.graphics.print("CALLACK", 15, 13)
    set_color(COLORS.A)
    love.graphics.print("// CONTINUOUS BATTLE", 118, 17)
    love.graphics.setFont(fonts.small)
    set_color(COLORS.muted)
    love.graphics.print(string.format("SEED %d  //  TICK %06d", model.seed, model.view.tick), 16, 48)
    love.graphics.printf(string.format("EXCHANGE %02d", model.view.exchange), 245, 48, 129, "right")
    set_color(COLORS.panel_edge)
    love.graphics.line(15, 69, 375, 69)
end

local function draw_side_status(side_id, x, align)
    local side = model.view.sides[side_id]
    love.graphics.setFont(fonts.body)
    set_color(COLORS[side_id])
    love.graphics.printf(string.upper(side.name), x, 77, 170, align)
    love.graphics.setFont(fonts.tiny)
    set_color(COLORS.muted)
    love.graphics.printf(string.format("%d BRICKS  //  %d MARBLES",
        side.bricks_alive, side.marbles_alive), x, 91, 170, align)
end

local function draw_field(field)
    local x, y = world_to_screen(field.x, field.y)
    local radius = field.radius / model.view.arena.width * ARENA_W
    local behaviour = field.data and field.data.behaviour
    local color = behaviour == "freeze" and COLORS.B
        or behaviour == "poison" and { 0.40, 0.85, 0.35 }
        or COLORS.effect
    set_color(color, behaviour == "release" and 0.12 or 0.055)
    love.graphics.circle("fill", x, y, radius)
    set_color(color, 0.22)
    love.graphics.circle("line", x, y, radius)
end

local function draw_brick(entity)
    if not entity.alive then return end
    local x, y = world_to_screen(entity.x, entity.y)
    local width = entity.width / model.view.arena.width * ARENA_W
    local height = entity.height / model.view.arena.height * ARENA_H
    local color = COLORS[entity.family] or COLORS.basic
    set_color(color, 0.35 + 0.55 * entity.hp_ratio)
    love.graphics.rectangle("fill", x - width / 2, y - height / 2, width, height, 3, 3)
    set_color(color)
    love.graphics.rectangle("line", x - width / 2, y - height / 2, width, height, 3, 3)
    set_color(COLORS.bg, 0.8)
    love.graphics.rectangle("fill", x - width / 2 + 2, y + height / 2 - 3,
        math.max(0, (width - 4) * entity.hp_ratio), 2, 1, 1)
end

local function draw_marble(entity)
    local x, y = world_to_screen(entity.x, entity.y)
    local radius = math.max(5, entity.radius / model.view.arena.width * ARENA_W)
    local color = COLORS[entity.owner]
    if entity.state == "flying" or entity.state == "blown" then
        set_color(color, 0.13)
        love.graphics.circle("fill", x, y, radius * 2.1)
    end
    set_color(COLORS.panel_edge)
    love.graphics.circle("fill", x, y, radius + 2)
    set_color(color, 0.50 + 0.50 * entity.shell_ratio)
    love.graphics.circle("fill", x, y, radius)
    set_color(COLORS.text, 0.72)
    love.graphics.circle("line", x, y, radius * 0.62)
    if entity.statuses.poison then
        set_color({ 0.40, 0.90, 0.35 })
        love.graphics.circle("line", x, y, radius + 4)
    elseif entity.statuses.freeze then
        set_color(COLORS.B)
        love.graphics.circle("line", x, y, radius + 4)
    end
end

local function draw_arena()
    panel(ARENA_X, ARENA_Y, ARENA_W, ARENA_H, 11)
    love.graphics.setScissor(ARENA_X, ARENA_Y, ARENA_W, ARENA_H)
    set_color(COLORS.panel_edge, 0.22)
    local _, centre_y = world_to_screen(0, model.view.arena.height / 2)
    love.graphics.line(ARENA_X + 8, centre_y, ARENA_X + ARENA_W - 8, centre_y)
    for _, field in ipairs(model.view.world.fields) do draw_field(field) end
    for _, entity in ipairs(model.view.entities) do
        if entity.type == "brick" then draw_brick(entity) end
    end
    for _, entity in ipairs(model.view.entities) do
        if entity.type == "marble" then draw_marble(entity) end
    end
    love.graphics.setScissor()
    love.graphics.setFont(fonts.tiny)
    set_color(COLORS.muted)
    love.graphics.print("CPU SLING", ARENA_X + 8, ARENA_Y + 7)
    love.graphics.printf("PLAYER SLING", ARENA_X + 8, ARENA_Y + ARENA_H - 17,
        ARENA_W - 16, "right")
end

local BUTTONS = {
    replay = { x = 15, y = 790, w = 174, h = 40, label = "REPLAY RECORDING" },
    new_seed = { x = 201, y = 790, w = 174, h = 40, label = "NEW SEED" },
}

local function draw_footer()
    panel(20, 677, 350, 103, 9)
    love.graphics.setFont(fonts.tiny)
    set_color(COLORS.muted)
    love.graphics.print(model.mode == "replay" and "CANONICAL RECORDING" or "LIVE 120 HZ WORLD",
        31, 688)
    love.graphics.setFont(fonts.body)
    set_color(COLORS.text)
    love.graphics.printf(model.last_cue or "", 31, 707, 328, "center")
    love.graphics.setFont(fonts.large)
    if model.view.finished then
        local color = model.view.winner and COLORS[model.view.winner] or COLORS.rare
        set_color(color)
        local copy_text = model.view.winner
            and string.upper(model.view.sides[model.view.winner].name) .. " WINS"
            or "DRAW"
        love.graphics.printf(copy_text, 31, 731, 328, "center")
    else
        set_color(COLORS.muted)
        love.graphics.printf(model.playing and "AUTO-RESOLVING" or "PAUSED",
            31, 731, 328, "center")
    end
    love.graphics.setFont(fonts.tiny)
    set_color(COLORS.muted)
    love.graphics.printf("SPACE PAUSE  //  RIGHT FIXED STEP", 0, 765, BASE_W, "center")
    for name, button in pairs(BUTTONS) do
        local enabled = name ~= "replay" or (model.battle and model.battle.result)
            or model.mode == "replay"
        local color = name == "replay" and COLORS.A or COLORS.B
        set_color(color, enabled and 0.18 or 0.05)
        love.graphics.rectangle("fill", button.x, button.y, button.w, button.h, 8, 8)
        set_color(color, enabled and 1 or 0.25)
        love.graphics.rectangle("line", button.x + 0.5, button.y + 0.5,
            button.w - 1, button.h - 1, 8, 8)
        love.graphics.setFont(fonts.body)
        love.graphics.printf(button.label, button.x, button.y + 12, button.w, "center")
    end
end

local function replay_action()
    if model.mode == "replay" then
        presentation.replay_seek(model.replay, 0)
        model.replay.event_cursor = 0
        model.playing = true
        model.cues = {}
        model.last_cue = "Recorded battle replay."
        report_action("replay")
    else
        if begin_replay() then
            report_action("replay")
        else
            report_action("replay_unavailable")
        end
    end
end

local function press_at(x, y)
    for name, button in pairs(BUTTONS) do
        if x >= button.x and x <= button.x + button.w
            and y >= button.y and y <= button.y + button.h then
            if name == "replay" then replay_action()
            else
                local seed = model.seed + 1
                if seed >= 2147483647 then seed = 1 end
                new_live(seed)
                report_action("new_seed")
            end
            return true
        end
    end
    return false
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    fonts.tiny = love.graphics.newFont(9)
    fonts.small = love.graphics.newFont(10)
    fonts.body = love.graphics.newFont(12)
    fonts.large = love.graphics.newFont(20)
    fonts.title = love.graphics.newFont(25)
    new_live(presentation.DEFAULT_SEED)
    report_action("ready")
end

function love.update(dt)
    touch_guard = math.max(0, touch_guard - dt)
    if model.mode == "live" then update_live(dt) else update_replay(dt) end
end

function love.draw()
    love.graphics.clear(COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 1)
    local scale, ox, oy = screen_frame()
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(scale, scale)
    set_color(COLORS.bg)
    love.graphics.rectangle("fill", 0, 0, BASE_W, BASE_H)
    draw_header()
    draw_side_status("A", 16, "left")
    draw_side_status("B", 204, "right")
    draw_arena()
    draw_footer()
    love.graphics.pop()
end

function love.keypressed(key)
    if key == "escape" then love.event.quit()
    elseif key == "r" then replay_action()
    elseif key == "n" then
        local seed = model.seed + 1
        if seed >= 2147483647 then seed = 1 end
        new_live(seed)
        report_action("new_seed")
    elseif key == "space" then model.playing = not model.playing
    elseif key == "right" then
        model.playing = false
        if model.mode == "live" and not model.battle.result then
            model.previous = model.current
            push_events(engine.step(model.battle, engine.FIXED_DT))
            model.current = engine.snapshot(model.battle)
            model.view = presentation.project(model.current, model.previous, 1)
        elseif model.mode == "replay" then
            presentation.replay_step(model.replay, 1)
            model.view = presentation.replay_project(model.replay)
        end
    end
end

function love.touchpressed(_, x, y)
    touch_guard = 1
    press_at(to_base(x, y))
end

function love.mousepressed(x, y, button)
    if button == 1 and touch_guard <= 0 then press_at(to_base(x, y)) end
end
