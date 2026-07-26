-- battle/tests/test_win_conditions.lua — both win conditions, and the draw.
--
-- The rule under test, symmetric on both sides:
--   * all opponent bricks destroyed  => victory
--   * all own marbles destroyed      => defeat
--
-- The mutual case is asserted too, because it is the load-bearing proof that
-- the volley is simultaneous: A resolves before B inside a volley, so if the
-- winner were decided mid-volley A would always take a mutual kill. It has to
-- come out a draw.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local engine = require("battle.engine")
local fixtures = require("battle.tests.fixtures")

local M = { name = "win_conditions" }

function M.run(t)
    -- ------------------------------------------------------------------
    -- Victory: A destroys every brick B has.
    -- B's marble is sturdy and A's wall is absorbers, so B cannot win back.
    -- ------------------------------------------------------------------
    local battle, result = engine.simulate({
        seed = 3,
        sides = {
            A = {
                name = "Breaker", sling = fixtures.TIGHT_SLING,
                formation = fixtures.tough_wall(3),
                marbles = { fixtures.cleaver(1) },
            },
            B = {
                name = "Glass", sling = fixtures.TIGHT_SLING,
                formation = fixtures.single_brick(3, 1),
                marbles = { fixtures.sturdy(1) },
            },
        },
    })
    t:eq(result.outcome, "victory", "destroying every enemy brick is a victory")
    t:eq(result.winner, "A", "the side that cleared the formation wins")
    t:eq(result.reason, "bricks_destroyed", "and the reason is recorded")
    t:eq(battle.sides.B.formation.alive, 0, "B has no bricks left")
    t:eq(result.volleys, 1, "it ended in the volley the last brick fell")

    -- Symmetric: the same setup with the sides swapped must give B the win.
    local _, mirrored = engine.simulate({
        seed = 3,
        sides = {
            A = {
                name = "Glass", sling = fixtures.TIGHT_SLING,
                formation = fixtures.single_brick(3, 1),
                marbles = { fixtures.sturdy(1) },
            },
            B = {
                name = "Breaker", sling = fixtures.TIGHT_SLING,
                formation = fixtures.tough_wall(3),
                marbles = { fixtures.cleaver(1) },
            },
        },
    })
    t:eq(mirrored.outcome, "victory", "the win condition is symmetric")
    t:eq(mirrored.winner, "B", "B wins the mirrored setup")
    t:eq(mirrored.reason, "bricks_destroyed", "for the same reason")

    -- ------------------------------------------------------------------
    -- Defeat: A loses every marble it has.
    -- A's only marble is a one-shell common firing into absorbers, which soak
    -- the damage and grind the shell off. A cannot win and cannot survive.
    -- ------------------------------------------------------------------
    local attrition, lost = engine.simulate({
        seed = 3,
        sides = {
            A = {
                name = "Doomed", sling = fixtures.TIGHT_SLING,
                formation = fixtures.tough_wall(3),
                marbles = { fixtures.fragile(1) },
            },
            B = {
                name = "Wall", sling = fixtures.TIGHT_SLING,
                formation = fixtures.tough_wall(3),
                marbles = { fixtures.sturdy(3) },
            },
        },
    })
    t:eq(lost.outcome, "victory", "losing every marble ends the battle")
    t:eq(lost.winner, "B", "the surviving side wins")
    t:eq(lost.reason, "opponent_marbles_destroyed", "and the reason is recorded")
    t:eq(#attrition.sides.A.roster, 0, "A has no marbles left")
    t:ok(attrition.sides.B.formation.alive > 0, "B still had bricks standing")

    -- The core came back even though the marble did not.
    t:eq(#attrition.sides.A.bag, 1, "the destroyed marble's core is in A's bag")

    -- ------------------------------------------------------------------
    -- Draw: both sides clear the other's formation in the same volley.
    -- A resolves first. If the winner were decided the moment A's cascade
    -- ended, A would win this. It must be a draw.
    -- ------------------------------------------------------------------
    local mutual_battle, mutual = engine.simulate({
        seed = 3,
        sides = {
            A = {
                name = "Left", sling = fixtures.TIGHT_SLING,
                formation = fixtures.single_brick(3, 1),
                marbles = { fixtures.cleaver(1) },
            },
            B = {
                name = "Right", sling = fixtures.TIGHT_SLING,
                formation = fixtures.single_brick(3, 1),
                marbles = { fixtures.cleaver(1) },
            },
        },
    })
    t:eq(mutual.outcome, "draw", "a mutual kill inside one volley is a draw")
    t:eq(mutual.winner, nil, "nobody wins on resolution order")
    t:eq(mutual.reason, "mutual", "and it is recorded as mutual")
    t:eq(mutual.volleys, 1, "decided in the first volley")
    t:eq(mutual_battle.sides.A.formation.alive, 0, "A's formation fell")
    t:eq(mutual_battle.sides.B.formation.alive, 0, "B's formation fell too")

    -- B genuinely got its shot off in that volley — it was not cut short by
    -- A winning first.
    local b_launches = harness.of_type(mutual_battle.log, "launch", "B")
    t:eq(#b_launches, 1, "B fired in the same volley A did")

    -- ------------------------------------------------------------------
    -- Draw by exhaustion: neither condition is reachable inside the cap.
    -- ------------------------------------------------------------------
    local _, stalled = engine.simulate({
        seed = 3,
        max_volleys = 4,
        sides = {
            A = {
                name = "Stone", sling = fixtures.TIGHT_SLING,
                formation = fixtures.tough_wall(3),
                marbles = { fixtures.sturdy(1) },
            },
            B = {
                name = "Stone", sling = fixtures.TIGHT_SLING,
                formation = fixtures.tough_wall(3),
                marbles = { fixtures.sturdy(1) },
            },
        },
    })
    t:eq(stalled.outcome, "draw", "hitting the volley cap is a draw")
    t:eq(stalled.reason, "volley_limit", "reported as the volley limit, not a win")
end

if arg and arg[0] and arg[0]:find("test_win_conditions.lua", 1, true) then
    harness.run_one(M)
end

return M
