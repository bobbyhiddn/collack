-- battle/content/bricks.lua — hardcoded brick archetypes.
--
-- Bricks are static formation elements with BEHAVIOUR, not just hit points.
-- Four archetypes ship here:
--
--   inert   — the control. Takes damage, dies, does nothing else. Every other
--             archetype is measured against this one.
--   absorb  — soaks 1 point off every incoming hit and grinds an extra point of
--             durability off the shell that hit it. Attrition, not a wall.
--   reflect — survives a hit and throws the marble back the way it came,
--             flipping its lateral trajectory. Dies like anything else.
--   chain   — detonates on death and damages its orthogonal neighbours, which
--             can detonate in turn (depth-capped in the engine).
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
        behaviour = "absorb",
        hp = 3,
    },
    {
        id = "mirror_pane",
        name = "Mirror Pane",
        behaviour = "reflect",
        hp = 2,
    },
    {
        id = "powder_keg",
        name = "Powder Keg",
        behaviour = "chain",
        hp = 1,
        chain_damage = 2,
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
