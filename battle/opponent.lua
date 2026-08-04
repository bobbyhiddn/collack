-- Seeded asymmetric CPU construction.  Recipes are selected and fully built
-- before the first player offer, so no later draft choice can influence them.

local RNG = require("battle.rng")
local contract = require("battle.vslice_contract")
local draft = require("battle.draft")
local draft_content = require("battle.content.draft")
local brick_content = require("battle.content.bricks")
local rule_ast = require("battle.rule_ast")
local util = require("battle.run_util")

local M = {}

local RECIPES = {
    {
        id = "bastion",
        name = "Bastion",
        description = "A broad durable wall with a short, stubborn bag.",
        scout_tags = { "guard", "sustain" },
        sling_ids = { "momentum" },
        bricks = {
            { 1, 1, { "basalt_absorber" } },
            { 1, 2, { "training_dummy" } },
            { 1, 3, { "mirror_pane" } },
            { 1, 4, { "aegis_keystone" } },
            { 1, 5, { "granite_fortifier" } },
            { 1, 6, { "basalt_absorber" } },
            { 1, 7, { "training_dummy" } },
            { 2, 2, { "moss_regenerator" } },
            { 2, 6, { "vault_arch" } },
            { 3, 4, { "temporal_anchor" } },
        },
        marbles = {
            { "banded_guard_uncommon", "quartz_common" },
            { "warden_rare", "banded_guard_uncommon" },
            { "quartz_common", "warden_rare" },
        },
        bag_order = { 2, 1, 3 },
    },
    {
        id = "fuse_garden",
        name = "Fuse Garden",
        description = "A sparse field garden built around releases and statuses.",
        scout_tags = { "field", "release" },
        sling_ids = { "effect_amplifier" },
        bricks = {
            { 1, 2, { "venom_glass" } },
            { 1, 4, { "lodestone_block" } },
            { 1, 6, { "rime_block" } },
            { 2, 3, { "shatter_crystal" } },
            { 2, 5, { "powder_keg" } },
            { 3, 4, { "void_prism" } },
        },
        marbles = {
            { "geode_uncommon", "silver_seed_uncommon" },
            { "magnet_needle_epic", "lodestone_epic" },
            { "chalk_common", "flint_hook_common" },
            { "silver_seed_uncommon", "geode_uncommon" },
        },
        bag_order = { 3, 1, 4, 2 },
    },
    {
        id = "glass_cannon",
        name = "Glass Cannon",
        description = "Five dangerous bricks buy time for three penetrating shots.",
        scout_tags = { "burst", "force" },
        sling_ids = { "ricochet", "momentum" },
        bricks = {
            { 1, 3, { "shatter_crystal" } },
            { 2, 2, { "powder_keg" } },
            { 1, 6, { "mirror_pane" } },
            { 2, 3, { "splice_node" } },
            { 2, 4, { "prismatic_mirror" } },
        },
        marbles = {
            { "shard_ram_rare", "geode_uncommon" },
            { "cinder_legendary", "lodestone_epic" },
            { "flint_hook_common", "shard_ram_rare" },
        },
        bag_order = { 1, 3, 2 },
    },
}

local RECIPE_BY_ID = {}
for _, recipe in ipairs(RECIPES) do RECIPE_BY_ID[recipe.id] = recipe end

local function empty_grid()
    local grid = {}
    for row = 1, contract.FORMATION.ROWS do
        grid[row] = {}
        for col = 1, contract.FORMATION.COLS do grid[row][col] = "." end
    end
    return grid
end

