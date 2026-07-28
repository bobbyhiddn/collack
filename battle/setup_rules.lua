-- Pure formation and ordered-bag rules for the player setup surface.

local contract = require("battle.vslice_contract")
local util = require("battle.run_util")
local rule_ast = require("battle.rule_ast")
local draft = require("battle.draft")
local draft_content = require("battle.content.draft")
local brick_content = require("battle.content.bricks")
local sling_content = require("battle.content.slings")

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

local function same_rule_set(left, right)
    return rule_ast.same(left, right)
end

local function tags_match(rule_set, target)
    local tags = util.set(rule_set.synergy_tags or {})
    for _, required in ipairs(target.required_tags or {}) do
        if not tags[required] then return false end
    end
    for _, excluded in ipairs(target.excluded_tags or {}) do
        if tags[excluded] then return false end
    end
    return true
end

function M.resolve_ability_links(loadout)
    local by_uid, cells = {}, {}
    for _, brick in ipairs((loadout and loadout.bricks) or {}) do
        by_uid[brick.uid] = brick
    end
    for row = 1, contract.FORMATION.ROWS do
        for col = 1, contract.FORMATION.COLS do
            local uid = loadout.formation
                and loadout.formation[row]
                and loadout.formation[row][col]
            if uid and uid ~= "." then cells[uid] = { row = row, col = col } end
        end
    end
    local sources = {}
    for uid, cell in pairs(cells) do
        if by_uid[uid] then
            sources[#sources + 1] = { uid = uid, cell = cell, brick = by_uid[uid] }
        end
    end
    table.sort(sources, function(left, right)
        if left.cell.row ~= right.cell.row then return left.cell.row < right.cell.row end
        if left.cell.col ~= right.cell.col then return left.cell.col < right.cell.col end
        return tostring(left.uid) < tostring(right.uid)
    end)
    local links, errors = {}, {}
    local deltas = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
    for _, source in ipairs(sources) do
        local valid = pcall(rule_ast.assert_valid, source.brick.rule_set)
        if valid then
            for _, ability in ipairs(rule_ast.linked_cost_groups(source.brick.rule_set)) do
                local cost_rule = rule_ast.rule(source.brick.rule_set, ability.cost_rule_id)
                local amount = cost_rule.magnitude.value
                local candidates = {}
                for _, delta in ipairs(deltas) do
                    local row = source.cell.row + delta[1]
                    local col = source.cell.col + delta[2]
                    local uid = loadout.formation
                        and loadout.formation[row]
                        and loadout.formation[row][col]
                    local brick = uid and uid ~= "." and by_uid[uid] or nil
                    if brick and uid ~= source.uid and (brick.hp or brick.max_hp or 0) >= amount
                        and (cost_rule.lethal
                            or (brick.hp or brick.max_hp or 0) - amount > 0)
                        and tags_match(brick.rule_set, cost_rule.target) then
                        candidates[#candidates + 1] = {
                            uid = uid, row = row, col = col, brick = brick,
                        }
                    end
                end
                table.sort(candidates, function(left, right)
                    if left.row ~= right.row then return left.row < right.row end
                    if left.col ~= right.col then return left.col < right.col end
                    return tostring(left.uid) < tostring(right.uid)
                end)
                local target = candidates[1]
                if not target then
                    errors[#errors + 1] = error_item(
                        "ability_link_missing",
                        source.brick.name .. " needs one eligible orthogonally adjacent ally.",
                        "formation"
                    )
                else
                    links[#links + 1] = {
                        ability_id = ability.id,
                        source_uid = source.uid,
                        target_uid = target.uid,
                        source_rule_set_id = source.brick.rule_set.id,
                        cost_rule_id = ability.cost_rule_id,
                        payoff_rule_ids = util.deep_copy(ability.payoff_rule_ids),
                        source_cell = util.deep_copy(source.cell),
                        target_cell = { row = target.row, col = target.col },
                        cost_amount = amount,
                        lethal = cost_rule.lethal,
                        cadence = util.deep_copy(cost_rule.cadence),
                    }
                end
            end
        end
    end
    return links, errors
end

function M.validate(loadout, options)
    options = options or {}
    local errors = {}
    if type(loadout) ~= "table" then
        return false, { error_item("setup_required", "Setup must be a table.", "setup") }
    end

    if not options.skip_contract then
        local valid, message = contract.validate_setup(contract_shape(loadout))
        if not valid then
            errors[#errors + 1] = error_item("contract_invalid", message, "setup")
        end
    end

    local canonical_rules = {}
    local sling_id = loadout.sling_id or (loadout.sling and loadout.sling.id)
    local sling_known = sling_content.has(sling_id)
    local sling_canonical = sling_known
        and sling_content.canonical_rule_set(sling_id)
    local sling_rules = loadout.sling and loadout.sling.rule_set
        or sling_canonical
    if not sling_known or not sling_rules then
        errors[#errors + 1] = error_item(
            "sling_rules_missing",
            "The drafted sling needs a known canonical rule set.",
            "sling"
        )
    else
        canonical_rules[#canonical_rules + 1] = sling_rules
        if not same_rule_set(sling_rules, sling_canonical) then
            errors[#errors + 1] = error_item(
                "sling_rules_mismatch",
                "The drafted sling rules do not match its content identity.",
                "sling"
            )
        else
            local runtime_valid, runtime_error = pcall(
                sling_content.runtime,
                sling_id,
                sling_rules,
                loadout.sling
            )
            if not runtime_valid then
                errors[#errors + 1] = error_item(
                    "sling_runtime_mismatch",
                    tostring(runtime_error),
                    "sling"
                )
            end
        end
    end

    local marble_ids = {}
    for _, marble in ipairs(loadout.marbles or {}) do
        if type(marble) ~= "table" then
            errors[#errors + 1] = error_item(
                "marble_invalid",
                "Every drafted marble must be a canonical value.",
                "marbles"
            )
        elseif marble.content_id == nil then
            errors[#errors + 1] = error_item(
                "marble_content_missing",
                "Every drafted marble needs a content identity.",
                "marbles"
            )
        end
        local definition = type(marble) == "table"
            and draft_content.marble_by_id[marble.content_id]
            or nil
        local rules = type(marble) == "table"
            and (marble.rule_set or (definition and definition.rule_set))
            or nil
        if definition and rules then
            if not same_rule_set(rules, definition.rule_set) then
                errors[#errors + 1] = error_item(
                    "marble_rules_mismatch",
                    "A drafted marble's rules do not match its content identity.",
                    "marbles"
                )
            end
            if not rules.availability.player_draft
                and not rules.availability.player_reward then
                errors[#errors + 1] = error_item(
                    "marble_unavailable",
                    "That marble is not legal for a player loadout.",
                    "marbles"
                )
            end
        else
            errors[#errors + 1] = error_item(
                "marble_rules_missing",
                "Every drafted marble needs canonical rules.",
                "marbles"
            )
        end
        if type(marble) == "table" then
            local authority_valid, canonical_or_error = pcall(
                draft.canonical_marble,
                marble
            )
            if authority_valid then
                canonical_rules[#canonical_rules + 1] = canonical_or_error.rule_set
            else
                errors[#errors + 1] = error_item(
                    "marble_authority_mismatch",
                    tostring(canonical_or_error),
                    "marbles"
                )
            end
            marble_ids[marble.uid] = true
        end
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
        local brick_known = brick_content.has(brick.content_id)
        local canonical = brick_known
            and brick_content.canonical_rule_set(brick.content_id)
        local rules = brick.rule_set or canonical
        if brick_known and rules then
            canonical_rules[#canonical_rules + 1] = rules
            if not same_rule_set(rules, canonical) then
                errors[#errors + 1] = error_item(
                    "brick_rules_mismatch",
                    "A drafted brick's rules do not match its content identity.",
                    "bricks"
                )
            else
                local runtime_valid, runtime_error = pcall(
                    brick_content.runtime,
                    brick.content_id,
                    rules,
                    brick
                )
                if not runtime_valid then
                    errors[#errors + 1] = error_item(
                        "brick_runtime_mismatch",
                        tostring(runtime_error),
                        "bricks"
                    )
                end
            end
            if not rules.availability.player_draft
                and not rules.availability.player_reward then
                errors[#errors + 1] = error_item(
                    "brick_unavailable",
                    "That brick is not legal for a player loadout.",
                    "bricks"
                )
            end
        else
            errors[#errors + 1] = error_item(
                "brick_rules_missing",
                "Every drafted brick needs canonical rules.",
                "bricks"
            )
        end
        brick_ids[brick.uid] = true
    end

    local compatible, compatibility_errors = rule_ast.validate_collection(canonical_rules)
    if not compatible then
        for _, message in ipairs(compatibility_errors) do
            errors[#errors + 1] = error_item(
                "rules_incompatible",
                message,
                "loadout"
            )
        end
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
            if uid and uid ~= "." then
                for _, brick in ipairs(loadout.bricks or {}) do
                    if brick.uid == uid and brick.rule_set
                        and brick.rule_set.formation
                        and brick.rule_set.formation.rear_row
                        and row ~= contract.FORMATION.ROWS then
                        errors[#errors + 1] = error_item(
                            "formation_rear_row_required",
                            brick.name .. " must be placed in the rear row.",
                            "formation"
                        )
                    end
                end
            end
        end
    end

    local links, link_errors = M.resolve_ability_links(loadout)
    for _, item in ipairs(link_errors) do errors[#errors + 1] = item end
    if loadout.ability_links ~= nil
        and not util.deep_equal(loadout.ability_links, links) then
        errors[#errors + 1] = error_item(
            "ability_links_stale",
            "Linked allied-cost handoff does not match the canonical formation.",
            "ability_links"
        )
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
    local valid, errors = M.validate(loadout, { skip_contract = true })
    if not valid then
        local first = errors[1] or {}
        error(string.format(
            "cannot hand off invalid canonical setup%s%s",
            first.code and " (" .. tostring(first.code) .. ")" or "",
            first.message and ": " .. tostring(first.message) or ""
        ))
    end
    local marbles = {}
    for _, marble in ipairs(loadout.marbles or {}) do
        marbles[#marbles + 1] = draft.canonical_marble(marble)
    end
    local ability_links = M.resolve_ability_links(loadout)
    return {
        schema_version = 1,
        id = "player",
        name = name or "Collector",
        sling_id = loadout.sling_id or (loadout.sling and loadout.sling.id),
        sling = util.deep_copy(loadout.sling),
        marbles = marbles,
        bricks = util.deep_copy(loadout.bricks),
        formation = util.deep_copy(loadout.formation),
        bag_order = util.deep_copy(loadout.bag_order),
        build_tags = M.build_tags(loadout),
        ability_links = util.deep_copy(ability_links),
    }
end

return M
