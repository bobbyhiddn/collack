-- Compatibility constraints are canonical data, not draft-only conditionals.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local ast = require("battle.rule_ast")
local content = require("battle.content.draft")

local M = { name = "rule_compatibility" }

local function contains(errors, fragment)
    for _, message in ipairs(errors or {}) do
        if message:find(fragment, 1, true) then return true end
    end
    return false
end

function M.run(t)
    local momentum = ast.copy(content.sling_by_id.momentum.rule_set)
    local ricochet = ast.copy(content.sling_by_id.ricochet.rule_set)
    local compatible, reason = ast.compatible(momentum, ricochet)
    t:ok(compatible, reason or "the approved sling rules are compatible")

    momentum.compatibility.excludes = { "tag:rebound" }
    compatible, reason = ast.compatible(momentum, ricochet)
    t:eq(compatible, false, "tag exclusions are enforced")
    t:eq(reason, momentum.id .. " excludes tag:rebound",
        "exclusion reasons are stable and actionable")

    momentum.compatibility.excludes = {}
    momentum.compatibility.requires = { "tag:field" }
    local valid, errors = ast.validate_collection({ momentum, ricochet })
    t:eq(valid, false, "missing synergy requirements reject a collection")
    t:ok(contains(errors, "requires tag:field"),
        "missing requirements identify the exact token")

    local amplifier = ast.copy(content.sling_by_id.effect_amplifier.rule_set)
    valid, errors = ast.validate_collection({ momentum, ricochet, amplifier })
    t:ok(valid, table.concat(errors or {}, "; "))

    local duplicate = ast.copy(ricochet)
    valid, errors = ast.validate_collection({ ricochet, duplicate })
    t:eq(valid, false, "max_copies is enforced")
    t:ok(contains(errors, "exceeds max_copies"),
        "copy-limit failures identify the canonical rule set")

    local _, first = ast.validate_collection({ duplicate, ricochet })
    local _, second = ast.validate_collection({ ricochet, duplicate })
    t:eq(table.concat(first, "|"), table.concat(second, "|"),
        "compatibility errors are deterministically ordered")
end

if arg and arg[0] and arg[0]:find("test_rule_compatibility.lua", 1, true) then
    harness.run_one(M)
end

return M
