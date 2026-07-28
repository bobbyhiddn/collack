-- battle/tests/fixtures.lua — hand-built setups for the constructed scenarios.
--
-- The tests that check a specific mechanic use these rather than the demo
-- matchup, so each one exercises exactly one thing with no randomness in the
-- way. Tests use canonical sling RuleSets instead of hand-authored stat tables.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local F = {}

-- Constructed continuous-engine matchups live under battle/tests so product
-- archives never ship a fixed matchup or bypass the draft/setup handoff.
local layouts = {
    wedge = {
        { "training_dummy", "plain_block", "basalt_absorber", "aegis_keystone", "basalt_absorber", "plain_block", "training_dummy" },
        { ".", "granite_fortifier", "venom_glass", "temporal_anchor", "shatter_crystal", "granite_fortifier", "." },
        { ".", ".", "prismatic_mirror", "powder_keg", "splice_node", ".", "." },
    },
    bastion = {
        { "mirror_pane", "chalk_block", "rime_block", "moss_regenerator", "lodestone_block", "chalk_block", "mirror_pane" },
        { "granite_fortifier", ".", "void_prism", "vault_arch", "void_prism", ".", "granite_fortifier" },
        { ".", "splice_node", "aegis_keystone", "plain_block", "aegis_keystone", "powder_keg", "." },
    },
}

local marble_defs = {
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
        core = "concussion_pearl",
        shells = { "silver_veined", "granite_mottled", "jade_lattice" },
    },
    lodestone_epic = {
        name = "Lodestone", rarity = "epic",
        core = "lodestone_heart",
        shells = { "flint_spiral", "quartz_banded", "jade_lattice", "chalk_plain" },
    },
}

local function hand(...)
    local out = {}
    for _, key in ipairs({ ... }) do
        local def = assert(marble_defs[key], "unknown test marble: " .. tostring(key))
        local copy = {
            name = def.name,
            rarity = def.rarity,
            core = def.core,
            shells = {},
        }
        for index, shell in ipairs(def.shells) do copy.shells[index] = shell end
        out[#out + 1] = copy
    end
    return out
end

function F.default_matchup()
    return {
        A = {
            name = "Fen",
            sling = "ricochet",
            formation = layouts.wedge,
            marbles = hand("warden_rare", "geode_uncommon", "quartz_common", "chalk_common"),
        },
        B = {
            name = "Bram",
            sling = "effect_amplifier",
            formation = layouts.bastion,
            marbles = hand("lodestone_epic", "drifter_common", "geode_uncommon", "chalk_common"),
        },
    }
end

--- One shell, one durability: breaks on its first collision, which exposes the
--- core and fires blowback. The workhorse of the blowback tests.
function F.fragile(lane)
    return {
        name = "Fragile", rarity = "common",
        core = "dull_quartz", shells = { "chalk_plain" }, lane = lane,
    }
end

--- Three thick shells, survives a long time.
function F.sturdy(lane)
    return {
        name = "Sturdy", rarity = "rare",
        core = "dull_quartz",
        shells = { "granite_mottled", "quartz_banded", "jade_lattice" },
        lane = lane,
    }
end

--- Deals 2 damage on its first collision: kills a 1 hp brick outright.
function F.cleaver(lane)
    return {
        name = "Cleaver", rarity = "uncommon",
        core = "dull_quartz", shells = { "obsidian_shard", "jade_lattice" }, lane = lane,
    }
end

--- A row of absorbers: nothing in these tests can chew through it by accident,
--- so a formation built from it is guaranteed to survive the volley.
function F.tough_wall(cols)
    local row = {}
    for col = 1, cols do row[col] = "basalt_absorber" end
    return { row }
end

--- A single 1 hp brick in the given column, padded to `cols` wide.
function F.single_brick(cols, col, brick_id)
    local row = {}
    for index = 1, cols do row[index] = "." end
    row[col] = brick_id or "chalk_block"
    return { row }
end

return F
