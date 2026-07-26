-- battle/tests/test_blowback.lua — blowback hits friendly marbles.
--
-- The rule under test: when a marble's last shell breaks, the core releases and
-- the release ALWAYS produces baseline blowback, which displaces nearby marbles
-- on both sides — the firing player's own marbles included. Friendly
-- displacement is required, not optional. It is what makes clustering
-- dangerous, so the blocked-and-crushed case is asserted too.

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

local M = { name = "blowback_friendly_fire" }

function M.run(t)
    -- ------------------------------------------------------------------
    -- Scenario 1: a common core, so nothing but BASELINE blowback is in
    -- play, released in column 3 with allies parked either side of it.
    -- ------------------------------------------------------------------
    local battle = engine.new_battle({
        seed = 11,
        max_volleys = 1,
        sides = {
            A = {
                name = "Ally", sling = fixtures.TIGHT_SLING,
                formation = fixtures.tough_wall(5),
                -- The fragile marble fires first; the two sturdy ones stay in
                -- the rack flanking the lane it fires from.
                marbles = { fixtures.fragile(3), fixtures.sturdy(2), fixtures.sturdy(4) },
            },
            B = {
                name = "Enemy", sling = fixtures.TIGHT_SLING,
                formation = fixtures.single_brick(5, 3),
                marbles = { fixtures.sturdy(2), fixtures.sturdy(3), fixtures.sturdy(4) },
            },
        },
    })
    engine.run(battle)
    local log = battle.log

    local releases = harness.of_type(log, "core_release")
    t:ok(#releases >= 1, "the fragile marble's core released")
    if #releases >= 1 then
        t:eq(releases[1].side, "A", "the release belongs to the firing player")
        t:eq(releases[1].release, "baseline", "a common core produces baseline blowback")
        t:eq(releases[1].col, 3, "released in the column it died in")
    end

    -- The core returns to the owner's bag and the marble leaves play.
    local destroyed = harness.of_type(log, "marble_destroyed", "A")
    t:ok(#destroyed >= 1, "the marble is destroyed when its core is exposed")
    if #destroyed >= 1 then
        t:eq(destroyed[1].cause, "core_released", "destroyed by core release")
        t:eq(destroyed[1].core_bagged, "dull_quartz", "the core returns to the bag")
    end
    t:eq(#battle.sides.A.bag, 1, "exactly one core in A's bag")

    -- THE REQUIREMENT: allied marbles were displaced.
    local friendly = harness.select(log, function(event)
        return event.type == "blowback_displace" and event.side == "A" and event.ally == true
    end)
    t:ok(#friendly >= 2, string.format(
        "blowback displaced the firing player's OWN marbles (got %d, want >= 2)", #friendly))

    local moved_out = { [1] = false, [5] = false }
    for _, event in ipairs(friendly) do
        t:eq(event.ally, true, "a friendly displacement is flagged as allied")
        if moved_out[event.to] ~= nil then moved_out[event.to] = true end
    end
    t:ok(moved_out[1], "the ally in lane 2 was shoved outward to lane 1")
    t:ok(moved_out[5], "the ally in lane 4 was shoved outward to lane 5")

    -- Lane state agrees with the log: this is real displacement, not just a
    -- logged claim about one.
    t:ok(battle.sides.A.rack[1] ~= nil, "a marble now sits in A's lane 1")
    t:ok(battle.sides.A.rack[5] ~= nil, "a marble now sits in A's lane 5")

    -- And the enemy rack was hit by the same release.
    local enemy = harness.select(log, function(event)
        return event.type == "blowback_displace" and event.side == "B" and event.ally == false
    end)
    t:ok(#enemy >= 1, "blowback also displaced the opponent's marbles")

    -- Allies are processed before enemies, so friendly fire is visible first.
    local first_displace = harness.of_type(log, "blowback_displace")[1]
    if first_displace then
        t:eq(first_displace.side, "A", "the firing player's own rack is resolved first")
    end

    -- ------------------------------------------------------------------
    -- Scenario 2: clustering. A marble with nowhere to be shoved takes the
    -- force instead and loses shell durability.
    -- ------------------------------------------------------------------
    local packed = engine.new_battle({
        seed = 11,
        max_volleys = 1,
        sides = {
            A = {
                name = "Packed", sling = fixtures.TIGHT_SLING,
                formation = fixtures.tough_wall(5),
                -- Lanes 2 and 3 are adjacent, so the marble in lane 2 has
                -- nowhere to go when the core pops in column 1.
                marbles = { fixtures.fragile(1), fixtures.sturdy(2), fixtures.sturdy(3) },
            },
            B = {
                name = "Enemy", sling = fixtures.TIGHT_SLING,
                formation = fixtures.single_brick(5, 1),
                marbles = { fixtures.sturdy(5) },
            },
        },
    })
    engine.run(packed)

    local blocked = harness.select(packed.log, function(event)
        return event.type == "blowback_blocked" and event.side == "A" and event.ally == true
    end)
    t:ok(#blocked >= 1, "a clustered ally had nowhere to be displaced to")
    if #blocked >= 1 then
        t:eq(blocked[1].lane, 2, "it was the ally in lane 2")
        t:eq(blocked[1].into, 3, "which was shoved into the occupied lane 3")
    end

    local crushed = harness.select(packed.log, function(event)
        return event.type == "shell_crushed" and event.side == "A"
    end)
    t:ok(#crushed >= 1, "the ally that could not move lost shell durability instead")
    if #crushed >= 1 then
        t:eq(crushed[1].cause, "blowback_crush", "crushed by its own side's blowback")
    end
end

if arg and arg[0] and arg[0]:find("test_blowback.lua", 1, true) then
    harness.run_one(M)
end

return M
