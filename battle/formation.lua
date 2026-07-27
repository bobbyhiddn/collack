-- battle/formation.lua — brick formations on a fixed grid.
--
-- Placement is a fixed grid of rows x cols (ADR 0004). Row 1 is the FRONT row,
-- the one nearest the incoming marble; higher rows are deeper into the
-- defender's formation. Columns are numbered left to right from the attacker's
-- point of view, and the column space is shared with the lane space that
-- marbles sit in, which is what lets a blowback epicentre in the formation map
-- onto marbles in both racks.

local bricks = require("battle.content.bricks")

local M = {}

--- Build a formation from a layout: an array of rows, each an array of brick
--- ids. Product handoffs use stable brick UIDs in the grid and pass the
--- drafted roster as the second argument. Use "." or false for an empty cell.
--- Every row must be the same width.
function M.build(layout, roster)
    local rows = #layout
    if rows < 1 then
        error("formation layout has no rows")
    end
    local cols = #layout[1]
    if cols < 1 then
        error("formation layout row 1 has no columns")
    end

    local roster_by_uid = {}
    for _, brick in ipairs(roster or {}) do
        if brick.uid == nil then error("formation roster brick is missing uid") end
        if roster_by_uid[brick.uid] then
            error("formation roster contains duplicate uid: " .. tostring(brick.uid))
        end
        roster_by_uid[brick.uid] = brick
    end

    local grid = {}
    local alive = 0
    for row = 1, rows do
        if #layout[row] ~= cols then
            error(string.format("formation row %d has %d columns, expected %d", row, #layout[row], cols))
        end
        grid[row] = {}
        for col = 1, cols do
            local cell = layout[row][col]
            if cell and cell ~= "." then
                local roster_item = roster_by_uid[cell]
                local content_id = roster_item and roster_item.content_id or cell
                local def = bricks.by_id[content_id]
                if not def then
                    error("unknown brick: " .. tostring(content_id))
                end
                grid[row][col] = {
                    id = def.id,
                    uid = roster_item and roster_item.uid or nil,
                    name = def.name,
                    family = def.family or "basic",
                    behaviour = def.behaviour,
                    hp = def.hp,
                    max_hp = def.hp,
                    aegis_spent = false,
                    row = row,
                    col = col,
                    alive = true,
                }
                alive = alive + 1
            end
        end
    end

    if roster and #roster > 0 then
        if alive ~= #roster then
            error(string.format(
                "formation places %d bricks but roster contains %d",
                alive,
                #roster
            ))
        end
        local placed = {}
        for row = 1, rows do
            for col = 1, cols do
                local brick = grid[row][col]
                if brick and brick.uid then
                    if placed[brick.uid] then
                        error("formation places brick twice: " .. tostring(brick.uid))
                    end
                    placed[brick.uid] = true
                end
            end
        end
        for uid in pairs(roster_by_uid) do
            if not placed[uid] then
                error("formation omits roster brick: " .. tostring(uid))
            end
        end
    end

    if alive == 0 then
        error("formation layout contains no bricks")
    end

    return { rows = rows, cols = cols, grid = grid, alive = alive }
end

function M.brick_at(formation, row, col)
    if row < 1 or row > formation.rows then return nil end
    if col < 1 or col > formation.cols then return nil end
    local brick = formation.grid[row][col]
    if brick and brick.alive then return brick end
    return nil
end

function M.in_bounds(formation, row, col)
    return row >= 1 and row <= formation.rows and col >= 1 and col <= formation.cols
end

--- Orthogonal neighbours in a fixed order: up, down, left, right. The order is
--- fixed rather than shuffled so chain detonations are reproducible without
--- consuming randomness.
function M.neighbours(formation, row, col)
    local out = {}
    local deltas = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
    for _, delta in ipairs(deltas) do
        local brick = M.brick_at(formation, row + delta[1], col + delta[2])
        if brick then
            out[#out + 1] = brick
        end
    end
    return out
end

--- Mark a brick dead and decrement the live count. Returns true if this call
--- was the one that killed it (so callers cannot double-count a kill).
function M.kill(formation, brick)
    if not brick.alive then return false end
    brick.alive = false
    brick.hp = 0
    formation.alive = formation.alive - 1
    return true
end

return M
