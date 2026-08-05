-- The comprehension pool is the approved, deliberately small 17-item packet.

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
local run_presentation = require("run_presentation")
local util = require("battle.run_util")

local M = { name = "rule_migration" }

local APPROVED = {
    "sling:momentum",
    "sling:ricochet",
    "sling:effect_amplifier",
    "marble:chalk_common",
    "marble:quartz_common",
    "marble:geode_uncommon",
    "marble:warden_rare",
    "marble:lodestone_epic",
    "marble:cinder_legendary",
    "brick_kit:guard_pair",
    "brick_kit:mirror_anchor",
    "brick_kit:living_aegis",
    "brick_kit:venom_rime",
    "brick_kit:lodestone_void",
    "brick_kit:shatter_keg",
    "brick_kit:splice_keg",
    "brick_kit:vault_temporal",
}

local LEGACY = {
    drifter_common = true,
    flint_hook_common = true,
    silver_seed_uncommon = true,
    banded_guard_uncommon = true,
    shard_ram_rare = true,
    magnet_needle_epic = true,
}

local function contains(values, wanted)
    for _, value in ipairs(values or {}) do
        if value == wanted then return true end
    end
    return false
end

function M.run(t)
    t:eq(content.COMPREHENSION_POOL_SIZE, 17,
        "the comprehension pool remains exactly seventeen items")
    t:eq(#content.SLINGS, 3, "the packet contains three macro slings")
    t:eq(#content.MARBLES, 6, "the packet contains six marble cards")
    t:eq(#content.BRICK_KITS, 8, "the packet contains eight positional kits")

    local seen = {}
    for index, entry in ipairs(content.COMPREHENSION_POOL) do
        local key = entry.category .. ":" .. entry.id
        t:eq(key, APPROVED[index], "approved item " .. index .. " is unchanged")
        t:eq(seen[key], nil, key .. " appears once")
        seen[key] = true

        local lookup = entry.category == "sling" and content.sling_by_id
            or entry.category == "marble" and content.marble_by_id
            or content.brick_kit_by_id
        local item = lookup[entry.id]
        t:ok(item ~= nil, key .. " resolves")
        t:eq(item.compact_copy, ast.compact(item.rule_set),
            key .. " has no handwritten card meaning")
        t:eq(item.balance.rule_set_id, item.rule_set.id,
            key .. " balance is tied to the same rule set")
        t:eq(item.compatibility.max_copies, item.rule_set.compatibility.max_copies,
            key .. " compatibility is tied to the same rule set")

        local authority = ast.player_authority(item.rule_set)
        local player_rules = ast.player_rules(item.rule_set)
        local profile = ast.project(item.rule_set)
        t:eq(#authority.rule_ids, #player_rules,
            key .. " has one canonical ID per inspectable rule")
        t:eq(item.draft_value, authority.rarity_budget,
            key .. " legacy draft value is only a RuleSet budget projection")
        t:eq(item.compact_copy, authority.compact_copy,
            key .. " compact copy uses canonical player rules")
        t:ok(util.deep_equal(item.mechanics, authority.compact_lines),
            key .. " compact lines use canonical player rules")
        t:ok(util.deep_equal(item.inspection_copy, authority.inspection_copy),
            key .. " expanded inspection uses canonical player rules")
        if entry.category == "brick_kit" then
            t:eq(item.balance.packaging_only, true,
                key .. " has no independent power budget")
            t:eq(#item.balance.members, 2,
                key .. " reports both member ledgers")
        else
            t:ok(util.deep_equal(item.balance, authority.balance),
                key .. " accounting uses canonical player rules")
        end
        t:eq(
            #authority.balance.lines,
            #authority.rule_ids + #item.rule_set.abilities,
            key .. " accounting includes only canonical rules and MCU surcharges"
        )

        local first_inspection = run_presentation.inspect_rule_set(item.rule_set, 1)
        t:eq(first_inspection.count, #authority.rule_ids,
            key .. " inspection and attribution expose the exact same count")
        for rule_index, rule in ipairs(player_rules) do
            local rule_id = authority.rule_ids[rule_index]
            t:eq(rule_id, rule.id,
                key .. " canonical player-rule order is stable at " .. rule_index)
            local inspection = run_presentation.inspect_rule_set(
                item.rule_set,
                rule_index
            )
            t:eq(inspection.rule.id, rule_id,
                key .. " inspection exposes attributed rule " .. rule_index)
            t:eq(authority.balance.lines[rule_index].rule_id, rule_id,
                key .. " accounting exposes attributed rule " .. rule_index)
            t:ok(contains(profile._rule_ids[rule.operation.stat], rule_id),
                key .. " execution projects attributed rule " .. rule_index)
        end
        for _, rule_ids in pairs(profile._rule_ids) do
            for _, rule_id in ipairs(rule_ids) do
                t:ok(contains(authority.rule_ids, rule_id),
                    key .. " execution cannot attribute an internal helper rule")
            end
        end
    end

    t:eq(#content.LEGACY_MARBLES, 6,
        "legacy CPU support stays explicit and quarantined")
    for _, item in ipairs(content.LEGACY_MARBLES) do
        t:ok(LEGACY[item.id], item.id .. " is an approved legacy-only marble")
        t:eq(seen["marble:" .. item.id], nil,
            item.id .. " cannot enter comprehension offers")
        LEGACY[item.id] = nil
    end
    t:eq(next(LEGACY), nil, "all and only the six legacy marbles are quarantined")
end

if arg and arg[0] and arg[0]:find("test_rule_migration.lua", 1, true) then
    harness.run_one(M)
end

return M
