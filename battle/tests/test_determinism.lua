-- battle/tests/test_determinism.lua — same seed, same setup, same log.
--
-- The rule under test: the simulation is seed-driven, and the same seed with
-- the same starting setup produces an identical battle log. The test runs each
-- seed twice and diffs the logs line by line.
--
-- It also asserts the negative: different seeds produce different logs. Without
-- that, an engine that ignored the seed entirely — or one whose log recorded
-- nothing that varies — would pass the determinism check trivially.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local engine = require("battle.engine")
local setup = require("battle.tests.fixtures")
local RNG = require("battle.rng")

local M = { name = "determinism" }

local function first_difference(left, right)
    local limit = math.max(#left, #right)
    for index = 1, limit do
        if left[index] ~= right[index] then
            return index, tostring(left[index]), tostring(right[index])
        end
    end
    return nil
end

function M.run(t)
    -- The generator itself, before anything is built on it.
    local a, b = RNG.new(12345), RNG.new(12345)
    local same = true
    for _ = 1, 500 do
        if a:next() ~= b:next() then same = false break end
    end
    t:ok(same, "the RNG replays identically from the same seed")
    t:neq(RNG.new(1):next(), RNG.new(2):next(), "different seeds diverge immediately")

    local texts = {}
    for _, seed in ipairs({ 1, 42, 4242, 20260726 }) do
        -- Fresh setup tables both times: nothing is carried over between runs
        -- except the seed itself.
        local first = engine.new_battle({ seed = seed, sides = setup.default_matchup() })
        local first_result = engine.run(first)

        local second = engine.new_battle({ seed = seed, sides = setup.default_matchup() })
        local second_result = engine.run(second)

        local left, right = first.log:lines(), second.log:lines()
        t:eq(#right, #left, string.format("seed %d: both runs logged the same number of events", seed))

        local index, got, want = first_difference(left, right)
        if index then
            t:fail(string.format("seed %d: logs diverge at line %d\n    run 1: %s\n    run 2: %s",
                seed, index, want, got))
        else
            t:ok(true, string.format("seed %d: both runs produced an identical log (%d lines)", seed, #left))
        end

        -- Same conclusion, same amount of randomness consumed.
        t:eq(second_result.outcome, first_result.outcome, "seed " .. seed .. ": same outcome")
        t:eq(second_result.winner, first_result.winner, "seed " .. seed .. ": same winner")
        t:eq(second_result.volleys, first_result.volleys, "seed " .. seed .. ": same length")
        t:eq(second.rng.draws, first.rng.draws, "seed " .. seed .. ": same number of RNG draws")

        texts[seed] = first.log:text()
    end

    -- The seed has to matter, or the check above proves nothing.
    local distinct = {}
    local count = 0
    for _, text in pairs(texts) do
        if not distinct[text] then
            distinct[text] = true
            count = count + 1
        end
    end
    t:ok(count > 1, "different seeds produce different battles")

    -- Determinism must survive a battle having already been run in this
    -- process — no global counter or leftover state may leak into the next one.
    local warmup = engine.new_battle({ seed = 777, sides = setup.default_matchup() })
    engine.run(warmup)
    local after = engine.new_battle({ seed = 42, sides = setup.default_matchup() })
    engine.run(after)
    t:eq(after.log:text(), texts[42], "a battle is unaffected by battles run before it")
end

if arg and arg[0] and arg[0]:find("test_determinism.lua", 1, true) then
    harness.run_one(M)
end

return M
