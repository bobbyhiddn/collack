-- battle/tests/fixtures.lua — hand-built setups for the constructed scenarios.
--
-- The tests that check a specific mechanic use these rather than the demo
-- matchup, so each one exercises exactly one thing with no randomness in the
-- way. TIGHT_SLING has scatter 0 on purpose: a scatter roll would move the
-- entry column and make "the marble hits this brick" a probabilistic claim.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local F = {}

F.TIGHT_SLING = {
    id = "test_tight_sling",
    name = "Test Tight Sling",
    damage_bonus = 0,
    durability_bonus = 0,
    momentum_bonus = 0,
    aim = 0,
    scatter = 0,
}

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
