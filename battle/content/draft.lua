-- Curated draft content for the first complete run.  These are individual
-- choices, never prebuilt armies: one sling, one marble blueprint, or one
-- positional two-brick idea.

local M = {}

M.VERSION = "draft-content-1"

M.TAGS = {
    force = {
        label = "Force",
        description = "Raises launch impulse, mass, or penetration.",
    },
    rebound = {
        label = "Rebound",
        description = "Creates valuable second angles after impact.",
    },
    field = {
        label = "Fields",
        description = "Improves persistent zones and release effects.",
    },
    release = {
        label = "Core Release",
        description = "Benefits when a marble sheds its final shell.",
    },
    durable = {
        label = "Durable",
        description = "Keeps marbles or bricks relevant through repeated impacts.",
    },
    tempo = {
        label = "Tempo",
        description = "Produces useful pressure early in the ordered bag.",
    },
    angle = {
        label = "Angles",
        description = "Changes approach lines and punishes exposed lanes.",
    },
    chain = {
        label = "Chain",
        description = "Converts adjacency into linked damage or release value.",
    },
    guard = {
        label = "Guard",
        description = "Protects a valuable neighbour or formation lane.",
    },
    sustain = {
        label = "Sustain",
        description = "Recovers or prevents damage over several exchanges.",
    },
    control = {
        label = "Control",
        description = "Pulls, slows, poisons, or redirects moving marbles.",
    },
    depth = {
        label = "Protected Depth",
        description = "Rewards placing important pieces behind a front line.",
    },
    burst = {
        label = "Burst",
        description = "Trades durability for a decisive damage window.",
    },
    absorption = {
        label = "Absorption",
        description = "Turns direct impact into protection for an adjacent line.",
    },
    mirror_lane = {
        label = "Mirror Lane",
        description = "Builds a protected lane around deliberate rebounds.",
    },
    renewal = {
        label = "Renewal",
        description = "Combines recovery with a one-time prevention effect.",
    },
    status_lock = {
        label = "Status Lock",
        description = "Layers multiple fixed-step statuses on one approach.",
    },
    gravity_well = {
        label = "Gravity Well",
        description = "Pulls a target into a follow-up effect.",
    },
    detonation = {
        label = "Detonation",
        description = "Makes one destruction the fuse for nearby damage.",
    },
    damage_link = {
        label = "Damage Link",
        description = "Routes adjacency damage into a prepared chain.",
    },
    deep_reserve = {
        label = "Deep Reserve",
        description = "Protects a late formation piece behind a dedicated front.",
    },
}

M.SLINGS = {
    {
        id = "momentum",
        name = "Momentum Sling",
        role = "Pressure",
        rarity = "specialized",
        draft_value = 100,
        mechanics = {
            "Adds launch impulse and penetration to every marble.",
            "Best with durable shells that can survive deeper contact.",
        },
        tags = { "force", "durable" },
        counter_tags = { "guard", "depth" },
        art_id = "sling_momentum",
    },
    {
        id = "ricochet",
        name = "Ricochet Sling",
        role = "Angles",
        rarity = "specialized",
        draft_value = 100,
        mechanics = {
            "Retains more impact energy on rebound.",
            "Turns mirrors and angled cores into chained approach lines.",
        },
        tags = { "rebound", "angle" },
        counter_tags = { "depth", "burst" },
        art_id = "sling_ricochet",
    },
    {
        id = "effect_amplifier",
        name = "Effect Amplifier",
        role = "Catalyst",
        rarity = "specialized",
        draft_value = 100,
        mechanics = {
            "Enlarges fields, release impulse, and non-chip effects.",
            "Does not add raw collision damage.",
        },
        tags = { "field", "release" },
        counter_tags = { "sustain", "control" },
        art_id = "sling_effect_amplifier",
    },
}

