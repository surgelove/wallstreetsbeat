function love.conf(t)
    t.window.title = "wallstreetsbeat"
    t.window.width = 1920
    t.window.height = 1080  -- 16:9
    t.window.resizable = true
    t.window.minwidth = 1065
    t.window.minheight = 600
    t.window.fullscreen = false
    t.window.fullscreentype = "exclusive"
    t.window.borderless = false
    t.window.highdpi = true
    t.identity = "aia_trade"
    t.modules.touch = true
    t.window.orientation = "landscape"  -- locks to landscape on mobile
end
