-- ── MODULES ──
require("constants")
suit = require("suit")
require("audio")
require("data")
require("game")
require("chart")
require("ui")

-- ── SCREEN MANAGEMENT ──
SCREEN = "welcome"
SCREENS = {
    WELCOME = "welcome",
    PRESIDENT = "president",
    SELECTOR = "selector",
    INTRO = "intro",
    TRADING = "trading",
    EOD = "eod",
    RECAP = "recap",
}

-- ── LOVE CALLBACKS ──
function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("STONKS")
    chartFont = love.graphics.newFont("fonts/Inter-Regular.ttf", 11)
    love.graphics.setFont(love.graphics.newFont("fonts/pixel.ttf", 14))
    initAudio()
    initData()
    refreshFeatureVisibility()
    welcomeImage = love.graphics.newImage("stonks.png")
    loadPresidentImages()
end

function love.update(dt)
    if SCREEN == SCREENS.TRADING and not tickPaused and dataMode then
        tickTimer = tickTimer + dt
        local interval = TICK_INTERVAL / speedMult
        if tickTimer >= interval then
            tickTimer = 0
            tick()
        end
    end
    if toastTimer > 0 then
        toastTimer = toastTimer - dt
        if toastTimer <= 0 then toastMsg = nil end
    end
    updateParticles(dt)
end

function love.draw()
    local w, h = love.graphics.getDimensions()
    
    love.graphics.setBackgroundColor(17/255, 20/255, 24/255)
    
    -- SUIT: reset per-frame state (must come before any widget definitions)
    suit._instance:enterFrame()
    
    if SCREEN == SCREENS.WELCOME then drawWelcome(w, h) end
    if SCREEN == SCREENS.PRESIDENT then drawPresident(w, h) end
    if SCREEN == SCREENS.SELECTOR then drawSelector(w, h) end
    if SCREEN == SCREENS.INTRO then drawIntro(w, h) end
    if SCREEN == SCREENS.TRADING then drawTrading(w, h) end
    if SCREEN == SCREENS.EOD then drawEOD(w, h) end
    if SCREEN == SCREENS.RECAP then drawRecap(w, h) end
    
    -- SUIT: render all registered widgets
    suit.draw()
    
    -- Toast overlay
    if toastMsg and toastTimer > 0 then
        love.graphics.setColor(0.1, 0.1, 0.18, 0.95)
        love.graphics.rectangle("fill", w/2 - 150, h/2 - 20, 300, 40, 5)
        love.graphics.setColor(0.94, 0.71, 0.16)
        love.graphics.printf(toastMsg, w/2 - 140, h/2 - 10, 280, "center")
    end
end

-- ── MOUSE / TOUCH BRIDGE ──
-- SUIT handles button clicks internally via mouseReleasedOn().
-- We only need to forward low-level events to SUIT and handle
-- non-button interactions (drag, welcome tap).

function love.mousemoved(x, y, dx, dy)
    if SCREEN == SCREENS.TRADING then handleDrag(x, y) end
end

function love.mousereleased(x, y, b)
    if SCREEN == SCREENS.TRADING then endDrag() end
    if SCREEN == SCREENS.WELCOME then
        pickPresident()
        SCREEN = SCREENS.PRESIDENT
    elseif SCREEN == SCREENS.PRESIDENT then
        SCREEN = SCREENS.SELECTOR
    end
end

-- ── TOUCH SUPPORT ──
touchId = nil

function love.touchpressed(id, x, y, dx, dy, pressure)
    touchId = id
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    if id == touchId and SCREEN == SCREENS.TRADING then
        handleDrag(x, y)
    end
end

function love.touchreleased(id, x, y, dx, dy, pressure)
    if id == touchId then
        touchId = nil
        if SCREEN == SCREENS.TRADING then endDrag() end
        if SCREEN == SCREENS.WELCOME then
            pickPresident()
            SCREEN = SCREENS.PRESIDENT
        elseif SCREEN == SCREENS.PRESIDENT then
            SCREEN = SCREENS.SELECTOR
        end
    end
end

-- ── SUIT KEYBOARD FORWARDING ──
function love.textinput(t)
    suit.textinput(t)
end

function love.resize(w, h)
    recalcLayout()
end

function love.keypressed(key)
    if key == "f11" or key == "f" then
        love.window.setFullscreen(not love.window.getFullscreen())
    end
    -- ESC quits on mobile
    if key == "escape" then
        love.event.quit()
    end
end

-- ── TIMING ──
tickTimer = 0
tickPaused = false
speedMult = 1.0
toastMsg = nil
toastTimer = 0
