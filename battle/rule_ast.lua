-- Canonical executable rule grammar.
--
-- Content owns one value-only RuleSet.  Validation, runtime projection,
-- player-facing copy, battle attribution, compatibility, and balance all read
-- this same tree.  None of those consumers is allowed to carry a second
-- handwritten description of what a rule means.

local M = {}

M.SCHEMA_VERSION = 1

local registry = {}

local ITEM_FIELDS = {
    schema_version = true,
    kind = true,
    id = true,
    name = true,
    role = true,
    rules = true,
    drawback = true,
    compatibility = true,
    synergy_tags = true,
    rarity_budget = true,
}

local RULE_FIELDS = {
    id = true,
    trigger = true,
    condition = true,
    target = true,
    operation = true,
    magnitude = true,
    duration = true,
    cadence = true,
    cost = true,
    visibility = true,
}

local TRIGGER_FIELDS = { event = true, phase = true }
local CONDITION_FIELDS = { predicate = true, value = true }
local TARGET_FIELDS = { selector = true, relation = true }
local OPERATION_FIELDS = { verb = true, stat = true, mode = true }
local QUANTITY_FIELDS = { value = true, unit = true }
local CADENCE_FIELDS = { unit = true, interval = true, charges = true, limit = true }
local COST_FIELDS = { kind = true, stat = true, magnitude = true, unit = true }
local DRAWBACK_FIELDS = { kind = true, stat = true, magnitude = true, unit = true }
local COMPATIBILITY_FIELDS = { requires = true, excludes = true, max_copies = true }

local ALLOWED_VISIBILITY = {
    compact = true,
    expanded = true,
    internal = true,
}

local ALLOWED_MODES = {
    add = true,
    set = true,
}

local ALLOWED_TRIGGERS = {
    build = true,
    collision = true,
    core_release = true,
    damaging_collision = true,
    destroyed = true,
    field_contact = true,
    launch = true,
    non_chip_collision = true,
    passive = true,
    status_tick = true,
    survives_collision = true,
    wall_or_brick_contact = true,
}

local ALLOWED_PHASES = { before = true, during = true, after = true }

local ALLOWED_CONDITIONS = {
    adjacent = true,
    always = true,
    enemy = true,
    final_shell = true,
    first_time = true,
    moving = true,
    non_chip = true,
    survives = true,
}

local ALLOWED_TARGETS = {
    all_owned_marbles = true,
    current_shell = true,
    launch = true,
    nearby_marbles = true,
    orthogonal_neighbours = true,
    release_area = true,
    self = true,
    striking_marble = true,
    struck_brick = true,
    target_column = true,
}

local ALLOWED_VERBS = {
    accelerate = true,
    aim = true,
    amplify = true,
    apply_status = true,
    ["break"] = true,
    cover = true,
    deal = true,
    heal = true,
    hold = true,
    launch = true,
    negate = true,
    persist = true,
    pierce = true,
    prevent = true,
    protect = true,
    pull = true,
    push = true,
    rebound = true,
    redirect = true,
    rewind = true,
    scatter = true,
    scorch = true,
    set = true,
    slow = true,
    splash = true,
    target = true,
    wear = true,
}

local ALLOWED_STATS = {
    aim = true,
    behaviour = true,
    break_shell = true,
    collision = true,
    collision_splash = true,
    damage = true,
    damage_bonus = true,
    damage_reduction = true,
    death_splash = true,
    durability = true,
    durability_bonus = true,
    durability_cost = true,
    duration_ticks = true,
    effect_power = true,
    field_duration = true,
    field_radius = true,
    field_release_strength = true,
    field_strength = true,
    harmless = true,
    heal_after_hit = true,
    hp = true,
    invert = true,
    launch_speed_multiplier = true,
    momentum_bonus = true,
    momentum_delta = true,
    negate_once = true,
    pierces_absorb = true,
    precision = true,
    protect_adjacent = true,
    radius = true,
    reflect = true,
    release = true,
    rewind = true,
    ricochet = true,
    scatter = true,
    scorch = true,
    shell_wear = true,
    shots_per_volley = true,
    shrapnel = true,
    splash_behind = true,
    status = true,
    trajectory = true,
    velocity_multiplier = true,
}

local STAT_VERBS = {
    aim = { aim = true },
    behaviour = { hold = true, set = true },
    break_shell = { ["break"] = true },
    collision = { set = true },
    collision_splash = { splash = true },
    damage = { deal = true },
    damage_bonus = { deal = true },
    damage_reduction = { prevent = true },
    death_splash = { splash = true },
    durability = { protect = true },
    durability_bonus = { protect = true },
    durability_cost = { wear = true },
    duration_ticks = { persist = true },
    effect_power = { amplify = true },
    field_duration = { persist = true },
    field_radius = { cover = true },
    field_release_strength = { push = true },
    field_strength = { pull = true, set = true },
    harmless = { prevent = true },
    heal_after_hit = { heal = true },
    hp = { protect = true },
    invert = { pull = true },
    launch_speed_multiplier = { slow = true },
    momentum_bonus = { accelerate = true },
    momentum_delta = { accelerate = true },
    negate_once = { negate = true },
    pierces_absorb = { pierce = true },
    precision = { target = true },
    protect_adjacent = { protect = true },
    radius = { push = true },
    reflect = { rebound = true },
    release = { set = true },
    rewind = { rewind = true },
    ricochet = { rebound = true },
    scatter = { scatter = true },
    scorch = { scorch = true },
    shell_wear = { wear = true },
    shots_per_volley = { launch = true },
    shrapnel = { splash = true },
    splash_behind = { splash = true },
    status = { apply_status = true, set = true },
    trajectory = { aim = true },
    velocity_multiplier = { slow = true },
}

