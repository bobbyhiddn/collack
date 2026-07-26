-- Pure presentation adapter over battle/. It runs the canonical deterministic
-- engine to obtain an event sequence, then initializes and advances display
-- state solely from that sequence. No combat rule or mutable engine snapshot is
-- retained here, and this module runs under plain Lua for headless replay tests.

local engine = require("battle.engine")
local setup = require("battle.setup")

local M = {}

M.DEFAULT_SEED = 9125
M.EVENT_SECONDS = 0.16

local function deep_copy(source, seen)
    if type(source) ~= "table" then return source end
    seen = seen or {}
    if seen[source] then error("event sequences must not contain cycles") end
    seen[source] = true
    local out = {}
    for key, value in pairs(source) do
        out[deep_copy(key, seen)] = deep_copy(value, seen)
    end
    seen[source] = nil
    return out
end

local function project_side(source)
    assert(type(source) == "table", "battle_start is missing a side snapshot")
    local side = {
        id = source.id,
        name = source.name,
        sling_id = source.sling_id,
        sling_name = source.sling_name,
        rows = source.rows,
        cols = source.cols,
        bricks_alive = source.bricks_alive,
        marbles_alive = source.marbles_alive,
        grid = {},
        marbles = {},
        queue = {},
        active = nil,
    }

    for row = 1, side.rows do
        side.grid[row] = {}
    end
    for _, brick in ipairs(source.bricks or {}) do
        side.grid[brick.row][brick.col] = {
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

    for _, source_marble in ipairs(source.marbles or {}) do
        local marble = {
            uid = source_marble.uid,
            name = source_marble.name,
            rarity = source_marble.rarity,
            core = source_marble.core,
            lane = source_marble.lane,
            state = source_marble.state,
            alive = source_marble.alive,
            shells = {},
            statuses = {},
            flash = nil,
        }
        for _, shell in ipairs(source_marble.shells or {}) do
            marble.shells[#marble.shells + 1] = deep_copy(shell)
        end
        side.marbles[marble.uid] = marble
    end
    for _, uid in ipairs(source.queue or {}) do
        side.queue[#side.queue + 1] = uid
    end
    return side
end

local function view_from_start(event)
    assert(event and event.type == "battle_start",
        "event sequence must begin with battle_start")
    local initial = event.initial_state
    assert(type(initial) == "table" and initial.protocol_version == 1,
        "battle_start has no supported initial-state payload")
    assert(type(initial.sides) == "table",
        "battle_start initial-state payload has no sides")
    return {
        seed = event.seed,
        volley = 0,
        seq = 0,
        current = nil,
        feed = {},
        finished = false,
        outcome = nil,
        winner = nil,
        reason = nil,
        sides = {
            A = project_side(initial.sides.A),
            B = project_side(initial.sides.B),
        },
    }
end

local function result_from_events(events)
    for index = #events, 1, -1 do
        local event = events[index]
        if event.type == "battle_end" then
            return {
                outcome = event.outcome,
                winner = event.winner ~= "none" and event.winner or nil,
                reason = event.reason,
                volleys = event.volleys,
            }
        end
    end
    return nil
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

--- Build a presentation from canonical events alone. The sequence is copied so
--- callers may discard or mutate their decoded/engine-owned representation.
function M.from_events(events)
    assert(type(events) == "table" and #events > 0,
        "from_events needs a non-empty event sequence")
    local copied_events = deep_copy(events)
    local first = copied_events[1]
    local model = {
        seed = first.seed,
        view = view_from_start(first),
        cursor = 0,
        elapsed = M.EVENT_SECONDS,
        interval = M.EVENT_SECONDS,
        playing = true,
        events = copied_events,
    }
    model.result = result_from_events(copied_events)
    return model
end

function M.new(seed)
    seed = math.floor(tonumber(seed) or M.DEFAULT_SEED)
    local battle = engine.new_battle({
        seed = seed,
        sides = setup.default_matchup(),
    })
    engine.run(battle)
    local model = M.from_events(battle.log.events)
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
    local replay = M.from_events(model.events)
    replay.log_text = model.log_text
    return replay
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

-- Product-shaped snapshot projection added by the run-loop slice.  The legacy
-- event adapter above remains available only until the continuous battle
-- integration replaces the exhibition boot path.
function M.project(run_snapshot, previous_frame, current_frame, alpha)
    return require("run_presentation").project(
        run_snapshot,
        previous_frame,
        current_frame,
        alpha
    )
end

return M
