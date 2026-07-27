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

for _, spec in ipairs(SPECS) do
    local rule_set = rulebook.bricks[spec.id]
    local profile = ast.project(rule_set)
    local brick = {
        id = spec.id,
        name = spec.name,
        family = spec.family,
        behaviour = profile.behaviour,
        hp = profile.hp,
        rule_set = ast.copy(rule_set),
        compact_copy = ast.compact(rule_set, 1),
        inspection_copy = ast.expanded_lines(rule_set),
        balance = ast.balance(rule_set),
    }
    BRICKS[#BRICKS + 1] = brick
    by_id[brick.id] = brick
end

return {
    list = BRICKS,
    by_id = by_id,
}
