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

M.VERSION = "grammar-content-2"

M.TAGS = {
    force = { label = "Force", description = "Raises launch impulse or penetration." },
    rebound = { label = "Rebound", description = "Creates valuable second angles." },
    field = { label = "Fields", description = "Uses persistent zones or release areas." },
    release = { label = "Core Release", description = "Acts when the final shell breaks." },
    durable = { label = "Durable", description = "Stays relevant through repeated impacts." },
    tempo = { label = "Tempo", description = "Produces useful early pressure." },
    angle = { label = "Angles", description = "Changes approach lines." },
    chain = {
        label = "Chain",
        description = "On hostile destruction, wears the causal and nearby enemy marbles.",
    },
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
    retaliation = {
        label = "Retaliation",
        description = "Punishes clustered enemy marbles after destruction.",
    },
    adjacent_guard = {
        label = "Adjacent Guard",
        description = "Protects orthogonally adjacent allied bricks.",
    },
    deep_reserve = { label = "Deep Reserve", description = "Protects a late formation piece." },
}

local function decorate(spec, rule_set)
    ast.assert_valid(rule_set)
    local authority = ast.player_authority(rule_set)
    local item = {
        id = spec.id,
        name = spec.name or rule_set.name,
        role = rule_set.role,
        rarity = rule_set.rarity,
        -- Kept as a compatibility projection for the legacy draft UI. The
        -- canonical RuleSet budget is the only authored balance authority.
        draft_value = authority.rarity_budget,
        tags = ast.copy(rule_set.synergy_tags),
        counter_tags = ast.copy(spec.counter_tags or {}),
        art_id = spec.art_id,
        suggested_placement = spec.suggested_placement,
        rule_set = ast.copy(rule_set),
        compact_copy = authority.compact_copy,
        inspection_copy = ast.copy(authority.inspection_copy),
        mechanics = ast.copy(authority.compact_lines),
        compatibility = ast.copy(rule_set.compatibility),
        balance = ast.copy(authority.balance),
        availability = ast.copy(rule_set.availability),
        abilities = ast.copy(rule_set.abilities),
        telegraph = ast.copy(authority.telegraph),
    }
    if spec.rarity ~= nil and spec.rarity ~= rule_set.rarity then
        error(spec.id .. " rarity projection diverges from canonical RuleSet")
    end
    return item
end

local SLING_SPECS = {
    {
        id = "momentum",
        counter_tags = { "guard", "depth" },
        art_id = "sling_momentum",
    },
    {
        id = "ricochet",
        counter_tags = { "depth", "burst" },
        art_id = "sling_ricochet",
    },
    {
        id = "effect_amplifier",
        counter_tags = { "sustain", "control" },
        art_id = "sling_effect_amplifier",
    },
}