local STRING_STATS = {
    behaviour = true,
    collision = true,
    release = true,
    status = true,
}

local BOOLEAN_STATS = {
    break_shell = true,
    harmless = true,
    invert = true,
    negate_once = true,
    pierces_absorb = true,
    precision = true,
    rewind = true,
    ricochet = true,
}

local ALLOWED_UNITS = {
    cells = true,
    count = true,
    damage = true,
    durability = true,
    flag = true,
    hp = true,
    id = true,
    launch_force = true,
    multiplier = true,
    percent = true,
    radius = true,
    shots = true,
    strength = true,
    ticks = true,
}

local ALLOWED_COST_KINDS = {
    consume = true,
    none = true,
    opportunity = true,
    reduce = true,
    risk = true,
}

local BALANCE_WEIGHT = {
    behaviour = 0,
    collision = 0,
    release = 0,
    hp = 1.0,
    durability = 1.0,
    durability_bonus = 1.0,
    damage = 3.0,
    damage_bonus = 3.0,
    damage_reduction = 3.0,
    durability_cost = 1.5,
    shell_wear = 1.5,
    momentum_bonus = 1.4,
    aim = 1.0,
    scatter = 0.5,
    shots_per_volley = 7.0,
    ricochet = 5.0,
    precision = 4.0,
    effect_power = 6.0,
    heal_after_hit = 3.0,
    protect_adjacent = 4.0,
    reflect = 4.0,
    status = 3.0,
    field_radius = 0.4,
    field_strength = 0.08,
    death_splash = 4.0,
    collision_splash = 4.0,
    momentum_delta = 1.4,
    harmless = 2.0,
    negate_once = 6.0,
    break_shell = 7.0,
    rewind = 6.0,
    radius = 2.0,
    invert = 4.0,
    scorch = 4.0,
    shrapnel = 4.0,
    duration_ticks = 0.02,
    velocity_multiplier = 2.0,
    launch_speed_multiplier = 3.0,
    field_duration = 0.04,
    field_release_strength = 0.2,
    splash_behind = 4.0,
    pierces_absorb = 4.0,
    trajectory = 1.0,
}

local TARGET_MULTIPLIER = {
    self = 1.0,
    current_shell = 1.0,
    struck_brick = 1.0,
    striking_marble = 1.0,
    launch = 1.0,
    all_owned_marbles = 2.0,
    orthogonal_neighbours = 1.8,
    nearby_marbles = 2.0,
    release_area = 2.0,
    target_column = 1.4,
}

local TRIGGER_COPY = {
    build = "Always",
    launch = "On launch",
    collision = "On contact",
    damaging_collision = "On a damaging contact",
    non_chip_collision = "On a non-chip contact",
    wall_or_brick_contact = "On wall or brick contact",
    survives_collision = "After surviving a contact",
    destroyed = "When destroyed",
    field_contact = "In its field",
    core_release = "When the core releases",
    status_tick = "While the status lasts",
    passive = "While active",
}

local CONDITION_COPY = {
    always = "",
    survives = "",
    first_time = " the first time",
    enemy = " against an enemy",
    moving = " while the marble is moving",
    final_shell = " after the final shell breaks",
    non_chip = " with a non-chip shell",
    adjacent = " when adjacent",
}

local TARGET_COPY = {
    self = "itself",
    current_shell = "the striking shell",
    struck_brick = "the struck brick",
    striking_marble = "the striking marble",
    launch = "the launch",
    all_owned_marbles = "every marble in the bag",
    orthogonal_neighbours = "orthogonally adjacent bricks",
    nearby_marbles = "nearby allied and enemy marbles",
    release_area = "the core release",
    target_column = "the target column",
}

local UNIT_COPY = {
    damage = "damage",
    durability = "durability",
    hp = "integrity",
    launch_force = "launch force",
    multiplier = "×",
    cells = "cell",
    ticks = "ticks",
    contacts = "contact",
    shots = "shot",
    shells = "shell",
    percent = "%",
    radius = "radius",
    strength = "force",
    count = "",
    flag = "",
    id = "",
}

local UNIT_PLURAL = {
    cell = "cells",
    contact = "contacts",
    shot = "shots",
    shell = "shells",
}

local function deep_copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do out[deep_copy(key, seen)] = deep_copy(item, seen) end
    return out
