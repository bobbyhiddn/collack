-- Runtime profiles compiled from the canonical rule AST.

local ast = require("battle.rule_ast")
local rulebook = require("battle.content.rules")

local M = {}

local function assert_identity(kind, id, profile, stat)
    if profile[stat] ~= id then
        error(string.format(
            "%s profile %s is absent from canonical RuleSet %s",
            kind,
            tostring(id),
            tostring(profile._rule_set_id)
        ))
    end
    return profile
end

local function normalize_collision(id, rule_set)
    local profile = ast.project_prefix(rule_set, "collision." .. id .. ".")
    assert_identity("collision", id, profile, "collision")
    profile.id = id
    profile.pierces_absorb = profile.pierces_absorb == true
    profile.splash_behind = profile.splash_behind or 0
    profile.durability_cost = profile.durability_cost or 0
    return profile
end

local function normalize_release(id, rule_set)
    local profile = ast.project_prefix(rule_set, "release.")
    assert_identity("release", id, profile, "release")
    profile.id = id
    profile.invert = profile.invert == true
    profile.scorch = profile.scorch or 0
    profile.shrapnel = profile.shrapnel or 0
    return profile
end

local function normalize_status(id, rule_set)
    local profile = ast.project_prefix(rule_set, "status." .. id .. ".")
    return assert_identity("status", id, profile, "status")
end

function M.release_profile(release_id, source_rule_set)
    local id = release_id or "baseline"
    local rule_set = source_rule_set or rulebook.releases[id]
    if not rule_set then error("unknown release effect: " .. tostring(release_id)) end
    return normalize_release(id, rule_set)
end

function M.collision_profile(collision_id, source_rule_set)
    local rule_set = source_rule_set or rulebook.collisions[collision_id]
    if not rule_set then error("unknown collision effect: " .. tostring(collision_id)) end
    return normalize_collision(collision_id, rule_set)
end

function M.brick_profile(behaviour, source_rule_set)
    local rule_set = source_rule_set or rulebook.brick_behaviours[behaviour]
    if not rule_set then error("unknown brick behaviour: " .. tostring(behaviour)) end
    return assert_identity("brick", behaviour, ast.project(rule_set), "behaviour")
end

function M.status_profile(status_id, source_rule_set)
    local rule_set = source_rule_set or rulebook.statuses[status_id]
    if not rule_set then error("unknown marble status: " .. tostring(status_id)) end
    return normalize_status(status_id, rule_set)
end

return M
