-- Public setup-validation boundary. Fixed matchup fixtures are quarantined in
-- battle/tests and are excluded from every shipped archive.

local setup_rules = require("battle.setup_rules")

local M = {}

function M.validate(loadout)
    local valid, errors = setup_rules.validate(loadout)
    if valid then return true end
    return errors
end

M.validate_detailed = setup_rules.validate
M.empty_formation = setup_rules.empty_formation
M.player_spec = setup_rules.player_spec

return M
