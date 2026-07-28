-- Canonical executable rule grammar.
--
-- Content owns one value-only RuleSet.  Validation, runtime projection,
-- player-facing copy, battle attribution, compatibility, and balance all read
-- this same tree.  None of those consumers is allowed to carry a second
-- handwritten description of what a rule means.

local M = {}

M.SCHEMA_VERSION = 2

local RARITY_ORDER = {
    "common",
    "uncommon",
    "rare",
    "epic",
    "legendary",
}

-- This value-only table is the sole economy authority. Draft, reward, setup,
-- presentation, and validation all project it instead of repeating tier
-- numbers in private lookup tables.
local ECONOMY = {
    schema_version = 1,
    kind = "economy_rule_set",
    id = "economy.rarity.v1",
    rarity_order = RARITY_ORDER,
    tiers = {
        common = {
            rank = 1, shell_cap = 1,
            bonus_release_groups = 0, bonus_release_mcu = 0,
            brick_passive_groups = 0, brick_passive_mcu = 0,
            brick_copy_cap = 4, marble_copy_cap = 3,
        },
        uncommon = {
            rank = 2, shell_cap = 2,
            bonus_release_groups = 1, bonus_release_mcu = 2,
            brick_passive_groups = 1, brick_passive_mcu = 2,
            brick_copy_cap = 3, marble_copy_cap = 2,
        },
        rare = {
            rank = 3, shell_cap = 3,
            bonus_release_groups = 1, bonus_release_mcu = 4,
            brick_passive_groups = 1, brick_passive_mcu = 4,
            brick_copy_cap = 2, marble_copy_cap = 2,
        },
        epic = {
            rank = 4, shell_cap = 4,
            bonus_release_groups = 2, bonus_release_mcu = 6,
            brick_passive_groups = 2, brick_passive_mcu = 6,
            brick_copy_cap = 1, marble_copy_cap = 1,
        },
        legendary = {
            rank = 5, shell_cap = 5,
            bonus_release_groups = 2, bonus_release_mcu = 8,
            brick_passive_groups = 2, brick_passive_mcu = 8,
            brick_copy_cap = 1, marble_copy_cap = 1,
        },
    },
    acquisition = {
        full_loadout_initial = {
            common = 50, uncommon = 28, rare = 14, epic = 6, legendary = 2,
        },
        short_run_win_1 = {
            common = 50, uncommon = 32, rare = 18, epic = 0, legendary = 0,
        },
        short_run_win_2_plus = {
            common = 35, uncommon = 30, rare = 20, epic = 12, legendary = 3,
        },
    },
}

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
    content_kind = true,
    component_kind = true,
    rarity = true,
    min_rarity = true,
    availability = true,
    abilities = true,
    components = true,
    formation = true,
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
    scaling = true,
    lethal = true,
}

local TRIGGER_FIELDS = { event = true, phase = true }
local CONDITION_FIELDS = { predicate = true, value = true }
local TARGET_FIELDS = {
    selector = true,
    relation = true,
    topology = true,
    count = true,
    exclude_self = true,
    require_alive = true,
    required_tags = true,
    excluded_tags = true,
    order = true,
    radius = true,
}
local OPERATION_FIELDS = { verb = true, stat = true, mode = true }
local QUANTITY_FIELDS = { value = true, unit = true }
local CADENCE_FIELDS = { unit = true, interval = true, charges = true, limit = true }
local COST_FIELDS = { kind = true, stat = true, magnitude = true, unit = true }
local DRAWBACK_FIELDS = { kind = true, stat = true, magnitude = true, unit = true }
local COMPATIBILITY_FIELDS = { requires = true, excludes = true, max_copies = true }
local AVAILABILITY_FIELDS = {
    player_draft = true,
    player_reward = true,
    cpu_recipe = true,
    legacy_only = true,
}
local ABILITY_FIELDS = {
    id = true,
    kind = true,
    rule_ids = true,
    cost_rule_id = true,
    payoff_rule_ids = true,
    recursion = true,
}
local RECURSION_FIELDS = { accepts_causes = true, max_generation = true }
local SCALING_FIELDS = {
    basis = true,
    numerator = true,
    denominator = true,
    cap = true,
    rounding = true,
}
local COMPONENT_FIELDS = { id = true, kind = true, min_rarity = true, order = true }
local FORMATION_FIELDS = { rear_row = true }
local ALLOWED_CAUSES = {
    ability_cost = true,
    ability_payoff = true,
    chain = true,
    hostile_collision = true,
    poison = true,
    shrapnel = true,
}

