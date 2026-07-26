-- Headless product-run inspector: deterministic draft/setup choices feed the
-- same canonical continuous engine used by the LÖVE client.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../?.lua",
    here .. "/../?/init.lua",
    package.path,
}, ";")

local engine = require("battle.engine")
local run = require("battle.run")

local options = { seed = 1337, quiet = false, max_exchanges = nil }
local index = 1
while arg and arg[index] do
    local flag = arg[index]
    if flag == "--seed" then
        index = index + 1
        options.seed = tonumber(arg[index]) or error("--seed needs a number")
    elseif flag == "--max-exchanges" or flag == "--max-volleys" then
        index = index + 1
        options.max_exchanges = tonumber(arg[index]) or error(flag .. " needs a number")
    elseif flag == "--quiet" then
        options.quiet = true
    elseif flag == "--help" or flag == "-h" then
        print("usage: lua5.1 battle/cli.lua [--seed N] [--max-exchanges N] [--quiet]")
        os.exit(0)
    else
        io.stderr:write("unknown argument: " .. tostring(flag) .. "\n")
        os.exit(2)
    end
    index = index + 1
end

local state = run.new({ run_seed = options.seed })
while state.phase == "draft" do
    local offer = state.draft.offer
    state = assert(run.dispatch(state, {
        kind = "choose_offer",
        offer_id = offer.offer_id,
        choice_id = offer.choices[1].choice_id,
    })).state
end
for brick_index, brick in ipairs(state.player.bricks) do
    state = assert(run.dispatch(state, {
        kind = "place_brick",
        brick_uid = brick.uid,
        row = math.floor((brick_index - 1) / 7) + 1,
        col = ((brick_index - 1) % 7) + 1,
    })).state
end
state = assert(run.dispatch(state, { kind = "lock_setup" })).state

local handoff = assert(run.battle_handoff(state))
local battle, result = engine.simulate({
    battle_seed = handoff.battle_seed,
    rules_version = handoff.rules_version,
    player = handoff.player,
    opponent = handoff.opponent,
    max_exchanges = options.max_exchanges,
})

if not options.quiet then
    for _, line in ipairs(battle.log:lines()) do print(line) end
    print("")
end

local winner = result.winner == "player" and handoff.player.name
    or result.winner == "opponent" and handoff.opponent.name
    or "nobody"
print(string.format(
    "run_seed=%d battle_seed=%d outcome=%s winner=%s reason=%s exchanges=%d rng_draws=%d",
    options.seed,
    handoff.battle_seed,
    result.outcome,
    winner,
    result.reason,
    result.exchanges,
    battle.rng.draws
))
