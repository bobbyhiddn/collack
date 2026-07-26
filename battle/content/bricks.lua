-- battle/content/bricks.lua — hardcoded brick archetypes.
--
-- Bricks are static formation elements with BEHAVIOUR, not just hit points.
-- The sixteen documented behaviours are grouped into defensive, effect,
-- utility and rare families. Their mechanics live in battle/effects.lua's
-- shared vocabulary; these records are content, not copied rule handlers.
--
-- hp is an integer pool; see ADR 0004 for why pools rather than binary
-- destruction. A binary brick is just hp = 1, so nothing is lost.

local BRICKS = {
    {
        id = "plain_block",
        name = "Plain Block",
        behaviour = "inert",
        hp = 2,
    },
    {
        id = "chalk_block",
        name = "Chalk Block",
        behaviour = "inert",
        hp = 1,
    },
    {
        id = "basalt_absorber",
        name = "Basalt Absorber",
        family = "defensive",
        behaviour = "absorb",
        hp = 3,
    },
    {
        id = "mirror_pane",
        name = "Mirror Pane",
        family = "defensive",
        behaviour = "reflect",
        hp = 2,
    },
    {
        id = "moss_regenerator",
        name = "Moss Regenerator",
        family = "defensive",
        behaviour = "regenerate",
        hp = 3,
    },
    {
        id = "granite_fortifier",
        name = "Granite Fortifier",
        family = "defensive",
        behaviour = "fortify",
        hp = 3,
    },
    {
        id = "venom_glass",
        name = "Venom Glass",
        family = "effect",
        behaviour = "poison",
        hp = 2,
    },
    {
        id = "rime_block",
        name = "Rime Block",
        family = "effect",
        behaviour = "freeze",
        hp = 2,
    },
    {
        id = "lodestone_block",
        name = "Lodestone Block",
        family = "effect",
        behaviour = "magnetic",
        hp = 2,
    },
    {
        id = "shatter_crystal",
        name = "Shatter Crystal",
        family = "effect",
        behaviour = "shatter",
        hp = 2,
    },
    {
        id = "powder_keg",
        name = "Powder Keg",
        family = "utility",
        behaviour = "chain",
        hp = 1,
    },
    {
        id = "vault_arch",
        name = "Vault Arch",
        family = "utility",
        behaviour = "vault",
        hp = 2,
    },
    {
        id = "splice_node",
        name = "Splice Node",
        family = "utility",
        behaviour = "splice",
        hp = 2,
    },
    {
        id = "training_dummy",
        name = "Training Dummy",
        family = "utility",
        behaviour = "dummy",
        hp = 1,
    },
    {
        id = "aegis_keystone",
        name = "Aegis Keystone",
        family = "rare",
        behaviour = "aegis",
        hp = 3,
    },
    {
        id = "void_prism",
        name = "Void Prism",
        family = "rare",
        behaviour = "void",
        hp = 2,
    },
    {
        id = "prismatic_mirror",
        name = "Prismatic Mirror",
        family = "rare",
        behaviour = "mirror",
        hp = 3,
    },
    {
        id = "temporal_anchor",
        name = "Temporal Anchor",
        family = "rare",
        behaviour = "temporal",
        hp = 3,
    },
}

local by_id = {}
for _, brick in ipairs(BRICKS) do
    by_id[brick.id] = brick
end

return {
    list = BRICKS,
    by_id = by_id,
}
