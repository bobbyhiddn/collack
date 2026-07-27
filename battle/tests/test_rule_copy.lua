-- Compact cards and expanded inspection copy are pure AST projections.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../../src/?.lua",
    here .. "/../?.lua",
    "./?.lua",
    "./src/?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local ast = require("battle.rule_ast")
local content = require("battle.content.draft")
local art = require("ui.art_tokens")

local M = { name = "rule_copy" }

local function same_lines(left, right)
    if #left ~= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    return true
end

function M.run(t)
    local momentum = content.sling_by_id.momentum
    t:eq(
        momentum.compact_copy,
        "Always, give every marble in the bag +3 launch force.",
        "compact sling copy is stable and plain-language"
    )
    t:eq(momentum.inspection_copy[1], "Role: pressure.",
        "expanded copy starts with the authored role")
    t:eq(momentum.inspection_copy[#momentum.inspection_copy],
        "Balance: 7.400 of 100.000 points.",
        "expanded copy includes deterministic balance accounting")
    t:ok(momentum.inspection_copy[3]:find("Tradeoff:", 1, true) ~= nil,
        "expanded sling copy exposes its real opportunity cost")

    for _, entry in ipairs(content.COMPREHENSION_POOL) do
        local lookup = entry.category == "sling" and content.sling_by_id
            or entry.category == "marble" and content.marble_by_id
            or content.brick_kit_by_id
        local item = lookup[entry.id]
        t:eq(item.compact_copy, ast.compact(item.rule_set),
            entry.id .. " compact copy is generated")
        t:ok(same_lines(item.mechanics, ast.compact_lines(item.rule_set)),
            entry.id .. " card lines are generated")
        t:ok(same_lines(item.inspection_copy, ast.expanded_lines(item.rule_set)),
            entry.id .. " inspection lines are generated")
    end

    local changed = ast.copy(momentum.rule_set)
    changed.rules[1].magnitude.value = 4
    t:eq(ast.compact(changed),
        "Always, give every marble in the bag +4 launch force.",
        "copy changes directly with executable magnitude")
    t:neq(ast.balance(changed).spent, momentum.balance.spent,
        "the same magnitude change reaches balance accounting")

    for id, token in pairs(art.behaviour) do
        t:eq(token.description, nil,
            id .. " art token carries no duplicate mechanics prose")
    end
end

if arg and arg[0] and arg[0]:find("test_rule_copy.lua", 1, true) then
    harness.run_one(M)
end

return M
