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

for _, id in ipairs(ORDER) do
    local rule_set = rulebook.slings[id]
    local profile = ast.project(rule_set)
    local sling = {
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
    }
    SLINGS[#SLINGS + 1] = sling
    by_id[id] = sling
end

return {
    list = SLINGS,
    by_id = by_id,
}
