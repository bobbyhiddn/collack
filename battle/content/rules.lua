-- Canonical mechanical content.
--
-- These RuleSets are the only authored source of numeric or boolean rule
-- meaning.  The legacy-shaped tables in shells.lua, cores.lua, bricks.lua,
-- slings.lua, and effects.lua are deterministic projections of these trees.

local ast = require("battle.rule_ast")

local M = {
    slings = {},
    collisions = {},
    releases = {},
    statuses = {},
    brick_behaviours = {},
    shells = {},
    cores = {},
    bricks = {},
}

local function node(id, trigger, target, verb, stat, value, unit, options)
    options = options or {}
    local quantity = {
        value = value,
        unit = unit or "count",
    }
    local magnitude, duration = quantity, nil
    if options.as_duration then
        magnitude, duration = nil, quantity
    end
    if options.duration_value ~= nil then
        local result = {
            value = options.duration_value,
            unit = options.duration_unit or "ticks",
        }
        if magnitude == nil then duration = result else
            -- Rules such as Guard have both a magnitude and an expiry.
            duration = result
        end
    end
    local result = {
        id = id,
        trigger = {
            event = trigger,
            phase = options.phase or "during",
        },
        condition = {
            predicate = options.condition or "always",
            value = options.condition_value,
        },
        target = {
            selector = target,
            relation = options.relation,
            topology = options.topology,
            count = options.count,
            exclude_self = options.exclude_self,
            require_alive = options.require_alive,
            required_tags = options.required_tags,
            excluded_tags = options.excluded_tags,
            order = options.order,
            radius = options.radius,
        },
        operation = {
            verb = verb,
            stat = stat,
            mode = options.mode or "set",
        },
        magnitude = magnitude,
        duration = duration,
        cadence = {
            unit = options.cadence_unit or trigger,
            interval = options.interval or 1,
            charges = options.charges,
            limit = options.limit,
        },
        cost = {
            kind = options.cost_kind or "none",
            stat = options.cost_stat,
            magnitude = options.cost_magnitude,
            unit = options.cost_unit,
        },
        visibility = options.visibility or "compact",
        scaling = options.scaling,
        lethal = options.lethal,
    }
    return result
end

local function rule_set(id, name, role, tags, rules, options)
    options = options or {}
    local item = {
        schema_version = ast.SCHEMA_VERSION,
        kind = "rule_set",
        id = id,
        name = name,
        role = role,
        rules = rules,
        drawback = options.drawback or { kind = "none" },
        compatibility = options.compatibility or {
            requires = {},
            excludes = {},
            max_copies = 1,
        },
        synergy_tags = tags,
        rarity_budget = options.rarity_budget or 100,
        content_kind = options.content_kind or "component",
        component_kind = options.component_kind or (
            (options.content_kind == nil or options.content_kind == "component")
                and "operation" or nil
        ),
        rarity = options.rarity,
        min_rarity = options.min_rarity,
        availability = options.availability or {
            player_draft = false,
            player_reward = false,
            cpu_recipe = false,
            legacy_only = false,
        },
        abilities = options.abilities or {},
        components = options.components or {},
        formation = options.formation,
    }
    ast.assert_valid(item)
    if options.register ~= false then ast.register(item) end
    return item
end

local function derive(spec, sources)
    local item = ast.compose({
        id = spec.id,
        name = spec.name,
        role = spec.role,
        drawback = spec.drawback or { kind = "none" },
        compatibility = spec.compatibility or {
            requires = {},
            excludes = {},
            max_copies = 1,
        },
        synergy_tags = spec.synergy_tags,
        rarity_budget = spec.rarity_budget or 100,
        content_kind = spec.content_kind or "component",
        component_kind = spec.component_kind or (
            (spec.content_kind == nil or spec.content_kind == "component")
                and "composition" or nil
        ),
        rarity = spec.rarity,
        min_rarity = spec.min_rarity,
        availability = spec.availability,
        abilities = spec.abilities,
        components = spec.components,
        formation = spec.formation,
    }, sources)
    ast.register(item)
    return item
end

-- Collision operations -------------------------------------------------------

