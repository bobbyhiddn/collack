-- battle/content/shells.lua — hardcoded shell definitions.
--
-- A shell is one layer of a marble. It supplies mineral, pattern, a collision
-- effect (looked up in battle/effects.lua) and durability. Durability is spent
-- by collisions; at zero the shell breaks and the next shell inward becomes the
-- outermost. When the last shell breaks the core is exposed and released.

local SHELLS = {
    {
        id = "jade_lattice",
        mineral = "jade",
        pattern = "lattice",
        collision = "chip",
        durability = 2,
    },
    {
        id = "obsidian_shard",
        mineral = "obsidian",
        pattern = "shard",
        collision = "cleave",
        durability = 1,
    },
    {
        id = "quartz_banded",
        mineral = "quartz",
        pattern = "banded",
        collision = "chip",
        durability = 3,
    },
    {
        id = "flint_spiral",
        mineral = "flint",
        pattern = "spiral",
        collision = "splinter",
        durability = 2,
    },
    {
        id = "silver_veined",
        mineral = "silver",
        pattern = "veined",
        collision = "ward",
        durability = 2,
    },
    {
        id = "granite_mottled",
        mineral = "granite",
        pattern = "mottled",
        collision = "heavy",
        durability = 3,
    },
    {
        id = "chalk_plain",
        mineral = "chalk",
        pattern = "plain",
        collision = "chip",
        durability = 1,
    },
}

local by_id = {}
for _, shell in ipairs(SHELLS) do
    by_id[shell.id] = shell
end

return {
    list = SHELLS,
    by_id = by_id,
}