M.MARBLES = {
    {
        id = "chalk_common",
        name = "Chalk Pebble",
        role = "Opener",
        rarity = "common",
        core = "dull_quartz",
        shells = { "chalk_plain" },
        draft_value = 98,
        mechanics = {
            "A light first shot that releases its core quickly.",
            "Low durability makes its timing predictable.",
        },
        tags = { "tempo", "release" },
        counter_tags = { "depth" },
        art_id = "marble_chalk_common",
    },
    {
        id = "quartz_common",
        name = "Quartz Round",
        role = "Survivor",
        rarity = "common",
        core = "skew_flint",
        shells = { "quartz_banded" },
        draft_value = 102,
        mechanics = {
            "One unusually durable shell preserves bag tempo.",
            "Rightward core bias opens a second attack line.",
        },
        tags = { "durable", "angle" },
        counter_tags = { "burst" },
        art_id = "marble_quartz_common",
    },
    {
        id = "drifter_common",
        name = "Drifter",
        role = "Control",
        rarity = "common",
        core = "cant_pebble",
        shells = { "jade_lattice" },
        draft_value = 99,
        mechanics = {
            "Leftward bias reaches lanes a straight opener misses.",
            "Its lattice shell applies reliable chip pressure.",
        },
        tags = { "angle", "control" },
        counter_tags = { "rebound" },
        art_id = "marble_drifter_common",
    },
    {
        id = "flint_hook_common",
        name = "Flint Hook",
        role = "Breaker",
        rarity = "common",
        core = "skew_flint",
        shells = { "flint_spiral" },
        draft_value = 101,
        mechanics = {
            "Splinter collision pressure in a cheap single shell.",
            "Rightward bias rewards an exposed edge lane.",
        },
        tags = { "burst", "angle" },
        counter_tags = { "guard" },
        art_id = "marble_flint_hook",
    },
    {
        id = "geode_uncommon",
        name = "Split Geode",
        role = "Fuse",
        rarity = "uncommon",
        core = "shrapnel_geode",
        shells = { "obsidian_shard", "jade_lattice" },
        draft_value = 101,
        mechanics = {
            "Cleave pressure outside, reliable lattice inside.",
            "Final shell release sprays nearby bricks.",
        },
        tags = { "chain", "release" },
        counter_tags = { "sustain" },
        art_id = "marble_geode_uncommon",
    },
    {
        id = "silver_seed_uncommon",
        name = "Silver Seed",
        role = "Control",
        rarity = "uncommon",
        core = "shrapnel_geode",
        shells = { "silver_veined", "chalk_plain" },
        draft_value = 100,
        mechanics = {
            "A warded outer shell protects a fragile release timer.",
            "Shrapnel release rewards contact near a cluster.",
        },
        tags = { "guard", "release" },
        counter_tags = { "chain" },
        art_id = "marble_silver_seed",
    },
    {
        id = "banded_guard_uncommon",
        name = "Banded Guard",
        role = "Survivor",
        rarity = "uncommon",
        core = "dull_quartz",
        shells = { "quartz_banded", "jade_lattice" },
        draft_value = 102,
        mechanics = {
            "Two steady shells make a dependable bag anchor.",
            "Straight travel exchanges tricks for repeatable contact.",
        },
        tags = { "durable", "guard" },
        counter_tags = { "tempo" },
        art_id = "marble_banded_guard",
    },
    {
        id = "warden_rare",
        name = "Warden",
        role = "Survivor",
        rarity = "rare",
        core = "concussion_pearl",
        shells = { "silver_veined", "granite_mottled", "jade_lattice" },
        draft_value = 102,
        mechanics = {
            "Three complementary shells make a stable mid-bag anchor.",
            "Concussion release has reach but can disturb either roster.",
        },
        tags = { "durable", "control" },
        counter_tags = { "burst" },
        art_id = "marble_warden_rare",
    },
    {
        id = "shard_ram_rare",
        name = "Shard Ram",
        role = "Breaker",
        rarity = "rare",
        core = "shrapnel_geode",
        shells = { "granite_mottled", "obsidian_shard", "flint_spiral" },
        draft_value = 101,
        mechanics = {
            "A heavy face carries cleave and splinter shells into contact.",
            "Shrapnel release finishes tightly packed damage.",
        },
        tags = { "force", "burst" },
        counter_tags = { "guard" },
        art_id = "marble_shard_ram",
    },
    {
        id = "lodestone_epic",
        name = "Lodestone",
        role = "Control",
        rarity = "epic",
        core = "lodestone_heart",
        shells = { "flint_spiral", "quartz_banded", "jade_lattice", "chalk_plain" },
        draft_value = 100,
        mechanics = {
            "Four shells delay a magnetic core release.",
            "The pull can cluster enemies or endanger your own bag.",
        },
        tags = { "control", "field" },
        counter_tags = { "sustain" },
        art_id = "marble_lodestone_epic",
    },
    {
        id = "magnet_needle_epic",
        name = "Magnet Needle",
        role = "Finisher",
        rarity = "epic",
        core = "lodestone_heart",
        shells = { "silver_veined", "obsidian_shard", "flint_spiral", "chalk_plain" },
        draft_value = 99,
        mechanics = {
            "Fragile inner layers accelerate a late magnetic release.",
            "Ward and cleave reward timing after a durable opener.",
        },
        tags = { "release", "control" },
        counter_tags = { "depth" },
        art_id = "marble_magnet_needle",
    },
    {
        id = "cinder_legendary",
        name = "Cinder",
        role = "Finisher",
        rarity = "legendary",
        core = "cinder_nucleus",
        shells = {
            "obsidian_shard", "flint_spiral", "granite_mottled",
            "quartz_banded", "jade_lattice",
        },
        draft_value = 102,
        mechanics = {
            "Five distinct layers provide quality without a single specialty.",
            "Scorch release is strongest after the formation is opened.",
        },
        tags = { "burst", "field" },
        counter_tags = { "sustain" },
        art_id = "marble_cinder_legendary",
    },
}

