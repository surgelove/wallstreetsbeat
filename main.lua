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
    INITIALS = "initials",
    PRESIDENT = "president",
    SELECTOR = "selector",
    PINS = "pins",
    TRADING = "trading",
    EOD = "eod",
    RECAP = "recap",
    ACHIEVEMENT = "achievement",
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
    buttonFont = love.graphics.newFont("fonts/default.ttf", sy(20))
    btnActionFont = love.graphics.newFont("fonts/default.ttf", sy(39))
    topFont = love.graphics.newFont("fonts/RobotoMono-VariableFont_wght.ttf", sy(20))
    headerValueFont = love.graphics.newFont("fonts/RobotoMono-VariableFont_wght.ttf", sy(26))
    initAudio()
    initData()
    refreshFeatureVisibility()
    loadUsers()
    chartDisplay = "pct"  -- "pct" or "price" for Y-axis labels
    leverage = 1          -- leverage multiplier
    playerInitials = ""   -- 3-letter initials for high scores
    goBackTo = nil        -- for settings BACK button
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
    -- Unlock notification timer
    if unlockTimer > 0 then
        unlockTimer = unlockTimer - dt
        if unlockTimer <= 0 then
            unlockMsg = nil
        end
    end
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
    
    -- Transform into 1920x1080 playable area, scaled to fill screen (like Balatro)
    love.graphics.push()
    love.graphics.translate(safeLeft, safeTop)
    love.graphics.scale(safeScale, safeScale)
    
    if SCREEN == SCREENS.WELCOME then drawWelcome(safeWidth, safeHeight) end
    if SCREEN == SCREENS.INITIALS then drawInitials(safeWidth, safeHeight) end
    if SCREEN == SCREENS.PRESIDENT then drawPresident(safeWidth, safeHeight) end
    if SCREEN == SCREENS.SELECTOR then drawSelector(safeWidth, safeHeight) end
    if SCREEN == SCREENS.PINS then drawPins(safeWidth, safeHeight) end
    if SCREEN == SCREENS.TRADING then drawTrading(safeWidth, safeHeight) end
    if SCREEN == SCREENS.EOD then drawEOD(safeWidth, safeHeight) end
    if SCREEN == SCREENS.RECAP then drawRecap(safeWidth, safeHeight) end
    if SCREEN == SCREENS.ACHIEVEMENT then drawAchievement(safeWidth, safeHeight) end
    if SCREEN == SCREENS.HIGHSCORE then drawHighscore(safeWidth, safeHeight) end
    if SCREEN == SCREENS.HIGHSCORELIST then drawHighscoreList(safeWidth, safeHeight) end
    if SCREEN == SCREENS.INSTRUCTIONS then drawInstructions(safeWidth, safeHeight) end
    if SCREEN == SCREENS.SETTINGS then drawSettings(safeWidth, safeHeight) end
    
    -- Unlock notification overlay (no background, fade-in, firework particles, rainbow halo text)
    if unlockMsg and unlockTimer > 0 then
        -- Rainbow color that pulses over time
        local h = (love.timer.getTime() * 0.5) % 1
        local r, g, b
        if h < 1/6 then local t = h * 6; r = 1; g = t; b = 0
        elseif h < 2/6 then local t = (h - 1/6) * 6; r = 1 - t; g = 1; b = 0
        elseif h < 3/6 then local t = (h - 2/6) * 6; r = 0; g = 1; b = t
        elseif h < 4/6 then local t = (h - 3/6) * 6; r = 0; g = 1 - t; b = 1
        elseif h < 5/6 then local t = (h - 4/6) * 6; r = t; g = 0; b = 1
        else local t = (h - 5/6) * 6; r = 1; g = 0; b = 1 - t end
        local msgFont = love.graphics.newFont("fonts/default.ttf", sy(30))
        love.graphics.setFont(msgFont)
        Button.printfWithHalo(unlockMsg, safeWidth/2 - sx(200), safeHeight/2 - sy(18), sx(400), "center", r, g, b, unlockAlpha)
        -- Draw unlock particles
        for _, p in ipairs(particles) do
            if p.isUnlock and p.x and p.life > 0 then
                local a = math.min(1, p.life / p.maxLife) * unlockAlpha
                love.graphics.setColor(p.r, p.g, p.b, a * 0.8)
                local size = 3 + (1 - p.life / p.maxLife) * 4
                love.graphics.circle("fill", p.x, p.y, size)
            end
        end
    end
    
    -- Toast overlay (for button feedback, errors, etc.)
    if toastMsg and toastTimer > 0 then
        love.graphics.setColor(0.1, 0.1, 0.18, 0.95)
        love.graphics.rectangle("fill", safeWidth/2 - sx(200), safeHeight/2 + sy(30), sx(400), sy(40), sy(5))
        love.graphics.setColor(0.94, 0.71, 0.16)
        local toastFont = love.graphics.newFont("fonts/default.ttf", sy(24))
        love.graphics.setFont(toastFont)
        love.graphics.printf(toastMsg, safeWidth/2 - sx(190), safeHeight/2 + sy(36), sx(380), "center")
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
    if SCREEN == SCREENS.ACHIEVEMENT then
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
    if SCREEN == SCREENS.ACHIEVEMENT then
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
        SCREEN = SCREENS.INITIALS
    elseif SCREEN == SCREENS.INITIALS then
        handleInitialsClick(gx, gy)
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
    if SCREEN == SCREENS.ACHIEVEMENT then handleAchievementClick(gx, gy) end
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
    if SCREEN == SCREENS.ACHIEVEMENT then
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
    if SCREEN == SCREENS.ACHIEVEMENT then
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
        if SCREEN == SCREENS.ACHIEVEMENT then
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
            SCREEN = SCREENS.INITIALS
        elseif SCREEN == SCREENS.INITIALS then
            handleInitialsClick(gx, gy)
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
        if SCREEN == SCREENS.ACHIEVEMENT then handleAchievementClick(gx, gy) end
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
    if key == "escape" then
        love.event.quit()
    end
    if key == "backspace" then
        if SCREEN == SCREENS.INITIALS then
            playerInitials = playerInitials:sub(1, -2)
        elseif SCREEN == SCREENS.HIGHSCORE then
            highscoreInitials = highscoreInitials:sub(1, -2)
        end
    end
    if key == "return" then
        if SCREEN == SCREENS.INITIALS and #playerInitials > 0 then
            SCREEN = SCREENS.PRESIDENT
            pickPresident()
        elseif SCREEN == SCREENS.HIGHSCORE and #highscoreInitials > 0 then
            addHighScore(highscoreInitials, highscoreNewScore)
            highscoreInitials = "SAVED"
        end
    end
end

function love.textinput(t)
    if #playerInitials < 3 and SCREEN == SCREENS.INITIALS then
        local upper = t:upper()
        if upper:match("^[A-Z]$") then
            playerInitials = playerInitials .. upper
        end
        return
    end
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
