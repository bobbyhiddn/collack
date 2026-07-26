-- battle/setup.lua — hardcoded starting setups.
--
-- Content generation is explicitly out of scope for this slice, so the marble,
-- brick and sling sets are written out by hand here. When a generator exists it
-- replaces this file and nothing else.

local M = {}

-- Formation layouts. "." is an empty cell. Row 1 is the front row, the one an
-- incoming marble meets first. Both formations must be the same width.
M.LAYOUTS = {
    -- A conventional wedge: soft front, absorbers in the middle, kegs tucked
    -- where a chain reaction can take the whole middle out.
    wedge = {
        { "training_dummy", "plain_block", "basalt_absorber", "aegis_keystone", "basalt_absorber", "plain_block", "training_dummy" },
        { ".", "granite_fortifier", "venom_glass", "temporal_anchor", "shatter_crystal", "granite_fortifier", "." },
        { ".", ".", "prismatic_mirror", "powder_keg", "splice_node", ".", "." },
    },
    -- Mirrors on the outside, so wide shots get thrown back out.
    bastion = {
        { "mirror_pane", "chalk_block", "rime_block", "moss_regenerator", "lodestone_block", "chalk_block", "mirror_pane" },
        { "granite_fortifier", ".", "void_prism", "vault_arch", "void_prism", ".", "granite_fortifier" },
        { ".", "splice_node", "aegis_keystone", "plain_block", "aegis_keystone", "powder_keg", "." },
    },
    -- Ten deliberately positioned quality bricks. Fortifiers shield the rare
    -- anchors beside them while the two void prisms punish repeated attacks.
    quality_ten = {
        { "aegis_keystone", ".", "temporal_anchor", ".", ".", ".", ".", "temporal_anchor", ".", "aegis_keystone" },
        { "granite_fortifier", "void_prism", "granite_fortifier", ".", ".", ".", ".", "granite_fortifier", "void_prism", "granite_fortifier" },
        { ".", ".", ".", ".", ".", ".", ".", ".", ".", "." },
    },
    weak_thirty = {
        { "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block" },
        { "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block" },
        { "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block", "chalk_block" },
    },
}

M.MARBLES = {
    chalk_common = {
        name = "Chalk Pebble", rarity = "common",
        core = "dull_quartz", shells = { "chalk_plain" },
    },
    quartz_common = {
        name = "Quartz Round", rarity = "common",
        core = "skew_flint", shells = { "quartz_banded" },
    },
    drifter_common = {
        name = "Drifter", rarity = "common",
        core = "cant_pebble", shells = { "jade_lattice" },
    },
    geode_uncommon = {
        name = "Split Geode", rarity = "uncommon",
        core = "shrapnel_geode", shells = { "obsidian_shard", "jade_lattice" },
    },
    warden_rare = {
        name = "Warden", rarity = "rare",
        core = "concussion_pearl", shells = { "silver_veined", "granite_mottled", "jade_lattice" },
    },
    lodestone_epic = {
        name = "Lodestone", rarity = "epic",
        core = "lodestone_heart", shells = { "flint_spiral", "quartz_banded", "jade_lattice", "chalk_plain" },
    },
    cinder_legendary = {
        name = "Cinder", rarity = "legendary",
        core = "cinder_nucleus",
        shells = { "obsidian_shard", "flint_spiral", "granite_mottled", "quartz_banded", "jade_lattice" },
    },
}

local function hand(...)
    local out = {}
    for _, key in ipairs({ ... }) do
        local def = M.MARBLES[key]
        if not def then error("unknown marble key: " .. tostring(key)) end
        -- Copy, because the engine stamps per-battle state onto what it builds
        -- from and shared tables would leak between battles.
        local copy = { name = def.name, rarity = def.rarity, core = def.core, shells = {} }
        for index, shell in ipairs(def.shells) do copy.shells[index] = shell end
        out[#out + 1] = copy
    end
    return out
end

M.hand = hand

--- The default demo matchup: two distinct but comparable loadouts.
function M.default_matchup()
    return {
        A = {
            name = "Fen",
            sling = "ricochet",
            formation = M.LAYOUTS.wedge,
            marbles = hand("warden_rare", "geode_uncommon", "quartz_common", "chalk_common"),
        },
        B = {
            name = "Bram",
            sling = "effect_amplifier",
            formation = M.LAYOUTS.bastion,
            marbles = hand("lodestone_epic", "drifter_common", "geode_uncommon", "chalk_common"),
        },
    }
end

--- Constructed quality-versus-quantity proof. Both players receive the same
--- ordered legendary hand and precision sling, leaving brick choice and
--- placement as the only asymmetric inputs.
function M.quality_vs_quantity()
    return {
        A = {
            name = "Tenfold",
            sling = "precision",
            formation = M.LAYOUTS.quality_ten,
            marbles = hand("cinder_legendary", "cinder_legendary", "cinder_legendary",
                "cinder_legendary", "cinder_legendary"),
        },
        B = {
            name = "Thirty Chalk",
            sling = "precision",
            formation = M.LAYOUTS.weak_thirty,
            marbles = hand("cinder_legendary", "cinder_legendary", "cinder_legendary",
                "cinder_legendary", "cinder_legendary"),
        },
    }
end

return M
