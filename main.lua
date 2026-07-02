-- ── MODULES ──
require("constants")
require("state")
require("audio")
require("data")
require("game")
require("chart")
require("ball")
require("snow")
require("chart_input")
require("ui")
Replay = require("replay")
local Haptics = require("haptics")
local theme = require("controls.theme")

-- ── SCREEN MANAGEMENT ──
SCREEN = "canvas"
SCREENS = {
    CANVAS = "canvas",
    INITIALS = "initials",
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
    GIMMICKS = "gimmicks",
    DEMO = "demo",
    ROTATE = "rotate",
}

-- ── LOVE CALLBACKS ──
function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("wallstreetsbeat")
    startMusic()
    initData()
    refreshFeatureVisibility()
    loadUsers()
    chartDisplay = "pct"  -- "pct" or "price" for Y-axis labels
    xerMAType = instrumentConfig.xerMA and instrumentConfig.xerMA.type or "TEMA"
    xerMAPeriod = instrumentConfig.xerMA and instrumentConfig.xerMA.period or 15
    xeeMAType = instrumentConfig.xeeMA and instrumentConfig.xeeMA.type or "EMA"
    xeeMAPeriod = instrumentConfig.xeeMA and instrumentConfig.xeeMA.period or 15
    leverage = 1          -- leverage multiplier
    playerInitials = ""   -- 3-letter initials for high scoresx
    goBackTo = nil        -- for settings BACK button
    local ok, img = pcall(love.graphics.newImage, "avatar.png")
    if ok then avatarImage = img else avatarImage = nil end
    local ok2, img2 = pcall(love.graphics.newImage, "padlock.png")
    if ok2 then padlockImage = img2 else padlockImage = nil end
    local ok3, img3 = pcall(love.graphics.newImage, "sprites/tendy.png")
    if ok3 then tendyImage = img3 else tendyImage = nil end
    local ok4, img4 = pcall(love.graphics.newImage, "sprites/pin_lock.png")
    if ok4 then pinLockImage = img4 else pinLockImage = nil end
    recalcSafeArea()
    recalcLayout()
    -- Fonts (after recalcSafeArea so sy() is valid)
    buttonFont = love.graphics.newFont("fonts/default.ttf", sy(30))
    btnActionFont = love.graphics.newFont("fonts/default.ttf", sy(58.5))
    topFont = love.graphics.newFont("fonts/RobotoMono-VariableFont_wght.ttf", sy(30))
    headerValueFont = love.graphics.newFont("fonts/default.ttf", sy(39))
    headerValueBigFont = love.graphics.newFont("fonts/default.ttf", sy(58.5))
    -- Cached fonts for per-frame use
    fonts = {
        default99  = love.graphics.newFont("fonts/default.ttf", sy(99)),
        default60  = love.graphics.newFont("fonts/default.ttf", sy(60)),
        default54  = love.graphics.newFont("fonts/default.ttf", sy(54)),
        default42  = love.graphics.newFont("fonts/default.ttf", sy(42)),
        default40  = love.graphics.newFont("fonts/default.ttf", sy(40.5)),
        default39  = love.graphics.newFont("fonts/default.ttf", sy(39)),
        default37  = love.graphics.newFont("fonts/default.ttf", sy(37.5)),
        default36  = love.graphics.newFont("fonts/default.ttf", sy(36)),
        default33  = love.graphics.newFont("fonts/default.ttf", sy(33)),
        default30  = love.graphics.newFont("fonts/default.ttf", sy(30)),
        default27  = love.graphics.newFont("fonts/default.ttf", sy(27)),
        default24  = love.graphics.newFont("fonts/default.ttf", sy(24)),
        default21  = love.graphics.newFont("fonts/default.ttf", sy(21)),
        default20  = love.graphics.newFont("fonts/default.ttf", sy(20)),
        default45  = love.graphics.newFont("fonts/default.ttf", sy(45)),
    }
    local spd = 0.3  -- default 0.3x
    speedSlider = Slider.new("speed", 0, 0, sx(150), sy(30), { 
        min = 0.3, max = 1, value = spd, step = 0,
        label = "",
        onChange = function(f)
            speedMult = 20 ^ (2 * f - 1)
            speedToastTimer = 1.5
            thrustRampActive = false
            effectiveSpeedMult = speedMult
        end
    })
    speedMult = 20 ^ (2 * spd - 1)
    local lev = instrumentConfig.defaultLeverage or 1
    levSlider = Slider.new("lev", 0, 0, sx(150), sy(30), {
        min = 1, max = 20, value = lev, step = 1,
        label = "",
        accentColor = {0.48, 0.41, 0.93},
        onChange = function(v)
            leverage = v
        end
    })
    leverage = lev
    ITER_VALUES = {1, 2, 4, 5, 10}
    local iters = instrumentConfig.defaultIterations or 10
    tradeIterations = iters
    local iterPos = 1
    for i, v in ipairs(ITER_VALUES) do
        if v == iters then iterPos = i; break end
    end
    iterSlider = Slider.new("iter", 0, 0, sx(150), sy(30), {
        min = 1, max = 5, value = iterPos, step = 1,
        label = "",
        accentColor = {0.20, 0.80, 0.60},
        onChange = function(v)
            tradeIterations = ITER_VALUES[math.floor(v)] or 1
        end
    })
    local SCOPE_VALUES = {180, 360, 720, 1440, 999999}
    local scopeLabels = {"15M", "30M", "1H", "2H", "ALL"}
    scopeTicks = SCOPE_VALUES[3]  -- default 1 hour
    scopeSlider = Slider.new("scope", 0, 0, sx(150), sy(30), {
        min = 1, max = 5, value = 3, step = 1,
        label = "",
        accentColor = {0.35, 0.60, 0.95},
        onChange = function(v)
            scopeTicks = SCOPE_VALUES[math.floor(v)] or 720
        end
    })
    buyStopHeld = false
    sellStopHeld = false
    pawsSpriteUnlocked = false
    dogSpriteUnlocked = false
    ballSpriteUnlocked = false
    tendySpriteUnlocked = false
    showQuitOverlay = false
    showSwitchOverlay = false
    switchOverlayTimer = 0  -- countdown before navigating to selector after switching
    switchPreserveIndex = nil  -- csvIndex to preserve when switching instruments
    switchPreserveDayFile = nil
    canvasPositionsLoaded = false
    manualTradeFlag = false
    algosOverlayVisible = false
    activeAlgos = {}
    buyStopHoldTime = 0
    sellStopHoldTime = 0
    stopBtnHoldTime = 0
    stopRepeatTimer = 0
    rewindHeld = false
    forwardHeld = false
    rewindRepeatTimer = 0
    rewindHoldTime = 0         -- accumulates while rewinding, for acceleration
    rewindButtonWasHeld = false
    wasRewinding = false
    prevRewindEnd = 0
    dyingTendies = {}       -- { timer, ... } shrink-to-0 animations
    rhythmHearts = {}       -- { timer, ... } rhythm reward heart fades
    delayedParticles = {}   -- { timer, price, idx, mood } delayed particle spawns
    rhythmBeatCount = 0     -- consecutive beats for tendie rhythm
    tradeSwipeOffset = 0
    tradeSwipeTarget = 0
    tradeSwipeStartX = 0
    tradeSwipeDragging = false
    rewindTendieConsumed = false
    lastTradeTapTime = 0       -- for rhythm-based tendie rewards
    lastButtonTime = 0         -- Balatro-style input cooldown
    BUTTON_COOLDOWN = 0.1      -- seconds between button presses

    -- Tendy drag state
    tendyDragActive = false
    tendyDragSlot = nil
    tendyDragX = 0
    tendyDragY = 0
    tendyDragStartX = 0
    tendyDragStartY = 0
    tendyMenuVisible = false
    tendyMenuZones = {}
    rewindUnlocked = false
    -- Rotate screen state
    rotX = 0
    rotY = 0
    rotateDragging = false
    rotateDragLastX = 0
    rotateDragLastY = 0
    rotateTendyHit = nil
    rotateLastDragTime = love.timer.getTime()  -- initialized so auto-return doesn't trigger immediately
    crossValues = {"OFF", "STOPS"}
    crossIndex = 1
    prevXERvsXEE = 0
    tendyMenuChoices = (instrumentConfig and instrumentConfig.tendyMenuChoices) or {
        { id = "rewind",  label = "REWIND" },
        { id = "bucket",  label = "BUCKET" },
        { id = "redeem",  label = "REDEEM" },
    }

    -- Heartbeat animation (synced to music BPM)
    heartBeatTimer = 0
    heartBeatScale = 1.0
    heartPulseTimer = 0   -- extra pulse on loop restart

    -- Canvas sprites: start empty, unlocked during gameplay.
    -- wsb.png is always present, centered on fresh install/reset.
    canvasSprites = {}
    canvasWsb = nil
    local okWsb, wsbImg = pcall(love.graphics.newImage, "sprites/wsb.png")
    if okWsb then
        local wiw, wih = wsbImg:getDimensions()
        canvasWsb = {
            image = wsbImg,
            file = "wsb.png",
            x = (safeWidth - wiw) / 2,
            y = (safeHeight - wih) / 2,
            scale = 1,
            w = wiw,
            h = wih,
        }
    end
    -- Load saved wsb position if exists
    loadCanvasPositions()

    Background.init()
