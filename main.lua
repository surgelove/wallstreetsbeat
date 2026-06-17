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
    PINS = "pins",
    TRADING = "trading",
    EOD = "eod",
    RECAP = "recap",
    HIGHSCORE = "highscore",
    HIGHSCORELIST = "highscorelist",
    INSTRUCTIONS = "instructions",
    SETTINGS = "settings",
}

-- ── LOVE CALLBACKS ──
function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("STONKS")
    -- using default LOVE font
    buttonFont = love.graphics.newFont("fonts/default.ttf", sy(13))
    btnActionFont = love.graphics.newFont("fonts/default.ttf", sy(26))
    topFont = love.graphics.newFont("fonts/RobotoMono-VariableFont_wght.ttf", sy(13))
    headerValueFont = love.graphics.newFont("fonts/RobotoMono-VariableFont_wght.ttf", sy(17))
    initAudio()
    initData()
    refreshFeatureVisibility()
    chartDisplay = "pct"  -- "pct" or "price" for Y-axis labels
    welcomeImage = love.graphics.newImage("stonks.png")
    local ok, img = pcall(love.graphics.newImage, "avatar.png")
    if ok then avatarImage = img else avatarImage = nil end
    local ok2, img2 = pcall(love.graphics.newImage, "padlock.png")
    if ok2 then padlockImage = img2 else padlockImage = nil end
    loadPresidentImages()
    recalcSafeArea()
    recalcLayout()
    speedSlider = Slider.new("speed", 0, 0, sx(100), sy(20), {
        min = 0, max = 1, value = 0.5, step = 0,
        label = "",
        onChange = function(f)
            speedMult = 10 ^ (2 * f - 1)
            speedToastTimer = 1.5
        end
    })
    speedMult = 1
    Background.init()
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
    if speedToastTimer > 0 then speedToastTimer = speedToastTimer - dt end
    -- Update background mood based on realized P&L
    if SCREEN == SCREENS.TRADING then
        local r = realizedPnl or 0
        if r > 0 then
            Background.setMood("green")
        elseif r < 0 then
            Background.setMood("red")
        else
            Background.setMood("gray")
        end
    else
        Background.setNeutral()
    end
    Background.update(dt)
    updateParticles(dt)
    updatePinSpin(dt)
end

function love.draw()
    -- Match clear color to background so any uncovered areas blend in
    love.graphics.setBackgroundColor(0.08, 0.08, 0.14)
    -- Draw velvet background full-screen first (fills the entire display)
    Background.draw(love.graphics.getWidth(), love.graphics.getHeight())
    
    -- Transform into 1280x720 playable area, scaled to fill screen (like Balatro)
    love.graphics.push()
    love.graphics.translate(safeLeft, safeTop)
    love.graphics.scale(safeScale, safeScale)
    
    if SCREEN == SCREENS.WELCOME then drawWelcome(safeWidth, safeHeight) end
    if SCREEN == SCREENS.PRESIDENT then drawPresident(safeWidth, safeHeight) end
    if SCREEN == SCREENS.SELECTOR then drawSelector(safeWidth, safeHeight) end
    if SCREEN == SCREENS.PINS then drawPins(safeWidth, safeHeight) end
    if SCREEN == SCREENS.TRADING then drawTrading(safeWidth, safeHeight) end
    if SCREEN == SCREENS.EOD then drawEOD(safeWidth, safeHeight) end
    if SCREEN == SCREENS.RECAP then drawRecap(safeWidth, safeHeight) end
    if SCREEN == SCREENS.HIGHSCORE then drawHighscore(safeWidth, safeHeight) end
    if SCREEN == SCREENS.HIGHSCORELIST then drawHighscoreList(safeWidth, safeHeight) end
    if SCREEN == SCREENS.INSTRUCTIONS then drawInstructions(safeWidth, safeHeight) end
    if SCREEN == SCREENS.SETTINGS then drawSettings(safeWidth, safeHeight) end
    
    -- Toast overlay (within safe area)
    if toastMsg and toastTimer > 0 then
        love.graphics.setColor(0.1, 0.1, 0.18, 0.95)
        love.graphics.rectangle("fill", safeWidth/2 - sx(150), safeHeight/2 - sy(20), sx(300), sy(40), sy(5))
        love.graphics.setColor(0.94, 0.71, 0.16)
        love.graphics.printf(toastMsg, safeWidth/2 - sx(140), safeHeight/2 - sy(10), sx(280), "center")
    end
    
    love.graphics.pop()
