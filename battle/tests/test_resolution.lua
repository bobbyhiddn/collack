-- battle/tests/test_resolution.lua — sequential resolution order.
--
-- The rule under test: both players launch marbles one at a time in sequence,
-- simultaneously on both sides. A launched marble cascades to a stop before the
-- next marble fires. This is neither turn-taking nor a free-for-all, and both
-- of those failure modes are asserted against explicitly:
--
--   * NOT a free-for-all — no two cascades are ever open at once.
--   * NOT turn-taking    — both sides launch in every volley, and the winner is
--                          decided only after both cascades have resolved.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local engine = require("battle.engine")
local setup = require("battle.setup")

local M = { name = "resolution_order" }

local LAUNCH_ISH = { launch = true, launch_aborted = true, no_marble = true }

function M.run(t)
    for _, seed in ipairs({ 1, 42, 4242, 20260726 }) do
        local battle = engine.simulate({ seed = seed, sides = setup.default_matchup() })
        local log = battle.log

        -- 1. Sequence numbers are dense and increasing, and volleys never go
        --    backwards — the log is a total order over the battle.
        local previous_volley = 0
        for index, event in ipairs(log.events) do
            t:eq(event.seq, index, "seed " .. seed .. ": log sequence is dense")
            if event.volley < previous_volley then
                t:fail("seed " .. seed .. ": volley went backwards at seq " .. event.seq)
            end
            previous_volley = event.volley
        end

        -- 2. Exactly one cascade is open at any point. A marble's whole run
        --    through the formation sits between its launch and its cascade_end
        --    with no other launch in between.
        local open = nil
        for _, event in ipairs(log.events) do
            if event.type == "launch" then
                if open ~= nil then
                    t:fail(string.format("seed %d: marble %s launched while marble %s was still in flight",
                        seed, tostring(event.marble), tostring(open)))
                end
                open = event.marble
            elseif event.type == "cascade_end" then
                t:eq(event.marble, open, "seed " .. seed .. ": cascade_end closes the open cascade")
                open = nil
            end
        end
        t:eq(open, nil, "seed " .. seed .. ": no cascade left open at the end")

        -- 3. Each side fires at most once per volley, and both sides fire in
        --    the same volley — simultaneous, not alternating.
        local per_volley = {}
        for _, event in ipairs(log.events) do
            if LAUNCH_ISH[event.type] then
                per_volley[event.volley] = per_volley[event.volley] or {}
                local slot = per_volley[event.volley]
                slot[event.side] = (slot[event.side] or 0) + 1
            end
        end
        local volleys_checked = 0
        for volley = 1, battle.volley do
            local slot = per_volley[volley]
            t:ok(slot ~= nil, string.format("seed %d: volley %d has launches", seed, volley))
            if slot then
                t:eq(slot.A, 1, string.format("seed %d volley %d: A fires exactly once", seed, volley))
                t:eq(slot.B, 1, string.format("seed %d volley %d: B fires exactly once", seed, volley))
                volleys_checked = volleys_checked + 1
            end
        end
        t:ok(volleys_checked > 1, "seed " .. seed .. ": battle ran more than one volley")

        -- 4. The battle ends exactly once, in the last volley.
        local ends = harness.of_type(log, "battle_end")
        t:eq(#ends, 1, "seed " .. seed .. ": exactly one battle_end")
        t:eq(ends[1].volley, battle.volley, "seed " .. seed .. ": battle_end in the final volley")
    end

    -- 5. Firing order is the player's declared order, not a shuffle: the first
    --    marble in the hand is the first one to leave the sling.
    local sides = setup.default_matchup()
    local battle = engine.new_battle({ seed = 5, sides = sides })
    local first_a = battle.sides.A.queue[1]
    local first_b = battle.sides.B.queue[1]
    t:eq(first_a.name, sides.A.marbles[1].name, "A fires its declared first marble first")
    t:eq(first_b.name, sides.B.marbles[1].name, "B fires its declared first marble first")
    engine.run(battle)
    local launches = harness.of_type(battle.log, "launch", "A")
    t:ok(#launches > 0, "A launched at least once")
    if #launches > 0 then
        t:eq(launches[1].marble, first_a.uid, "A's first launch is the head of its declared hand")
    end
end

if arg and arg[0] and arg[0]:find("test_resolution.lua", 1, true) then
    harness.run_one(M)
end

return M