end

function love.update(dt)
    updateMusic(dt, tickPaused)
    Replay.update(dt)
    -- Dying tendie animations (shrink to 0 over 1.5s)
    for i = #dyingTendies, 1, -1 do
        dyingTendies[i] = dyingTendies[i] - dt
        if dyingTendies[i] <= 0 then
            table.remove(dyingTendies, i)
        end
    end
    -- Rhythm reward heart fades
    for i = #rhythmHearts, 1, -1 do
        rhythmHearts[i].t = rhythmHearts[i].t - dt
        if rhythmHearts[i].t <= 0 then
            table.remove(rhythmHearts, i)
        end
    end
    if SCREEN == SCREENS.TRADING and not tickPaused and dataMode then
        tickTimer = tickTimer + dt
        local eff = (thrustRampActive and effectiveSpeedMult) or speedMult or 1
        local interval = TICK_INTERVAL / eff
        -- Cap accumulator to prevent death spiral on slower devices;
        -- ensures consistent acceleration behavior regardless of frame rate.
        -- Max ~30 ticks per frame (~2s of real time at 15 ticks/sec base).
        local maxTicks = 30
        local maxAccum = interval * maxTicks
        if tickTimer > maxAccum then
            tickTimer = maxAccum
        end
        while tickTimer >= interval do
            tickTimer = tickTimer - interval
            tick()
        end
    end
    -- Stop order repeat on long press
    if stopRepeatTimer > 0 and (buyStopHeld or sellStopHeld) then
        stopRepeatTimer = stopRepeatTimer - dt
        if stopRepeatTimer <= 0 then
            if buyStopHeld then
                buyStopHoldTime = (buyStopHoldTime or 0) + 0.2
                if buyStopHoldTime >= 0.75 then
                    removeOrderLinesByType("buy-stop")
                    buyStopHeld = false
                else
                    createBuyStop()
                end
            end
            if sellStopHeld then
                sellStopHoldTime = (sellStopHoldTime or 0) + 0.2
                if sellStopHoldTime >= 0.75 then
                    removeOrderLinesByType("sell-stop")
                    sellStopHeld = false
                else
                    createSellStop()
                end
            end
            if buyStopHeld or sellStopHeld then
                stopRepeatTimer = 0.2
            end
        end
    end
    -- Stop button hold-to-clear (mouse/touch — fires as soon as 0.5s hits)
    if pressedButtonId == "btn-buy-stop" then
        stopBtnHoldTime = (stopBtnHoldTime or 0) + dt
        if stopBtnHoldTime >= 0.75 then
            removeOrderLinesByType("buy-stop")
            stopBtnHoldTime = 0
        end
    elseif pressedButtonId == "btn-sell-stop" then
        stopBtnHoldTime = (stopBtnHoldTime or 0) + dt
        if stopBtnHoldTime >= 0.75 then
            removeOrderLinesByType("sell-stop")
            stopBtnHoldTime = 0
        end
    elseif pressedButtonId == "btn-sl" then
        stopBtnHoldTime = (stopBtnHoldTime or 0) + dt
        if stopBtnHoldTime >= 0.75 then
            removeOrderLinesByType("stop-loss")
            stopBtnHoldTime = 0
        end
    else
        stopBtnHoldTime = 0
    end
    -- Rewind repeat on long press (keyboard + on-screen button)
    if pressedButtonId == "btn-rewind" then
        -- Consume tendie immediately on first press frame (before rewind starts)
        if not rewindTendieConsumed and (tendies or 0) >= 1.0 then
            tendies = tendies - 1.0
            rewindTendieConsumed = true
        end
        rewindHeld = true
        rewindButtonWasHeld = true
        rewindHoldTime = (rewindHoldTime or 0) + dt
        if rewindRepeatTimer <= 0 then
            tickPaused = true
            rewindTicks = math.min((rewindTicks or 0) + 1, 720)
            local speedMul = rewindSpeedMul(rewindHoldTime or 0)
            rewindRepeatTimer = 0.067 / math.max(speedMult or 1, 1) / speedMul
        end
    else
        if rewindButtonWasHeld and (rewindTicks or 0) > 0 then
            resumeFromRewind()
        end
        rewindButtonWasHeld = false
        rewindHeld = false
        rewindHoldTime = 0
    end
    if rewindRepeatTimer > 0 then
        rewindRepeatTimer = rewindRepeatTimer - dt
        if rewindRepeatTimer <= 0 and (rewindHeld or forwardHeld) then
            if rewindHeld then
                tickPaused = true
                rewindTicks = math.min((rewindTicks or 0) + 1, REWIND_MAX_TICKS)
                rewindHoldTime = (rewindHoldTime or 0) + dt
                local speedMul = rewindSpeedMul(rewindHoldTime or 0)
                rewindRepeatTimer = 0.067 / math.max(speedMult or 1, 1) / speedMul
            elseif forwardHeld then
                rewindTicks = math.max(0, (rewindTicks or 0) - 1)
                if rewindTicks == 0 then tickPaused = false; showDogImage = false; pausedTimer = 0 end
                rewindRepeatTimer = 0.067 / math.max(speedMult or 1, 1)
            end
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
    -- Paused text timer (fade out only, doesn't unpause)
    if tickPaused then
        pausedTimer = (pausedTimer or 0) + dt
    else
        pausedTimer = 0
    end
    if toastTimer > 0 then
        toastTimer = toastTimer - dt
        if toastTimer <= 0 then toastMsg = nil end
    end
    if speedToastTimer > 0 then speedToastTimer = speedToastTimer - dt end
    -- Switch instrument delay: wait, then navigate to selector
    if switchOverlayTimer > 0 then
        switchOverlayTimer = switchOverlayTimer - dt
        if switchOverlayTimer <= 0 then
            canvasPositionsLoaded = false
            goToScreen(SCREENS.SELECTOR)
        end
    end
    -- Unlock notification timer
    if unlockTimer > 0 then
        unlockTimer = unlockTimer - dt
        if unlockTimer <= 0 then
            unlockMsg = nil
            -- Keep unlockSpriteImg so the achievement screen can show it persistently
        end
    end
    -- Haptic celebration pops with fireworks
    if hapticPops then
        local now = love.timer.getTime()
        for i = #hapticPops, 1, -1 do
            if hapticPops[i] <= now then
                Haptics.tap(0.03)
                spawnFireworkBurst(fireworkX, fireworkY)
                table.remove(hapticPops, i)
            end
        end
        if #hapticPops == 0 then hapticPops = nil end
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
    -- Heartbeat animation (synced to music BPM)
    if musicSource and musicSource:isPlaying() then
        -- Detect loop restart (sample position wraps to 0)
        local curSample = musicSource:tell("samples")
        if curSample < lastMusicSample then
            heartPulseTimer = 0.45  -- strong pulse on loop
        end
        lastMusicSample = curSample
        
        -- Regular beat from BPM
        local beatInterval = 60 / (musicBPM or 125)
        heartBeatTimer = heartBeatTimer + dt
        if heartBeatTimer >= beatInterval then
            heartBeatTimer = heartBeatTimer - beatInterval
            heartPulseTimer = math.max(heartPulseTimer, 0.18)  -- normal beat
        end
        
        -- Scale animation: quick attack, smooth decay
        if heartPulseTimer > 0 then
            heartPulseTimer = heartPulseTimer - dt
            -- t: 1.0 at peak → 0 as pulse fades
            local t = math.max(0, heartPulseTimer) / 0.18
            t = math.min(1, t)
            heartBeatScale = 1.0 + 0.75 * t * t  -- enlarge to 1.75x
        else
            heartBeatScale = 1.0
        end
    else
        heartBeatScale = 1.0
    end
    updateParticles(dt)
    recalcMAs()

    -- Rotate screen auto-return: after 1s idle, return X and Y to 0 proportionally
    if SCREEN == SCREENS.ROTATE then
        local idleTime = love.timer.getTime() - rotateLastDragTime
        if idleTime > 1.0 then
            local speed = 60 * dt  -- total degrees per second (shared between both axes)

            -- Helper: shortest signed distance from current to target (0)
            local function distToZero(v)
                return ((-v + 540) % 360) - 180
            end

            local dx = distToZero(rotX)
            local dy = distToZero(rotY)
            local adx = math.abs(dx)
            local ady = math.abs(dy)
            local total = adx + ady

            if total < 0.5 then
                rotX = 0
                rotY = 0
            else
                local step = math.min(total, speed)  -- total movement this frame
                local xStep = step * (adx / total)
                local yStep = step * (ady / total)
                rotX = ((rotX + (dx > 0 and xStep or -xStep)) % 360)
                rotY = ((rotY + (dy > 0 and yStep or -yStep)) % 360)
            end
        end
    end

    updateBall(dt)
    updateSnow(dt)
    updateToboggan(dt)
end

function love.draw()
    if SCREEN == SCREENS.CANVAS then
        -- Canvas screen: solid black everywhere, including letterbox bars
        love.graphics.setBackgroundColor(0, 0, 0)
        love.graphics.setColor(0, 0, 0)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    else
        -- Match clear color to background so any uncovered areas blend in
        love.graphics.setBackgroundColor(0.08, 0.08, 0.14)
        -- Draw velvet background full-screen first (fills the entire display)
        Background.draw(love.graphics.getWidth(), love.graphics.getHeight())
    end
    
    -- Transform into 1920x1080 playable area, scaled to fill screen (like Balatro)
    love.graphics.push()
    love.graphics.translate(safeLeft, safeTop)
    love.graphics.scale(safeScale, safeScale)
    
    if SCREEN == SCREENS.CANVAS then drawCanvas(safeWidth, safeHeight) end
    if SCREEN == SCREENS.INITIALS then drawInitials(safeWidth, safeHeight) end
    if SCREEN == SCREENS.SELECTOR then drawSelector(safeWidth, safeHeight) end
    if SCREEN == SCREENS.PINS then drawSpritesGallery(safeWidth, safeHeight) end
    if SCREEN == SCREENS.TRADING then
        drawTrading(safeWidth, safeHeight)
        -- Demo overlay on top of trading screen
        Replay.draw(safeWidth, safeHeight)
        -- ALGOS overlay
        if algosOverlayVisible then
            drawAlgosOverlay(safeWidth, safeHeight)
        end
        -- QUIT confirmation overlay
        if showQuitOverlay then
            drawQuitOverlay(safeWidth, safeHeight)
        end
        -- SWITCH instrument overlay
        if showSwitchOverlay then
            drawSwitchOverlay(safeWidth, safeHeight)
        end
    end
    if SCREEN == SCREENS.EOD then drawEOD(safeWidth, safeHeight) end
    if SCREEN == SCREENS.RECAP then drawRecap(safeWidth, safeHeight) end
    if SCREEN == SCREENS.ACHIEVEMENT then drawAchievement(safeWidth, safeHeight) end
    if SCREEN == SCREENS.HIGHSCORE then drawHighscore(safeWidth, safeHeight) end
    if SCREEN == SCREENS.HIGHSCORELIST then drawHighscoreList(safeWidth, safeHeight) end
    if SCREEN == SCREENS.INSTRUCTIONS then drawInstructions(safeWidth, safeHeight) end
    if SCREEN == SCREENS.SETTINGS then drawSettings(safeWidth, safeHeight) end
    if SCREEN == SCREENS.GIMMICKS then drawGimmicks(safeWidth, safeHeight) end
    if SCREEN == SCREENS.ROTATE then drawRotate(safeWidth, safeHeight) end
    if SCREEN == SCREENS.DEMO then drawDemo(safeWidth, safeHeight) end
    
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
        local msgFont = fonts.default45
        love.graphics.setFont(msgFont)
        Button.printfWithHalo(unlockMsg, safeWidth/2 - sx(300), safeHeight/2 - sy(27), sx(600), "center", r, g, b, unlockAlpha)
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
        love.graphics.rectangle("fill", safeWidth/2 - sx(300), safeHeight/2 + sy(45), sx(600), sy(60), sy(7.5))
        love.graphics.setColor(theme.color.gold)
        love.graphics.setFont(fonts.default36)
        love.graphics.printf(toastMsg, safeWidth/2 - sx(285), safeHeight/2 + sy(54), sx(570), "center")
    end

    -- Rhythm reward heart/tendy overlay
    if #rhythmHearts > 0 and heartImage and tendyImage then
        for _, item in ipairs(rhythmHearts) do
            local alpha = math.min(1, item.t / 0.5)  -- fade over 0.5s
            local isTendy = item.type == "tendy"
            local img = isTendy and tendyImage or heartImage
            local targetH = safeHeight * (isTendy and 0.14 or 0.20)
            local iw, ih = img:getDimensions()
            local scale = targetH / ih
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.draw(img, safeWidth / 2, safeHeight / 2, 0, scale, scale, iw / 2, ih / 2)
        end
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

-- Convert screen coordinates to game-area (1920x1080) coordinates
local function gx(sx) return (sx - safeLeft) / safeScale end
local function gy(sy) return (sy - safeTop) / safeScale end

-- ── SHARED INPUT HANDLERS (unifies mouse + touch) ──
local function handlePress(gx, gy, id, isTouch)
    -- Adjust for trading swipe offset so bet panel buttons hit-test correctly
    local hx = gx
    if SCREEN == SCREENS.TRADING then
        hx = gx - (tradeSwipeOffset or 0)
    end
    -- Tendy drag: check if pressing on a tendy in trading screen
    if SCREEN == SCREENS.TRADING and not tendyDragActive and (tendies or 0) >= 1.0 and tendyHitAreas then
        for _, ha in ipairs(tendyHitAreas) do
            if gx >= ha.x and gx <= ha.x + ha.w and gy >= ha.y and gy <= ha.y + ha.h then
                -- First time: unlock sprite
                if not tendySpriteUnlocked and playerInitials and playerInitials ~= "" then
                    unlockCanvasSprite("tendy.png", playerInitials)
                    tendySpriteUnlocked = true
                end
                -- Never consume on press — only on successful zone drop
                tendyDragActive = true
                tendyDragSlot = ha.idx
                tendyDragX = gx
                tendyDragY = gy
                tendyDragStartX = gx
                tendyDragStartY = gy
                tendyMenuVisible = true
                pressedButtonId = "tendy-drag"
                -- Unlock tendy sprite on first tendy drag
                if not tendySpriteUnlocked and playerInitials and playerInitials ~= "" then
                    unlockCanvasSprite("tendy.png", playerInitials)
                    tendySpriteUnlocked = true
                end
                return
            end
        end
    end
    for _, btn in pairs(Buttons) do
        if Button.hit(btn, hx, gy) then
            if love.timer.getTime() - lastButtonTime >= BUTTON_COOLDOWN then
                if btn.onClick then
                    btn.onClick()
                    Haptics.tap()
                end
                lastButtonTime = love.timer.getTime()
            end
            pressedButtonId = btn.id
            return
        end
    end
    -- Rotate screen: drag the tendy to rotate
    if SCREEN == SCREENS.ROTATE and rotateTendyHit then
        local dx = gx - rotateTendyHit.cx
        local dy = gy - rotateTendyHit.cy
        if dx * dx + dy * dy <= rotateTendyHit.radius * rotateTendyHit.radius then
            rotateDragging = true
            rotateDragLastX = gx
            rotateDragLastY = gy
            pressedButtonId = "rotate-drag"
            return
        end
    end

    if SCREEN == SCREENS.ACHIEVEMENT then
        -- no pin drag on achievement anymore
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
        -- Vertical sliders (in swipe zone, use hx)
        if (tradeSwipeOffset or 0) >= -safeWidth * 0.5 then
            if speedSlider and Slider.pressVertical(speedSlider, hx, gy) then
                thrustRampActive = false
                effectiveSpeedMult = speedMult
                return
            end
            if scopeSlider and Slider.pressVertical(scopeSlider, hx, gy) then
                return
            end
            if levSlider and Slider.pressVertical(levSlider, hx, gy) then
                return
            end
            if iterSlider and Slider.pressVertical(iterSlider, hx, gy) then
                return
            end
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
            if dxx * dxx + dyy * dyy <= (ballRadius + sy(6)) ^ 2 then
                ballDragging = true
                ballPhase = "dragging"
                return
            end
        end
    end
end

local function handleRelease(gx, gy, id, isTouch)
    rewindTendieConsumed = false
    local handledOnPress = pressedButtonId ~= nil
    pressedButtonId = nil
    if isTouch then touchId = nil end

    -- Rotate drag cleanup
    rotateDragging = false

    -- Tendy drop: check which menu zone was hit — consume tendy only on successful drop
    if tendyDragActive and tendyMenuZones then
        local droppedInZone = false
        for _, zone in ipairs(tendyMenuZones) do
            if gx >= zone.x and gx <= zone.x + zone.w and gy >= zone.y and gy <= zone.y + zone.h then
                droppedInZone = true
                tendies = math.max(0, (tendies or 1) - 1)
                if zone.id == "rewind" then
                    rewindUnlocked = true
                    toastMsg = "REWIND unlocked on chart!"
                    toastTimer = 2
                elseif zone.id == "redeem" then
                    realizedPnl = (realizedPnl or 0) + 100
                    toastMsg = "Redeemed +$100!"
                    toastTimer = 2
                elseif zone.id == "bucket" then
                    toastMsg = "BUCKET — nothing happens yet"
                    toastTimer = 2
                end
                break
            end
        end
        tendyDragActive = false
        tendyDragSlot = nil
        tendyMenuVisible = false
        tendyMenuZones = {}
        pressedButtonId = nil
        if isTouch then touchId = nil end
        return
    end
    -- Also clean up if drag was somehow left active (miss — refund tendy)
    if tendyDragActive then
        tendies = math.min(TENDY_MAX, (tendies or 0) + 1)
        tendyDragActive = false
        tendyDragSlot = nil
        tendyMenuVisible = false
        tendyMenuZones = {}
    end

    if SCREEN == SCREENS.ACHIEVEMENT then
        -- no pin release needed
    end
    if SCREEN == SCREENS.TRADING then
        avatarDragging = false
        if ballDragging then
            ballDragging = false
            -- Check if released over the dog/paws — award a tendy!
            local pawsBtn = Buttons["btn-paws"]
            if pawsBtn and ballX >= pawsBtn.x and ballX <= pawsBtn.x + pawsBtn.w
               and ballY >= pawsBtn.y and ballY <= pawsBtn.y + pawsBtn.h then
                -- First time: unlock only, don't award tendy
                if not ballSpriteUnlocked and playerInitials and playerInitials ~= "" then
                    unlockCanvasSprite("play_ball.png", playerInitials)
                    ballSpriteUnlocked = true
                    ballPhase = nil
                else
                    tendies = math.min(tendies + 1, 10)
                    ballPhase = nil
                end
            else
                ballPhase = "falling"
                ballVX = 0
                ballVY = 0
            end
        end
        Slider.release(scopeSlider)
        Slider.release(levSlider)
        Slider.release(iterSlider)
        if speedSlider then Slider.release(speedSlider) end
        if dragLine and wasOrderLineTap(gx, gy) then
            playX()
            removeOrderLine(dragLine)
        end
        endDrag()
    end
    if not handledOnPress then
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
        end
        if SCREEN == SCREENS.SELECTOR then handleSelectorClick(gx, gy) end
        if SCREEN == SCREENS.PINS then handleSpritesGalleryClick(gx, gy) end
        if SCREEN == SCREENS.TRADING then
            if algosOverlayVisible then
                handleAlgosOverlayClick(gx, gy)
            else
                handleTradingClick(gx, gy)
            end
        end
        if SCREEN == SCREENS.EOD then handleEODClick(gx, gy) end
        if SCREEN == SCREENS.RECAP then handleRecapClick(gx, gy) end
        if SCREEN == SCREENS.ACHIEVEMENT then handleAchievementClick(gx, gy) end
        if SCREEN == SCREENS.HIGHSCORE then handleHighscoreClick(gx, gy) end
        if SCREEN == SCREENS.HIGHSCORELIST then handleHighscoreListClick(gx, gy) end
        if SCREEN == SCREENS.INSTRUCTIONS then handleInstructionsClick(gx, gy) end
        if SCREEN == SCREENS.SETTINGS then handleSettingsClick(gx, gy) end
        if SCREEN == SCREENS.GIMMICKS then handleGimmicksClick(gx, gy) end
        if SCREEN == SCREENS.ROTATE then handleRotateClick(gx, gy) end
        if SCREEN == SCREENS.DEMO then handleDemoClick(gx, gy) end
    end
end

-- ── LOVE CALLBACKS ──
function love.mousepressed(x, y, b)
    if b ~= 1 then return end
    if touchId ~= nil then return end
    local gx, gy = (x - safeLeft) / safeScale, (y - safeTop) / safeScale
    handlePress(gx, gy, "mouse", false)
end

function love.mousemoved(x, y, dx, dy)
    if touchId ~= nil then return end
    if rotateDragging then
        local gx, gy = (x - safeLeft) / safeScale, (y - safeTop) / safeScale
        local ddx = gx - rotateDragLastX
        local ddy = gy - rotateDragLastY
        rotY = ((rotY or 0) - ddx * 0.5) % 360
        rotX = ((rotX or 0) + ddy * 0.5) % 360
        rotateDragLastX = gx
        rotateDragLastY = gy
        rotateLastDragTime = love.timer.getTime()
        return
    end
    if tendyDragActive then
        tendyDragX = gx(x)
        tendyDragY = gy(y)
        return
    end
    if canvasDragSprite then
        canvasDragSprite.x = gx(x) - canvasDragOffX
        canvasDragSprite.y = gy(y) - canvasDragOffY
        canvasWasDragged = true
        return
    end
    if SCREEN == SCREENS.ACHIEVEMENT then
        -- no pin drag
    end
    if SCREEN == SCREENS.TRADING then
        if scopeSlider and scopeSlider._dragging and scopeSlider._dragVertical then
            scopeSlider._tapped = false
            Slider.dragVertical(scopeSlider, gy(y))
            return
        end
        if speedSlider and speedSlider._dragging and speedSlider._dragVertical then
            speedSlider._tapped = false
            Slider.dragVertical(speedSlider, gy(y))
            return
        end
        if levSlider and levSlider._dragging and levSlider._dragVertical then
            levSlider._tapped = false
            Slider.dragVertical(levSlider, gy(y))
            return
        end
        if iterSlider and iterSlider._dragging and iterSlider._dragVertical then
            iterSlider._tapped = false
            Slider.dragVertical(iterSlider, gy(y))
            return
        end
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
    if touchId ~= nil then return end
    local gx, gy = (x - safeLeft) / safeScale, (y - safeTop) / safeScale
    handleRelease(gx, gy, "mouse", false)
end

-- ── TOUCH SUPPORT ──
touchId = nil

function love.touchpressed(id, x, y, dx, dy, pressure)
    touchId = id
    local gx, gy = (x - safeLeft) / safeScale, (y - safeTop) / safeScale
    handlePress(gx, gy, id, true)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    if rotateDragging and id == touchId then
        local gx, gy = (x - safeLeft) / safeScale, (y - safeTop) / safeScale
        local ddx = gx - rotateDragLastX
        local ddy = gy - rotateDragLastY
        rotY = ((rotY or 0) - ddx * 0.5) % 360
        rotX = ((rotX or 0) + ddy * 0.5) % 360
        rotateDragLastX = gx
        rotateDragLastY = gy
        rotateLastDragTime = love.timer.getTime()
        return
    end
    if tendyDragActive and id == touchId then
        tendyDragX = gx(x)
        tendyDragY = gy(y)
        return
    end
    if canvasDragSprite then
        canvasDragSprite.x = gx(x) - canvasDragOffX
        canvasDragSprite.y = gy(y) - canvasDragOffY
        canvasWasDragged = true
        return
    end
    if SCREEN == SCREENS.ACHIEVEMENT then
        -- no pin drag
    end
    if id == touchId and SCREEN == SCREENS.TRADING then
        if scopeSlider and scopeSlider._dragging and scopeSlider._dragVertical then
            scopeSlider._tapped = false
            Slider.dragVertical(scopeSlider, gy(y))
            return
        end
        if speedSlider and speedSlider._dragging and speedSlider._dragVertical then
            speedSlider._tapped = false
            Slider.dragVertical(speedSlider, gy(y))
            return
        end
        if levSlider and levSlider._dragging and levSlider._dragVertical then
            levSlider._tapped = false
            Slider.dragVertical(levSlider, gy(y))
            return
        end
        if iterSlider and iterSlider._dragging and iterSlider._dragVertical then
            iterSlider._tapped = false
            Slider.dragVertical(iterSlider, gy(y))
            return
        end
        if levSlider and levSlider._dragging then
            levSlider._tapped = false
            Slider.drag(levSlider, gx(x))
            return
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
        local gx, gy = (x - safeLeft) / safeScale, (y - safeTop) / safeScale
        handleRelease(gx, gy, id, true)
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
            speedSlider.value = math.max(speedSlider.min, speedSlider.value - 0.05)
            speedSlider.onChange(speedSlider.value)
        end
        if key == "right" and speedSlider then
            speedSlider.value = math.min(speedSlider.max, speedSlider.value + 0.05)
            speedSlider.onChange(speedSlider.value)
        end
        if key == "tab" then
            if position ~= 0 then createPLStop() end
        end
        if key == "/" or key == "slash" then
            buyStopHeld = true
            buyStopHoldTime = 0
            stopRepeatTimer = 0.2
            createBuyStop()
        end
        if key == "z" then
            sellStopHeld = true
            sellStopHoldTime = 0
            stopRepeatTimer = 0.2
            createSellStop()
        end
    end
    -- Rewind keys work even when tick is paused
    if SCREEN == SCREENS.TRADING and dataMode then
        if key == "[" then
            if (tendies or 0) >= 1.0 then
                tendies = tendies - 1.0
            end
            tickPaused = true
            rewindHeld = true
            rewindRepeatTimer = 0.2 / math.max(speedMult or 1, 1)
            rewindTicks = math.min((rewindTicks or 0) + 1, 720)
        end
        if key == "]" then
            forwardHeld = true
            rewindRepeatTimer = 0.2 / math.max(speedMult or 1, 1)
            rewindTicks = math.max(0, (rewindTicks or 0) - 1)
            if rewindTicks == 0 then tickPaused = false; showDogImage = false; pausedTimer = 0 end
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
            pickPresident()
            goToScreen(SCREENS.SELECTOR)
        elseif SCREEN == SCREENS.HIGHSCORE and #highscoreInitials > 0 then
            addHighScore(highscoreInitials, highscoreNewScore)
            highscoreInitials = "SAVED"
        end
    end
end

function love.keyreleased(key)
    if key == "/" or key == "slash" then buyStopHeld = false; buyStopHoldTime = 0 end
    if key == "z" then sellStopHeld = false; sellStopHoldTime = 0 end
    if key == "[" then rewindHeld = false end
    if key == "]" then forwardHeld = false end
end

-- Stop order helpers (used by keypress and long-press repeat)
function createBuyStop()
    local count = 0
    local closest = math.huge
    for i, l in ipairs(orderLines) do
        if l.type == "buy-stop" then
            count = count + 1
            if l.price < closest then closest = l.price end
        end
    end
    local step = currentPrice * (instrumentConfig.stopStepPct or DEFAULT_STOP_STEP_PCT)
    local maxSlots = tradeIterations or 1
    if count < maxSlots then
        -- Add one at the next price level above the highest existing (or at ask+step if none)
        local highest = -math.huge
        for _, l in ipairs(orderLines) do
            if l.type == "buy-stop" and l.price > highest then highest = l.price end
        end
        local price = highest == -math.huge and (currentAsk + step) or (highest + step)
        addOrderLine("buy-stop", round3(price))
    elseif closest ~= math.huge and (closest - currentAsk) >= step then
        -- Far enough: refresh ALL buy-stops at fresh prices
        removeOrderLinesByType("buy-stop")
        for i = 1, maxSlots do
            addOrderLine("buy-stop", round3(currentAsk + step * i))
        end
    end
end

function createSellStop()
    local count = 0
    local closest = -math.huge
    for i, l in ipairs(orderLines) do
        if l.type == "sell-stop" then
            count = count + 1
            if l.price > closest then closest = l.price end
        end
    end
    local step = currentPrice * (instrumentConfig.stopStepPct or DEFAULT_STOP_STEP_PCT)
    local maxSlots = tradeIterations or 1
    if count < maxSlots then
        -- Add one at the next price level below the lowest existing (or at bid-step if none)
        local lowest = math.huge
        for _, l in ipairs(orderLines) do
            if l.type == "sell-stop" and l.price < lowest then lowest = l.price end
        end
        local price = lowest == math.huge and (currentBid - step) or (lowest - step)
        addOrderLine("sell-stop", round3(price))
    elseif closest ~= -math.huge and (currentBid - closest) >= step then
        -- Far enough: refresh ALL sell-stops at fresh prices
        removeOrderLinesByType("sell-stop")
        for i = 1, maxSlots do
            addOrderLine("sell-stop", round3(currentBid - step * i))
        end
    end
end

function createPLStop()
    if position == 0 then return end
    local sp = instrumentConfig.stopStepPct or DEFAULT_STOP_STEP_PCT
    local defaultDist = currentPrice * sp
    
    -- Find existing stop-loss to determine which side of price it's on
    local existingPrice = nil
    for _, l in ipairs(orderLines) do
        if l.type == "stop-loss" then
            existingPrice = l.price
            break
        end
    end
    
    -- Remove old stop-losses
    for i = #orderLines, 1, -1 do
        if orderLines[i].type == "stop-loss" then
            table.remove(orderLines, i)
        end
    end
    
    local slPrice
    if existingPrice then
        -- Tighten toward price from whichever side the existing stop is on
        local currentDist = math.max(math.abs(currentPrice - existingPrice) * 0.5, 0.001)
        if existingPrice < currentPrice then
            -- Below price (stop-loss side): move up toward price but stay below
            slPrice = round3(currentPrice - currentDist)
        else
            -- Above price (take-profit side): move down toward price but stay above
            slPrice = round3(currentPrice + currentDist)
        end
    else
        -- First press: place on defensive side based on position
        local dist = defaultDist
        slPrice = position > 0 and round3(currentBid - dist) or round3(currentAsk + dist)
    end
    
    addOrderLine("stop-loss", slPrice)
end

-- Rewind speed acceleration: +1x/s 0-5s, +2x/s 5-10s, +3x/s 10s+, cap 30x
function rewindSpeedMul(holdTime)
    local ht = holdTime or 0
    local mul
    if ht <= 5 then mul = 1 + ht
    elseif ht <= 10 then mul = 6 + (ht - 5) * 2
    else mul = 16 + (ht - 10) * 3 end
    return math.min(30, mul)
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
        x = replicator.x + math.random(-sx(60), sx(60)),
        y = replicator.y + math.random(-sy(45), sy(45)),
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
    -- Reset all user data: removes saves and resets game state as if freshly installed
    love.filesystem.remove("users.txt")
    love.filesystem.remove("highscores.txt")
    love.filesystem.remove("canvas_positions.txt")
    users = {}
    highScores = {}
    playerInitials = ""
    position = 0
    avgPrice = 0
    pnl = 0
    realizedPnl = 0
    tendies = 1.0
    tradeCount = 0
    carryPosition = false
    orderLines = {}
    activeAlgos = {}
    currentDay = 1
    dataMode = nil
    -- Reset wsb to center
    if canvasWsb then
        canvasWsb.x = (safeWidth - canvasWsb.w) / 2
        canvasWsb.y = (safeHeight - canvasWsb.h) / 2
    end
    canvasSprites = {}
    canvasPositionsLoaded = false
    SCREEN = SCREENS.CANVAS
    toastMsg = "All data reset"
    toastTimer = 2
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
