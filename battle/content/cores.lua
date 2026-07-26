-- battle/content/cores.lua — hardcoded core definitions.
--
-- A core is the centre of a marble. It supplies:
--   * trajectory — the marble's lateral bias per row of travel.
--                  negative = drifts left, positive = drifts right, 0 = straight.
--   * release    — the effect fired when the marble's last shell breaks and the
--                  core is exposed. nil means "baseline blowback only", which
--                  is what every common core gets. Uncommon and above add one
--                  release effect ON TOP of baseline blowback; baseline
--                  blowback is never replaced or skipped.
--
-- min_rarity is the lowest marble rarity this core may appear in. It exists so
-- the "common cores get baseline blowback only" rule is checked by data, not
-- by trusting whoever writes a marble definition.

local CORES = {
    {
        id = "dull_quartz",
        name = "Dull Quartz",
        min_rarity = "common",
        trajectory = 0,
        release = nil,
    },
    {
        id = "cant_pebble",
        name = "Cant Pebble",
        min_rarity = "common",
        trajectory = -1,
        release = nil,
    },
    {
        id = "skew_flint",
        name = "Skew Flint",
        min_rarity = "common",
        trajectory = 1,
        release = nil,
    },
    {
        id = "shrapnel_geode",
        name = "Shrapnel Geode",
        min_rarity = "uncommon",
        trajectory = 0,
        -- Sprays the bricks orthogonally adjacent to the release point.
        release = "shrapnel",
    },
    {
        id = "concussion_pearl",
        name = "Concussion Pearl",
        min_rarity = "rare",
        trajectory = 1,
        -- Doubles the blowback radius. Hits more of your own rack too.
        release = "concussion",
    },
    {
        id = "lodestone_heart",
        name = "Lodestone Heart",
        min_rarity = "epic",
        trajectory = -1,
        -- Inverts blowback: marbles are pulled toward the epicentre instead of
        -- shoved away. Still a displacement, still hits both racks — it just
        -- makes clusters tighter rather than looser.
        release = "magnetize",
    },
    {
        id = "cinder_nucleus",
        name = "Cinder Nucleus",
        min_rarity = "legendary",
        trajectory = 0,
        -- Everything the blowback displaces is also scorched for 1 durability.
        release = "scorch",
    },
}

local by_id = {}
for _, core in ipairs(CORES) do
    by_id[core.id] = core
end

return {
    list = CORES,
    by_id = by_id,
}