M.SLINGS = {}
for _, spec in ipairs(SLING_SPECS) do
    M.SLINGS[#M.SLINGS + 1] = decorate(spec, slings.canonical_rule_set(spec.id))
end

local MARBLE_SPECS = {
    {
        id = "chalk_common", name = "Chalk Pebble", role = "opener", rarity = "common",
        core = "dull_quartz", shell_ids = { "chalk_plain" }, rarity_budget = 100,
        tags = { "tempo", "release" }, counter_tags = { "depth" },
        art_id = "marble_chalk_common", in_pool = true,
    },
    {
        id = "quartz_common", name = "Quartz Round", role = "survivor", rarity = "common",
        core = "skew_flint", shell_ids = { "quartz_banded" }, rarity_budget = 100,
        tags = { "durable", "angle" }, counter_tags = { "burst" },
        art_id = "marble_quartz_common", in_pool = true,
    },
    {
        id = "drifter_common", name = "Drifter", role = "control", rarity = "common",
        core = "cant_pebble", shell_ids = { "jade_lattice" }, rarity_budget = 100,
        tags = { "angle", "control" }, counter_tags = { "rebound" },
        art_id = "marble_drifter_common",
    },
    {
        id = "flint_hook_common", name = "Flint Hook", role = "breaker", rarity = "common",
        core = "skew_flint", shell_ids = { "flint_spiral" }, rarity_budget = 100,
        tags = { "burst", "angle" }, counter_tags = { "guard" },
        art_id = "marble_flint_hook",
    },
    {
        id = "geode_uncommon", name = "Split Geode", role = "fuse", rarity = "uncommon",
        core = "shrapnel_geode", shell_ids = { "obsidian_shard", "jade_lattice" },
        rarity_budget = 100, tags = { "chain", "release" }, counter_tags = { "sustain" },
        art_id = "marble_geode_uncommon", in_pool = true,
    },
    {
        id = "silver_seed_uncommon", name = "Silver Seed", role = "control", rarity = "uncommon",
        core = "shrapnel_geode", shell_ids = { "silver_veined", "chalk_plain" },
        rarity_budget = 100, tags = { "guard", "release" }, counter_tags = { "chain" },
        art_id = "marble_silver_seed",
    },
    {
        id = "banded_guard_uncommon", name = "Banded Guard", role = "survivor",
        rarity = "uncommon", core = "dull_quartz",
        shell_ids = { "quartz_banded", "jade_lattice" }, rarity_budget = 100,
        tags = { "durable", "guard" }, counter_tags = { "tempo" },
        art_id = "marble_banded_guard",
    },
    {
        id = "warden_rare", name = "Warden", role = "survivor", rarity = "rare",
        core = "concussion_pearl",
        shell_ids = { "silver_veined", "granite_mottled", "jade_lattice" },
        rarity_budget = 100, tags = { "durable", "control" }, counter_tags = { "burst" },
        art_id = "marble_warden_rare", in_pool = true,
    },
    {
        id = "shard_ram_rare", name = "Shard Ram", role = "breaker", rarity = "rare",
        core = "shrapnel_geode",
        shell_ids = { "granite_mottled", "obsidian_shard", "flint_spiral" },
        rarity_budget = 100, tags = { "force", "burst" }, counter_tags = { "guard" },
        art_id = "marble_shard_ram",
    },
    {
        id = "lodestone_epic", name = "Lodestone", role = "control", rarity = "epic",
        core = "lodestone_heart",
        shell_ids = { "flint_spiral", "quartz_banded", "jade_lattice", "chalk_plain" },
        rarity_budget = 100, tags = { "control", "field" }, counter_tags = { "sustain" },
        art_id = "marble_lodestone_epic", in_pool = true,
    },
    {
        id = "magnet_needle_epic", name = "Magnet Needle", role = "finisher", rarity = "epic",
        core = "lodestone_heart",
        shell_ids = { "silver_veined", "obsidian_shard", "flint_spiral", "chalk_plain" },
        rarity_budget = 100, tags = { "release", "control" }, counter_tags = { "depth" },
        art_id = "marble_magnet_needle",
    },
    {
        id = "cinder_legendary", name = "Cinder", role = "finisher", rarity = "legendary",
        core = "cinder_nucleus",
        shell_ids = {
            "obsidian_shard", "flint_spiral", "granite_mottled",
            "quartz_banded", "jade_lattice",
        },
        rarity_budget = 100, tags = { "burst", "field" }, counter_tags = { "sustain" },
        art_id = "marble_cinder_legendary", in_pool = true,
    },
}

M.MARBLES = {}
M.LEGACY_MARBLES = {}
M.ALL_MARBLES = {}

for _, spec in ipairs(MARBLE_SPECS) do
    local core_rules = cores.canonical_rule_set(spec.core)
    local sources = { core_rules }
    for _, shell_id in ipairs(spec.shell_ids) do
        sources[#sources + 1] = shells.canonical_rule_set(shell_id)
    end
    local rule_set = ast.compose({
        id = "card.marble." .. spec.id,
        name = spec.name,
        role = spec.role,
        synergy_tags = spec.tags,
        rarity_budget = 100,
        drawback = core_rules.drawback,
        content_kind = "marble",
        rarity = spec.rarity,
        availability = {
            player_draft = spec.in_pool == true,
            player_reward = spec.in_pool == true,
            cpu_recipe = true,
            legacy_only = spec.in_pool ~= true,
        },
        abilities = ast.copy(core_rules.abilities),
        compatibility = {
            requires = {},
            excludes = {},
            max_copies = ast.tier(spec.rarity).marble_copy_cap,
        },
    }, sources)
    ast.register(rule_set)
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
        id = "guard_pair", name = "Foundation Pair", role = "efficient foundations",
        rarity = "common",
        brick_ids = { "basalt_absorber", "training_dummy" }, rarity_budget = 100,
        tags = { "guard", "durable", "tempo" }, counter_tags = { "force" },
        suggested_placement = "Use the dense Basalt body and springy Dummy to shape lanes.",
        art_id = "kit_guard_pair",
    },
    {
        id = "mirror_anchor", name = "Anchored Mirror", role = "rebound lane",
        rarity = "uncommon",
        brick_ids = { "mirror_pane", "vault_arch" }, rarity_budget = 100,
        tags = { "rebound", "force", "mirror_lane" }, counter_tags = { "angle" },
        suggested_placement = "Set the mirror in the prepared rebound lane and angle the vault.",
        art_id = "kit_mirror_anchor",
    },
    {
        id = "living_aegis", name = "Living Aegis", role = "sustain",
        rarity = "epic",
        brick_ids = { "moss_regenerator", "aegis_keystone" }, rarity_budget = 100,
        tags = { "sustain", "guard", "renewal" }, counter_tags = { "burst" },
        suggested_placement = "Keep the regenerator adjacent to the keystone.",
        art_id = "kit_living_aegis",
    },
    {
        id = "venom_rime", name = "Cold Venom", role = "control field",
        rarity = "rare",
        brick_ids = { "venom_glass", "rime_block" }, rarity_budget = 100,
        tags = { "control", "field", "status_lock" }, counter_tags = { "durable" },
        suggested_placement = "Split them across approach lanes to layer statuses.",
        art_id = "kit_venom_rime",
    },
    {
        id = "lodestone_void", name = "Null Orbit", role = "cluster then strip",
        rarity = "epic",
        brick_ids = { "lodestone_block", "void_prism" }, rarity_budget = 100,
        tags = { "control", "field", "gravity_well" }, counter_tags = { "rebound" },
        suggested_placement = "Offset the prism behind the magnetic approach lane.",
        art_id = "kit_lodestone_void",
    },
    {
        id = "shatter_keg", name = "Fault Line", role = "shell-break retaliation",
        rarity = "rare",
        brick_ids = { "shatter_crystal", "powder_keg" }, rarity_budget = 100,
        tags = { "burst", "chain", "retaliation" }, counter_tags = { "sustain" },
        suggested_placement = "Put the Keg on a formation edge near the enemy marble cluster.",
        art_id = "kit_shatter_keg",
    },
    {
        id = "splice_keg", name = "Spliced Bastion", role = "bounded adjacent protection",
        rarity = "rare",
        brick_ids = { "splice_node", "granite_fortifier" }, rarity_budget = 100,
        tags = { "guard", "depth", "adjacent_guard" }, counter_tags = { "burst" },
        suggested_placement = "Place both pieces beside allies; Splice Guard never harms them.",
        art_id = "kit_splice_keg",
    },
    {
        id = "vault_temporal", name = "Deep Reserve", role = "protected depth",
        rarity = "legendary",
        brick_ids = { "prismatic_mirror", "temporal_anchor" }, rarity_budget = 100,
        tags = { "depth", "sustain", "rebound", "deep_reserve" }, counter_tags = { "tempo" },
        suggested_placement = "Keep the Temporal Anchor in the rear row behind the mirror.",
        art_id = "kit_vault_temporal",
    },
}

