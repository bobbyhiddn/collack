-- src/presentation.lua -- value-only projection and recorded-frame replay.
--
-- The canonical engine owns movement and outcomes.  This module only
-- interpolates two BattleFrame values and turns exact-tick events into cues.

local M = {}

M.SCHEMA_VERSION = 2
M.DEFAULT_SEED = 9125

local function copy(source, seen)
    if type(source) ~= "table" then return source end
    seen = seen or {}
    if seen[source] then error("presentation values cannot contain cycles") end
    seen[source] = true
    local out = {}
    for key, value in pairs(source) do out[copy(key, seen)] = copy(value, seen) end
    seen[source] = nil
    return out
end

local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function lerp(left, right, alpha)
    return left + (right - left) * alpha
end

local function by_id(items, key)
    local out = {}
    for _, item in ipairs(items or {}) do out[item[key or "id"]] = item end
    return out
end

local function project_side(previous, current, alpha)
    local prior_marbles = previous and by_id(previous.marbles, "uid") or {}
    local side = {
        id = current.id,
        name = current.name,
        sling_id = current.sling_id,
        sling_name = current.sling_name,
        rows = current.rows,
        cols = current.cols,
        bricks_alive = current.bricks_alive,
        marbles_alive = current.marbles_alive,
        grid = {},
        bricks = {},
        marbles = {},
        marble_list = {},
        queue = copy(current.queue),
        bag = copy(current.bag),
        active = nil,
        active_list = {},
    }
    for row = 1, side.rows do side.grid[row] = {} end
    for _, source in ipairs(current.bricks or {}) do
        local brick = copy(source)
        brick.hp_ratio = brick.max_hp > 0 and brick.hp / brick.max_hp or 0
        side.grid[brick.row][brick.col] = brick
        side.bricks[#side.bricks + 1] = brick
    end
    for _, source in ipairs(current.marbles or {}) do
        local marble = copy(source)
        local prior = prior_marbles[marble.uid]
        if prior and prior.x and marble.x then
            marble.render_x = lerp(prior.x, marble.x, alpha)
            marble.render_y = lerp(prior.y, marble.y, alpha)
        else
            marble.render_x, marble.render_y = marble.x, marble.y
        end
        local durability, maximum = 0, 0
        for _, shell in ipairs(marble.shells or {}) do
            durability = durability + math.max(0, shell.durability)
            maximum = maximum + shell.max_durability
        end
        marble.shell_ratio = maximum > 0 and durability / maximum or 0
        side.marbles[marble.uid] = marble
        side.marble_list[#side.marble_list + 1] = marble
        if marble.alive and (marble.state == "flying" or marble.state == "blown") then
            side.active_list[#side.active_list + 1] = marble
            side.active = side.active or marble
        end
    end
    return side
end

--- Project two completed canonical frames into a renderer-owned value.
--- `alpha` is render interpolation only and cannot affect either frame.
function M.project(current, previous, alpha)
    assert(type(current) == "table" and current.schema_version,
        "presentation.project needs a BattleFrame")
    previous = previous or current
    alpha = clamp(tonumber(alpha) or 1, 0, 1)
    local state = {
        schema_version = M.SCHEMA_VERSION,
        screen = current.result and "result" or "battle",
        seed = current.seed,
        tick = current.tick,
        time = current.time,
        exchange = current.exchange,
        volley = current.exchange,
        alpha = alpha,
        arena = copy(current.arena),
        world = {
            width = current.world.width,
            height = current.world.height,
            fields = copy(current.world.fields),
        },
        sides = {},
        entities = {},
        effect_cues = {},
        finished = current.result ~= nil,
        result = copy(current.result),
        outcome = current.result and current.result.outcome or nil,
        winner = current.result and current.result.winner or nil,
        reason = current.result and current.result.reason or nil,
    }
    state.sides.A = project_side(previous.sides and previous.sides.A, current.sides.A, alpha)
    state.sides.B = project_side(previous.sides and previous.sides.B, current.sides.B, alpha)
    for _, side_id in ipairs({ "A", "B" }) do
        local side = state.sides[side_id]
        for _, brick in ipairs(side.bricks) do
            state.entities[#state.entities + 1] = {
                type = "brick", owner = side_id, id = brick.body_id,
                art_id = "brick." .. brick.id, behaviour = brick.behaviour,
                family = brick.family, x = brick.x, y = brick.y,
                width = brick.width, height = brick.height,
                hp_ratio = brick.hp_ratio, alive = brick.alive,
            }
        end
        for _, marble in ipairs(side.marble_list) do
            if marble.alive and marble.render_x then
                state.entities[#state.entities + 1] = {
                    type = "marble", owner = side_id, id = marble.body_id,
                    uid = marble.uid, art_id = "marble." .. marble.rarity,
                    x = marble.render_x, y = marble.render_y,
                    radius = marble.radius, state = marble.state,
                    shell_ratio = marble.shell_ratio, statuses = copy(marble.statuses),
                }
            end
        end
    end
    return state
end

local function readable(value)
    return tostring(value or ""):gsub("_", " ")
end

function M.event_text(event, names)
    names = names or { A = "A", B = "B" }
    local actor = names[event.side] or "Arena"
    if event.type == "battle_start" then
        return string.format("Battle seeded %d", event.seed)
    elseif event.type == "exchange_start" or event.type == "volley_start" then
        return string.format("Exchange %d: both sides launch", event.exchange or event.volley)
    elseif event.type == "launch" then
        return string.format("%s launches %s", actor, event.name)
    elseif event.type == "collision" then
        return string.format("%s hits %s for %d", actor, readable(event.brick), event.damage)
    elseif event.type == "brick_destroyed" then
        return string.format("%s loses %s", actor, readable(event.brick))
    elseif event.type == "shell_break" then
        return string.format("%s shell breaks", actor)
    elseif event.type == "core_release" then
        return string.format("%s releases %s", actor, readable(event.release))
    elseif event.type == "blowback" then
        return string.format("%s release pushes %d marble(s)", actor, #(event.affected or {}))
    elseif event.type == "status_applied" then
        return string.format("%s gains %s", actor, readable(event.status))
    elseif event.type == "battle_end" then
        if event.outcome == "draw" then return "Draw: " .. readable(event.reason) end
        return string.format("%s wins", names[event.winner] or event.winner)
    end
    return actor .. ": " .. readable(event.type)
end

function M.cues(events)
    local cues = {}
    for _, event in ipairs(events or {}) do
        local cue = {
            seq = event.seq,
            tick = event.tick,
            type = event.type,
            owner = event.side,
            x = event.x,
            y = event.y,
            text = M.event_text(event),
        }
        if event.type == "collision" then cue.effect = "impact"
        elseif event.type == "brick_destroyed" then cue.effect = "brick_break"
        elseif event.type == "shell_break" then cue.effect = "shell_break"
        elseif event.type == "core_release" or event.type == "blowback" then cue.effect = "release"
        elseif event.type == "status_applied" then cue.effect = event.status
        elseif event.type == "wall_collision" or event.type == "ricochet" then cue.effect = "ricochet"
        elseif event.type == "battle_end" then cue.effect = "result"
        else cue.effect = "audit" end
        cues[#cues + 1] = cue
    end
    return cues
end

--- Construct playback from canonical recorded frames.  Playback never calls
--- battle.step; it seeks and interpolates immutable frame values.
function M.from_recording(recording)
    assert(type(recording) == "table" and #recording.frames > 0,
        "from_recording needs canonical frames")
    local owned = copy(recording)
    return {
        schema_version = M.SCHEMA_VERSION,
        recording = owned,
        cursor = 1,
        event_cursor = 0,
        elapsed = 0,
        interval = owned.frame_interval * owned.fixed_dt,
        playing = true,
        finished = #owned.frames == 1,
    }
end

function M.replay_step(replay, count)
    count = count or 1
    replay.cursor = math.min(#replay.recording.frames, replay.cursor + count)
    if replay.cursor >= #replay.recording.frames then
        replay.playing = false
        replay.finished = true
    end
    return replay.recording.frames[replay.cursor]
end

function M.replay_update(replay, dt, speed)
    if not replay.playing then return end
    replay.elapsed = replay.elapsed + math.max(0, tonumber(dt) or 0) * (speed or 1)
    while replay.elapsed >= replay.interval and replay.playing do
        replay.elapsed = replay.elapsed - replay.interval
        M.replay_step(replay, 1)
    end
end

function M.replay_seek(replay, tick)
    local frames = replay.recording.frames
    local selected = 1
    for index, frame in ipairs(frames) do
        if frame.tick > tick then break end
        selected = index
    end
    replay.cursor = selected
    replay.elapsed = 0
    replay.finished = selected >= #frames
    replay.playing = not replay.finished
    return frames[selected]
end

function M.replay_project(replay)
    local current = replay.recording.frames[replay.cursor]
    local previous = replay.recording.frames[math.max(1, replay.cursor - 1)]
    local alpha = replay.interval > 0 and replay.elapsed / replay.interval or 1
    return M.project(current, previous, alpha)
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
