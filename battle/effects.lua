-- battle/effects.lua — collision profiles and release profiles.
--
-- Kept as plain data rather than functions so a battle's whole rule surface can
-- be read in one screen, and so nothing here can accidentally reach for global
-- state or a random source.

local M = {}

-- Collision profiles, referenced by shell.collision.
--   damage         — base damage dealt to the brick.
--   momentum_cost  — momentum spent by the collision (1 = normal).
--   durability_cost— durability ground off the shell that hit.
--   pierces_absorb — if true, an absorb brick does not reduce this damage.
--   splash_behind  — damage also dealt to the brick one row further back.
M.collision = {
    chip = {
        id = "chip",
        damage = 1,
        momentum_cost = 1,
        durability_cost = 1,
        pierces_absorb = false,
        splash_behind = 0,
    },
    cleave = {
        id = "cleave",
        damage = 2,
        momentum_cost = 1,
        durability_cost = 1,
        pierces_absorb = false,
        splash_behind = 0,
    },
    splinter = {
        id = "splinter",
        damage = 1,
        momentum_cost = 1,
        durability_cost = 1,
        pierces_absorb = false,
        splash_behind = 1,
    },
    ward = {
        id = "ward",
        damage = 1,
        momentum_cost = 1,
        durability_cost = 1,
        pierces_absorb = true,
        splash_behind = 0,
    },
    heavy = {
        id = "heavy",
        damage = 2,
        momentum_cost = 2,
        durability_cost = 1,
        pierces_absorb = false,
        splash_behind = 0,
    },
}

-- Release profiles, referenced by core.release. nil release == baseline only.
--   radius        — blowback radius in lanes.
--   invert        — displace toward the epicentre instead of away from it.
--   scorch        — displaced marbles also lose 1 durability.
--   shrapnel      — damage dealt to bricks orthogonally adjacent to the release
--                   point, 0 for none.
--
-- BASELINE is what a common core produces, and it is also the floor for every
-- other core: a release profile adds to baseline, it never turns displacement
-- off. Friendly displacement is not optional.
M.BASELINE_RELEASE = {
    id = "baseline",
    radius = 1,
    invert = false,
    scorch = false,
    shrapnel = 0,
}

M.release = {
    shrapnel = {
        id = "shrapnel",
        radius = 1,
        invert = false,
        scorch = false,
        shrapnel = 1,
    },
    concussion = {
        id = "concussion",
        radius = 2,
        invert = false,
        scorch = false,
        shrapnel = 0,
    },
    magnetize = {
        id = "magnetize",
        radius = 1,
        invert = true,
        scorch = false,
        shrapnel = 0,
    },
    scorch = {
        id = "scorch",
        radius = 1,
        invert = false,
        scorch = true,
        shrapnel = 0,
    },
}

--- Resolve a core's release id into a concrete profile.
--- A nil id yields baseline. An unknown id is a content bug and raises.
function M.release_profile(release_id)
    if release_id == nil then
        return M.BASELINE_RELEASE
    end
    local profile = M.release[release_id]
    if not profile then
        error("unknown release effect: " .. tostring(release_id))
    end
    return profile
end

--- Resolve a shell's collision id into a concrete profile.
function M.collision_profile(collision_id)
    local profile = M.collision[collision_id]
    if not profile then
        error("unknown collision effect: " .. tostring(collision_id))
    end
    return profile
end

return M