end

-- ── MOUSE / TOUCH BRIDGE ──
pressedButtonId = nil

-- Convert screen coordinates to game-area (1280x720) coordinates
local function gx(sx) return (sx - safeLeft) / safeScale end
local function gy(sy) return (sy - safeTop) / safeScale end

function love.mousepressed(x, y, b)
    if b ~= 1 then return end
    local gx, gy = (x - safeLeft) / safeScale, (y - safeTop) / safeScale
    for id, btn in pairs(Buttons) do
        if Button.hit(btn, gx, gy) then
            pressedButtonId = id
            return
        end
    end
    if SCREEN == SCREENS.PINS then
        if tryPinPress(gx, gy) then return end
    end
    if SCREEN == SCREENS.TRADING then
        if speedSlider and Slider.press(speedSlider, gx, gy) then
            speedSlider._tapped = true
            return
        end
        local picked = pickOrderLine(gx, gy)
        if picked then
            dragLine = picked
            handleDrag(gx, gy)
        end
    end
end

function love.mousemoved(x, y, dx, dy)
    if SCREEN == SCREENS.PINS then
        doPinDrag(gx(x))
        return
    end
    if SCREEN == SCREENS.TRADING then
        if speedSlider and speedSlider._dragging then
            speedSlider._tapped = false
            Slider.drag(speedSlider, gx(x))
        end
        handleDrag(gx(x), gy(y))
    end
end

function love.mousereleased(x, y, b)
    if b ~= 1 then return end
    pressedButtonId = nil
    local gx, gy = (x - safeLeft) / safeScale, (y - safeTop) / safeScale
    if SCREEN == SCREENS.PINS then
        doPinRelease()
    end
    if SCREEN == SCREENS.TRADING then
        if speedSlider then
            if speedSlider._tapped then
                speedSlider.value = 0.5
                speedSlider.onChange(0.5)
            end
            Slider.release(speedSlider)
        end
        if dragLine and wasOrderLineTap(gx, gy) then
            playX()
            removeOrderLine(dragLine)
        end
        endDrag()
    end
    if SCREEN == SCREENS.WELCOME then
        pickPresident()
        SCREEN = SCREENS.PRESIDENT
    elseif SCREEN == SCREENS.PRESIDENT then
        -- Check if BACK button was pressed
        local b = Buttons["pres_back"]
        if b and Button.hit(b, gx, gy) and b.onClick then
            b.onClick()
        else
            currentDay = 1
            SCREEN = SCREENS.SELECTOR
        end
    end
    if SCREEN == SCREENS.SELECTOR then handleSelectorClick(gx, gy) end
    if SCREEN == SCREENS.PINS then handlePinsClick(gx, gy) end
    if SCREEN == SCREENS.TRADING then handleTradingClick(gx, gy) end
    if SCREEN == SCREENS.EOD then handleEODClick(gx, gy) end
    if SCREEN == SCREENS.RECAP then handleRecapClick(gx, gy) end
    if SCREEN == SCREENS.HIGHSCORE then handleHighscoreClick(gx, gy) end
    if SCREEN == SCREENS.HIGHSCORELIST then handleHighscoreListClick(gx, gy) end
    if SCREEN == SCREENS.INSTRUCTIONS then handleInstructionsClick(gx, gy) end
    if SCREEN == SCREENS.SETTINGS then handleSettingsClick(gx, gy) end
end

-- ── TOUCH SUPPORT ──
touchId = nil

