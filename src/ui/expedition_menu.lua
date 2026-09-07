-- Presentation-only front door. The live run is frozen while this menu is open.
local M = {}

function M.actions(context)
    local desktop = context.width > 900
    local x, y, width = desktop and 112 or 36, desktop and 444 or 504,
        desktop and 388 or 318
    local items = {}
    if context.page == "help" then y = desktop and 620 or 624 end
    local function add(id, label)
        items[#items + 1] = { id = id, label = label, x = x,
            y = y + (#items * 68), width = width, height = 56 }
    end
    if context.page == "help" then
        add("back", "GOT IT")
    elseif context.page == "confirm" then
        add("back", "KEEP MY EXPEDITION")
        add("start", "START A NEW EXPEDITION")
    else
        if context.can_resume then add("resume", "CONTINUE EXPEDITION") end
        add("new", "NEW EXPEDITION")
        add("help", "HOW TO PLAY")
    end
    return items
end

function M.draw(context)
    local g, c, fonts = love.graphics, context.colors, context.fonts
    local desktop, width = context.width > 900, context.width
    local x, text_width = desktop and 112 or 36, desktop and 480 or 318
    local function color(value, alpha) g.setColor(value[1], value[2], value[3], alpha or 1) end
    color(c.felt)
    g.rectangle("fill", 0, 0, width, context.height)
    color(c.walnut_mid)
    g.rectangle("fill", 12, 12, width - 24, context.height - 24, 20, 20)
    color(c.felt)
    g.rectangle("fill", 20, 20, width - 40, context.height - 40, 16, 16)
    color(c.brass_dark, 0.65)
    g.rectangle("line", 26, 26, width - 52, context.height - 52, 14, 14)
    g.setFont(fonts.result)
    color(c.chalk)
    g.printf("COLLACK", x, desktop and 104 or 74, text_width, desktop and "left" or "center")
    g.setFont(fonts.label)
    color(c.brass)
    g.printf("BRICKBREAKER / AUTOBATTLER", x, desktop and 152 or 124,
        text_width, desktop and "left" or "center")

    if context.page == "help" then
        local steps = {
            { "01  BUILD YOUR DEFENSE", "Tap a brick, then a grid cell. Put a Fortifier beside other bricks to protect them. Quick arrange fills empty spaces for you." },
            { "02  ORDER YOUR ATTACK", "Your marbles launch from left to right in bag order. Their shells, cores, and your sling shape every ricochet." },
            { "03  WATCH. REFIT. REPEAT.", "Combat plays itself. Break all rival bricks or outlast their marbles to win. Choose an upgrade after each victory. Clear three rivals to win the expedition." },
        }
        for i, step in ipairs(steps) do
            local y = (desktop and 224 or 183) + (i - 1) * (desktop and 102 or 132)
            g.setFont(fonts.label); color(c.brass); g.printf(step[1], x, y, text_width, "left")
            g.setFont(fonts.body); color(c.chalk); g.printf(step[2], x, y + 23, text_width, "left")
        end
    elseif context.page == "confirm" then
        g.setFont(fonts.display); color(c.chalk)
        g.printf("Begin again?", x, desktop and 264 or 270, text_width, "left")
        g.setFont(fonts.body); color(c.muted)
        g.printf("Starting a new expedition replaces your saved run. You can keep playing your current collection instead.",
            x, desktop and 316 or 326, text_width, "left")
    else
        local bx, by, bw, bh = desktop and 686 or 54, desktop and 154 or 185,
            desktop and 464 or 282, desktop and 470 or 218
        color(c.shadow, 0.6); g.rectangle("fill", bx + 4, by + 5, bw, bh, 16, 16)
        color(c.felt_mid); g.rectangle("fill", bx, by, bw, bh, 16, 16)
        color(c.brass_dark); g.setLineWidth(2); g.rectangle("line", bx, by, bw, bh, 16, 16)
        local brick_w, brick_h = bw * 0.17, bh * 0.09
        for row = 1, 2 do for col = 1, 4 do
            local xx = bx + bw * 0.08 + (col - 1) * bw * 0.21
            local yy = by + bh * 0.12 + (row - 1) * bh * 0.13
            context.brick(xx, yy, brick_w, brick_h,
                col % 2 == 0 and "defensive" or "utility", col % 2 == 0 and "fortify" or "reflect", 1, false)
        end end
        color(c.brass, 0.5); g.setLineWidth(2)
        g.line(bx + bw * 0.48, by + bh * 0.88, bx + bw * 0.92, by + bh * 0.49,
            bx + bw * 0.7, by + bh * 0.31)
        context.marble(bx + bw * 0.7, by + bh * 0.49, desktop and 22 or 14,
            "uncommon", "jade", 1, nil, false)
        context.marble(bx + bw * 0.48, by + bh * 0.88, desktop and 25 or 16,
            "common", "quartz", 1, nil, false)
        g.setLineWidth(1)
        g.setFont(fonts.body); color(c.chalk)
        g.printf("Build your formation. Unleash your marbles. Let the ricochets decide.",
            x, desktop and 232 or 426, text_width, desktop and "left" or "center")
        if desktop then
            g.setFont(fonts.card); color(c.brass)
            g.printf("Three rivals. One collection. Every placement matters.", x, 318, 448, "left")
        end
    end

    for i, action in ipairs(M.actions(context)) do
        local primary = i == 1
        color(primary and c.brass or c.felt_mid)
        g.rectangle("fill", action.x, action.y, action.width, action.height, 10, 10)
        color(context.focus == i and c.focus or c.brass_dark)
        g.setLineWidth(context.focus == i and 3 or 1)
        g.rectangle("line", action.x, action.y, action.width, action.height, 10, 10)
        g.setLineWidth(1); g.setFont(fonts.label); color(primary and c.ink or c.chalk)
        g.printf(action.label, action.x + 10, action.y + 20, action.width - 20, "center")
    end
    g.setFont(fonts.micro); color(c.muted)
    g.printf(context.note or "Progress saves between fights. Battle resumes from your last formation.",
        desktop and 112 or 36, desktop and 706 or 752, desktop and 1000 or 318,
        desktop and "left" or "center")
end

return M
