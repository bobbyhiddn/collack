-- Comprehension-first three-fight run.
--
-- This is a deliberately small campaign spine layered over the canonical
-- fixed-step battle engine.  It starts with a known sparse collection,
-- alternates setup/battle/refit, preserves casualties, and terminates after
-- exactly three escalating asymmetric encounters.  Content construction is
-- restricted to the 17-item grammar pool in battle/content/draft.lua.

local contract = require("battle.vslice_contract")
local draft = require("battle.draft")
local catalog = require("battle.content.draft")
local rule_ast = require("battle.rule_ast")
local setup_rules = require("battle.setup_rules")
local util = require("battle.run_util")

local M = {}

M.MODE = "comprehension_first_three_fight"
M.SCHEMA_VERSION = 1
M.SAVE_SCHEMA_VERSION = 1
M.RECORD_SCHEMA_VERSION = 1
M.RULES_VERSION = "continuous-v1"
M.CONTENT_VERSION = draft.CONTENT_VERSION

local LIMITS = contract.SHORT_RUN

local STARTING_LOADOUT = {
    sling_id = "momentum",
    marble_ids = { "chalk_common", "quartz_common" },
    bricks = {
        { kit_id = "guard_pair", brick_id = "basalt_absorber" },
        { kit_id = "guard_pair", brick_id = "granite_fortifier" },
        { kit_id = "mirror_anchor", brick_id = "mirror_pane" },
    },
}

-- Counts rise 2/2 -> 3/4 -> 4/5 and each encounter asks a different
-- composition question.  Every referenced sling, marble, and kit is one of
-- the approved 17 items; underlying bricks retain their kit provenance.
local ENCOUNTERS = {
    {
        id = "switchback_scout",
        name = "Switchback Scout",
        description = "A fragile fuse behind one mirror teaches the first side angle.",
        scout_tags = { "rebound", "burst" },
        sling_id = "ricochet",
        marbles = { "chalk_common", "quartz_common" },
        bricks = {
            { "shatter_keg", "powder_keg", 1, 4 },
            { "mirror_anchor", "mirror_pane", 2, 4 },
        },
    },
    {
        id = "fuse_garden",
        name = "Fuse Garden",
        description = "Status lanes pull the opener into a delayed release chain.",
        scout_tags = { "field", "release" },
        sling_id = "effect_amplifier",
        marbles = { "chalk_common", "geode_uncommon", "lodestone_epic" },
        bricks = {
            { "venom_rime", "venom_glass", 1, 2 },
            { "venom_rime", "rime_block", 1, 3 },
            { "shatter_keg", "shatter_crystal", 1, 4 },
            { "shatter_keg", "powder_keg", 1, 5 },
        },
    },
    {
        id = "brass_bastion",
        name = "Brass Bastion",
        description = "The terminal wall combines protection, renewal, and burst.",
        scout_tags = { "guard", "sustain" },
        sling_id = "momentum",
        marbles = {
            "quartz_common", "warden_rare", "lodestone_epic", "cinder_legendary",
        },
        bricks = {
            { "guard_pair", "basalt_absorber", 1, 2 },
            { "guard_pair", "granite_fortifier", 1, 3 },
            { "living_aegis", "moss_regenerator", 1, 4 },
            { "shatter_keg", "shatter_crystal", 1, 5 },
            { "shatter_keg", "powder_keg", 1, 6 },
        },
    },
}

local MARBLE_REWARD_ORDER = {
    "geode_uncommon",
    "warden_rare",
    "lodestone_epic",
    "cinder_legendary",
    "quartz_common",
    "chalk_common",
}

local BRICK_REWARD_ORDER = {
    { "living_aegis", "moss_regenerator" },
    { "living_aegis", "aegis_keystone" },
    { "venom_rime", "venom_glass" },
    { "venom_rime", "rime_block" },
    { "lodestone_void", "lodestone_block" },
    { "lodestone_void", "void_prism" },
    { "shatter_keg", "shatter_crystal" },
    { "shatter_keg", "powder_keg" },
    { "splice_keg", "splice_node" },
    { "vault_temporal", "vault_arch" },
    { "vault_temporal", "temporal_anchor" },
    { "mirror_anchor", "mirror_pane" },
    { "mirror_anchor", "temporal_anchor" },
    { "guard_pair", "basalt_absorber" },
    { "guard_pair", "granite_fortifier" },
}

local SLING_REWARD_ORDER = { "ricochet", "effect_amplifier", "momentum" }

local POOL = { sling = {}, marble = {}, brick_kit = {} }
for _, item in ipairs(catalog.COMPREHENSION_POOL) do
    POOL[item.category][item.id] = true
end

local function assert_pool(category, content_id)
    assert(
        POOL[category] and POOL[category][content_id],
        string.format("%s %s is outside the 17-item comprehension pool",
            tostring(category), tostring(content_id))
    )
end

