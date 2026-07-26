-- battle/cli.lua — run one battle from a seed and print the log.
--
-- Usage, from the repository root:
--   lua5.1 battle/cli.lua                 # default seed
--   lua5.1 battle/cli.lua --seed 4242
--   lua5.1 battle/cli.lua --seed 7 --quiet   # result line only
--
-- No love.*, no graphics, no input. This is the deliverable shape for the
-- headless slice: a seed goes in, a battle log comes out.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../?.lua",
    here .. "/../?/init.lua",
    package.path,
}, ";")

local engine = require("battle.engine")
local setup = require("battle.setup")

local options = { seed = 1337, quiet = false, max_volleys = nil }

local index = 1
while arg and arg[index] do
    local flag = arg[index]
    if flag == "--seed" then
        index = index + 1
        options.seed = tonumber(arg[index]) or error("--seed needs a number")
    elseif flag == "--max-volleys" then
        index = index + 1
        options.max_volleys = tonumber(arg[index]) or error("--max-volleys needs a number")
    elseif flag == "--quiet" then
        options.quiet = true
    elseif flag == "--help" or flag == "-h" then
        print("usage: lua5.1 battle/cli.lua [--seed N] [--max-volleys N] [--quiet]")
        os.exit(0)
    else
        io.stderr:write("unknown argument: " .. tostring(flag) .. "\n")
        os.exit(2)
    end
    index = index + 1
end

local battle, result = engine.simulate({
    seed = options.seed,
    sides = setup.default_matchup(),
    max_volleys = options.max_volleys,
})

if not options.quiet then
    for _, line in ipairs(battle.log:lines()) do
        print(line)
    end
    print("")
end

local winner = result.winner and battle.sides[result.winner].name or "nobody"
print(string.format(
    "seed=%d outcome=%s winner=%s reason=%s volleys=%d rng_draws=%d",
    options.seed, result.outcome, winner, result.reason, result.volleys, battle.rng.draws))
