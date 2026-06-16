function love.conf(t)
    t.window.title = "STONKS"
    t.window.width = 1024
    t.window.height = 600
    t.window.resizable = true
    t.window.minwidth = 360
    t.window.minheight = 640
    t.window.fullscreen = false
    t.window.fullscreentype = "exclusive"
    t.window.borderless = false
    t.identity = "aia_trade"
    -- Mobile: accelerometer, touch, etc.
    t.modules.touch = true
end
