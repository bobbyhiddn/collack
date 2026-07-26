-- LÖVE 11.4 config. The 390x844 logical surface is phone-native and the
-- renderer letterboxes it cleanly in resizable desktop windows.
-- Pinned to 11.4 because love.js@11.4.1 (latest npm release) embeds the LÖVE
-- 11.4 runtime; declaring 11.5 caused indirect WASM calls to functions absent
-- in 11.4, throwing RuntimeError: null function on init. The battle-log client
-- uses only 11.0-era graphics/window APIs, so 11.4 is sufficient.
-- Bumping to 11.5 requires building Davidobot/love.js master against LÖVE 11.5
-- (tracked as a follow-up).
-- Audio modules disabled at boot for minimal dependency surface in love.js.
function love.conf(t)
    t.identity = "collack-spike"
    t.version = "11.4"
    t.console = false

    t.window.title = "Callack Auto-Battler"
    t.window.icon = nil
    t.window.width = 390
    t.window.height = 844
    t.window.resizable = true
    t.window.minwidth = 320
    t.window.minheight = 568
    t.window.vsync = 1
    t.window.msaa = 0
    t.window.highdpi = false

    -- Keep all modules enabled for love.js — the npm-prebuilt WASM blob
    -- has indirect-call entries that reference disabled-module init code,
    -- and disabling at conf time triggered RuntimeError: null function on
    -- boot. The Lua-level module flags don't shrink the WASM, so this is
    -- a no-cost change.
end