M.collisions.chip = rule_set(
    "collision.chip",
    "Chip",
    "steady contact",
    { "tempo" },
    {
        node("collision.chip.damage", "collision", "struck_brick",
            "deal", "damage", 1, "damage"),
        node("collision.chip.wear", "collision", "current_shell",
            "wear", "durability_cost", 1, "durability", { visibility = "expanded" }),
        node("collision.chip.identity", "build", "self",
            "set", "collision", "chip", "id", { visibility = "expanded" }),
    }
)

M.collisions.cleave = rule_set(
    "collision.cleave",
    "Cleave",
    "heavy contact",
    { "burst" },
    {
        node("collision.cleave.damage", "collision", "struck_brick",
            "deal", "damage", 2, "damage"),
        node("collision.cleave.wear", "collision", "current_shell",
            "wear", "durability_cost", 1, "durability", { visibility = "expanded" }),
        node("collision.cleave.identity", "build", "self",
            "set", "collision", "cleave", "id", { visibility = "expanded" }),
    }
)

M.collisions.splinter = rule_set(
    "collision.splinter",
    "Splinter",
    "depth contact",
    { "angle", "chain" },
    {
        node("collision.splinter.damage", "collision", "struck_brick",
            "deal", "damage", 1, "damage"),
        node("collision.splinter.behind", "collision", "target_column",
            "splash", "splash_behind", 1, "damage"),
        node("collision.splinter.wear", "collision", "current_shell",
            "wear", "durability_cost", 1, "durability", { visibility = "expanded" }),
        node("collision.splinter.identity", "build", "self",
            "set", "collision", "splinter", "id", { visibility = "expanded" }),
    }
)

M.collisions.ward = rule_set(
    "collision.ward",
    "Ward",
    "armour breaker",
    { "guard" },
    {
        node("collision.ward.damage", "collision", "struck_brick",
            "deal", "damage", 1, "damage"),
        node("collision.ward.pierce", "collision", "struck_brick",
            "pierce", "pierces_absorb", true, "flag"),
        node("collision.ward.wear", "collision", "current_shell",
            "wear", "durability_cost", 1, "durability", { visibility = "expanded" }),
        node("collision.ward.identity", "build", "self",
            "set", "collision", "ward", "id", { visibility = "expanded" }),
    }
)

M.collisions.heavy = rule_set(
    "collision.heavy",
    "Heavy",
    "force contact",
    { "force" },
    {
        node("collision.heavy.damage", "collision", "struck_brick",
            "deal", "damage", 2, "damage"),
        node("collision.heavy.wear", "collision", "current_shell",
            "wear", "durability_cost", 1, "durability", { visibility = "expanded" }),
        node("collision.heavy.identity", "build", "self",
            "set", "collision", "heavy", "id", { visibility = "expanded" }),
    }
)

-- Core release operations ----------------------------------------------------

-- Every release creates the same persistent fixed-step field. The shared
-- canonical nodes are composed into each release RuleSet, so non-baseline
-- releases do not gain hidden mechanics from a runtime overlay.
local RELEASE_FIELD_RULES = {
    node("release.baseline.field_duration", "core_release", "release_area",
        "persist", "field_duration", 24, "ticks",
        { as_duration = true, visibility = "expanded" }),
    node("release.baseline.field_strength", "core_release", "release_area",
        "push", "field_release_strength", 10, "strength", { visibility = "expanded" }),
}

