-- Player-facing expedition helpers. Every formation edit uses the same
-- canonical commands as manual placement; storage stays outside the engine.
local codec = require("save_codec")
local run = require("battle.run")
local loop = require("run_loop")

local M = {}
M.storage_digest = codec.checksum

function M.encode(app)
    local save, err = run.save(app.model.run)
    if not save then return nil, err and err.message end
    local ok, bytes = pcall(codec.encode, save)
    if not ok then return nil, "This expedition could not be saved." end
    return bytes
end

function M.restore(bytes, settings)
    local ok, result = pcall(function()
        local save = codec.decode(bytes)
        local state, err = run.load(save)
        assert(state, err and err.message or "Invalid expedition")
        assert(type(state.run_seed) == "number" and state.fight
            and type(state.fight.index) == "number"
            and type(state.journal) == "table", "Incomplete expedition")
        assert(state.phase == "setup" or state.phase == "draft" or state.phase == "result",
            "Unknown expedition phase")
        assert(state.fight.index % 1 == 0 and state.fight.index >= 1
            and state.fight.index <= 3, "Unknown expedition fight")
        settings = settings or {}
        local app = loop.new({ short_run = true, run_seed = state.run_seed,
            muted = settings.muted, reduced_motion = settings.reduced_motion })
        app.model.run = state
        app.current_frame = state.battle and state.battle.recording and state.battle.recording.final
        app.previous_frame = app.current_frame
        -- Projection validates the state needed by the first rendered screen.
        loop.project(app)
        return app
    end)
    if not ok then return nil, "The saved expedition is unavailable. You can start a new one." end
    return result
end

function M.arrange(app)
    if app.model.run.phase ~= "setup" then return nil, "Arrange bricks before battle." end
    local placed = {}
    local formation = app.model.run.setup.formation
    for row = 1, 3 do
        for col = 1, 7 do
            local uid = formation[row] and formation[row][col]
            if uid and uid ~= "." then placed[uid] = true end
        end
    end
    local cells = { {1,3}, {1,4}, {1,5}, {2,3}, {2,4}, {2,5} }
    for row = 1, 3 do for col = 1, 7 do cells[#cells + 1] = {row,col} end end
    local ids = {}
    for _, brick in ipairs(app.model.run.player.bricks) do ids[#ids + 1] = brick.uid end
    for _, uid in ipairs(ids) do
        if not placed[uid] then
            local selected, err = loop.activate(app, "brick:" .. uid, "auto_arrange")
            if not selected then return nil, err and err.message end
            for _, cell in ipairs(cells) do
                local row, col = cell[1], cell[2]
                if app.model.run.setup.formation[row][col] == "." then
                    local accepted = loop.activate(app, "cell:" .. row .. ":" .. col, "auto_arrange")
                    if accepted then break end
                end
            end
        end
    end
    return app.model.run.setup.valid
end

return M
