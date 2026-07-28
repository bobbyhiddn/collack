-- The rule grammar rejects data outside its bounded executable vocabulary.

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

local M = { name = "rule_schema" }

local function has_error(errors, fragment)
    for _, message in ipairs(errors or {}) do
        if message:find(fragment, 1, true) then return true end
    end
    return false
end

function M.run(t)
    t:eq(ast.SCHEMA_VERSION, 2, "the executable grammar is explicitly versioned")

    for _, entry in ipairs(content.COMPREHENSION_POOL) do
        local lookup = entry.category == "sling" and content.sling_by_id
            or entry.category == "marble" and content.marble_by_id
            or content.brick_kit_by_id
        local item = lookup[entry.id]
        local valid, errors = ast.validate(item.rule_set)
        t:ok(valid, entry.id .. " validates: " .. table.concat(errors or {}, "; "))
        t:eq(item.rule_set.kind, "rule_set", entry.id .. " uses the canonical data contract")
        t:ok(type(item.rule_set.role) == "string", entry.id .. " declares a role")
        t:ok(type(item.rule_set.drawback.kind) == "string", entry.id .. " declares a drawback")
        t:ok(type(item.rule_set.compatibility.max_copies) == "number",
            entry.id .. " declares compatibility")
        t:ok(#item.rule_set.synergy_tags > 0, entry.id .. " declares synergy tags")
        for _, rule in ipairs(item.rule_set.rules) do
            t:ok(rule.trigger.event and rule.trigger.phase,
                rule.id .. " declares a trigger")
            t:ok(rule.condition.predicate, rule.id .. " declares a condition")
            t:ok(rule.target.selector, rule.id .. " declares a selector")
            t:ok(rule.operation.verb and rule.operation.stat,
                rule.id .. " declares an observable operation")
            t:ok(rule.magnitude ~= nil or rule.duration ~= nil,
                rule.id .. " declares magnitude or duration")
            t:ok(rule.cadence.unit and rule.cadence.interval,
                rule.id .. " declares cadence")
            t:ok(rule.cost.kind, rule.id .. " declares rule-level cost")
        end
    end

    local source = content.SLINGS[1].rule_set
    t:eq(ast.canonical(ast.copy(source)), ast.canonical(source),
        "canonical serialization is independent of table identity")

    local unknown_field = ast.copy(source)
    unknown_field.presentation_hint = "meaning"
    local valid, errors = ast.validate(unknown_field)
    t:eq(valid, false, "presentation-only meaning is rejected by the schema")
    t:ok(has_error(errors, "unknown field presentation_hint"),
        "unknown schema fields produce an actionable error")

    local unknown_verb = ast.copy(source)
    unknown_verb.rules[1].operation.verb = "improvise"
    valid, errors = ast.validate(unknown_verb)
    t:eq(valid, false, "unimplemented verbs are rejected")
    t:ok(has_error(errors, "operation.verb is outside the canonical vocabulary"),
        "verb errors identify the bounded vocabulary")

    local wrong_signature = ast.copy(source)
    wrong_signature.rules[1].operation.verb = "wear"
    valid, errors = ast.validate(wrong_signature)
    t:eq(valid, false, "known verbs cannot be attached to unrelated runtime stats")
    t:ok(has_error(errors, "verb/stat combination is not executable"),
        "semantic operation errors identify the unsupported signature")

    local missing_target = ast.copy(source)
    missing_target.rules[1].target = nil
    valid, errors = ast.validate(missing_target)
    t:eq(valid, false, "rules without selectors are rejected")
    t:ok(has_error(errors, ".target must be a table"),
        "missing selectors are reported at their schema path")

    local missing_id = ast.copy(source)
    missing_id.rules[1].id = nil
    valid, errors = ast.validate(missing_id)
    t:eq(valid, false, "missing rule IDs return validation errors instead of raising")
    t:ok(has_error(errors, ".id must be a non-empty string"),
        "missing IDs are reported at their schema path")

    local over_budget = ast.copy(source)
    over_budget.rarity_budget = 0
    valid, errors = ast.validate(over_budget)
    t:eq(valid, false, "rules cannot silently exceed their rarity budget")
    t:ok(has_error(errors, "exceeds rarity budget"),
        "budget validation reports the accounted overage")
end

if arg and arg[0] and arg[0]:find("test_rule_schema.lua", 1, true) then
    harness.run_one(M)
end

return M
