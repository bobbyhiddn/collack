-- Adversarial identity and mutation checks for the exact 17-item packet.

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
local catalog = require("battle.content.draft")
local rulebook = require("battle.content.rules")
local effects = require("battle.effects")
local slings = require("battle.content.slings")
local cores = require("battle.content.cores")
local shells = require("battle.content.shells")
local bricks = require("battle.content.bricks")
local util = require("battle.run_util")

local M = { name = "canonical_rule_identity" }

local function item_for(entry)
    local lookup = entry.category == "sling" and catalog.sling_by_id
        or entry.category == "marble" and catalog.marble_by_id
        or catalog.brick_kit_by_id
    return assert(lookup[entry.id])
end

local function add_rule_set_ids(out, rule_set)
    for _, rule_id in ipairs(ast.player_rule_ids(rule_set)) do out[rule_id] = true end
end

local function count_keys(values)
    local count = 0
    for _ in pairs(values) do count = count + 1 end
    return count
end

local function contains(values, wanted)
    for _, value in ipairs(values or {}) do
        if value == wanted then return true end
    end
    return false
end

local function runtime_profiles(entry, item)
    local profiles = {}
    if entry.category == "sling" then
        profiles[#profiles + 1] = slings.by_id[item.id]
    elseif entry.category == "marble" then
        local core = cores.by_id[item.core]
        profiles[#profiles + 1] = ast.project(core.rule_set)
        profiles[#profiles + 1] = effects.release_profile(core.release)
        for _, shell_id in ipairs(item.shells) do
            local shell = shells.by_id[shell_id]
            profiles[#profiles + 1] = ast.project(shell.rule_set)
            profiles[#profiles + 1] = effects.collision_profile(shell.collision)
        end
    else
        for _, brick_id in ipairs(item.brick_ids) do
            local brick = bricks.by_id[brick_id]
            profiles[#profiles + 1] = ast.project(brick.rule_set)
            profiles[#profiles + 1] = effects.brick_profile(brick.behaviour)
            if brick.behaviour == "poison" or brick.behaviour == "freeze" then
                profiles[#profiles + 1] = effects.status_profile(brick.behaviour)
            end
        end
    end
    return profiles
end

local function component_ids(entry, item)
    local ids = {}
    if entry.category == "sling" then
        add_rule_set_ids(ids, slings.by_id[item.id].rule_set)
    elseif entry.category == "marble" then
        add_rule_set_ids(ids, cores.by_id[item.core].rule_set)
        for _, shell_id in ipairs(item.shells) do
            add_rule_set_ids(ids, shells.by_id[shell_id].rule_set)
        end
    else
        for _, brick_id in ipairs(item.brick_ids) do
            add_rule_set_ids(ids, bricks.by_id[brick_id].rule_set)
        end
    end
    return ids
end

local function balance_line(balance, rule_id)
    for _, line in ipairs(balance.lines or {}) do
        if line.rule_id == rule_id then return line end
    end
    return nil
end

local STRING_ALTERNATIVE = {
    behaviour = "inert",
    collision = "chip",
    release = "baseline",
    status = "poison",
}

local function changed_value(rule)
    local quantity = rule.magnitude or rule.duration
    if type(quantity.value) == "number" then return quantity.value + 0.001 end
    if type(quantity.value) == "boolean" then return not quantity.value end
    local alternative = STRING_ALTERNATIVE[rule.operation.stat] or "canonical_alternative"
    if alternative == quantity.value then alternative = alternative .. "_other" end
    return alternative
end

local function mutate_rule(rule_set, rule_id, value)
    local changed = ast.copy(rule_set)
    for _, rule in ipairs(changed.rules) do
        if rule.id == rule_id then
            (rule.magnitude or rule.duration).value = value
            return changed
        end
    end
    error("missing rule to mutate: " .. tostring(rule_id))
end

local function all_runtime_rule_sets()
    local out, seen = {}, {}
    local groups = {
        "slings",
        "collisions",
        "releases",
        "statuses",
        "brick_behaviours",
        "shells",
        "cores",
        "bricks",
    }
    for _, group in ipairs(groups) do
        for _, rule_set in pairs(rulebook[group]) do
            if not seen[rule_set] then
                seen[rule_set] = true
                out[#out + 1] = rule_set
            end
        end
    end
    for _, entry in ipairs(catalog.COMPREHENSION_POOL) do
        local rule_set = item_for(entry).rule_set
        if not seen[rule_set] then
            seen[rule_set] = true
            out[#out + 1] = rule_set
        end
    end
    return out
end

local function has_error(errors, fragment)
    for _, message in ipairs(errors or {}) do
        if message:find(fragment, 1, true) then return true end
    end
    return false
end

function M.run(t)
    local checked_items = 0
    for _, entry in ipairs(catalog.COMPREHENSION_POOL) do
        checked_items = checked_items + 1
        local key = entry.category .. ":" .. entry.id
        local item = item_for(entry)
        local authority = ast.player_authority(item.rule_set)
        local authority_ids = {}

        t:eq(#authority.rule_ids, #authority.rules,
            key .. " exposes every canonical structured rule")
        t:eq(
            #authority.balance.lines,
            #authority.rule_ids + #item.rule_set.abilities,
            key .. " accounts every canonical structured rule and ability MCU"
        )
        for index, rule_id in ipairs(authority.rule_ids) do
            t:eq(authority_ids[rule_id], nil,
                key .. " rejects duplicate/helper-inflated ID " .. rule_id)
            authority_ids[rule_id] = true
            t:eq(rule_id:match("^card%."), nil,
                key .. " does not manufacture a card-prefixed rule ID")
            local resolved = ast.resolve(rule_id)
            t:ok(resolved ~= nil, key .. " resolves canonical ID " .. rule_id)
            t:eq(resolved and resolved.rule.id, rule_id,
                key .. " resolves the exact canonical node " .. rule_id)
            t:ok(ast.belongs_to(rule_id, item.rule_set.id),
                key .. " registers exact item membership for " .. rule_id)
            t:eq(authority.balance.lines[index].rule_id, rule_id,
                key .. " keeps accounting in canonical ID order")
            t:eq(authority.balance.lines[index].value,
                (authority.rules[index].magnitude or authority.rules[index].duration).value,
                key .. " accounting exposes the mechanical value for " .. rule_id)
        end

        local components = component_ids(entry, item)
        t:eq(count_keys(components), #authority.rule_ids,
            key .. " composition neither shadows nor inflates component rules")
        for rule_id in pairs(components) do
            t:ok(authority_ids[rule_id],
                key .. " owns canonical component rule " .. rule_id)
        end

        local attributed = 0
        for _, profile in ipairs(runtime_profiles(entry, item)) do
            for stat, rule_ids in pairs(profile._rule_ids or {}) do
                local profile_seen = {}
                for _, rule_id in ipairs(rule_ids) do
                    t:eq(profile_seen[rule_id], nil,
                        key .. " runtime profile rejects helper inflation for " .. rule_id)
                    profile_seen[rule_id] = true
                    t:ok(authority_ids[rule_id],
                        key .. " runtime rule belongs to the exact item: " .. rule_id)
                    t:ok(ast.resolve(rule_id) ~= nil,
                        key .. " runtime rule resolves: " .. rule_id)
                end
                local event = ast.attribute({}, profile, stat)
                if event.rule_id then
                    attributed = attributed + 1
                    t:ok(authority_ids[event.rule_id],
                        key .. " runtime attribution selects an exact member")
                    t:ok(contains(rule_ids, event.rule_id),
                        key .. " runtime attribution selects from its compiled stat")
                end
            end
        end
        t:ok(attributed > 0, key .. " exercises runtime attribution membership")
    end
    t:eq(checked_items, 17, "the adversarial identity audit covers exactly 17 items")

    local active_mutations = 0
    for _, rule_set in ipairs(all_runtime_rule_sets()) do
        for _, rule in ipairs(rule_set.rules) do
            t:neq(rule.visibility, "internal",
                rule.id .. " cannot hide executable routing or mechanics")
            local changed = mutate_rule(rule_set, rule.id, changed_value(rule))
            local valid, errors = ast.validate(changed)
            local error_text = table.concat(errors or {}, "; ")
            local rejected_negative = error_text:find(
                "negative net ability cost",
                1,
                true
            ) ~= nil
            t:ok(valid or rejected_negative,
                rule.id .. " either remains valid or fails the canonical negative-net guard: "
                    .. error_text)
            if rejected_negative then
                t:ok(not valid,
                    rule.id .. " cannot use a mutation to create negative net cost")
            end
            if valid then
                local before_profile = ast.project(rule_set)
                local after_profile = ast.project(changed)
                if not util.deep_equal(before_profile, after_profile) then
                    active_mutations = active_mutations + 1
                    local before = ast.player_authority(rule_set)
                    local after = ast.player_authority(changed)
                    local before_line = assert(balance_line(before.balance, rule.id))
                    local after_line = assert(balance_line(after.balance, rule.id))
                    t:neq(before.canonical_rule_set, after.canonical_rule_set,
                        rule.id .. " changes the inspectable structured authority")
                    t:ok(not util.deep_equal(before.rules, after.rules),
                        rule.id .. " changes the inspectable rule node")
                    t:neq(table.concat(before.inspection_copy, "\n"),
                        table.concat(after.inspection_copy, "\n"),
                        rule.id .. " changes generated expanded copy")
                    t:neq(before_line.value, after_line.value,
                        rule.id .. " changes its accounting value")
                    t:ok(not util.deep_equal(before.balance, after.balance),
                        rule.id .. " changes balance accounting")
                end
            end
        end
    end
    t:ok(active_mutations > 0,
        "the adversarial audit exercised mechanically active mutations")

    local baseline = rulebook.releases.baseline
    local changed = mutate_rule(baseline, "release.baseline.field_strength", 11)
    local before = ast.player_authority(baseline)
    local after = ast.player_authority(changed)
    t:eq(ast.project(baseline).field_release_strength, 10,
        "baseline field strength starts at ten")
    t:eq(ast.project(changed).field_release_strength, 11,
        "a visible field-strength mutation changes compiled mechanics")
    t:neq(table.concat(before.inspection_copy, "\n"),
        table.concat(after.inspection_copy, "\n"),
        "field-strength mutation changes inspection copy")
    t:neq(before.balance.spent, after.balance.spent,
        "field-strength mutation changes balance accounting")

    local extreme = mutate_rule(baseline, "release.baseline.field_strength", 999)
    local extreme_balance = ast.balance(extreme)
    local extreme_line = assert(balance_line(
        extreme_balance,
        "release.baseline.field_strength"
    ))
    t:eq(extreme_line.value, 999,
        "the 10-to-999 counterexample is visible in accounting")
    t:neq(extreme_balance.spent, before.balance.spent,
        "the 10-to-999 counterexample changes accounted spend")
    local valid, errors = ast.validate(extreme)
    t:eq(valid, false, "the 10-to-999 mutation cannot compile outside its budget")
    t:ok(has_error(errors, "exceeds rarity budget"),
        "the 10-to-999 mutation fails at the visible balance gate")
    t:raises(function() ast.project(extreme) end, "exceeds rarity budget",
        "the 10-to-999 mutation cannot alter fixed-step mechanics")

    local hidden = ast.copy(baseline)
    for _, rule in ipairs(hidden.rules) do
        if rule.id == "release.baseline.field_strength" then
            rule.visibility = "internal"
        end
    end
    valid, errors = ast.validate(hidden)
    t:eq(valid, false, "mechanically active rules cannot be marked internal")
    t:ok(has_error(errors, "visibility must be compact or expanded"),
        "the grammar reports hidden executable rules")
end

if arg and arg[0] and arg[0]:find("test_canonical_rule_identity.lua", 1, true) then
    harness.run_one(M)
end

return M
