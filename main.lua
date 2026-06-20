-- ── MODULES ──
require("constants")
require("audio")
require("data")
require("game")
require("chart")
require("ui")

-- ── SCREEN MANAGEMENT ──
SCREEN = "canvas"
SCREENS = {
    CANVAS = "canvas",
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
    love.window.setTitle("wallstreetsbeat")
    -- using default LOVE font
    buttonFont = love.graphics.newFont("fonts/default.ttf", sy(20))
    btnActionFont = love.graphics.newFont("fonts/default.ttf", sy(39))
    topFont = love.graphics.newFont("fonts/RobotoMono-VariableFont_wght.ttf", sy(20))
    headerValueFont = love.graphics.newFont("fonts/default.ttf", sy(26))
    headerValueBigFont = love.graphics.newFont("fonts/default.ttf", sy(39))
    initAudio()
    initData()
    refreshFeatureVisibility()
    loadUsers()
    chartDisplay = "pct"  -- "pct" or "price" for Y-axis labels
    leverage = 1          -- leverage multiplier
    playerInitials = ""   -- 3-letter initials for high scores
    goBackTo = nil        -- for settings BACK button
    welcomeImage = love.graphics.newImage("wallstreetsbeat.jpg")
    local ok, img = pcall(love.graphics.newImage, "avatar.png")
    if ok then avatarImage = img else avatarImage = nil end
    local ok2, img2 = pcall(love.graphics.newImage, "padlock.png")
    if ok2 then padlockImage = img2 else padlockImage = nil end
    local ok3, img3 = pcall(love.graphics.newImage, "sprites/tendy.png")
    if ok3 then tendyImage = img3 else tendyImage = nil end
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
    levSlider = Slider.new("lev", 0, 0, sx(100), sy(20), {
        min = 1, max = 20, value = 1, step = 1,
        label = "",
        accentColor = {0.48, 0.41, 0.93},
        onChange = function(v)
            leverage = v
        end
    })
    ITER_VALUES = {1, 2, 4, 5, 10}
    tradeIterations = 1
    iterSlider = Slider.new("iter", 0, 0, sx(100), sy(20), {
        min = 1, max = 5, value = 1, step = 1,
        label = "",
        accentColor = {0.20, 0.80, 0.60},
        onChange = function(v)
            tradeIterations = ITER_VALUES[math.floor(v)] or 1
        end
    })
    buyStopHeld = false
    sellStopHeld = false
    stopRepeatTimer = 0
    rewindHeld = false
    forwardHeld = false
    rewindRepeatTimer = 0
    rewindButtonWasHeld = false
    wasRewinding = false
    prevRewindEnd = 0

    -- Canvas sprites: load from config with per-sprite scales
    canvasSprites = {}
    canvasWsb = nil
    local spriteConfig = instrumentConfig.canvasSprites or {}
    math.randomseed(os.time())
    for _, sc in ipairs(spriteConfig) do
        local ok, img = pcall(love.graphics.newImage, "sprites/" .. sc.file)
        if ok then
            local iw, ih = img:getDimensions()
            local scale = sc.scale or 0.3
            local sw, sh = iw * scale, ih * scale
            local entry = {
                image = img,
                file = sc.file,
                x = math.random(sx(40), safeWidth - sw - sx(40)),
                y = math.random(sy(40), safeHeight - sh - sy(40)),
                scale = scale,
                w = sw,
                h = sh,
            }
            table.insert(canvasSprites, entry)
        end
    end
    -- Load wsb.png separately — always drawn on top
    local okWsb, wsbImg = pcall(love.graphics.newImage, "sprites/wsb.png")
    if okWsb then
        local wsbScale = instrumentConfig.canvasWsbScale or 0.55
        local wiw, wih = wsbImg:getDimensions()
        local wsw, wsh = wiw * wsbScale, wih * wsbScale
        canvasWsb = {
            image = wsbImg,
            file = "wsb.png",
            x = math.random(sx(40), safeWidth - wsw - sx(40)),
            y = math.random(sy(40), safeHeight - wsh - sy(40)),
            scale = wsbScale,
            w = wsw,
            h = wsh,
        }
    end
    -- Load saved canvas positions if they exist
    loadCanvasPositions()

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
    -- Stop order repeat on long press
    if stopRepeatTimer > 0 and (buyStopHeld or sellStopHeld) then
        stopRepeatTimer = stopRepeatTimer - dt
        if stopRepeatTimer <= 0 then
            if buyStopHeld then createBuyStop() end
            if sellStopHeld then createSellStop() end
            stopRepeatTimer = 0.2
        end
    end
    -- Rewind repeat on long press (keyboard + on-screen button)
    if pressedButtonId == "btn-rewind" then
        rewindHeld = true
        rewindButtonWasHeld = true
        if rewindRepeatTimer <= 0 then
            tickPaused = true
            rewindTicks = math.min((rewindTicks or 0) + 1, 720)
            rewindRepeatTimer = 0.067 / math.max(speedMult or 1, 1)
        end
    else
        if rewindButtonWasHeld and (rewindTicks or 0) > 0 then
            resumeFromRewind()
        end
        rewindButtonWasHeld = false
        rewindHeld = false
    end
    if rewindRepeatTimer > 0 then
        rewindRepeatTimer = rewindRepeatTimer - dt
        if rewindRepeatTimer <= 0 and (rewindHeld or forwardHeld) then
            if rewindHeld then
                tickPaused = true
                rewindTicks = math.min((rewindTicks or 0) + 1, 720)
            elseif forwardHeld then
                rewindTicks = math.max(0, (rewindTicks or 0) - 1)
                if rewindTicks == 0 then tickPaused = false; showDogImage = false end
            end
            rewindRepeatTimer = 0.067 / math.max(speedMult or 1, 1)
        end
    end
    -- Restore state when rewound
    if (rewindTicks or 0) > 0 then
        if not wasRewinding then
            startRewindSound()
            wasRewinding = true
            prevRewindEnd = #prices
        end
        local rewindEnd = math.max(1, #prices - (rewindTicks or 0))
        -- Detect trade marker crossings during rewind
        if rewindEnd ~= prevRewindEnd then
            for _, m in ipairs(tradeMarkers) do
                if m.idx >= math.min(rewindEnd, prevRewindEnd) and m.idx <= math.max(rewindEnd, prevRewindEnd) then
                    if m.type == "buy" then playBuy() end
                    if m.type == "sell" then playSell() end
                    if m.type == "star-win" or m.type == "star-lose" then
                        if m.type == "star-win" then playStar() else playX() end
                    end
                    break
                end
            end
        end
        prevRewindEnd = rewindEnd
        updateRewindSound(dt)
        restoreRewindState()
    else
        if wasRewinding then
            stopRewindSound()
            wasRewinding = false
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
    -- Update background mood based on unrealized P&L
    if SCREEN == SCREENS.TRADING then
        local r = pnl or 0
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
    updateBall(dt)
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
    
    if SCREEN == SCREENS.CANVAS then drawCanvas(safeWidth, safeHeight) end
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
canvasDragSprite = nil
canvasDragOffX = 0
canvasDragOffY = 0
canvasWasDragged = false
canvasCopyCount = 0

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
    if SCREEN == SCREENS.CANVAS then
        canvasDragSprite = nil
        canvasWasDragged = false
        -- Check wsb first (always on top)
        if canvasWsb and gx >= canvasWsb.x and gx <= canvasWsb.x + canvasWsb.w
           and gy >= canvasWsb.y and gy <= canvasWsb.y + canvasWsb.h then
            canvasDragSprite = canvasWsb
            canvasDragOffX = gx - canvasWsb.x
            canvasDragOffY = gy - canvasWsb.y
            return
        end
        if canvasSprites then
            for i = #canvasSprites, 1, -1 do
                local s = canvasSprites[i]
                if gx >= s.x and gx <= s.x + s.w
                   and gy >= s.y and gy <= s.y + s.h then
                    canvasDragSprite = s
                    canvasDragOffX = gx - s.x
                    canvasDragOffY = gy - s.y
                    -- Move to front (swap with last)
                    canvasSprites[i] = canvasSprites[#canvasSprites]
                    canvasSprites[#canvasSprites] = s
                    return
                end
            end
        end
    end
    if SCREEN == SCREENS.TRADING then
        if speedSlider and Slider.press(speedSlider, gx, gy) then
            speedSlider._tapped = true
            return
        end
        -- Leverage slider
        if levSlider and Slider.press(levSlider, gx, gy) then
            levSlider._tapped = true
            return
        end
        -- Iterations slider
        if iterSlider and Slider.press(iterSlider, gx, gy) then
            iterSlider._tapped = true
            return
        end
        -- Avatar drag
        if avatarHitW > 0 and gx >= avatarHitX and gx <= avatarHitX + avatarHitW
           and gy >= avatarHitY and gy <= avatarHitY + avatarHitH then
            avatarDragging = true
            return
        end
        local picked = pickOrderLine(gx, gy)
        if picked then
            dragLine = picked
            handleDrag(gx, gy)
        end
        -- Ball drag
        if ballPhase and ballImage then
            local dxx = gx - ballX
            local dyy = gy - ballY
            if dxx * dxx + dyy * dyy <= (ballRadius + sy(4)) ^ 2 then
                ballDragging = true
                ballPhase = "dragging"
                return
            end
        end
    end
end

function love.mousemoved(x, y, dx, dy)
    if canvasDragSprite then
        canvasDragSprite.x = gx(x) - canvasDragOffX
        canvasDragSprite.y = gy(y) - canvasDragOffY
        canvasWasDragged = true
        return
    end
    if SCREEN == SCREENS.PINS then
        doPinDrag(gx(x))
        return
    end
    if SCREEN == SCREENS.ACHIEVEMENT then
        doPinDrag(gx(x))
        return
    end
    if SCREEN == SCREENS.TRADING then
        if levSlider and levSlider._dragging then
            levSlider._tapped = false
            Slider.drag(levSlider, gx(x))
            return
        end
        if iterSlider and iterSlider._dragging then
            iterSlider._tapped = false
            Slider.drag(iterSlider, gx(x))
            return
        end
        if avatarDragging then
            avatarOffX = avatarOffX + dx
            avatarOffY = avatarOffY + dy
            return
        end
        if speedSlider and speedSlider._dragging then
            speedSlider._tapped = false
            Slider.drag(speedSlider, gx(x))
        end
        handleDrag(gx(x), gy(y))
    end
    -- Ball drag move
    if ballDragging then
        ballX = gx(x)
        ballY = gy(y)
        ballVX = 0
        ballVY = 0
        return
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
        avatarDragging = false
        if ballDragging then
            ballDragging = false
            -- Check if released over the dog/paws — award a tendy!
            local pawsBtn = Buttons["btn-paws"]
            if pawsBtn and ballX >= pawsBtn.x and ballX <= pawsBtn.x + pawsBtn.w
               and ballY >= pawsBtn.y and ballY <= pawsBtn.y + pawsBtn.h then
                tendies = math.min(tendies + 1, 10)
                ballPhase = nil
            else
                ballPhase = "falling"
                ballVX = 0
                ballVY = 0
            end
        end
        if levSlider then
            if levSlider._tapped then
                levSlider.value = 1
                levSlider.onChange(1)
            end
            Slider.release(levSlider)
        end
        if iterSlider then
            if iterSlider._tapped then
                iterSlider.value = 1
                iterSlider.onChange(1)
            end
            Slider.release(iterSlider)
        end
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
    if SCREEN == SCREENS.CANVAS then
        if canvasWasDragged then
            checkReplicatorCopy(canvasDragSprite)
            checkLiquidateDestroy(canvasDragSprite)
            canvasDragSprite = nil
            canvasWasDragged = false
            saveCanvasPositions()
        else
            handleCanvasClick(gx, gy)
        end
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
    if SCREEN == SCREENS.CANVAS then
        canvasDragSprite = nil
        canvasWasDragged = false
        -- Check wsb first (always on top)
        if canvasWsb and gx >= canvasWsb.x and gx <= canvasWsb.x + canvasWsb.w
           and gy >= canvasWsb.y and gy <= canvasWsb.y + canvasWsb.h then
            canvasDragSprite = canvasWsb
            canvasDragOffX = gx - canvasWsb.x
            canvasDragOffY = gy - canvasWsb.y
            return
        end
        if canvasSprites then
            for i = #canvasSprites, 1, -1 do
                local s = canvasSprites[i]
                if gx >= s.x and gx <= s.x + s.w
                   and gy >= s.y and gy <= s.y + s.h then
                    canvasDragSprite = s
                    canvasDragOffX = gx - s.x
                    canvasDragOffY = gy - s.y
                    canvasSprites[i] = canvasSprites[#canvasSprites]
                    canvasSprites[#canvasSprites] = s
                    return
                end
            end
        end
    end
    if SCREEN == SCREENS.TRADING then
        if speedSlider and Slider.press(speedSlider, gx, gy) then
            speedSlider._tapped = true
            return
        end
        -- Leverage slider
        if levSlider and Slider.press(levSlider, gx, gy) then
            levSlider._tapped = true
            return
        end
        -- Iterations slider
        if iterSlider and Slider.press(iterSlider, gx, gy) then
            iterSlider._tapped = true
            return
        end
        -- Avatar drag
        if avatarHitW > 0 and gx >= avatarHitX and gx <= avatarHitX + avatarHitW
           and gy >= avatarHitY and gy <= avatarHitY + avatarHitH then
            avatarDragging = true
            return
        end
        local picked = pickOrderLine(gx, gy)
        if picked then
            dragLine = picked
            handleDrag(gx, gy)
        end
        -- Ball drag (touch)
        if ballPhase and ballImage then
            local dxx = gx - ballX
            local dyy = gy - ballY
            if dxx * dxx + dyy * dyy <= (ballRadius + sy(4)) ^ 2 then
                ballDragging = true
                ballPhase = "dragging"
                return
            end
        end
    end
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    if canvasDragSprite then
        canvasDragSprite.x = gx(x) - canvasDragOffX
        canvasDragSprite.y = gy(y) - canvasDragOffY
        canvasWasDragged = true
        return
    end
    if SCREEN == SCREENS.PINS then
        doPinDrag(gx(x))
        return
    end
    if SCREEN == SCREENS.ACHIEVEMENT then
        doPinDrag(gx(x))
        return
    end
    if id == touchId and SCREEN == SCREENS.TRADING then
        if levSlider and levSlider._dragging then
            levSlider._tapped = false
            Slider.drag(levSlider, gx(x))
            return
        end
        if avatarDragging then
            avatarOffX = avatarOffX + dx
            avatarOffY = avatarOffY + dy
            return
        end
        if iterSlider and iterSlider._dragging then
            iterSlider._tapped = false
            Slider.drag(iterSlider, gx(x))
        end
        if speedSlider and speedSlider._dragging then
            speedSlider._tapped = false
            Slider.drag(speedSlider, gx(x))
        end
        handleDrag(gx(x), gy(y))
    end
    -- Ball drag move (touch)
    if ballDragging then
        ballX = gx(x)
        ballY = gy(y)
        ballVX = 0
        ballVY = 0
        return
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
            avatarDragging = false
            if ballDragging then
                ballDragging = false
                local pawsBtn = Buttons["btn-paws"]
                if pawsBtn and ballX >= pawsBtn.x and ballX <= pawsBtn.x + pawsBtn.w
                   and ballY >= pawsBtn.y and ballY <= pawsBtn.y + pawsBtn.h then
                    tendies = math.min(tendies + 1, 10)
                    ballPhase = nil
                else
                    ballPhase = "falling"
                    ballVX = 0
                    ballVY = 0
                end
            end
            if levSlider then
                if levSlider._tapped then
                    levSlider.value = 1
                    levSlider.onChange(1)
                end
                Slider.release(levSlider)
            end
            if iterSlider then
                if iterSlider._tapped then
                    iterSlider.value = 1
                    iterSlider.onChange(1)
                end
                Slider.release(iterSlider)
            end
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
        if SCREEN == SCREENS.CANVAS then
            if canvasWasDragged then
                checkReplicatorCopy(canvasDragSprite)
                checkLiquidateDestroy(canvasDragSprite)
                canvasDragSprite = nil
                canvasWasDragged = false
                saveCanvasPositions()
            else
                handleCanvasClick(gx, gy)
            end
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
        if SCREEN == SCREENS.TRADING then
            removeAllOrderLines()
        else
            love.event.quit()
        end
    end
    if SCREEN == SCREENS.TRADING and not tickPaused and dataMode then
        if key == "lshift" then sell() end
        if key == "rshift" then buy() end
        if key == "space" then closePosition() end
        if key == "left" and speedSlider then
            speedSlider.value = math.max(0, speedSlider.value - 0.05)
            speedSlider.onChange(speedSlider.value)
        end
        if key == "right" and speedSlider then
            speedSlider.value = math.min(1, speedSlider.value + 0.05)
            speedSlider.onChange(speedSlider.value)
        end
        if key == "tab" then
            if position ~= 0 then
                local hasSL = false
                for _, l in ipairs(orderLines) do
                    if l.type == "stop-loss" then hasSL = true; break end
                end
                if not hasSL then
                    local sp = instrumentConfig.stopStepPct or 0.004
                    local slPrice = position > 0 and math.floor((currentBid - currentPrice * sp * 2) * 1000 + 0.5) / 1000 or math.floor((currentAsk + currentPrice * sp * 2) * 1000 + 0.5) / 1000
                    addOrderLine("stop-loss", slPrice)
                end
            end
        end
        if key == "/" or key == "slash" then
            buyStopHeld = true
            stopRepeatTimer = 0.2
            createBuyStop()
        end
        if key == "z" then
            sellStopHeld = true
            stopRepeatTimer = 0.2
            createSellStop()
        end
    end
    -- Rewind keys work even when tick is paused
    if SCREEN == SCREENS.TRADING and dataMode then
        if key == "[" then
            tickPaused = true
            rewindHeld = true
            rewindRepeatTimer = 0.2 / math.max(speedMult or 1, 1)
            rewindTicks = math.min((rewindTicks or 0) + 1, 720)
        end
        if key == "]" then
            forwardHeld = true
            rewindRepeatTimer = 0.2 / math.max(speedMult or 1, 1)
            rewindTicks = math.max(0, (rewindTicks or 0) - 1)
            if rewindTicks == 0 then tickPaused = false; showDogImage = false end
        end
        if key == "\\" then
            resumeFromRewind()
        end
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

function love.keyreleased(key)
    if key == "/" or key == "slash" then buyStopHeld = false end
    if key == "z" then sellStopHeld = false end
    if key == "[" then rewindHeld = false end
    if key == "]" then forwardHeld = false end
end

-- Stop order helpers (used by keypress and long-press repeat)
function createBuyStop()
    local count = 0
    local highest = -math.huge
    for _, l in ipairs(orderLines) do
        if l.type == "buy-stop" then
            count = count + 1
            if l.price > highest then highest = l.price end
        end
    end
    if count < (tradeIterations or 1) then
        local step = currentPrice * (instrumentConfig.stopStepPct or 0.004)
        local price = highest == -math.huge and (currentAsk + step) or (highest + step)
        addOrderLine("buy-stop", math.floor(price * 1000 + 0.5) / 1000)
    end
end

function createSellStop()
    local count = 0
    local lowest = math.huge
    for _, l in ipairs(orderLines) do
        if l.type == "sell-stop" then
            count = count + 1
            if l.price < lowest then lowest = l.price end
        end
    end
    if count < (tradeIterations or 1) then
        local step = currentPrice * (instrumentConfig.stopStepPct or 0.004)
        local price = lowest == math.huge and (currentBid - step) or (lowest - step)
        addOrderLine("sell-stop", math.floor(price * 1000 + 0.5) / 1000)
    end
end

-- ── CANVAS POSITION PERSISTENCE ──
function saveCanvasPositions()
    local lines = {}
    if canvasSprites then
        for _, s in ipairs(canvasSprites) do
            if s.file then
                table.insert(lines, s.file .. ":" .. string.format("%.1f", s.x) .. ":" .. string.format("%.1f", s.y))
            end
        end
    end
    if canvasWsb and canvasWsb.file then
        table.insert(lines, canvasWsb.file .. ":" .. string.format("%.1f", canvasWsb.x) .. ":" .. string.format("%.1f", canvasWsb.y))
    end
    if #lines > 0 then
        love.filesystem.write("canvas_positions.txt", table.concat(lines, "\n"))
    end
end

function loadCanvasPositions()
    local content = love.filesystem.read("canvas_positions.txt")
    -- Fall back to bundled default if no saved positions exist
    if not content then
        content = love.filesystem.read("data/canvas_default.txt")
    end
    if not content then return end
    local saved = {}
    for line in content:gmatch("[^\r\n]+") do
        local file, sx, sy = line:match("^(.+):(.+):(.+)$")
        if file and sx and sy then
            saved[file] = { x = tonumber(sx), y = tonumber(sy) }
        end
    end
    if canvasSprites then
        for _, s in ipairs(canvasSprites) do
            if s.file and saved[s.file] then
                s.x = math.max(0, math.min(safeWidth - s.w, saved[s.file].x))
                s.y = math.max(0, math.min(safeHeight - s.h, saved[s.file].y))
            end
        end
    end
    if canvasWsb and canvasWsb.file and saved[canvasWsb.file] then
        canvasWsb.x = math.max(0, math.min(safeWidth - canvasWsb.w, saved[canvasWsb.file].x))
        canvasWsb.y = math.max(0, math.min(safeHeight - canvasWsb.h, saved[canvasWsb.file].y))
    end
    -- Recreate copies from saved positions
    for file, pos in pairs(saved) do
        local sourceFile = file:match("^_copy_%d+_(.+)$")
        if sourceFile then
            local source = nil
            for _, s in ipairs(canvasSprites) do
                if s.file == sourceFile then source = s; break end
            end
            if not source and canvasWsb and canvasWsb.file == sourceFile then
                source = canvasWsb
            end
            if source then
                local num = tonumber(file:match("^_copy_(%d+)_"))
                if num and num > canvasCopyCount then canvasCopyCount = num end
                table.insert(canvasSprites, {
                    image = source.image,
                    file = file,
                    x = math.max(0, math.min(safeWidth - source.w, pos.x)),
                    y = math.max(0, math.min(safeHeight - source.h, pos.y)),
                    scale = source.scale,
                    w = source.w,
                    h = source.h,
                })
            end
        end
    end
end

function checkReplicatorCopy(dragged)
    if not dragged or dragged.file == "replicator.png" then return end
    local replicator = nil
    if canvasSprites then
        for _, s in ipairs(canvasSprites) do
            if s.file == "replicator.png" then replicator = s; break end
        end
    end
    if not replicator then return end
    -- Check overlap (any edge overlap)
    if dragged.x + dragged.w < replicator.x or dragged.x > replicator.x + replicator.w
       or dragged.y + dragged.h < replicator.y or dragged.y > replicator.y + replicator.h then
        return
    end
    -- Create copy with offset from the replicator
    canvasCopyCount = canvasCopyCount + 1
    local copy = {
        image = dragged.image,
        file = "_copy_" .. canvasCopyCount .. "_" .. dragged.file,
        x = replicator.x + math.random(-sx(40), sx(40)),
        y = replicator.y + math.random(-sy(30), sy(30)),
        scale = dragged.scale,
        w = dragged.w,
        h = dragged.h,
    }
    table.insert(canvasSprites, copy)
end

function checkLiquidateDestroy(dragged)
    if not dragged or dragged.file == "liquidate.png" then return end
    local liquidate = nil
    if canvasSprites then
        for _, s in ipairs(canvasSprites) do
            if s.file == "liquidate.png" then liquidate = s; break end
        end
    end
    if not liquidate then return end
    -- Check overlap
    if dragged.x + dragged.w < liquidate.x or dragged.x > liquidate.x + liquidate.w
       or dragged.y + dragged.h < liquidate.y or dragged.y > liquidate.y + liquidate.h then
        return
    end
    -- Count how many sprites share this identity (keep at least one)
    local identity = dragged.file:match("^_copy_%d+_(.+)$") or dragged.file
    local count = 0
    for _, s in ipairs(canvasSprites) do
        local id = s.file:match("^_copy_%d+_(.+)$") or s.file
        if id == identity then count = count + 1 end
    end
    if count <= 1 then return end
    -- Remove dragged sprite from canvasSprites
    for i = #canvasSprites, 1, -1 do
        if canvasSprites[i] == dragged then
            table.remove(canvasSprites, i)
            break
        end
    end
end

function resetCanvasPositions()
    love.filesystem.remove("canvas_positions.txt")
    -- Remove all copy sprites
    local kept = {}
    for _, s in ipairs(canvasSprites) do
        if not s.file:match("^_copy_") then
            table.insert(kept, s)
        end
    end
    canvasSprites = kept
    -- Reset all original sprites to random positions
    math.randomseed(os.time())
    for _, s in ipairs(canvasSprites) do
        s.x = math.random(sx(40), safeWidth - s.w - sx(40))
        s.y = math.random(sy(40), safeHeight - s.h - sy(40))
    end
    -- Reset wsb
    if canvasWsb then
        canvasWsb.x = math.random(sx(40), safeWidth - canvasWsb.w - sx(40))
        canvasWsb.y = math.random(sy(40), safeHeight - canvasWsb.h - sy(40))
    end
    canvasCopyCount = 0
end

function saveCanvasDefault()
    -- Write current layout as the default for new users
    local lines = {}
    if canvasSprites then
        for _, s in ipairs(canvasSprites) do
            if s.file and not s.file:match("^_copy_") then
                table.insert(lines, s.file .. ":" .. string.format("%.1f", s.x) .. ":" .. string.format("%.1f", s.y))
            end
        end
    end
    if canvasWsb and canvasWsb.file then
        table.insert(lines, canvasWsb.file .. ":" .. string.format("%.1f", canvasWsb.x) .. ":" .. string.format("%.1f", canvasWsb.y))
    end
    if #lines > 0 then
        -- Write to source dir (dev only) so it gets bundled in .love
        local f, err = io.open("data/canvas_default.txt", "w")
        if f then
            f:write(table.concat(lines, "\n"))
            f:close()
        end
        -- Also write to save dir so it's used immediately
        love.filesystem.write("data/canvas_default.txt", table.concat(lines, "\n"))
        love.filesystem.write("canvas_positions.txt", table.concat(lines, "\n"))
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