M.BRICK_KITS = {
    {
        id = "guard_pair",
        name = "Basalt Escort",
        role = "Adjacent protection",
        brick_ids = { "basalt_absorber", "granite_fortifier" },
        suggested_placement = "Place side by side; the fortifier shelters the absorber.",
        draft_value = 101,
        mechanics = {
            "Absorber reduces incoming impulse.",
            "Fortifier protects an orthogonally adjacent brick.",
        },
        tags = { "guard", "durable", "absorption" },
        counter_tags = { "force" },
        art_id = "kit_guard_pair",
    },
    {
        id = "mirror_anchor",
        name = "Anchored Mirror",
        role = "Rebound lane",
        brick_ids = { "mirror_pane", "temporal_anchor" },
        suggested_placement = "Set the mirror forward with the anchor one row behind.",
        draft_value = 100,
        mechanics = {
            "Mirror pane redirects a surviving impact.",
            "Temporal anchor protects the rebound lane over time.",
        },
        tags = { "rebound", "depth", "mirror_lane" },
        counter_tags = { "angle" },
        art_id = "kit_mirror_anchor",
    },
    {
        id = "living_aegis",
        name = "Living Aegis",
        role = "Sustain",
        brick_ids = { "moss_regenerator", "aegis_keystone" },
        suggested_placement = "Keep the regenerator adjacent to the keystone.",
        draft_value = 102,
        mechanics = {
            "Regenerator restores damaged neighbours.",
            "Aegis prevents a key destruction once.",
        },
        tags = { "sustain", "guard", "renewal" },
        counter_tags = { "burst" },
        art_id = "kit_living_aegis",
    },
    {
        id = "venom_rime",
        name = "Cold Venom",
        role = "Control field",
        brick_ids = { "venom_glass", "rime_block" },
        suggested_placement = "Split them across approach lanes to layer statuses.",
        draft_value = 99,
        mechanics = {
            "Venom applies damage over later fixed steps.",
            "Rime reduces speed and lengthens exposure.",
        },
        tags = { "control", "field", "status_lock" },
        counter_tags = { "durable" },
        art_id = "kit_venom_rime",
    },
    {
        id = "lodestone_void",
        name = "Null Orbit",
        role = "Cluster then strip",
        brick_ids = { "lodestone_block", "void_prism" },
        suggested_placement = "Offset the prism behind the magnetic approach lane.",
        draft_value = 101,
        mechanics = {
            "Lodestone pulls a moving marble off its clean line.",
            "Void strips value after the cluster forms.",
        },
        tags = { "control", "field", "gravity_well" },
        counter_tags = { "rebound" },
        art_id = "kit_lodestone_void",
    },
    {
        id = "shatter_keg",
        name = "Fault Line",
        role = "Burst chain",
        brick_ids = { "shatter_crystal", "powder_keg" },
        suggested_placement = "Place adjacent where one break can reach the other.",
        draft_value = 98,
        mechanics = {
            "Shatter converts a hard hit into nearby damage.",
            "Powder keg propagates destruction through adjacency.",
        },
        tags = { "burst", "chain", "detonation" },
        counter_tags = { "sustain" },
        art_id = "kit_shatter_keg",
    },
    {
        id = "splice_keg",
        name = "Spliced Fuse",
        role = "Adjacency damage",
        brick_ids = { "splice_node", "powder_keg" },
        suggested_placement = "Join the node directly to the keg and another kit.",
        draft_value = 100,
        mechanics = {
            "Splice shares damage with an adjacent target.",
            "Powder keg turns that shared break into a chain.",
        },
        tags = { "chain", "burst", "damage_link" },
        counter_tags = { "guard" },
        art_id = "kit_splice_keg",
    },
    {
        id = "vault_temporal",
        name = "Deep Reserve",
        role = "Protected depth",
        brick_ids = { "vault_arch", "temporal_anchor" },
        suggested_placement = "Place the vault in front of the deeper anchor.",
        draft_value = 102,
        mechanics = {
            "Vault protects a valuable piece behind it.",
            "Temporal anchor extends the value of that protected lane.",
        },
        tags = { "depth", "sustain", "deep_reserve" },
        counter_tags = { "tempo" },
        art_id = "kit_vault_temporal",
    },
}

local function index_by_id(list)
    local out = {}
    for _, item in ipairs(list) do out[item.id] = item end
    return out
end

M.sling_by_id = index_by_id(M.SLINGS)
M.marble_by_id = index_by_id(M.MARBLES)
M.brick_kit_by_id = index_by_id(M.BRICK_KITS)

return M