M.BRICK_KITS = {}
for _, spec in ipairs(KIT_SPECS) do
    local sources = {}
    for _, brick_id in ipairs(spec.brick_ids) do
        sources[#sources + 1] = bricks.canonical_rule_set(brick_id)
    end
    local rule_set = ast.compose({
        id = "card.brick_kit." .. spec.id,
        name = spec.name,
        role = spec.role,
        synergy_tags = spec.tags,
        rarity_budget = 100,
        content_kind = "brick_kit",
        rarity = spec.rarity,
        availability = {
            player_draft = true,
            player_reward = false,
            cpu_recipe = true,
            legacy_only = false,
        },
        abilities = {},
        compatibility = {
            requires = {},
            excludes = {},
            max_copies = 1,
        },
    }, sources)
    ast.register(rule_set)
    local item = decorate(spec, rule_set)
    item.brick_ids = ast.copy(spec.brick_ids)
    item.telegraph = {
        rarity = spec.rarity,
        beads = ast.tier(spec.rarity).rank,
        offer_tier = spec.rarity,
        packaging_only = true,
        members = {},
    }
    item.balance = {
        schema_version = ast.SCHEMA_VERSION,
        rule_set_id = rule_set.id,
        budget = nil,
        packaging_only = true,
        members = {},
    }
    for _, brick_id in ipairs(spec.brick_ids) do
        item.balance.members[#item.balance.members + 1] = {
            content_id = brick_id,
            ledger = ast.balance(bricks.canonical_rule_set(brick_id)),
        }
        item.telegraph.members[#item.telegraph.members + 1] =
            ast.player_authority(bricks.canonical_rule_set(brick_id)).telegraph
    end
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
M.brick_reward_pool = {}
M.brick_kit_for = {}
for _, kit in ipairs(M.BRICK_KITS) do
    for _, brick_id in ipairs(kit.brick_ids) do
        if M.brick_kit_for[brick_id] then
            error("behaviour brick appears in more than one canonical kit: " .. brick_id)
        end
        local rule_set = bricks.canonical_rule_set(brick_id)
        M.brick_kit_for[brick_id] = kit.id
        if rule_set.availability.player_reward then
            M.brick_reward_pool[#M.brick_reward_pool + 1] = {
                id = brick_id,
                kit_id = kit.id,
                rarity = rule_set.rarity,
                rule_set = ast.copy(rule_set),
            }
        end
    end
end
table.sort(M.brick_reward_pool, function(left, right) return left.id < right.id end)
assert(#M.brick_reward_pool == 16, "all 16 behaviour bricks must be reward-authorized")

function M.economy()
    return ast.economy()
end

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

-- Catalogs are compatibility projections, never construction authority.
-- Return a fresh recursive value for every exported table read so list, alias,
-- by-id, reward, tag, and RuleSet mutations cannot survive into a later read
-- (or cross-poison another exported view).  Keep the module itself as userdata
-- so neither ordinary assignment nor rawset can replace an accessor or scalar.
local module = newproxy(true)
local module_metatable = getmetatable(module)
module_metatable.__index = function(_, key)
    local value = M[key]
    if type(value) == "table" then return ast.copy(value) end
    return value
end
module_metatable.__newindex = function(_, key)
    error("draft catalog facade is read-only (" .. tostring(key) .. ")", 2)
end
module_metatable.__metatable = "isolated draft catalog projections"
return module
