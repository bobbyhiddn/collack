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
    local used, chosen, journal = {}, {}, {}

    if category == "sling" then
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
        return chosen, offer_seed, journal
    end

    local predicates = {}
    if next(current) ~= nil then
        predicates[#predicates + 1] = function(candidate)
            return intersects(candidate.tags, current)
        end
        predicates[#predicates + 1] = function(candidate)
            return not intersects(candidate.tags, current)
                or introduces(candidate.tags, current)
        end
    end
    predicates[#predicates + 1] = function(candidate)
        return intersects(candidate.counter_tags, scouts)
    end
    local rng = RNG.new(offer_seed)
    while #chosen < contract.DRAFT.OFFER_SIZE do
        local predicate = predicates[#chosen + 1] or function() return true end
        local eligible = {}
        for _, candidate in ipairs(candidates) do
            if not used[candidate.id] and predicate(candidate) then
                eligible[#eligible + 1] = candidate
            end
        end
        if #eligible == 0 then
            for _, candidate in ipairs(candidates) do
                if not used[candidate.id] then eligible[#eligible + 1] = candidate end
            end
        end
        if #eligible == 0 then error("draft pool cannot fill a three-choice offer") end
        local selected, sample = rule_ast.sample_rarity(
            eligible,
            "full_loadout_initial",
            rng:int(1, 100),
            rng:int(1, 2147483646)
        )
        used[selected.id] = true
        chosen[#chosen + 1] = selected
        sample.slot = #chosen
        journal[#journal + 1] = sample
    end
    return chosen, offer_seed, journal
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
    local rules = slings.runtime(item.id, item.rule_set)
    return {
        archetype = rules.archetype,
        launch_impulse_bonus = rules.momentum_bonus or 0,
        effect_power = rules.effect_power or 0,
        ricochet = rules.ricochet == true,
        shots_per_exchange = rules.shots_per_volley or 1,
    }
end

local function marble_details(item)
    local core = cores.runtime(item.core, item.rule_set)
    local shell_details = {}
    for order, shell_id in ipairs(item.shells) do
        local shell = shells.runtime(shell_id, item.rule_set)
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
        local brick = bricks.runtime(brick_id)
        brick_details[#brick_details + 1] = {
            id = brick.id,
            name = brick.name,
            family = brick.family or "basic",
            behaviour = brick.behaviour,
            hp = brick.hp,
            rarity = brick.rarity,
            telegraph = util.deep_copy(brick.telegraph),
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
        balance = util.deep_copy(category == "brick_kit" and item.balance or authority.balance),
        telegraph = util.deep_copy(category == "brick_kit"
            and item.telegraph or authority.telegraph),
        availability = util.deep_copy(item.rule_set.availability),
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

    local candidates, offer_seed, sampling_journal = curated_choices(state, category)
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
        economy_rule_set_id = rule_ast.ECONOMY.id,
        sampling_journal = util.deep_copy(sampling_journal),
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
    local rules = slings.runtime(item.id, item.rule_set)
    for key, value in pairs(rules) do out[key] = util.deep_copy(value) end
    out.content_id = item.id
    out.rule_set = util.deep_copy(item.rule_set)
    local authority = rule_ast.player_authority(out.rule_set)
    out.compact_copy = authority.compact_copy
    out.inspection_copy = util.deep_copy(authority.inspection_copy)
    out.balance = util.deep_copy(authority.balance)
    out.compatibility = util.deep_copy(item.compatibility)
    return out
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

local RARITY_RANK = {}
for rank, rarity in ipairs(rule_ast.ECONOMY.rarity_order) do
    RARITY_RANK[rarity] = rank
end

-- Component identity and exact shell order already live in the composed
-- RuleSet: the core trajectory node and each shell durability node appear in
-- source order. Derive selectors from those canonical nodes, then require the
-- catalog's compatibility projections to agree. This prevents the catalog
-- table itself from becoming a second mutable mechanics source.
local function marble_selectors(item)
    local expected_rule_set_id = "card.marble." .. tostring(item.id)
    if item.rule_set.id ~= expected_rule_set_id then
        error(string.format(
            "marble %s RuleSet identity diverges: %s",
            tostring(item.id),
            tostring(item.rule_set.id)
        ))
    end
    if item.name ~= item.rule_set.name then
        error("catalog name projection diverges from canonical RuleSet identity")
    end
    local core_id
    local shell_ids = {}
    local seen_shells = {}
    for _, rule in ipairs(item.rule_set.rules) do
        local candidate_core = rule.id:match("^core%.([%w_]+)%.trajectory$")
        if candidate_core then
            if core_id and core_id ~= candidate_core then
                error("canonical marble contains multiple core identities")
            end
            core_id = candidate_core
        end
        local shell_id = rule.id:match("^shell%.([%w_]+)%.durability$")
        if shell_id then
            if seen_shells[shell_id] then
                error("canonical marble repeats shell identity: " .. tostring(shell_id))
            end
            seen_shells[shell_id] = true
            shell_ids[#shell_ids + 1] = shell_id
        end
    end
    if not core_id then error("canonical marble RuleSet has no core identity") end
    if #shell_ids < 1 then error("canonical marble RuleSet has no shell identity") end
    local rarity = item.rule_set.rarity
    local tier = rule_ast.ECONOMY.tiers[rarity]
    if not tier then error("canonical marble RuleSet has invalid rarity") end
    if #shell_ids > tier.shell_cap then
        error("canonical marble RuleSet exceeds its rarity shell cap")
    end
    if item.core ~= core_id then
        error("catalog core projection diverges from canonical RuleSet identity")
    end
    if not util.deep_equal(item.shells, shell_ids) then
        error("catalog ordered shell projection diverges from canonical RuleSet identity")
    end
    if item.rarity ~= rarity then
        error("catalog rarity projection diverges from canonical RuleSet rarity")
    end
    return {
        core = core_id,
        shells = shell_ids,
        rarity = rarity,
    }
end

-- Materialize every setup/execution field from the same catalog item and
-- RuleSet used by inspection, copy, validation, and balance. Recomputing the
-- projections here also means an intentional valid RuleSet edit is observed
-- everywhere, while a stale draft copy cannot remain a mechanical authority.
local function materialize_marble(item, uid)
    rule_ast.assert_valid(item.rule_set)
    local selectors = marble_selectors(item)
    local core = cores.runtime(selectors.core, item.rule_set)
    if RARITY_RANK[core.min_rarity] > RARITY_RANK[selectors.rarity] then
        error(string.format(
            "canonical core %s needs rarity %s or better",
            tostring(core.id),
            tostring(core.min_rarity)
        ))
    end
    if selectors.rarity == "common" and core.release ~= nil then
        error("canonical common marble cannot carry a release effect")
    end
    for _, shell_id in ipairs(selectors.shells) do
        shells.runtime(shell_id, item.rule_set)
    end
    local authority = rule_ast.player_authority(item.rule_set)
    return {
        uid = uid,
        content_id = item.id,
        name = item.rule_set.name,
        role = item.rule_set.role,
        rarity = selectors.rarity,
        core = selectors.core,
        shells = util.deep_copy(selectors.shells),
        mechanics = util.deep_copy(authority.compact_lines),
        compact_copy = authority.compact_copy,
        inspection_copy = util.deep_copy(authority.inspection_copy),
        rule_set = util.deep_copy(item.rule_set),
        compatibility = util.deep_copy(item.rule_set.compatibility),
        balance = util.deep_copy(authority.balance),
        telegraph = util.deep_copy(authority.telegraph),
        availability = util.deep_copy(item.rule_set.availability),
        tags = util.deep_copy(item.rule_set.synergy_tags),
        art_id = item.art_id,
    }
end

function M.instantiate_marble(choice, index, owner)
    local item = catalog_item("marble", choice.content_id)
    if not item then error("unknown marble draft choice: " .. tostring(choice.content_id)) end
    return materialize_marble(
        item,
        string.format("%s-m%02d", owner or "player", index)
    )
end

-- Verify a mutable setup or handoff value, then return a fresh canonical value.
-- Exact table shape is intentional: aliases and unknown adjacent selectors must
-- not acquire meaning merely because a later consumer starts reading them.
function M.canonical_marble(instance)
    if type(instance) ~= "table" or not plain_value(instance) then
        error("live marble must be a plain canonical value")
    end
    if instance.uid == nil then error("live marble is missing uid") end
    local item = catalog_item("marble", instance.content_id)
    if not item then
        error("unknown marble content identity: " .. tostring(instance.content_id))
    end
    local canonical = materialize_marble(item, instance.uid)
    for field, value in pairs(canonical) do
        if not util.deep_equal(instance[field], value) then
            error(string.format(
                "marble %s %s diverges from canonical content/RuleSet authority",
                tostring(instance.content_id),
                field
            ))
        end
    end
    for field in pairs(instance) do
        if canonical[field] == nil then
            error(string.format(
                "marble %s contains unknown selector or field %s",
                tostring(instance.content_id),
                tostring(field)
            ))
        end
    end
    return canonical
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
        rarity = item.rarity,
        tags = util.deep_copy(item.tags),
        mechanics = util.deep_copy(item.mechanics),
        compact_copy = item.compact_copy,
        inspection_copy = util.deep_copy(item.inspection_copy),
        rule_set = util.deep_copy(item.rule_set),
        compatibility = util.deep_copy(item.compatibility),
        balance = util.deep_copy(item.balance),
        telegraph = util.deep_copy(item.telegraph),
        availability = util.deep_copy(item.availability),
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
    if not bricks.has(brick_id) then error("unknown brick: " .. tostring(brick_id)) end
    local profile = bricks.runtime(brick_id)
    local authority = rule_ast.player_authority(profile.rule_set)
    return {
        uid = string.format("%s-b%02d", owner or "player", index),
        content_id = profile.id,
        kit_id = item.id,
        name = profile.name,
        family = profile.family or "basic",
        behaviour = profile.behaviour,
        hp = profile.hp,
        max_hp = profile.hp,
        rarity = profile.rarity,
        restitution = profile.restitution,
        tags = util.deep_copy(profile.rule_set.synergy_tags),
        art_id = "brick_" .. profile.id,
        mechanics = util.deep_copy(authority.compact_lines),
        compact_copy = authority.compact_copy,
        inspection_copy = util.deep_copy(authority.inspection_copy),
        rule_set = util.deep_copy(profile.rule_set),
        compatibility = util.deep_copy(profile.rule_set.compatibility),
        balance = util.deep_copy(profile.balance),
        telegraph = util.deep_copy(authority.telegraph),
        availability = util.deep_copy(profile.availability),
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
