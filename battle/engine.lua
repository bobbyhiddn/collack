-- battle/engine.lua — the Callack battle simulation.
--
-- Pure Lua. No love.*, no io, no os.time, no math.random. Everything that could
-- vary between runs is either derived from the seed or fixed by construction,
-- because the contract is: same seed + same setup => byte-identical battle log.
--
-- Shape of a battle (see docs/decisions/0004-battle-sim-model.md):
--
--   * Two players, A and B. Each has a brick FORMATION on a fixed grid and a
--     RACK of marbles sitting in lanes, fired by a SLING.
--   * Play proceeds in VOLLEYS. In each volley BOTH players commit their next
--     marble before either cascade resolves, and win conditions are checked
--     only once both cascades are done. That is what makes this simultaneous
--     rather than turn-taking: neither side can be denied its shot, and neither
--     side can win "first" inside a volley.
--   * A launched marble CASCADES through the opponent's formation, colliding
--     brick by brick, until it runs out of momentum, leaves the grid, or loses
--     its last shell. Only when both cascades have finished does the next
--     volley begin.
--   * When a marble's last shell breaks the core is exposed and RELEASES. The
--     release always produces baseline blowback, which displaces marbles within
--     a radius on BOTH racks — the firing player's own marbles included.
--
-- Column space and lane space are the same integer space: column c of either
-- formation is lane c of either rack. That is the coupling that lets a core
-- released deep in the enemy formation shove your own marbles around.

local RNG = require("battle.rng")
local Log = require("battle.battlelog")
local effects = require("battle.effects")
local formation_mod = require("battle.formation")
local marble_mod = require("battle.marble")

local slings = require("battle.content.slings")

local M = {}

M.DEFAULT_MAX_VOLLEYS = 40
M.MAX_CHAIN_DEPTH = 3      -- chain bricks detonating chain bricks
M.MAX_BLOWBACK_DEPTH = 3   -- a blowback kill triggering another blowback
M.MAX_CASCADE_STEPS = 200  -- belt-and-braces guard; momentum already bounds this

local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function remove_from(list, item)
    for index = 1, #list do
        if list[index] == item then
            table.remove(list, index)
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

local function resolve_sling(spec)
    if type(spec) == "table" then return spec end
    local sling = slings.by_id[spec or "training_sling"]
    if not sling then
        error("unknown sling: " .. tostring(spec))
    end
    return sling
end

--- Spread n marbles evenly across `cols` lanes. Integer arithmetic on exact
--- doubles, so the placement is identical everywhere.
local function default_lane(index, count, cols)
    return math.floor(((2 * index - 1) * cols) / (2 * count)) + 1
end

