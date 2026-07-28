-- Seeded asymmetric CPU construction.  Recipes are selected and fully built
-- before the first player offer, so no later draft choice can influence them.

local RNG = require("battle.rng")
local contract = require("battle.vslice_contract")
local draft = require("battle.draft")
local draft_content = require("battle.content.draft")
local brick_content = require("battle.content.bricks")
local core_content = require("battle.content.cores")
local shell_content = require("battle.content.shells")
local marble_rules = require("battle.marble")
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
            { 1, 1, { "basalt_absorber", "granite_fortifier" } },
            { 1, 2, { "granite_fortifier", "basalt_absorber" } },
            { 1, 3, { "mirror_pane", "prismatic_mirror" } },
            { 1, 4, { "aegis_keystone" } },
            { 1, 5, { "mirror_pane", "prismatic_mirror" } },
            { 1, 6, { "granite_fortifier", "basalt_absorber" } },
            { 1, 7, { "basalt_absorber", "granite_fortifier" } },
            { 2, 2, { "moss_regenerator", "vault_arch" } },
            { 2, 4, { "temporal_anchor", "aegis_keystone" } },
            { 2, 6, { "moss_regenerator", "vault_arch" } },
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
            { 1, 2, { "venom_glass", "rime_block" } },
            { 1, 4, { "lodestone_block", "shatter_crystal" } },
            { 1, 6, { "rime_block", "venom_glass" } },
            { 2, 3, { "shatter_crystal", "splice_node" } },
            { 2, 5, { "powder_keg", "void_prism" } },
            { 3, 4, { "void_prism", "lodestone_block" } },
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
            { 1, 2, { "shatter_crystal", "mirror_pane" } },
            { 1, 4, { "powder_keg", "shatter_crystal" } },
            { 1, 6, { "shatter_crystal", "mirror_pane" } },
            { 2, 3, { "splice_node", "prismatic_mirror" } },
            { 2, 5, { "prismatic_mirror", "splice_node" } },
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
    for _, brick in ipairs(spec.bricks) do
        if brick_ids[brick.uid] then return fail("opponent brick uids must be unique") end
        if not brick_content.has(brick.content_id) then return fail("opponent contains an unknown brick") end
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
        local definition = draft_content.marble_by_id[marble.content_id]
        if not definition then return fail("opponent contains an unknown marble") end
        local cap = marble_rules.SHELL_CAP[definition.rarity]
        if #(definition.shells or {}) < 1 or #(definition.shells or {}) > cap then
            return fail("opponent marble violates its shell cap")
        end
        if not core_content.has(definition.core) then
            return fail("opponent marble has an unknown core")
        end
        local core = core_content.runtime(definition.core, definition.rule_set)
        if marble_rules.rarity_rank(core.min_rarity) > marble_rules.rarity_rank(definition.rarity) then
            return fail("opponent marble core exceeds its rarity")
        end
        for _, shell_id in ipairs(definition.shells) do
            if not shell_content.has(shell_id) then
                return fail("opponent marble has an unknown shell")
            end
        end
        marble_ids[marble.uid] = true
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
