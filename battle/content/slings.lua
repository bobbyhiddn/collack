-- battle/content/slings.lua — hardcoded sling definitions.
--
-- A sling modifies EVERY marble in the hand it is loaded with. The modifiers
-- are applied once, at marble-build time, so a marble's printed stats already
-- include its sling. Nothing re-reads the sling mid-battle.
--
--   damage_bonus     — added to every collision's damage.
--   durability_bonus — added to every shell's durability.
--   momentum_bonus   — added to launch momentum (how many collisions a marble
--                      can push through before it comes to rest).
--   aim              — added to the core's trajectory. Lets a sling correct or
--                      exaggerate a core's drift.
--   scatter          — half-width of the random launch scatter, in lanes.
--                      0 means the sling never misses its lane.

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
}

local by_id = {}
for _, sling in ipairs(SLINGS) do
    by_id[sling.id] = sling
end

return {
    list = SLINGS,
    by_id = by_id,
}
