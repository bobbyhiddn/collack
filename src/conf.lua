-- LÖVE 11.5 config. Window is 800x600, internal-pixel target.
-- Audio modules disabled at boot for minimal dependency surface in love.js.
function love.conf(t)
    t.identity = "collack-spike"
    t.version = "11.5"
    t.console = false

    t.window.title = "Collack Spike"
    t.window.icon = nil
    t.window.width = 800
    t.window.height = 600
    t.window.resizable = false
    t.window.vsync = 1
    t.window.msaa = 0
    t.window.highdpi = false

    -- Disable modules we don't use; smaller WASM and fewer browser warnings.
    t.modules.audio = false
    t.modules.sound = false
    t.modules.physics = false
    t.modules.video = false
    t.modules.joystick = false
    t.modules.touch = true   -- keep on for iOS Capacitor wrap
    t.modules.thread = false
end
