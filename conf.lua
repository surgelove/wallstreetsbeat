function love.conf(t)
    t.window.title = "STONKS"
    t.window.width = 1280
    t.window.height = 720  -- 16:9
    t.window.resizable = true
    t.window.minwidth = 710
    t.window.minheight = 400
    t.window.fullscreen = false
    t.window.fullscreentype = "exclusive"
    t.window.borderless = false
    t.window.highdpi = true
    t.identity = "aia_trade"
    t.modules.touch = true
    t.window.orientation = "landscape"  -- locks to landscape on mobile
end
