-- Pure formation and ordered-bag rules for the player setup surface.

local contract = require("battle.vslice_contract")
local util = require("battle.run_util")

local M = {}

function M.empty_formation()
    local formation = {}
    for row = 1, contract.FORMATION.ROWS do
        formation[row] = {}
        for col = 1, contract.FORMATION.COLS do formation[row][col] = "." end
    end
    return formation
end

local function error_item(code, message, field)
    return { code = code, message = message, field = field }
end

local function contract_shape(loadout)
    return {
        sling_id = loadout.sling_id or (loadout.sling and loadout.sling.id),
        marbles = loadout.marbles,
        bricks = loadout.bricks,
        bag_order = loadout.bag_order,
        formation = loadout.formation,
    }
end

function M.validate(loadout)
    local errors = {}
    if type(loadout) ~= "table" then
        return false, { error_item("setup_required", "Setup must be a table.", "setup") }
    end

    local valid, message = contract.validate_setup(contract_shape(loadout))
    if not valid then
        errors[#errors + 1] = error_item("contract_invalid", message, "setup")
    end

    local marble_ids = {}
    for _, marble in ipairs(loadout.marbles or {}) do
        if marble.content_id == nil then
            errors[#errors + 1] = error_item(
                "marble_content_missing",
                "Every drafted marble needs a content identity.",
                "marbles"
            )
        end
        marble_ids[marble.uid] = true
    end

    local brick_ids = {}
    for _, brick in ipairs(loadout.bricks or {}) do
        if brick.content_id == nil then
            errors[#errors + 1] = error_item(
                "brick_content_missing",
                "Every drafted brick needs a content identity.",
                "bricks"
            )
        end
        brick_ids[brick.uid] = true
    end

    for _, uid in ipairs(loadout.bag_order or {}) do
        if not marble_ids[uid] then
            errors[#errors + 1] = error_item(
                "bag_unknown_marble",
                "The bag contains a marble that was not drafted.",
                "bag_order"
            )
        end
    end
    for row = 1, contract.FORMATION.ROWS do
        for col = 1, contract.FORMATION.COLS do
            local uid = loadout.formation
                and loadout.formation[row]
                and loadout.formation[row][col]
            if uid and uid ~= "." and not brick_ids[uid] then
                errors[#errors + 1] = error_item(
                    "formation_unknown_brick",
                    "The formation contains a brick that was not drafted.",
                    "formation"
                )
            end
        end
    end

    return #errors == 0, errors
end

function M.status(loadout)
    local valid, errors = M.validate(loadout)
    return { valid = valid, errors = errors }
end

function M.find_brick_cell(formation, uid)
    for row = 1, contract.FORMATION.ROWS do
        for col = 1, contract.FORMATION.COLS do
            if formation[row][col] == uid then return { row = row, col = col } end
        end
    end
    return nil
end

function M.place(loadout, brick_uid, row, col)
    if not util.is_integer(row) or not util.is_integer(col)
        or row < 1 or row > contract.FORMATION.ROWS
        or col < 1 or col > contract.FORMATION.COLS then
        return nil, error_item(
            "cell_out_of_bounds",
            "Choose a cell inside the 3 × 7 formation.",
            "formation"
        )
    end

    local known = false
    for _, brick in ipairs(loadout.bricks or {}) do
        if brick.uid == brick_uid then known = true break end
    end
    if not known then
        return nil, error_item(
            "brick_unknown",
            "Choose one of the eight drafted bricks.",
            "formation"
        )
    end

    local occupied = loadout.formation[row][col]
    if occupied and occupied ~= "." and occupied ~= brick_uid then
        return nil, error_item(
            "cell_occupied",
            "That cell already holds another brick.",
            "formation"
        )
    end

    local updated = util.deep_copy(loadout)
    local previous = M.find_brick_cell(updated.formation, brick_uid)
    if previous and previous.row == row and previous.col == col then
        return nil, error_item(
            "placement_unchanged",
            "That brick is already in this cell.",
            "formation"
        )
    end
    if previous then updated.formation[previous.row][previous.col] = "." end
    updated.formation[row][col] = brick_uid
    return updated, nil, previous
end

function M.move_bag(loadout, marble_uid, before_uid)
    local from = util.index_of(loadout.bag_order, marble_uid)
    if not from then
        return nil, error_item(
            "bag_marble_unknown",
            "Choose a marble already in the drafted bag.",
            "bag_order"
        )
    end
    if before_uid ~= nil and not util.index_of(loadout.bag_order, before_uid) then
        return nil, error_item(
            "bag_target_unknown",
            "Choose a valid insertion slot.",
            "bag_order"
        )
    end
    if before_uid == marble_uid then
        return nil, error_item(
            "bag_order_unchanged",
            "Choose a different insertion slot.",
            "bag_order"
        )
    end

    local updated = util.deep_copy(loadout)
    table.remove(updated.bag_order, from)
    local target
    if before_uid == nil then
        target = #updated.bag_order + 1
    else
        target = util.index_of(updated.bag_order, before_uid)
    end
    table.insert(updated.bag_order, target, marble_uid)
    if util.deep_equal(updated.bag_order, loadout.bag_order) then
        return nil, error_item(
            "bag_order_unchanged",
            "That move would not change launch order.",
            "bag_order"
        )
    end
    return updated
end

local function shared_tags(left, right)
    local right_tags = util.set(right.tags)
    local out = {}
    for _, tag in ipairs(left.tags or {}) do
        if right_tags[tag] then out[#out + 1] = tag end
    end
    return out
end

function M.adjacency_preview(loadout)
    local by_uid = {}
    for _, brick in ipairs(loadout.bricks or {}) do by_uid[brick.uid] = brick end
    local out = {}
    local deltas = { { 0, 1 }, { 1, 0 } }
    for row = 1, contract.FORMATION.ROWS do
        for col = 1, contract.FORMATION.COLS do
            local uid = loadout.formation[row][col]
            if uid and uid ~= "." then
                for _, delta in ipairs(deltas) do
                    local next_row, next_col = row + delta[1], col + delta[2]
                    if next_row <= contract.FORMATION.ROWS
                        and next_col <= contract.FORMATION.COLS then
                        local neighbour_uid = loadout.formation[next_row][next_col]
                        if neighbour_uid and neighbour_uid ~= "." then
                            local tags = shared_tags(by_uid[uid], by_uid[neighbour_uid])
                            out[#out + 1] = {
                                left_uid = uid,
                                right_uid = neighbour_uid,
                                tags = tags,
                                active_synergy = #tags > 0,
                            }
                        end
                    end
                end
            end
        end
    end
    return out
end

function M.build_tags(loadout)
    local counts = {}
    local function count(item)
        for _, tag in ipairs((item and item.tags) or {}) do
            counts[tag] = (counts[tag] or 0) + 1
        end
    end
    count(loadout.sling)
    for _, marble in ipairs(loadout.marbles or {}) do count(marble) end
    for _, brick in ipairs(loadout.bricks or {}) do count(brick) end
    local out = {}
    for _, tag in ipairs(util.sorted_keys(counts)) do
        out[#out + 1] = { id = tag, count = counts[tag] }
    end
    return out
end

function M.player_spec(loadout, name)
    return {
        schema_version = 1,
        id = "player",
        name = name or "Collector",
        sling_id = loadout.sling_id or (loadout.sling and loadout.sling.id),
        sling = util.deep_copy(loadout.sling),
        marbles = util.deep_copy(loadout.marbles),
        bricks = util.deep_copy(loadout.bricks),
        formation = util.deep_copy(loadout.formation),
        bag_order = util.deep_copy(loadout.bag_order),
        build_tags = M.build_tags(loadout),
    }
end

return M
