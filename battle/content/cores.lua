-- Core identities projected from trajectory and release RuleSets.

local ast = require("battle.rule_ast")
local rulebook = require("battle.content.rules")

local SPECS = {
    { id = "dull_quartz", name = "Dull Quartz" },
    { id = "cant_pebble", name = "Cant Pebble" },
    { id = "skew_flint", name = "Skew Flint" },
    { id = "shrapnel_geode", name = "Shrapnel Geode" },
    { id = "concussion_pearl", name = "Concussion Pearl" },
    { id = "lodestone_heart", name = "Lodestone Heart" },
    { id = "cinder_nucleus", name = "Cinder Nucleus" },
}

local CORES = {}
local by_id = {}
local spec_by_id = {}
for _, spec in ipairs(SPECS) do spec_by_id[spec.id] = spec end

local function compile(spec, rule_set)
    local release = ast.rule_value(rule_set, "core." .. spec.id .. ".release")
    if release == "baseline" then release = nil end
    local min_rarity = rule_set.min_rarity
    for _, component in ipairs(rule_set.components or {}) do
        if component.kind == "core" and component.id == "core." .. spec.id then
            min_rarity = component.min_rarity
            break
        end
    end
    return {
        id = spec.id,
        name = spec.name,
        min_rarity = min_rarity,
        trajectory = ast.rule_value(rule_set, "core." .. spec.id .. ".trajectory"),
        release = release,
        rule_set = ast.copy(rule_set),
    }
end

local function runtime(id, rule_set, shadow)
    local spec = spec_by_id[id]
    if not spec then error("unknown core: " .. tostring(id)) end
    rule_set = rule_set or rulebook.cores[id]
    ast.assert_runtime_source("core", id, rule_set, shadow)
    local canonical = compile(spec, rule_set)
    for _, field in ipairs({ "trajectory", "release", "min_rarity" }) do
        if shadow and shadow[field] ~= nil and shadow[field] ~= canonical[field] then
            error(string.format(
                "core %s compiled %s diverges from canonical RuleSet",
                tostring(id),
                field
            ))
        end
    end
    return canonical
end

local function canonical_rule_set(id)
    local rule_set = rulebook.cores[id]
    if not rule_set then error("unknown core: " .. tostring(id)) end
    return ast.copy(rule_set)
end

local function has(id)
    return spec_by_id[id] ~= nil and rulebook.cores[id] ~= nil
end

for _, spec in ipairs(SPECS) do
    local rule_set = rulebook.cores[spec.id]
    local core = compile(spec, rule_set)
    CORES[#CORES + 1] = core
    by_id[core.id] = core
end

return {
    list = CORES,
    by_id = by_id,
    runtime = runtime,
    canonical_rule_set = canonical_rule_set,
    has = has,
}
