-- LÖVE presentation/controller for the canonical battle event log.
local presentation = require("presentation")

local BASE_W, BASE_H = 390, 844
local model
local fonts = {}
local touch_guard = 0
local last_pointer_action = -100

local COLORS = {
    bg = { 0.025, 0.035, 0.065 },
    panel = { 0.055, 0.075, 0.12 },
    panel_edge = { 0.16, 0.22, 0.34 },
    text = { 0.92, 0.94, 0.98 },
    muted = { 0.52, 0.59, 0.69 },
    a = { 1.00, 0.61, 0.25 },
    b = { 0.22, 0.78, 0.95 },
    damage = { 1.00, 0.28, 0.30 },
    heal = { 0.28, 0.92, 0.56 },
    basic = { 0.38, 0.43, 0.52 },
    defensive = { 0.20, 0.56, 0.82 },
    effect = { 0.63, 0.34, 0.82 },
    utility = { 0.84, 0.50, 0.18 },
    rare = { 0.93, 0.72, 0.20 },
}

local LABELS = {
    inert = "BASE",
    absorb = "ABS",
    reflect = "REF",
    regenerate = "REG",
    fortify = "FORT",
    poison = "PSN",
    freeze = "FRZ",
    magnetic = "MAG",
    shatter = "SHT",
    chain = "CHN",
    vault = "VLT",
    splice = "SPL",
    dummy = "DMY",
    aegis = "AEG",
    void = "VOID",
    mirror = "MIR",
    temporal = "TMP",
}

local function set_color(color, alpha)
    love.graphics.setColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function frame()
    local width, height = love.graphics.getDimensions()
    local scale = math.min(width / BASE_W, height / BASE_H)
    return scale, (width - BASE_W * scale) / 2, (height - BASE_H * scale) / 2
end

local function to_base(x, y)
    local scale, ox, oy = frame()
    return (x - ox) / scale, (y - oy) / scale
end

local function panel(x, y, w, h, radius)
    set_color(COLORS.panel)
    love.graphics.rectangle("fill", x, y, w, h, radius or 8, radius or 8)
    set_color(COLORS.panel_edge)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, radius or 8, radius or 8)
end

local function shorten(text, limit)
    text = tostring(text or "")
    if #text <= limit then return text end
    return text:sub(1, limit - 3) .. "..."
end

local function draw_header()
    set_color(COLORS.text)
    love.graphics.setFont(fonts.title)
    love.graphics.print("CALLACK", 15, 13)
    set_color(COLORS.a)
    love.graphics.print("// AUTO-BATTLER", 118, 17)

    love.graphics.setFont(fonts.small)
    set_color(COLORS.muted)
    love.graphics.print(string.format("DETERMINISTIC SEED %d", model.seed), 16, 48)
    love.graphics.printf(string.format("VOLLEY %02d", model.view.volley), 250, 48, 124, "right")
    set_color(COLORS.panel_edge)
    love.graphics.line(15, 68, 375, 68)
end

local function draw_side_label(side, y, color, side_id)
    love.graphics.setFont(fonts.body)
    set_color(color)
    love.graphics.print(side_id .. "  " .. string.upper(side.name), 16, y)
    love.graphics.setFont(fonts.tiny)
    set_color(COLORS.muted)
    love.graphics.printf(string.upper(side.sling_name), 170, y + 2, 204, "right")
    love.graphics.print(string.format("%d BRICKS  //  %d MARBLES",
        side.bricks_alive, side.marbles_alive), 16, y + 20)
end

local function shell_durability(marble)
    local current, maximum = 0, 0
    for _, shell in ipairs(marble.shells) do
        current = current + math.max(0, shell.durability)
        maximum = maximum + shell.max_durability
    end
    return current, maximum
end