local function append_journal(state, entry)
    local copy = util.deep_copy(entry)
    copy.seq = #state.journal + 1
    state.journal[#state.journal + 1] = copy
end

local function error_result(state, command, code, message, details)
    return {
        schema_version = 1,
        error = true,
        code = code,
        message = message,
        phase = state and state.phase or nil,
        command = command and (command.kind or command.type) or nil,
        details = util.deep_copy(details),
        state_unchanged = true,
    }
end

local function accepted(state, events)
    return { state = state, events = events or {} }
end

local function empty_formation()
    return setup_rules.empty_formation()
end

local function find_by_uid(items, uid)
    for index, item in ipairs(items or {}) do
        if item.uid == uid then return item, index end
    end
    return nil
end

local function find_cell(formation, uid)
    return setup_rules.find_brick_cell(formation, uid)
end

local function clear_cell(formation, uid)
    local cell = find_cell(formation, uid)
    if cell then formation[cell.row][cell.col] = "." end
    return cell
end

local function rule_ids(rule_set)
    return rule_ast.player_rule_ids(rule_set)
end

local function current_tag_set(state)
    local out = {}
    local function collect(item)
        for _, tag in ipairs((item and item.tags) or {}) do out[tag] = true end
    end
    collect(state.player.sling)
    for _, marble in ipairs(state.player.marbles) do collect(marble) end
    for _, brick in ipairs(state.player.bricks) do collect(brick) end
    return out
end

local function matching_tags(tags, wanted)
    local out = {}
    for _, tag in ipairs(tags or {}) do
        if wanted[tag] then out[#out + 1] = tag end
    end
    return out
end

local function introduced_tags(tags, current)
    local out = {}
    for _, tag in ipairs(tags or {}) do
        if not current[tag] then out[#out + 1] = tag end
    end
    return out
end

local function tag_metadata(tags)
    local out = {}
    for _, id in ipairs(tags or {}) do
        local tag = catalog.TAGS[id]
        out[#out + 1] = {
            id = id,
            label = tag and tag.label or id,
            description = tag and tag.description or "",
        }
    end
    return out
end

local function instantiate_marble(content_id, index, owner)
    assert_pool("marble", content_id)
    return draft.instantiate_marble({ content_id = content_id }, index, owner)
end

local function instantiate_sling(content_id)
    assert_pool("sling", content_id)
    return draft.instantiate_sling({ content_id = content_id })
end

local function instantiate_brick(kit_id, brick_id, index, owner)
    assert_pool("brick_kit", kit_id)
    return draft.instantiate_brick(kit_id, brick_id, index, owner)
end

local function battle_seed(run_seed, fight_index)
    local base = contract.derive_seed(run_seed, "battle")
    return util.normalize_seed(base + fight_index * 49979687, contract.SEED_MODULUS)
end

local function reward_seed(run_seed, fight_index)
    local base = contract.derive_seed(run_seed, "draft")
    return util.normalize_seed(base + fight_index * 67867967, contract.SEED_MODULUS)
end

local function build_encounter(run_seed, fight_index)
    local recipe = assert(ENCOUNTERS[fight_index], "unknown short-run encounter")
    assert_pool("sling", recipe.sling_id)
    local owner = "opponent-f" .. tostring(fight_index)
    local sling = instantiate_sling(recipe.sling_id)
    local marbles = {}
    local bag_order = {}
    local pool_items = {
        { category = "sling", id = recipe.sling_id },
    }
    for index, content_id in ipairs(recipe.marbles) do
        local marble = instantiate_marble(content_id, index, owner)
        marbles[#marbles + 1] = marble
        bag_order[#bag_order + 1] = marble.uid
        pool_items[#pool_items + 1] = { category = "marble", id = content_id }
    end
    local formation = empty_formation()
    local bricks = {}
    local seen_kits = {}
    for index, item in ipairs(recipe.bricks) do
        local kit_id, brick_id, row, col = item[1], item[2], item[3], item[4]
        local brick = instantiate_brick(kit_id, brick_id, index, owner)
        bricks[#bricks + 1] = brick
        formation[row][col] = brick.uid
        if not seen_kits[kit_id] then
            pool_items[#pool_items + 1] = { category = "brick_kit", id = kit_id }
            seen_kits[kit_id] = true
        end
    end
    return {
        schema_version = 1,
        recipe_id = recipe.id,
        encounter_index = fight_index,
        name = recipe.name,
        description = recipe.description,
        scout_tags = util.deep_copy(recipe.scout_tags),
        scout_metadata = tag_metadata(recipe.scout_tags),
        seed = battle_seed(run_seed, fight_index),
        sling = sling,
        sling_id = sling.id,
        marbles = marbles,
        bricks = bricks,
        formation = formation,
        bag_order = bag_order,
        pool_items = pool_items,
        canonical_scout = {
            sling = {
                name = sling.name,
                compact_copy = sling.compact_copy,
                rule_set_id = sling.rule_set.id,
                rule_ids = rule_ids(sling.rule_set),
            },
            marbles = (function()
                local out = {}
                for _, marble in ipairs(marbles) do
                    out[#out + 1] = {
                        name = marble.name,
                        compact_copy = marble.compact_copy,
                        rule_set_id = marble.rule_set.id,
                        rule_ids = rule_ids(marble.rule_set),
                    }
                end
                return out
            end)(),
            bricks = (function()
                local out = {}
                for _, brick in ipairs(bricks) do
                    out[#out + 1] = {
                        name = brick.name,
                        compact_copy = brick.compact_copy,
                        rule_set_id = brick.rule_set.id,
                        rule_ids = rule_ids(brick.rule_set),
                    }
                end
                return out
            end)(),
        },
    }
end

local function route_projection(run_seed)
    local out = {}
    for index, recipe in ipairs(ENCOUNTERS) do
        out[#out + 1] = {
            index = index,
            total = LIMITS.FIGHTS,
            id = recipe.id,
            name = recipe.name,
            description = recipe.description,
            scout_tags = util.deep_copy(recipe.scout_tags),
            marble_count = #recipe.marbles,
            brick_count = #recipe.bricks,
            battle_seed = battle_seed(run_seed, index),
            terminal = index == LIMITS.FIGHTS,
        }
    end
    return out
end

local function setup_loadout(state)
    return {
        sling_id = state.player.sling and state.player.sling.id,
        sling = state.player.sling,
        marbles = state.player.marbles,
        bricks = state.player.bricks,
        formation = state.setup.formation,
        bag_order = state.setup.bag_order,
    }
end

local function setup_error(code, message, field)
    return { code = code, message = message, field = field }
end

local function validate_setup(state)
    local errors = {}
    local marbles = state.player.marbles or {}
    local bricks = state.player.bricks or {}
    if #marbles < 1 or #marbles > LIMITS.MARBLE_CAP then
        errors[#errors + 1] = setup_error(
            "marble_cap",
            string.format("Keep 1–%d marbles in the ordered bag.", LIMITS.MARBLE_CAP),
            "marbles"
        )
    end
    if #bricks < 1 or #bricks > LIMITS.BRICK_CAP then
        errors[#errors + 1] = setup_error(
            "brick_cap",
            string.format("Keep 1–%d bricks in the formation.", LIMITS.BRICK_CAP),
            "bricks"
        )
    end

    local marble_ids = {}
    for _, marble in ipairs(marbles) do
        if marble_ids[marble.uid] then
            errors[#errors + 1] = setup_error(
                "marble_uid_duplicate", "Marble identities must be unique.", "marbles"
            )
        end
        marble_ids[marble.uid] = true
        if not POOL.marble[marble.content_id] then
            errors[#errors + 1] = setup_error(
                "marble_outside_pool", "A marble is outside the comprehension pool.", "marbles"
            )
        end
    end
    local bag_ids = {}
    for _, uid in ipairs(state.setup.bag_order or {}) do
        if not marble_ids[uid] then
            errors[#errors + 1] = setup_error(
                "bag_unknown_marble", "The bag contains an unknown marble.", "bag_order"
            )
        elseif bag_ids[uid] then
            errors[#errors + 1] = setup_error(
                "bag_duplicate_marble", "The bag repeats a marble.", "bag_order"
            )
        end
        bag_ids[uid] = true
    end
    for uid in pairs(marble_ids) do
        if not bag_ids[uid] then
            errors[#errors + 1] = setup_error(
                "bag_missing_marble", "Every active marble must appear in the bag.", "bag_order"
            )
        end
    end

    local brick_ids = {}
    for _, brick in ipairs(bricks) do
        if brick_ids[brick.uid] then
            errors[#errors + 1] = setup_error(
                "brick_uid_duplicate", "Brick identities must be unique.", "bricks"
            )
        end
        brick_ids[brick.uid] = true
        if not POOL.brick_kit[brick.kit_id] then
            errors[#errors + 1] = setup_error(
                "brick_outside_pool", "A brick lacks approved kit provenance.", "bricks"
            )
        end
    end

    local placed = {}
    if #(state.setup.formation or {}) ~= contract.FORMATION.ROWS then
        errors[#errors + 1] = setup_error(
            "formation_rows", "Formation must have exactly three rows.", "formation"
        )
    else
        for row = 1, contract.FORMATION.ROWS do
            local cells = state.setup.formation[row]
            if type(cells) ~= "table" then
                errors[#errors + 1] = setup_error(
                    "formation_row_missing", "A formation row is missing.", "formation"
                )
            else
                for col = 1, contract.FORMATION.COLS do
                    local uid = cells[col]
                    if uid and uid ~= "." then
                        if not brick_ids[uid] then
                            errors[#errors + 1] = setup_error(
                                "formation_unknown_brick",
                                "The formation contains an unknown brick.",
                                "formation"
                            )
                        elseif placed[uid] then
                            errors[#errors + 1] = setup_error(
                                "formation_duplicate_brick",
                                "A brick is placed more than once.",
                                "formation"
                            )
                        end
                        placed[uid] = true
                    end
                end
            end
        end
    end
    for uid in pairs(brick_ids) do
        if not placed[uid] then
            errors[#errors + 1] = setup_error(
                "formation_missing_brick",
                "Place every active brick before locking.",
                "formation"
            )
        end
    end

    local rule_sets = { state.player.sling and state.player.sling.rule_set }
    for _, marble in ipairs(marbles) do rule_sets[#rule_sets + 1] = marble.rule_set end
    for _, brick in ipairs(bricks) do rule_sets[#rule_sets + 1] = brick.rule_set end
    local compatible, compatibility_errors = rule_ast.validate_collection(rule_sets)
    if not compatible then
        for _, message in ipairs(compatibility_errors) do
            errors[#errors + 1] = setup_error(
                "rules_incompatible", message, "loadout"
            )
        end
    end
    return #errors == 0, errors
end

local function refresh_setup(state)
    local valid, errors = validate_setup(state)
    state.setup.valid = valid
    state.setup.errors = errors
    local loadout = setup_loadout(state)
    state.setup.build_tags = setup_rules.build_tags(loadout)
    state.setup.adjacencies = setup_rules.adjacency_preview(loadout)
end

local function starting_player(name)
    local sling = instantiate_sling(STARTING_LOADOUT.sling_id)
    sling.starting = true
    local marbles = {}
    local bag_order = {}
    for index, content_id in ipairs(STARTING_LOADOUT.marble_ids) do
        local marble = instantiate_marble(content_id, index, "player")
        marbles[#marbles + 1] = marble
        bag_order[#bag_order + 1] = marble.uid
    end
    local bricks = {}
    for index, item in ipairs(STARTING_LOADOUT.bricks) do
        bricks[#bricks + 1] =
            instantiate_brick(item.kit_id, item.brick_id, index, "player")
    end
    return {
        id = "player",
        name = name or "Collector",
        sling = sling,
        marbles = marbles,
        bricks = bricks,
    }, bag_order
end

function M.new(options)
    options = options or {}
    local run_seed = util.normalize_seed(options.run_seed, contract.SEED_MODULUS)
    local run_index = math.max(1, math.floor(tonumber(options.run_index) or 1))
    local player, bag_order = starting_player(options.player_name)
    local state = {
        schema_version = M.SCHEMA_VERSION,
        mode = M.MODE,
        run_id = string.format("short-run-%d-%03d", run_seed, run_index),
        run_index = run_index,
        run_seed = run_seed,
        content_version = options.content_version or M.CONTENT_VERSION,
        rules_version = options.rules_version or M.RULES_VERSION,
        phase = contract.PHASE.SETUP,
        domain_seeds = {
            draft = contract.derive_seed(run_seed, "draft"),
            opponent = contract.derive_seed(run_seed, "opponent"),
            battle = battle_seed(run_seed, 1),
        },
        fight = {
            index = 1,
            total = LIMITS.FIGHTS,
            victories = 0,
            history = {},
            route = route_projection(run_seed),
        },
        limits = {
            marbles = LIMITS.MARBLE_CAP,
            bricks = LIMITS.BRICK_CAP,
        },
        player = player,
        opponent = build_encounter(run_seed, 1),
        setup = {
            formation = empty_formation(),
            bag_order = bag_order,
            valid = false,
            errors = {},
            build_tags = {},
            adjacencies = {},
        },
        draft = {
            stage = "refit",
            round = 0,
            offer_index = 0,
            offer = nil,
            picks = {
                sling = { content_id = player.sling.content_id },
                marbles = {},
                brick_kits = {},
            },
        },
        workshop = {
            broken_bricks = {},
            reward_history = {},
            last_attrition = nil,
        },
        next_uid = {
            marble = #player.marbles + 1,
            brick = #player.bricks + 1,
        },
        battle = nil,
        result = nil,
        journal = {},
    }
    append_journal(state, {
        kind = "run_started",
        starting_sling = player.sling.content_id,
        starting_marbles = util.deep_copy(STARTING_LOADOUT.marble_ids),
        starting_bricks = util.deep_copy(STARTING_LOADOUT.bricks),
    })
    refresh_setup(state)
    return state
end

function M.snapshot(state)
    return util.deep_copy(state)
end

function M.loadout(state)
    return util.deep_copy(setup_loadout(state))
end

local function place_command(state, command)
    local updated, placement_error, previous = setup_rules.place(
        setup_loadout(state),
        command.brick_uid,
        command.row,
        command.col
    )
    if not updated then
        return nil, error_result(
            state, command, placement_error.code, placement_error.message, placement_error
        )
    end
    local next_state = util.deep_copy(state)
    next_state.setup.formation = updated.formation
    refresh_setup(next_state)
    append_journal(next_state, {
        kind = "command",
        command = {
            kind = "place_brick",
            brick_uid = command.brick_uid,
            row = command.row,
            col = command.col,
        },
    })
    return accepted(next_state, {
        {
            schema_version = 1,
            type = previous and "brick_moved" or "brick_placed",
            brick_uid = command.brick_uid,
            row = command.row,
            col = command.col,
            previous = util.deep_copy(previous),
        },
    })
end

local function bag_command(state, command)
    local old_index = util.index_of(state.setup.bag_order, command.marble_uid)
    local updated, bag_error = setup_rules.move_bag(
        setup_loadout(state),
        command.marble_uid,
        command.before_uid
    )
    if not updated then
        return nil, error_result(
            state, command, bag_error.code, bag_error.message, bag_error
        )
    end
    local next_state = util.deep_copy(state)
    next_state.setup.bag_order = updated.bag_order
    refresh_setup(next_state)
    append_journal(next_state, {
        kind = "command",
        command = {
            kind = "move_bag",
            marble_uid = command.marble_uid,
            before_uid = command.before_uid,
        },
    })
    return accepted(next_state, {
        {
            schema_version = 1,
            type = "bag_reordered",
            marble_uid = command.marble_uid,
            from = old_index,
            to = util.index_of(next_state.setup.bag_order, command.marble_uid),
            bag_order = util.deep_copy(next_state.setup.bag_order),
        },
    })
end

local function handoff_payload(state)
    return {
        schema_version = 1,
        run_id = state.run_id,
        fight_index = state.fight.index,
        battle_seed = state.domain_seeds.battle,
        rules_version = state.rules_version,
        content_version = state.content_version,
        player = setup_rules.player_spec(setup_loadout(state), state.player.name),
        opponent = util.deep_copy(state.opponent),
    }
end

local function lock_command(state, command)
    local valid, errors = validate_setup(state)
    if not valid then
        return nil, error_result(
            state,
            command,
            "setup_invalid",
            string.format(
                "Place every active brick and order 1–%d marbles.",
                LIMITS.MARBLE_CAP
            ),
            errors
        )
    end
    local next_state = util.deep_copy(state)
    local handoff = handoff_payload(next_state)
    next_state.phase = contract.PHASE.BATTLE
    next_state.battle = {
        schema_version = 1,
        fight_index = next_state.fight.index,
        encounter_id = next_state.opponent.recipe_id,
        status = "handoff",
        tick = 0,
        exchange = 0,
        world = nil,
        pending_events = {},
        recording = nil,
        handoff = util.deep_copy(handoff),
    }
    append_journal(next_state, {
        kind = "command",
        command = { kind = "lock_setup" },
    })
    return accepted(next_state, {
        {
            schema_version = 1,
            type = "phase_changed",
            from = contract.PHASE.SETUP,
            to = contract.PHASE.BATTLE,
        },
        {
            schema_version = 1,
            type = "battle_handoff",
            fight_index = next_state.fight.index,
            handoff = handoff,
        },
    })
end

local function rotated_item(list, seed, predicate)
    local first = (seed % #list) + 1
    for offset = 0, #list - 1 do
        local item = list[((first + offset - 1) % #list) + 1]
        if predicate(item) then return item end
    end
    return nil
end

local function owned_marble_ids(state)
    local out = {}
    for _, marble in ipairs(state.player.marbles) do out[marble.content_id] = true end
    return out
end

local function owned_brick_ids(state)
    local out = {}
    for _, brick in ipairs(state.player.bricks) do out[brick.content_id] = true end
    return out
end

local function candidate_marble(state, seed)
    local owned = owned_marble_ids(state)
    return rotated_item(MARBLE_REWARD_ORDER, seed, function(id)
        return not owned[id]
    end)
end

local function candidate_brick(state, seed)
    local owned = owned_brick_ids(state)
    return rotated_item(BRICK_REWARD_ORDER, seed, function(item)
        return not owned[item[2]]
    end)
end

local function candidate_sling(state, seed)
    return rotated_item(SLING_REWARD_ORDER, seed, function(id)
        return id ~= state.player.sling.content_id
    end)
end

local function canonical_rule_authority(item)
    return rule_ast.player_authority(
        assert(item and item.rule_set, "canonical item rule set is required")
    )
end

local function weakest_marble(state)
    local selected, selected_authority
    for _, marble in ipairs(state.player.marbles) do
        local authority = canonical_rule_authority(marble)
        if not selected
            or authority.balance.spent < selected_authority.balance.spent
            or (authority.balance.spent == selected_authority.balance.spent
                and marble.uid < selected.uid) then
            selected = marble
            selected_authority = authority
        end
    end
    return selected, selected_authority
end

local function first_brick(state)
    local selected
    for _, brick in ipairs(state.player.bricks) do
        if not selected or brick.uid < selected.uid then selected = brick end
    end
    return selected
end

local OPERATION_VERB = {
    add_marble = "ADD",
    add_brick = "ADD",
    replace_marble = "REPLACE",
    replace_brick = "RESHAPE",
    repair_brick = "REPAIR",
    remove_marble = "REMOVE",
    remove_brick = "REMOVE",
    reshape_sling = "RESHAPE",
}

local function operation_copy(operation, state, item)
    local kind = operation.kind
    if kind == "add_marble" then
        return string.format(
            "ADD %s • bag grows from %d to %d of %d.",
            item.name,
            #state.player.marbles,
            #state.player.marbles + 1,
            LIMITS.MARBLE_CAP
        )
    elseif kind == "add_brick" then
        return string.format(
            "ADD %s • formation grows from %d to %d of %d.",
            item.name,
            #state.player.bricks,
            #state.player.bricks + 1,
            LIMITS.BRICK_CAP
        )
    elseif kind == "replace_marble" then
        local target = find_by_uid(state.player.marbles, operation.target_uid)
        return string.format("REPLACE %s with %s • bag size stays %d.",
            target and target.name or "marble", item.name, #state.player.marbles)
    elseif kind == "replace_brick" then
        local target = find_by_uid(state.player.bricks, operation.target_uid)
        return string.format("RESHAPE %s into %s • keep its cell.",
            target and target.name or "brick", item.name)
    elseif kind == "repair_brick" then
        return string.format("REPAIR %s • return one casualty at full integrity.", item.name)
    elseif kind == "remove_marble" then
        local target = find_by_uid(state.player.marbles, operation.target_uid)
        return string.format("REMOVE %s • bag shrinks from %d to %d; cycle the rest sooner.",
            target and target.name or "marble",
            #state.player.marbles,
            #state.player.marbles - 1)
    elseif kind == "remove_brick" then
        local target = find_by_uid(state.player.bricks, operation.target_uid)
        return string.format("REMOVE %s • formation shrinks from %d to %d; free one slot.",
            target and target.name or "brick",
            #state.player.bricks,
            #state.player.bricks - 1)
    elseif kind == "reshape_sling" then
        return string.format("RESHAPE %s into %s • preserve the run, change its macro rule.",
            state.player.sling.name, item.name)
    end
    error("unknown reward operation: " .. tostring(kind))
end

local function reward_choice(state, slot, operation, item, category, next_opponent)
    local current = current_tag_set(state)
    local scout = util.set(next_opponent.scout_tags)
    local tags = item.tags or item.rule_set.synergy_tags
    local authority = canonical_rule_authority(item)
    local operation_text = operation_copy(operation, state, item)
    return {
        choice_id = string.format(
            "refit:%02d:%d:%s:%s",
            state.fight.index,
            slot,
            operation.kind,
            item.content_id or item.id
        ),
        content_id = item.content_id or item.id,
        content_ids = { item.content_id or item.id },
        category = category,
        operation = util.deep_copy(operation),
        operation_verb = OPERATION_VERB[operation.kind],
        operation_copy = operation_text,
        name = item.name,
        role = operation.kind:gsub("_", " "),
        rarity = item.rarity,
        draft_value = authority.rarity_budget,
        mechanics = util.deep_copy(authority.compact_lines),
        compact_copy = authority.compact_copy,
        inspection_copy = util.deep_copy(authority.inspection_copy),
        rule_set = util.deep_copy(item.rule_set),
        compatibility = util.deep_copy(item.rule_set.compatibility),
        balance = util.deep_copy(authority.balance),
        tags = util.deep_copy(tags),
        tag_metadata = tag_metadata(tags),
        synergy = {
            matched = matching_tags(tags, current),
            introduced = introduced_tags(tags, current),
            counters = matching_tags(item.counter_tags or tags, scout),
        },
        suggested_placement = item.suggested_placement,
        art_id = item.art_id,
        details = util.deep_copy(item.details),
        causal_attribution = {
            cause = "post_battle_choice",
            fight_index = state.fight.index,
            operation = operation.kind,
            target_uid = operation.target_uid,
            target_authority = util.deep_copy(operation.target_authority),
            source_rule_set_id = authority.rule_set_id,
            source_rule_ids = util.deep_copy(authority.rule_ids),
            generated_compact_copy = authority.compact_copy,
            generated_operation_copy = operation_text,
        },
    }
end

local function marble_item(content_id)
    return assert(catalog.marble_by_id[content_id], "unknown reward marble")
end

local function brick_item(kit_id, brick_id)
    local brick = instantiate_brick(kit_id, brick_id, 1, "reward")
    brick.content_id = brick_id
    return brick
end

local function sling_item(content_id)
    return instantiate_sling(content_id)
end

local function reward_operations(state)
    local seed = reward_seed(state.run_seed, state.fight.index)
    local operations = {}
    local marble_id = candidate_marble(state, seed)
    local brick_spec = candidate_brick(state, seed + 17)
    local sling_id = candidate_sling(state, seed + 31)

    if state.fight.index == 1 then
        if #state.player.marbles < LIMITS.MARBLE_CAP and marble_id then
            operations[#operations + 1] = {
                operation = { kind = "add_marble", content_id = marble_id },
                item = marble_item(marble_id),
                category = "marble",
            }
        end
        if #state.player.bricks < LIMITS.BRICK_CAP and brick_spec then
            operations[#operations + 1] = {
                operation = {
                    kind = "add_brick",
                    kit_id = brick_spec[1],
                    content_id = brick_spec[2],
                },
                item = brick_item(brick_spec[1], brick_spec[2]),
                category = "brick_kit",
            }
        end
        local target = first_brick(state)
        if target and brick_spec then
            operations[#operations + 1] = {
                operation = {
                    kind = "replace_brick",
                    target_uid = target.uid,
                    kit_id = brick_spec[1],
                    content_id = brick_spec[2],
                },
                item = brick_item(brick_spec[1], brick_spec[2]),
                category = "brick_kit",
            }
        end
    else
        if #state.player.bricks < LIMITS.BRICK_CAP and brick_spec then
            operations[#operations + 1] = {
                operation = {
                    kind = "add_brick",
                    kit_id = brick_spec[1],
                    content_id = brick_spec[2],
                },
                item = brick_item(brick_spec[1], brick_spec[2]),
                category = "brick_kit",
            }
        end
        if sling_id then
            operations[#operations + 1] = {
                operation = { kind = "reshape_sling", content_id = sling_id },
                item = sling_item(sling_id),
                category = "sling",
            }
        end
        local broken = state.workshop.broken_bricks[1]
        if broken then
            operations[#operations + 1] = {
                operation = {
                    kind = "repair_brick",
                    target_uid = broken.brick.uid,
                    broken_index = 1,
                    kit_id = broken.brick.kit_id,
                    content_id = broken.brick.content_id,
                },
                item = util.deep_copy(broken.brick),
                category = "brick_kit",
            }
        elseif #state.player.marbles > LIMITS.START_MARBLES then
            local target, target_authority = weakest_marble(state)
            operations[#operations + 1] = {
                operation = {
                    kind = "remove_marble",
                    target_uid = target.uid,
                    content_id = target.content_id,
                    target_authority = target_authority,
                },
                item = util.deep_copy(target),
                category = "marble",
            }
        elseif marble_id then
            local target, target_authority = weakest_marble(state)
            operations[#operations + 1] = {
                operation = {
                    kind = "replace_marble",
                    target_uid = target.uid,
                    content_id = marble_id,
                    target_authority = target_authority,
                },
                item = marble_item(marble_id),
                category = "marble",
            }
        end
    end

    -- Cap or casualty edge cases can remove a primary operation.  Fill with
    -- exact, legal replacement/removal operations rather than emitting a
    -- dead card.
    if #operations < LIMITS.OFFER_SIZE and marble_id and #state.player.marbles > 0 then
        local target, target_authority = weakest_marble(state)
        operations[#operations + 1] = {
            operation = {
                kind = "replace_marble",
                target_uid = target.uid,
                content_id = marble_id,
                target_authority = target_authority,
            },
            item = marble_item(marble_id),
            category = "marble",
        }
    end
    if #operations < LIMITS.OFFER_SIZE and #state.player.bricks > 1 then
        local target = first_brick(state)
        operations[#operations + 1] = {
            operation = {
                kind = "remove_brick",
                target_uid = target.uid,
                kit_id = target.kit_id,
                content_id = target.content_id,
            },
            item = util.deep_copy(target),
            category = "brick_kit",
        }
    end
    if #operations < LIMITS.OFFER_SIZE and sling_id then
        operations[#operations + 1] = {
            operation = { kind = "reshape_sling", content_id = sling_id },
            item = sling_item(sling_id),
            category = "sling",
        }
    end
    assert(#operations >= LIMITS.OFFER_SIZE, "short-run reward pool cannot fill three choices")
    while #operations > LIMITS.OFFER_SIZE do table.remove(operations) end
    return operations, seed
end

local function make_reward_offer(state)
    local next_opponent = build_encounter(state.run_seed, state.fight.index + 1)
    local operations, seed = reward_operations(state)
    local choices = {}
    for index, spec in ipairs(operations) do
        choices[#choices + 1] = reward_choice(
            state,
            index,
            spec.operation,
            spec.item,
            spec.category,
            next_opponent
        )
    end
    return {
        schema_version = 1,
        offer_id = string.format("%s:refit:%02d", state.run_id, state.fight.index),
        category = "refit",
        stage = "refit",
        round = state.fight.index,
        offer_seed = seed,
        choices = choices,
        build_tags = util.sorted_keys(current_tag_set(state)),
        scout_tags = util.deep_copy(next_opponent.scout_tags),
        next_encounter = {
            index = state.fight.index + 1,
            recipe_id = next_opponent.recipe_id,
            name = next_opponent.name,
            description = next_opponent.description,
            marble_count = #next_opponent.marbles,
            brick_count = #next_opponent.bricks,
            canonical_scout = util.deep_copy(next_opponent.canonical_scout),
        },
    }
end

local function target_authority_matches(target, expected)
    return type(expected) == "table"
        and util.deep_equal(canonical_rule_authority(target), expected)
end

local function apply_operation(state, operation)
    local kind = operation.kind
    if kind == "add_marble" then
        if #state.player.marbles >= LIMITS.MARBLE_CAP then
            return nil, "marble_cap"
        end
        local marble = instantiate_marble(
            operation.content_id,
            state.next_uid.marble,
            "player"
        )
        state.next_uid.marble = state.next_uid.marble + 1
        state.player.marbles[#state.player.marbles + 1] = marble
        state.setup.bag_order[#state.setup.bag_order + 1] = marble.uid
    elseif kind == "add_brick" then
        if #state.player.bricks >= LIMITS.BRICK_CAP then
            return nil, "brick_cap"
        end
        local brick = instantiate_brick(
            operation.kit_id,
            operation.content_id,
            state.next_uid.brick,
            "player"
        )
        state.next_uid.brick = state.next_uid.brick + 1
        state.player.bricks[#state.player.bricks + 1] = brick
    elseif kind == "replace_marble" then
        local target, index = find_by_uid(state.player.marbles, operation.target_uid)
        if not target then return nil, "target_missing" end
        if not target_authority_matches(target, operation.target_authority) then
            return nil, "target_authority_changed"
        end
        local replacement = instantiate_marble(operation.content_id, 1, "replacement")
        replacement.uid = target.uid
        state.player.marbles[index] = replacement
    elseif kind == "replace_brick" then
        local target, index = find_by_uid(state.player.bricks, operation.target_uid)
        if not target then return nil, "target_missing" end
        local replacement = instantiate_brick(
            operation.kit_id,
            operation.content_id,
            1,
            "replacement"
        )
        replacement.uid = target.uid
        state.player.bricks[index] = replacement
    elseif kind == "repair_brick" then
        local broken = state.workshop.broken_bricks[operation.broken_index or 1]
        if not broken or broken.brick.uid ~= operation.target_uid then
            return nil, "casualty_missing"
        end
        if #state.player.bricks >= LIMITS.BRICK_CAP then
            return nil, "brick_cap"
        end
        local repaired = util.deep_copy(broken.brick)
        repaired.hp = repaired.max_hp
        state.player.bricks[#state.player.bricks + 1] = repaired
        if broken.cell
            and state.setup.formation[broken.cell.row][broken.cell.col] == "." then
            state.setup.formation[broken.cell.row][broken.cell.col] = repaired.uid
        end
        table.remove(state.workshop.broken_bricks, operation.broken_index or 1)
    elseif kind == "remove_marble" then
        if #state.player.marbles <= 1 then return nil, "last_marble" end
        local target, index = find_by_uid(state.player.marbles, operation.target_uid)
        if not index then return nil, "target_missing" end
        if not target_authority_matches(target, operation.target_authority) then
            return nil, "target_authority_changed"
        end
        table.remove(state.player.marbles, index)
        local bag_index = util.index_of(state.setup.bag_order, operation.target_uid)
        if bag_index then table.remove(state.setup.bag_order, bag_index) end
    elseif kind == "remove_brick" then
        if #state.player.bricks <= 1 then return nil, "last_brick" end
        local _, index = find_by_uid(state.player.bricks, operation.target_uid)
        if not index then return nil, "target_missing" end
        clear_cell(state.setup.formation, operation.target_uid)
        table.remove(state.player.bricks, index)
    elseif kind == "reshape_sling" then
        state.player.sling = instantiate_sling(operation.content_id)
    else
        return nil, "operation_unknown"
    end
    return true
end

local function choose_reward(state, command)
    local offer = state.draft.offer
    if not offer or command.offer_id ~= offer.offer_id then
        return nil, error_result(
            state,
            command,
            "offer_stale",
            "That refit offer is no longer active.",
            { expected_offer_id = offer and offer.offer_id or nil }
        )
    end
    local choice = draft.find_choice(offer, command.choice_id)
    if not choice then
        return nil, error_result(
            state,
            command,
            "choice_unknown",
            "Choose one of the three visible refit cards.",
            { offer_id = offer.offer_id }
        )
    end
    local next_state = util.deep_copy(state)
    local applied, apply_error = apply_operation(next_state, choice.operation)
    if not applied then
        return nil, error_result(
            state,
            command,
            "reward_invalid",
            "That refit is no longer legal.",
            { reason = apply_error }
        )
    end
    next_state.workshop.reward_history[#next_state.workshop.reward_history + 1] = {
        fight_index = next_state.fight.index,
        offer_id = offer.offer_id,
        choice_id = choice.choice_id,
        operation = util.deep_copy(choice.operation),
        operation_copy = choice.operation_copy,
        causal_attribution = util.deep_copy(choice.causal_attribution),
    }
    append_journal(next_state, {
        kind = "command",
        command = {
            kind = "choose_offer",
            offer_id = command.offer_id,
            choice_id = command.choice_id,
        },
    })

    local previous_fight = next_state.fight.index
    next_state.fight.index = next_state.fight.index + 1
    next_state.domain_seeds.battle = battle_seed(next_state.run_seed, next_state.fight.index)
    next_state.opponent = build_encounter(next_state.run_seed, next_state.fight.index)
    next_state.phase = contract.PHASE.SETUP
    next_state.draft.offer = nil
    next_state.draft.round = next_state.fight.index - 1
    next_state.battle = nil
    next_state.result = nil
    refresh_setup(next_state)
    return accepted(next_state, {
        {
            schema_version = 1,
            type = "reward_chosen",
            fight_index = previous_fight,
            choice_id = choice.choice_id,
            operation = choice.operation.kind,
            operation_copy = choice.operation_copy,
            causal_attribution = util.deep_copy(choice.causal_attribution),
        },
        {
            schema_version = 1,
            type = "phase_changed",
            from = contract.PHASE.DRAFT,
            to = contract.PHASE.SETUP,
        },
        {
            schema_version = 1,
            type = "encounter_scouted",
            fight_index = next_state.fight.index,
            opponent = util.deep_copy(next_state.opponent),
        },
    })
end

local function new_run_command(state)
    local next_state = M.new({
        run_seed = util.next_seed(state.run_seed, contract.SEED_MODULUS),
        run_index = state.run_index + 1,
        content_version = state.content_version,
        rules_version = state.rules_version,
        player_name = state.player.name,
    })
    return accepted(next_state, {
        {
            schema_version = 1,
            type = "new_run",
            previous_run_id = state.run_id,
            run_id = next_state.run_id,
            run_seed = next_state.run_seed,
        },
    })
end

function M.dispatch(state, command)
    if type(state) ~= "table" or state.mode ~= M.MODE then
        return nil, error_result(state, command, "state_invalid", "ShortRunState is required.")
    end
    local kind = type(command) == "table" and (command.kind or command.type) or nil
    if not kind then
        return nil, error_result(state, command, "command_invalid", "Command kind is required.")
    end
    if state.phase == contract.PHASE.DRAFT and kind == "choose_offer" then
        return choose_reward(state, command)
    elseif state.phase == contract.PHASE.SETUP and kind == "place_brick" then
        return place_command(state, command)
    elseif state.phase == contract.PHASE.SETUP and kind == "move_bag" then
        return bag_command(state, command)
    elseif state.phase == contract.PHASE.SETUP and kind == "lock_setup" then
        return lock_command(state, command)
    elseif state.phase == contract.PHASE.RESULT and kind == "new_run" then
        return new_run_command(state)
    end
    return nil, error_result(
        state,
        command,
        "command_out_of_phase",
        string.format("%s is not allowed during %s.", tostring(kind), state.phase)
    )
end

local function plain_value(value, seen)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then
        return true
    end
    if kind ~= "table" or getmetatable(value) ~= nil then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, item in pairs(value) do
        if not plain_value(key, seen) or not plain_value(item, seen) then return false end
    end
    seen[value] = nil
    return true
end

local function validate_completion(state, completion)
    if state.phase ~= contract.PHASE.BATTLE then
        return nil, error_result(
            state,
            { kind = "battle_complete" },
            "battle_not_active",
            "A battle result is accepted only during automatic battle."
        )
    end
    if type(completion) ~= "table"
        or type(completion.result) ~= "table"
        or type(completion.recording) ~= "table"
        or completion.recording.schema_version ~= 1
        or type(completion.recording.frames) ~= "table"
        or type(completion.recording.events) ~= "table"
        or type(completion.recording.keyframes) ~= "table"
        or type(completion.recording.result) ~= "table"
        or type(completion.recording.final) ~= "table"
        or type(completion.recording.final.sides) ~= "table"
        or type(completion.recording.final.sides.A) ~= "table"
        or type(completion.recording.final.sides.A.bricks) ~= "table"
        or #completion.recording.frames == 0
        or #completion.recording.keyframes == 0 then
        return nil, error_result(
            state,
            { kind = "battle_complete" },
            "battle_recording_invalid",
            "Battle completion needs frames, keyframes, events, and a final attrition snapshot."
        )
    end
    if not plain_value(completion) then
        return nil, error_result(
            state,
            { kind = "battle_complete" },
            "battle_completion_not_serializable",
            "Battle completion values must be plain serializable data."
        )
    end
    local result = completion.result
    local recorded = completion.recording.result
    if type(result.outcome) ~= "string"
        or type(result.reason) ~= "string"
        or not util.is_integer(result.exchanges or 0)
        or recorded.outcome ~= result.outcome
        or recorded.winner ~= result.winner
        or recorded.reason ~= result.reason
        or recorded.exchanges ~= result.exchanges then
        return nil, error_result(
            state,
            { kind = "battle_complete" },
            "battle_recording_mismatch",
            "The final recording result must match the canonical battle result."
        )
    end
    return true
end

local function apply_attrition(state, recording)
    local final_by_uid = {}
    for _, brick in ipairs(recording.final.sides.A.bricks or {}) do
        final_by_uid[brick.uid] = brick
    end
    local survivors = {}
    local casualties = {}
    for _, brick in ipairs(state.player.bricks) do
        local final = final_by_uid[brick.uid]
        if final and final.alive ~= false and (final.hp or 0) > 0 then
            local restored = util.deep_copy(brick)
            -- The approved economy uses casualty-only attrition: a survivor
            -- is ready next fight, while a destroyed brick becomes a repair
            -- candidate.
            restored.hp = restored.max_hp
            survivors[#survivors + 1] = restored
        else
            local casualty = {
                fight_index = state.fight.index,
                brick = util.deep_copy(brick),
                cell = find_cell(state.setup.formation, brick.uid),
            }
            casualties[#casualties + 1] = casualty
            state.workshop.broken_bricks[#state.workshop.broken_bricks + 1] =
                util.deep_copy(casualty)
            clear_cell(state.setup.formation, brick.uid)
        end
    end
    state.player.bricks = survivors
    state.workshop.last_attrition = {
        fight_index = state.fight.index,
        casualties = util.deep_copy(casualties),
        surviving_bricks = #survivors,
    }
    return casualties
end

local function causal_ledger(recording)
    local out = {}
    for _, event in ipairs(recording.events or {}) do
        if event.rule_id then
            out[#out + 1] = {
                seq = event.seq,
                tick = event.tick,
                event_type = event.type,
                rule_id = event.rule_id,
                rule_source = event.rule_source,
                rule_role = event.rule_role,
                rule_operation = event.rule_operation,
                rule_target = event.rule_target,
                rule_magnitude = event.rule_magnitude,
                rule_unit = event.rule_unit,
                generated_callout = assert(
                    rule_ast.callout(event),
                    "attributed combat trigger lacks generated callout"
                ),
            }
        end
    end
    return out
end

function M.complete_battle(state, completion)
    local valid, completion_error = validate_completion(state, completion)
    if not valid then return nil, completion_error end
    local next_state = util.deep_copy(state)
    next_state.battle.status = "finished"
    next_state.battle.tick = completion.final_tick
        or completion.recording.final_tick
        or next_state.battle.tick
    next_state.battle.exchange = completion.result.exchanges
    next_state.battle.world = nil
    next_state.battle.pending_events = {}
    next_state.battle.recording = util.deep_copy(completion.recording)
    next_state.battle.checkpoint_hashes =
        util.deep_copy(completion.checkpoint_hashes or {})

    local casualties = apply_attrition(next_state, completion.recording)
    local won = completion.result.outcome == "victory"
        and completion.result.winner == "player"
    local history = {
        fight_index = next_state.fight.index,
        encounter_id = next_state.opponent.recipe_id,
        opponent = util.deep_copy(next_state.opponent),
        result = util.deep_copy(completion.result),
        recording = util.deep_copy(completion.recording),
        checkpoint_hashes = util.deep_copy(completion.checkpoint_hashes or {}),
        casualties = util.deep_copy(casualties),
        causal_ledger = causal_ledger(completion.recording),
    }
    next_state.fight.history[#next_state.fight.history + 1] = history
    append_journal(next_state, {
        kind = "battle_completed",
        fight_index = next_state.fight.index,
        encounter_id = next_state.opponent.recipe_id,
        result = util.deep_copy(completion.result),
        casualty_uids = (function()
            local out = {}
            for _, casualty in ipairs(casualties) do
                out[#out + 1] = casualty.brick.uid
            end
            return out
        end)(),
    })

    local events = {
        {
            schema_version = 1,
            type = "fight_result",
            fight_index = next_state.fight.index,
            won = won,
            result = util.deep_copy(completion.result),
            casualties = util.deep_copy(casualties),
        },
    }
    if won then next_state.fight.victories = next_state.fight.victories + 1 end

    if won and next_state.fight.index < LIMITS.FIGHTS then
        next_state.phase = contract.PHASE.DRAFT
        next_state.result = nil
        next_state.draft.offer_index = next_state.fight.index
        next_state.draft.round = next_state.fight.index
        next_state.draft.offer = make_reward_offer(next_state)
        append_journal(next_state, {
            kind = "offer_generated",
            offer = util.deep_copy(next_state.draft.offer),
        })
        events[#events + 1] = {
            schema_version = 1,
            type = "phase_changed",
            from = contract.PHASE.BATTLE,
            to = contract.PHASE.DRAFT,
        }
        events[#events + 1] = {
            schema_version = 1,
            type = "reward_offer_generated",
            fight_index = next_state.fight.index,
            offer = util.deep_copy(next_state.draft.offer),
        }
    else
        next_state.phase = contract.PHASE.RESULT
        if won then
            next_state.result = {
                schema_version = 1,
                outcome = "victory",
                winner = "player",
                reason = "three_fights_cleared",
                exchanges = completion.result.exchanges,
                fights_cleared = LIMITS.FIGHTS,
                terminal = true,
                battle_reason = completion.result.reason,
            }
        else
            next_state.result = {
                schema_version = 1,
                outcome = "defeat",
                winner = completion.result.winner or "opponent",
                reason = "run_ended_at_fight_" .. tostring(next_state.fight.index),
                exchanges = completion.result.exchanges,
                fights_cleared = next_state.fight.victories,
                terminal = true,
                battle_reason = completion.result.reason,
            }
        end
        events[#events + 1] = {
            schema_version = 1,
            type = "phase_changed",
            from = contract.PHASE.BATTLE,
            to = contract.PHASE.RESULT,
        }
        events[#events + 1] = {
            schema_version = 1,
            type = "run_result",
            result = util.deep_copy(next_state.result),
        }
    end
    refresh_setup(next_state)
    return accepted(next_state, events)
end

function M.battle_handoff(state)
    if not state.battle or not state.battle.handoff then return nil end
    return util.deep_copy(state.battle.handoff)
end

function M.save(state)
    if type(state) ~= "table" or state.mode ~= M.MODE then
        return nil, {
            schema_version = 1,
            error = true,
            code = "state_invalid",
            message = "ShortRunState is required.",
        }
    end
    if state.phase == contract.PHASE.BATTLE then
        return nil, {
            schema_version = 1,
            error = true,
            code = "battle_save_unsupported",
            message = "Save at setup, refit, or the terminal result boundary.",
        }
    end
    return {
        schema_version = M.SAVE_SCHEMA_VERSION,
        kind = "callack_short_run_save",
        content_version = state.content_version,
        rules_version = state.rules_version,
        state = util.deep_copy(state),
    }
end

function M.load(save)
    if type(save) ~= "table"
        or save.schema_version ~= M.SAVE_SCHEMA_VERSION
        or save.kind ~= "callack_short_run_save"
        or type(save.state) ~= "table"
        or save.state.mode ~= M.MODE then
        return nil, {
            schema_version = 1,
            error = true,
            code = "save_invalid",
            message = "A versioned short-run save is required.",
        }
    end
    if save.content_version ~= M.CONTENT_VERSION
        or save.rules_version ~= M.RULES_VERSION
        or save.state.content_version ~= save.content_version
        or save.state.rules_version ~= save.rules_version then
        return nil, {
            schema_version = 1,
            error = true,
            code = "save_version_mismatch",
            message = "This save belongs to a different content or rules build.",
        }
    end
    if not plain_value(save.state) or save.state.phase == contract.PHASE.BATTLE then
        return nil, {
            schema_version = 1,
            error = true,
            code = "save_state_invalid",
            message = "The saved state is not a serializable run boundary.",
        }
    end
    local state = util.deep_copy(save.state)
    refresh_setup(state)
    return state
end

function M.record(state)
    if type(state) ~= "table"
        or state.mode ~= M.MODE
        or state.phase ~= contract.PHASE.RESULT
        or not state.result then
        return nil, {
            schema_version = 1,
            error = true,
            code = "run_not_finished",
            message = "A replay record is available only after terminal win or loss.",
        }
    end
    return {
        schema_version = M.RECORD_SCHEMA_VERSION,
        mode = M.MODE,
        run_id = state.run_id,
        run_index = state.run_index,
        run_seed = state.run_seed,
        content_version = state.content_version,
        rules_version = state.rules_version,
        journal = util.deep_copy(state.journal),
        fights = util.deep_copy(state.fight.history),
        result = util.deep_copy(state.result),
        final_state = util.deep_copy(state),
    }
end

local function replay_error(code, message, details)
    return {
        schema_version = 1,
        error = true,
        code = code,
        message = message,
        details = util.deep_copy(details),
    }
end

function M.replay(record)
    if type(record) ~= "table"
        or record.schema_version ~= M.RECORD_SCHEMA_VERSION
        or record.mode ~= M.MODE
        or type(record.journal) ~= "table"
        or type(record.fights) ~= "table" then
        return nil, replay_error("record_invalid", "A versioned short-run record is required.")
    end
    if record.content_version ~= M.CONTENT_VERSION
        or record.rules_version ~= M.RULES_VERSION then
        return nil, replay_error(
            "record_version_mismatch",
            "This replay belongs to a different content or rules build."
        )
    end
    local player_name = record.final_state
        and record.final_state.player
        and record.final_state.player.name
        or "Collector"
    local state = M.new({
        run_seed = record.run_seed,
        run_index = record.run_index,
        content_version = record.content_version,
        rules_version = record.rules_version,
        player_name = player_name,
    })
    local fight_index = 1
    for _, entry in ipairs(record.journal) do
        if entry.kind == "command" then
            local result, command_error = M.dispatch(state, entry.command)
            if not result then
                return nil, replay_error(
                    "journal_command_failed",
                    "A recorded command is no longer legal.",
                    command_error
                )
            end
            state = result.state
        elseif entry.kind == "battle_completed" then
            local fight = record.fights[fight_index]
            if not fight then
                return nil, replay_error(
                    "fight_recording_missing",
                    "The journal references a missing fight recording."
                )
            end
            local completed, completion_error = M.complete_battle(state, {
                final_tick = fight.recording.final_tick,
                result = fight.result,
                recording = fight.recording,
                checkpoint_hashes = fight.checkpoint_hashes,
            })
            if not completed then
                return nil, replay_error(
                    "fight_recording_rejected",
                    "A recorded fight could not be restored.",
                    completion_error
                )
            end
            state = completed.state
            fight_index = fight_index + 1
        end
    end
    if state.phase ~= contract.PHASE.RESULT
        or not util.deep_equal(state.result, record.result)
        or not util.deep_equal(state.player, record.final_state.player)
        or not util.deep_equal(state.setup, record.final_state.setup)
        or not util.deep_equal(state.workshop, record.final_state.workshop) then
        return nil, replay_error(
            "replay_mismatch",
            "Same-build replay did not reconstruct the terminal run."
        )
    end
    return state
end

function M.state_machine()
    return {
        {
            phase = "setup",
            fight = 1,
            commands = { "place_brick", "move_bag", "lock_setup" },
            next = "battle",
        },
        { phase = "battle", commands = {}, completion = "engine", next = "draft|result" },
        { phase = "draft", label = "refit", command = "choose_offer", next = "setup" },
        { phase = "setup", fights = { 2, 3 }, next = "battle" },
        { phase = "result", terminal = true, command = "new_run", next = "setup" },
    }
end

function M.encounters()
    return util.deep_copy(ENCOUNTERS)
end

function M.starting_loadout()
    return util.deep_copy(STARTING_LOADOUT)
end

function M.pool_membership()
    return util.deep_copy(POOL)
end

function M.preview_reward_offer(state)
    if type(state) ~= "table"
        or state.mode ~= M.MODE
        or state.fight.index >= LIMITS.FIGHTS then
        return nil
    end
    return util.deep_copy(make_reward_offer(state))
end

function M.validate_setup_state(state)
    return validate_setup(state)
end

return M
