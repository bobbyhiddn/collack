-- battle/marble.lua — marble construction and the rules that constrain it.
--
-- A marble is a core wrapped in an ORDERED array of shells, outermost first.
-- shells[1] is the layer that takes the next hit. When it breaks it is removed
-- and shells[2] becomes shells[1]. When the array empties the core is exposed,
-- which is precisely the moment the marble stops existing as a combat unit.
--
-- Two invariants are enforced here rather than trusted:
--   1. shell count is at least 1 and at most the rarity's cap;
--   2. a live marble always has at least one shell, so the core is never
--      exposed during play (see marble.assert_core_covered).

local cores = require("battle.content.cores")
local shells = require("battle.content.shells")
local slings = require("battle.content.slings")
local rule_ast = require("battle.rule_ast")
local draft = require("battle.draft")

local M = {}

-- Rarity shell caps, straight from the spec.
M.SHELL_CAP = {
    common = 1,
    uncommon = 2,
    rare = 3,
    epic = 4,
    legendary = 5,
}

-- Rarity ordering, used to check a core is legal for the marble's rarity.
M.RARITY_ORDER = { "common", "uncommon", "rare", "epic", "legendary" }

local rarity_rank = {}
for index, name in ipairs(M.RARITY_ORDER) do
    rarity_rank[name] = index
end

function M.rarity_rank(rarity)
    return rarity_rank[rarity]
end

local next_uid = 0
local function alloc_uid()
    next_uid = next_uid + 1
    return next_uid
end

--- Reset the uid counter. Called at the start of every battle so that uids are
--- a function of the battle alone; otherwise a process that runs two battles
--- would produce different uids the second time and the log would not be
--- reproducible across runs.
function M.reset_uids()
    next_uid = 0
end

--- Build a live marble from a definition table:
---   { name, rarity, core = "<core id>", shells = { "<shell id>", ... } }
--- shells are listed OUTERMOST FIRST.
--- sling is applied at build time and baked into the resulting stats.
function M.build(def, sling, owner_id, require_canonical)
    if def.content_id ~= nil then
        def = draft.canonical_marble(def)
    elseif require_canonical then
        error("product battle marble is missing canonical content identity")
    end
    local cap = M.SHELL_CAP[def.rarity]
    if not cap then
        error("unknown rarity: " .. tostring(def.rarity))
    end

    local shell_ids = def.shells or {}
    if #shell_ids < 1 then
        error(string.format("marble %q has no shells; the core would be exposed", tostring(def.name)))
    end
    if #shell_ids > cap then
        error(string.format(
            "marble %q is %s and may carry at most %d shell(s), got %d",
            tostring(def.name), def.rarity, cap, #shell_ids))
    end

    if not cores.has(def.core) then
        error("unknown core: " .. tostring(def.core))
    end
    local entity_rule_set = def.rule_set
    if entity_rule_set then rule_ast.assert_valid(entity_rule_set) end
    local core_def = cores.runtime(
        def.core,
        entity_rule_set
    )
    if rarity_rank[core_def.min_rarity] > rarity_rank[def.rarity] then
        error(string.format(
            "core %q needs rarity %s or better, marble %q is %s",
            core_def.id, core_def.min_rarity, tostring(def.name), def.rarity))
    end
    -- The spec's rule, enforced: only uncommon and above carry a release
    -- effect. Commons get baseline blowback, which every core gets anyway.
    if def.rarity == "common" and core_def.release ~= nil then
        error(string.format("common marble %q may not carry a release effect", tostring(def.name)))
    end

    if type(sling) ~= "table" or not sling.rule_set then
        error("live marble construction needs a canonical sling RuleSet")
    end
    sling = slings.runtime(sling.id, sling.rule_set, sling)
    local built_shells = {}
    for index, shell_id in ipairs(shell_ids) do
        if not shells.has(shell_id) then
            error("unknown shell: " .. tostring(shell_id))
        end
        local shell_def = shells.runtime(
            shell_id,
            entity_rule_set
        )
        built_shells[index] = {
            id = shell_def.id,
            mineral = shell_def.mineral,
            pattern = shell_def.pattern,
            collision = shell_def.collision,
            durability = shell_def.durability + (sling.durability_bonus or 0),
            max_durability = shell_def.durability + (sling.durability_bonus or 0),
            rule_set = rule_ast.copy(shell_def.rule_set),
        }
    end

    return {
        uid = def.uid ~= nil and def.uid or alloc_uid(),
        content_id = def.content_id,
        name = def.name,
        rarity = def.rarity,
        owner = owner_id,
        core = {
            id = core_def.id,
            name = core_def.name,
            trajectory = core_def.trajectory + (sling.aim or 0),
            release = core_def.release,
            rule_set = rule_ast.copy(core_def.rule_set),
        },
        shells = built_shells,
        -- Momentum contributes to canonical launch speed and physical mass.
        -- More shells make a heavier, more persistent shot.
        momentum = #built_shells + (sling.momentum_bonus or 0),
        damage_bonus = sling.damage_bonus or 0,
        scatter = sling.scatter or 0,
        ricochet = sling.ricochet == true,
        precision = sling.precision == true,
        effect_power = sling.effect_power or 0,
        sling_id = sling.id,
        sling_rule_set = rule_ast.copy(sling.rule_set),
        rule_set = entity_rule_set and rule_ast.copy(entity_rule_set) or nil,
        compact_copy = def.compact_copy,
        inspection_copy = def.inspection_copy,
        balance = def.balance,
        lane = nil,
        statuses = {},
        state = "ready", -- ready | flying | destroyed
    }
end

--- Outermost shell, or nil if the core is exposed (which must never happen for
--- a marble still in a rack).
function M.outer_shell(marble)
    return marble.shells[1]
end

function M.shell_count(marble)
    return #marble.shells
end

--- Invariant check used by the engine and by the tests.
function M.assert_core_covered(marble)
    if #marble.shells < 1 then
        error(string.format("marble %s (uid %s) has an exposed core while still in play",
            tostring(marble.name), marble.uid))
    end
end

return M
