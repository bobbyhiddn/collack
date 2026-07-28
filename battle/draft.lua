-- Deterministic curated offer generation.  This module owns no run
-- progression; battle/run.lua asks it for the next offer and instantiates the
-- selected individual content.

local contract = require("battle.vslice_contract")
local RNG = require("battle.rng")
local catalog = require("battle.content.draft")
local slings = require("battle.content.slings")
local cores = require("battle.content.cores")
local shells = require("battle.content.shells")
local bricks = require("battle.content.bricks")
local rule_ast = require("battle.rule_ast")
local util = require("battle.run_util")

local M = {}

M.CONTENT_VERSION = catalog.VERSION

local function tags_from_item(item, out)
    for _, tag in ipairs((item and item.tags) or {}) do out[tag] = true end
end

function M.current_tag_set(state)
    local out = {}
    tags_from_item(state.player and state.player.sling, out)
    for _, marble in ipairs((state.player and state.player.marbles) or {}) do
        tags_from_item(marble, out)
    end
    for _, brick in ipairs((state.player and state.player.bricks) or {}) do
        tags_from_item(brick, out)
    end
    return out
end

function M.current_tags(state)
    return util.sorted_keys(M.current_tag_set(state))
end

function M.stage_for(picks)
    picks = picks or {}
    if not picks.sling then return "sling", 1 end
    if #(picks.marbles or {}) < contract.DRAFT.MARBLE_PICKS then
        return "marble", #(picks.marbles or {}) + 1
    end
    if #(picks.brick_kits or {}) < contract.DRAFT.BRICK_KIT_PICKS then
        return "brick_kit", #(picks.brick_kits or {}) + 1
    end
    return "complete", 1
end

local function pool_for(category)
    if category == "sling" then return catalog.SLINGS end
    if category == "marble" then return catalog.MARBLES end
    if category == "brick_kit" then return catalog.BRICK_KITS end
    error("unknown draft category: " .. tostring(category))
end

local function selected_ids(state, category)
    local selected = {}
    if category == "marble" then
        for _, marble in ipairs(state.player.marbles or {}) do
            selected[marble.content_id] = true
        end
    elseif category == "brick_kit" then
        for _, kit in ipairs(state.draft.picks.brick_kits or {}) do
            selected[kit.content_id] = true
        end
    end
    return selected
end

