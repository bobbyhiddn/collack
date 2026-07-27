-- Comprehension-first draft catalog.
--
-- Mechanical copy is generated from each canonical RuleSet.  The only
-- presentation-authored strings here are names, art identity, tag glossary,
-- and positional advice; none can change simulation meaning.

local ast = require("battle.rule_ast")
local slings = require("battle.content.slings")
local cores = require("battle.content.cores")
local shells = require("battle.content.shells")
local bricks = require("battle.content.bricks")

local M = {}

M.VERSION = "grammar-content-1"

M.TAGS = {
    force = { label = "Force", description = "Raises launch impulse or penetration." },
    rebound = { label = "Rebound", description = "Creates valuable second angles." },
    field = { label = "Fields", description = "Uses persistent zones or release areas." },
    release = { label = "Core Release", description = "Acts when the final shell breaks." },
    durable = { label = "Durable", description = "Stays relevant through repeated impacts." },
    tempo = { label = "Tempo", description = "Produces useful early pressure." },
    angle = { label = "Angles", description = "Changes approach lines." },
    chain = { label = "Chain", description = "Links contact or destruction effects." },
    guard = { label = "Guard", description = "Protects a brick or formation lane." },
    sustain = { label = "Sustain", description = "Recovers or prevents damage." },
    control = { label = "Control", description = "Pulls, slows, strips, or redirects." },
    depth = { label = "Protected Depth", description = "Rewards protected rear positions." },
    burst = { label = "Burst", description = "Creates a decisive damage window." },
    absorption = { label = "Absorption", description = "Turns impact into protection." },
    mirror_lane = { label = "Mirror Lane", description = "Builds around deliberate rebounds." },
    renewal = { label = "Renewal", description = "Combines recovery and prevention." },
    status_lock = { label = "Status Lock", description = "Layers fixed-step statuses." },
    gravity_well = { label = "Gravity Well", description = "Pulls a target into follow-up effects." },
    detonation = { label = "Detonation", description = "Turns destruction into nearby damage." },
    damage_link = { label = "Damage Link", description = "Routes contact damage through adjacency." },
    deep_reserve = { label = "Deep Reserve", description = "Protects a late formation piece." },
}

local function decorate(spec, rule_set)
    ast.assert_valid(rule_set)
    local item = {
        id = spec.id,
        name = spec.name or rule_set.name,
        role = rule_set.role,
        rarity = spec.rarity,
        draft_value = spec.draft_value,
        tags = ast.copy(rule_set.synergy_tags),
        counter_tags = ast.copy(spec.counter_tags or {}),
        art_id = spec.art_id,
        suggested_placement = spec.suggested_placement,
        rule_set = ast.copy(rule_set),
        compact_copy = ast.compact(rule_set),
        inspection_copy = ast.expanded_lines(rule_set),
        mechanics = ast.compact_lines(rule_set),
        compatibility = ast.copy(rule_set.compatibility),
        balance = ast.balance(rule_set),
    }
    return item
end

local SLING_SPECS = {
    {
        id = "momentum",
        draft_value = 100,
        counter_tags = { "guard", "depth" },
        art_id = "sling_momentum",
    },
    {
        id = "ricochet",
        draft_value = 100,
        counter_tags = { "depth", "burst" },
        art_id = "sling_ricochet",
    },
    {
        id = "effect_amplifier",
        draft_value = 100,
        counter_tags = { "sustain", "control" },
        art_id = "sling_effect_amplifier",
    },
}

