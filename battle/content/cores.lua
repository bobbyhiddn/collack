-- Core identities projected from trajectory and release RuleSets.

local ast = require("battle.rule_ast")
local rulebook = require("battle.content.rules")

local SPECS = {
    { id = "dull_quartz", name = "Dull Quartz", min_rarity = "common" },
    { id = "cant_pebble", name = "Cant Pebble", min_rarity = "common" },
    { id = "skew_flint", name = "Skew Flint", min_rarity = "common" },
    { id = "shrapnel_geode", name = "Shrapnel Geode", min_rarity = "uncommon" },
    { id = "concussion_pearl", name = "Concussion Pearl", min_rarity = "rare" },
    { id = "lodestone_heart", name = "Lodestone Heart", min_rarity = "epic" },
    { id = "cinder_nucleus", name = "Cinder Nucleus", min_rarity = "legendary" },
}

local CORES = {}
local by_id = {}

for _, spec in ipairs(SPECS) do
    local rule_set = rulebook.cores[spec.id]
    local profile = ast.project(rule_set)
    local release = profile.release
    if release == "baseline" then release = nil end
    local core = {
        id = spec.id,
        name = spec.name,
        min_rarity = spec.min_rarity,
        trajectory = profile.trajectory,
        release = release,
        rule_set = ast.copy(rule_set),
    }
    CORES[#CORES + 1] = core
    by_id[core.id] = core
end

return {
    list = CORES,
    by_id = by_id,
}
