-- Adversarial proof for the schema-v2 rarity law and deny-by-default allied harm.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")
local ast = require("battle.rule_ast")
local rules = require("battle.content.rules")
local catalog = require("battle.content.draft")
local bricks = require("battle.content.bricks")
local cores = require("battle.content.cores")
local shells = require("battle.content.shells")
local setup_rules = require("battle.setup_rules")
local engine = require("battle.engine")
local draft = require("battle.draft")
local checkpoints = require("battle.checkpoints")
local fixtures = require("battle.tests.fixtures")
local opponent = require("battle.opponent")
local short_run = require("battle.short_run")
local short_fixtures = require("battle.tests.short_run_fixtures")

local M = { name = "allied_cost_rarity" }

local function rule(id, trigger, target, verb, stat, value, unit, options)
    options = options or {}
    return {
        id = id,
        trigger = { event = trigger, phase = options.phase or "during" },
        condition = {
            predicate = options.condition or "always",
            value = options.condition_value,
        },
        target = options.target or { selector = target, relation = options.relation },
        operation = { verb = verb, stat = stat, mode = options.mode or "set" },
        magnitude = { value = value, unit = unit },
        cadence = {
            unit = options.cadence_unit or trigger,
            interval = options.interval or 1,
            charges = options.charges,
        },
        cost = { kind = "none" },
        visibility = options.visibility or "compact",
        scaling = options.scaling,
        lethal = options.lethal,
    }
end

local function relay_rule_set()
    return {
        schema_version = ast.SCHEMA_VERSION,
        kind = "rule_set",
        id = "brick.plain_block",
        name = "Bloodstone Relay",
        role = "sacrificial shell bolster",
        content_kind = "brick",
        rarity = "rare",
        rarity_budget = 100,
        availability = {
            player_draft = false,
            player_reward = false,
            cpu_recipe = false,
            legacy_only = false,
        },
        components = {},
        abilities = {
            {
                id = "bloodstone_relay",
                kind = "allied_brick_cost",
                cost_rule_id = "fixture.relay.cost",
                payoff_rule_ids = { "fixture.relay.payoff" },
                recursion = {
                    accepts_causes = { "hostile_collision" },
                    max_generation = 1,
                },
            },
        },
        rules = {
            rule("brick.plain_block.hp", "build", "self", "protect", "hp", 2, "hp",
                { visibility = "expanded" }),
            rule("brick.plain_block.restitution", "build", "self", "set", "restitution",
                0.72, "multiplier", { visibility = "expanded" }),
            rule("brick.plain_block.behaviour", "build", "self", "set", "behaviour",
                "inert", "id", { visibility = "expanded" }),
            rule("fixture.relay.cost", "damaging_collision",
                "setup_linked_allied_brick", "deal", "damage", 1, "damage", {
                    phase = "after",
                    cadence_unit = "exchange",
                    charges = 2,
                    lethal = false,
                    target = {
                        selector = "setup_linked_allied_brick",
                        relation = "allied",
                        topology = "orthogonal",
                        count = 1,
                        exclude_self = true,
                        require_alive = true,
                        required_tags = {},
                        excluded_tags = {},
                        order = "local_row_col_uid",
                    },
                }),
            rule("fixture.relay.payoff", "ability_cost_paid", "current_shell",
                "wear", "shell_wear", 2, "durability", {
                    phase = "after",
                    relation = "enemy",
                    condition_value = "bloodstone_relay",
                    scaling = {
                        basis = "cost_damage_applied",
                        numerator = 2,
                        denominator = 1,
                        cap = 2,
                        rounding = "floor",
                    },
                }),
        },
        drawback = { kind = "reduce", stat = "hp", magnitude = 1, unit = "hp" },
        compatibility = { requires = {}, excludes = {}, max_copies = 2 },
        synergy_tags = { "retaliation" },
    }
end

local function blank_formation()
    local out = {}
    for row = 1, 3 do
        out[row] = {}
        for col = 1, 7 do out[row][col] = "." end
    end
    return out
end

local function test_battle()
    local sides = {
        A = {
            name = "Relay",
            sling = "momentum",
            formation = { { "plain_block", "plain_block", "plain_block" } },
            marbles = {
                {
                    name = "A", rarity = "common",
                    core = "dull_quartz", shells = { "chalk_plain" },
                },
            },
        },
        B = {
            name = "Striker",
            sling = "momentum",
            formation = { { "plain_block", "plain_block", "plain_block" } },
            marbles = {
                {
                    name = "B", rarity = "common",
                    core = "dull_quartz", shells = { "chalk_plain" },
                },
            },
        },
    }
    return engine.new({
        seed = 17017,
        sides = sides,
        max_exchanges = 2,
        max_exchange_ticks = 20,
    })
end

local BEHAVIOUR_IDS = {
    "basalt_absorber",
    "training_dummy",
    "mirror_pane",
    "moss_regenerator",
    "granite_fortifier",
    "shatter_crystal",
    "vault_arch",
    "venom_glass",
    "rime_block",
    "lodestone_block",
    "powder_keg",
    "splice_node",
    "aegis_keystone",
    "void_prism",
    "prismatic_mirror",
    "temporal_anchor",
}

local function all_behaviour_battle()
    local formation = blank_formation()
    for index, id in ipairs(BEHAVIOUR_IDS) do
        local row = math.floor((index - 1) / 7) + 1
        local col = ((index - 1) % 7) + 1
        formation[row][col] = id
    end
    local enemy = blank_formation()
    enemy[1][1] = "plain_block"
    return engine.new({
        seed = 17017,
        sides = {
            A = {
                name = "Roster",
                sling = "momentum",
                formation = formation,
                marbles = {
                    {
                        name = "A", rarity = "common",
                        core = "dull_quartz", shells = { "chalk_plain" },
                    },
                },
            },
            B = {
                name = "Probe",
                sling = "momentum",
                formation = enemy,
                marbles = {
                    {
                        name = "B", rarity = "common",
                        core = "dull_quartz", shells = { "chalk_plain" },
                    },
                },
            },
        },
        max_exchanges = 2,
        max_exchange_ticks = 20,
    })
end