local function complete_release(rules)
    local out = { rules[1] }
    for _, rule in ipairs(RELEASE_FIELD_RULES) do out[#out + 1] = ast.copy(rule) end
    for index = 2, #rules do out[#out + 1] = rules[index] end
    return out
end

M.releases.baseline = rule_set(
    "release.baseline",
    "Blowback",
    "symmetric displacement",
    { "release" },
    complete_release({
        node("release.baseline.radius", "core_release", "nearby_marbles",
            "push", "radius", 1, "radius", { condition = "final_shell" }),
        node("release.baseline.identity", "build", "self",
            "set", "release", "baseline", "id", { visibility = "expanded" }),
    }),
    {
        drawback = {
            kind = "risk",
            stat = "core_release",
            magnitude = 1,
            unit = "count",
        },
    }
)

M.releases.shrapnel = rule_set(
    "release.shrapnel",
    "Shrapnel",
    "release damage",
    { "release", "chain" },
    {
        node("release.shrapnel.damage", "core_release", "nearest_enemy_brick_cluster",
            "splash", "shrapnel", 1, "damage", {
                condition = "final_shell",
                relation = "enemy",
                count = 5,
                order = "distance_row_col_uid",
            }),
        node("release.shrapnel.identity", "build", "self",
            "set", "release", "shrapnel", "id", { visibility = "expanded" }),
    },
    {
        drawback = {
            kind = "risk",
            stat = "core_release",
            magnitude = 1,
            unit = "count",
        },
    }
)

M.releases.concussion = rule_set(
    "release.concussion",
    "Concussion",
    "wide displacement",
    { "release", "control" },
    {
        node("release.concussion.radius", "core_release", "nearby_marbles",
            "push", "radius", 2, "radius", { condition = "final_shell" }),
        node("release.concussion.identity", "build", "self",
            "set", "release", "concussion", "id", { visibility = "expanded" }),
    },
    {
        drawback = {
            kind = "risk",
            stat = "core_release",
            magnitude = 2,
            unit = "radius",
        },
    }
)

M.releases.magnetize = rule_set(
    "release.magnetize",
    "Magnetize",
    "clustering displacement",
    { "release", "control", "field" },
    {
        node("release.magnetize.invert", "core_release", "nearby_marbles",
            "pull", "invert", true, "flag", { condition = "final_shell" }),
        node("release.magnetize.identity", "build", "self",
            "set", "release", "magnetize", "id", { visibility = "expanded" }),
    },
    {
        drawback = {
            kind = "risk",
            stat = "core_release",
            magnitude = 1,
            unit = "count",
        },
    }
)

M.releases.scorch = rule_set(
    "release.scorch",
    "Scorch",
    "release attrition",
    { "release", "field", "burst" },
    {
        node("release.scorch.wear", "core_release", "nearby_marbles",
            "scorch", "scorch", 1, "durability", { condition = "final_shell" }),
        node("release.scorch.identity", "build", "self",
            "set", "release", "scorch", "id", { visibility = "expanded" }),
    },
    {
        drawback = {
            kind = "risk",
            stat = "core_release",
            magnitude = 1,
            unit = "durability",
        },
    }
)

-- Status operations ----------------------------------------------------------

M.statuses.poison = rule_set(
    "status.poison",
    "Poison",
    "delayed shell wear",
    { "control", "field" },
    {
        node("status.poison.duration", "field_contact", "striking_marble",
            "persist", "duration_ticks", 240, "ticks",
            { as_duration = true, condition = "enemy", visibility = "expanded" }),
        node("status.poison.wear", "status_tick", "current_shell",
            "wear", "shell_wear", 1, "durability",
            { interval = 120, cadence_unit = "ticks" }),
        node("status.poison.identity", "build", "self",
            "set", "status", "poison", "id", { visibility = "expanded" }),
    }
)

M.statuses.freeze = rule_set(
    "status.freeze",
    "Freeze",
    "temporary slowing",
    { "control", "field" },
    {
        node("status.freeze.duration", "field_contact", "striking_marble",
            "persist", "duration_ticks", 90, "ticks",
            { as_duration = true, condition = "enemy", visibility = "expanded" }),
        node("status.freeze.field_slow", "field_contact", "striking_marble",
            "slow", "velocity_multiplier", 0.985, "multiplier", { visibility = "expanded" }),
        node("status.freeze.launch_slow", "launch", "launch",
            "slow", "launch_speed_multiplier", 0.72, "multiplier"),
        node("status.freeze.identity", "build", "self",
            "set", "status", "freeze", "id", { visibility = "expanded" }),
    }
)

-- Brick operations -----------------------------------------------------------

M.brick_behaviours.inert = rule_set(
    "brick.behaviour.inert",
    "Base",
    "body",
    { "durable" },
    {
        node("brick.inert.identity", "build", "self",
            "hold", "behaviour", "inert", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.absorb = rule_set(
    "brick.behaviour.absorb",
    "Dense Body",
    "raw body",
    { "guard", "durable" },
    {
        node("brick.absorb.identity", "build", "self",
            "set", "behaviour", "absorb", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.reflect = rule_set(
    "brick.behaviour.reflect",
    "Reflect",
    "rebound guard",
    { "rebound", "guard" },
    {
        node("brick.reflect.rebound", "survives_collision", "striking_marble",
            "rebound", "reflect", 1.08, "multiplier", { condition = "survives" }),
        node("brick.reflect.identity", "build", "self",
            "set", "behaviour", "reflect", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.regenerate = rule_set(
    "brick.behaviour.regenerate",
    "Regenerate",
    "sustain",
    { "sustain", "durable" },
    {
        node("brick.regenerate.heal", "survives_collision", "self",
            "heal", "heal_after_hit", 1, "hp", {
                condition = "survives",
                cadence_unit = "exchange",
                charges = 1,
            }),
        node("brick.regenerate.identity", "build", "self",
            "set", "behaviour", "regenerate", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.fortify = rule_set(
    "brick.behaviour.fortify",
    "Fortify",
    "adjacent guard",
    { "guard", "depth" },
    {
        node("brick.fortify.protect", "damaging_collision", "orthogonal_neighbours",
            "protect", "protect_adjacent", 1, "damage", { condition = "adjacent" }),
        node("brick.fortify.identity", "build", "self",
            "set", "behaviour", "fortify", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.poison = rule_set(
    "brick.behaviour.poison",
    "Poison",
    "attrition field",
    { "control", "field" },
    {
        node("brick.poison.status", "field_contact", "striking_marble",
            "apply_status", "status", "poison", "id", { condition = "enemy" }),
        node("brick.poison.radius", "passive", "self",
            "cover", "field_radius", 6.5, "radius", { visibility = "expanded" }),
        node("brick.poison.strength", "passive", "release_area",
            "set", "field_strength", 0, "strength", { visibility = "expanded" }),
        node("brick.poison.identity", "build", "self",
            "set", "behaviour", "poison", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.freeze = rule_set(
    "brick.behaviour.freeze",
    "Freeze",
    "slow field",
    { "control", "field" },
    {
        node("brick.freeze.status", "field_contact", "striking_marble",
            "apply_status", "status", "freeze", "id", { condition = "enemy" }),
        node("brick.freeze.radius", "passive", "self",
            "cover", "field_radius", 6.5, "radius", { visibility = "expanded" }),
        node("brick.freeze.strength", "passive", "release_area",
            "set", "field_strength", 0, "strength", { visibility = "expanded" }),
        node("brick.freeze.identity", "build", "self",
            "set", "behaviour", "freeze", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.magnetic = rule_set(
    "brick.behaviour.magnetic",
    "Magnetic",
    "pull field",
    { "control", "field" },
    {
        node("brick.magnetic.radius", "passive", "self",
            "cover", "field_radius", 13, "radius", { visibility = "expanded" }),
        node("brick.magnetic.strength", "passive", "nearby_marbles",
            "pull", "field_strength", -58, "strength"),
        node("brick.magnetic.identity", "build", "self",
            "set", "behaviour", "magnetic", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.shatter = rule_set(
    "brick.behaviour.shatter",
    "Shatter",
    "shell breaker",
    { "burst", "control" },
    {
        node("brick.shatter.wear", "collision", "current_shell",
            "wear", "shell_wear", 2, "durability"),
        node("brick.shatter.identity", "build", "self",
            "set", "behaviour", "shatter", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.chain = rule_set(
    "brick.behaviour.chain",
    "Chain",
    "destruction burst",
    { "chain", "burst" },
    {
        node("brick.chain.shell_wear", "destroyed", "chain_enemy_marbles",
            "wear", "chain_shell_wear", 1, "durability", {
                relation = "enemy",
                count = 3,
                radius = 24,
                order = "causal_then_distance_body_id",
                charges = 1,
            }),
        node("brick.chain.identity", "build", "self",
            "set", "behaviour", "chain", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.vault = rule_set(
    "brick.behaviour.vault",
    "Vault",
    "forward force",
    { "force", "depth" },
    {
        node("brick.vault.force", "collision", "striking_marble",
            "accelerate", "momentum_delta", 1, "launch_force"),
        node("brick.vault.identity", "build", "self",
            "set", "behaviour", "vault", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.splice = rule_set(
    "brick.behaviour.splice",
    "Splice",
    "adjacent guard",
    { "guard", "depth" },
    {
        node("brick.splice.guard", "damaging_collision", "orthogonal_neighbours",
            "protect", "guard", 1, "damage", {
                condition = "survives",
                relation = "allied",
                topology = "orthogonal",
                count = 4,
                exclude_self = true,
                require_alive = true,
                order = "local_up_down_left_right",
                cadence_unit = "exchange",
                charges = 1,
                duration_value = 120,
                duration_unit = "ticks",
            }),
        node("brick.splice.identity", "build", "self",
            "set", "behaviour", "splice", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.dummy = rule_set(
    "brick.behaviour.dummy",
    "Dummy",
    "spring body",
    { "tempo" },
    {
        node("brick.dummy.identity", "build", "self",
            "set", "behaviour", "dummy", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.aegis = rule_set(
    "brick.behaviour.aegis",
    "Aegis",
    "one-shot guard",
    { "guard", "sustain" },
    {
        node("brick.aegis.negate", "damaging_collision", "self",
            "negate", "negate_once", true, "flag", { charges = 1 }),
        node("brick.aegis.identity", "build", "self",
            "set", "behaviour", "aegis", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.void = rule_set(
    "brick.behaviour.void",
    "Void",
    "shell strip",
    { "control", "burst" },
    {
        node("brick.void.break", "collision", "current_shell",
            "break", "break_shell", true, "flag"),
        node("brick.void.identity", "build", "self",
            "set", "behaviour", "void", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.mirror = rule_set(
    "brick.behaviour.mirror",
    "Mirror",
    "punishing rebound",
    { "rebound", "guard" },
    {
        node("brick.mirror.rebound", "survives_collision", "striking_marble",
            "rebound", "reflect", 1.08, "multiplier", { condition = "survives" }),
        node("brick.mirror.wear", "collision", "current_shell",
            "wear", "shell_wear", 1, "durability"),
        node("brick.mirror.identity", "build", "self",
            "set", "behaviour", "mirror", "id", { visibility = "expanded" }),
    }
)

M.brick_behaviours.temporal = rule_set(
    "brick.behaviour.temporal",
    "Temporal",
    "damage rewind",
    { "sustain", "depth" },
    {
        node("brick.temporal.rewind", "survives_collision", "self",
            "rewind", "rewind", true, "flag", { condition = "survives" }),
        node("brick.temporal.identity", "build", "self",
            "set", "behaviour", "temporal", "id", { visibility = "expanded" }),
    }
)

-- Sling operations -----------------------------------------------------------

local function sling(id, name, role, tags, rules, drawback)
    M.slings[id] = rule_set(
        "sling." .. id,
        name,
        role,
        tags,
        rules,
        {
            drawback = drawback or { kind = "none" },
            content_kind = "sling",
            availability = {
                player_draft = true,
                player_reward = true,
                cpu_recipe = true,
                legacy_only = false,
            },
            compatibility = {
                requires = {},
                excludes = {},
                max_copies = 1,
            },
        }
    )
end

sling("training_sling", "Training Sling", "training", { "tempo" }, {
    node("sling.training.force", "build", "all_owned_marbles",
        "accelerate", "momentum_bonus", 1, "launch_force"),
    node("sling.training.scatter", "launch", "launch",
        "scatter", "scatter", 1, "count", { visibility = "expanded" }),
})

sling("tuned_sling", "Tuned Sling", "durability", { "durable" }, {
    node("sling.tuned.durability", "build", "all_owned_marbles",
        "protect", "durability_bonus", 1, "durability"),
    node("sling.tuned.force", "build", "all_owned_marbles",
        "accelerate", "momentum_bonus", 1, "launch_force", { visibility = "expanded" }),
})

sling("heavy_sling", "Heavy Sling", "damage", { "force", "burst" }, {
    node("sling.heavy.damage", "collision", "struck_brick",
        "deal", "damage_bonus", 1, "damage"),
    node("sling.heavy.scatter", "launch", "launch",
        "scatter", "scatter", 1, "count", { visibility = "expanded" }),
})

sling("raker_sling", "Raker Sling", "angle force", { "force", "angle" }, {
    node("sling.raker.force", "build", "all_owned_marbles",
        "accelerate", "momentum_bonus", 2, "launch_force"),
    node("sling.raker.aim", "launch", "launch",
        "aim", "aim", 1, "count"),
    node("sling.raker.scatter", "launch", "launch",
        "scatter", "scatter", 1, "count", { visibility = "expanded" }),
})

sling("volley", "Volley Sling", "cadence", { "tempo", "burst" }, {
    node("sling.volley.shots", "launch", "all_owned_marbles",
        "launch", "shots_per_volley", 2, "shots", { limit = 2 }),
}, {
    kind = "opportunity",
    stat = "launch_force",
    magnitude = 1,
    unit = "launch_force",
})

sling("momentum", "Momentum Sling", "pressure", { "force", "durable" }, {
    node("sling.momentum.force", "build", "all_owned_marbles",
        "accelerate", "momentum_bonus", 3, "launch_force"),
}, {
    kind = "opportunity",
    stat = "rebound and effect amplification",
    magnitude = 1,
    unit = "count",
})

sling("ricochet", "Ricochet Sling", "angles", { "rebound", "angle" }, {
    node("sling.ricochet.force", "build", "all_owned_marbles",
        "accelerate", "momentum_bonus", 1, "launch_force", { visibility = "expanded" }),
    node("sling.ricochet.rebound", "wall_or_brick_contact", "striking_marble",
        "rebound", "ricochet", true, "flag"),
}, {
    kind = "opportunity",
    stat = "launch_force",
    magnitude = 2,
    unit = "launch_force",
})

sling("spread", "Spread Sling", "coverage", { "angle", "tempo" }, {
    node("sling.spread.force", "build", "all_owned_marbles",
        "accelerate", "momentum_bonus", 1, "launch_force", { visibility = "expanded" }),
    node("sling.spread.scatter", "launch", "launch",
        "scatter", "scatter", 2, "count"),
}, {
    kind = "reduce",
    stat = "accuracy",
    magnitude = 2,
    unit = "count",
})

sling("precision", "Precision Sling", "targeting", { "angle", "burst" }, {
    node("sling.precision.force", "build", "all_owned_marbles",
        "accelerate", "momentum_bonus", 1, "launch_force", { visibility = "expanded" }),
    node("sling.precision.target", "launch", "target_column",
        "target", "precision", true, "flag"),
}, {
    kind = "opportunity",
    stat = "launch_force",
    magnitude = 2,
    unit = "launch_force",
})

sling("effect_amplifier", "Effect Amplifier", "catalyst", { "field", "release" }, {
    node("sling.amplifier.force", "build", "all_owned_marbles",
        "accelerate", "momentum_bonus", 1, "launch_force", { visibility = "expanded" }),
    node("sling.amplifier.power", "non_chip_collision", "release_area",
        "amplify", "effect_power", 1, "count", { condition = "non_chip" }),
}, {
    kind = "risk",
    stat = "core_release",
    magnitude = 1,
    unit = "count",
})

-- Derived shell/core/brick sets ----------------------------------------------

local shell_specs = {
    jade_lattice = { durability = 2, collision = "chip", tags = { "tempo", "durable" } },
    obsidian_shard = { durability = 1, collision = "cleave", tags = { "burst" } },
    quartz_banded = { durability = 3, collision = "chip", tags = { "durable" } },
    flint_spiral = { durability = 2, collision = "splinter", tags = { "angle", "chain" } },
    silver_veined = { durability = 2, collision = "ward", tags = { "guard" } },
    granite_mottled = { durability = 3, collision = "heavy", tags = { "force", "durable" } },
    chalk_plain = { durability = 1, collision = "chip", tags = { "tempo", "release" } },
}

for id, spec in pairs(shell_specs) do
    local identity = rule_set(
        "shell.identity." .. id,
        id:gsub("_", " "),
        "shell",
        spec.tags,
        {
            node("shell." .. id .. ".durability", "build", "current_shell",
                "protect", "durability", spec.durability, "durability",
                { visibility = "expanded" }),
            node("shell." .. id .. ".collision", "build", "self",
                "set", "collision", spec.collision, "id", { visibility = "expanded" }),
        },
        { register = false }
    )
    M.shells[id] = derive({
        id = "shell." .. id,
        name = id:gsub("_", " "),
        role = "shell",
        synergy_tags = spec.tags,
        content_kind = "component",
        component_kind = "shell",
    }, { identity, M.collisions[spec.collision] })
end

local core_specs = {
    dull_quartz = {
        trajectory = 0, release = "baseline", min_rarity = "common",
        tags = { "tempo", "release" },
    },
    cant_pebble = {
        trajectory = -1, release = "baseline", min_rarity = "common",
        tags = { "angle", "control" },
    },
    skew_flint = {
        trajectory = 1, release = "baseline", min_rarity = "common",
        tags = { "angle", "burst" },
    },
    shrapnel_geode = {
        trajectory = 0, release = "shrapnel", min_rarity = "uncommon",
        tags = { "release", "chain" },
    },
    concussion_pearl = {
        trajectory = 1, release = "concussion", min_rarity = "rare",
        tags = { "release", "control" },
    },
    lodestone_heart = {
        trajectory = -1, release = "magnetize", min_rarity = "epic",
        tags = { "control", "field" },
    },
    cinder_nucleus = {
        trajectory = 0, release = "scorch", min_rarity = "legendary",
        tags = { "burst", "field" },
    },
}

for id, spec in pairs(core_specs) do
    local identity = rule_set(
        "core.identity." .. id,
        id:gsub("_", " "),
        "core",
        spec.tags,
        {
            node("core." .. id .. ".trajectory", "launch", "launch",
                "aim", "trajectory", spec.trajectory, "count", { visibility = "expanded" }),
            node("core." .. id .. ".release", "build", "self",
                "set", "release", spec.release, "id", { visibility = "expanded" }),
        },
        { register = false, component_kind = "core_identity" }
    )
    local release_sources = { M.releases.baseline }
    local abilities = {}
    if spec.release ~= "baseline" then
        release_sources[#release_sources + 1] = M.releases[spec.release]
        local rule_ids = {}
        for _, rule in ipairs(M.releases[spec.release].rules) do
            if rule.trigger.event == "core_release" then rule_ids[#rule_ids + 1] = rule.id end
        end
        abilities[1] = {
            id = spec.release,
            kind = "core_release",
            rule_ids = rule_ids,
        }
    end
    local sources = { identity }
    for _, source in ipairs(release_sources) do sources[#sources + 1] = source end
    M.cores[id] = derive({
        id = "core." .. id,
        name = id:gsub("_", " "),
        role = "core",
        synergy_tags = spec.tags,
        drawback = M.releases[spec.release].drawback,
        content_kind = "component",
        component_kind = "core",
        min_rarity = spec.min_rarity,
        abilities = abilities,
    }, sources)
end

local function availability(player)
    return {
        player_draft = player,
        player_reward = player,
        cpu_recipe = true,
        legacy_only = not player,
    }
end

local BRICK_ABILITIES = {
    inert = {},
    absorb = {},
    dummy = {},
    reflect = {
        { id = "reflect", kind = "passive", rule_ids = { "brick.reflect.rebound" } },
    },
    regenerate = {
        { id = "regenerate", kind = "passive", rule_ids = { "brick.regenerate.heal" } },
    },
    fortify = {
        { id = "fortify", kind = "passive", rule_ids = { "brick.fortify.protect" } },
    },
    poison = {
        {
            id = "poison_field", kind = "passive",
            rule_ids = {
                "brick.poison.status", "brick.poison.radius", "brick.poison.strength",
                "status.poison.duration", "status.poison.wear",
            },
        },
    },
    freeze = {
        {
            id = "freeze_field", kind = "passive",
            rule_ids = {
                "brick.freeze.status", "brick.freeze.radius", "brick.freeze.strength",
                "status.freeze.duration", "status.freeze.field_slow",
                "status.freeze.launch_slow",
            },
        },
    },
    magnetic = {
        {
            id = "magnetic_field", kind = "passive",
            rule_ids = { "brick.magnetic.radius", "brick.magnetic.strength" },
        },
    },
    shatter = {
        { id = "shatter", kind = "passive", rule_ids = { "brick.shatter.wear" } },
    },
    chain = {
        {
            id = "chain", kind = "passive",
            rule_ids = { "brick.chain.shell_wear" },
            recursion = {
                accepts_causes = { "hostile_collision", "shrapnel" },
                max_generation = 3,
            },
        },
    },
    vault = {
        { id = "vault", kind = "passive", rule_ids = { "brick.vault.force" } },
    },
    splice = {
        { id = "splice_guard", kind = "passive", rule_ids = { "brick.splice.guard" } },
    },
    aegis = {
        { id = "aegis", kind = "passive", rule_ids = { "brick.aegis.negate" } },
    },
    void = {
        { id = "void", kind = "passive", rule_ids = { "brick.void.break" } },
    },
    mirror = {
        {
            id = "prismatic_mirror", kind = "passive",
            rule_ids = { "brick.mirror.rebound", "brick.mirror.wear" },
        },
    },
    temporal = {
        { id = "temporal", kind = "passive", rule_ids = { "brick.temporal.rewind" } },
    },
}

local brick_specs = {
    plain_block = {
        hp = 2, restitution = 0.82, behaviour = "inert", rarity = "common",
        tags = { "durable" }, available = false,
    },
    chalk_block = {
        hp = 1, restitution = 0.90, behaviour = "inert", rarity = "common",
        tags = { "tempo" }, available = false,
    },
    basalt_absorber = {
        hp = 4, restitution = 0.68, behaviour = "absorb", rarity = "common",
        tags = { "guard", "durable" },
    },
    training_dummy = {
        hp = 2, restitution = 1.04, behaviour = "dummy", rarity = "common",
        tags = { "tempo" },
    },
    mirror_pane = {
        hp = 2, restitution = 0.88, behaviour = "reflect", rarity = "uncommon",
        tags = { "rebound", "guard" },
    },
    moss_regenerator = {
        hp = 3, restitution = 0.76, behaviour = "regenerate", rarity = "uncommon",
        tags = { "sustain" },
    },
    granite_fortifier = {
        hp = 2, restitution = 0.72, behaviour = "fortify", rarity = "uncommon",
        tags = { "guard", "depth" },
    },
    shatter_crystal = {
        hp = 2, restitution = 0.94, behaviour = "shatter", rarity = "uncommon",
        tags = { "burst" },
    },
    vault_arch = {
        hp = 2, restitution = 0.84, behaviour = "vault", rarity = "uncommon",
        tags = { "force", "depth" },
    },
    venom_glass = {
        hp = 1, restitution = 0.92, behaviour = "poison", rarity = "rare",
        tags = { "control", "field" },
    },
    rime_block = {
        hp = 1, restitution = 0.90, behaviour = "freeze", rarity = "rare",
        tags = { "control", "field" },
    },
    lodestone_block = {
        hp = 2, restitution = 0.70, behaviour = "magnetic", rarity = "rare",
        tags = { "control", "field" },
    },
    powder_keg = {
        hp = 1, restitution = 0.86, behaviour = "chain", rarity = "rare",
        tags = { "chain", "burst" },
    },
    splice_node = {
        hp = 2, restitution = 0.74, behaviour = "splice", rarity = "rare",
        tags = { "guard", "depth" },
    },
    aegis_keystone = {
        hp = 2, restitution = 0.70, behaviour = "aegis", rarity = "epic",
        tags = { "guard", "sustain" },
    },
    void_prism = {
        hp = 1, restitution = 0.96, behaviour = "void", rarity = "epic",
        tags = { "control", "burst" },
    },
    prismatic_mirror = {
        hp = 2, restitution = 0.90, behaviour = "mirror", rarity = "epic",
        tags = { "rebound", "guard" },
    },
    temporal_anchor = {
        hp = 2, restitution = 0.66, behaviour = "temporal", rarity = "legendary",
        tags = { "sustain", "depth" }, rear_row = true,
    },
}

for id, spec in pairs(brick_specs) do
    local identity = rule_set(
        "brick.identity." .. id,
        id:gsub("_", " "),
        "brick",
        spec.tags,
        {
            node("brick." .. id .. ".hp", "build", "self",
                "protect", "hp", spec.hp, "hp", { visibility = "expanded" }),
            node("brick." .. id .. ".restitution", "build", "self",
                "set", "restitution", spec.restitution, "multiplier",
                { visibility = "expanded" }),
            node("brick." .. id .. ".behaviour", "build", "self",
                "set", "behaviour", spec.behaviour, "id", { visibility = "expanded" }),
        },
        {
            register = false,
            component_kind = "brick_identity",
        }
    )
    local sources = { identity, M.brick_behaviours[spec.behaviour] }
    if M.statuses[spec.behaviour] then
        sources[#sources + 1] = M.statuses[spec.behaviour]
    end
    M.bricks[id] = derive({
        id = "brick." .. id,
        name = id:gsub("_", " "),
        role = M.brick_behaviours[spec.behaviour].role,
        synergy_tags = spec.tags,
        content_kind = "brick",
        rarity = spec.rarity,
        availability = availability(spec.available ~= false),
        abilities = BRICK_ABILITIES[spec.behaviour],
        formation = spec.rear_row and { rear_row = true } or nil,
        compatibility = {
            requires = {},
            excludes = {},
            max_copies = ast.tier(spec.rarity).brick_copy_cap,
        },
    }, sources)
end

return M