end

M.copy = deep_copy

local function sorted_keys(value)
    local keys = {}
    for key in pairs(value or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        if type(left) == type(right) then return tostring(left) < tostring(right) end
        return type(left) < type(right)
    end)
    return keys
end

local function nonempty(value)
    return type(value) == "string" and value ~= ""
end

local function sequence_length(value)
    if type(value) ~= "table" then return nil end
    local count = 0
    for index in ipairs(value) do count = index end
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > count or key % 1 ~= 0 then
            return nil
        end
    end
    return count
end

local function check_fields(value, allowed, path, errors)
    if type(value) ~= "table" then
        errors[#errors + 1] = path .. " must be a table"
        return false
    end
    for _, key in ipairs(sorted_keys(value)) do
        if not allowed[key] then
            errors[#errors + 1] = path .. " contains unknown field " .. tostring(key)
        end
    end
    return true
end

local function check_string(value, path, errors)
    if not nonempty(value) then errors[#errors + 1] = path .. " must be a non-empty string" end
end

local function check_string_list(value, path, errors)
    local length = sequence_length(value)
    if length == nil then
        errors[#errors + 1] = path .. " must be an array"
        return
    end
    local seen = {}
    for index, item in ipairs(value) do
        if not nonempty(item) then
            errors[#errors + 1] = string.format("%s[%d] must be a non-empty string", path, index)
        elseif seen[item] then
            errors[#errors + 1] = path .. " contains duplicate " .. item
        else
            seen[item] = true
        end
    end
end

local function check_quantity(value, path, errors)
    if not check_fields(value, QUANTITY_FIELDS, path, errors) then return end
    if value.value == nil then errors[#errors + 1] = path .. ".value is required" end
    check_string(value.unit, path .. ".unit", errors)
    local value_type = type(value.value)
    if value.value ~= nil and value_type ~= "number"
        and value_type ~= "string" and value_type ~= "boolean" then
        errors[#errors + 1] = path .. ".value must be a number, string, or boolean"
    end
    if value.unit ~= nil and not ALLOWED_UNITS[value.unit] then
        errors[#errors + 1] = path .. ".unit is outside the canonical vocabulary"
    end
end

local function validate_rule(rule, path, errors, ids)
    if not check_fields(rule, RULE_FIELDS, path, errors) then return end
    check_string(rule.id, path .. ".id", errors)
    if nonempty(rule.id) then
        if ids[rule.id] then errors[#errors + 1] = path .. ".id duplicates " .. rule.id end
        ids[rule.id] = true
    end

    if check_fields(rule.trigger, TRIGGER_FIELDS, path .. ".trigger", errors) then
        check_string(rule.trigger.event, path .. ".trigger.event", errors)
        check_string(rule.trigger.phase, path .. ".trigger.phase", errors)
        if rule.trigger.event ~= nil and not ALLOWED_TRIGGERS[rule.trigger.event] then
            errors[#errors + 1] = path .. ".trigger.event is outside the canonical vocabulary"
        end
        if rule.trigger.phase ~= nil and not ALLOWED_PHASES[rule.trigger.phase] then
            errors[#errors + 1] = path .. ".trigger.phase is outside the canonical vocabulary"
        end
    end
    if check_fields(rule.condition, CONDITION_FIELDS, path .. ".condition", errors) then
        check_string(rule.condition.predicate, path .. ".condition.predicate", errors)
        if rule.condition.predicate ~= nil
            and not ALLOWED_CONDITIONS[rule.condition.predicate] then
            errors[#errors + 1] = path .. ".condition.predicate is outside the canonical vocabulary"
        end
    end
    if check_fields(rule.target, TARGET_FIELDS, path .. ".target", errors) then
        check_string(rule.target.selector, path .. ".target.selector", errors)
        if rule.target.selector ~= nil and not ALLOWED_TARGETS[rule.target.selector] then
            errors[#errors + 1] = path .. ".target.selector is outside the canonical vocabulary"
        end
    end
    if check_fields(rule.operation, OPERATION_FIELDS, path .. ".operation", errors) then
        check_string(rule.operation.verb, path .. ".operation.verb", errors)
        check_string(rule.operation.stat, path .. ".operation.stat", errors)
        if rule.operation.verb ~= nil and not ALLOWED_VERBS[rule.operation.verb] then
            errors[#errors + 1] = path .. ".operation.verb is outside the canonical vocabulary"
        end
        if rule.operation.stat ~= nil and not ALLOWED_STATS[rule.operation.stat] then
            errors[#errors + 1] = path .. ".operation.stat is outside the canonical vocabulary"
        end
        local verbs = STAT_VERBS[rule.operation.stat]
        if verbs and not verbs[rule.operation.verb] then
            errors[#errors + 1] = path
                .. ".operation verb/stat combination is not executable"
        end
        if not ALLOWED_MODES[rule.operation.mode] then
            errors[#errors + 1] = path .. ".operation.mode must be add or set"
        end
    end
    if rule.magnitude == nil and rule.duration == nil then
        errors[#errors + 1] = path .. " needs magnitude or duration"
    elseif rule.magnitude ~= nil and rule.duration ~= nil then
        errors[#errors + 1] = path .. " cannot declare both magnitude and duration"
    end
    if rule.magnitude ~= nil then check_quantity(rule.magnitude, path .. ".magnitude", errors) end
    if rule.duration ~= nil then check_quantity(rule.duration, path .. ".duration", errors) end
    local quantity = rule.magnitude or rule.duration
    if quantity then
        local stat = rule.operation and rule.operation.stat
        local expected = STRING_STATS[stat] and "string"
            or BOOLEAN_STATS[stat] and "boolean"
            or "number"
        if type(quantity.value) ~= expected then
            errors[#errors + 1] = path .. ".quantity must be " .. expected
                .. " for " .. tostring(stat)
        end
        if rule.duration and type(quantity.value) == "number" and quantity.value < 0 then
            errors[#errors + 1] = path .. ".duration.value must not be negative"
        end
        if rule.operation and rule.operation.mode == "add"
            and type(quantity.value) ~= "number" then
            errors[#errors + 1] = path .. ".operation.mode add requires a numeric quantity"
        end
    end

    if check_fields(rule.cadence, CADENCE_FIELDS, path .. ".cadence", errors) then
        check_string(rule.cadence.unit, path .. ".cadence.unit", errors)
        if rule.cadence.unit ~= nil
            and not ALLOWED_TRIGGERS[rule.cadence.unit]
            and rule.cadence.unit ~= "ticks" then
            errors[#errors + 1] = path .. ".cadence.unit is outside the canonical vocabulary"
        end
        if type(rule.cadence.interval) ~= "number" or rule.cadence.interval < 1 then
            errors[#errors + 1] = path .. ".cadence.interval must be >= 1"
        end
        if rule.cadence.charges ~= nil
            and (type(rule.cadence.charges) ~= "number"
                or rule.cadence.charges < 1
                or rule.cadence.charges % 1 ~= 0) then
            errors[#errors + 1] = path .. ".cadence.charges must be a positive integer"
        end
        if rule.cadence.limit ~= nil
            and (type(rule.cadence.limit) ~= "number"
                or rule.cadence.limit < 1
                or rule.cadence.limit % 1 ~= 0) then
            errors[#errors + 1] = path .. ".cadence.limit must be a positive integer"
        end
        if rule.cadence.charges ~= nil and rule.cadence.limit ~= nil then
            errors[#errors + 1] = path .. ".cadence cannot declare both charges and limit"
        end
    end
    if check_fields(rule.cost, COST_FIELDS, path .. ".cost", errors) then
        check_string(rule.cost.kind, path .. ".cost.kind", errors)
        if rule.cost.kind ~= nil and not ALLOWED_COST_KINDS[rule.cost.kind] then
            errors[#errors + 1] = path .. ".cost.kind is outside the canonical vocabulary"
        end
        if rule.cost.magnitude ~= nil and type(rule.cost.magnitude) ~= "number" then
            errors[#errors + 1] = path .. ".cost.magnitude must be numeric"
        end
        if rule.cost.kind ~= nil and rule.cost.kind ~= "none" then
            check_string(rule.cost.stat, path .. ".cost.stat", errors)
            if type(rule.cost.magnitude) ~= "number" then
                errors[#errors + 1] = path .. ".cost.magnitude is required for a real cost"
            end
            if not ALLOWED_UNITS[rule.cost.unit] then
                errors[#errors + 1] = path .. ".cost.unit is outside the canonical vocabulary"
            end
        end
    end
    if not ALLOWED_VISIBILITY[rule.visibility] then
        errors[#errors + 1] = path .. ".visibility must be compact, expanded, or internal"
    end
end

local function magnitude_number(rule)
    local quantity = rule.magnitude or rule.duration
    local value = quantity and quantity.value
    if type(value) == "number" then return math.abs(value) end
    if value == false or value == nil then return 0 end
    return 1
end

local function drawback_credit(drawback)
    if not drawback or drawback.kind == "none" then return 0 end
    return math.abs(tonumber(drawback.magnitude) or 1)
end

function M.balance(item)
    local gross = 0
    local lines = {}
    for _, rule in ipairs(item.rules or {}) do
        local stat = rule.operation and rule.operation.stat or ""
        local weight = BALANCE_WEIGHT[stat] or 1
        local target = rule.target and rule.target.selector or "self"
        local scope = TARGET_MULTIPLIER[target] or 1
        local cadence = rule.cadence and rule.cadence.interval or 1
        local value = magnitude_number(rule)
        local points = value * weight * scope / cadence
        if rule.cost and rule.cost.kind ~= "none" then
            points = points - math.abs(tonumber(rule.cost.magnitude) or 1)
        end
        if points < 0 then points = 0 end
        gross = gross + points
        lines[#lines + 1] = {
            rule_id = rule.id,
            stat = stat,
            points = math.floor(points * 1000 + 0.5) / 1000,
        }
    end
    local credit = drawback_credit(item.drawback)
    local spent = math.max(0, gross - credit)
    return {
        schema_version = M.SCHEMA_VERSION,
        rule_set_id = item.id,
        gross = math.floor(gross * 1000 + 0.5) / 1000,
        drawback_credit = credit,
        spent = math.floor(spent * 1000 + 0.5) / 1000,
        budget = item.rarity_budget,
        remaining = math.floor(((item.rarity_budget or 0) - spent) * 1000 + 0.5) / 1000,
        lines = lines,
    }
end

function M.validate(item)
    local errors = {}
    if not check_fields(item, ITEM_FIELDS, "rule_set", errors) then return false, errors end
    if item.schema_version ~= M.SCHEMA_VERSION then
        errors[#errors + 1] = "rule_set.schema_version must be " .. M.SCHEMA_VERSION
    end
    if item.kind ~= "rule_set" then errors[#errors + 1] = "rule_set.kind must be rule_set" end
    check_string(item.id, "rule_set.id", errors)
    check_string(item.name, "rule_set.name", errors)
    check_string(item.role, "rule_set.role", errors)

    local count = sequence_length(item.rules)
    if count == nil or count < 1 then
        errors[#errors + 1] = "rule_set.rules must be a non-empty array"
    else
        local ids = {}
        for index, rule in ipairs(item.rules) do
            validate_rule(rule, string.format("rule_set.rules[%d]", index), errors, ids)
        end
    end

    if check_fields(item.drawback, DRAWBACK_FIELDS, "rule_set.drawback", errors) then
        check_string(item.drawback.kind, "rule_set.drawback.kind", errors)
        if item.drawback.kind ~= nil and not ALLOWED_COST_KINDS[item.drawback.kind] then
            errors[#errors + 1] = "rule_set.drawback.kind is outside the canonical vocabulary"
        end
        if item.drawback.magnitude ~= nil and type(item.drawback.magnitude) ~= "number" then
            errors[#errors + 1] = "rule_set.drawback.magnitude must be numeric"
        end
        if item.drawback.kind ~= nil and item.drawback.kind ~= "none" then
            check_string(item.drawback.stat, "rule_set.drawback.stat", errors)
            if type(item.drawback.magnitude) ~= "number" then
                errors[#errors + 1] = "rule_set.drawback.magnitude is required"
            end
            if not ALLOWED_UNITS[item.drawback.unit] then
                errors[#errors + 1] = "rule_set.drawback.unit is outside the canonical vocabulary"
            end
        end
    end
    if check_fields(item.compatibility, COMPATIBILITY_FIELDS, "rule_set.compatibility", errors) then
        check_string_list(item.compatibility.requires, "rule_set.compatibility.requires", errors)
        check_string_list(item.compatibility.excludes, "rule_set.compatibility.excludes", errors)
        if type(item.compatibility.max_copies) ~= "number"
            or item.compatibility.max_copies < 1
            or item.compatibility.max_copies % 1 ~= 0 then
            errors[#errors + 1] = "rule_set.compatibility.max_copies must be a positive integer"
        end
    end
    check_string_list(item.synergy_tags, "rule_set.synergy_tags", errors)
    local tag_count = sequence_length(item.synergy_tags)
    if tag_count ~= nil and tag_count < 1 then
        errors[#errors + 1] = "rule_set.synergy_tags must not be empty"
    end
    if type(item.rarity_budget) ~= "number" or item.rarity_budget < 0 then
        errors[#errors + 1] = "rule_set.rarity_budget must be a non-negative number"
    end

    if #errors == 0 then
        local accounting = M.balance(item)
        if accounting.spent > item.rarity_budget then
            errors[#errors + 1] = string.format(
                "rule_set exceeds rarity budget: %.3f > %.3f",
                accounting.spent,
                item.rarity_budget
            )
        end
    end
    return #errors == 0, errors
end

function M.assert_valid(item)
    local valid, errors = M.validate(item)
    if not valid then error(table.concat(errors, "; "), 2) end
    return item
end

function M.compose(spec, sources)
    local item = {
        schema_version = M.SCHEMA_VERSION,
        kind = "rule_set",
        id = assert(spec.id, "composed rule set needs id"),
        name = assert(spec.name, "composed rule set needs name"),
        role = assert(spec.role, "composed rule set needs role"),
        rules = {},
        drawback = deep_copy(spec.drawback or { kind = "none" }),
        compatibility = deep_copy(spec.compatibility or {
            requires = {},
            excludes = {},
            max_copies = 1,
        }),
        synergy_tags = deep_copy(spec.synergy_tags or {}),
        rarity_budget = assert(spec.rarity_budget, "composed rule set needs rarity_budget"),
    }
    for source_index, source in ipairs(sources or {}) do
        M.assert_valid(source)
        for rule_index, rule in ipairs(source.rules) do
            local derived = deep_copy(rule)
            derived.id = string.format(
                "%s.%02d.%02d.%s",
                item.id,
                source_index,
                rule_index,
                rule.id
            )
            item.rules[#item.rules + 1] = derived
        end
    end
    return M.assert_valid(item)
end

local function projection_value(rule)
    if rule.magnitude then return rule.magnitude.value end
    return rule.duration and rule.duration.value
end

function M.project(item)
    M.assert_valid(item)
    local profile = {
        _rule_set_id = item.id,
        _rule_source = item.name,
        _rule_ids = {},
        _cadence = {},
    }
    for _, rule in ipairs(item.rules) do
        local stat = rule.operation.stat
        local value = projection_value(rule)
        if rule.operation.mode == "add" then
            profile[stat] = (profile[stat] or 0) + value
        else
            profile[stat] = value
        end
        profile._rule_ids[stat] = profile._rule_ids[stat] or {}
        profile._rule_ids[stat][#profile._rule_ids[stat] + 1] = rule.id
        profile._cadence[stat] = deep_copy(rule.cadence)
    end
    return profile
end

local function matches_token(item, token)
    if token == item.id then return true end
    local prefix, value = tostring(token):match("^([^:]+):(.+)$")
    if prefix == "role" then return item.role == value end
    if prefix == "tag" then
        for _, tag in ipairs(item.synergy_tags or {}) do
            if tag == value then return true end
        end
    end
    return false
end

function M.compatible(left, right)
    M.assert_valid(left)
    M.assert_valid(right)
    for _, token in ipairs(left.compatibility.excludes) do
        if matches_token(right, token) then
            return false, left.id .. " excludes " .. token
        end
    end
    for _, token in ipairs(right.compatibility.excludes) do
        if matches_token(left, token) then
            return false, right.id .. " excludes " .. token
        end
    end
    return true
end

function M.validate_collection(items)
    local errors = {}
    local counts = {}
    local available = {}
    local valid_items = {}
    for _, item in ipairs(items or {}) do
        local valid, item_errors = M.validate(item)
        if not valid then
            for _, message in ipairs(item_errors) do
                errors[#errors + 1] = tostring(type(item) == "table" and item.id or "item")
                    .. ": " .. message
            end
        else
            valid_items[#valid_items + 1] = item
            counts[item.id] = (counts[item.id] or 0) + 1
            available[item.id] = true
            available["role:" .. item.role] = true
            for _, tag in ipairs(item.synergy_tags or {}) do available["tag:" .. tag] = true end
        end
    end
    for _, item in ipairs(valid_items) do
        if counts[item.id] > item.compatibility.max_copies then
            errors[#errors + 1] = item.id .. " exceeds max_copies"
        end
        for _, requirement in ipairs(item.compatibility.requires) do
            if not available[requirement] then
                errors[#errors + 1] = item.id .. " requires " .. requirement
            end
        end
    end
    for left_index = 1, #valid_items do
        for right_index = left_index + 1, #valid_items do
            local valid, reason = M.compatible(valid_items[left_index], valid_items[right_index])
            if not valid then errors[#errors + 1] = reason end
        end
    end
    table.sort(errors)
    return #errors == 0, errors
end

local function quantity_copy(quantity)
    if not quantity then return "" end
    local value = quantity.value
    if type(value) == "boolean" then return value and "" or "not " end
    local unit = UNIT_COPY[quantity.unit] or tostring(quantity.unit)
    if unit == "%" or unit == "×" then return tostring(value) .. unit end
    if unit == "" then return tostring(value) end
    local rendered_unit = unit
    if math.abs(tonumber(value) or 0) ~= 1 then
        rendered_unit = UNIT_PLURAL[unit] or unit
    end
    return tostring(value) .. " " .. rendered_unit
end

local function operation_copy(rule)
    local value = quantity_copy(rule.magnitude or rule.duration)
    local target = TARGET_COPY[rule.target.selector] or rule.target.selector:gsub("_", " ")
    local verb = rule.operation.verb
    if verb == "deal" then return "deal " .. value .. " to " .. target
    elseif verb == "wear" then return "wear " .. target .. " by " .. value
    elseif verb == "prevent" then
        if rule.operation.stat == "harmless" then return "prevent wear to " .. target end
        return "prevent " .. value .. " for " .. target
    elseif verb == "heal" then return "restore " .. value .. " to " .. target
    elseif verb == "protect" then
        if rule.operation.stat == "hp" or rule.operation.stat == "durability" then
            if rule.target.selector == "self" then return "start with " .. value end
            return target .. " starts with " .. value
        elseif rule.operation.stat == "durability_bonus" then
            return "add " .. value .. " to every shell"
        end
        return "protect " .. target .. " from " .. value
    elseif verb == "accelerate" then return "give " .. target .. " +" .. value
    elseif verb == "slow" then
        if (rule.magnitude or rule.duration).unit == "multiplier" then
            local multiplier = tonumber((rule.magnitude or rule.duration).value)
            if multiplier then
                return "reduce " .. target .. " speed to "
                    .. tostring(math.floor(multiplier * 1000 + 0.5) / 10) .. "%"
            end
            return "multiply " .. target .. " speed by " .. value
        end
        return "reduce " .. target .. " by " .. value
    elseif verb == "aim" then return "shift " .. target .. " by " .. value
    elseif verb == "scatter" then return "vary " .. target .. " by up to " .. value
    elseif verb == "launch" then return "launch " .. value .. " from " .. target
    elseif verb == "rebound" then
        local amount = (rule.magnitude or rule.duration).value
        if type(amount) == "number" then
            return "multiply the rebound speed of " .. target .. " by "
                .. tostring(amount) .. "×"
        end
        return "make " .. target .. " retain extra rebound"
    elseif verb == "target" then return "make " .. target .. " choose the weakest brick"
    elseif verb == "amplify" then
        return "add " .. value .. " to non-chip hits and core-release power"
    elseif verb == "apply_status" then
        return "apply " .. tostring(rule.magnitude.value):gsub("_", " ") .. " to " .. target
    elseif verb == "pull" then return "pull " .. target .. " inward"
    elseif verb == "splash" then return "deal " .. value .. " to " .. target
    elseif verb == "negate" then return "negate damage to " .. target
    elseif verb == "break" then return "break " .. target
    elseif verb == "rewind" then return "restore " .. target .. " to its pre-contact state"
    elseif verb == "redirect" then return "redirect " .. target
    elseif verb == "push" then
        if rule.operation.stat == "radius" then
            return "push " .. target .. " within radius "
                .. tostring((rule.magnitude or rule.duration).value)
        end
        return "push " .. target .. " with " .. value
    elseif verb == "scorch" then return "scorch " .. target .. " for " .. value
    elseif verb == "cover" then
        return "cover a " .. tostring((rule.magnitude or rule.duration).value)
            .. "-radius field around " .. target
    elseif verb == "pierce" then return "ignore absorption for " .. target
    elseif verb == "persist" then return "last for " .. value
    elseif verb == "set" then return "set " .. target .. " to " .. value
    elseif verb == "hold" then return "hold " .. value
    end
    return verb:gsub("_", " ") .. " " .. target .. (value ~= "" and " by " .. value or "")
end

local function cadence_copy(cadence)
    if cadence.charges then return string.format(" (%d charge%s)", cadence.charges,
        cadence.charges == 1 and "" or "s") end
    if cadence.limit then return string.format(" (chain limit %d)", cadence.limit) end
    if cadence.interval > 1 then
        return string.format(" (every %d %s)", cadence.interval, cadence.unit)
    end
    return ""
end

function M.rule_sentence(rule)
    local trigger = TRIGGER_COPY[rule.trigger.event]
        or rule.trigger.event:gsub("_", " ")
    local condition = CONDITION_COPY[rule.condition.predicate]
        or (" when " .. rule.condition.predicate:gsub("_", " "))
    local sentence = trigger .. condition .. ", " .. operation_copy(rule)
        .. cadence_copy(rule.cadence) .. "."
    return sentence:sub(1, 1):upper() .. sentence:sub(2)
end

local function unique_lines(item, include)
    local lines, counts, order = {}, {}, {}
    for _, rule in ipairs(item.rules or {}) do
        if include[rule.visibility] then
            local line = M.rule_sentence(rule)
            if not counts[line] then order[#order + 1] = line end
            counts[line] = (counts[line] or 0) + 1
        end
    end
    for _, line in ipairs(order) do
        local count = counts[line]
        lines[#lines + 1] = count > 1 and (line .. " ×" .. count) or line
    end
    return lines
end

local function drawback_copy(drawback)
    if not drawback or drawback.kind == "none" then return "No additional rules cost." end
    local stat = tostring(drawback.stat or "value"):gsub("_", " ")
    local value = drawback.magnitude and tostring(drawback.magnitude) or ""
    local unit = drawback.unit and (UNIT_COPY[drawback.unit] or drawback.unit) or ""
    if drawback.kind == "opportunity" then
        return "Tradeoff: gives up " .. stat .. (value ~= "" and " " .. value or "") .. "."
    elseif drawback.kind == "reduce" then
        return "Tradeoff: loses " .. value .. (unit ~= "" and " " .. unit or "")
            .. " of " .. stat .. "."
    elseif drawback.kind == "risk" then
        return "Tradeoff: " .. stat .. " also affects allies."
    end
    return "Tradeoff: " .. drawback.kind:gsub("_", " ") .. " " .. stat .. "."
end

function M.compact_lines(item, max_lines)
    M.assert_valid(item)
    local lines = unique_lines(item, { compact = true })
    max_lines = max_lines or 2
    local out = {}
    for index = 1, math.min(max_lines, #lines) do out[#out + 1] = lines[index] end
    if #out == 0 then out[1] = "Role: " .. item.role .. "." end
    return out
end

function M.compact(item, max_lines)
    return table.concat(M.compact_lines(item, max_lines), " ")
end

function M.expanded_lines(item)
    M.assert_valid(item)
    local lines = { "Role: " .. item.role .. "." }
    local rules = unique_lines(item, { compact = true, expanded = true })
    for _, line in ipairs(rules) do lines[#lines + 1] = line end
    lines[#lines + 1] = drawback_copy(item.drawback)
    if #item.compatibility.requires > 0 then
        lines[#lines + 1] = "Requires: " .. table.concat(item.compatibility.requires, ", ") .. "."
    end
    if #item.compatibility.excludes > 0 then
        lines[#lines + 1] = "Cannot combine with: " .. table.concat(item.compatibility.excludes, ", ") .. "."
    end
    lines[#lines + 1] = "Synergy: " .. table.concat(item.synergy_tags, ", ") .. "."
    local accounting = M.balance(item)
    lines[#lines + 1] = string.format(
        "Balance: %.3f of %.3f points.",
        accounting.spent,
        accounting.budget
    )
    return lines
end

function M.expanded(item)
    return table.concat(M.expanded_lines(item), " ")
end

local function canonical_scalar(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    if value == nil then return "nil" end
    error("unsupported canonical scalar: " .. type(value))
end

local function canonical_value(value, visiting)
    if type(value) ~= "table" then return canonical_scalar(value) end
    visiting = visiting or {}
    if visiting[value] then error("canonical rule trees cannot contain cycles") end
    visiting[value] = true
    local parts = {}
    local length = sequence_length(value)
    if length ~= nil and length > 0 then
        for index = 1, length do parts[#parts + 1] = canonical_value(value[index], visiting) end
        visiting[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for _, key in ipairs(sorted_keys(value)) do
        parts[#parts + 1] = canonical_scalar(key) .. ":" .. canonical_value(value[key], visiting)
    end
    visiting[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

function M.canonical(item)
    M.assert_valid(item)
    return canonical_value(item)
end

function M.register(item)
    M.assert_valid(item)
    for _, rule in ipairs(item.rules) do
        local existing = registry[rule.id]
        if existing and existing.rule_set_id ~= item.id then
            error("rule id already registered by " .. existing.rule_set_id .. ": " .. rule.id)
        end
        registry[rule.id] = {
            rule_set_id = item.id,
            source_name = item.name,
            role = item.role,
            rule = deep_copy(rule),
        }
    end
    return item
end

function M.resolve(rule_id)
    local entry = registry[rule_id]
    return entry and deep_copy(entry) or nil
end

local function rule_id_for(source, stat)
    if not source then return nil end
    if source._rule_ids and source._rule_ids[stat] then
        return source._rule_ids[stat][1]
    end
    for _, rule in ipairs(source.rules or {}) do
        if rule.operation.stat == stat then return rule.id end
    end
    return nil
end

function M.attribute(fields, source, stat, overrides)
    fields = fields or {}
    local rule_id = rule_id_for(source, stat)
    if not rule_id then return fields end
    local entry = registry[rule_id]
    local rule = entry and entry.rule
    fields.rule_id = rule_id
    fields.rule_source = (overrides and overrides.source_name)
        or (entry and entry.source_name)
        or source._rule_source
    fields.rule_role = entry and entry.role or nil
    fields.rule_operation = rule and rule.operation.verb or nil
    fields.rule_target = rule and rule.target.selector or nil
    if rule and rule.magnitude then
        fields.rule_magnitude = rule.magnitude.value
        fields.rule_unit = rule.magnitude.unit
    elseif rule and rule.duration then
        fields.rule_magnitude = rule.duration.value
        fields.rule_unit = rule.duration.unit
    end
    return fields
end

local CALLOUT_VERB = {
    deal = "deals",
    wear = "wears",
    prevent = "prevents",
    heal = "restores",
    protect = "protects",
    accelerate = "accelerates",
    slow = "slows",
    aim = "redirects",
    scatter = "scatters",
    launch = "launches",
    rebound = "rebounds",
    target = "targets",
    amplify = "amplifies",
    apply_status = "applies",
    pull = "pulls",
    splash = "splashes",
    negate = "negates",
    ["break"] = "breaks",
    cover = "covers",
    rewind = "rewinds",
    redirect = "redirects",
    push = "pushes",
    scorch = "scorches",
    pierce = "pierces",
    persist = "persists",
    set = "sets",
}

function M.callout(event)
    if not event or not event.rule_id then return nil end
    local source = event.rule_source or "Rule"
    local verb = CALLOUT_VERB[event.rule_operation]
        or tostring(event.rule_operation or "triggers"):gsub("_", " ")
    local target = TARGET_COPY[event.rule_target]
        or tostring(event.rule_target or "the target"):gsub("_", " ")
    local amount = event.rule_magnitude
    local unit = UNIT_COPY[event.rule_unit] or event.rule_unit or ""
    local amount_copy = ""
    if type(amount) == "number" then
        amount_copy = " " .. tostring(amount)
        if unit ~= "" then amount_copy = amount_copy .. " " .. unit end
    elseif type(amount) == "string" and event.rule_operation == "apply_status" then
        amount_copy = " " .. amount:gsub("_", " ")
    end
    return source .. " " .. verb .. amount_copy .. " on " .. target
end

return M