M.SLINGS = {}
for _, spec in ipairs(SLING_SPECS) do
    M.SLINGS[#M.SLINGS + 1] = decorate(spec, slings.by_id[spec.id].rule_set)
end

local MARBLE_SPECS = {
    {
        id = "chalk_common", name = "Chalk Pebble", role = "opener", rarity = "common",
        core = "dull_quartz", shell_ids = { "chalk_plain" }, draft_value = 98,
        tags = { "tempo", "release" }, counter_tags = { "depth" },
        art_id = "marble_chalk_common", in_pool = true,
    },
    {
        id = "quartz_common", name = "Quartz Round", role = "survivor", rarity = "common",
        core = "skew_flint", shell_ids = { "quartz_banded" }, draft_value = 102,
        tags = { "durable", "angle" }, counter_tags = { "burst" },
        art_id = "marble_quartz_common", in_pool = true,
    },
    {
        id = "drifter_common", name = "Drifter", role = "control", rarity = "common",
        core = "cant_pebble", shell_ids = { "jade_lattice" }, draft_value = 99,
        tags = { "angle", "control" }, counter_tags = { "rebound" },
        art_id = "marble_drifter_common",
    },
    {
        id = "flint_hook_common", name = "Flint Hook", role = "breaker", rarity = "common",
        core = "skew_flint", shell_ids = { "flint_spiral" }, draft_value = 101,
        tags = { "burst", "angle" }, counter_tags = { "guard" },
        art_id = "marble_flint_hook",
    },
    {
        id = "geode_uncommon", name = "Split Geode", role = "fuse", rarity = "uncommon",
        core = "shrapnel_geode", shell_ids = { "obsidian_shard", "jade_lattice" },
        draft_value = 101, tags = { "chain", "release" }, counter_tags = { "sustain" },
        art_id = "marble_geode_uncommon", in_pool = true,
    },
    {
        id = "silver_seed_uncommon", name = "Silver Seed", role = "control", rarity = "uncommon",
        core = "shrapnel_geode", shell_ids = { "silver_veined", "chalk_plain" },
        draft_value = 100, tags = { "guard", "release" }, counter_tags = { "chain" },
        art_id = "marble_silver_seed",
    },
    {
        id = "banded_guard_uncommon", name = "Banded Guard", role = "survivor",
        rarity = "uncommon", core = "dull_quartz",
        shell_ids = { "quartz_banded", "jade_lattice" }, draft_value = 102,
        tags = { "durable", "guard" }, counter_tags = { "tempo" },
        art_id = "marble_banded_guard",
    },
    {
        id = "warden_rare", name = "Warden", role = "survivor", rarity = "rare",
        core = "concussion_pearl",
        shell_ids = { "silver_veined", "granite_mottled", "jade_lattice" },
        draft_value = 102, tags = { "durable", "control" }, counter_tags = { "burst" },
        art_id = "marble_warden_rare", in_pool = true,
    },
    {
        id = "shard_ram_rare", name = "Shard Ram", role = "breaker", rarity = "rare",
        core = "shrapnel_geode",
        shell_ids = { "granite_mottled", "obsidian_shard", "flint_spiral" },
        draft_value = 101, tags = { "force", "burst" }, counter_tags = { "guard" },
        art_id = "marble_shard_ram",
    },
    {
        id = "lodestone_epic", name = "Lodestone", role = "control", rarity = "epic",
        core = "lodestone_heart",
        shell_ids = { "flint_spiral", "quartz_banded", "jade_lattice", "chalk_plain" },
        draft_value = 100, tags = { "control", "field" }, counter_tags = { "sustain" },
        art_id = "marble_lodestone_epic", in_pool = true,
    },
    {
        id = "magnet_needle_epic", name = "Magnet Needle", role = "finisher", rarity = "epic",
        core = "lodestone_heart",
        shell_ids = { "silver_veined", "obsidian_shard", "flint_spiral", "chalk_plain" },
        draft_value = 99, tags = { "release", "control" }, counter_tags = { "depth" },
        art_id = "marble_magnet_needle",
    },
    {
        id = "cinder_legendary", name = "Cinder", role = "finisher", rarity = "legendary",
        core = "cinder_nucleus",
        shell_ids = {
            "obsidian_shard", "flint_spiral", "granite_mottled",
            "quartz_banded", "jade_lattice",
        },
        draft_value = 102, tags = { "burst", "field" }, counter_tags = { "sustain" },
        art_id = "marble_cinder_legendary", in_pool = true,
    },
}

M.MARBLES = {}
M.LEGACY_MARBLES = {}
M.ALL_MARBLES = {}

for _, spec in ipairs(MARBLE_SPECS) do
    local sources = { cores.by_id[spec.core].rule_set }
    for _, shell_id in ipairs(spec.shell_ids) do
        sources[#sources + 1] = shells.by_id[shell_id].rule_set
    end
    local rule_set = ast.compose({
        id = "card.marble." .. spec.id,
        name = spec.name,
        role = spec.role,
        synergy_tags = spec.tags,
        rarity_budget = spec.draft_value,
        drawback = cores.by_id[spec.core].rule_set.drawback,
    }, sources)
    local item = decorate(spec, rule_set)
    item.core = spec.core
    item.shells = ast.copy(spec.shell_ids)
    M.ALL_MARBLES[#M.ALL_MARBLES + 1] = item
    if spec.in_pool then
        M.MARBLES[#M.MARBLES + 1] = item
    else
        M.LEGACY_MARBLES[#M.LEGACY_MARBLES + 1] = item
    end
end

local KIT_SPECS = {
    {
        id = "guard_pair", name = "Basalt Escort", role = "adjacent protection",
        brick_ids = { "basalt_absorber", "granite_fortifier" }, draft_value = 101,
        tags = { "guard", "durable", "absorption" }, counter_tags = { "force" },
        suggested_placement = "Place side by side; the fortifier shelters the absorber.",
        art_id = "kit_guard_pair",
    },
    {
        id = "mirror_anchor", name = "Anchored Mirror", role = "rebound lane",
        brick_ids = { "mirror_pane", "temporal_anchor" }, draft_value = 100,
        tags = { "rebound", "depth", "mirror_lane" }, counter_tags = { "angle" },
        suggested_placement = "Set the mirror forward with the anchor one row behind.",
        art_id = "kit_mirror_anchor",
    },
    {
        id = "living_aegis", name = "Living Aegis", role = "sustain",
        brick_ids = { "moss_regenerator", "aegis_keystone" }, draft_value = 102,
        tags = { "sustain", "guard", "renewal" }, counter_tags = { "burst" },
        suggested_placement = "Keep the regenerator adjacent to the keystone.",
        art_id = "kit_living_aegis",
    },
    {
        id = "venom_rime", name = "Cold Venom", role = "control field",
        brick_ids = { "venom_glass", "rime_block" }, draft_value = 99,
        tags = { "control", "field", "status_lock" }, counter_tags = { "durable" },
        suggested_placement = "Split them across approach lanes to layer statuses.",
        art_id = "kit_venom_rime",
    },
    {
        id = "lodestone_void", name = "Null Orbit", role = "cluster then strip",
        brick_ids = { "lodestone_block", "void_prism" }, draft_value = 101,
        tags = { "control", "field", "gravity_well" }, counter_tags = { "rebound" },
        suggested_placement = "Offset the prism behind the magnetic approach lane.",
        art_id = "kit_lodestone_void",
    },
    {
        id = "shatter_keg", name = "Fault Line", role = "burst chain",
        brick_ids = { "shatter_crystal", "powder_keg" }, draft_value = 98,
        tags = { "burst", "chain", "detonation" }, counter_tags = { "sustain" },
        suggested_placement = "Place adjacent where one break can reach the other.",
        art_id = "kit_shatter_keg",
    },
    {
        id = "splice_keg", name = "Spliced Fuse", role = "adjacency damage",
        brick_ids = { "splice_node", "powder_keg" }, draft_value = 100,
        tags = { "chain", "burst", "damage_link" }, counter_tags = { "guard" },
        suggested_placement = "Join the node directly to the keg and another kit.",
        art_id = "kit_splice_keg",
    },
    {
        id = "vault_temporal", name = "Deep Reserve", role = "protected depth",
        brick_ids = { "vault_arch", "temporal_anchor" }, draft_value = 102,
        tags = { "depth", "sustain", "deep_reserve" }, counter_tags = { "tempo" },
        suggested_placement = "Place the vault in front of the deeper anchor.",
        art_id = "kit_vault_temporal",
    },
}

M.BRICK_KITS = {}
for _, spec in ipairs(KIT_SPECS) do
    local sources = {}
    for _, brick_id in ipairs(spec.brick_ids) do
        sources[#sources + 1] = bricks.by_id[brick_id].rule_set
    end
    local rule_set = ast.compose({
        id = "card.brick_kit." .. spec.id,
        name = spec.name,
        role = spec.role,
        synergy_tags = spec.tags,
        rarity_budget = spec.draft_value,
    }, sources)
    local item = decorate(spec, rule_set)
    item.brick_ids = ast.copy(spec.brick_ids)
    M.BRICK_KITS[#M.BRICK_KITS + 1] = item
end

local function index_by_id(list)
    local out = {}
    for _, item in ipairs(list) do out[item.id] = item end
    return out
end

M.sling_by_id = index_by_id(M.SLINGS)
M.marble_by_id = index_by_id(M.ALL_MARBLES)
M.brick_kit_by_id = index_by_id(M.BRICK_KITS)

M.COMPREHENSION_POOL = {}
for _, item in ipairs(M.SLINGS) do
    M.COMPREHENSION_POOL[#M.COMPREHENSION_POOL + 1] = {
        category = "sling",
        id = item.id,
    }
end
for _, item in ipairs(M.MARBLES) do
    M.COMPREHENSION_POOL[#M.COMPREHENSION_POOL + 1] = {
        category = "marble",
        id = item.id,
    }
end
for _, item in ipairs(M.BRICK_KITS) do
    M.COMPREHENSION_POOL[#M.COMPREHENSION_POOL + 1] = {
        category = "brick_kit",
        id = item.id,
    }
end
M.COMPREHENSION_POOL_SIZE = #M.COMPREHENSION_POOL
assert(M.COMPREHENSION_POOL_SIZE == 17, "the approved comprehension pool must stay at 17 items")

return M
