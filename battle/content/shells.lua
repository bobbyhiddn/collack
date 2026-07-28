-- Shell appearance identities projected onto canonical collision rules.

local ast = require("battle.rule_ast")
local rulebook = require("battle.content.rules")

local SPECS = {
    { id = "jade_lattice", mineral = "jade", pattern = "lattice" },
    { id = "obsidian_shard", mineral = "obsidian", pattern = "shard" },
    { id = "quartz_banded", mineral = "quartz", pattern = "banded" },
    { id = "flint_spiral", mineral = "flint", pattern = "spiral" },
    { id = "silver_veined", mineral = "silver", pattern = "veined" },
    { id = "granite_mottled", mineral = "granite", pattern = "mottled" },
    { id = "chalk_plain", mineral = "chalk", pattern = "plain" },
}

local SHELLS = {}
local by_id = {}
local spec_by_id = {}
for _, spec in ipairs(SPECS) do spec_by_id[spec.id] = spec end

local function compile(spec, rule_set)
    return {
        id = spec.id,
        mineral = spec.mineral,
        pattern = spec.pattern,
        collision = ast.rule_value(rule_set, "shell." .. spec.id .. ".collision"),
        durability = ast.rule_value(rule_set, "shell." .. spec.id .. ".durability"),
        rule_set = ast.copy(rule_set),
    }
end

local function runtime(id, rule_set, shadow)
    local spec = spec_by_id[id]
    if not spec then error("unknown shell: " .. tostring(id)) end
    rule_set = rule_set or rulebook.shells[id]
    ast.assert_runtime_source("shell", id, rule_set, shadow)
    local canonical = compile(spec, rule_set)
    for _, field in ipairs({ "collision", "durability" }) do
        if shadow and shadow[field] ~= nil and shadow[field] ~= canonical[field] then
            error(string.format(
                "shell %s compiled %s diverges from canonical RuleSet",
                tostring(id),
                field
            ))
        end
    end
    return canonical
end

local function canonical_rule_set(id)
    local rule_set = rulebook.shells[id]
    if not rule_set then error("unknown shell: " .. tostring(id)) end
    return ast.copy(rule_set)
end

local function has(id)
    return spec_by_id[id] ~= nil and rulebook.shells[id] ~= nil
end

for _, spec in ipairs(SPECS) do
    local rule_set = rulebook.shells[spec.id]
    local shell = compile(spec, rule_set)
    SHELLS[#SHELLS + 1] = shell
    by_id[shell.id] = shell
end

return {
    list = SHELLS,
    by_id = by_id,
    runtime = runtime,
    canonical_rule_set = canonical_rule_set,
    has = has,
}
