-- Stable, implementation-light contracts for the product-shaped vertical
-- slice. Draft/setup work and the continuous battle import these values rather
-- than silently choosing different counts, phases, timing, or seed coupling.

local M = {}

M.VERSION = 1

M.PHASE = {
    DRAFT = "draft",
    SETUP = "setup",
    BATTLE = "battle",
    RESULT = "result",
}

M.DRAFT = {
    OFFER_SIZE = 3,
    SLING_PICKS = 1,
    MARBLE_PICKS = 4,
    BRICK_KIT_PICKS = 4,
    BRICKS_PER_KIT = 2,
}

M.FORMATION = {
    ROWS = 3,
    COLS = 7,
}

M.PHYSICS = {
    FIXED_HZ = 120,
    FIXED_DT = 1 / 120,
    MAX_STEPS_PER_UPDATE = 8,
    RECORD_EVERY_TICKS = 4,
    KEYFRAME_EVERY_TICKS = 120,
    MAX_EXCHANGES = 40,
}

M.SEED_MODULUS = 2147483647
M.SEED_DOMAIN = {
    draft = 104729,
    opponent = 130363,
    battle = 169087,
}

local transitions = {
    draft = { setup = true },
    setup = { battle = true },
    battle = { result = true },
    result = {},
}

local commands = {
    draft = { choose_offer = true },
    setup = { place_brick = true, move_bag = true, lock_setup = true },
    battle = {},
    result = { new_run = true },
}

local function sequence_length(value)
    if type(value) ~= "table" then return nil end
    local count = 0
    for index in ipairs(value) do count = index end
    return count
end

local function nonempty(value)
    return type(value) == "string" and value ~= ""
end

local function fail(message)
    return false, message
end

function M.can_transition(from, to)
    return transitions[from] ~= nil and transitions[from][to] == true
end

function M.command_allowed(phase, kind)
    return commands[phase] ~= nil and commands[phase][kind] == true
end

function M.derive_seed(run_seed, domain)
    local offset = M.SEED_DOMAIN[domain]
    if not offset then error("unknown seed domain: " .. tostring(domain)) end
    local seed = math.floor(tonumber(run_seed) or 1) % M.SEED_MODULUS
    if seed < 0 then seed = seed + M.SEED_MODULUS end
    if seed == 0 then seed = 1 end
    local derived = (seed + offset) % M.SEED_MODULUS
    if derived == 0 then derived = 1 end
    return derived
end

function M.validate_offer(offer)
    if type(offer) ~= "table" then return fail("offer must be a table") end
    if not nonempty(offer.offer_id) then return fail("offer_id is required") end
    if offer.category ~= "sling" and offer.category ~= "marble"
        and offer.category ~= "brick_kit" then
        return fail("unknown offer category")
    end
    if sequence_length(offer.choices) ~= M.DRAFT.OFFER_SIZE then
        return fail("offer must contain exactly three choices")
    end

    local seen = {}
    for _, choice in ipairs(offer.choices) do
        if not nonempty(choice.choice_id) then return fail("choice_id is required") end
        if seen[choice.choice_id] then return fail("choice IDs must be unique") end
        seen[choice.choice_id] = true
        if sequence_length(choice.mechanics) == 0 then
            return fail("every choice needs mechanics copy")
        end
        if sequence_length(choice.tags) == 0 then
            return fail("every choice needs synergy tags")
        end
        if offer.category == "brick_kit"
            and sequence_length(choice.content_ids) ~= M.DRAFT.BRICKS_PER_KIT then
            return fail("brick kit choices must contain exactly two bricks")
        end
    end
    return true
end

-- Validate the locked PLAYER setup. CPU recipes have their own intentional
-- counts, but must apply equivalent permutation and no-overlap checks.
function M.validate_setup(setup)
    if type(setup) ~= "table" then return fail("setup must be a table") end
    if not nonempty(setup.sling_id) then return fail("sling_id is required") end
    if sequence_length(setup.marbles) ~= M.DRAFT.MARBLE_PICKS then
        return fail("player setup needs exactly four marbles")
    end
    local expected_bricks = M.DRAFT.BRICK_KIT_PICKS * M.DRAFT.BRICKS_PER_KIT
    if sequence_length(setup.bricks) ~= expected_bricks then
        return fail("player setup needs exactly eight bricks")
    end
    if sequence_length(setup.bag_order) ~= M.DRAFT.MARBLE_PICKS then
        return fail("bag must order exactly four marbles")
    end
    if sequence_length(setup.formation) ~= M.FORMATION.ROWS then
        return fail("formation must have exactly three rows")
    end

    local marble_ids = {}
    for _, marble in ipairs(setup.marbles) do
        if type(marble) ~= "table" or marble.uid == nil then
            return fail("every marble needs a uid")
        end
        if marble_ids[marble.uid] then return fail("marble uids must be unique") end
        marble_ids[marble.uid] = true
    end

    local bag_ids = {}
    for _, uid in ipairs(setup.bag_order) do
        if not marble_ids[uid] then return fail("bag contains an unknown marble") end
        if bag_ids[uid] then return fail("bag contains a duplicate marble") end
        bag_ids[uid] = true
    end
    for uid in pairs(marble_ids) do
        if not bag_ids[uid] then return fail("bag omits a drafted marble") end
    end

    local brick_ids = {}
    for _, brick in ipairs(setup.bricks) do
        if type(brick) ~= "table" or brick.uid == nil then
            return fail("every brick needs a uid")
        end
        if brick_ids[brick.uid] then return fail("brick uids must be unique") end
        brick_ids[brick.uid] = true
    end

    local placed = {}
    for row = 1, M.FORMATION.ROWS do
        local cells = setup.formation[row]
        if type(cells) ~= "table" then return fail("formation row is missing") end
        for col = 1, M.FORMATION.COLS do
            local uid = cells[col]
            if uid ~= "." and uid ~= false and uid ~= nil then
                if not brick_ids[uid] then return fail("formation contains an unknown brick") end
                if placed[uid] then return fail("a brick is placed more than once") end
                placed[uid] = true
            end
        end
        if cells[M.FORMATION.COLS + 1] ~= nil then
            return fail("formation row exceeds seven columns")
        end
    end
    for uid in pairs(brick_ids) do
        if not placed[uid] then return fail("formation omits a drafted brick") end
    end

    return true
end

return M