local function build_player(id, def, cols)
    local sling = resolve_sling(def.sling)
    local player = {
        id = id,
        name = def.name or id,
        sling = sling,
        formation = formation_mod.build(def.formation),
        rack = {},    -- lane -> marble
        roster = {},  -- every live marble, stable order
        queue = {},   -- firing order
        bag = {},     -- core ids recovered from destroyed marbles
        lanes = cols,
    }

    local defs = def.marbles or {}
    if #defs < 1 then
        error(string.format("player %s has no marbles", id))
    end
    if #defs > cols then
        error(string.format("player %s has %d marbles but only %d lanes", id, #defs, cols))
    end

    for index, marble_def in ipairs(defs) do
        local marble = marble_mod.build(marble_def, sling, id)
        local lane = marble_def.lane or default_lane(index, #defs, cols)
        if lane < 1 or lane > cols then
            error(string.format("marble %q lane %d is outside 1..%d", tostring(marble_def.name), lane, cols))
        end
        if player.rack[lane] then
            error(string.format("two marbles assigned to lane %d for player %s", lane, id))
        end
        marble.lane = lane
        player.rack[lane] = marble
        player.roster[#player.roster + 1] = marble
        -- Firing order is the player's declared order (ADR 0004), not a shuffle.
        player.queue[#player.queue + 1] = marble
    end

    return player
end

--- Create a battle. opts:
---   seed          — integer seed (required for a reproducible battle)
---   sides         — { A = <player def>, B = <player def> }
---   max_volleys   — draw-by-exhaustion cap
--- A player def is { name, sling, formation = <layout>, marbles = { <def>... } }.
function M.new_battle(opts)
    assert(type(opts) == "table", "new_battle needs an options table")
    assert(opts.sides and opts.sides.A and opts.sides.B, "new_battle needs sides A and B")

    -- uids are per-battle so that running two battles in one process yields the
    -- same log for the same seed both times.
    marble_mod.reset_uids()

    local a_cols = #opts.sides.A.formation[1]
    local b_cols = #opts.sides.B.formation[1]
    if a_cols ~= b_cols then
        error(string.format("both formations must be the same width (A=%d, B=%d); "
            .. "columns and rack lanes share one coordinate space", a_cols, b_cols))
    end

    local battle = {
        seed = math.floor(tonumber(opts.seed) or 1),
        rng = RNG.new(opts.seed),
        log = Log.new(),
        volley = 0,
        max_volleys = opts.max_volleys or M.DEFAULT_MAX_VOLLEYS,
        lanes = a_cols,
        order = { "A", "B" },
        sides = {},
        result = nil,
    }

    battle.sides.A = build_player("A", opts.sides.A, a_cols)
    battle.sides.B = build_player("B", opts.sides.B, b_cols)

    battle.log:add(0, "-", "battle_start", {
        seed = battle.seed,
        lanes = battle.lanes,
        a_marbles = #battle.sides.A.roster,
        b_marbles = #battle.sides.B.roster,
        a_bricks = battle.sides.A.formation.alive,
        b_bricks = battle.sides.B.formation.alive,
        max_volleys = battle.max_volleys,
    })

    return battle
end

local function opponent_of(battle, player)
    if player.id == "A" then return battle.sides.B end
    return battle.sides.A
end

local function log(battle, side, kind, fields)
    return battle.log:add(battle.volley, side, kind, fields)
end

-- ---------------------------------------------------------------------------
-- Bricks
-- ---------------------------------------------------------------------------

local damage_brick

--- A chain brick detonating into its orthogonal neighbours. Depth-capped so a
--- dense field of chain bricks cannot recurse forever.
local function detonate(battle, owner, brick, depth)
    if depth > M.MAX_CHAIN_DEPTH then
        log(battle, owner.id, "chain_capped", { row = brick.row, col = brick.col, depth = depth })
        return
    end
    log(battle, owner.id, "chain_detonate", {
        brick = brick.id, row = brick.row, col = brick.col, damage = brick.chain_damage, depth = depth,
    })
    for _, neighbour in ipairs(formation_mod.neighbours(owner.formation, brick.row, brick.col)) do
        damage_brick(battle, owner, neighbour, brick.chain_damage, "chain", depth)
    end
end

--- Apply damage to a brick. `owner` is the player whose formation it belongs
--- to. Returns true if this call destroyed it.
function damage_brick(battle, owner, brick, amount, source, depth)
    if not brick.alive or amount <= 0 then return false end
    brick.hp = brick.hp - amount
    log(battle, owner.id, "brick_damaged", {
        brick = brick.id, row = brick.row, col = brick.col,
        damage = amount, hp_left = math.max(0, brick.hp), source = source,
    })
    if brick.hp > 0 then return false end

    formation_mod.kill(owner.formation, brick)
    log(battle, owner.id, "brick_destroyed", {
        brick = brick.id, row = brick.row, col = brick.col,
        source = source, bricks_left = owner.formation.alive,
    })
    if brick.behaviour == "chain" then
        detonate(battle, owner, brick, (depth or 0) + 1)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Marble destruction, core release, blowback
-- ---------------------------------------------------------------------------

local apply_blowback

local function destroy_marble(battle, owner, marble, cause)
    if marble.state == "destroyed" then return end
    marble.state = "destroyed"
    if marble.lane and owner.rack[marble.lane] == marble then
        owner.rack[marble.lane] = nil
    end
    remove_from(owner.roster, marble)
    remove_from(owner.queue, marble)
    -- The core survives the marble and returns to the owner's bag. It is not a
    -- combat unit: bagged cores never re-enter the battle, they are what the
    -- owner walks away with. See ADR 0004.
    owner.bag[#owner.bag + 1] = marble.core.id
    log(battle, owner.id, "marble_destroyed", {
        marble = marble.uid, name = marble.name, cause = cause,
        marbles_left = #owner.roster, core_bagged = marble.core.id,
    })
end

--- The core is exposed and lets go. `col` is the lane/column the release
--- happens in; `owner` is the marble's player, `other` the opponent.
--- `formation_owner` is whose bricks (if any) are around the release point —
--- nil when the release happens in a rack rather than on a formation.
local function release_core(battle, owner, other, marble, col, row, formation_owner, depth)
    local profile = effects.release_profile(marble.core.release)
    log(battle, owner.id, "core_release", {
        marble = marble.uid, core = marble.core.id, release = profile.id,
        col = col, row = row or -1, depth = depth,
    })

    destroy_marble(battle, owner, marble, "core_released")

    -- Baseline blowback always fires, for every rarity, including common.
    apply_blowback(battle, owner, other, col, profile, depth)

    -- Release effects that touch bricks only apply when the core popped inside
    -- a formation.
    if profile.shrapnel > 0 and formation_owner then
        log(battle, formation_owner.id, "shrapnel", { col = col, row = row, damage = profile.shrapnel })
        for _, neighbour in ipairs(formation_mod.neighbours(formation_owner.formation, row, col)) do
            damage_brick(battle, formation_owner, neighbour, profile.shrapnel, "shrapnel", 0)
        end
    end
end

--- Grind durability off a racked marble's outermost shell. Returns the marble
--- if this killed it (caller queues the secondary release), nil otherwise.
local function crush_shell(battle, owner, marble, amount, cause)
    local shell = marble.shells[1]
    if not shell then return marble end
    shell.durability = shell.durability - amount
    log(battle, owner.id, "shell_crushed", {
        marble = marble.uid, mineral = shell.mineral, pattern = shell.pattern,
        durability_left = math.max(0, shell.durability), cause = cause,
    })
    if shell.durability > 0 then return nil end
    table.remove(marble.shells, 1)
    log(battle, owner.id, "shell_break", {
        marble = marble.uid, mineral = shell.mineral, shells_left = #marble.shells, cause = cause,
    })
    if #marble.shells == 0 then
        return marble
    end
    return nil
end

--- Baseline blowback: displace every marble within `radius` lanes of the
--- epicentre, on BOTH racks. The firing player's own rack is processed FIRST,
--- deliberately — friendly displacement is a rule of the game, not a side
--- effect, and putting it first makes that obvious in the log.
---
--- A marble shoved into a lane that is off the rack or already occupied cannot
--- move, so it takes the force instead and loses a point of shell durability.
--- That is the cost of clustering.
function apply_blowback(battle, owner, other, epicentre, profile, depth)
    depth = depth or 1
    if depth > M.MAX_BLOWBACK_DEPTH then
        log(battle, owner.id, "blowback_capped", { col = epicentre, depth = depth })
        return
    end

    log(battle, owner.id, "blowback", {
        col = epicentre, radius = profile.radius, release = profile.id,
        invert = profile.invert, depth = depth,
    })

    local secondaries = {}

    for _, side in ipairs({ owner, other }) do
        local ally = (side.id == owner.id)

        -- Collect affected marbles, then order them so they get out of each
        -- other's way: pushed outward, the far ones move first; pulled inward,
        -- the near ones move first. Ties break on lane, so the order is total.
        local affected = {}
        for lane = 1, side.lanes do
            local marble = side.rack[lane]
            if marble and math.abs(lane - epicentre) <= profile.radius then
                affected[#affected + 1] = marble
            end
        end
        table.sort(affected, function(left, right)
            local dl = math.abs(left.lane - epicentre)
            local dr = math.abs(right.lane - epicentre)
            if dl ~= dr then
                if profile.invert then return dl < dr end
                return dl > dr
            end
            return left.lane < right.lane
        end)

        for _, marble in ipairs(affected) do
            local delta = marble.lane - epicentre
            local direction
            if delta == 0 then
                -- Sitting exactly on the epicentre: nothing decides which way
                -- it goes but the seed.
                direction = battle.rng:sign()
            elseif delta > 0 then
                direction = 1
            else
                direction = -1
            end
            if profile.invert then direction = -direction end

            local target = marble.lane + direction
            local blocked = target < 1 or target > side.lanes or side.rack[target] ~= nil
            if blocked then
                log(battle, side.id, "blowback_blocked", {
                    marble = marble.uid, lane = marble.lane, into = target, ally = ally,
                })
                local killed = crush_shell(battle, side, marble, 1, "blowback_crush")
                if killed then secondaries[#secondaries + 1] = { side = side, marble = killed } end
            else
                side.rack[marble.lane] = nil
                side.rack[target] = marble
                local from = marble.lane
                marble.lane = target
                log(battle, side.id, "blowback_displace", {
                    marble = marble.uid, from = from, to = target, ally = ally,
                })
            end

            if profile.scorch and marble.state ~= "destroyed" then
                local killed = crush_shell(battle, side, marble, 1, "scorch")
                if killed then secondaries[#secondaries + 1] = { side = side, marble = killed } end
            end
        end
    end

    -- Chained releases run after both racks have settled, so nothing mutates a
    -- rack that is still being walked.
    for _, entry in ipairs(secondaries) do
        local side = entry.side
        local marble = entry.marble
        if marble.state ~= "destroyed" then
            local counterpart = (side.id == owner.id) and other or owner
            release_core(battle, side, counterpart, marble, marble.lane, nil, nil, depth + 1)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Cascade
-- ---------------------------------------------------------------------------

--- One collision between a flying marble and a brick.
--- Returns a table describing what the cascade should do next:
---   { destroyed = bool, momentum_spent = n, dir_flip = bool, traj = n }
local function resolve_collision(battle, attacker, defender, marble, brick, row, col, dir, traj)
    local shell = marble.shells[1]
    marble_mod.assert_core_covered(marble)
    local profile = effects.collision_profile(shell.collision)

    local damage = profile.damage + marble.damage_bonus
    local durability_cost = profile.durability_cost

    if brick.behaviour == "absorb" and not profile.pierces_absorb then
        damage = math.max(0, damage - 1)
        durability_cost = durability_cost + 1
        log(battle, defender.id, "absorb", { brick = brick.id, row = row, col = col, marble = marble.uid })
    end

    log(battle, attacker.id, "collision", {
        marble = marble.uid, effect = profile.id, brick = brick.id,
        row = row, col = col, damage = damage, mineral = shell.mineral, pattern = shell.pattern,
    })

    damage_brick(battle, defender, brick, damage, "collision", 0)

    if profile.splash_behind > 0 then
        local behind = formation_mod.brick_at(defender.formation, row + dir, col)
        if behind then
            damage_brick(battle, defender, behind, profile.splash_behind, "splinter", 0)
        end
    end

    -- Reflect only matters if the pane survived the hit.
    local flipped = false
    if brick.alive and brick.behaviour == "reflect" then
        dir = -dir
        if traj == 0 then
            traj = battle.rng:sign()
        else
            traj = -traj
        end
        flipped = true
        log(battle, defender.id, "reflect", {
            brick = brick.id, row = row, col = col, marble = marble.uid, new_trajectory = traj,
        })
    end

    -- Shell wear happens last, so a shell that breaks on this hit still gets to
    -- deal its damage.
    shell.durability = shell.durability - durability_cost
    local destroyed = false
    if shell.durability <= 0 then
        table.remove(marble.shells, 1)
        log(battle, attacker.id, "shell_break", {
            marble = marble.uid, mineral = shell.mineral, shells_left = #marble.shells, cause = "collision",
        })
        if #marble.shells == 0 then
            release_core(battle, attacker, defender, marble, col, row, defender, 1)
            destroyed = true
        end
    end

    return {
        destroyed = destroyed,
        momentum_cost = profile.momentum_cost,
        dir = dir,
        traj = traj,
        flipped = flipped,
    }
end

--- Pick the brick the sling points at: the live brick nearest the marble's own
--- lane, breaking ties toward the front row and then the left column. The scan
--- order is fixed, so aiming consumes no randomness and is reproducible.
---
--- Aiming is what a sling is FOR, and without it the simulation deadlocks: a
--- marble pinned to its rack lane whose column has already been cleared flies
--- through empty space every volley forever, landing no collisions, wearing no
--- shells, and every battle ends on the volley limit.
local function choose_target(defender, lane)
    local best, best_key = nil, nil
    for row = 1, defender.formation.rows do
        for col = 1, defender.formation.cols do
            local brick = formation_mod.brick_at(defender.formation, row, col)
            if brick then
                local key = { math.abs(col - lane), row, col }
                if not best_key
                    or key[1] < best_key[1]
                    or (key[1] == best_key[1] and key[2] < best_key[2])
                    or (key[1] == best_key[1] and key[2] == best_key[2] and key[3] < best_key[3]) then
                    best, best_key = brick, key
                end
            end
        end
    end
    return best
end

--- Entry column that puts a marble on its target given the core's lateral
--- drift: walk the drift backwards from the target to row 1.
local function entry_column(target, traj, cols)
    if not target then return 1 end
    return clamp(target.col - traj * (target.row - 1), 1, cols)
end

--- Fly one marble through the opponent's formation until it stops or dies.
local function resolve_cascade(battle, attacker, defender, marble)
    marble.state = "flying"
    local home_lane = marble.lane
    -- Out of the rack and into the air: a marble in flight cannot be shoved by
    -- blowback, and its lane is free for someone else to be pushed into.
    if attacker.rack[home_lane] == marble then
        attacker.rack[home_lane] = nil
    end

    local cols = defender.formation.cols
    local traj = marble.core.trajectory
    local target = choose_target(defender, home_lane)
    local aimed = entry_column(target, traj, cols)

    -- Scatter is the sling's inaccuracy. A sling with scatter 0 always puts the
    -- marble where it aimed; a loose one may throw the whole run off.
    local scatter = 0
    if marble.scatter and marble.scatter > 0 then
        scatter = battle.rng:int(-marble.scatter, marble.scatter)
    end
    local col = clamp(aimed + scatter, 1, cols)
    local row = 1
    local dir = 1
    local momentum = marble.momentum

    log(battle, attacker.id, "launch", {
        marble = marble.uid, name = marble.name, rarity = marble.rarity,
        lane = home_lane, aimed_col = aimed, scatter = scatter, entry_col = col,
        target_row = target and target.row or -1, target_col = target and target.col or -1,
        momentum = momentum, shells = #marble.shells, trajectory = traj, core = marble.core.id,
    })

    local stop_reason = nil
    local steps = 0
    while not stop_reason do
        steps = steps + 1
        if steps > M.MAX_CASCADE_STEPS then
            stop_reason = "stalled"
            break
        end

        if row > defender.formation.rows then
            stop_reason = "through"
        elseif row < 1 then
            stop_reason = "ejected"
        elseif col < 1 or col > cols then
            stop_reason = "wide"
        else
            local brick = formation_mod.brick_at(defender.formation, row, col)
            if not brick then
                row = row + dir
                col = col + traj
            else
                local outcome = resolve_collision(battle, attacker, defender, marble, brick, row, col, dir, traj)
                momentum = momentum - outcome.momentum_cost
                dir = outcome.dir
                traj = outcome.traj
                if outcome.destroyed then
                    stop_reason = "destroyed"
                elseif momentum <= 0 then
                    stop_reason = "spent"
                else
                    row = row + dir
                    col = col + traj
                end
            end
        end
    end

    log(battle, attacker.id, "cascade_end", {
        marble = marble.uid, reason = stop_reason, row = row, col = col, momentum_left = math.max(0, momentum),
    })

    if stop_reason == "destroyed" then
        return
    end

    -- The marble survived. It comes to rest and rejoins the rack, preferring
    -- the lane it launched from; if blowback filled that lane it settles in the
    -- nearest free one.
    marble.state = "ready"
    marble_mod.assert_core_covered(marble)
    local lane = nil
    if not attacker.rack[home_lane] then
        lane = home_lane
    else
        for offset = 1, attacker.lanes do
            local left = home_lane - offset
            local right = home_lane + offset
            if left >= 1 and not attacker.rack[left] then lane = left break end
            if right <= attacker.lanes and not attacker.rack[right] then lane = right break end
        end
    end
    if not lane then
        -- Cannot happen with #marbles <= lanes, but do not fail silently.
        error("no free lane for returning marble " .. tostring(marble.uid))
    end
    marble.lane = lane
    attacker.rack[lane] = marble
    attacker.queue[#attacker.queue + 1] = marble
    log(battle, attacker.id, "rack_return", { marble = marble.uid, lane = lane, shells_left = #marble.shells })
end

-- ---------------------------------------------------------------------------
-- Win conditions
-- ---------------------------------------------------------------------------

--- Evaluated once per volley, after BOTH cascades. Symmetric: all opponent
--- bricks destroyed is victory, all own marbles destroyed is defeat. If both
--- sides satisfy a winning condition in the same volley it is a draw — nobody
--- wins on resolution order.
local function evaluate(battle)
    local a, b = battle.sides.A, battle.sides.B
    local a_reasons, b_reasons = {}, {}

    if b.formation.alive == 0 then a_reasons[#a_reasons + 1] = "bricks_destroyed" end
    if #b.roster == 0 then a_reasons[#a_reasons + 1] = "opponent_marbles_destroyed" end
    if a.formation.alive == 0 then b_reasons[#b_reasons + 1] = "bricks_destroyed" end
    if #a.roster == 0 then b_reasons[#b_reasons + 1] = "opponent_marbles_destroyed" end

    local a_wins = #a_reasons > 0
    local b_wins = #b_reasons > 0

    if a_wins and b_wins then
        return {
            outcome = "draw", winner = nil, reason = "mutual",
            a_reason = table.concat(a_reasons, "+"), b_reason = table.concat(b_reasons, "+"),
            volleys = battle.volley,
        }
    elseif a_wins then
        return { outcome = "victory", winner = "A", reason = table.concat(a_reasons, "+"), volleys = battle.volley }
    elseif b_wins then
        return { outcome = "victory", winner = "B", reason = table.concat(b_reasons, "+"), volleys = battle.volley }
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Volley loop
-- ---------------------------------------------------------------------------

--- Run the battle to completion. Returns the result table.
function M.run(battle)
    while battle.result == nil do
        if battle.volley >= battle.max_volleys then
            battle.result = {
                outcome = "draw", winner = nil, reason = "volley_limit", volleys = battle.volley,
            }
            break
        end

        battle.volley = battle.volley + 1
        log(battle, "-", "volley_start", {
            a_marbles = #battle.sides.A.roster, b_marbles = #battle.sides.B.roster,
            a_bricks = battle.sides.A.formation.alive, b_bricks = battle.sides.B.formation.alive,
        })

        -- Both sides commit their next marble BEFORE either cascade resolves.
        -- This is the simultaneity: whatever the other side's marble does this
        -- volley, your shot was already loaded.
        local launchers = {}
        for _, id in ipairs(battle.order) do
            local player = battle.sides[id]
            launchers[id] = table.remove(player.queue, 1)
        end

        -- Cascades resolve one at a time and to completion — a marble finishes
        -- its whole run through the formation before the next one moves.
        for _, id in ipairs(battle.order) do
            local marble = launchers[id]
            local player = battle.sides[id]
            if marble then
                if marble.state == "destroyed" then
                    -- Killed by the other side's blowback after it was loaded
                    -- but before it fired. The shot is lost.
                    log(battle, id, "launch_aborted", { marble = marble.uid, reason = "destroyed_before_launch" })
                else
                    resolve_cascade(battle, player, opponent_of(battle, player), marble)
                end
            else
                log(battle, id, "no_marble", {})
            end
        end

        battle.result = evaluate(battle)
    end

    log(battle, "-", "battle_end", {
        outcome = battle.result.outcome,
        winner = battle.result.winner or "none",
        reason = battle.result.reason,
        volleys = battle.result.volleys,
        a_bricks = battle.sides.A.formation.alive,
        b_bricks = battle.sides.B.formation.alive,
        a_marbles = #battle.sides.A.roster,
        b_marbles = #battle.sides.B.roster,
    })

    return battle.result
end

--- Convenience: build and run in one call. Returns battle, result.
function M.simulate(opts)
    local battle = M.new_battle(opts)
    local result = M.run(battle)
    return battle, result
end

return M