local function prepare_relay(mutate_rule_set)
    local relay = relay_rule_set()
    if mutate_rule_set then mutate_rule_set(relay) end
    ast.assert_valid(relay)
    local relay_brick = {
        uid = "relay", content_id = "plain_block", id = "plain_block",
        name = "Bloodstone Relay", behaviour = "inert", rarity = "rare",
        hp = 2, max_hp = 2, restitution = 0.72, rule_set = relay,
    }
    local ally = draft.instantiate_brick("guard_pair", "basalt_absorber", 1, "A")
    ally.uid = "ally"
    local other = draft.instantiate_brick("guard_pair", "basalt_absorber", 2, "A")
    other.uid = "other"
    local formation = blank_formation()
    formation[1][1], formation[1][2], formation[1][3] = "relay", "ally", "other"
    local side_a = {
        name = "Relay", sling = "momentum", formation = formation,
        bricks = { relay_brick, ally, other },
        marbles = {{
            name = "A", rarity = "common", core = "dull_quartz",
            shells = { "chalk_plain" },
        }},
    }
    local links, errors = setup_rules.resolve_ability_links(side_a)
    assert(#errors == 0, errors[1] and errors[1].code)
    side_a.ability_links = links
    local enemy_formation = blank_formation()
    enemy_formation[1][1], enemy_formation[1][2], enemy_formation[1][3] =
        "plain_block", "plain_block", "plain_block"
    local battle = engine.new({
        seed = 17017,
        sides = {
            A = side_a,
            B = {
                name = "Striker", sling = "momentum",
                formation = enemy_formation,
                marbles = {{
                    name = "B", rarity = "common", core = "dull_quartz",
                    shells = { "chalk_plain" },
                }},
            },
        },
        max_exchanges = 2,
        max_exchange_ticks = 20,
    })
    battle.exchange = 1
    local owner = battle.sides.A
    local source = owner.formation.grid[1][1]
    local target = owner.formation.grid[1][2]
    other = owner.formation.grid[1][3]
    target.hp, target.max_hp = 3, 3
    other.hp, other.max_hp = 3, 3
    battle.world:get_box(target.body_id).data.hp = 3
    battle.world:get_box(other.body_id).data.hp = 3
    local striking = battle.sides.B.all_marbles[1]
    striking.shells[1].durability = 3
    striking.shells[1].max_durability = 3
    return battle, owner, source, target, other, striking
end

local function prepare_splice(mutate_rule_set)
    local splice = draft.instantiate_brick("splice_keg", "splice_node", 1, "A")
    splice.uid = "splice"
    if mutate_rule_set then mutate_rule_set(splice.rule_set) end
    ast.assert_valid(splice.rule_set)
    local guarded = draft.instantiate_brick(
        "guard_pair", "basalt_absorber", 2, "A"
    )
    guarded.uid = "guarded"
    local formation = blank_formation()
    formation[1][1], formation[1][2] = "splice", "guarded"
    local enemy = blank_formation()
    enemy[1][1] = "plain_block"
    local battle = engine.new({
        seed = 17018,
        sides = {
            A = {
                name = "Splice", sling = "momentum", formation = formation,
                bricks = { splice, guarded }, ability_links = {},
                marbles = {{
                    name = "A", rarity = "common", core = "dull_quartz",
                    shells = { "chalk_plain" },
                }},
            },
            B = {
                name = "Enemy", sling = "momentum", formation = enemy,
                marbles = {{
                    name = "B", rarity = "common", core = "dull_quartz",
                    shells = { "chalk_plain" },
                }},
            },
        },
        max_exchanges = 3,
        max_exchange_ticks = 20,
    })
    battle.exchange = 1
    return battle, battle.sides.A,
        battle.sides.A.formation.grid[1][1],
        battle.sides.A.formation.grid[1][2]
end

local function prepare_keg(enemy_marble_count)
    local keg = draft.instantiate_brick("shatter_keg", "powder_keg", 1, "A")
    keg.uid = "keg"
    local neighbour = draft.instantiate_brick(
        "guard_pair", "basalt_absorber", 2, "A"
    )
    neighbour.uid = "safe-neighbour"
    local formation = blank_formation()
    formation[1][1], formation[1][2] = "keg", "safe-neighbour"
    local enemy_formation = blank_formation()
    enemy_formation[1][1] = "plain_block"
    local enemy_marbles = {}
    for index = 1, enemy_marble_count do
        enemy_marbles[index] = {
            name = "Enemy " .. index, rarity = "common",
            core = "dull_quartz", shells = { "chalk_plain" }, lane = index,
        }
    end
    local battle = engine.new({
        seed = 17020,
        sides = {
            A = {
                name = "Keg", sling = "momentum", formation = formation,
                bricks = { keg, neighbour }, ability_links = {},
                marbles = {{
                    name = "Owner", rarity = "common", core = "dull_quartz",
                    shells = { "chalk_plain" },
                }},
            },
            B = {
                name = "Cluster", sling = "momentum",
                formation = enemy_formation, marbles = enemy_marbles,
            },
        },
        max_exchanges = 2,
        max_exchange_ticks = 20,
    })
    battle.exchange = 1
    return battle, battle.sides.A,
        battle.sides.A.formation.grid[1][1],
        battle.sides.A.formation.grid[1][2],
        battle.sides.B.all_marbles[1],
        battle.sides.B.all_marbles[2]
end

local function count_rarity(acquisition)
    local candidates = {}
    for _, rarity in ipairs(ast.rarity_order()) do
        candidates[#candidates + 1] = { id = rarity, rarity = rarity }
    end
    local counts = {}
    for ticket = 1, 100 do
        local selected = ast.sample_rarity(candidates, acquisition, ticket, 1)
        counts[selected.rarity] = (counts[selected.rarity] or 0) + 1
    end
    return counts
end

function M.run(t)
    local relay = relay_rule_set()
    local valid, errors = ast.validate(relay)
    t:ok(valid, "the sacrificial Relay fixture validates: "
        .. table.concat(errors or {}, "; "))
    t:eq(ast.ability_summary(relay).mcu, 4,
        "the rare linked-cost fixture is exactly at its MCU ceiling")
    local relay_compact = ast.compact(relay, 2)
    local relay_expanded = ast.expanded(relay)
    t:ok(relay_compact:find(
        "COST 1 linked allied integrity (once per exchange, 2 charges)",
        1,
        true
    ) ~= nil, "compact copy projects the exact linked cost and cadence")
    t:ok(relay_compact:find("wear the striking shell by 2 durability", 1, true) ~= nil,
        "compact copy projects the promised payoff from its canonical rule")
    t:ok(relay_expanded:find("required tags: any tags; excluded tags: none", 1, true)
        ~= nil, "expanded copy projects the exact eligibility filter")
    t:ok(relay_expanded:find("Payoff 1 fixture.relay.payoff scales floor(2 × cost / 1)",
        1, true) ~= nil, "expanded copy projects scaling and payoff identity")

    local too_low = ast.copy(relay)
    too_low.rarity = "uncommon"
    too_low.compatibility.max_copies = 3
    valid, errors = ast.validate(too_low)
    t:eq(valid, false, "allied-cost authority is rejected below rare")
    t:ok(table.concat(errors, "; "):find("invalid below rare", 1, true) ~= nil,
        "tier rejection identifies linked-cost authority")

    local widened = ast.copy(relay)
    widened.rules[4].target.selector = "orthogonal_neighbours"
    valid, errors = ast.validate(widened)
    t:eq(valid, false, "a generic neighbour selector cannot become an allied cost")
    t:ok(table.concat(errors, "; "):find("narrow setup link", 1, true) ~= nil,
        "widened selector is rejected by the narrow authority validator")

    local free_payoff = ast.copy(relay)
    free_payoff.rules[5].scaling = nil
    valid, errors = ast.validate(free_payoff)
    t:eq(valid, false, "a linked payoff without canonical scaling is rejected")

    local duplicate_payoff = ast.copy(relay)
    local second_payoff = ast.copy(duplicate_payoff.rules[5])
    second_payoff.id = "fixture.relay.payoff.second"
    duplicate_payoff.rules[#duplicate_payoff.rules + 1] = second_payoff
    duplicate_payoff.abilities[1].payoff_rule_ids[2] = second_payoff.id
    t:eq(ast.ability_summary(duplicate_payoff).mcu, 5,
        "a second payoff operation costs MCU even when it reuses the same verb")
    valid, errors = ast.validate(duplicate_payoff)
    t:eq(valid, false, "a rare linked ability cannot hide a second payoff above its MCU ceiling")
    t:ok(table.concat(errors, "; "):find("MCU ceiling", 1, true) ~= nil,
        "duplicate-operation complexity fails through the canonical tier ceiling")

    local overcredited_cost = ast.copy(relay)
    overcredited_cost.rules[4].magnitude.value = 2
    valid, errors = ast.validate(overcredited_cost)
    t:eq(valid, false, "an allied cost cannot claim more credit than its priced payoff")
    t:ok(table.concat(errors, "; "):find("allied-cost credit exceeds", 1, true) ~= nil,
        "allied-cost overcredit is rejected by canonical balance accounting")

    local combined_credit = ast.copy(relay)
    combined_credit.drawback.magnitude = 23
    valid, errors = ast.validate(combined_credit)
    t:eq(valid, false, "authored and allied-cost credits cannot exceed 25 together")
    t:ok(table.concat(errors, "; "):find("credit exceeds 25", 1, true) ~= nil,
        "combined drawback credit uses the single canonical cap")

    local generic_harm = ast.copy(relay)
    generic_harm.abilities = {
        {
            id = "generic_splash",
            kind = "passive",
            rule_ids = { "fixture.relay.cost", "fixture.relay.payoff" },
        },
    }
    valid, errors = ast.validate(generic_harm)
    t:eq(valid, false, "a generic passive cannot claim allied damage authority")
    t:ok(table.concat(errors, "; "):find("generic allied harm", 1, true) ~= nil,
        "generic allied harm is rejected independently of cost metadata")

    local common = ast.copy(rules.bricks.basalt_absorber)
    local disguised = ast.copy(common)
    local reflected
    for _, candidate in ipairs(rules.bricks.mirror_pane.rules) do
        if candidate.id == "brick.reflect.rebound" then reflected = ast.copy(candidate) end
    end
    reflected.trigger.event = "build"
    disguised.rules[#disguised.rules + 1] = reflected
    valid, errors = ast.validate(disguised)
    t:eq(valid, false, "common rejects a passive disguised as a build rule")
    t:ok(table.concat(errors, "; "):find("ungrouped brick rule", 1, true) ~= nil,
        "build-passive disguise fails at canonical AST validation")

    local nested = ast.copy(common)
    nested.rules[1].operation.passive = { stat = "reflect", magnitude = 1 }
    t:eq(ast.validate(nested), false,
        "common rejects a nested alternate effect field")

    local aliased = ast.copy(common)
    aliased.abilities = {{
        id = "body_alias",
        kind = "passive",
        rule_ids = { "brick.basalt_absorber.hp" },
    }}
    t:eq(ast.validate(aliased), false,
        "common rejects a body rule aliased into a passive group")

    local cached = {
        rule_set = ast.copy(common),
        behaviour = "absorb",
        hp = 2,
        max_hp = 2,
        restitution = 0.68,
        rarity = "common",
        cached_rules = { passive = "reflect" },
    }
    t:raises(function()
        bricks.runtime("basalt_absorber", common, cached)
    end, "forbidden shadow mechanics", "common rejects cached shadow passives")

    local economy_copy = ast.economy()
    economy_copy.tiers.common.shell_cap = 5
    economy_copy.rarity_order[1] = "legendary"
    t:eq(ast.tier("common").shell_cap, 1,
        "mutating a copied economy cannot change canonical shell caps")
    t:eq(ast.rarity_order()[1], "common",
        "mutating a copied rarity order cannot change canonical tier order")

    local mutations = {
        {
            label = "enemy relation",
            apply = function(item) item.rules[4].target.relation = "enemy" end,
        },
        {
            label = "diagonal topology",
            apply = function(item) item.rules[4].target.topology = "diagonal" end,
        },
        {
            label = "two targets",
            apply = function(item) item.rules[4].target.count = 2 end,
        },
        {
            label = "self selection",
            apply = function(item) item.rules[4].target.exclude_self = false end,
        },
        {
            label = "dead target",
            apply = function(item) item.rules[4].target.require_alive = false end,
        },
        {
            label = "runtime retarget order",
            apply = function(item) item.rules[4].target.order = "nearest_runtime" end,
        },
        {
            label = "zero cost",
            apply = function(item) item.rules[4].magnitude.value = 0 end,
        },
        {
            label = "fractional cost",
            apply = function(item) item.rules[4].magnitude.value = 1.5 end,
        },
        {
            label = "additive cost",
            apply = function(item) item.rules[4].operation.mode = "add" end,
        },
        {
            label = "unbounded charges",
            apply = function(item) item.rules[4].cadence.charges = 4 end,
        },
        {
            label = "mismatched trigger cadence",
            apply = function(item) item.rules[4].cadence.unit = "collision" end,
        },
        {
            label = "missing lethal declaration",
            apply = function(item) item.rules[4].lethal = nil end,
        },
        {
            label = "flat payoff",
            apply = function(item) item.rules[5].magnitude.value = 1 end,
        },
        {
            label = "wrong payoff ability",
            apply = function(item) item.rules[5].condition.value = "other" end,
        },
        {
            label = "generation four",
            apply = function(item) item.abilities[1].recursion.max_generation = 4 end,
        },
    }
    for _, mutation in ipairs(mutations) do
        local changed = ast.copy(relay)
        mutation.apply(changed)
        valid = ast.validate(changed)
        t:eq(valid, false, "linked-cost mutation rejects " .. mutation.label)
    end

    local loadout = {
        bricks = {
            {
                uid = "relay", name = "Bloodstone Relay", hp = 2, max_hp = 2,
                rule_set = relay,
            },
            {
                uid = "ally-a", name = "Basalt A", hp = 4, max_hp = 4,
                rule_set = bricks.canonical_rule_set("basalt_absorber"),
            },
            {
                uid = "ally-b", name = "Basalt B", hp = 4, max_hp = 4,
                rule_set = bricks.canonical_rule_set("basalt_absorber"),
            },
        },
        formation = blank_formation(),
    }
    loadout.formation[2][2] = "relay"
    loadout.formation[1][2] = "ally-a"
    loadout.formation[2][1] = "ally-b"
    local links, link_errors = setup_rules.resolve_ability_links(loadout)
    t:eq(#link_errors, 0, "setup resolves the fixture link")
    t:eq(#links, 1, "setup resolves exactly one fixture link")
    t:eq(links[1].target_uid, "ally-a",
        "local row, column, and UID tie-break selects the declared adjacent ally")
    local moved = ast.copy(loadout)
    moved.formation[1][2] = "."
    local moved_links = setup_rules.resolve_ability_links(moved)
    t:eq(moved_links[1].target_uid, "ally-b",
        "moving the target recomputes the stable preview")

    local function product_side(owner)
        local sling = draft.instantiate_sling({ content_id = "momentum" })
        local marble = draft.instantiate_marble(
            { content_id = "chalk_common" }, 1, owner
        )
        local brick = draft.instantiate_brick(
            "guard_pair", "basalt_absorber", 1, owner
        )
        local formation = blank_formation()
        formation[1][1] = brick.uid
        return {
            name = owner,
            sling = sling,
            sling_id = sling.id,
            marbles = { marble },
            bricks = { brick },
            formation = formation,
            bag_order = { marble.uid },
            ability_links = {},
        }
    end
    local tampered_player = product_side("player")
    tampered_player.ability_links[1] = {
        ability_id = "forged", source_uid = tampered_player.bricks[1].uid,
        target_uid = tampered_player.bricks[1].uid,
    }
    t:raises(function()
        engine.new({
            player = tampered_player,
            opponent = product_side("opponent"),
            battle_seed = 17,
        })
    end, "links are stale", "battle.new rejects a forged allied-cost handoff before stepping")

    for _, mutation in ipairs({
        function(link) link.source_rule_set_id = "forged" end,
        function(link) link.cost_rule_id = "forged" end,
        function(link) link.payoff_rule_ids = { "forged" } end,
        function(link) link.cost_amount = 2 end,
        function(link) link.lethal = true end,
        function(link) link.cadence.interval = 2 end,
        function(link) link.source_cell.col = 2 end,
        function(link) link.target_cell.col = 3 end,
        function(link) link.target_uid = "other" end,
    }) do
        local tampered, _, tampered_source, tampered_target, tampered_other,
            tampered_striking = prepare_relay()
        local link = tampered.ability_links["A|relay|bloodstone_relay"]
        mutation(link)
        local target_before, other_before = tampered_target.hp, tampered_other.hp
        local resolved = engine.activate_linked_cost(
            tampered,
            "A",
            tampered_source.uid,
            "bloodstone_relay",
            "hostile_collision",
            tampered_striking
        )
        t:eq(resolved, false, "runtime link tamper is rejected before payment")
        t:eq(tampered_target.hp, target_before,
            "runtime link tamper leaves the declared ally unchanged")
        t:eq(tampered_other.hp, other_before,
            "runtime link tamper cannot retarget another ally")
    end

    local battle, owner, source, target, other, striking = prepare_relay()
    target.guard = {
        amount = 1, expires_tick = 999, exchange = 1,
        source_owner = "A", source_uid = "other",
        source_rule_set_id = other.rule_set.id, ability_id = "splice_guard",
    }
    local activated, activation_id = engine.activate_linked_cost(
        battle, "A", source.uid, "bloodstone_relay",
        "hostile_collision", striking
    )
    t:eq(activated, true, "the valid fixture activation resolves")
    t:eq(target.hp, 2, "the declared adjacent ally pays exactly one integrity")
    t:eq(target.guard.amount, 1, "Splice Guard cannot prevent an allied ability cost")
    t:eq(striking.shells[1].durability, 1,
        "the exact one-point cost bolsters the promised two-shell-wear payoff")
    t:eq(other.hp, 3, "the fixture never widens cost damage to another ally")

    local triggered = harness.of_type(battle.log, "ability_triggered")
    local paid = harness.of_type(battle.log, "ability_cost_paid")
    local payoff = harness.of_type(battle.log, "ability_payoff_applied")
    t:eq(#triggered, 1, "one trigger event is emitted")
    t:eq(#paid, 1, "one exact payment event is emitted")
    t:eq(#payoff, 1, "one promised payoff event is emitted")
    t:eq(triggered[1].activation_id, activation_id,
        "trigger uses the stable activation identity")
    t:eq(paid[1].activation_id, activation_id,
        "cost uses the same activation identity")
    t:eq(payoff[1].activation_id, activation_id,
        "payoff uses the same activation identity")
    t:ok(triggered[1].seq < paid[1].seq and paid[1].seq < payoff[1].seq,
        "atomic trigger, payment, and payoff ordering is stable")
    t:eq(paid[1].integrity_before, 3, "cost evidence records integrity before")
    t:eq(paid[1].integrity_after, 2, "cost evidence records integrity after")
    for _, event in ipairs({ triggered[1], paid[1], payoff[1] }) do
        for _, field in ipairs({
            "event_id", "tick", "exchange", "root_event_id", "parent_event_id",
            "generation", "source_owner", "source_entity_id", "source_rule_set_id",
            "rule_id", "ability_id", "operation", "target_selector",
            "target_owner", "target_entity_id", "target_relation", "amount", "unit",
            "cause", "activation_id", "linked_source_uid", "linked_target_uid",
            "cadence_index", "charges_before", "charges_after",
        }) do
            t:ok(event[field] ~= nil,
                event.type .. " carries attributed field " .. field)
        end
    end

    local replay_battle, _, replay_source, replay_target, replay_other, replay_striking =
        prepare_relay()
    replay_target.guard = {
        amount = 1, expires_tick = 999, exchange = 1,
        source_owner = "A", source_uid = "other",
        source_rule_set_id = replay_other.rule_set.id, ability_id = "splice_guard",
    }
    engine.activate_linked_cost(
        replay_battle, "A", replay_source.uid, "bloodstone_relay",
        "hostile_collision", replay_striking
    )
    t:eq(replay_battle.log:text(), battle.log:text(),
        "linked-cost trigger, payment, payoff, and evidence replay byte-identically")

    local hp_before = other.hp
    engine.apply_brick_harm(battle, owner, other, 1, {
        source_owner = "A",
        source_entity_id = source.uid,
        source_rule_set_id = source.rule_set.id,
        cause = "generic_splash",
    })
    t:eq(other.hp, hp_before,
        "generic allied damage is denied without linked authorization")
    local authorization_id = paid[1].authorization_id
    engine.apply_brick_harm(battle, owner, other, 1, {
        source_owner = "A",
        source_uid = source.uid,
        source_entity_id = source.uid,
        source_rule_set_id = source.rule_set.id,
        rule_id = "fixture.relay.cost",
        ability_id = "bloodstone_relay",
        cause = "ability_cost",
        root_event_id = paid[1].root_event_id,
        activation_id = activation_id,
        authorization_id = authorization_id,
    })
    t:eq(other.hp, hp_before,
        "a used authorization cannot be copied or widened to another ally")

    local fresh_battle, fresh_owner, fresh_source, fresh_target, _, _ =
        prepare_relay()
    fresh_battle.authorizations["fresh-cost"] = {
        root_event_id = "fresh-root",
        activation_id = "fresh-activation",
        ability_id = "bloodstone_relay",
        source_uid = fresh_source.uid,
        source_rule_set_id = fresh_source.rule_set.id,
        cost_rule_id = "fixture.relay.cost",
        target_uid = fresh_target.uid,
        target_owner = fresh_owner.id,
        amount = 1,
        lethal = false,
        used = false,
    }
    local fresh_before = fresh_target.hp
    engine.apply_brick_harm(fresh_battle, fresh_owner, fresh_target, 1, {
        source_owner = fresh_owner.id,
        source_uid = fresh_source.uid,
        source_entity_id = fresh_source.uid,
        source_rule_set_id = fresh_source.rule_set.id,
        rule_id = "generic.splash",
        ability_id = "bloodstone_relay",
        operation = "splash",
        target_selector = "orthogonal_neighbours",
        cause = "generic_splash",
        root_event_id = "fresh-root",
        activation_id = "fresh-activation",
        authorization_id = "fresh-cost",
    })
    t:eq(fresh_target.hp, fresh_before,
        "a fresh cost authorization cannot be attached to generic splash")
    t:eq(fresh_battle.authorizations["fresh-cost"].used, false,
        "a denied generic path cannot consume the narrow authorization")

    local forged_before = fresh_target.hp
    engine.apply_brick_harm(fresh_battle, fresh_owner, fresh_target, 1, {
        source_owner = "B",
        source_entity_id = fresh_source.uid,
        source_rule_set_id = fresh_source.rule_set.id,
        operation = "deal",
        target_selector = "setup_linked_allied_brick",
        cause = "ability_cost",
        authorization_id = "fresh-cost",
    })
    t:eq(fresh_target.hp, forged_before,
        "forging an enemy owner around an actual allied source fails closed")
    local enemy_owner = fresh_battle.sides.B
    local enemy_source = enemy_owner.all_marbles[1]
    engine.apply_brick_harm(fresh_battle, enemy_owner, fresh_target, 1, {
        source_owner = enemy_owner.id,
        source_entity_id = enemy_source.uid,
        source_marble = enemy_source,
        cause = "hostile_collision",
    })
    t:eq(fresh_target.hp, forged_before,
        "forging the target owner cannot redirect hostile damage onto its ally")
    local replay_payload = ast.copy(paid[1])
    replay_payload.source_entity_id = fresh_source.uid
    replay_payload.source_uid = fresh_source.uid
    engine.apply_brick_harm(
        fresh_battle, fresh_owner, fresh_target, 1, replay_payload
    )
    t:eq(fresh_target.hp, forged_before,
        "replayed and deserialized attribution fields carry no allied authority")
    engine.apply_brick_harm(fresh_battle, fresh_owner, fresh_target, 1, {
        source_owner = fresh_owner.id,
        source_entity_id = fresh_source.uid,
        nested = {
            operation = "deal",
            target_selector = "setup_linked_allied_brick",
            authorization_id = "fresh-cost",
        },
        cause = "ability_cost",
    })
    t:eq(fresh_target.hp, forged_before,
        "nested caller payloads cannot manufacture allied-cost authority")

    local roster_battle = all_behaviour_battle()
    local roster_owner = roster_battle.sides.A
    local roster_count = 0
    local roster_source = roster_owner.all_marbles[1]
    for row = 1, roster_owner.formation.rows do
        for col = 1, roster_owner.formation.cols do
            local brick = roster_owner.formation.grid[row][col]
            if brick then
                roster_count = roster_count + 1
                local before = brick.hp
                for _, cause in ipairs({
                    "friendly_collision",
                    "splash",
                    "field",
                    "status",
                    "destroyed",
                    "chain",
                    "generation_three",
                }) do
                    engine.apply_brick_harm(roster_battle, roster_owner, brick, 1, {
                        source_owner = "A",
                        source_entity_id = roster_source.uid,
                        source_rule_set_id = roster_source.shells[1].rule_set.id,
                        source_marble = roster_source,
                        cause = cause,
                        root_event_id = brick.id .. ":" .. cause,
                        generation = cause == "generation_three" and 3 or 0,
                    })
                    t:eq(brick.hp, before,
                        brick.id .. " rejects unauthorized allied " .. cause)
                end
            end
        end
    end
    t:eq(roster_count, 16,
        "all sixteen behaviour bricks cross the deny-by-default harm boundary")
    local unknown_target = roster_owner.formation.grid[1][1]
    local unknown_before = unknown_target.hp
    engine.apply_brick_harm(roster_battle, roster_owner, unknown_target, 1, {
        cause = "environment",
        root_event_id = "missing-owner",
    })
    t:eq(unknown_target.hp, unknown_before,
        "brick harm with a missing source owner fails closed")
    engine.apply_brick_harm(roster_battle, roster_owner, unknown_target, 1, {
        source_owner = "forged-owner",
        source_entity_id = "hostile-probe",
        cause = "environment",
        root_event_id = "forged-owner",
    })
    t:eq(unknown_target.hp, unknown_before,
        "brick harm with an unknown source owner fails closed")
    engine.apply_brick_harm(roster_battle, roster_owner, unknown_target, 1, {
        source_owner = "B",
        source_entity_id = "hostile-probe",
        cause = "generation_four",
        root_event_id = "generation-four",
        generation = 4,
    })
    t:eq(unknown_target.hp, unknown_before,
        "a fourth-generation hostile mutation is visibly refused")
    t:eq(#harness.of_type(roster_battle.log, "cascade_capped"), 1,
        "generation-four refusal emits one cap event")

    local capped_battle = all_behaviour_battle()
    local capped_owner = capped_battle.sides.A
    local capped_target = capped_owner.formation.grid[1][1]
    local capped_before = capped_target.hp
    for _ = 1, engine.MAX_BRICK_HARM_ATTEMPTS + 1 do
        engine.apply_brick_harm(capped_battle, capped_owner, capped_target, 1, {
            source_owner = "A",
            source_entity_id = "allied-cap-probe",
            cause = "generic_splash",
            root_event_id = "harm-cap-root",
        })
    end
    t:eq(capped_target.hp, capped_before,
        "harm-attempt cap cannot be used to mutate an ally")
    local cap_events = harness.of_type(capped_battle.log, "cascade_capped")
    t:eq(#cap_events, 1, "a root emits one visible harm-attempt cap event")
    t:eq(cap_events[1].cap_reason, "brick_harm_attempts",
        "the cap event names the exact exhausted budget")

    local shell_before = striking.shells[1].durability
    activated = engine.activate_linked_cost(
        battle, "A", source.uid, "bloodstone_relay",
        "hostile_collision", striking
    )
    t:eq(activated, false, "a second activation in the same exchange is cadence-blocked")
    t:eq(target.hp, 2, "cadence block spends no linked integrity")
    t:eq(striking.shells[1].durability, shell_before,
        "cadence block grants no payoff")

    local interval_battle, _, interval_source, interval_target, _, interval_striking =
        prepare_relay(function(item) item.rules[4].cadence.interval = 2 end)
    activated = engine.activate_linked_cost(
        interval_battle, "A", interval_source.uid, "bloodstone_relay",
        "hostile_collision", interval_striking
    )
    t:eq(activated, true, "an interval-two exchange cadence activates on its first window")
    interval_battle.exchange = 2
    activated = engine.activate_linked_cost(
        interval_battle, "A", interval_source.uid, "bloodstone_relay",
        "hostile_collision", interval_striking
    )
    t:eq(activated, false, "an interval-two exchange cadence blocks the skipped exchange")
    t:eq(interval_target.hp, 2, "the skipped cadence window spends no linked integrity")
    interval_battle.exchange = 3
    activated = engine.activate_linked_cost(
        interval_battle, "A", interval_source.uid, "bloodstone_relay",
        "hostile_collision", interval_striking
    )
    t:eq(activated, true, "an interval-two exchange cadence reopens on the next window")
    t:eq(interval_target.hp, 1, "the reopened cadence window pays exactly once")

    battle.exchange = 2
    target.hp = 1
    activated = engine.activate_linked_cost(
        battle, "A", source.uid, "bloodstone_relay",
        "hostile_collision", striking
    )
    t:eq(activated, false, "nonlethal exact payment blocks at one integrity")
    t:eq(target.hp, 1, "insufficient target integrity remains unchanged")
    activated = engine.activate_linked_cost(
        battle, "A", source.uid, "bloodstone_relay",
        "ability_cost", striking
    )
    t:eq(activated, false, "an undeclared recursive cause is denied")

    local lethal_battle, _, lethal_source, lethal_target, _, lethal_striking =
        prepare_relay(function(item) item.rules[4].lethal = true end)
    lethal_target.hp = 1
    lethal_battle.world:get_box(lethal_target.body_id).data.hp = 1
    activated = engine.activate_linked_cost(
        lethal_battle,
        "A",
        lethal_source.uid,
        "bloodstone_relay",
        "hostile_collision",
        lethal_striking
    )
    t:eq(activated, true, "an explicitly lethal exact payment may reach zero")
    t:eq(lethal_target.alive, false, "lethal payment destroys only its linked ally")
    local lethal_paid = harness.of_type(lethal_battle.log, "ability_cost_paid")[1]
    local lethal_payoff = harness.of_type(lethal_battle.log, "ability_payoff_applied")[1]
    local lethal_destroyed = harness.of_type(lethal_battle.log, "brick_destroyed")[1]
    t:ok(lethal_paid.seq < lethal_payoff.seq
        and lethal_payoff.seq < lethal_destroyed.seq,
        "lethal destruction and descendants wait until the promised payoff completes")
    for _, field in ipairs({
        "event_id", "tick", "exchange", "root_event_id", "parent_event_id",
        "generation", "source_owner", "source_entity_id", "source_rule_set_id",
        "rule_id", "ability_id", "operation", "target_selector", "target_owner",
        "target_entity_id", "target_relation", "amount", "unit", "cause",
        "activation_id", "linked_source_uid", "linked_target_uid",
    }) do
        t:ok(lethal_destroyed[field] ~= nil,
            "linked-cost destruction carries attributed field " .. field)
    end

    local capped_activation, _, capped_source, capped_link_target, _,
        capped_striking = prepare_relay()
    capped_activation.cascade_attempts["activation-cap-root"] = {
        ability_activations = engine.MAX_CASCADE_ACTIVATIONS,
        brick_harm_attempts = 0,
        capped = {},
    }
    local capped_link_before = capped_link_target.hp
    activated = engine.activate_linked_cost(
        capped_activation,
        "A",
        capped_source.uid,
        "bloodstone_relay",
        "hostile_collision",
        capped_striking,
        { root_event_id = "activation-cap-root", generation = 1 }
    )
    t:eq(activated, false, "the per-root activation budget refuses activation seventeen")
    t:eq(capped_link_target.hp, capped_link_before,
        "an activation-cap refusal spends no linked integrity")
    t:eq(capped_source.ability_state.bloodstone_relay.spent, 0,
        "an activation-cap refusal spends no charge")

    local chain_battle, keg_owner, keg, neighbour, enemy_marble =
        prepare_keg(1)
    neighbour.hp, neighbour.max_hp = 3, 3
    enemy_marble.shells[1].durability = 3
    enemy_marble.shells[1].max_durability = 3
    engine.apply_brick_harm(chain_battle, keg_owner, keg, 1, {
        source_owner = "B",
        source_entity_id = enemy_marble.uid,
        source_rule_set_id = enemy_marble.shells[1].rule_set.id,
        cause = "hostile_collision",
        root_event_id = "chain-root",
        parent_event_id = "chain-root",
        generation = 0,
        source_marble = enemy_marble,
    })
    t:eq(neighbour.hp, 3, "Powder Keg never damages an adjacent brick")
    t:eq(enemy_marble.shells[1].durability, 2,
        "Powder Keg Chain wears the causal enemy marble shell exactly once")

    local cascade_battle, cascade_owner, cascade_keg, _, causal, nearby =
        prepare_keg(2)
    local nearby_body = cascade_battle.world:get_body(nearby.body_id)
    cascade_battle.world:set_position(
        nearby.body_id,
        cascade_keg.x + 2,
        cascade_keg.y + 2
    )
    nearby_body = cascade_battle.world:get_body(nearby.body_id)
    t:ok(nearby_body ~= nil, "the bounded Chain fixture places a second live target")
    engine.apply_brick_harm(cascade_battle, cascade_owner, cascade_keg, 1, {
        source_owner = "B",
        source_entity_id = causal.uid,
        source_rule_set_id = causal.shells[1].rule_set.id,
        cause = "hostile_collision",
        root_event_id = "chain-breadth-first",
        parent_event_id = "chain-breadth-first",
        generation = 0,
        source_marble = causal,
    })
    local cascade_targets = harness.of_type(cascade_battle.log, "chain_targeted")
    local cascade_releases = harness.of_type(cascade_battle.log, "core_release")
    t:eq(#cascade_targets, 2, "bounded Chain selects the causal and one nearby enemy")
    t:eq(#cascade_releases, 2, "both one-shell Chain targets release their cores")
    t:ok(cascade_targets[2].seq < cascade_releases[1].seq,
        "all generation-one Chain targets resolve before generation-two releases")
    for _, release in ipairs(cascade_releases) do
        t:eq(release.root_event_id, "chain-breadth-first",
            "descendant core release retains the physical root identity")
        t:eq(release.generation, 2,
            "a shell broken by generation-one Chain releases at generation two")
    end

    local generation_battle, generation_owner, generation_keg, _,
        generation_marble = prepare_keg(1)
    generation_marble.shells[1].durability = 1
    engine.apply_brick_harm(generation_battle, generation_owner, generation_keg, 1, {
        source_owner = "B",
        source_entity_id = generation_marble.uid,
        source_rule_set_id = generation_marble.shells[1].rule_set.id,
        cause = "hostile_collision",
        root_event_id = "generation-release-cap",
        parent_event_id = "generation-release-cap",
        generation = 2,
        source_marble = generation_marble,
    })
    t:eq(#harness.of_type(generation_battle.log, "core_release"), 0,
        "a fourth-generation release attempt is not applied")
    local generation_caps = harness.of_type(generation_battle.log, "cascade_capped")
    t:eq(#generation_caps, 1,
        "the refused fourth-generation release emits one visible cap event")
    t:eq(generation_caps[1].root_event_id, "generation-release-cap",
        "the generation cap retains the original physical root")
    t:eq(generation_caps[1].cap_reason, "generation",
        "the cap evidence names the refused generation")

    local splice_battle, splice_owner, splice, guarded = prepare_splice()
    guarded.hp, guarded.max_hp = 3, 3
    local guarded_ok = engine.trigger_splice_guard(splice_battle, "A", "splice")
    t:eq(guarded_ok, true, "Splice grants its canonical adjacent Guard")
    t:eq(guarded.guard.amount, 1, "Splice Guard is exactly one point")
    engine.trigger_splice_guard(splice_battle, "A", "splice")
    t:eq(guarded.guard.amount, 1, "Splice Guard does not stack")
    local splice_enemy = splice_battle.sides.B.all_marbles[1]
    engine.apply_brick_harm(splice_battle, splice_owner, guarded, 2, {
        source_owner = "B",
        source_entity_id = splice_enemy.uid,
        source_rule_set_id = splice_enemy.shells[1].rule_set.id,
        source_marble = splice_enemy,
        cause = "shrapnel",
        root_event_id = "guard-root",
    })
    t:eq(guarded.hp, 2, "Guard prevents one point of hostile brick damage")
    t:eq(guarded.guard, nil, "the one-point Guard is consumed")

    local parameter_battle, _, parameter_splice, parameter_guarded =
        prepare_splice(function(item)
            for _, guard in ipairs(item.rules) do
                if guard.id == "brick.splice.guard" then
                    guard.magnitude.value = 2
                    guard.duration.value = 17
                    guard.cadence.interval = 2
                end
            end
        end)
    guarded_ok = engine.trigger_splice_guard(
        parameter_battle, "A", parameter_splice.uid
    )
    t:eq(guarded_ok, true, "mutated canonical Splice activates in its first window")
    t:eq(parameter_guarded.guard.amount, 2,
        "Splice runtime reads canonical guard magnitude")
    t:eq(parameter_guarded.guard.expires_tick, parameter_battle.tick + 17,
        "Splice runtime reads canonical guard duration")
    parameter_battle.exchange = 2
    guarded_ok = engine.trigger_splice_guard(
        parameter_battle, "A", parameter_splice.uid
    )
    t:eq(guarded_ok, false, "Splice runtime reads canonical interval cadence")
    parameter_battle.exchange = 3
    guarded_ok = engine.trigger_splice_guard(
        parameter_battle, "A", parameter_splice.uid
    )
    t:eq(guarded_ok, true, "Splice cadence reopens on the canonical interval")

    local tampered_battle, _, tampered_splice, tampered_guarded = prepare_splice()
    for _, guard in ipairs(tampered_splice.rule_set.rules) do
        if guard.id == "brick.splice.guard" then guard.magnitude.value = 9 end
    end
    guarded_ok = engine.trigger_splice_guard(
        tampered_battle, "A", tampered_splice.uid
    )
    t:eq(guarded_ok, false,
        "post-validation passive mutation is rejected by engine-owned identity")
    t:eq(tampered_guarded.guard, nil,
        "post-validation passive mutation cannot reach runtime state")

    local tutorial_state = short_fixtures.to_battle(short_run.new({
        run_seed = 9125,
        short_run = true,
    }))
    local tutorial_battle, tutorial_result = engine.simulate(
        short_run.battle_handoff(tutorial_state)
    )
    t:eq(tutorial_result.outcome, "victory",
        "the legal lone-fuse tutorial still reaches the first refit")
    t:eq(tutorial_result.winner, "player",
        "removing illegal Chain self-damage does not strand the tutorial route")
    t:eq(tutorial_battle.sides.B.formation.alive, 0,
        "the first encounter clears through hostile contact, not allied splash")

    local balance_first = engine.new({
        seed = 17017,
        sides = fixtures.rarity_balance_matchup(),
    })
    local balance_first_result = engine.run(balance_first)
    local balance_second = engine.new({
        seed = 17017,
        sides = fixtures.rarity_balance_matchup(),
    })
    local balance_second_result = engine.run(balance_second)
    local first_hashes = checkpoints.from_recording(engine.recording(balance_first))
    local second_hashes = checkpoints.from_recording(engine.recording(balance_second))
    t:eq(balance_first_result.outcome, "victory",
        "the coherent lower-rarity wall reaches a decisive result")
    t:eq(balance_first_result.winner, "A",
        "the coherent lower-rarity wall defeats the sparse upper-tier set")
    t:eq(balance_second_result.winner, balance_first_result.winner,
        "the rarity balance counterexample repeats its winner")
    t:eq(table.concat(second_hashes, ","), table.concat(first_hashes, ","),
        "the rarity balance counterexample repeats every checkpoint hash")
    t:eq(#first_hashes, 37, "the stored rarity balance trace has 37 checkpoints")
    for index, expected in pairs({
        [1] = "000000:19ae9243",
        [13] = "001440:7c20598e",
        [25] = "002880:00964a05",
        [37] = "004217:0b361697",
    }) do
        t:eq(first_hashes[index], expected,
            "rarity balance checkpoint " .. index .. " matches its stored hash")
    end

    local expected_rarity = {
        basalt_absorber = "common",
        training_dummy = "common",
        mirror_pane = "uncommon",
        moss_regenerator = "uncommon",
        granite_fortifier = "uncommon",
        shatter_crystal = "uncommon",
        vault_arch = "uncommon",
        venom_glass = "rare",
        rime_block = "rare",
        lodestone_block = "rare",
        powder_keg = "rare",
        splice_node = "rare",
        aegis_keystone = "epic",
        void_prism = "epic",
        prismatic_mirror = "epic",
        temporal_anchor = "legendary",
    }
    local roster_count = 0
    for id, rarity in pairs(expected_rarity) do
        roster_count = roster_count + 1
        local item = rules.bricks[id]
        local summary = ast.ability_summary(item)
        local tier = ast.tier(rarity)
        t:eq(item.rarity, rarity, id .. " has canonical rarity")
        t:eq(item.rarity_budget, 100, id .. " uses the fixed 100-point envelope")
        t:ok(summary.count <= tier.brick_passive_groups,
            id .. " stays within its passive-group ceiling")
        t:ok(summary.mcu <= tier.brick_passive_mcu,
            id .. " stays within its MCU ceiling")
        t:ok(item.compatibility.max_copies <= tier.brick_copy_cap,
            id .. " stays within its copy ceiling")
        if rarity == "common" then
            t:eq(summary.count, 0, id .. " has no common passive")
        end
    end
    t:eq(roster_count, 16, "all sixteen behaviour bricks are rarity-validated")
    t:eq(#catalog.brick_reward_pool, 16,
        "all sixteen behaviour bricks enter the canonical individual reward pool")
    t:eq(#catalog.MARBLES, 6,
        "the six comprehension marbles remain player-authorized")
    t:eq(#catalog.LEGACY_MARBLES, 6,
        "the six legacy marbles remain CPU/recording-only")
    t:eq(#catalog.ALL_MARBLES, 12,
        "all twelve current marble blueprints remain schema-validated")
    t:eq(#cores.list, 7, "all seven cores remain canonical components")
    t:eq(#shells.list, 7, "all seven shells remain canonical components")
    t:eq(#catalog.BRICK_KITS, 8, "all eight migrated kits remain available")
    for _, fixture_id in ipairs({ "plain_block", "chalk_block" }) do
        local fixture = bricks.canonical_rule_set(fixture_id)
        t:eq(fixture.rarity, "common", fixture_id .. " is an inert common fixture")
        t:eq(ast.ability_summary(fixture).count, 0,
            fixture_id .. " carries no passive")
        t:eq(fixture.availability.player_draft, false,
            fixture_id .. " cannot enter player draft")
        t:eq(fixture.availability.player_reward, false,
            fixture_id .. " cannot enter player rewards")
    end
    for _, kit in ipairs(catalog.BRICK_KITS) do
        local highest = 0
        for _, brick_id in ipairs(kit.brick_ids) do
            highest = math.max(
                highest,
                ast.rarity_rank(bricks.canonical_rule_set(brick_id).rarity)
            )
        end
        t:eq(ast.rarity_rank(kit.rarity), highest,
            kit.id .. " offer tier equals its highest member")
        t:eq(kit.balance.packaging_only, true,
            kit.id .. " is packaging rather than a shadow power authority")
        local lowered = ast.copy(kit.rule_set)
        local lowered_rank = ast.rarity_rank(kit.rarity) == 1
            and 2
            or ast.rarity_rank(kit.rarity) - 1
        lowered.rarity = ast.rarity_order()[lowered_rank]
        local lowered_valid, lowered_errors = ast.validate(lowered)
        t:eq(lowered_valid, false,
            kit.id .. " rejects an offer tier unlike its highest member")
        t:ok(table.concat(lowered_errors, "; "):find(
            "highest member rarity",
            1,
            true
        ) ~= nil, kit.id .. " reports its forged kit tier")
    end
    t:raises(function()
        draft.instantiate_marble({ content_id = "drifter_common" }, 1, "player")
    end, "not player-draft eligible",
    "a legacy-only marble cannot be forged into a player draft choice")
    local legacy_mutation = ast.copy(catalog.LEGACY_MARBLES[1].rule_set)
    legacy_mutation.availability.player_draft = true
    valid, errors = ast.validate(legacy_mutation)
    t:eq(valid, false, "legacy-only authority cannot opt into player draft")
    t:ok(table.concat(errors, "; "):find("legacy-only", 1, true) ~= nil,
        "legacy availability mutation fails at canonical validation")

    local win_one_state = short_run.new({ run_seed = 17017, short_run = true })
    win_one_state.fight.index = 1
    local legendary_reward_valid, legendary_reward_error =
        short_run.reward_operation_legal(win_one_state, {
            kind = "add_marble",
            content_id = "cinder_legendary",
        })
    t:eq(legendary_reward_valid, false,
        "a legendary add reward is illegal after win one")
    t:eq(legendary_reward_error, "marble_not_reward_eligible",
        "the unavailable win-one tier reports canonical reward illegality")
    local recipe_count = 0
    for _, recipe in ipairs(opponent.recipes()) do
        recipe_count = recipe_count + 1
        local built = opponent.build(17017, recipe.id)
        local recipe_valid, recipe_error = opponent.validate(built)
        t:ok(recipe_valid, recipe.id .. " passes rarity/copy/formation authority: "
            .. tostring(recipe_error or ""))
    end
    t:eq(recipe_count, 3, "all three opponent recipes are fully validated")
    t:eq(ast.resolve("brick.chain.splash"), nil,
        "the old Chain neighbour-damage rule is absent")
    t:eq(ast.resolve("brick.splice.splash"), nil,
        "the old Splice neighbour-damage rule is absent")

    for _, marble in ipairs(catalog.ALL_MARBLES) do
        local tier = ast.tier(marble.rule_set.rarity)
        local summary = ast.ability_summary(marble.rule_set)
        local shell_count = #marble.shells
        t:eq(marble.rule_set.rarity_budget, 100,
            marble.id .. " uses the fixed 100-point envelope")
        t:ok(shell_count >= 1 and shell_count <= tier.shell_cap,
            marble.id .. " obeys its canonical shell cap")
        t:ok(summary.count <= tier.bonus_release_groups,
            marble.id .. " obeys its bonus release ceiling")
        t:ok(summary.mcu <= tier.bonus_release_mcu,
            marble.id .. " obeys its bonus release MCU ceiling")
        if marble.rarity == "common" then
            t:eq(summary.count, 0, marble.id .. " has baseline-only core release")
        end
    end
    for _, core in ipairs(cores.list) do
        t:eq(
            core.min_rarity,
            rules.cores[core.id].min_rarity,
            core.id .. " projects its canonical component minimum"
        )
    end

    local initial_counts = count_rarity("full_loadout_initial")
    local win_one_counts = count_rarity("short_run_win_1")
    local later_counts = count_rarity("short_run_win_2_plus")
    for rarity, expected in pairs({
        common = 50, uncommon = 28, rare = 14, epic = 6, legendary = 2,
    }) do
        t:eq(initial_counts[rarity] or 0, expected,
            "initial 100-ticket table is exact for " .. rarity)
    end
    for rarity, expected in pairs({
        common = 50, uncommon = 32, rare = 18, epic = 0, legendary = 0,
    }) do
        t:eq(win_one_counts[rarity] or 0, expected,
            "win-one 100-ticket table is exact for " .. rarity)
    end
    for rarity, expected in pairs({
        common = 35, uncommon = 30, rare = 20, epic = 12, legendary = 3,
    }) do
        t:eq(later_counts[rarity] or 0, expected,
            "later-win 100-ticket table is exact for " .. rarity)
    end

    local first = ast.copy(catalog.MARBLES[1])
    local alias = ast.copy(first)
    alias.id = "catalogue_alias_for_" .. first.id
    local second = ast.copy(catalog.MARBLES[2])
    local tickets = {
        { tier_ticket = 1, item_ticket = 17 },
        { tier_ticket = 1, item_ticket = 19 },
        { tier_ticket = 1, item_ticket = 23 },
    }
    local sampled, journal = ast.sample_rarity_without_replacement(
        { first, alias, second },
        "full_loadout_initial",
        3,
        tickets
    )
    t:eq(#sampled, 2,
        "undersized reward pool returns every unique identity without replacement")
    t:eq(journal.unique_pool_size, 2,
        "sampling journal records alias-collapsed canonical pool size")
    t:eq(journal.pool_exhausted, true,
        "sampling journal explicitly records undersized pool exhaustion")
    t:ok(ast.content_identity(sampled[1]) ~= ast.content_identity(sampled[2]),
        "weighted sampling never repeats a canonical content identity")
    local repeated = ast.sample_rarity_without_replacement(
        { first, alias, second },
        "full_loadout_initial",
        3,
        tickets
    )
    t:eq(
        table.concat({
            ast.content_identity(sampled[1]), ast.content_identity(sampled[2]),
        }, ","),
        table.concat({
            ast.content_identity(repeated[1]), ast.content_identity(repeated[2]),
        }, ","),
        "fixed tickets reproduce unique reward sampling exactly"
    )
    local conflicting_alias = ast.copy(alias)
    conflicting_alias.rule_set.name = "tampered alias"
    t:raises(function()
        ast.sample_rarity_without_replacement(
            { first, conflicting_alias }, "full_loadout_initial", 2, tickets
        )
    end, "conflicting authority",
        "duplicate catalogue aliases with divergent authority fail closed")
end

if arg and arg[0] and arg[0]:find("test_allied_cost_rarity.lua", 1, true) then
    harness.run_one(M)
end

return M
