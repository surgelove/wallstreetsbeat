-- ── MODULES ──
require("constants")
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
    -- using default LOVE font
    initAudio()
    initData()
    refreshFeatureVisibility()
    welcomeImage = love.graphics.newImage("stonks.png")
    loadPresidentImages()
    recalcSafeArea()
    recalcLayout()
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
    love.graphics.setBackgroundColor(17/255, 20/255, 24/255)
    
    -- Transform into 16:9 safe area centered on screen
    love.graphics.push()
    love.graphics.translate(safeLeft, safeTop)
    
    if SCREEN == SCREENS.WELCOME then drawWelcome(safeWidth, safeHeight) end
    if SCREEN == SCREENS.PRESIDENT then drawPresident(safeWidth, safeHeight) end
    if SCREEN == SCREENS.SELECTOR then drawSelector(safeWidth, safeHeight) end
    if SCREEN == SCREENS.INTRO then drawIntro(safeWidth, safeHeight) end
    if SCREEN == SCREENS.TRADING then drawTrading(safeWidth, safeHeight) end
    if SCREEN == SCREENS.EOD then drawEOD(safeWidth, safeHeight) end
    if SCREEN == SCREENS.RECAP then drawRecap(safeWidth, safeHeight) end
    
    -- Toast overlay (within safe area)
    if toastMsg and toastTimer > 0 then
        love.graphics.setColor(0.1, 0.1, 0.18, 0.95)
        love.graphics.rectangle("fill", safeWidth/2 - 150, safeHeight/2 - 20, 300, 40, 5)
        love.graphics.setColor(0.94, 0.71, 0.16)
        love.graphics.printf(toastMsg, safeWidth/2 - 140, safeHeight/2 - 10, 280, "center")
    end
    
    love.graphics.pop()
end

-- ── MOUSE / TOUCH BRIDGE ──
pressedButtonId = nil

-- Convert screen coordinates to game-area (16:9) coordinates
local function gx(sx) return sx - safeLeft end
local function gy(sy) return sy - safeTop end

function love.mousepressed(x, y, b)
    if b ~= 1 then return end
    local gx, gy = x - safeLeft, y - safeTop
    for id, btn in pairs(Buttons) do
        if Button.hit(btn, gx, gy) then
            pressedButtonId = id
            return
        end
    end
end

function love.mousemoved(x, y, dx, dy)
    if SCREEN == SCREENS.TRADING then handleDrag(gx(x), gy(y)) end
end

function love.mousereleased(x, y, b)
    if b ~= 1 then return end
    pressedButtonId = nil
    local gx, gy = x - safeLeft, y - safeTop
    if SCREEN == SCREENS.TRADING then endDrag() end
    if SCREEN == SCREENS.WELCOME then
        pickPresident()
        SCREEN = SCREENS.PRESIDENT
    elseif SCREEN == SCREENS.PRESIDENT then
        SCREEN = SCREENS.SELECTOR
    end
    if SCREEN == SCREENS.SELECTOR then handleSelectorClick(gx, gy) end
    if SCREEN == SCREENS.INTRO then
        if isButtonHit("intro_ok", gx, gy) then
            SCREEN = SCREENS.TRADING
            initTradingSession()
        end
    end
    if SCREEN == SCREENS.TRADING then handleTradingClick(gx, gy) end
    if SCREEN == SCREENS.EOD then handleEODClick(gx, gy) end
    if SCREEN == SCREENS.RECAP then handleRecapClick(gx, gy) end
end

-- ── TOUCH SUPPORT ──
touchId = nil

function love.touchpressed(id, x, y, dx, dy, pressure)
    touchId = id
    local gx, gy = x - safeLeft, y - safeTop
    for bid, btn in pairs(Buttons) do
        if Button.hit(btn, gx, gy) then
            pressedButtonId = bid
            return
        end
    end
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    if id == touchId and SCREEN == SCREENS.TRADING then
        handleDrag(gx(x), gy(y))
    end
end

function love.touchreleased(id, x, y, dx, dy, pressure)
    if id == touchId then
        touchId = nil
        local gx, gy = x - safeLeft, y - safeTop
        if SCREEN == SCREENS.TRADING then endDrag() end
        if SCREEN == SCREENS.WELCOME then
            pickPresident()
            SCREEN = SCREENS.PRESIDENT
        elseif SCREEN == SCREENS.PRESIDENT then
            SCREEN = SCREENS.SELECTOR
        end
        if SCREEN == SCREENS.SELECTOR then handleSelectorClick(gx, gy) end
        if SCREEN == SCREENS.INTRO then
            if isButtonHit("intro_ok", gx, gy) then
                SCREEN = SCREENS.TRADING
                initTradingSession()
            end
        end
        if SCREEN == SCREENS.TRADING then handleTradingClick(gx, gy) end
        if SCREEN == SCREENS.EOD then handleEODClick(gx, gy) end
        if SCREEN == SCREENS.RECAP then handleRecapClick(gx, gy) end
    end
end

function love.resize(w, h)
    recalcSafeArea(w, h)
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
