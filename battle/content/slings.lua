-- Sling identities projected from the canonical executable rule grammar.

local ast = require("battle.rule_ast")
local rulebook = require("battle.content.rules")

local ORDER = {
    "training_sling",
    "tuned_sling",
    "heavy_sling",
    "raker_sling",
    "volley",
    "momentum",
    "ricochet",
    "spread",
    "precision",
    "effect_amplifier",
}

local SLINGS = {}
local by_id = {}

local RUNTIME_FIELDS = {
    "shots_per_volley",
    "damage_bonus",
    "durability_bonus",
    "momentum_bonus",
    "aim",
    "scatter",
    "ricochet",
    "precision",
    "effect_power",
}

local function compile(id, rule_set)
    local profile = ast.project(rule_set)
    return {
        id = id,
        name = rule_set.name,
        archetype = id,
        shots_per_volley = profile.shots_per_volley or 1,
        damage_bonus = profile.damage_bonus or 0,
        durability_bonus = profile.durability_bonus or 0,
        momentum_bonus = profile.momentum_bonus or 0,
        aim = profile.aim or 0,
        scatter = profile.scatter or 0,
        ricochet = profile.ricochet == true,
        precision = profile.precision == true,
        effect_power = profile.effect_power or 0,
        rule_set = ast.copy(rule_set),
        compact_copy = ast.compact(rule_set),
        inspection_copy = ast.expanded_lines(rule_set),
        balance = ast.balance(rule_set),
        _rule_set_id = profile._rule_set_id,
        _rule_source = profile._rule_source,
        _rule_ids = ast.copy(profile._rule_ids),
        _cadence = ast.copy(profile._cadence),
    }
end

local function runtime(id, rule_set, shadow)
    rule_set = rule_set or rulebook.slings[id]
    if not rule_set then error("unknown sling: " .. tostring(id)) end
    if rule_set.id ~= "sling." .. tostring(id) then
        error(string.format(
            "sling %s RuleSet identity diverges: %s",
            tostring(id),
            tostring(rule_set.id)
        ))
    end
    ast.assert_runtime_source("sling", id, rule_set, shadow)
    local canonical = compile(id, rule_set)
    for _, field in ipairs(RUNTIME_FIELDS) do
        if shadow and shadow[field] ~= nil and shadow[field] ~= canonical[field] then
            error(string.format(
                "sling %s compiled %s diverges from canonical RuleSet",
                tostring(id),
                field
            ))
        end
    end
    return canonical
end

local function canonical_rule_set(id)
    local rule_set = rulebook.slings[id]
    if not rule_set then error("unknown sling: " .. tostring(id)) end
    return ast.copy(rule_set)
end

local function has(id)
    return rulebook.slings[id] ~= nil
end

for _, id in ipairs(ORDER) do
    local rule_set = rulebook.slings[id]
    local sling = compile(id, rule_set)
    SLINGS[#SLINGS + 1] = sling
    by_id[id] = sling
end

return {
    list = SLINGS,
    by_id = by_id,
    runtime = runtime,
    canonical_rule_set = canonical_rule_set,
    has = has,
}
