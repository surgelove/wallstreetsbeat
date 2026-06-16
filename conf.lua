function love.conf(t)
    t.window.title = "STONKS"
    t.window.width = 1024
    t.window.height = 576  -- 16:9
    t.window.resizable = true
    t.window.minwidth = 568
    t.window.minheight = 320
    t.window.fullscreen = false
    t.window.fullscreentype = "exclusive"
    t.window.borderless = false
    t.window.highdpi = true
    t.identity = "aia_trade"
    t.modules.touch = true
    t.window.orientation = "landscape"  -- locks to landscape on mobile
end
