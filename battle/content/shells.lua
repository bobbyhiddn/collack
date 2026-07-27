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

for _, spec in ipairs(SPECS) do
    local rule_set = rulebook.shells[spec.id]
    local profile = ast.project(rule_set)
    local shell = {
        id = spec.id,
        mineral = spec.mineral,
        pattern = spec.pattern,
        collision = profile.collision,
        durability = profile.durability,
        rule_set = ast.copy(rule_set),
    }
    SHELLS[#SHELLS + 1] = shell
    by_id[shell.id] = shell
end

return {
    list = SHELLS,
    by_id = by_id,
}