local ALLOWED_VISIBILITY = {
    compact = true,
    expanded = true,
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
    ability_cost_paid = true,
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
    nearest_enemy_brick_cluster = true,
    chain_enemy_marbles = true,
    orthogonal_neighbours = true,
    release_area = true,
    self = true,
    striking_marble = true,
    struck_brick = true,
    target_column = true,
    setup_linked_allied_brick = true,
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
    guard = true,
    chain_shell_wear = true,
    restitution = true,
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
    guard = { protect = true },
    chain_shell_wear = { wear = true },
    restitution = { set = true },
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
    guard = 4.0,
    chain_shell_wear = 1.5,
    restitution = 8.0,
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
    nearest_enemy_brick_cluster = 1.8,
    chain_enemy_marbles = 2.0,
    release_area = 2.0,
    target_column = 1.4,
    setup_linked_allied_brick = 1.0,
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
    ability_cost_paid = "After its linked cost is paid",
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
    nearest_enemy_brick_cluster = "the nearest enemy brick and its orthogonal allies",
    chain_enemy_marbles = "the causal and two nearest enemy marbles",
    release_area = "the core release",
    target_column = "the target column",
    setup_linked_allied_brick = "the setup-linked allied brick",
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

local function deep_equal(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not deep_equal(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function is_player_rule(rule)
    return type(rule) == "table"
        and (rule.visibility == "compact" or rule.visibility == "expanded")
end

-- Executable routing values are rules, not hidden metadata. Every consumer
-- uses this exact ordered projection so execution identity, copy, inspection,
-- attribution, and accounting cannot disagree about item membership.
function M.player_rules(item)
    local out = {}
    for _, rule in ipairs((item and item.rules) or {}) do
        if is_player_rule(rule) then out[#out + 1] = deep_copy(rule) end
    end
    return out
end

function M.player_rule_ids(item)
    local out = {}
    for _, rule in ipairs(M.player_rules(item)) do out[#out + 1] = rule.id end
    return out
end

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
        if rule.target.relation ~= nil
            and rule.target.relation ~= "allied"
            and rule.target.relation ~= "enemy"
            and rule.target.relation ~= "self"
            and rule.target.relation ~= "symmetric" then
            errors[#errors + 1] = path .. ".target.relation is outside the canonical vocabulary"
        end
        if rule.target.count ~= nil
            and (type(rule.target.count) ~= "number"
                or rule.target.count < 1
                or rule.target.count % 1 ~= 0) then
            errors[#errors + 1] = path .. ".target.count must be a positive integer"
        end
        if rule.target.radius ~= nil
            and (type(rule.target.radius) ~= "number" or rule.target.radius < 0) then
            errors[#errors + 1] = path .. ".target.radius must be non-negative"
        end
        if rule.target.topology ~= nil and not nonempty(rule.target.topology) then
            errors[#errors + 1] = path .. ".target.topology must be a non-empty string"
        end
        if rule.target.order ~= nil and not nonempty(rule.target.order) then
            errors[#errors + 1] = path .. ".target.order must be a non-empty string"
        end
        for _, field in ipairs({ "exclude_self", "require_alive" }) do
            if rule.target[field] ~= nil and type(rule.target[field]) ~= "boolean" then
                errors[#errors + 1] = path .. ".target." .. field .. " must be boolean"
            end
        end
        if rule.target.required_tags ~= nil then
            check_string_list(rule.target.required_tags, path .. ".target.required_tags", errors)
        end
        if rule.target.excluded_tags ~= nil then
            check_string_list(rule.target.excluded_tags, path .. ".target.excluded_tags", errors)
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
            and rule.cadence.unit ~= "ticks"
            and rule.cadence.unit ~= "exchange" then
            errors[#errors + 1] = path .. ".cadence.unit is outside the canonical vocabulary"
        end
        if type(rule.cadence.interval) ~= "number"
            or rule.cadence.interval < 1
            or rule.cadence.interval % 1 ~= 0 then
            errors[#errors + 1] = path .. ".cadence.interval must be a positive integer"
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
    if rule.scaling ~= nil
        and check_fields(rule.scaling, SCALING_FIELDS, path .. ".scaling", errors) then
        if rule.scaling.basis ~= "cost_damage_applied" then
            errors[#errors + 1] = path .. ".scaling.basis must be cost_damage_applied"
        end
        if type(rule.scaling.numerator) ~= "number"
            or rule.scaling.numerator < 0
            or rule.scaling.numerator % 1 ~= 0 then
            errors[#errors + 1] = path .. ".scaling.numerator must be a non-negative integer"
        end
        if type(rule.scaling.denominator) ~= "number"
            or rule.scaling.denominator < 1
            or rule.scaling.denominator % 1 ~= 0 then
            errors[#errors + 1] = path .. ".scaling.denominator must be a positive integer"
        end
        if type(rule.scaling.cap) ~= "number"
            or rule.scaling.cap < 0
            or rule.scaling.cap % 1 ~= 0 then
            errors[#errors + 1] = path .. ".scaling.cap must be a non-negative integer"
        end
        if rule.scaling.rounding ~= "floor" then
            errors[#errors + 1] = path .. ".scaling.rounding must be floor"
        end
    end
    if rule.lethal ~= nil and type(rule.lethal) ~= "boolean" then
        errors[#errors + 1] = path .. ".lethal must be boolean"
    end
    if not ALLOWED_VISIBILITY[rule.visibility] then
        errors[#errors + 1] = path .. ".visibility must be compact or expanded"
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

local RARITY_RANK = {}
for rank, rarity in ipairs(RARITY_ORDER) do RARITY_RANK[rarity] = rank end

function M.rarity_rank(rarity)
    return RARITY_RANK[rarity]
end

function M.rarity_order()
    return deep_copy(RARITY_ORDER)
end

function M.economy()
    return deep_copy(ECONOMY)
end

function M.economy_id()
    return ECONOMY.id
end

function M.acquisition(acquisition_id)
    local weights = ECONOMY.acquisition[acquisition_id]
    return weights and deep_copy(weights) or nil
end

function M.tier(rarity)
    local tier = ECONOMY.tiers[rarity]
    return tier and deep_copy(tier) or nil
end

local MULTI_TARGET = {
    all_owned_marbles = true,
    chain_enemy_marbles = true,
    nearby_marbles = true,
    nearest_enemy_brick_cluster = true,
    orthogonal_neighbours = true,
    release_area = true,
    target_column = true,
}

local TRACKED_STATS = {
    duration_ticks = true,
    field_duration = true,
    guard = true,
    negate_once = true,
    rewind = true,
    status = true,
}

local RULE_CHANGING_VERBS = {
    ["break"] = true,
    negate = true,
    redirect = true,
    rewind = true,
    target = true,
}

-- An authored cost annotation never grants friendly-harm authority. The only
-- canonical allied harmful operation is the exact cost rule owned by an
-- allied_brick_cost group; every generic target/verb combination fails schema
-- validation before it can reach setup or runtime.
local ALLIED_HARM_VERBS = {
    ["break"] = true,
    apply_status = true,
    deal = true,
    pull = true,
    push = true,
    redirect = true,
    scorch = true,
    slow = true,
    splash = true,
    wear = true,
}

local function brick_body_behaviour(item)
    local slug = type(item.id) == "string" and item.id:match("^brick%.([%w_]+)$")
    if not slug then return nil, nil end
    for _, rule in ipairs(item.rules or {}) do
        if rule.id == "brick." .. slug .. ".behaviour"
            and rule.trigger.event == "build"
            and rule.operation.stat == "behaviour" then
            return slug, rule.magnitude.value
        end
    end
    return slug, nil
end

-- Bricks may carry only their three authored body projections plus the
-- behaviour/status identity projections selected by that body. Every other
-- rule, including a rule whose trigger was changed to "build", is an ability
-- and must belong to a canonical ability group.
local function is_brick_body_rule(item, rule)
    if not rule or not rule.trigger or rule.trigger.event ~= "build"
        or not rule.operation then return false end
    local slug, behaviour = brick_body_behaviour(item)
    if not slug or not behaviour then return false end
    if rule.id == "brick." .. slug .. "." .. tostring(rule.operation.stat) then
        return rule.operation.stat == "hp"
            or rule.operation.stat == "restitution"
            or rule.operation.stat == "behaviour"
    end
    if rule.id == "brick." .. tostring(behaviour) .. ".identity" then
        return rule.operation.stat == "behaviour"
            and rule.magnitude.value == behaviour
    end
    if rule.id == "status." .. tostring(behaviour) .. ".identity" then
        return rule.operation.stat == "status"
            and rule.magnitude.value == behaviour
    end
    return false
end

local ROUTING_STATS = {
    behaviour = true,
    collision = true,
    field_radius = true,
    field_strength = true,
    duration_ticks = true,
    field_duration = true,
    release = true,
    -- Applying a named status routes into that status's separately authored
    -- and separately priced operations; it does not hide an extra payoff.
    status = true,
    trajectory = true,
}

local function ability_rule_ids(group)
    if group.kind == "allied_brick_cost" then
        local out = { group.cost_rule_id }
        for _, rule_id in ipairs(group.payoff_rule_ids or {}) do out[#out + 1] = rule_id end
        return out
    end
    return group.rule_ids or {}
end

local function ability_mcu(group, by_id)
    local rules = {}
    for _, rule_id in ipairs(ability_rule_ids(group)) do
        if by_id[rule_id] then rules[#rules + 1] = by_id[rule_id] end
    end
    local effect_operations = 0
    local multi, tracked, rule_change = false, false, false
    for _, rule in ipairs(rules) do
        local stat = rule.operation and rule.operation.stat
        local is_linked_cost = group.kind == "allied_brick_cost"
            and rule.id == group.cost_rule_id
        if not ROUTING_STATS[stat] and not is_linked_cost then
            -- MCU prices authored effect operations, not distinct verb names.
            -- Two payoffs that both wear a shell remain two mechanics to
            -- understand and cannot collapse into one by sharing a verb.
            effect_operations = effect_operations + 1
        end
        local target = rule.target or {}
        if MULTI_TARGET[target.selector] or (target.count or 1) > 1 then multi = true end
        if stat == "field_radius" then multi = true end
        if TRACKED_STATS[stat] or rule.duration ~= nil
            or (rule.cadence and (rule.cadence.charges or rule.cadence.interval > 1)) then
            tracked = true
        end
        if RULE_CHANGING_VERBS[rule.operation and rule.operation.verb] then
            rule_change = true
        end
    end
    local mcu = 1 + math.max(0, effect_operations - 1)
    if multi then mcu = mcu + 1 end
    if tracked then mcu = mcu + 1 end
    if rule_change then mcu = mcu + 1 end
    if group.recursion and (group.recursion.max_generation or 0) > 0 then mcu = mcu + 1 end
    if group.kind == "allied_brick_cost" then mcu = mcu + 1 end
    return mcu
end

function M.ability_summary(item)
    local by_id = {}
    for _, rule in ipairs((item and item.rules) or {}) do
        if nonempty(rule.id) then by_id[rule.id] = rule end
    end
    local groups, mcu = {}, 0
    for _, group in ipairs((item and item.abilities) or {}) do
        local cost = ability_mcu(group, by_id)
        groups[#groups + 1] = {
            id = group.id,
            kind = group.kind,
            mcu = cost,
            rule_ids = deep_copy(ability_rule_ids(group)),
        }
        mcu = mcu + cost
    end
    return { groups = groups, count = #groups, mcu = mcu }
end

function M.linked_cost_groups(item)
    local out = {}
    for _, group in ipairs((item and item.abilities) or {}) do
        if group.kind == "allied_brick_cost" then out[#out + 1] = deep_copy(group) end
    end
    return out
end

local function validate_availability(item, errors)
    local path = "rule_set.availability"
    if not check_fields(item.availability, AVAILABILITY_FIELDS, path, errors) then return end
    for field in pairs(AVAILABILITY_FIELDS) do
        if type(item.availability[field]) ~= "boolean" then
            errors[#errors + 1] = path .. "." .. field .. " must be boolean"
        end
    end
    if item.availability.legacy_only
        and (item.availability.player_draft or item.availability.player_reward) then
        errors[#errors + 1] = path .. " legacy-only content cannot be player-acquired"
    end
end

local function validate_components(item, errors)
    local length = sequence_length(item.components)
    if length == nil then
        errors[#errors + 1] = "rule_set.components must be an array"
        return
    end
    for index, component in ipairs(item.components) do
        local path = string.format("rule_set.components[%d]", index)
        if check_fields(component, COMPONENT_FIELDS, path, errors) then
            check_string(component.id, path .. ".id", errors)
            check_string(component.kind, path .. ".kind", errors)
            if component.min_rarity ~= nil and not RARITY_RANK[component.min_rarity] then
                errors[#errors + 1] = path .. ".min_rarity is invalid"
            end
            if component.order ~= index then
                errors[#errors + 1] = path .. ".order must match canonical composition order"
            end
        end
    end
end

local function validate_abilities(item, errors)
    local length = sequence_length(item.abilities)
    if length == nil then
        errors[#errors + 1] = "rule_set.abilities must be an array"
        return
    end
    local rules, assigned, group_ids, linked_cost_rules = {}, {}, {}, {}
    for _, rule in ipairs(item.rules or {}) do
        if nonempty(rule.id) then rules[rule.id] = rule end
    end
    for index, group in ipairs(item.abilities or {}) do
        local path = string.format("rule_set.abilities[%d]", index)
        if check_fields(group, ABILITY_FIELDS, path, errors) then
            check_string(group.id, path .. ".id", errors)
            if nonempty(group.id) then
                if group_ids[group.id] then errors[#errors + 1] = path .. ".id is duplicated" end
                group_ids[group.id] = true
            end
            if group.kind ~= "passive" and group.kind ~= "core_release"
                and group.kind ~= "allied_brick_cost" then
                errors[#errors + 1] = path .. ".kind is invalid"
            end
            if item.content_kind == "brick" and group.kind == "core_release" then
                errors[#errors + 1] = path .. " brick ability cannot be a core release"
            elseif item.content_kind == "marble" and group.kind ~= "core_release" then
                errors[#errors + 1] = path .. " marble bonus ability must be a core release"
            end
            if group.kind == "allied_brick_cost" and item.content_kind ~= "brick" then
                errors[#errors + 1] = path .. " linked allied cost source must be a brick"
            end
            if group.recursion ~= nil
                and check_fields(group.recursion, RECURSION_FIELDS,
                    path .. ".recursion", errors) then
                check_string_list(group.recursion.accepts_causes,
                    path .. ".recursion.accepts_causes", errors)
                for _, cause in ipairs(group.recursion.accepts_causes or {}) do
                    if not ALLOWED_CAUSES[cause] then
                        errors[#errors + 1] =
                            path .. ".recursion accepts unknown cause " .. tostring(cause)
                    end
                end
                if type(group.recursion.max_generation) ~= "number"
                    or group.recursion.max_generation < 0
                    or group.recursion.max_generation > 3
                    or group.recursion.max_generation % 1 ~= 0 then
                    errors[#errors + 1] =
                        path .. ".recursion.max_generation must be an integer from 0 through 3"
                end
            end
            local ids
            if group.kind == "allied_brick_cost" then
                if nonempty(group.cost_rule_id) then
                    linked_cost_rules[group.cost_rule_id] = true
                end
                check_string(group.cost_rule_id, path .. ".cost_rule_id", errors)
                check_string_list(group.payoff_rule_ids, path .. ".payoff_rule_ids", errors)
                if sequence_length(group.payoff_rule_ids) == 0 then
                    errors[#errors + 1] = path .. ".payoff_rule_ids must not be empty"
                end
                ids = ability_rule_ids(group)
                if group.recursion == nil then
                    errors[#errors + 1] = path .. ".recursion is required"
                end
                local cost_rule = rules[group.cost_rule_id]
                if cost_rule then
                    local target = cost_rule.target or {}
                    local cadence = cost_rule.cadence or {}
                    local magnitude = cost_rule.magnitude or {}
                    if item.rarity and RARITY_RANK[item.rarity] < RARITY_RANK.rare then
                        errors[#errors + 1] = path .. " is invalid below rare"
                    end
                    if target.selector ~= "setup_linked_allied_brick"
                        or target.relation ~= "allied"
                        or target.topology ~= "orthogonal"
                        or target.count ~= 1
                        or target.exclude_self ~= true
                        or target.require_alive ~= true
                        or target.order ~= "local_row_col_uid"
                        or sequence_length(target.required_tags) == nil
                        or sequence_length(target.excluded_tags) == nil then
                        errors[#errors + 1] = path .. " cost selector is not a narrow setup link"
                    end
                    if cost_rule.operation.verb ~= "deal"
                        or cost_rule.operation.stat ~= "damage"
                        or cost_rule.operation.mode ~= "set"
                        or magnitude.unit ~= "damage"
                        or type(magnitude.value) ~= "number"
                        or magnitude.value <= 0
                        or magnitude.value % 1 ~= 0 then
                        errors[#errors + 1] = path .. " cost rule must deal exact positive integer damage"
                    end
                    if cadence.charges == nil or cadence.charges < 1 or cadence.charges > 3 then
                        errors[#errors + 1] = path .. " cost cadence needs one through three charges"
                    end
                    if cadence.unit ~= "ticks" and cadence.unit ~= "exchange"
                        and cadence.unit ~= cost_rule.trigger.event then
                        errors[#errors + 1] =
                            path .. " cost trigger and cadence data do not match"
                    end
                    if type(cost_rule.lethal) ~= "boolean" then
                        errors[#errors + 1] = path .. " cost rule must declare lethal"
                    end
                end
                for _, payoff_id in ipairs(group.payoff_rule_ids or {}) do
                    local payoff = rules[payoff_id]
                    if payoff and (payoff.trigger.event ~= "ability_cost_paid"
                        or payoff.condition.value ~= group.id
                        or payoff.scaling == nil) then
                        errors[#errors + 1] =
                            path .. " payoff must bind its scaling to this ability_cost_paid event"
                    end
                    if payoff and payoff.scaling and payoff.magnitude
                        and payoff.magnitude.value ~= payoff.scaling.cap then
                        errors[#errors + 1] =
                            path .. " payoff magnitude must equal its canonical scaling cap"
                    end
                end
            else
                check_string_list(group.rule_ids, path .. ".rule_ids", errors)
                if sequence_length(group.rule_ids) == 0 then
                    errors[#errors + 1] = path .. ".rule_ids must not be empty"
                end
                ids = group.rule_ids or {}
            end
            for _, rule_id in ipairs(ids or {}) do
                if not rules[rule_id] then
                    errors[#errors + 1] = path .. " references missing rule " .. tostring(rule_id)
                elseif assigned[rule_id] then
                    errors[#errors + 1] = path .. " double-groups rule " .. tostring(rule_id)
                else
                    local grouped_rule = rules[rule_id]
                    if group.kind == "passive"
                        and is_brick_body_rule(item, grouped_rule) then
                        errors[#errors + 1] =
                            path .. " cannot disguise a body rule as a passive"
                    elseif group.kind == "core_release"
                        and (grouped_rule.trigger.event ~= "core_release"
                            or rule_id:match("^release%.baseline%.")) then
                        errors[#errors + 1] =
                            path .. " must contain only bonus core-release rules"
                    end
                    assigned[rule_id] = group.id
                end
            end
        end
    end

    for _, rule in ipairs(item.rules or {}) do
        if rule.target
            and rule.target.relation == "allied"
            and rule.operation
            and ALLIED_HARM_VERBS[rule.operation.verb]
            and not linked_cost_rules[rule.id] then
            errors[#errors + 1] =
                "generic allied harm is forbidden outside an allied_brick_cost rule: "
                .. tostring(rule.id)
        end
    end

    if item.content_kind == "brick" then
        for _, rule in ipairs(item.rules or {}) do
            if not is_brick_body_rule(item, rule) and not assigned[rule.id] then
                errors[#errors + 1] = "rule_set has ungrouped brick rule " .. rule.id
            end
        end
    elseif item.content_kind == "marble" then
        for _, rule in ipairs(item.rules or {}) do
            if rule.trigger.event == "core_release"
                and not rule.id:match("^release%.baseline%.")
                and not assigned[rule.id] then
                errors[#errors + 1] = "rule_set has ungrouped bonus release rule " .. rule.id
            end
        end
    end
end

function M.balance(item)
    local gross = 0
    local lines = {}
    local points_by_rule = {}
    local linked_cost_group_by_rule = {}
    local linked_cost_points = {}
    for _, group in ipairs((item and item.abilities) or {}) do
        if group.kind == "allied_brick_cost" then
            linked_cost_group_by_rule[group.cost_rule_id] = group.id
        end
    end
    for _, rule in ipairs(M.player_rules(item)) do
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
        points_by_rule[rule.id] = points
        local linked_group = linked_cost_group_by_rule[rule.id]
        if linked_group then
            linked_cost_points[linked_group] = points
        else
            gross = gross + points
        end
        lines[#lines + 1] = {
            rule_id = rule.id,
            stat = stat,
            operation = rule.operation.verb,
            mode = rule.operation.mode,
            target = target,
            value = deep_copy((rule.magnitude or rule.duration).value),
            unit = (rule.magnitude or rule.duration).unit,
            cadence = deep_copy(rule.cadence),
            points = linked_group and 0 or math.floor(points * 1000 + 0.5) / 1000,
            credit = linked_group and math.floor(points * 1000 + 0.5) / 1000
                or nil,
        }
    end
    local ability_summary = M.ability_summary(item)
    for _, group in ipairs(ability_summary.groups) do
        local points = group.mcu * 2
        gross = gross + points
        lines[#lines + 1] = {
            rule_id = "ability:" .. group.id,
            stat = "mechanical_complexity",
            operation = group.kind,
            mode = "set",
            target = "ability_group",
            value = group.mcu,
            unit = "count",
            cadence = {},
            points = points,
        }
    end
    local allied_cost_credit = 0
    local allied_cost_excess = 0
    for _, group in ipairs((item and item.abilities) or {}) do
        if group.kind == "allied_brick_cost" then
            local payoff_points = 0
            for _, rule_id in ipairs(group.payoff_rule_ids or {}) do
                payoff_points = payoff_points + (points_by_rule[rule_id] or 0)
            end
            local cost_points = linked_cost_points[group.id] or 0
            allied_cost_credit = allied_cost_credit + math.min(cost_points, payoff_points)
            if cost_points > payoff_points then
                allied_cost_excess = allied_cost_excess + cost_points - payoff_points
            end
        end
    end
    local authored_credit = drawback_credit(item.drawback)
    local total_credit = authored_credit + allied_cost_credit
    local spent = gross - total_credit
    return {
        schema_version = M.SCHEMA_VERSION,
        rule_set_id = item.id,
        gross = math.floor(gross * 1000 + 0.5) / 1000,
        drawback_credit = authored_credit,
        allied_cost_credit = math.floor(allied_cost_credit * 1000 + 0.5) / 1000,
        total_credit = math.floor(total_credit * 1000 + 0.5) / 1000,
        allied_cost_excess = math.floor(allied_cost_excess * 1000 + 0.5) / 1000,
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
    check_string(item.content_kind, "rule_set.content_kind", errors)
    if item.content_kind ~= "component"
        and item.content_kind ~= "sling"
        and item.content_kind ~= "marble"
        and item.content_kind ~= "brick"
        and item.content_kind ~= "brick_kit" then
        errors[#errors + 1] = "rule_set.content_kind is invalid"
    end
    if item.content_kind == "component" then
        check_string(item.component_kind, "rule_set.component_kind", errors)
        if item.component_kind == "core" and not RARITY_RANK[item.min_rarity] then
            errors[#errors + 1] =
                "core component rule set must declare canonical min_rarity"
        end
    elseif item.component_kind ~= nil then
        errors[#errors + 1] = "rule_set.component_kind is only valid for components"
    end
    if item.rarity ~= nil and not RARITY_RANK[item.rarity] then
        errors[#errors + 1] = "rule_set.rarity is invalid"
    end
    if item.min_rarity ~= nil and not RARITY_RANK[item.min_rarity] then
        errors[#errors + 1] = "rule_set.min_rarity is invalid"
    end
    validate_availability(item, errors)
    validate_components(item, errors)

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
    validate_abilities(item, errors)
    if item.formation ~= nil
        and check_fields(item.formation, FORMATION_FIELDS, "rule_set.formation", errors)
        and item.formation.rear_row ~= nil
        and type(item.formation.rear_row) ~= "boolean" then
        errors[#errors + 1] = "rule_set.formation.rear_row must be boolean"
    end
    check_string_list(item.synergy_tags, "rule_set.synergy_tags", errors)
    local tag_count = sequence_length(item.synergy_tags)
    if tag_count ~= nil and tag_count < 1 then
        errors[#errors + 1] = "rule_set.synergy_tags must not be empty"
    end
    if type(item.rarity_budget) ~= "number" or item.rarity_budget < 0 then
        errors[#errors + 1] = "rule_set.rarity_budget must be a non-negative number"
    end

    if item.content_kind == "marble" or item.content_kind == "brick" then
        if item.rarity_budget ~= 100 then
            errors[#errors + 1] = "complete marble and brick rarity_budget must equal 100"
        end
        if not item.rarity then
            errors[#errors + 1] = "complete marble and brick content must declare rarity"
        end
        local tier = item.rarity and ECONOMY.tiers[item.rarity]
        if tier then
            local summary = M.ability_summary(item)
            local group_cap = item.content_kind == "brick"
                and tier.brick_passive_groups or tier.bonus_release_groups
            local mcu_cap = item.content_kind == "brick"
                and tier.brick_passive_mcu or tier.bonus_release_mcu
            if summary.count > group_cap then
                errors[#errors + 1] = "rule_set exceeds " .. item.rarity .. " ability-group ceiling"
            end
            if summary.mcu > mcu_cap then
                errors[#errors + 1] = "rule_set exceeds " .. item.rarity .. " MCU ceiling"
            end
            local copy_cap = item.content_kind == "brick"
                and tier.brick_copy_cap or tier.marble_copy_cap
            if item.compatibility and item.compatibility.max_copies > copy_cap then
                errors[#errors + 1] = "rule_set exceeds " .. item.rarity .. " copy ceiling"
            end
            if item.content_kind == "brick" and item.rarity == "common"
                and summary.count ~= 0 then
                errors[#errors + 1] = "common brick must have zero passives"
            end
            if item.content_kind == "marble" then
                local shell_count, core_count, core_min = 0, 0, "common"
                for _, component in ipairs(item.components or {}) do
                    if component.kind == "shell" then shell_count = shell_count + 1 end
                    if component.kind == "core" then
                        core_count = core_count + 1
                        core_min = component.min_rarity or "common"
                    end
                end
                if core_count ~= 1 then
                    errors[#errors + 1] = "marble must contain exactly one core"
                end
                if shell_count < 1 then
                    errors[#errors + 1] = "marble must contain at least one shell"
                elseif shell_count > tier.shell_cap then
                    errors[#errors + 1] = "marble exceeds " .. item.rarity .. " shell cap"
                end
                if RARITY_RANK[core_min] and RARITY_RANK[core_min] > RARITY_RANK[item.rarity] then
                    errors[#errors + 1] = "marble core is below its canonical minimum rarity"
                end
                if item.rarity == "common" and summary.count > 0 then
                    errors[#errors + 1] = "common marble cannot have a bonus core release"
                end
                local baseline = {}
                for _, rule in ipairs(item.rules or {}) do baseline[rule.id] = true end
                for _, rule_id in ipairs({
                    "release.baseline.radius",
                    "release.baseline.field_duration",
                    "release.baseline.field_strength",
                }) do
                    if not baseline[rule_id] then
                        errors[#errors + 1] =
                            "marble is missing mandatory baseline core release rule " .. rule_id
                    end
                end
            end
        end
    end
    if item.content_kind == "brick_kit" then
        local highest_rank, member_count = 0, 0
        for _, component in ipairs(item.components or {}) do
            member_count = member_count + 1
            if component.kind ~= "brick" then
                errors[#errors + 1] =
                    "brick kit components must be individual bricks"
            end
            highest_rank = math.max(
                highest_rank,
                RARITY_RANK[component.min_rarity] or 0
            )
        end
        if member_count < 1 then
            errors[#errors + 1] = "brick kit must contain at least one brick"
        end
        if not item.rarity or RARITY_RANK[item.rarity] ~= highest_rank then
            errors[#errors + 1] =
                "brick kit rarity must equal its highest member rarity"
        end
        if #(item.abilities or {}) ~= 0 then
            errors[#errors + 1] =
                "brick kit is packaging and cannot own ability groups"
        end
        if item.availability and item.availability.player_reward then
            errors[#errors + 1] =
                "brick kit cannot enter individual player rewards"
        end
    end

    if item.drawback and drawback_credit(item.drawback) > 25 then
        errors[#errors + 1] = "rule_set drawback/formation/copy credit exceeds 25"
    end
    for _, rule in ipairs(item.rules or {}) do
        local stat = rule.operation and rule.operation.stat
        if rule.trigger and rule.trigger.event ~= "build"
            and not ROUTING_STATS[stat]
            and (BALANCE_WEIGHT[stat] or 1) <= 0 then
            errors[#errors + 1] = "executable effect has zero balance weight: " .. tostring(rule.id)
        end
    end

    if #errors == 0 then
        local accounting = M.balance(item)
        if accounting.allied_cost_excess > 0 then
            errors[#errors + 1] =
                "allied-cost credit exceeds the priced value of its payoff"
        end
        if accounting.total_credit > 25 then
            errors[#errors + 1] =
                "rule_set drawback/formation/copy credit exceeds 25"
        end
        if accounting.spent < 0 then
            errors[#errors + 1] = "rule_set has a negative net ability cost"
        end
        if item.content_kind ~= "brick_kit" and accounting.spent > item.rarity_budget then
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
    local availability = deep_copy(spec.availability or {
        player_draft = false,
        player_reward = false,
        cpu_recipe = false,
        legacy_only = false,
    })
    local components = deep_copy(spec.components or {})
    if spec.components == nil then
        for _, source in ipairs(sources or {}) do
            if source.content_kind == "component" then
                components[#components + 1] = {
                    id = source.id,
                    kind = source.component_kind,
                    min_rarity = source.min_rarity,
                    order = #components + 1,
                }
            elseif spec.content_kind == "brick_kit"
                and source.content_kind == "brick" then
                components[#components + 1] = {
                    id = source.id,
                    kind = "brick",
                    min_rarity = source.rarity,
                    order = #components + 1,
                }
            end
        end
    end
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
        content_kind = assert(spec.content_kind, "composed rule set needs content_kind"),
        component_kind = spec.component_kind,
        rarity = spec.rarity,
        min_rarity = spec.min_rarity,
        availability = availability,
        abilities = deep_copy(spec.abilities or {}),
        components = components,
        formation = deep_copy(spec.formation),
    }
    local by_id = {}
    for _, source in ipairs(sources or {}) do
        M.assert_valid(source)
        for _, rule in ipairs(source.rules) do
            local existing = by_id[rule.id]
            if existing then
                if not deep_equal(existing, rule) then
                    error("composed rule id has conflicting definitions: " .. rule.id)
                end
            else
                local canonical = deep_copy(rule)
                by_id[rule.id] = canonical
                item.rules[#item.rules + 1] = canonical
            end
        end
    end
    return M.assert_valid(item)
end

local function projection_value(rule)
    if rule.magnitude then return rule.magnitude.value end
    return rule.duration and rule.duration.value
end

local function project_rules(item, include)
    M.assert_valid(item)
    local profile = {
        _rule_set_id = item.id,
        _rule_source = item.name,
        _rule_ids = {},
        _cadence = {},
        _duration = {},
        _abilities = deep_copy(item.abilities),
    }
    for _, rule in ipairs(item.rules) do
        if include == nil or include(rule) then
            local stat = rule.operation.stat
            local value = projection_value(rule)
            if rule.operation.mode == "add" then
                profile[stat] = (profile[stat] or 0) + value
            else
                profile[stat] = value
            end
            if is_player_rule(rule) then
                profile._rule_ids[stat] = profile._rule_ids[stat] or {}
                profile._rule_ids[stat][#profile._rule_ids[stat] + 1] = rule.id
            end
            profile._cadence[stat] = deep_copy(rule.cadence)
            if rule.duration then profile._duration[stat] = deep_copy(rule.duration) end
        end
    end
    return profile
end

function M.project(item)
    return project_rules(item)
end

-- Compile a runtime view directly from a selected portion of one canonical
-- RuleSet. This is used when an entity RuleSet contains several shells or
-- effects with overlapping stat names: selection is by canonical rule ID, not
-- by a separately authored profile table.
function M.project_matching(item, include)
    if type(include) ~= "function" then
        error("project_matching needs a rule predicate", 2)
    end
    return project_rules(item, include)
end

function M.project_prefix(item, prefix)
    if type(prefix) ~= "string" or prefix == "" then
        error("project_prefix needs a non-empty canonical rule prefix", 2)
    end
    return project_rules(item, function(rule)
        return rule.id:sub(1, #prefix) == prefix
    end)
end

function M.rule(item, rule_id)
    M.assert_valid(item)
    for _, rule in ipairs(item.rules) do
        if rule.id == rule_id then return deep_copy(rule) end
    end
    return nil
end

function M.rule_value(item, rule_id)
    local rule = M.rule(item, rule_id)
    if not rule then
        error(string.format(
            "canonical RuleSet %s is missing required rule %s",
            tostring(type(item) == "table" and item.id or "?"),
            tostring(rule_id)
        ), 2)
    end
    return deep_copy(projection_value(rule))
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

local function candidate_content_identity(candidate)
    if type(candidate) ~= "table" then
        error("rarity candidate must be a table", 3)
    end
    if candidate.rule_set ~= nil then
        M.assert_valid(candidate.rule_set)
        if candidate.rarity ~= nil and candidate.rarity ~= candidate.rule_set.rarity then
            error("rarity candidate diverges from its canonical RuleSet: "
                .. tostring(candidate.id), 3)
        end
        return candidate.rule_set.id
    end
    local identity = candidate.content_id or candidate.id
    if not nonempty(identity) then
        error("rarity candidate is missing canonical content identity", 3)
    end
    return identity
end

function M.content_identity(candidate)
    return candidate_content_identity(candidate)
end

local function unique_candidates(candidates)
    local unique, by_identity = {}, {}
    for _, candidate in ipairs(candidates or {}) do
        local identity = candidate_content_identity(candidate)
        local existing = by_identity[identity]
        if existing then
            local left_rules, right_rules = existing.rule_set, candidate.rule_set
            if (left_rules or right_rules)
                and (not left_rules or not right_rules or not M.same(left_rules, right_rules)) then
                error("duplicate catalogue identity has conflicting authority: " .. identity, 3)
            end
            if existing.rarity ~= candidate.rarity then
                error("duplicate catalogue identity has conflicting rarity: " .. identity, 3)
            end
        else
            by_identity[identity] = candidate
            unique[#unique + 1] = candidate
        end
    end
    return unique
end

function M.sample_rarity(candidates, acquisition_id, tier_ticket, item_ticket)
    local weights = ECONOMY.acquisition[acquisition_id]
    if not weights then error("unknown acquisition point: " .. tostring(acquisition_id), 2) end
    tier_ticket = math.floor(tonumber(tier_ticket) or 0)
    if tier_ticket < 1 or tier_ticket > 100 then
        error("tier ticket must be an integer from 1 through 100", 2)
    end
    local represented, by_tier, eligible_ids = {}, {}, {}
    for _, candidate in ipairs(unique_candidates(candidates)) do
        if not RARITY_RANK[candidate.rarity] then
            error("rarity candidate is missing canonical rarity: " .. tostring(candidate.id), 2)
        end
        by_tier[candidate.rarity] = by_tier[candidate.rarity] or {}
        by_tier[candidate.rarity][#by_tier[candidate.rarity] + 1] = candidate
        eligible_ids[#eligible_ids + 1] = candidate_content_identity(candidate)
    end
    table.sort(eligible_ids)
    local total = 0
    for _, rarity in ipairs(RARITY_ORDER) do
        if by_tier[rarity] and (weights[rarity] or 0) > 0 then
            represented[rarity] = weights[rarity]
            total = total + weights[rarity]
            table.sort(by_tier[rarity], function(left, right)
                return candidate_content_identity(left) < candidate_content_identity(right)
            end)
        end
    end
    if total == 0 then error("rarity sampler has no represented eligible tier", 2) end
    local point = (tier_ticket - 0.5) * total / 100
    local cumulative, selected_tier = 0
    for _, rarity in ipairs(RARITY_ORDER) do
        cumulative = cumulative + (represented[rarity] or 0)
        if point < cumulative then selected_tier = rarity break end
    end
    selected_tier = selected_tier or RARITY_ORDER[#RARITY_ORDER]
    local tier_items = by_tier[selected_tier]
    local selector = math.floor(tonumber(item_ticket) or tier_ticket)
    local selected = tier_items[((selector - 1) % #tier_items) + 1]
    local normalized = {}
    for _, rarity in ipairs(RARITY_ORDER) do
        normalized[rarity] = represented[rarity]
            and represented[rarity] * 100 / total or 0
    end
    return selected, {
        economy_rule_set_id = ECONOMY.id,
        acquisition = acquisition_id,
        eligible_ids = eligible_ids,
        normalized_tier_weights = normalized,
        tier_ticket = tier_ticket,
        selected_tier = selected_tier,
        selected_id = selected.id,
        selected_content_id = candidate_content_identity(selected),
    }
end

-- Weighted deterministic sampling without replacement. Duplicate catalogue
-- aliases collapse to one canonical content identity. If the eligible pool is
-- smaller than requested, every unique eligible item is returned exactly once
-- and the journal marks the exhaustion instead of duplicating or inventing
-- content.
function M.sample_rarity_without_replacement(
    candidates,
    acquisition_id,
    requested_count,
    tickets
)
    requested_count = math.max(0, math.floor(tonumber(requested_count) or 0))
    local remaining = unique_candidates(candidates)
    local selected, slots = {}, {}
    local count = math.min(requested_count, #remaining)
    for slot = 1, count do
        local ticket = tickets and tickets[slot] or {}
        local tier_ticket = ticket.tier_ticket or (((slot * 37 - 1) % 100) + 1)
        local item_ticket = ticket.item_ticket or (slot * 104729)
        local item, sample = M.sample_rarity(
            remaining,
            acquisition_id,
            tier_ticket,
            item_ticket
        )
        selected[#selected + 1] = item
        sample.slot = slot
        slots[#slots + 1] = sample
        local identity = candidate_content_identity(item)
        for index, candidate in ipairs(remaining) do
            if candidate_content_identity(candidate) == identity then
                table.remove(remaining, index)
                break
            end
        end
    end
    return selected, {
        economy_rule_set_id = ECONOMY.id,
        acquisition = acquisition_id,
        requested_count = requested_count,
        returned_count = #selected,
        unique_pool_size = #selected + #remaining,
        pool_exhausted = #selected < requested_count,
        slots = slots,
    }
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
    elseif verb == "pull" then
        local amount = (rule.magnitude or rule.duration).value
        if type(amount) == "boolean" then
            return amount and ("pull " .. target .. " inward")
                or ("do not pull " .. target .. " inward")
        end
        return "pull " .. target .. " inward with " .. value
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

local function unique_lines(item, include, excluded)
    local lines, counts, order = {}, {}, {}
    for _, rule in ipairs(M.player_rules(item)) do
        if include[rule.visibility] and not (excluded and excluded[rule.id]) then
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

local function linked_cost_copy(item, group)
    local cost = M.rule(item, group.cost_rule_id)
    if not cost then return nil end
    local payoff_copy = {}
    for _, payoff_id in ipairs(group.payoff_rule_ids or {}) do
        local payoff = M.rule(item, payoff_id)
        if not payoff then return nil end
        payoff_copy[#payoff_copy + 1] = operation_copy(payoff)
    end
    local cadence = cost.cadence
    local timing
    if cadence.unit == "exchange" and cadence.interval == 1 then
        timing = "once per exchange"
    elseif cadence.interval > 1 then
        timing = string.format("every %d %s", cadence.interval, cadence.unit)
    else
        timing = "once per " .. cadence.unit
    end
    if cadence.charges then
        timing = string.format(
            "%s, %d charge%s",
            timing,
            cadence.charges,
            cadence.charges == 1 and "" or "s"
        )
    end
    return string.format(
        "COST %d linked allied integrity (%s) → %s.",
        cost.magnitude.value,
        timing,
        table.concat(payoff_copy, " then ")
    )
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
    local lines, excluded = {}, {}
    for _, group in ipairs(M.linked_cost_groups(item)) do
        local line = linked_cost_copy(item, group)
        if line then lines[#lines + 1] = line end
        for _, rule_id in ipairs(ability_rule_ids(group)) do excluded[rule_id] = true end
    end
    for _, line in ipairs(unique_lines(item, { compact = true }, excluded)) do
        lines[#lines + 1] = line
    end
    if item.content_kind == "brick" and item.rarity == "common" then
        table.insert(lines, 1, "NO PASSIVE.")
        if #lines == 1 then
            lines[#lines + 1] = "Role: " .. item.role .. "."
        end
    end
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
    local summary = M.ability_summary(item)
    if item.rarity then
        local tier = ECONOMY.tiers[item.rarity]
        local ceiling = item.content_kind == "brick"
            and tier.brick_passive_groups or tier.bonus_release_groups
        lines[#lines + 1] = string.format(
            "Rarity: %s. Abilities: %d/%d. Complexity: %d MCU.",
            item.rarity,
            summary.count,
            ceiling,
            summary.mcu
        )
        lines[#lines + 1] = string.format(
            "Copy cap: %d. Balance envelope: 100.",
            item.compatibility.max_copies
        )
    end
    local rules = unique_lines(item, { compact = true, expanded = true })
    for _, line in ipairs(rules) do lines[#lines + 1] = line end
    for _, group in ipairs(M.linked_cost_groups(item)) do
        local cost = M.rule(item, group.cost_rule_id)
        local required = #cost.target.required_tags > 0
            and table.concat(cost.target.required_tags, ", ")
            or "any tags"
        local excluded = #cost.target.excluded_tags > 0
            and table.concat(cost.target.excluded_tags, ", ")
            or "none"
        lines[#lines + 1] = string.format(
            "Linked cost %s selects one live orthogonal ally by local row, column, and UID "
                .. "(required tags: %s; excluded tags: %s); %s.",
            group.id,
            required,
            excluded,
            cost.lethal and "lethal payment is allowed" or "payment must leave it alive"
        )
        for payoff_index, payoff_id in ipairs(group.payoff_rule_ids) do
            local payoff = M.rule(item, payoff_id)
            lines[#lines + 1] = string.format(
                "Payoff %d %s scales floor(%d × cost / %d), capped at %d; "
                    .. "causes: %s; generation %d.",
                payoff_index,
                payoff.id,
                payoff.scaling.numerator,
                payoff.scaling.denominator,
                payoff.scaling.cap,
                table.concat(group.recursion.accepts_causes, ", "),
                group.recursion.max_generation
            )
        end
    end
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

-- A serializable snapshot of every player-facing projection controlled by a
-- RuleSet. Consumers copy this value instead of rebuilding parallel notions of
-- identity, language, or accounting.
function M.player_authority(item)
    M.assert_valid(item)
    local summary = M.ability_summary(item)
    local tier = item.rarity and ECONOMY.tiers[item.rarity] or nil
    return {
        schema_version = M.SCHEMA_VERSION,
        rule_set_id = item.id,
        rule_ids = M.player_rule_ids(item),
        rules = M.player_rules(item),
        canonical_rule_set = M.canonical(item),
        rarity_budget = item.rarity_budget,
        compact_copy = M.compact(item),
        compact_lines = M.compact_lines(item),
        inspection_copy = M.expanded_lines(item),
        balance = M.balance(item),
        content_kind = item.content_kind,
        rarity = item.rarity,
        availability = deep_copy(item.availability),
        abilities = deep_copy(item.abilities),
        ability_summary = summary,
        telegraph = tier and {
            rarity = item.rarity,
            beads = tier.rank,
            shell_cap = tier.shell_cap,
            passive_count = summary.count,
            passive_ceiling = item.content_kind == "brick"
                and tier.brick_passive_groups or tier.bonus_release_groups,
            mcu = summary.mcu,
            mcu_ceiling = item.content_kind == "brick"
                and tier.brick_passive_mcu or tier.bonus_release_mcu,
            copy_cap = item.compatibility.max_copies,
            balance_budget = 100,
        } or nil,
    }
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

function M.same(left, right)
    if not left or not right then return false end
    local left_valid, left_canonical = pcall(M.canonical, left)
    local right_valid, right_canonical = pcall(M.canonical, right)
    return left_valid and right_valid and left_canonical == right_canonical
end

-- A compatibility projection may cross a boundary only when any RuleSet it
-- claims to represent is byte-identical to the structured authority being
-- compiled. Scalar checks in each content module then catch stale projected
-- fields without making those fields authoritative.
function M.assert_runtime_source(kind, id, source_rule_set, shadow)
    M.assert_valid(source_rule_set)
    if shadow and shadow.rule_set
        and not M.same(source_rule_set, shadow.rule_set) then
        error(string.format(
            "%s %s compiled RuleSet diverges from canonical RuleSet",
            tostring(kind),
            tostring(id)
        ), 2)
    end
    return source_rule_set
end

function M.register(item)
    M.assert_valid(item)
    local ability_by_rule = {}
    for _, group in ipairs(item.abilities or {}) do
        for _, rule_id in ipairs(ability_rule_ids(group)) do
            ability_by_rule[rule_id] = group.id
        end
    end
    for _, rule in ipairs(item.rules) do
        local existing = registry[rule.id]
        if existing then
            if not deep_equal(existing.rule, rule) then
                error("rule id conflicts with " .. existing.rule_set_id .. ": " .. rule.id)
            end
            local known = false
            for _, rule_set_id in ipairs(existing.rule_set_ids) do
                if rule_set_id == item.id then known = true break end
            end
            if not known then
                existing.rule_set_ids[#existing.rule_set_ids + 1] = item.id
            end
            if ability_by_rule[rule.id] then
                if existing.ability_id
                    and existing.ability_id ~= ability_by_rule[rule.id] then
                    error("rule id belongs to conflicting ability groups: " .. rule.id)
                end
                existing.ability_id = ability_by_rule[rule.id]
            end
        else
            registry[rule.id] = {
                rule_set_id = item.id,
                rule_set_ids = { item.id },
                source_name = item.name,
                role = item.role,
                rule = deep_copy(rule),
                ability_id = ability_by_rule[rule.id],
            }
        end
    end
    return item
end

function M.resolve(rule_id)
    local entry = registry[rule_id]
    return entry and deep_copy(entry) or nil
end

function M.belongs_to(rule_id, rule_set_id)
    local entry = registry[rule_id]
    if not entry then return false end
    for _, candidate in ipairs(entry.rule_set_ids) do
        if candidate == rule_set_id then return true end
    end
    return false
end

local function rule_id_for(source, stat)
    if not source then return nil end
    if source._rule_ids and source._rule_ids[stat] then
        for _, rule_id in ipairs(source._rule_ids[stat]) do
            local entry = registry[rule_id]
            if not entry or is_player_rule(entry.rule) then return rule_id end
        end
    end
    for _, rule in ipairs(source.rules or {}) do
        if is_player_rule(rule) and rule.operation.stat == stat then return rule.id end
    end
    return nil
end

local function attribute_entry(fields, rule_id, entry, source, overrides)
    local rule = entry and entry.rule
    if not rule or not is_player_rule(rule) then return fields end
    fields.rule_id = fields.rule_id or rule_id
    fields.rule_source = fields.rule_source
        or (overrides and overrides.source_name)
        or entry.source_name
        or (source and source._rule_source)
    fields.rule_role = fields.rule_role or entry.role
    fields.rule_operation = fields.rule_operation or rule.operation.verb
    fields.rule_target = fields.rule_target or rule.target.selector
    fields.source_rule_set_id = fields.source_rule_set_id
        or (source and source._rule_set_id)
        or entry.rule_set_id
    fields.ability_id = fields.ability_id or entry.ability_id
    fields.operation = fields.operation or rule.operation.verb
    fields.target_selector = fields.target_selector or rule.target.selector
    if rule and rule.magnitude then
        fields.rule_magnitude = fields.rule_magnitude or rule.magnitude.value
        fields.rule_unit = fields.rule_unit or rule.magnitude.unit
    elseif rule and rule.duration then
        fields.rule_magnitude = fields.rule_magnitude or rule.duration.value
        fields.rule_unit = fields.rule_unit or rule.duration.unit
    end
    return fields
end

function M.attribute(fields, source, stat, overrides)
    fields = fields or {}
    local rule_id = rule_id_for(source, stat)
    if not rule_id then return fields end
    return attribute_entry(fields, rule_id, registry[rule_id], source, overrides)
end

-- Events created by a central mutation boundary often arrive with a canonical
-- rule ID instead of a projected profile. Enrich them from the same registry;
-- callers may supply entity-specific source identity without it being
-- overwritten by the component RuleSet that first registered the node.
function M.attribute_rule_id(fields, rule_id, overrides)
    fields = fields or {}
    if type(rule_id) ~= "string" then return fields end
    return attribute_entry(fields, rule_id, registry[rule_id], nil, overrides)
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
