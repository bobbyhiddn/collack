-- battle/content/slings.lua — hardcoded sling definitions.
--
-- A sling modifies EVERY marble in the hand it is loaded with. Marble-local
-- modifiers are applied once at build time. shots_per_volley belongs to the
-- player because it changes commitment cadence, not marble stats.
--
--   damage_bonus     — added to every collision's damage.
--   durability_bonus — added to every shell's durability.
--   momentum_bonus   — added to launch impulse and mass tuning.
--   aim              — added to the core's continuous launch-angle bias.
--   scatter          — deterministic launch-angle variance; 0 is exact aim.

local SLINGS = {
    {
        id = "training_sling",
        name = "Training Sling",
        damage_bonus = 0,
        durability_bonus = 0,
        momentum_bonus = 1,
        aim = 0,
        scatter = 1,
    },
    {
        id = "tuned_sling",
        name = "Tuned Sling",
        damage_bonus = 0,
        durability_bonus = 1,
        momentum_bonus = 1,
        aim = 0,
        scatter = 0,
    },
    {
        id = "heavy_sling",
        name = "Heavy Sling",
        damage_bonus = 1,
        durability_bonus = 0,
        momentum_bonus = 0,
        aim = 0,
        scatter = 1,
    },
    {
        id = "raker_sling",
        name = "Raker Sling",
        damage_bonus = 0,
        durability_bonus = 0,
        momentum_bonus = 2,
        aim = 1,
        scatter = 1,
    },
    {
        id = "volley",
        name = "Volley Sling",
        archetype = "volley",
        shots_per_volley = 2,
        damage_bonus = 0,
        durability_bonus = 0,
        momentum_bonus = 0,
        aim = 0,
        scatter = 0,
    },
    {
        id = "momentum",
        name = "Momentum Sling",
        archetype = "momentum",
        shots_per_volley = 1,
        damage_bonus = 0,
        durability_bonus = 0,
        momentum_bonus = 3,
        aim = 0,
        scatter = 0,
    },
    {
        id = "ricochet",
        name = "Ricochet Sling",
        archetype = "ricochet",
        shots_per_volley = 1,
        damage_bonus = 0,
        durability_bonus = 0,
        momentum_bonus = 1,
        aim = 0,
        scatter = 0,
        ricochet = true,
    },
    {
        id = "spread",
        name = "Spread Sling",
        archetype = "spread",
        shots_per_volley = 1,
        damage_bonus = 0,
        durability_bonus = 0,
        momentum_bonus = 1,
        aim = 0,
        scatter = 2,
    },
    {
        id = "precision",
        name = "Precision Sling",
        archetype = "precision",
        shots_per_volley = 1,
        damage_bonus = 0,
        durability_bonus = 0,
        momentum_bonus = 1,
        aim = 0,
        scatter = 0,
        precision = true,
    },
    {
        id = "effect_amplifier",
        name = "Effect Amplifier",
        archetype = "effect_amplifier",
        shots_per_volley = 1,
        damage_bonus = 0,
        durability_bonus = 0,
        momentum_bonus = 1,
        aim = 0,
        scatter = 0,
        effect_power = 1,
    },
}

local by_id = {}
for _, sling in ipairs(SLINGS) do
    by_id[sling.id] = sling
end

return {
    list = SLINGS,
    by_id = by_id,
}
