-- Runtime profiles compiled from the canonical rule AST.

local ast = require("battle.rule_ast")
local rulebook = require("battle.content.rules")

local M = {}

local function merge_profiles(base, overlay)
    local out = {}
    for key, value in pairs(base or {}) do out[key] = ast.copy(value) end
    for key, value in pairs(overlay or {}) do
        if key ~= "_rule_ids" and key ~= "_cadence" then out[key] = ast.copy(value) end
    end
    out._rule_ids = {}
    for stat, ids in pairs((base and base._rule_ids) or {}) do
        out._rule_ids[stat] = ast.copy(ids)
    end
    for stat, ids in pairs((overlay and overlay._rule_ids) or {}) do
        out._rule_ids[stat] = ast.copy(ids)
    end
    out._cadence = {}
    for stat, cadence in pairs((base and base._cadence) or {}) do
        out._cadence[stat] = ast.copy(cadence)
    end
    for stat, cadence in pairs((overlay and overlay._cadence) or {}) do
        out._cadence[stat] = ast.copy(cadence)
    end
    return out
end

M.brick = {}
for id, rule_set in pairs(rulebook.brick_behaviours) do
    M.brick[id] = ast.project(rule_set)
end

M.collision = {}
for id, rule_set in pairs(rulebook.collisions) do
    local profile = ast.project(rule_set)
    profile.id = profile.collision
    profile.pierces_absorb = profile.pierces_absorb == true
    profile.splash_behind = profile.splash_behind or 0
    profile.durability_cost = profile.durability_cost or 0
    M.collision[id] = profile
end

M.BASELINE_RELEASE = ast.project(rulebook.releases.baseline)
M.BASELINE_RELEASE.id = "baseline"
M.BASELINE_RELEASE.invert = M.BASELINE_RELEASE.invert == true
M.BASELINE_RELEASE.scorch = M.BASELINE_RELEASE.scorch or 0
M.BASELINE_RELEASE.shrapnel = M.BASELINE_RELEASE.shrapnel or 0

M.release = {}
for id, rule_set in pairs(rulebook.releases) do
    if id ~= "baseline" then
        local profile = merge_profiles(M.BASELINE_RELEASE, ast.project(rule_set))
        profile.id = id
        profile.invert = profile.invert == true
        profile.scorch = profile.scorch or 0
        profile.shrapnel = profile.shrapnel or 0
        M.release[id] = profile
    end
end

M.status = {}
for id, rule_set in pairs(rulebook.statuses) do
    M.status[id] = ast.project(rule_set)
end

function M.release_profile(release_id)
    if release_id == nil or release_id == "baseline" then return M.BASELINE_RELEASE end
    local profile = M.release[release_id]
    if not profile then error("unknown release effect: " .. tostring(release_id)) end
    return profile
end

function M.collision_profile(collision_id)
    local profile = M.collision[collision_id]
    if not profile then error("unknown collision effect: " .. tostring(collision_id)) end
    return profile
end

function M.brick_profile(behaviour)
    local profile = M.brick[behaviour]
    if not profile then error("unknown brick behaviour: " .. tostring(behaviour)) end
    return profile
end

function M.status_profile(status_id)
    local profile = M.status[status_id]
    if not profile then error("unknown marble status: " .. tostring(status_id)) end
    return profile
end

return M