local function shuffled_available(state, category)
    local selected = selected_ids(state, category)
    local available = {}
    for _, item in ipairs(pool_for(category)) do
        if not selected[item.id] then available[#available + 1] = item end
    end

    local offer_index = state.draft.offer_index or 1
    local seed = util.normalize_seed(
        state.domain_seeds.draft + offer_index * 32452843,
        contract.SEED_MODULUS
    )
    local rng = RNG.new(seed)
    for index = #available, 2, -1 do
        local swap = rng:int(1, index)
        available[index], available[swap] = available[swap], available[index]
    end
    return available, seed
end

local function intersects(tags, wanted)
    for _, tag in ipairs(tags or {}) do
        if wanted[tag] then return true end
    end
    return false
end

local function introduces(tags, current)
    for _, tag in ipairs(tags or {}) do
        if not current[tag] then return true end
    end
    return false
end

local function pick_where(candidates, used, predicate)
    for _, candidate in ipairs(candidates) do
        if not used[candidate.id] and predicate(candidate) then
            used[candidate.id] = true
            return candidate
        end
    end
    return nil
end

local function curated_choices(state, category)
    local candidates, offer_seed = shuffled_available(state, category)
    local current = M.current_tag_set(state)
    local scouts = util.set(state.opponent and state.opponent.scout_tags or {})
    local used, chosen = {}, {}

    if next(current) ~= nil then
        local shared = pick_where(candidates, used, function(candidate)
            return intersects(candidate.tags, current)
        end)
        if shared then chosen[#chosen + 1] = shared end

        local new_direction = pick_where(candidates, used, function(candidate)
            return not intersects(candidate.tags, current)
        end)
        if not new_direction then
            new_direction = pick_where(candidates, used, function(candidate)
                return introduces(candidate.tags, current)
            end)
        end
        if new_direction then chosen[#chosen + 1] = new_direction end
    end

    local counter = pick_where(candidates, used, function(candidate)
        return intersects(candidate.counter_tags, scouts)
    end)
    if counter then chosen[#chosen + 1] = counter end

    while #chosen < contract.DRAFT.OFFER_SIZE do
        local fallback = pick_where(candidates, used, function() return true end)
        if not fallback then error("draft pool cannot fill a three-choice offer") end
        chosen[#chosen + 1] = fallback
    end

    return chosen, offer_seed
end

local function tag_metadata(tags)
    local out = {}
    for _, tag in ipairs(tags or {}) do
        local definition = catalog.TAGS[tag]
        out[#out + 1] = {
            id = tag,
            label = definition and definition.label or tag,
            description = definition and definition.description or "",
        }
    end
    return out
end

local function matching_tags(tags, wanted)
    local out = {}
    for _, tag in ipairs(tags or {}) do
        if wanted[tag] then out[#out + 1] = tag end
    end
    return out
end

local function new_tags(tags, current)
    local out = {}
    for _, tag in ipairs(tags or {}) do
        if not current[tag] then out[#out + 1] = tag end
    end
    return out
end

local function sling_details(item)
    local rules = slings.by_id[item.id] or {}
    return {
        archetype = rules.archetype,
        launch_impulse_bonus = rules.momentum_bonus or 0,
        effect_power = rules.effect_power or 0,
        ricochet = rules.ricochet == true,
        shots_per_exchange = rules.shots_per_volley or 1,
    }
end

local function marble_details(item)
    local core = cores.by_id[item.core]
    local shell_details = {}
    for order, shell_id in ipairs(item.shells) do
        local shell = shells.by_id[shell_id]
        shell_details[#shell_details + 1] = {
            order = order,
            id = shell.id,
            mineral = shell.mineral,
            pattern = shell.pattern,
            collision = shell.collision,
            durability = shell.durability,
        }
    end
    return {
        rarity = item.rarity,
        role = item.role,
        core = {
            id = core.id,
            name = core.name,
            angle_bias = core.trajectory,
            release = core.release or "baseline_blowback",
        },
        shells = shell_details,
        shell_count = #shell_details,
    }
end

local function kit_details(item)
    local brick_details = {}
    for _, brick_id in ipairs(item.brick_ids) do
        local brick = bricks.by_id[brick_id]
        brick_details[#brick_details + 1] = {
            id = brick.id,
            name = brick.name,
            family = brick.family or "basic",
            behaviour = brick.behaviour,
            hp = brick.hp,
        }
    end
    return {
        role = item.role,
        suggested_placement = item.suggested_placement,
        bricks = brick_details,
    }
end

local function choice_from_item(item, category, current, scouts)
    local authority = rule_ast.player_authority(item.rule_set)
    local content_ids
    local details
    if category == "sling" then
        content_ids = { item.id }
        details = sling_details(item)
    elseif category == "marble" then
        content_ids = { item.id }
        details = marble_details(item)
    else
        content_ids = util.deep_copy(item.brick_ids)
        details = kit_details(item)
    end

    local matched = matching_tags(item.tags, current)
    local introduced = new_tags(item.tags, current)
    local counters = matching_tags(item.counter_tags, scouts)
    return {
        choice_id = category .. ":" .. item.id,
        content_id = item.id,
        content_ids = content_ids,
        name = item.name,
        role = item.role,
        rarity = item.rarity,
        draft_value = authority.rarity_budget,
        mechanics = util.deep_copy(authority.compact_lines),
        compact_copy = authority.compact_copy,
        inspection_copy = util.deep_copy(authority.inspection_copy),
        rule_set = util.deep_copy(item.rule_set),
        compatibility = util.deep_copy(item.compatibility),
        balance = util.deep_copy(authority.balance),
        tags = util.deep_copy(item.tags),
        tag_metadata = tag_metadata(item.tags),
        synergy = {
            matched = matched,
            introduced = introduced,
            counters = counters,
        },
        suggested_placement = item.suggested_placement,
        art_id = item.art_id,
        details = details,
    }
end

function M.make_offer(state)
    local category, round = M.stage_for(state.draft.picks)
    if category == "complete" then return nil end

    local candidates, offer_seed = curated_choices(state, category)
    local current = M.current_tag_set(state)
    local scouts = util.set(state.opponent.scout_tags)
    local choices = {}
    for _, candidate in ipairs(candidates) do
        choices[#choices + 1] = choice_from_item(candidate, category, current, scouts)
    end

    local offer = {
        schema_version = 1,
        offer_id = string.format("%s:offer:%02d", state.run_id, state.draft.offer_index),
        category = category,
        stage = category,
        round = round,
        offer_seed = offer_seed,
        choices = choices,
        build_tags = M.current_tags(state),
        scout_tags = util.deep_copy(state.opponent.scout_tags),
    }
    local valid, message = contract.validate_offer(offer)
    if not valid then error("generated invalid offer: " .. tostring(message)) end
    return offer
end

local function catalog_item(category, content_id)
    if category == "sling" then return catalog.sling_by_id[content_id] end
    if category == "marble" then return catalog.marble_by_id[content_id] end
    if category == "brick_kit" then return catalog.brick_kit_by_id[content_id] end
    return nil
end

function M.find_choice(offer, choice_id)
    for _, choice in ipairs((offer and offer.choices) or {}) do
        if choice.choice_id == choice_id then return choice end
    end
    return nil
end

function M.instantiate_sling(choice)
    local item = catalog_item("sling", choice.content_id)
    if not item then error("unknown sling draft choice: " .. tostring(choice.content_id)) end
    local out = util.deep_copy(item)
    local rules = slings.by_id[item.id]
    for key, value in pairs(rules or {}) do
        if out[key] == nil then out[key] = util.deep_copy(value) end
    end
    out.content_id = item.id
    out.rule_set = util.deep_copy(item.rule_set)
    out.compact_copy = item.compact_copy
    out.inspection_copy = util.deep_copy(item.inspection_copy)
    out.balance = util.deep_copy(item.balance)
    out.compatibility = util.deep_copy(item.compatibility)
    return out
end

function M.instantiate_marble(choice, index, owner)
    local item = catalog_item("marble", choice.content_id)
    if not item then error("unknown marble draft choice: " .. tostring(choice.content_id)) end
    return {
        uid = string.format("%s-m%02d", owner or "player", index),
        content_id = item.id,
        name = item.name,
        role = item.role,
        rarity = item.rarity,
        core = item.core,
        shells = util.deep_copy(item.shells),
        mechanics = util.deep_copy(item.mechanics),
        compact_copy = item.compact_copy,
        inspection_copy = util.deep_copy(item.inspection_copy),
        rule_set = util.deep_copy(item.rule_set),
        compatibility = util.deep_copy(item.compatibility),
        balance = util.deep_copy(item.balance),
        tags = util.deep_copy(item.tags),
        art_id = item.art_id,
    }
end

function M.instantiate_kit(choice, first_brick_index, owner)
    local item = catalog_item("brick_kit", choice.content_id)
    if not item then error("unknown brick kit draft choice: " .. tostring(choice.content_id)) end
    local instances = {}
    for offset, brick_id in ipairs(item.brick_ids) do
        instances[#instances + 1] = M.instantiate_brick(
            item.id,
            brick_id,
            first_brick_index + offset - 1,
            owner
        )
    end
    return {
        content_id = item.id,
        name = item.name,
        role = item.role,
        tags = util.deep_copy(item.tags),
        mechanics = util.deep_copy(item.mechanics),
        compact_copy = item.compact_copy,
        inspection_copy = util.deep_copy(item.inspection_copy),
        rule_set = util.deep_copy(item.rule_set),
        compatibility = util.deep_copy(item.compatibility),
        balance = util.deep_copy(item.balance),
        suggested_placement = item.suggested_placement,
        draft_value = item.rule_set.rarity_budget,
        art_id = item.art_id,
    }, instances
end

-- Public individual-brick construction for sparse runs.  Bricks retain their
-- approved kit provenance, so legacy brick definitions cannot enter the run
-- merely because old recordings still need them to load.
function M.instantiate_brick(kit_id, brick_id, index, owner)
    local item = catalog_item("brick_kit", kit_id)
    if not item then error("unknown brick kit: " .. tostring(kit_id)) end
    local member = false
    for _, candidate in ipairs(item.brick_ids) do
        if candidate == brick_id then member = true break end
    end
    if not member then
        error(string.format(
            "brick %s is not part of comprehension-pool kit %s",
            tostring(brick_id),
            tostring(kit_id)
        ))
    end
    local definition = bricks.by_id[brick_id]
    if not definition then error("unknown brick: " .. tostring(brick_id)) end
    return {
        uid = string.format("%s-b%02d", owner or "player", index),
        content_id = definition.id,
        kit_id = item.id,
        name = definition.name,
        family = definition.family or "basic",
        behaviour = definition.behaviour,
        hp = definition.hp,
        max_hp = definition.hp,
        tags = util.deep_copy(item.tags),
        art_id = "brick_" .. definition.id,
        mechanics = rule_ast.compact_lines(definition.rule_set, 1),
        compact_copy = definition.compact_copy,
        inspection_copy = util.deep_copy(definition.inspection_copy),
        rule_set = util.deep_copy(definition.rule_set),
        compatibility = util.deep_copy(definition.rule_set.compatibility),
        balance = util.deep_copy(definition.balance),
    }
end

function M.catalog_summary()
    return {
        content_version = catalog.VERSION,
        slings = #catalog.SLINGS,
        marbles = #catalog.MARBLES,
        brick_kits = #catalog.BRICK_KITS,
        brick_archetypes = #bricks.list,
        tags = #util.sorted_keys(catalog.TAGS),
        comprehension_pool = catalog.COMPREHENSION_POOL_SIZE,
        legacy_marbles = #catalog.LEGACY_MARBLES,
    }
end

return M