function love.touchpressed(id, x, y, dx, dy, pressure)
    touchId = id
    local gx, gy = (x - safeLeft) / safeScale, (y - safeTop) / safeScale
    for bid, btn in pairs(Buttons) do
        if Button.hit(btn, gx, gy) then
            pressedButtonId = bid
            return
        end
    end
    if SCREEN == SCREENS.PINS then
        if tryPinPress(gx, gy) then return end
    end
    if SCREEN == SCREENS.TRADING then
        if speedSlider and Slider.press(speedSlider, gx, gy) then
            speedSlider._tapped = true
            return
        end
        local picked = pickOrderLine(gx, gy)
        if picked then
            dragLine = picked
            handleDrag(gx, gy)
        end
    end
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    if SCREEN == SCREENS.PINS then
        doPinDrag(gx(x))
        return
    end
    if id == touchId and SCREEN == SCREENS.TRADING then
        if speedSlider and speedSlider._dragging then
            speedSlider._tapped = false
            Slider.drag(speedSlider, gx(x))
        end
        handleDrag(gx(x), gy(y))
    end
end

function love.touchreleased(id, x, y, dx, dy, pressure)
    if id == touchId then
        touchId = nil
        local gx, gy = (x - safeLeft) / safeScale, (y - safeTop) / safeScale
        if SCREEN == SCREENS.PINS then
            doPinRelease()
        end
        if SCREEN == SCREENS.TRADING then
            if speedSlider then
                if speedSlider._tapped then
                    speedSlider.value = 0.5
                    speedSlider.onChange(0.5)
                end
                Slider.release(speedSlider)
            end
            if dragLine and wasOrderLineTap(gx, gy) then
                playX()
                removeOrderLine(dragLine)
            end
            endDrag()
        end
        if SCREEN == SCREENS.WELCOME then
            pickPresident()
            SCREEN = SCREENS.PRESIDENT
        elseif SCREEN == SCREENS.PRESIDENT then
            local b = Buttons["pres_back"]
            if b and Button.hit(b, gx, gy) and b.onClick then
                b.onClick()
            else
                SCREEN = SCREENS.SELECTOR
            end
        end
        if SCREEN == SCREENS.SELECTOR then handleSelectorClick(gx, gy) end
        if SCREEN == SCREENS.PINS then handlePinsClick(gx, gy) end
        if SCREEN == SCREENS.TRADING then handleTradingClick(gx, gy) end
        if SCREEN == SCREENS.EOD then handleEODClick(gx, gy) end
        if SCREEN == SCREENS.RECAP then handleRecapClick(gx, gy) end
        if SCREEN == SCREENS.HIGHSCORE then handleHighscoreClick(gx, gy) end
        if SCREEN == SCREENS.HIGHSCORELIST then handleHighscoreListClick(gx, gy) end
        if SCREEN == SCREENS.INSTRUCTIONS then handleInstructionsClick(gx, gy) end
        if SCREEN == SCREENS.SETTINGS then handleSettingsClick(gx, gy) end
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
    -- Backspace for high score initials
    if key == "backspace" and SCREEN == SCREENS.HIGHSCORE then
        highscoreInitials = highscoreInitials:sub(1, -2)
    end
    -- Return confirms initials
    if key == "return" and SCREEN == SCREENS.HIGHSCORE and #highscoreInitials > 0 then
        addHighScore(highscoreInitials, highscoreNewScore)
        highscoreInitials = "SAVED"
    end
end

function love.textinput(t)
    if SCREEN ~= SCREENS.HIGHSCORE then return end
    if #highscoreInitials >= 3 then return end
    if highscoreInitials == "SAVED" then return end
    -- Only allow uppercase letters
    local upper = t:upper()
    if upper:match("^[A-Z]$") then
        highscoreInitials = highscoreInitials .. upper
    end
end

-- ── TIMING ──
tickTimer = 0
tickPaused = false
speedMult = 1.0
toastMsg = nil
toastTimer = 0
speedToastTimer = 0