local function draw_queue(side, y, color)
    love.graphics.setFont(fonts.tiny)
    set_color(COLORS.muted)
    if y < 200 then
        love.graphics.printf("ORDERED QUEUE", 248, y - 9, 126, "right")
    else
        love.graphics.print("ORDERED QUEUE", 16, y - 9)
    end

    if #side.queue == 0 then
        love.graphics.printf("QUEUE EMPTY", 0, y + 7, BASE_W, "center")
        return
    end

    local spacing = 58
    local start = (BASE_W - (#side.queue - 1) * spacing) / 2
    for order, uid in ipairs(side.queue) do
        local marble = side.marbles[uid]
        if marble and marble.alive then
            local x = start + (order - 1) * spacing
            set_color(COLORS.panel_edge)
            love.graphics.circle("fill", x, y + 13, 17)
            set_color(color)
            love.graphics.circle("fill", x, y + 13, 12)
            set_color(COLORS.bg, 0.55)
            love.graphics.circle("line", x, y + 13, 8)

            love.graphics.setFont(fonts.tiny)
            set_color(COLORS.text)
            love.graphics.printf(tostring(order), x - 8, y + 6, 16, "center")
            love.graphics.printf(tostring(#marble.shells), x - 8, y + 21, 16, "center")

            local durability, maximum = shell_durability(marble)
            set_color(COLORS.panel_edge)
            love.graphics.rectangle("fill", x - 19, y + 34, 38, 3, 2, 2)
            if maximum > 0 then
                set_color(durability < maximum and COLORS.damage or color)
                love.graphics.rectangle("fill", x - 19, y + 34, 38 * durability / maximum, 3, 2, 2)
            end

            local status = marble.statuses.poison and "P" or (marble.statuses.freeze and "F" or nil)
            if status then
                set_color(COLORS.effect)
                love.graphics.circle("fill", x + 13, y + 2, 6)
                set_color(COLORS.text)
                love.graphics.printf(status, x + 8, y - 2, 10, "center")
            end
        end
    end
end

local CELL_W, CELL_H, CELL_GAP = 47, 27, 4

local function grid_origin(cols)
    return (BASE_W - (cols * CELL_W + (cols - 1) * CELL_GAP)) / 2
end

local function visual_row(side_id, rows, row)
    if side_id == "B" then return rows - row end
    return row - 1
end

local function draw_formation(side, side_id, y)
    local x0 = grid_origin(side.cols)
    love.graphics.setFont(fonts.tiny)
    for row = 1, side.rows do
        local vy = y + visual_row(side_id, side.rows, row) * (CELL_H + CELL_GAP)
        for col = 1, side.cols do
            local x = x0 + (col - 1) * (CELL_W + CELL_GAP)
            local brick = side.grid[row][col]
            if brick then
                local family_color = COLORS[brick.family] or COLORS.basic
                if brick.alive then
                    local health = brick.max_hp > 0 and brick.hp / brick.max_hp or 0
                    set_color(family_color, 0.35 + health * 0.55)
                    love.graphics.rectangle("fill", x, vy, CELL_W, CELL_H, 5, 5)
                    if brick.flash == "damage" then
                        set_color(COLORS.damage, 0.9)
                    elseif brick.flash == "heal" then
                        set_color(COLORS.heal, 0.9)
                    else
                        set_color(family_color)
                    end
                    love.graphics.rectangle("line", x + 0.5, vy + 0.5, CELL_W - 1, CELL_H - 1, 5, 5)
                    set_color(COLORS.text)
                    love.graphics.printf(LABELS[brick.behaviour] or "?", x + 2, vy + 4, CELL_W - 4, "center")
                    love.graphics.printf(string.format("%d/%d", brick.hp, brick.max_hp),
                        x + 2, vy + 15, CELL_W - 4, "center")
                else
                    set_color(COLORS.panel_edge, 0.35)
                    love.graphics.rectangle("line", x + 0.5, vy + 0.5, CELL_W - 1, CELL_H - 1, 5, 5)
                    love.graphics.line(x + 9, vy + 7, x + CELL_W - 9, vy + CELL_H - 7)
                    love.graphics.line(x + CELL_W - 9, vy + 7, x + 9, vy + CELL_H - 7)
                end
            else
                set_color(COLORS.panel_edge, 0.18)
                love.graphics.rectangle("line", x + 0.5, vy + 0.5, CELL_W - 1, CELL_H - 1, 5, 5)
            end
        end
    end
end

local function draw_active(attacker_id, target_side, target_id, grid_y)
    local attacker = model.view.sides[attacker_id]
    local active = attacker.active
    if not active then return end

    local row = active.row > 0 and active.row or active.target_row
    local col = active.col > 0 and active.col or active.target_col
    if row < 1 or col < 1 then return end

    local x0 = grid_origin(target_side.cols)
    local x = x0 + (col - 1) * (CELL_W + CELL_GAP) + CELL_W / 2
    local y = grid_y + visual_row(target_id, target_side.rows, row) * (CELL_H + CELL_GAP) + CELL_H / 2
    local color = attacker_id == "A" and COLORS.a or COLORS.b
    set_color(color, 0.24)
    love.graphics.circle("fill", x, y, 18)
    set_color(color)
    love.graphics.circle("fill", x, y, 7)
    love.graphics.circle("line", x, y, 13)
    love.graphics.setFont(fonts.tiny)
    set_color(COLORS.bg)
    love.graphics.printf(attacker_id, x - 5, y - 5, 10, "center")
end

local function feed_color(entry)
    if entry.side == "A" then return COLORS.a end
    if entry.side == "B" then return COLORS.b end
    return COLORS.muted
end

local function draw_event_log()
    panel(15, 254, 360, 205, 9)
    love.graphics.setFont(fonts.tiny)
    set_color(COLORS.muted)
    love.graphics.print("DETERMINISTIC EVENT LOG", 27, 266)
    love.graphics.printf(string.format("%d / %d", model.cursor, #model.events), 280, 266, 80, "right")

    local current = model.view.feed[#model.view.feed]
    if current then
        set_color(feed_color(current))
        love.graphics.setFont(fonts.body)
        love.graphics.printf(shorten(current.text, 55), 27, 288, 336, "left")
    else
        set_color(COLORS.text)
        love.graphics.setFont(fonts.body)
        love.graphics.print("Formations locked. Preparing volley.", 27, 288)
    end

    set_color(COLORS.panel_edge)
    love.graphics.line(27, 316, 363, 316)
    love.graphics.setFont(fonts.tiny)
    for index, entry in ipairs(model.view.feed) do
        local y = 326 + (index - 1) * 20
        set_color(feed_color(entry), index == #model.view.feed and 1 or 0.62)
        love.graphics.print(string.format("%03d", entry.seq), 27, y)
        set_color(COLORS.text, index == #model.view.feed and 1 or 0.72)
        love.graphics.print(shorten(entry.text, 48), 58, y)
    end

    if not model.playing and not model.view.finished then
        set_color(COLORS.rare)
        love.graphics.printf("PAUSED", 0, 437, BASE_W, "center")
    end
end

local function draw_result()
    panel(15, 677, 360, 82, 9)
    love.graphics.setFont(fonts.tiny)
    set_color(COLORS.muted)
    love.graphics.print("MATCH OUTCOME", 27, 687)

    love.graphics.setFont(fonts.large)
    if model.view.finished then
        if model.view.outcome == "draw" then
            set_color(COLORS.rare)
            love.graphics.printf("DRAW", 27, 706, 336, "center")
        else
            local winner = model.view.sides[model.view.winner]
            local color = model.view.winner == "A" and COLORS.a or COLORS.b
            set_color(color)
            love.graphics.printf(string.upper(winner.name) .. " WINS", 27, 706, 336, "center")
        end
        love.graphics.setFont(fonts.tiny)
        set_color(COLORS.text)
        love.graphics.printf(string.upper((model.view.reason or ""):gsub("_", " ")),
            27, 737, 336, "center")
    else
        set_color(COLORS.text)
        love.graphics.printf(model.playing and "AUTO-RESOLVING" or "PAUSED", 27, 711, 336, "center")
        love.graphics.setFont(fonts.tiny)
        set_color(COLORS.muted)
        love.graphics.printf("VOLLEY-LOCKED // BOTH SIDES COMMIT FIRST", 27, 739, 336, "center")
    end
end

local BUTTONS = {
    replay = { x = 15, y = 790, w = 174, h = 40, label = "REPLAY SEED", key = "R" },
    new_seed = { x = 201, y = 790, w = 174, h = 40, label = "NEW SEED", key = "N" },
}

local function draw_button(button, color)
    set_color(color, 0.18)
    love.graphics.rectangle("fill", button.x, button.y, button.w, button.h, 8, 8)
    set_color(color)
    love.graphics.rectangle("line", button.x + 0.5, button.y + 0.5, button.w - 1, button.h - 1, 8, 8)
    love.graphics.setFont(fonts.body)
    love.graphics.printf(button.label, button.x, button.y + 8, button.w, "center")
    love.graphics.setFont(fonts.tiny)
    love.graphics.printf(button.key, button.x, button.y + 25, button.w, "center")
end

local function reset_same_seed()
    model = presentation.replay(model)
end

local function reset_new_seed()
    model = presentation.next_seed(model)
end

local function press_at(x, y)
    for name, button in pairs(BUTTONS) do
        if x >= button.x and x <= button.x + button.w
            and y >= button.y and y <= button.y + button.h then
            local now = love.timer.getTime()
            if now - last_pointer_action < 1 then return true end
            last_pointer_action = now
            if name == "replay" then reset_same_seed() else reset_new_seed() end
            return true
        end
    end
    return false
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    love.window.setTitle("Callack Auto-Battler")
    fonts.tiny = love.graphics.newFont(9)
    fonts.small = love.graphics.newFont(10)
    fonts.body = love.graphics.newFont(12)
    fonts.large = love.graphics.newFont(20)
    fonts.title = love.graphics.newFont(25)
    model = presentation.new(presentation.DEFAULT_SEED)
end

function love.update(dt)
    touch_guard = math.max(0, touch_guard - dt)
    presentation.update(model, dt)
end

function love.draw()
    love.graphics.clear(COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 1)
    local scale, ox, oy = frame()
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(scale, scale)

    set_color(COLORS.bg)
    love.graphics.rectangle("fill", 0, 0, BASE_W, BASE_H)
    draw_header()

    local a, b = model.view.sides.A, model.view.sides.B
    draw_side_label(b, 77, COLORS.b, "B")
    draw_queue(b, 108, COLORS.b)
    draw_formation(b, "B", 154)
    draw_active("A", b, "B", 154)

    draw_event_log()

    draw_side_label(a, 476, COLORS.a, "A")
    draw_formation(a, "A", 514)
    draw_active("B", a, "A", 514)
    draw_queue(a, 620, COLORS.a)

    draw_result()
    love.graphics.setFont(fonts.tiny)
    set_color(COLORS.muted)
    love.graphics.printf("SPACE PAUSE/PLAY  //  RIGHT STEP", 0, 767, BASE_W, "center")
    draw_button(BUTTONS.replay, COLORS.a)
    draw_button(BUTTONS.new_seed, COLORS.b)

    love.graphics.pop()
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "r" then
        reset_same_seed()
    elseif key == "n" then
        reset_new_seed()
    elseif key == "space" then
        if model.cursor < #model.events then model.playing = not model.playing end
    elseif key == "right" then
        model.playing = false
        presentation.step(model, 1)
    end
end

function love.touchpressed(_, x, y)
    -- love.js may emit a delayed synthetic mouse press for the same tap.
    -- Keep the guard long enough to cover mobile browsers' click delay.
    touch_guard = 1.0
    press_at(to_base(x, y))
end

function love.mousepressed(x, y, button)
    if button ~= 1 or touch_guard > 0 then return end
    press_at(to_base(x, y))
end
