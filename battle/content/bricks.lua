-- Brick appearance/family metadata projected onto canonical behaviour rules.

local ast = require("battle.rule_ast")
local rulebook = require("battle.content.rules")

local SPECS = {
    { id = "plain_block", name = "Plain Block" },
    { id = "chalk_block", name = "Chalk Block" },
    { id = "basalt_absorber", name = "Basalt Absorber", family = "defensive" },
    { id = "mirror_pane", name = "Mirror Pane", family = "defensive" },
    { id = "moss_regenerator", name = "Moss Regenerator", family = "defensive" },
    { id = "granite_fortifier", name = "Granite Fortifier", family = "defensive" },
    { id = "venom_glass", name = "Venom Glass", family = "effect" },
    { id = "rime_block", name = "Rime Block", family = "effect" },
    { id = "lodestone_block", name = "Lodestone Block", family = "effect" },
    { id = "shatter_crystal", name = "Shatter Crystal", family = "effect" },
    { id = "powder_keg", name = "Powder Keg", family = "utility" },
    { id = "vault_arch", name = "Vault Arch", family = "utility" },
    { id = "splice_node", name = "Splice Node", family = "utility" },
    { id = "training_dummy", name = "Training Dummy", family = "utility" },
    { id = "aegis_keystone", name = "Aegis Keystone", family = "rare" },
    { id = "void_prism", name = "Void Prism", family = "rare" },
    { id = "prismatic_mirror", name = "Prismatic Mirror", family = "rare" },
    { id = "temporal_anchor", name = "Temporal Anchor", family = "rare" },
}

local BRICKS = {}
local by_id = {}
local spec_by_id = {}
for _, spec in ipairs(SPECS) do spec_by_id[spec.id] = spec end

local function compile(spec, rule_set)
    local authority = ast.player_authority(rule_set)
    return {
        id = spec.id,
        name = spec.name,
        family = spec.family,
        behaviour = ast.rule_value(rule_set, "brick." .. spec.id .. ".behaviour"),
        hp = ast.rule_value(rule_set, "brick." .. spec.id .. ".hp"),
        restitution = ast.rule_value(rule_set, "brick." .. spec.id .. ".restitution"),
        rarity = rule_set.rarity,
        availability = ast.copy(rule_set.availability),
        abilities = ast.copy(rule_set.abilities),
        telegraph = ast.copy(authority.telegraph),
        rule_set = ast.copy(rule_set),
        compact_copy = authority.compact_copy,
        inspection_copy = ast.copy(authority.inspection_copy),
        balance = ast.copy(authority.balance),
    }
end

local function runtime(id, rule_set, shadow)
    local spec = spec_by_id[id]
    if not spec then error("unknown brick: " .. tostring(id)) end
    rule_set = rule_set or rulebook.bricks[id]
    ast.assert_runtime_source("brick", id, rule_set, shadow)
    local canonical = compile(spec, rule_set)
    for _, field in ipairs({ "behaviour", "hp", "restitution", "rarity" }) do
        if shadow and shadow[field] ~= nil and shadow[field] ~= canonical[field] then
            error(string.format(
                "brick %s compiled %s diverges from canonical RuleSet",
                tostring(id),
                field
            ))
        end
    end
    if shadow and shadow.max_hp ~= nil and shadow.max_hp ~= canonical.hp then
        error(string.format(
            "brick %s compiled max_hp diverges from canonical RuleSet",
            tostring(id)
        ))
    end
    return canonical
end

local function canonical_rule_set(id)
    local rule_set = rulebook.bricks[id]
    if not rule_set then error("unknown brick: " .. tostring(id)) end
    return ast.copy(rule_set)
end

local function has(id)
    return spec_by_id[id] ~= nil and rulebook.bricks[id] ~= nil
end

for _, spec in ipairs(SPECS) do
    local rule_set = rulebook.bricks[spec.id]
    local brick = compile(spec, rule_set)
    BRICKS[#BRICKS + 1] = brick
    by_id[brick.id] = brick
end

return {
    list = BRICKS,
    by_id = by_id,
    runtime = runtime,
    canonical_rule_set = canonical_rule_set,
    has = has,
}