local function pick(rng, list)
    return list[rng:int(1, #list)]
end

local function tag_details(tags)
    local out = {}
    for _, id in ipairs(tags) do
        local tag = draft_content.TAGS[id]
        out[#out + 1] = {
            id = id,
            label = tag and tag.label or id,
            description = tag and tag.description or "",
        }
    end
    return out
end

local function build_recipe(recipe, seed)
    local rng = RNG.new(seed)
    local sling_id = pick(rng, recipe.sling_ids)
    local sling = draft.instantiate_sling({ content_id = sling_id })
    local formation = empty_grid()
    local brick_roster = {}
    for index, slot in ipairs(recipe.bricks) do
        local brick_id = pick(rng, slot[3])
        local profile = brick_content.runtime(brick_id)
        local uid = string.format("opponent-b%02d", index)
        brick_roster[#brick_roster + 1] = {
            uid = uid,
            content_id = profile.id,
            name = profile.name,
            family = profile.family or "basic",
            behaviour = profile.behaviour,
            hp = profile.hp,
            max_hp = profile.hp,
            rule_set = util.deep_copy(profile.rule_set),
            compact_copy = profile.compact_copy,
            inspection_copy = util.deep_copy(profile.inspection_copy),
            balance = util.deep_copy(profile.balance),
            tags = util.deep_copy(recipe.scout_tags),
            art_id = "brick_" .. profile.id,
        }
        formation[slot[1]][slot[2]] = uid
    end

    local marble_roster = {}
    for index, alternatives in ipairs(recipe.marbles) do
        local marble_id = pick(rng, alternatives)
        marble_roster[#marble_roster + 1] =
            draft.instantiate_marble({ content_id = marble_id }, index, "opponent")
    end

    local bag_order = {}
    for _, roster_index in ipairs(recipe.bag_order) do
        bag_order[#bag_order + 1] = marble_roster[roster_index].uid
    end

    return {
        schema_version = 1,
        recipe_id = recipe.id,
        name = recipe.name,
        description = recipe.description,
        scout_tags = util.deep_copy(recipe.scout_tags),
        scout_metadata = tag_details(recipe.scout_tags),
        seed = seed,
        sling = sling,
        sling_id = sling.id,
        marbles = marble_roster,
        bricks = brick_roster,
        formation = formation,
        bag_order = bag_order,
    }
end

local function fail(message)
    return false, message
end

function M.validate(spec)
    if type(spec) ~= "table" then return fail("opponent must be a table") end
    if not RECIPE_BY_ID[spec.recipe_id] then return fail("opponent recipe is unknown") end
    if type(spec.name) ~= "string" or spec.name == "" then return fail("opponent name is required") end
    if #((spec.scout_tags) or {}) ~= 2 then return fail("opponent needs exactly two scout tags") end
    if not draft_content.sling_by_id[spec.sling_id] then return fail("opponent sling is unsupported") end
    if #(spec.bricks or {}) == 0 then return fail("opponent needs bricks") end
    if #(spec.marbles or {}) == 0 then return fail("opponent needs marbles") end

    local brick_ids = {}
    local collection = {}
    for _, brick in ipairs(spec.bricks) do
        if brick_ids[brick.uid] then return fail("opponent brick uids must be unique") end
        if not brick_content.has(brick.content_id) then return fail("opponent contains an unknown brick") end
        local canonical = brick_content.canonical_rule_set(brick.content_id)
        if not canonical.availability.cpu_recipe then
            return fail("opponent contains a brick unavailable to CPU recipes")
        end
        if not rule_ast.same(brick.rule_set, canonical) then
            return fail("opponent brick diverges from canonical authority")
        end
        collection[#collection + 1] = canonical
        brick_ids[brick.uid] = true
    end

    local placed = {}
    if #(spec.formation or {}) ~= contract.FORMATION.ROWS then
        return fail("opponent formation must have three rows")
    end
    for row = 1, contract.FORMATION.ROWS do
        local cells = spec.formation[row]
        if type(cells) ~= "table" then return fail("opponent formation row is missing") end
        for col = 1, contract.FORMATION.COLS do
            local uid = cells[col]
            if uid and uid ~= "." then
                if not brick_ids[uid] then return fail("opponent formation contains an unknown brick") end
                if placed[uid] then return fail("opponent brick is placed twice") end
                placed[uid] = true
                for _, brick in ipairs(spec.bricks) do
                    if brick.uid == uid and brick.rule_set.formation
                        and brick.rule_set.formation.rear_row
                        and row ~= contract.FORMATION.ROWS then
                        return fail("rear-row brick violates its canonical formation constraint")
                    end
                end
            end
        end
        if cells[contract.FORMATION.COLS + 1] ~= nil then
            return fail("opponent formation exceeds seven columns")
        end
    end
    for uid in pairs(brick_ids) do
        if not placed[uid] then return fail("opponent formation omits a brick") end
    end

    local marble_ids = {}
    for _, marble in ipairs(spec.marbles) do
        if marble_ids[marble.uid] then return fail("opponent marble uids must be unique") end
        local authority_valid, canonical_or_error = pcall(
            draft.canonical_marble,
            marble
        )
        if not authority_valid then
            return fail(
                "opponent marble diverges from canonical authority: "
                .. tostring(canonical_or_error)
            )
        end
        marble_ids[marble.uid] = true
        collection[#collection + 1] = canonical_or_error.rule_set
    end

    if #(spec.bag_order or {}) ~= #spec.marbles then
        return fail("opponent bag must match its roster")
    end
    local bag_ids = {}
    for _, uid in ipairs(spec.bag_order) do
        if not marble_ids[uid] then return fail("opponent bag contains an unknown marble") end
        if bag_ids[uid] then return fail("opponent bag contains a duplicate marble") end
        bag_ids[uid] = true
    end
    for uid in pairs(marble_ids) do
        if not bag_ids[uid] then return fail("opponent bag omits a marble") end
    end
    local compatible, compatibility_errors = rule_ast.validate_collection(collection)
    if not compatible then
        return fail("opponent violates canonical copy/compatibility rules: "
            .. tostring(compatibility_errors[1]))
    end
    return true
end

function M.build(opponent_seed, recipe_id)
    local seed = util.normalize_seed(opponent_seed, contract.SEED_MODULUS)
    local recipe
    if recipe_id then
        recipe = RECIPE_BY_ID[recipe_id]
        if not recipe then error("unknown opponent recipe: " .. tostring(recipe_id)) end
    else
        local rng = RNG.new(seed)
        recipe = RECIPES[rng:int(1, #RECIPES)]
    end
    local spec = build_recipe(recipe, seed)
    local valid, message = M.validate(spec)
    if not valid then error("generated invalid opponent: " .. tostring(message)) end
    return spec
end

local function multiset(items, field)
    local out = {}
    for _, item in ipairs(items or {}) do
        local id = item[field]
        out[id] = (out[id] or 0) + 1
    end
    return out
end

function M.is_mirror(player, cpu)
    if not player or not cpu then return false end
    if #(player.marbles or {}) ~= #(cpu.marbles or {}) then return false end
    if #(player.bricks or {}) ~= #(cpu.bricks or {}) then return false end
    local player_sling = player.sling_id or (player.sling and player.sling.id)
    if player_sling ~= cpu.sling_id then return false end
    return util.deep_equal(
        multiset(player.marbles, "content_id"),
        multiset(cpu.marbles, "content_id")
    ) and util.deep_equal(
        multiset(player.bricks, "content_id"),
        multiset(cpu.bricks, "content_id")
    )
end

function M.recipes()
    local out = {}
    for _, recipe in ipairs(RECIPES) do
        out[#out + 1] = {
            id = recipe.id,
            name = recipe.name,
            description = recipe.description,
            scout_tags = util.deep_copy(recipe.scout_tags),
            brick_count = #recipe.bricks,
            marble_count = #recipe.marbles,
        }
    end
    return out
end

return M
