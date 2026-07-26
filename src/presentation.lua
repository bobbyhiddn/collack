-- Pure presentation adapter over battle/. It runs the canonical deterministic
-- engine once, snapshots the initial display state, then advances that display
-- solely by consuming the engine's event log. No combat rule is implemented
-- here, and this module runs under plain Lua for headless replay tests.

local engine = require("battle.engine")
local setup = require("battle.setup")

local M = {}

M.DEFAULT_SEED = 9125
M.EVENT_SECONDS = 0.16

local function copy_shells(source)
    local out = {}
    for index, shell in ipairs(source) do
        out[index] = {
            mineral = shell.mineral,
            pattern = shell.pattern,
            durability = shell.durability,
            max_durability = shell.max_durability,
        }
    end
    return out
end

local function snapshot_side(player)
    local side = {
        id = player.id,
        name = player.name,
        sling_id = player.sling.id,
        sling_name = player.sling.name,
        rows = player.formation.rows,
        cols = player.formation.cols,
        bricks_alive = player.formation.alive,
        marbles_alive = #player.roster,
        grid = {},
        marbles = {},
        queue = {},
        active = nil,
    }

    for row = 1, player.formation.rows do
        side.grid[row] = {}
        for col = 1, player.formation.cols do
            local brick = player.formation.grid[row][col]
            if brick then
                side.grid[row][col] = {
                    id = brick.id,
                    name = brick.name,
                    family = brick.family,
                    behaviour = brick.behaviour,
                    hp = brick.hp,
                    max_hp = brick.max_hp,
                    alive = brick.alive,
                    flash = nil,
                }
            end
        end
    end

    for _, marble in ipairs(player.roster) do
        side.marbles[marble.uid] = {
            uid = marble.uid,
            name = marble.name,
            rarity = marble.rarity,
            core = marble.core.name,
            lane = marble.lane,
            state = marble.state,
            alive = true,
            shells = copy_shells(marble.shells),
            statuses = {},
            flash = nil,
        }
    end
    for _, marble in ipairs(player.queue) do
        side.queue[#side.queue + 1] = marble.uid
    end
    return side
end

local function remove_uid(list, uid)
    for index = 1, #list do
        if list[index] == uid then
            table.remove(list, index)
            return
        end
    end
end

local function contains_uid(list, uid)
    for _, candidate in ipairs(list) do
        if candidate == uid then return true end
    end
    return false
end

local function find_marble(view, uid)
    local marble = view.sides.A.marbles[uid]
    if marble then return marble, view.sides.A end
    marble = view.sides.B.marbles[uid]
    if marble then return marble, view.sides.B end
    return nil, nil
end

local function brick_at(view, side_id, row, col)
    local side = view.sides[side_id]
    if not side or not side.grid[row] then return nil end
    return side.grid[row][col]
end

local function readable(value)
    return tostring(value or ""):gsub("_", " ")
end

function M.event_text(model, event)
    local side = model.view.sides[event.side]
    local actor = side and side.name or "Arena"
    if event.type == "battle_start" then
        return string.format("Battle seeded %d: both formations locked", event.seed)
    elseif event.type == "volley_start" then
        return string.format("Volley %d: simultaneous commitment", event.volley)
    elseif event.type == "launch" then
        return string.format("%s launches %s from lane %d", actor, event.name, event.lane)
    elseif event.type == "launch_aborted" then
        return string.format("%s launch aborted: %s", actor, readable(event.reason))
    elseif event.type == "collision" then
        return string.format("%s hits %s at %d,%d for %d", actor,
            readable(event.brick), event.row, event.col, event.damage)
    elseif event.type == "brick_damaged" then
        return string.format("%s's %s has %d HP", actor, readable(event.brick), event.hp_left)
    elseif event.type == "brick_destroyed" then
        return string.format("%s loses %s - %d bricks remain", actor,
            readable(event.brick), event.bricks_left)
    elseif event.type == "shell_damaged" or event.type == "shell_crushed" then
        return string.format("%s shell takes damage - %d durability", actor, event.durability_left)
    elseif event.type == "shell_break" then
        return string.format("%s shell breaks - %d layers remain", actor, event.shells_left)
    elseif event.type == "marble_destroyed" then
        return string.format("%s loses %s - core recovered", actor, event.name)
    elseif event.type == "core_release" then
        return string.format("%s releases %s at lane %d", actor, readable(event.release), event.col)
    elseif event.type == "blowback" then
        return string.format("%s blowback reaches %d lane(s)", actor, event.radius)
    elseif event.type == "blowback_displace" then
        return string.format("%s marble shoved lane %d to %d", actor, event.from, event.to)
    elseif event.type == "status_applied" then
        return string.format("%s applies %s", actor, readable(event.status))
    elseif event.type == "status_tick" then
        return string.format("%s marble suffers %s", actor, readable(event.status))
    elseif event.type == "cascade_end" then
        return string.format("%s cascade ends: %s", actor, readable(event.reason))
    elseif event.type == "battle_end" then
        if event.outcome == "draw" then
            return "Final: draw - " .. readable(event.reason)
        end
        local winner = model.view.sides[event.winner]
        return "Final: " .. (winner and winner.name or event.winner) .. " wins"
    end
    return actor .. " triggers " .. readable(event.type)
end

local function push_feed(model, event)
    local feed = model.view.feed
    feed[#feed + 1] = {
        seq = event.seq,
        side = event.side,
        type = event.type,
        text = M.event_text(model, event),
    }
    while #feed > 6 do table.remove(feed, 1) end
end

--- Apply one canonical log event to display-only state.
function M.apply_event(model, event)
    local view = model.view
    for _, side_id in ipairs({ "A", "B" }) do
        local side = view.sides[side_id]
        for row = 1, side.rows do
            for col = 1, side.cols do
                local brick = side.grid[row][col]
                if brick then brick.flash = nil end
            end
        end
        for _, marble in pairs(side.marbles) do marble.flash = nil end
    end
    view.current = event
    view.seq = event.seq

    if event.type == "volley_start" then
        view.volley = event.volley
    elseif event.type == "launch" then
        local side = view.sides[event.side]
        local marble = side.marbles[event.marble]
        remove_uid(side.queue, event.marble)
        if marble then
            marble.state = "flying"
            marble.lane = nil
        end
        side.active = {
            uid = event.marble,
            name = event.name,
            row = 0,
            col = event.entry_col,
            target_row = event.target_row,
            target_col = event.target_col,
            shot = event.shot,
        }
    elseif event.type == "collision" then
        local side = view.sides[event.side]
        if side.active and side.active.uid == event.marble then
            side.active.row = event.row
            side.active.col = event.col
        end
    elseif event.type == "cascade_end" then
        local side = view.sides[event.side]
        side.active = nil
        view.last_cascade = {
            side = event.side,
            reason = event.reason,
            row = event.row,
            col = event.col,
        }
    elseif event.type == "rack_return" then
        local side = view.sides[event.side]
        local marble = side.marbles[event.marble]
        if marble then
            marble.state = "ready"
            marble.lane = event.lane
            if not contains_uid(side.queue, event.marble) then
                side.queue[#side.queue + 1] = event.marble
            end
        end
    elseif event.type == "brick_damaged" then
        local brick = brick_at(view, event.side, event.row, event.col)
        if brick then
            brick.hp = event.hp_left
            brick.flash = "damage"
        end
    elseif event.type == "brick_destroyed" then
        local side = view.sides[event.side]
        local brick = brick_at(view, event.side, event.row, event.col)
        if brick then
            brick.alive = false
            brick.hp = 0
            brick.flash = "destroyed"
        end
        side.bricks_alive = event.bricks_left
    elseif event.type == "regenerate" or event.type == "temporal" then
        local brick = brick_at(view, event.side, event.row, event.col)
        if brick then
            brick.hp = event.hp_left
            brick.flash = "heal"
        end
    elseif event.type == "shell_damaged" or event.type == "shell_crushed" then
        local marble = find_marble(view, event.marble)
        if marble and marble.shells[1] then
            marble.shells[1].durability = event.durability_left
            marble.flash = "damage"
        end
    elseif event.type == "shell_break" then
        local marble = find_marble(view, event.marble)
        if marble and #marble.shells > event.shells_left then
            table.remove(marble.shells, 1)
            marble.flash = "break"
        end
    elseif event.type == "marble_destroyed" then
        local marble, side = find_marble(view, event.marble)
        if marble then
            marble.alive = false
            marble.state = "destroyed"
            marble.lane = nil
        end
        if side then
            remove_uid(side.queue, event.marble)
            if side.active and side.active.uid == event.marble then side.active = nil end
            side.marbles_alive = event.marbles_left
        end
    elseif event.type == "blowback_displace" then
        local marble = find_marble(view, event.marble)
        if marble then marble.lane = event.to end
    elseif event.type == "status_applied" then
        local marble = find_marble(view, event.marble)
        if marble then marble.statuses[event.status] = event.duration end
    elseif event.type == "status_tick" then
        local marble = find_marble(view, event.marble)
        if marble then
            local left = (marble.statuses[event.status] or 1) - 1
            marble.statuses[event.status] = left > 0 and left or nil
        end
    elseif event.type == "battle_end" then
        view.finished = true
        view.outcome = event.outcome
        view.winner = event.winner ~= "none" and event.winner or nil
        view.reason = event.reason
    end

    push_feed(model, event)
end

function M.new(seed)
    seed = math.floor(tonumber(seed) or M.DEFAULT_SEED)
    local battle = engine.new_battle({
        seed = seed,
        sides = setup.default_matchup(),
    })
    local model = {
        seed = seed,
        battle = battle,
        view = {
            seed = seed,
            volley = 0,
            seq = 0,
            current = nil,
            feed = {},
            finished = false,
            outcome = nil,
            winner = nil,
            reason = nil,
            sides = {
                A = snapshot_side(battle.sides.A),
                B = snapshot_side(battle.sides.B),
            },
        },
        cursor = 0,
        elapsed = M.EVENT_SECONDS,
        interval = M.EVENT_SECONDS,
        playing = true,
    }
    model.result = engine.run(battle)
    model.events = battle.log.events
    model.log_text = battle.log:text()
    return model
end

function M.step(model, count)
    count = count or 1
    local last = nil
    for _ = 1, count do
        if model.cursor >= #model.events then
            model.playing = false
            break
        end
        model.cursor = model.cursor + 1
        last = model.events[model.cursor]
        M.apply_event(model, last)
    end
    if model.cursor >= #model.events then model.playing = false end
    return last
end

function M.update(model, dt)
    if not model.playing then return end
    model.elapsed = model.elapsed + math.max(0, tonumber(dt) or 0)
    while model.elapsed >= model.interval and model.playing do
        model.elapsed = model.elapsed - model.interval
        M.step(model, 1)
    end
end

function M.replay(model)
    return M.new(model.seed)
end

function M.next_seed(model)
    local seed = model.seed + 1
    if seed >= 2147483647 then seed = 1 end
    return M.new(seed)
end

function M.to_end(model)
    while model.cursor < #model.events do M.step(model, 1) end
    return model
end

return M
