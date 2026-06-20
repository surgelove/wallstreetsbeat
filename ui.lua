-- ── CONTROLS ──
local theme = require("controls.theme")
Button = require("controls.button")
Slider = require("controls.slider")
Background = require("controls.background")

-- Global button registry (for click dispatching)
Buttons = {}

-- ── PIN STATE ──
pinMemeImages = {}
pinSelected = nil
pinAngle = 0          -- cumulative rotation (radians), cos() gives visible scale
pinVelocity = 0       -- angular velocity for momentum
pinDragging = false
pinLastX = 0
pinTapCandidate = false  -- true if press was on pin card, cleared on drag
pinSnapTarget = nil   -- target angle for smooth snap
pinSnapSpeed = 6      -- how fast the snap lerps (rad/s)
pinCardX = 0
pinCardY = 0
pinCardW = 0
pinCardH = 0
pinHasCopyrighted = false

-- ── AVATAR DRAG STATE ──
avatarOffX = 0
avatarOffY = 0
avatarDragging = false
avatarHitX = 0
avatarHitY = 0
avatarHitW = 0
avatarHitH = 0

-- Rainbow glow helper
local function rainbowColor(offset)
    offset = offset or 0
    local h = (love.timer.getTime() * 0.5 + offset) % 1
    local r, g, b
    if h < 1/6 then
        local t = h * 6; r = 1; g = t; b = 0
    elseif h < 2/6 then
        local t = (h - 1/6) * 6; r = 1 - t; g = 1; b = 0
    elseif h < 3/6 then
        local t = (h - 2/6) * 6; r = 0; g = 1; b = t
    elseif h < 4/6 then
        local t = (h - 3/6) * 6; r = 0; g = 1 - t; b = 1
    elseif h < 5/6 then
        local t = (h - 4/6) * 6; r = t; g = 0; b = 1
    else
        local t = (h - 5/6) * 6; r = 1; g = 0; b = 1 - t
    end
    return r, g, b
end

-- Shortcut to create + register a button
-- Supports: regButton(id, x, y, w, h, text, subText, onClick|opts)
function regButton(id, x, y, w, h, text, subText, onClickOrOpts)
    local opts
    if type(onClickOrOpts) == "table" then
        opts = onClickOrOpts
    else
        opts = { onClick = onClickOrOpts }
    end
    local btn = Button.new(id, x, y, w, h, text, subText, opts)
    Buttons[id] = btn
    return btn
end

function isButtonHit(id, mx, my)
    local b = Buttons[id]
    if not b then return false end
    return Button.hit(b, mx, my)
end

function drawBtnBox(id, bgR, bgG, bgB, textR, textG, textB, borderR, borderG, borderB)
    local b = Buttons[id]
    if not b then return end
    local featureMap = {
        ["btn-sell"] = "sellButton", ["btn-buy"] = "buyButton",
        ["btn-sell-stop"] = "sellStopButton", ["btn-buy-stop"] = "buyStopButton",
        ["btn-sl"] = "stopLossButton", ["btn-flat"] = "flatButton",
        ["btn-cancel"] = "cancelButton", ["btn-endday"] = "endDayButton",
    }
    local fk = featureMap[id]
    if fk and not isFeatureUnlocked(fk) then
        b.locked = true
        b.lockThreshold = featureUnlocks[fk]
    else
        b.locked = false
        if bgR then
            b.style = "filled"
            b.bg = {bgR, bgG, bgB}
        else
            b.style = "outline"
        end
        if textR then
            b.fg = {textR, textG, textB}
        end
        if borderR then
            b.border = {borderR, borderG, borderB}
        end
    end
    Button.draw(b)
end

-- ── PRESIDENT ──
currentPresident = nil
presidentImages = {}

function loadPresidentImages()
    local presidents = instrumentConfig.presidents or {}
    for _, p in ipairs(presidents) do
        local ok, img = pcall(love.graphics.newImage, p.image)
        if ok then
            presidentImages[p.name] = img
        end
    end
end

currentEvent = ""

function pickPresident()
    -- Load saved features and settings for this user
    loadUserFeatures(playerInitials)
    if users[playerInitials] then
        local u = users[playerInitials]
        if u.chartDisplay then chartDisplay = u.chartDisplay end
        if u.defaultSpeed and speedSlider then
            speedSlider.value = u.defaultSpeed
            speedSlider.onChange(u.defaultSpeed)
        end
    end
    local presidents = instrumentConfig.presidents or {}
    if #presidents == 0 then return end
    local pick = presidents[math.random(#presidents)]
    currentPresident = pick
    
    local events = instrumentConfig.events or {}
    if #events > 0 then
        currentEvent = events[math.random(#events)]
    else
        currentEvent = ""
    end
end

function drawPresident(w, h)
    love.graphics.setBackgroundColor(0.04, 0.04, 0.06)
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("YOUR PRESIDENT IS...", 0, h * 0.08, w, "center", 0.78, 0.83, 0.88)
    
    if currentPresident then
        local img = presidentImages[currentPresident.name]
        if img then
            local iw, ih = img:getDimensions()
            local scale = math.min(150 / iw, 150 / ih)
            local dw, dh = iw * scale, ih * scale
            love.graphics.draw(img, (w - dw) / 2, h * 0.2, 0, scale, scale)
        end
        Button.printfWithHalo(currentPresident.name, 0, h * 0.2 + 170, w, "center", 0.94, 0.71, 0.16)
    end
    
    -- Breaking news
    if currentEvent ~= "" then
        Button.printfWithHalo("BREAKING NEWS", 0, h * 0.55, w, "center", 0.91, 0.25, 0.38)
        Button.printfWithHalo(currentEvent, 0, h * 0.55 + sy(50), w, "center", 0.78, 0.83, 0.88)
    end
    
    Button.printfWithHalo("TAP TO CONTINUE", 0, h * 0.8, w, "center", 0.35, 0.42, 0.48)

    -- BACK button
    Buttons = {}
    local backW, backH = sx(100), sy(36)
    local backX = w - backW - sx(20)
    local backY = h - backH - sy(14)
    regButton("pres_back", backX, backY, backW, backH, "", nil, function()
        SCREEN = SCREENS.WELCOME
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)

    love.graphics.setFont(prev)
end

-- ── SCREENS ──
function drawWelcome(w, h)
    -- Reset all game state when returning to welcome
    startingBalance = 10000
    realizedPnl = 0
    pnl = 0
    tendies = 1
    position = 0
    avgPrice = 0
    prevPosition = 0
    tradeCount = 0
    carryPosition = false
    prices = {}
    minutePrices = {}
    currentPrice = RANDOM_BASE or 32.40
    currentBid = currentPrice - 0.01
    currentAsk = currentPrice + 0.01
    prevPrice = currentPrice
    dataMode = nil
    csvData = nil
    csvIndex = 0
    rwIndex = 0
    predIndex = 0
    easyPhase = 0
    rewindTicks = 0
    stateSnapshots = {}
    currentDay = 1
    removeAllOrderLines()
    tradeMarkers = {}
    particles = {}
    milestonesHit = {}
    tickPaused = false
    speedMult = 10 ^ (-0.4)
    buyStopHeld = false
    sellStopHeld = false
    stopRepeatTimer = 0
    rewindHeld = false
    forwardHeld = false
    rewindButtonWasHeld = false
    avatarOffX = 0
    avatarOffY = 0
    -- Dark vignette behind the image so it pops against the velvet
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", 0, 0, w, h)
    if welcomeImage then
        local imgW, imgH = welcomeImage:getDimensions()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(welcomeImage, 0, 0, 0, w / imgW, h / imgH)
    end
end

function drawSelector(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CHOOSE INSTRUMENT", 0, h * 0.08, w, "center", 0.94, 0.71, 0.16)
    
    local items = { "RANDOM", "EASY" }
    local sorted = {}
    for g, _ in pairs(groups) do table.insert(sorted, g) end
    table.sort(sorted)
    for _, g in ipairs(sorted) do table.insert(items, g) end
    
    local cols = 4
    local gap = sx(10)
    local btnW = math.min(sx(140), (w - sx(100) - gap * (cols - 1)) / cols)
    local btnH = sy(50)
    local gridW = cols * btnW + (cols - 1) * gap
    local startX = (w - gridW) / 2
    local startY = h * 0.2
    
    Buttons = {}
    for i, name in ipairs(items) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local bx = startX + col * (btnW + gap)
        local by = startY + row * (btnH + gap)
        regButton("sel_" .. name, bx, by, btnW, btnH, name, nil, function() startGame(name) end)
        local isR = (name == "RANDOM")
        if isR then
            love.graphics.setColor(0.48, 0.41, 0.93)
            love.graphics.rectangle("line", bx, by, btnW, btnH, sy(5))
            Button.printfWithHalo(name, bx, by + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.48, 0.41, 0.93)
        else
            love.graphics.setColor(0.12, 0.14, 0.16)
            love.graphics.rectangle("line", bx, by, btnW, btnH, sy(5))
            Button.printfWithHalo(name, bx, by + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.78, 0.83, 0.88)
        end
    end
    
    -- PINS button — special entry below the grid, locked if no pins yet
    local lastIdx = #items
    local pinsRow = math.floor(lastIdx / cols) + 1
    local pinsBx = startX + 0 * (btnW + gap)
    local pinsBy = startY + pinsRow * (btnH + gap) + gap
    local hasPins = hasAnyPins(playerInitials)
    local pinsBtn = regButton("sel_PINS", pinsBx, pinsBy, btnW, btnH, "PINS", nil, function()
        SCREEN = SCREENS.PINS
    end)
    if not hasPins then
        pinsBtn.locked = true
    end
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.setLineWidth(math.max(1, sy(2)))
    love.graphics.rectangle("line", pinsBx, pinsBy, btnW, btnH, sy(5))
    love.graphics.setLineWidth(math.max(1, sy(1)))
    Button.printfWithHalo("PINS", pinsBx, pinsBy + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.94, 0.71, 0.16)
    
    -- HIGHSCORES button — beside PINS
    local hsBx = startX + 1 * (btnW + gap)
    local hsBy = pinsBy
    regButton("sel_HIGHSCORES", hsBx, hsBy, btnW, btnH, "SCORES", nil, function()
        loadHighScores()
        SCREEN = SCREENS.HIGHSCORELIST
    end)
    love.graphics.setColor(0, 0.78, 0.41)
    love.graphics.setLineWidth(math.max(1, sy(2)))
    love.graphics.rectangle("line", hsBx, hsBy, btnW, btnH, sy(5))
    love.graphics.setLineWidth(math.max(1, sy(1)))
    Button.printfWithHalo("SCORES", hsBx, hsBy + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0, 0.78, 0.41)
    
    -- INSTRUCTIONS button — beside SCORES
    local instrBx = startX + 2 * (btnW + gap)
    local instrBy = pinsBy
    regButton("sel_INSTRUCTIONS", instrBx, instrBy, btnW, btnH, "HELP", nil, function()
        SCREEN = SCREENS.INSTRUCTIONS
    end)
    love.graphics.setColor(0.35, 0.42, 0.80)
    love.graphics.setLineWidth(math.max(1, sy(2)))
    love.graphics.rectangle("line", instrBx, instrBy, btnW, btnH, sy(5))
    love.graphics.setLineWidth(math.max(1, sy(1)))
    Button.printfWithHalo("HELP", instrBx, instrBy + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.35, 0.42, 0.80)
    
    -- BACK button (bottom-right)
    local backW, backH = sx(100), sy(36)
    local backX = w - backW - sx(20)
    local backY = h - backH - sy(14)
    regButton("sel_back", backX, backY, backW, backH, "", nil, function()
        SCREEN = SCREENS.WELCOME
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)
    
    -- SETTINGS button (bottom-left)
    local setW, setH = sx(140), sy(36)
    local setX = sx(20)
    local setY = backY
    regButton("sel_SETTINGS", setX, setY, setW, setH, "", nil, function()
        goBackTo = SCREEN
        SCREEN = SCREENS.SETTINGS
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", setX, setY, setW, setH, sy(5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("SETTINGS", setX, setY + (setH - btnActionFont:getHeight()) / 2, setW, "center", 0.35, 0.42, 0.48)

    love.graphics.setFont(prev)
end



function drawTrading(w, h)
    Buttons = {}
    local topH = TOPBAR_H
    local botH = BOTBAR_H
    local prevFont = love.graphics.getFont()
    
    -- Top bar pill
    love.graphics.setColor(0.07, 0.08, 0.09)
    love.graphics.rectangle("fill", 0, sy(6), w, topH - sy(6), PILL_R)
    love.graphics.setColor(0.78, 0.83, 0.88, 0.25)
    love.graphics.setLineWidth(math.max(1, sy(1)))
    love.graphics.rectangle("line", 0, sy(6), w, topH - sy(6), PILL_R)
    
    -- Top bar uses Monaco
    if topFont then love.graphics.setFont(topFont) end
    
    -- Instrument name (clickable to restart) — gold
    local instNameW = 170
    regButton("btn-instrument", PILL_R + sx(14), 5, instNameW, topH, "", nil, function()
        currentDay = 1
        SCREEN = SCREENS.SELECTOR
        position = 0; avgPrice = 0; realizedPnl = 0; pnl = 0; tradeCount = 0; tendies = 1
        prices = {}; orderLines = {}; tradeMarkers = {}; particles = {}
        removeAllOrderLines()
    end)
    local cy = sy(6) + (topH - sy(6)) / 2 - 3
    
    if btnActionFont then
        love.graphics.setFont(btnActionFont)
        local bfh = btnActionFont:getHeight()
        local text = instrumentText or "RANDOM"
        Button.printfWithHalo(text, PILL_R + sx(14), cy - bfh / 2, instNameW, "left", 0.94, 0.71, 0.16)
        love.graphics.setFont(topFont)
    end
    
    midStart = PILL_R + sx(14) + instNameW + sx(20)
    
    -- Avatar square at top-right (draggable)
    local avSize = sy(42)
    local avX = w - PILL_R - avSize - sy(6) + avatarOffX
    local avY = sy(6) + (topH - sy(6) - avSize) / 2 + avatarOffY
    -- Store hit area for drag detection
    avatarHitX = avX
    avatarHitY = avY
    avatarHitW = avSize
    avatarHitH = avSize
    if avatarImage then
        love.graphics.stencil(function()
            love.graphics.rectangle("fill", avX, avY, avSize, avSize, PILL_R)
        end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(avatarImage, avX, avY, 0, avSize / avatarImage:getWidth(), avSize / avatarImage:getHeight())
        love.graphics.setStencilTest()
    else
        love.graphics.setColor(0.20, 0.22, 0.28)
        love.graphics.rectangle("fill", avX, avY, avSize, avSize, PILL_R)
    end
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.setLineWidth(math.max(1, sy(1.5)))
    love.graphics.rectangle("line", avX, avY, avSize, avSize, PILL_R)
    love.graphics.setLineWidth(math.max(1, sy(1)))
    
    -- Middle space: between instrument name end and avatar start
    
    -- Calculate tendies dimensions to push P&L left and make room on right
    local tendiesWidth = 0
    if tendyImage then
        local tendyH = sy(44)
        local tw, th = tendyImage:getDimensions()
        local tendyScale = tendyH / th
        local tendyW = tw * tendyScale
        local overlapPct = 0.65
        local tendyStep = tendyW * (1 - overlapPct)
        tendiesWidth = tendyW + 9 * tendyStep
    end
    
    local midEnd = avX - sx(20)
    if tendyImage then
        midEnd = midEnd - tendiesWidth - sx(8)
    end
    local midW = midEnd - midStart
    local colW = midW / 2  -- ASK/BID | P&L
    
    -- ASK/BID labels and numbers — top-aligned inside the pill
    local sFh = sy(24)
    local sFont = love.graphics.newFont("fonts/default.ttf", sFh)
    local ax = midStart
    local pillTopY = sy(6)
    local labelY = pillTopY + sy(3)
    local numberY = labelY + sFh + sy(1)
    
    love.graphics.setFont(sFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    love.graphics.print("AKS", ax + sx(14), labelY)
    love.graphics.setFont(headerValueBigFont)
    love.graphics.setColor(0.95, 0.15, 0.25)
    love.graphics.printf(string.format("%.2f", currentAsk), ax + sx(14), numberY, colW / 2 - sx(14) - sx(10), "left")
    
    love.graphics.setFont(sFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    love.graphics.print("DIB", ax + colW / 2 + sx(14), labelY)
    love.graphics.setFont(headerValueBigFont)
    love.graphics.setColor(0, 0.78, 0.41)
    love.graphics.printf(string.format("%.2f", currentBid), ax + colW / 2 + sx(14), numberY, colW / 2 - sx(14) - sx(10), "left")
    
    -- P&L section
    local total = startingBalance + pnl + realizedPnl
    local ux = midStart + colW
    local smallFh = sy(24)
    local smallFont = love.graphics.newFont("fonts/default.ttf", smallFh)
    local pnlColW = colW / 3
    
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    love.graphics.print("UNREGARDED", ux + sx(14), labelY)
    love.graphics.setFont(headerValueBigFont)
    if pnl == 0 then love.graphics.setColor(0.55, 0.55, 0.60) else love.graphics.setColor(pnl > 0 and 0 or 0.91, pnl > 0 and 0.78 or 0.25, 0.41) end
    love.graphics.printf(fmtPnl(pnl), ux + sx(14), numberY, pnlColW - sx(14), "left")
    
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    love.graphics.print("REGARDED", ux + pnlColW + sx(14), labelY)
    love.graphics.setFont(headerValueBigFont)
    if realizedPnl == 0 then love.graphics.setColor(0.55, 0.55, 0.60) else love.graphics.setColor(realizedPnl > 0 and 0 or 0.91, realizedPnl > 0 and 0.78 or 0.25, 0.41) end
    love.graphics.printf(fmtPnl(realizedPnl), ux + pnlColW + sx(14), numberY, pnlColW - sx(14), "left")
    
    love.graphics.setFont(headerValueBigFont)
    love.graphics.setColor((total - startingBalance) >= 0 and 0 or 0.91, (total - startingBalance) >= 0 and 0.78 or 0.25, 0.41)
    love.graphics.printf("$" .. fmtMoney(total), ux + pnlColW * 2 + sx(14), cy - headerValueBigFont:getHeight() / 2 + 2, pnlColW - sx(14), "left")
    
    -- TENDIES display on the right side, just before avatar
    if tendyImage then
        local tendyH = sy(44)
        local tw, th = tendyImage:getDimensions()
        local tendyScale = tendyH / th
        local tendyW = tw * tendyScale
        local overlapPct = 0.65
        local tendyStep = tendyW * (1 - overlapPct)
        local rightAnchor = avX - sx(20) - tendyW + sx(2)
        local tendiesX = rightAnchor - (tendies - 1) * tendyStep
        local tendiesY = sy(6) + (topH - sy(6) - tendyH) / 2
        for i = 0, tendies - 1 do
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(tendyImage, tendiesX + i * tendyStep, tendiesY, 0, tendyScale, tendyScale)
        end
        -- Dying tendies (shrink-to-0 animation over 1.5s)
        if dyingTendies and #dyingTendies > 0 then
            local animDuration = 1.5
            for di = 1, #dyingTendies do
                local timer = dyingTendies[di]
                local progress = math.max(0, timer / animDuration)  -- 1 → 0
                local dScale = tendyScale * progress
                local dW = tw * dScale
                local dH = th * dScale
                local dX = rightAnchor - (tendies + #dyingTendies - di) * tendyStep + (tendyW - dW) / 2
                local dY = tendiesY + (tendyH - dH) / 2
                love.graphics.setColor(1, 1, 1, progress)
                love.graphics.draw(tendyImage, dX, dY, 0, dScale, dScale)
            end
        end
    end
    
    love.graphics.setFont(prevFont)
    
    -- Chart
    drawChart()
    
    -- Rewind button (top-left of chart, visible when losing and have tendies, or actively rewinding)
    if dataMode and (tendies or 0) > 0 and (pnl < 0 or (rewindTicks or 0) > 0) and (rewindTicks or 0) < 720 then
        local rwW, rwH = sx(220), sy(84)
        local rwX = chartX + sx(8)
        local rwY = chartY + sy(8)
        regButton("btn-rewind", rwX, rwY, rwW, rwH, "REWIND\n1 TENDIE", nil, function() end)
        love.graphics.setColor(0.91, 0.25, 0.38, 0.85)
        love.graphics.rectangle("fill", rwX, rwY, rwW, rwH, sy(8))
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle("line", rwX, rwY, rwW, rwH, sy(8))
        if btnActionFont then love.graphics.setFont(btnActionFont) end
        local fh = btnActionFont:getHeight()
        Button.printfWithHalo("REWIND\n1 TENDIE", rwX, rwY + (rwH - fh * 2) / 2, rwW, "center", 1, 1, 1)
    end
    
    -- No panel backgrounds — velvet shows through behind buttons
    
    -- Side panel buttons: align top and bottom with chart area
    local padX, gap = sx(8), sy(8)
    local chartTop = TOPBAR_H + sy(8)
    local chartBot = h - BOTBAR_H - sy(6) - sy(8)
    local chartH = chartBot - chartTop
    local panelY = chartTop
    local btnH = math.floor((chartH - gap * 4) / 4.5)
    local halfH = math.floor(btnH / 2)
    
    -- Left panel
    local lx = padX
    regButton("btn-sell", lx, panelY, PANEL_W - padX * 2, btnH, "SELL", "Market", sell)
    drawBtnBox("btn-sell", 0.72, 0.19, 0.30, 0.45, 0.05, 0.05)
    regButton("btn-sell-stop", lx, panelY + (btnH + gap), PANEL_W - padX * 2, btnH, "SELL STOP", nil, function()
        local count = 0
        local lowest = math.huge
        for _, l in ipairs(orderLines) do
            if l.type == "sell-stop" then
                count = count + 1
                if l.price < lowest then lowest = l.price end
            end
        end
        if count >= (tradeIterations or 1) then return end
        local step = currentPrice * (instrumentConfig.stopStepPct or 0.004)
        local price = lowest == math.huge and (currentBid - step) or (lowest - step)
        addOrderLine("sell-stop", math.floor(price * 1000 + 0.5) / 1000)
    end)
    drawBtnBox("btn-sell-stop", 0.15, 0.15, 0.20, 0.72, 0.19, 0.30, 0.72, 0.19, 0.30)
    regButton("btn-sl", lx, panelY + (btnH + gap) * 2, PANEL_W - padX * 2, btnH, "PL STOP", nil, function()
        if position == 0 then return end
        for _, l in ipairs(orderLines) do
            if l.type == "stop-loss" then return end
        end
        local sp = instrumentConfig.stopStepPct or 0.004
        local slPrice = position > 0 and math.floor((currentBid - currentPrice * sp * 2) * 1000 + 0.5) / 1000 or math.floor((currentAsk + currentPrice * sp * 2) * 1000 + 0.5) / 1000
        addOrderLine("stop-loss", slPrice)
    end)
    drawBtnBox("btn-sl", 0.15, 0.15, 0.20, 0.78, 0.60, 0.13, 0.78, 0.60, 0.13)
    regButton("btn-cancel", lx, panelY + (btnH + gap) * 3, PANEL_W - padX * 2, btnH, "CANCEL STOPS", nil, removeAllOrderLines)
    drawBtnBox("btn-cancel", 0.15, 0.15, 0.20, 0.35, 0.42, 0.48, 0.35, 0.42, 0.48)
    local halfH = math.floor(btnH / 2)
    local bottomY = panelY + (btnH + gap) * 4  -- align bottom of half button with chart bottom
    regButton("btn-settings", lx, bottomY, PANEL_W - padX * 2, halfH, "SETTINGS", nil, function()
        goBackTo = SCREEN
        SCREEN = SCREENS.SETTINGS
    end)
    drawBtnBox("btn-settings", 0.15, 0.15, 0.20, 0.60, 0.60, 0.65, 0.60, 0.60, 0.65)

    -- Right panel
    local rx = w - PANEL_W + padX
    regButton("btn-buy", rx, panelY, PANEL_W - padX * 2, btnH, "BUY", "Market", buy)
    drawBtnBox("btn-buy", 0, 0.78, 0.41, 0.05, 0.40, 0.15)
    regButton("btn-buy-stop", rx, panelY + (btnH + gap), PANEL_W - padX * 2, btnH, "BUY STOP", nil, function()
        local count = 0
        local highest = -math.huge
        for _, l in ipairs(orderLines) do
            if l.type == "buy-stop" then
                count = count + 1
                if l.price > highest then highest = l.price end
            end
        end
        if count >= (tradeIterations or 1) then return end
        local step = currentPrice * (instrumentConfig.stopStepPct or 0.004)
        local price = highest == -math.huge and (currentAsk + step) or (highest + step)
        addOrderLine("buy-stop", math.floor(price * 1000 + 0.5) / 1000)
    end)
    drawBtnBox("btn-buy-stop", 0.15, 0.15, 0.20, 0, 0.78, 0.41, 0, 0.78, 0.41)
    regButton("btn-flat", rx, panelY + (btnH + gap) * 2, PANEL_W - padX * 2, btnH, "CLOSE POSTN", nil, closePosition)
    drawBtnBox("btn-flat", 0.15, 0.15, 0.20, 0.50, 0.50, 0.52, 0.69, 0.69, 0.69)
    regButton("btn-endday", rx, panelY + (btnH + gap) * 3, PANEL_W - padX * 2, btnH, "END DAY", nil, skipTo1555)
    drawBtnBox("btn-endday", 0.15, 0.15, 0.20, 0.78, 0.50, 0.60, 0.78, 0.50, 0.60)
    regButton("btn-quit", rx, bottomY, PANEL_W - padX * 2, halfH, "QUIT", nil, function()
        SCREEN = SCREENS.WELCOME
    end)
    drawBtnBox("btn-quit", 0.15, 0.15, 0.20, 0.91, 0.25, 0.38, 0.91, 0.25, 0.38)
    
    -- Bottom bar pill
    love.graphics.setColor(0.07, 0.08, 0.09)
    love.graphics.rectangle("fill", 0, h - botH - sy(6), w, botH, PILL_R)
    love.graphics.setColor(0.78, 0.83, 0.88, 0.25)
    love.graphics.setLineWidth(math.max(1, sy(1)))
    love.graphics.rectangle("line", 0, h - botH - sy(6), w, botH, PILL_R)
    
    -- Position label (left)
    local posW = sx(120)
    local posX = APP_PAD + sx(14)
    local posLabel = position == 0 and "FLAT" or (position > 0 and ("LONG " .. math.abs(position)) or ("SHORT " .. math.abs(position)))
    local posR, posG, posB = position == 0 and 0.35 or (position > 0 and 0 or 0.91),
                              position == 0 and 0.42 or (position > 0 and 0.78 or 0.25),
                              position == 0 and 0.48 or (position > 0 and 0.41 or 0.38)
    local bfh = btnActionFont and btnActionFont:getHeight() or sy(20)
    if btnActionFont then
        local prev = love.graphics.getFont()
        love.graphics.setFont(btnActionFont)
        Button.printfWithHalo(posLabel, posX, (h - botH - sy(6)) + (botH - bfh) / 2 - 1, posW, "left", posR, posG, posB)
        love.graphics.setFont(prev)
    else
        love.graphics.setColor(posR, posG, posB)
        love.graphics.print(posLabel, posX, h - botH + 6)
    end
    
    -- Day display (right) — wider to fit "Wednesday", right-aligned
    local dayW = sx(150)
    if currentDay and weekDays then
        local dayStr = weekDays[currentDay] or ""
        if dayStr ~= "" and btnActionFont then
            local prev = love.graphics.getFont()
            love.graphics.setFont(btnActionFont)
            local dayX = w - PILL_R
            Button.printfWithHalo(dayStr, dayX - dayW, (h - botH - sy(6)) + (botH - bfh) / 2 - 1, dayW, "right", 0.30, 0.60, 0.95)
            love.graphics.setFont(prev)
        end
    end
    
    -- Middle space: SPD, LEV, ITER, AVG evenly spaced
    local fMidStart = posX + posW + sx(10)
    local fMidEnd = w - PILL_R - dayW - sx(10)
    local fMidW = fMidEnd - fMidStart
    local nCols = 4
    local colW = fMidW / nCols
    
    local bCy = (h - botH - sy(6)) + botH / 2 - 3
    local bSmallFh = sy(24)
    local bSmallFont = love.graphics.newFont("fonts/default.ttf", bSmallFh)
    local bPillTopY = h - botH - sy(6)
    local bLabelY = bPillTopY + sy(3)
    local bNumberY = bLabelY + bSmallFh + sy(1)
    
    local labelW = sx(18)
    local valueW = sx(64)
    
    -- SPD slider
    local spdX = fMidStart + 0 * colW
    if speedSlider then
        love.graphics.setFont(bSmallFont)
        love.graphics.setColor(0.90, 0.90, 0.93)
        love.graphics.print("SP\195\174\195\174D", spdX + labelW, bLabelY)
        local trackW = colW - labelW - valueW - sx(8)
        speedSlider.x = spdX + labelW
        speedSlider.y = bCy - speedSlider.h / 2
        speedSlider.w = trackW
        speedSlider.h = sy(20)
        Slider.draw(speedSlider)
        local spd = speedMult or 1
        love.graphics.setColor(0.94, 0.71, 0.16)
        love.graphics.setFont(headerValueBigFont)
        local valX = speedSlider.x + speedSlider.w + sx(8)
        love.graphics.printf(string.format("%.1fx", spd), valX, bNumberY, valueW, "left")
    end
    
    -- LEV slider
    local levX = fMidStart + 1 * colW
    love.graphics.setFont(bSmallFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    love.graphics.print("LEVIED RAGE", levX + labelW, bLabelY)
    local trackW = colW - labelW - valueW - sx(8)
    if levSlider then
        levSlider.x = levX + labelW
        levSlider.y = bCy - levSlider.h / 2
        levSlider.w = trackW
        Slider.draw(levSlider)
    end
    -- Value
    love.graphics.setColor(0.48, 0.41, 0.93)
    love.graphics.setFont(headerValueBigFont)
    love.graphics.printf((leverage or 1) .. "x", levX + labelW + trackW + sx(8), bNumberY, valueW, "left")
    
    -- ITER slider (split trades into iterations)
    local iterX = fMidStart + 2 * colW
    love.graphics.setFont(bSmallFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    love.graphics.print("CHOP", iterX + labelW, bLabelY)
    local trackW2 = colW - labelW - valueW - sx(8)
    if iterSlider then
        iterSlider.x = iterX + labelW
        iterSlider.y = bCy - iterSlider.h / 2
        iterSlider.w = trackW2
        Slider.draw(iterSlider)
    end
    love.graphics.setColor(0.20, 0.80, 0.60)
    love.graphics.setFont(headerValueBigFont)
    love.graphics.printf((tradeIterations or 1) .. "x", iterX + labelW + trackW2 + sx(8), bNumberY, valueW, "left")
    
    -- AVG info column
    local function drawInfoCol(label, val, colIdx, cr, cg, cb)
        local cx = fMidStart + (colIdx + 0.5) * colW
        love.graphics.setFont(bSmallFont)
        love.graphics.setColor(cr, cg, cb)
        love.graphics.print(label, cx - colW / 2 + sx(14), bLabelY)
        love.graphics.setFont(headerValueBigFont)
        love.graphics.setColor(cr, cg, cb)
        local valStr = tostring(val)
        love.graphics.printf(valStr, cx - colW / 2 + sx(14), bNumberY, colW - sx(14), "left")
    end
    drawInfoCol("HAVE'R'EDGE", avgPrice and string.format("%.2f", avgPrice) or "—", 3, 0.78, 0.83, 0.88)
    
    love.graphics.setFont(prevFont)
end

function drawEOD(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    local prev = love.graphics.getFont()
    
    local posDir = position > 0 and "LONG" or "SHORT"
    local text = string.format("Open position: %s %d @ %.2f\n\nClose at market or carry to next day?",
                               posDir, math.abs(position), avgPrice or 0)
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    love.graphics.setColor(0.78, 0.83, 0.88)
    love.graphics.printf(text, 50, h * 0.3, w - 100, "center")
    
    -- CLOSE button
    regButton("eod-close", w * 0.35 - 60, h * 0.5, 120, 40, "CLOSE", nil, function()
        closeAllPositions("MARKET CLOSED")
        SCREEN = SCREENS.RECAP
    end)
    love.graphics.setColor(0.72, 0.19, 0.30)
    love.graphics.rectangle("fill", w * 0.35 - 60, h * 0.5, 120, 40, 3)
    Button.printfWithHalo("CLOSE", w * 0.35 - 60, h * 0.5 + (40 - btnActionFont:getHeight()) / 2, 120, "center", 0, 0, 0)
    
    -- KEEP button
    regButton("eod-keep", w * 0.65 - 60, h * 0.5, 120, 40, "KEEP", nil, function()
        carryPosition = true
        SCREEN = SCREENS.RECAP
    end)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.rectangle("line", w * 0.65 - 60, h * 0.5, 120, 40, 3)
    Button.printfWithHalo("KEEP", w * 0.65 - 60, h * 0.5 + (40 - btnActionFont:getHeight()) / 2, 120, "center", 0.94, 0.71, 0.16)
    
    love.graphics.setFont(prev)
end

function drawRecap(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    local prev = love.graphics.getFont()
    
    local total = startingBalance + realizedPnl
    local dayPnl = realizedPnl
    local sign = dayPnl >= 0 and "+" or "-"
    
    -- Heading
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo((weekDays[currentDay] or "DAY") .. " COMPLETE!", 0, h * 0.08, w, "center", 0.94, 0.71, 0.16)
    
    -- Financial summary
    local text = string.format("Starting Balance\n$%s\n\nDay P&L\n%s$%s\n\nFinal Balance\n$%s",
                               fmtMoney(startingBalance), sign, fmtPnl(dayPnl), fmtMoney(total))
    love.graphics.setColor(0.78, 0.83, 0.88)
    local bodyFont = love.graphics.newFont("fonts/default.ttf", sy(27))
    love.graphics.setFont(bodyFont)
    love.graphics.printf(text, w * 0.3, h * 0.15, w * 0.4, "center")
    
    -- Buttons centered, styled like selector screen
    local btnW = sx(280)
    local btnH = sy(60)
    local btnGap = sy(15)
    local btnX = w / 2 - btnW / 2
    local btnY = h * 0.55
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    
    -- CONTINUE button
    regButton("recap-continue", btnX, btnY, btnW, btnH, "CONTINUE", nil, continueTrading)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, sy(5))
    love.graphics.setLineWidth(math.max(1, sy(2)))
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, sy(5))
    love.graphics.setLineWidth(math.max(1, sy(1)))
    Button.printfWithHalo("CONTINUE", btnX, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.94, 0.71, 0.16)
    
    -- START OVER button
    regButton("recap-restart", btnX, btnY + btnH + btnGap, btnW, btnH, "START OVER", nil, function()
        love.event.quit("restart")
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.setLineWidth(math.max(1, sy(2)))
    love.graphics.rectangle("line", btnX, btnY + btnH + btnGap, btnW, btnH, sy(5))
    love.graphics.setLineWidth(math.max(1, sy(1)))
    Button.printfWithHalo("START OVER", btnX, btnY + btnH + btnGap + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.35, 0.42, 0.48)
    
    love.graphics.setFont(prev)
end

-- ── CLICK HANDLERS ──
function handleSelectorClick(mx, my)
    for id, b in pairs(Buttons) do
        if id:find("^sel_") and Button.hit(b, mx, my) then
            if b.locked then return end
            if b.onClick then b.onClick() end
            return
        end
    end
end

function handleTradingClick(mx, my)
    for id, b in pairs(Buttons) do
        if id:find("^btn%-") and Button.hit(b, mx, my) then
            if b.locked then
                local thresh = b.lockThreshold or "?"
                toastMsg = "Need $" .. tostring(thresh) .. " total P&L to unlock"
                toastTimer = 2
                return
            end
            if b.onClick then b.onClick() end
            return
        end
    end
end

function handleEODClick(mx, my)
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
            b.onClick()
            return
        end
    end
end

function handleRecapClick(mx, my)
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
            b.onClick()
            return
        end
    end
end

-- ── ACHIEVEMENT SCREEN ──
-- Globals set by continueTrading: achievementNextScreen, achievementCarryMode, achievementSavedMode, achievementSavedGroup

function drawAchievement(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    Buttons = {}
    local prev = love.graphics.getFont()
    
    -- Load pin meme if needed
    if not next(pinMemeImages) then loadPinMemes() end
    
    -- Title
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("PIN UNLOCKED!", 0, h * 0.06, w, "center", 0.94, 0.71, 0.16)
    
    -- Subtitle
    love.graphics.setColor(0.60, 0.60, 0.65)
    local bodyFont = love.graphics.newFont("fonts/default.ttf", sy(24))
    love.graphics.setFont(bodyFont)
    love.graphics.printf("SURVIVED A TRADING DAY", 0, h * 0.16, w, "center")
    
    -- Spinnable pin card
    if pinAwarded and pinMemeImages[pinAwarded] then
        local data = pinMemeImages[pinAwarded]
        local availH = h * 0.45
        local availW = w * 0.35
        local iw, ih = data.img:getDimensions()
        local aspect = iw / ih
        local cardW, cardH
        if availW / availH > aspect then
            cardH = availH
            cardW = cardH * aspect
        else
            cardW = availW
            cardH = cardW / aspect
        end
        
        local cardCX = w / 2
        local cardCY = h * 0.46
        
        -- Store for drag hit testing
        pinSelected = pinAwarded
        pinCardX = cardCX
        pinCardY = cardCY
        pinCardW = cardW
        pinCardH = cardH
        
        drawPinCard(data.img, cardCX, cardCY, cardW, cardH, pinAngle, data.label)
        
        -- Drag hint
        love.graphics.setColor(0.35, 0.42, 0.48)
        if btnActionFont then love.graphics.setFont(btnActionFont) end
        Button.printfWithHalo("DRAG TO SPIN", 0, cardCY + cardH / 2 + sy(8), w, "center", 0.35, 0.42, 0.48)
    end
    
    -- CONTINUE button
    local btnW, btnH = sx(220), sy(50)
    local btnX = w / 2 - btnW / 2
    local btnY = h * 0.78
    regButton("ach_continue", btnX, btnY, btnW, btnH, "CONTINUE", nil, function()
        pinSelected = nil
        pinAngle = 0
        pinVelocity = 0
        pinDragging = false
        pinSnapTarget = nil
        if achievementCarryMode then
            if achievementSavedMode == "random" then
                startGame("RANDOM")
            elseif achievementSavedMode == "predictable" then
                startGame("EASY")
            elseif achievementSavedGroup and achievementSavedGroup ~= "" then
                startGame(achievementSavedGroup)
            else
                SCREEN = SCREENS.SELECTOR
            end
        else
            SCREEN = SCREENS.SELECTOR
        end
    end)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, sy(5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CONTINUE", btnX, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.94, 0.71, 0.16)
    
    love.graphics.setFont(prev)
end

function handleAchievementClick(mx, my)
    -- Let pin drag work (reuse tryPinPress from PINS)
    if tryPinPress(mx, my) then return end
    for id, b in pairs(Buttons) do
        if id:find("^ach_") and Button.hit(b, mx, my) and b.onClick then
            b.onClick()
            return
        end
    end
end

-- ── HIGH SCORE SCREEN ──
function drawHighscore(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    Buttons = {}
    local prev = love.graphics.getFont()
    
    -- Auto-save with player initials
    if highscoreInitials ~= "SAVED" then
        local initials = playerInitials ~= "" and playerInitials or "???"
        addHighScore(initials, highscoreNewScore)
        highscoreInitials = "SAVED"
    end
    
    -- Heading
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("WEEK COMPLETE!", 0, h * 0.04, w, "center", 0.94, 0.71, 0.16)
    
    local colW = w / 2
    
    -- ── LEFT COLUMN: Your result ──
    local lx = 0
    local ly = h * 0.12
    love.graphics.setColor(0.60, 0.60, 0.65)
    local labelFont = love.graphics.newFont("fonts/default.ttf", sy(22))
    love.graphics.setFont(labelFont)
    love.graphics.printf("YOUR RESULT", lx, ly, colW, "center")
    ly = ly + sy(32)
    
    local total = highscoreNewScore
    local weekPnl = total - 10000
    local sign = weekPnl >= 0 and "+" or "-"
    local bodyFont = love.graphics.newFont("fonts/default.ttf", sy(40))
    love.graphics.setFont(bodyFont)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.printf("$" .. fmtMoney(total), lx, ly, colW, "center")
    ly = ly + sy(48)
    
    local pnlFont = love.graphics.newFont("fonts/default.ttf", sy(28))
    love.graphics.setFont(pnlFont)
    love.graphics.setColor(weekPnl >= 0 and 0 or 0.91, weekPnl >= 0 and 0.78 or 0.25, 0.41)
    love.graphics.printf(sign .. "$" .. fmtPnl(weekPnl) .. " P&L", lx, ly, colW, "center")
    ly = ly + sy(36)
    
    local gamesFont = love.graphics.newFont("fonts/default.ttf", sy(22))
    love.graphics.setFont(gamesFont)
    local u = users[playerInitials]
    love.graphics.setColor(0.50, 0.55, 0.60)
    if u then
        love.graphics.printf(u.games .. " game" .. (u.games ~= 1 and "s" or "") .. " played", lx, ly, colW, "center")
        ly = ly + sy(26)
        love.graphics.printf("Best: $" .. fmtMoney(u.high), lx, ly, colW, "center")
        ly = ly + sy(26)
        love.graphics.printf(#(u.pins or {}) .. " pins collected", lx, ly, colW, "center")
    end
    
    if isNewHighScore(highscoreNewScore) then
        ly = ly + sy(36)
        love.graphics.setColor(0.94, 0.71, 0.16)
        if btnActionFont then love.graphics.setFont(btnActionFont) end
        love.graphics.printf("NEW HIGH SCORE!", lx, ly, colW, "center")
    end
    
    -- ── RIGHT COLUMN: Top 10 ──
    local rx = colW
    local ry = h * 0.12
    love.graphics.setColor(0.60, 0.60, 0.65)
    love.graphics.setFont(labelFont)
    love.graphics.printf("TOP 10", rx, ry, colW, "center")
    ry = ry + sy(32)
    
    local scoreFont = love.graphics.newFont("fonts/default.ttf", sy(24))
    love.graphics.setFont(scoreFont)
    local shown = math.min(#highScores, 10)
    for i = 1, shown do
        local entry = highScores[i]
        local line = string.format("%2d. %3s  $%s", i, entry.initials, fmtMoney(entry.score))
        if entry.initials == playerInitials then
            love.graphics.setColor(0.94, 0.71, 0.16)
        elseif i == 1 then
            love.graphics.setColor(0.94, 0.71, 0.16)
        elseif i == 2 then
            love.graphics.setColor(0.78, 0.83, 0.88)
        elseif i == 3 then
            love.graphics.setColor(0.60, 0.45, 0.30)
        else
            love.graphics.setColor(0.50, 0.55, 0.60)
        end
        love.graphics.printf(line, rx, ry, colW, "center")
        ry = ry + sy(36)
    end
    
    -- CONTINUE button
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    local btnW, btnH = sx(280), sy(60)
    local btnX = w / 2 - btnW / 2
    regButton("hs-continue", btnX, h * 0.88, btnW, btnH, "CONTINUE", nil, function()
        SCREEN = SCREENS.WELCOME
        currentDay = 1
    end)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.setLineWidth(math.max(1, sy(2)))
    love.graphics.rectangle("line", btnX, h * 0.88, btnW, btnH, sy(5))
    love.graphics.setLineWidth(math.max(1, sy(1)))
    Button.printfWithHalo("CONTINUE", btnX, h * 0.88 + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.94, 0.71, 0.16)
    
    love.graphics.setFont(prev)
end

function handleHighscoreClick(mx, my)
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
            b.onClick()
            return
        end
    end
end

-- ── HIGH SCORE LIST SCREEN (from selector) ──
function drawHighscoreList(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    
    -- Heading
    Button.printfWithHalo("HIGH SCORES", 0, h * 0.04, w, "center", 0.94, 0.71, 0.16)
    
    local colW = w / 2
    
    -- ── LEFT COLUMN: Your stats ──
    local lx = 0
    local ly = h * 0.12
    love.graphics.setColor(0.60, 0.60, 0.65)
    local labelFont = love.graphics.newFont("fonts/default.ttf", sy(22))
    love.graphics.setFont(labelFont)
    love.graphics.printf("YOUR STATS", lx, ly, colW, "center")
    ly = ly + sy(32)
    
    local u = users[playerInitials]
    local bodyFont = love.graphics.newFont("fonts/default.ttf", sy(28))
    love.graphics.setFont(bodyFont)
    if u then
        love.graphics.setColor(0.94, 0.71, 0.16)
        love.graphics.printf(playerInitials, lx, ly, colW, "center")
        ly = ly + sy(34)
        love.graphics.setColor(0.78, 0.83, 0.88)
        love.graphics.setFont(love.graphics.newFont("fonts/default.ttf", sy(24)))
        love.graphics.printf(u.games .. " game" .. (u.games ~= 1 and "s" or "") .. " played", lx, ly, colW, "center")
        ly = ly + sy(28)
        love.graphics.printf("Best: $" .. fmtMoney(u.high), lx, ly, colW, "center")
        ly = ly + sy(28)
        love.graphics.printf(#(u.pins or {}) .. " pins collected", lx, ly, colW, "center")
    else
        love.graphics.setColor(0.50, 0.55, 0.60)
        love.graphics.printf("No stats yet", lx, ly, colW, "center")
    end
    
    -- ── RIGHT COLUMN: Top 10 ──
    local rx = colW
    local ry = h * 0.12
    love.graphics.setColor(0.60, 0.60, 0.65)
    love.graphics.setFont(labelFont)
    love.graphics.printf("TOP 10", rx, ry, colW, "center")
    ry = ry + sy(32)
    
    if #highScores == 0 then
        love.graphics.setColor(0.50, 0.55, 0.60)
        love.graphics.setFont(love.graphics.newFont("fonts/default.ttf", sy(24)))
        love.graphics.printf("No scores yet!", rx, ry, colW, "center")
    else
        local scoreFont = love.graphics.newFont("fonts/default.ttf", sy(24))
        love.graphics.setFont(scoreFont)
        local shown = math.min(#highScores, 10)
        for i = 1, shown do
            local entry = highScores[i]
            local line = string.format("%2d. %3s  $%s", i, entry.initials, fmtMoney(entry.score))
            if entry.initials == playerInitials then
                love.graphics.setColor(0.94, 0.71, 0.16)
            elseif i == 1 then
                love.graphics.setColor(0.94, 0.71, 0.16)
            elseif i == 2 then
                love.graphics.setColor(0.78, 0.83, 0.88)
            elseif i == 3 then
                love.graphics.setColor(0.60, 0.45, 0.30)
            else
                love.graphics.setColor(0.50, 0.55, 0.60)
            end
            love.graphics.printf(line, rx, ry, colW, "center")
            ry = ry + sy(36)
        end
    end
    
    -- BACK button
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    local backW, backH = sx(100), sy(36)
    local backX = w - backW - sx(20)
    local backY = h - backH - sy(14)
    regButton("hsl-back", backX, backY, backW, backH, "", nil, function()
        SCREEN = SCREENS.SELECTOR
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(5))
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)
    
    love.graphics.setFont(prev)
end

function handleHighscoreListClick(mx, my)
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
            b.onClick()
            return
        end
    end
end

-- ── INSTRUCTIONS SCREEN ──
function drawInstructions(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    
    -- Heading
    Button.printfWithHalo("HOW TO PLAY", 0, h * 0.08, w, "center", 0.94, 0.71, 0.16)
    
    -- Instructions body
    local bodyFont = love.graphics.newFont("fonts/default.ttf", sy(27))
    love.graphics.setFont(bodyFont)
    love.graphics.setColor(0.78, 0.83, 0.88)
    
    local lines = {
        "Welcome to STONKS!",
        "",
        "This is a one-week trading challenge.",
        "You start with $10,000 and trade",
        "across Monday through Friday.",
        "",
        "Each day you can buy and sell shares",
        "to try to grow your balance.",
        "",
        "At the end of the week your final",
        "score is saved to the high scores",
        "list and compared against others.",
        "",
        "The game ends after Friday —",
        "make the most of your week!"
    }
    
    local lineY = h * 0.15
    for _, line in ipairs(lines) do
        love.graphics.printf(line, 0, lineY, w, "center")
        lineY = lineY + sy(33)
    end
    
    -- BACK button
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    local backW, backH = sx(100), sy(36)
    local backX = w - backW - sx(20)
    local backY = h - backH - sy(14)
    regButton("instr-back", backX, backY, backW, backH, "", nil, function()
        SCREEN = SCREENS.SELECTOR
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(5))
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)
    
    love.graphics.setFont(prev)
end

function handleInstructionsClick(mx, my)
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
            b.onClick()
            return
        end
    end
end

-- ── SETTINGS SCREEN ──
function drawSettings(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    Buttons = {}  -- clear buttons from previous screen
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    
    Button.printfWithHalo("SETTINGS", 0, h * 0.08, w, "center", 0.94, 0.71, 0.16)
    
    local bodyFont = love.graphics.newFont("fonts/default.ttf", sy(24))
    love.graphics.setFont(bodyFont)
    
    -- Y-Axis display toggle — centered vertically
    love.graphics.setColor(0.78, 0.83, 0.88)
    local labelY = h * 0.25
    love.graphics.printf("Y-AXIS DISPLAY", 0, labelY, w, "center")
    
    local btnW, btnH = sx(180), sy(60)
    local gap = sx(20)
    local totalW = btnW * 2 + gap
    local startX = w / 2 - totalW / 2
    local btnY = labelY + sy(60)
    
    -- PCT button
    local pctSelected = (chartDisplay or "pct") == "pct"
    regButton("set_pct", startX, btnY, btnW, btnH, "", nil, function()
        chartDisplay = "pct"
    end)
    if pctSelected then
        love.graphics.setColor(0.48, 0.41, 0.93)
        love.graphics.rectangle("fill", startX, btnY, btnW, btnH, sy(5))
    else
        love.graphics.setColor(0.25, 0.28, 0.32)
        love.graphics.rectangle("line", startX, btnY, btnW, btnH, sy(5))
    end
    Button.printfWithHalo("%", startX, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.78, 0.83, 0.88)
    
    -- PRICE button
    local priceSelected = (chartDisplay or "pct") == "price"
    regButton("set_price", startX + btnW + gap, btnY, btnW, btnH, "", nil, function()
        chartDisplay = "price"
    end)
    if priceSelected then
        love.graphics.setColor(0.48, 0.41, 0.93)
        love.graphics.rectangle("fill", startX + btnW + gap, btnY, btnW, btnH, sy(5))
    else
        love.graphics.setColor(0.25, 0.28, 0.32)
        love.graphics.rectangle("line", startX + btnW + gap, btnY, btnW, btnH, sy(5))
    end
    Button.printfWithHalo("$ PRICE", startX + btnW + gap, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.78, 0.83, 0.88)
    
    -- Default Speed slider
    local speedY = btnY + btnH + sy(40)
    love.graphics.setColor(0.78, 0.83, 0.88)
    love.graphics.setFont(bodyFont)
    local speedVal = (speedSlider and speedSlider.value) or 0.5
    local speedDisplay = 0.1 + 1.9 * speedVal
    love.graphics.printf("DEFAULT SPEED  " .. string.format("%.1f", speedDisplay) .. "x", 0, speedY, w, "center")
    love.graphics.setColor(0.25, 0.28, 0.32)
    local speedBarW, speedBarH = sx(300), sy(10)
    local speedBarX = w / 2 - speedBarW / 2
    love.graphics.rectangle("fill", speedBarX, speedY + sy(30), speedBarW, speedBarH, sy(5))
    love.graphics.setColor(0.48, 0.41, 0.93)
    love.graphics.rectangle("fill", speedBarX, speedY + sy(30), math.floor(speedBarW * speedVal), speedBarH, sy(5))
    regButton("set_speed_bar", speedBarX, speedY + sy(25), speedBarW, speedBarH + sy(10), "", nil, function()
        -- handled by click
    end)
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    love.graphics.setColor(0.60, 0.60, 0.65)
    love.graphics.printf("0.1x", 0, speedY + sy(30) + sy(10), speedBarX - sx(10), "right")
    love.graphics.printf("2x", speedBarX + speedBarW + sx(10), speedY + sy(30) + sy(10), sx(50), "left")
    
    -- BACK button
    local backW, backH = sx(100), sy(36)
    local backX = w - backW - sx(20)
    local backY = h - backH - sy(14)
    regButton("set_back", backX, backY, backW, backH, "", nil, function()
        if goBackTo then
            SCREEN = goBackTo
            goBackTo = nil
        else
            SCREEN = SCREENS.SELECTOR
        end
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)
    
    love.graphics.setFont(prev)
end

function handleSettingsClick(mx, my)
    -- Check back button explicitly
    if Buttons["set_back"] and Button.hit(Buttons["set_back"], mx, my) then
        Buttons["set_back"].onClick()
        return
    end
    -- Check toggle buttons
    if Buttons["set_pct"] and Button.hit(Buttons["set_pct"], mx, my) then
        chartDisplay = "pct"
        saveUserSettings(playerInitials)
        return
    end
    if Buttons["set_price"] and Button.hit(Buttons["set_price"], mx, my) then
        chartDisplay = "price"
        saveUserSettings(playerInitials)
        return
    end
    -- Default speed bar
    if Buttons["set_speed_bar"] and Button.hit(Buttons["set_speed_bar"], mx, my) then
        local btn = Buttons["set_speed_bar"]
        local relX = mx - btn.x
        local pct = math.max(0, math.min(1, relX / btn.w))
        if speedSlider then
            speedSlider.value = pct
            speedSlider.onChange(pct)
        end
        saveUserSettings(playerInitials)
        return
    end
end

-- ── INITIALS SCREEN ──
function drawInitials(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    Buttons = {}
    local prev = love.graphics.getFont()
    local bodyFont = love.graphics.newFont("fonts/default.ttf", sy(24))
    local smallFont = love.graphics.newFont("fonts/default.ttf", sy(18))
    
    -- Title
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("YOUR INITIALS", 0, h * 0.06, w, "center", 0.94, 0.71, 0.16)
    
    -- Load existing users for display
    loadUsers()
    local existing = getExistingUsers()
    local hasExisting = #existing > 0
    
    local curY = h * 0.16
    
    if hasExisting then
        -- Section header
        love.graphics.setFont(smallFont)
        love.graphics.setColor(0.45, 0.50, 0.55)
        love.graphics.printf("SAVED PLAYERS", 0, curY, w, "center")
        curY = curY + sy(28)
        
        -- User cards
        local cardW = sx(340)
        local cardH = sy(56)
        local cardGap = sy(8)
        local delW = sy(44)   -- delete button width
        local maxCards = math.min(#existing, 4)  -- show up to 4
        
        for i = 1, maxCards do
            local init = existing[i]
            local data = users[init]
            local cx = w / 2 - cardW / 2
            local cy = curY + (i - 1) * (cardH + cardGap)
            
            -- Card background
            love.graphics.setColor(0.12, 0.14, 0.18)
            love.graphics.rectangle("fill", cx, cy, cardW, cardH, sy(6))
            love.graphics.setColor(0.25, 0.28, 0.35)
            love.graphics.rectangle("line", cx, cy, cardW, cardH, sy(6))
            
            -- Initials in large font
            if btnActionFont then love.graphics.setFont(btnActionFont) end
            love.graphics.setColor(0.94, 0.71, 0.16)
            love.graphics.print(init, cx + sx(16), cy + (cardH - btnActionFont:getHeight()) / 2)
            
            -- Stats on the right (before delete button)
            love.graphics.setFont(smallFont)
            love.graphics.setColor(0.50, 0.55, 0.60)
            local statsText = string.format("%d game%s  ·  High $%s",
                data.games, data.games ~= 1 and "s" or "", fmtMoney(data.high))
            love.graphics.print(statsText, cx + sx(100), cy + (cardH - smallFont:getHeight()) / 2)
            
            -- Clickable button (main card, leaving room for delete)
            local mainW = cardW - delW - sx(6)
            regButton("user_" .. init, cx, cy, mainW, cardH, "", nil, function()
                playerInitials = init
                SCREEN = SCREENS.PRESIDENT
                pickPresident()
            end)
            
            -- Delete button (red ✕ on the right)
            local delX = cx + cardW - delW - sx(2)
            local delBtnW = delW + sx(2)
            regButton("deluser_" .. init, delX, cy, delBtnW, cardH, "", nil, function()
                deleteUser(init)
            end)
            love.graphics.setColor(0.72, 0.19, 0.30)
            love.graphics.rectangle("fill", delX, cy, delBtnW, cardH, sy(6))
            love.graphics.setColor(0.85, 0.30, 0.40)
            love.graphics.rectangle("line", delX, cy, delBtnW, cardH, sy(6))
            if btnActionFont then love.graphics.setFont(btnActionFont) end
            Button.printfWithHalo("X", delX, cy + (cardH - btnActionFont:getHeight()) / 2, delBtnW, "center", 0.94, 0.83, 0.88)
        end
        
        curY = curY + maxCards * (cardH + cardGap) + sy(16)
        
        -- Divider
        love.graphics.setFont(smallFont)
        love.graphics.setColor(0.35, 0.42, 0.48)
        love.graphics.printf("— or enter new —", 0, curY, w, "center")
        curY = curY + sy(28)
    else
        -- No existing users: show guidance text
        love.graphics.setColor(0.60, 0.60, 0.65)
        love.graphics.setFont(bodyFont)
        love.graphics.printf("Enter 3 letters to identify your scores", 0, curY, w, "center")
        curY = curY + sy(40)
    end
    
    -- Entry field with blinking cursor
    local showCursor = math.floor(love.timer.getTime() * 2) % 2 == 0
    local display = playerInitials
    if showCursor and #playerInitials < 3 then
        display = display .. "_"
    end
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo(display, w * 0.5 - sx(100), curY, sx(200), "center", 0.78, 0.83, 0.88)
    curY = curY + sy(48)
    
    -- Keyboard hint
    love.graphics.setFont(bodyFont)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.printf("Tap letters below or type on keyboard", 0, curY, w, "center")
    curY = curY + sy(30)
    
    -- On-screen keyboard (A-Z in rows)
    local keyW, keyH = sx(60), sy(50)
    local keyGap = sx(4)
    local rows = { "ABCDEFGH", "IJKLMNOP", "QRSTUVWX", "YZ" }
    for rIdx, row in ipairs(rows) do
        local rowW = #row * keyW + (#row - 1) * keyGap
        local rowX = w / 2 - rowW / 2
        local rowY = curY + (rIdx - 1) * (keyH + keyGap)
        for i = 1, #row do
            local ch = row:sub(i, i)
            local kx = rowX + (i - 1) * (keyW + keyGap)
            regButton("init_" .. ch, kx, rowY, keyW, keyH, "", nil, function()
                if #playerInitials < 3 then
                    playerInitials = playerInitials .. ch
                end
            end)
            love.graphics.setColor(0.25, 0.28, 0.32)
            love.graphics.rectangle("fill", kx, rowY, keyW, keyH, sy(5))
            love.graphics.setColor(0.78, 0.83, 0.88)
            love.graphics.printf(ch, kx, rowY + (keyH - btnActionFont:getHeight()) / 2, keyW, "center")
        end
    end
    
    -- DELETE and DONE buttons
    local btnW, btnH = sx(140), sy(50)
    local delX = w / 2 - btnW - sx(20)
    local doneX = w / 2 + sx(20)
    local actY = curY + 4 * (keyH + keyGap)
    regButton("init_del", delX, actY, btnW, btnH, "", nil, function()
        playerInitials = playerInitials:sub(1, -2)
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", delX, actY, btnW, btnH, sy(5))
    Button.printfWithHalo("DELETE", delX, actY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.60, 0.60, 0.65)
    
    regButton("init_done", doneX, actY, btnW, btnH, "", nil, function()
        if #playerInitials > 0 then
            SCREEN = SCREENS.PRESIDENT
            pickPresident()
        end
    end)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.rectangle("line", doneX, actY, btnW, btnH, sy(5))
    Button.printfWithHalo("DONE", doneX, actY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.94, 0.71, 0.16)
    
    love.graphics.setFont(prev)
end

function handleInitialsClick(mx, my)
    -- Check user card clicks first (including delete buttons)
    for id, b in pairs(Buttons) do
        if (id:find("^user_") or id:find("^deluser_") or id:find("^init_")) and Button.hit(b, mx, my) and b.onClick then
            b.onClick()
            return
        end
    end
end

-- ── PINS SCREEN ──
function loadPinMemes()
    pinMemeImages = {}
    local memeFiles = {
        "are_ya_winning_son.png",
        "don_tzu_trader_stop_loss.png",
        "money_come_back_no.png",
        "big_short_bubble.png",
        "diamond_hands_grocery.png",
        "jack_black_milkshake.png",
        "crying_mask_over.png",
        "gumby_cover_cat_eyes.png",
        "honey_saved_house.png",
    }
    -- Build label and copyright lookup from milestones config
    local labelMap = {}
    local copyrightedMap = {}
    if instrumentConfig and instrumentConfig.milestones then
        for _, m in ipairs(instrumentConfig.milestones) do
            local fname = m.image:match("([^/]+)$")
            if fname then
                labelMap[fname] = m.label
                copyrightedMap[fname] = m.copyrighted or false
            end
        end
    end
    for _, f in ipairs(memeFiles) do
        local ok, img = pcall(love.graphics.newImage, "memes/" .. f)
        if ok then
            local name = f:gsub("%.png$", ""):gsub("_", " "):gsub("(%l)(%w*)", function(a,b) return a:upper()..b end):gsub(" ", " ")
            local copyrighted = copyrightedMap[f] or false
            pinMemeImages[f] = { img = img, name = name, label = labelMap[f] or "", copyrighted = copyrighted }
            if copyrighted then pinHasCopyrighted = true end
        end
    end
end

function updatePinSpin(dt)
    if pinDragging then
        pinSnapTarget = nil
        return
    end

    -- Smooth snap toward target
    if pinSnapTarget then
        local diff = pinSnapTarget - pinAngle
        if math.abs(diff) < 0.01 then
            pinAngle = pinSnapTarget
            pinSnapTarget = nil
            pinVelocity = 0
        else
            pinAngle = pinAngle + diff * math.min(pinSnapSpeed * dt, 0.35)
        end
        return
    end

    -- Apply momentum with friction
    local friction = 4.0
    if math.abs(pinVelocity) > 0.01 then
        pinAngle = pinAngle + pinVelocity * dt
        pinVelocity = pinVelocity * (1 - friction * dt)
        if math.abs(pinVelocity) < 0.05 then
            pinVelocity = 0
            -- Start smooth snap to nearest rest position
            pinSnapTarget = math.floor(pinAngle / math.pi + 0.5) * math.pi
        end
    end
end

function drawPinCard(memeImg, cx, cy, cw, ch, angle, backLabel)
    local scaleX = math.cos(angle)
    local absScale = math.abs(scaleX)
    local w = cw * absScale
    local h = ch
    local frameR = math.floor(math.min(w, h) * 0.04)
    local pad = math.floor(math.min(w, h) * 0.025)

    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.scale(scaleX, 1)

    -- Drop shadow
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", -w / 2 + 5, -h / 2 + 5, w, h, frameR)

    -- Outer golden frame
    local gold1 = { 0.84, 0.69, 0.22 }
    local gold2 = { 0.72, 0.58, 0.15 }
    love.graphics.setColor(gold1[1], gold1[2], gold1[3])
    love.graphics.rectangle("fill", -w / 2, -h / 2, w, h, frameR)

    if scaleX > 0 then
        -- FRONT: meme image on dark backing
        love.graphics.setColor(0.06, 0.06, 0.10)
        love.graphics.rectangle("fill", -w / 2 + 3, -h / 2 + 3, w - 6, h - 6, frameR - 3)

        love.graphics.setColor(1, 1, 1)
        local iw, ih = memeImg:getDimensions()
        local s = math.min((w - pad * 2) / iw, (h - pad * 2) / ih)
        local dw, dh = iw * s, ih * s
        love.graphics.draw(memeImg, -dw / 2, -dh / 2, 0, s, s)

        -- Top shine gradient overlay
        local shineH = h * 0.35
        for i = 0, shineH do
            local a = 0.18 * (1 - i / shineH)
            love.graphics.setColor(1, 1, 1, a)
            love.graphics.rectangle("fill", -w / 2 + pad, -h / 2 + i, w - pad * 2, 1)
        end
    else
        -- BACK: gold surface fills the entire card
        love.graphics.setColor(gold2[1], gold2[2], gold2[3])
        love.graphics.rectangle("fill", -w / 2 + pad, -h / 2 + pad, w - pad * 2, h - pad * 2, frameR - pad)

        -- Inner decorative rings
        love.graphics.setColor(0.94, 0.81, 0.35)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", -w / 2 + pad + 4, -h / 2 + pad + 4, w - pad * 2 - 8, h - pad * 2 - 8, frameR - pad - 4)
        love.graphics.setColor(0.5, 0.38, 0.10)
        love.graphics.setLineWidth(math.max(1, sy(1)))
        love.graphics.rectangle("line", -w / 2 + pad + 10, -h / 2 + pad + 10, w - pad * 2 - 20, h - pad * 2 - 20, frameR - pad - 10)
        love.graphics.setLineWidth(math.max(1, sy(1)))

        -- Label fills the entire back (counter-flip so text isn't mirrored)
        if backLabel and backLabel ~= "" then
            local innerW = w - pad * 2 - 20
            local innerH = h - pad * 2 - 20
            local fontSize = math.floor(math.min(innerW * 0.11, innerH * 0.12))
            if fontSize < 10 then fontSize = 10 end
            local labelFont = love.graphics.newFont("fonts/RobotoMono-VariableFont_wght.ttf", fontSize)
            local prevF = love.graphics.getFont()
            love.graphics.setFont(labelFont)

            -- Word wrap
            local words = {}
            for word in backLabel:gmatch("%S+") do table.insert(words, word) end
            local lines = {}
            local currentLine = ""
            local maxWidth = innerW * 0.85
            for _, word in ipairs(words) do
                local test = currentLine == "" and word or currentLine .. " " .. word
                if labelFont:getWidth(test) > maxWidth and currentLine ~= "" then
                    table.insert(lines, currentLine)
                    currentLine = word
                else
                    currentLine = test
                end
            end
            if currentLine ~= "" then table.insert(lines, currentLine) end

            local lineH = labelFont:getHeight()
            local totalH = #lines * lineH
            local startY = -totalH / 2

            -- Counter-flip so text reads correctly on the back
            love.graphics.push()
            love.graphics.scale(-1, 1)

            for i, line in ipairs(lines) do
                local lw = labelFont:getWidth(line)
                local ly = startY + (i - 1) * lineH
                -- Shadow
                love.graphics.setColor(0.15, 0.10, 0.03)
                love.graphics.print(line, -lw / 2 + 1, ly + 1)
                -- Gold text
                love.graphics.setColor(0.94, 0.81, 0.30)
                love.graphics.print(line, -lw / 2, ly)
            end

            love.graphics.pop()
            love.graphics.setFont(prevF)
        end
    end

    -- Outer edge bevel
    love.graphics.setColor(1, 1, 1, 0.2)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", -w / 2 + 1, -h / 2 + 1, w - 2, h - 2, frameR - 1)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("line", -w / 2, -h / 2, w, h, frameR)
    love.graphics.setLineWidth(math.max(1, sy(1)))

    love.graphics.pop()
end

function spinPin()
end

function tryPinPress(mx, my)
    if not pinSelected or pinCardW == 0 then return false end
    local hw = pinCardW / 2
    local hh = pinCardH / 2
    if mx >= pinCardX - hw and mx <= pinCardX + hw
       and my >= pinCardY - hh and my <= pinCardY + hh then
        pinDragging = true
        pinLastX = mx
        pinVelocity = 0
        pinTapCandidate = true
        return true
    end
    return false
end

function doPinDrag(mx)
    if not pinDragging then return end
    local dx = mx - pinLastX
    if math.abs(dx) > 2 then
        pinTapCandidate = false
    end
    pinLastX = mx
    local sensitivity = 0.012
    pinAngle = pinAngle + dx * sensitivity
    pinVelocity = dx * sensitivity / (love.timer.getDelta() or 0.016)
end

function doPinRelease()
    if pinTapCandidate and pinSelected then
        -- Tap on pin card: hide it to reveal the grid behind
        pinSelected = nil
        pinAngle = 0
        pinVelocity = 0
        pinSnapTarget = nil
    end
    pinDragging = false
    pinTapCandidate = false
end

function drawPins(w, h)
    if not next(pinMemeImages) then loadPinMemes() end

    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    local prev = love.graphics.getFont()

    -- Title
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("YOUR COLLECTED PINS", 0, h * 0.02, w, "center", 0.94, 0.71, 0.16)

    -- 3-column layout: Left pricing | Thumbnail grid | Right pricing — all at same Y
    local cols = 3
    local thumbSize = math.min(58, (w * 0.38) / cols)
    local thumbGap = 8
    local gridW = cols * thumbSize + (cols - 1) * thumbGap
    local gridH = 3 * thumbSize + 2 * thumbGap
    local gridStartX = (w - gridW) / 2
    local gridStartY = h * 0.12

    -- Left and right columns align vertically with the middle of the grid
    local colLeftX = 12
    local colLeftW = gridStartX - 24
    local colRightX = gridStartX + gridW + 12
    local colRightW = w - colRightX - 12
    local colCenterY = gridStartY + gridH / 2

    Buttons = {}
    local ordered = getUserPins(playerInitials)
    if #ordered == 0 then
        -- No pins yet — show empty state
        love.graphics.setColor(0.35, 0.42, 0.48)
        local bodyFont = love.graphics.newFont("fonts/default.ttf", sy(24))
        love.graphics.setFont(bodyFont)
        love.graphics.printf("No pins collected yet", 0, gridStartY + gridH / 2 - sy(20), w, "center")
        love.graphics.printf("Survive a trading day to earn one!", 0, gridStartY + gridH / 2 + sy(8), w, "center")
    end
    for idx, fname in ipairs(ordered) do
        local data = pinMemeImages[fname]
        if data then
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local bx = gridStartX + col * (thumbSize + thumbGap)
            local by = gridStartY + row * (thumbSize + thumbGap)
            local selected = (pinSelected == fname)

            if selected then
                love.graphics.setColor(0.94, 0.71, 0.16, 0.3)
                love.graphics.rectangle("fill", bx - 3, by - 3, thumbSize + 6, thumbSize + 6, 8)
                love.graphics.setColor(0.94, 0.71, 0.16)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", bx - 3, by - 3, thumbSize + 6, thumbSize + 6, 8)
                love.graphics.setLineWidth(math.max(1, sy(1)))
            end

            regButton("pin_" .. fname, bx, by, thumbSize, thumbSize, "", nil, function()
                pinSelected = fname
                pinAngle = 0
                pinVelocity = 0
                pinDragging = false
                pinSnapTarget = nil
            end)

            love.graphics.setColor(0.10, 0.12, 0.15)
            love.graphics.rectangle("fill", bx, by, thumbSize, thumbSize, 5)
            local img = data.img
            local iw, ih = img:getDimensions()
            local s = math.min((thumbSize - 6) / iw, (thumbSize - 6) / ih)
            local dw, dh = iw * s, ih * s
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(img, bx + (thumbSize - dw) / 2, by + (thumbSize - dh) / 2, 0, s, s)
        end
    end

    if btnActionFont then love.graphics.setFont(btnActionFont) end
    local fh = btnActionFont:getHeight()

    -- Pricing columns — only show if selected pin is not copyrighted
    local isCopyrighted = false
    if pinSelected then
        local data = pinMemeImages[pinSelected]
        if data and data.copyrighted then isCopyrighted = true end
    end
    if not isCopyrighted then
        -- Left column: $9.99 pin — centered vertically with grid
        local leftBlockH = fh * 3 + 6 + 20
        local leftStartY = colCenterY - leftBlockH / 2
        local r1, g1, b1 = rainbowColor(0)
        Button.printfWithHalo("$9.99", colLeftX, leftStartY, colLeftW, "center", r1, g1, b1)
        Button.printfWithHalo("GET YOUR PIN", colLeftX, leftStartY + fh + 2, colLeftW, "center", 0.94, 0.71, 0.16)
        local amazonTY = leftStartY + fh * 2 + 6
        Button.printfWithHalo("ON AMAZON", colLeftX, amazonTY, colLeftW, "center", 0.78, 0.83, 0.88)

        -- Amazon logo below left column
        local logoCX = colLeftX + colLeftW / 2
        local logoY = amazonTY + fh + 2
        local logoW2, logoH2 = 60, 16
        love.graphics.setColor(0.96, 0.60, 0.20)
        local px = 3
        for i = 0, logoW2 / px - 1 do
            local t = i / (logoW2 / px - 1)
            local offset = (t - 0.5) * (t - 0.5) * logoH2 * 0.6
            love.graphics.rectangle("fill", logoCX - logoW2 / 2 + i * px, logoY + offset, px - 1, px - 1)
        end
        local tipX = logoCX + logoW2 / 2 - px
        love.graphics.rectangle("fill", tipX, logoY - px, px - 1, px - 1)
        love.graphics.rectangle("fill", tipX, logoY, px - 1, px - 1)
        love.graphics.rectangle("fill", tipX, logoY + px, px - 1, px - 1)

        -- Right column: $5.99 slop — centered vertically with grid
        local rightBlockH = fh * 6 + 6
        local rightStartY = colCenterY - rightBlockH / 2
        local r2, g2, b2 = rainbowColor(0.35)
        Button.printfWithHalo("$5.99", colRightX, rightStartY, colRightW, "center", r2, g2, b2)
        local rightText = "GET YOUR\nUNFUNGIBLE AND\nUNFUGLYABLE 3D\nANIMATION SLOP"
        Button.printfWithHalo(rightText, colRightX, rightStartY + fh + 2, colRightW, "center", 0.94, 0.71, 0.16)
        local creatorsY = rightStartY + fh * 5 + 6
        Button.printfWithHalo("FROM THE CREATORS", colRightX, creatorsY, colRightW, "center", 0.78, 0.83, 0.88)
    end

    -- Fullscreen pin card — overlay, half-screen, centered
    if pinSelected then
        local availH = h * 0.50
        local availW = w * 0.50

        -- Maintain meme aspect ratio
        local data = pinMemeImages[pinSelected]
        local iw, ih = data.img:getDimensions()
        local aspect = iw / ih
        local cardW, cardH
        if availW / availH > aspect then
            cardH = availH
            cardW = cardH * aspect
        else
            cardW = availW
            cardH = cardW / aspect
        end

        local cardCX = w / 2
        local cardCY = h / 2

        -- Store for hit testing
        pinCardX = cardCX
        pinCardY = cardCY
        pinCardW = cardW
        pinCardH = cardH

        -- Dark blur overlay behind the pin
        love.graphics.setColor(0.02, 0.03, 0.04, 0.75)
        love.graphics.rectangle("fill", 0, 0, w, h)

        drawPinCard(data.img, cardCX, cardCY, cardW, cardH, pinAngle, data.label)

        -- Side text while pin is shown (~100px from card edges)
        if not data.copyrighted then
            if btnActionFont then love.graphics.setFont(btnActionFont) end
            local gap = 100
            local leftCX = cardCX - cardW / 2
            local rightCX = cardCX + cardW / 2
            -- Left price
            local r3, g3, b3 = rainbowColor(0)
            Button.printfWithHalo("$9.99", leftCX - gap - 80, cardCY - cardH / 2.2, 80, "center", r3, g3, b3)
            -- Left: YOU MUST BUY PIN
            love.graphics.setColor(0.94, 0.71, 0.16)
            local leftText = "YOU\nMUST\nBUY\nPIN"
            Button.printfWithHalo(leftText, leftCX - gap - 80, cardCY - cardH / 4, 80, "center", 0.94, 0.71, 0.16)
            -- Right price
            local r4, g4, b4 = rainbowColor(0.35)
            Button.printfWithHalo("$5.99", rightCX + gap, cardCY - cardH / 2.2, 80, "center", r4, g4, b4)
            -- Right: GET WELL REGARDED SLOP
            love.graphics.setColor(0.94, 0.71, 0.16)
            local rightText = "GET\nWELL\nREGARDED\nSLOP"
            Button.printfWithHalo(rightText, rightCX + gap, cardCY - cardH / 6, 80, "center", 0.94, 0.71, 0.16)
        end

        -- Drag hint below pin
        love.graphics.setColor(0.35, 0.42, 0.48)
        local hintY = cardCY + cardH / 2 + 6
        if btnActionFont then love.graphics.setFont(btnActionFont) end
        Button.printfWithHalo("DRAG TO SPIN", 0, hintY, w, "center", 0.35, 0.42, 0.48)
        love.graphics.setColor(0.25, 0.30, 0.35)
        local disregardY = hintY + btnActionFont:getHeight() + 2
        Button.printfWithHalo("CLICK THE PIN TO DISREGARD", 0, disregardY, w, "center", 0.25, 0.30, 0.35)
    end

    -- BACK button
    local backW, backH = sx(100), sy(36)
    local backX = w - backW - sx(20)
    local backY = h - backH - sy(14)
    regButton("pin-back", backX, backY, backW, backH, "", nil, function()
        pinSelected = nil
        pinAngle = 0
        pinVelocity = 0
        pinDragging = false
        pinSnapTarget = nil
        SCREEN = SCREENS.SELECTOR
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)

    love.graphics.setFont(prev)
end

function handlePinsClick(mx, my)
    for id, b in pairs(Buttons) do
        if id:find("^pin[_-]") and Button.hit(b, mx, my) and b.onClick then
            -- When pin is enlarged, only allow the BACK button
            if pinSelected and not id:find("%-back$") then
                return
            end
            b.onClick()
            return
        end
    end
end

-- ── CANVAS SCREEN ──
function drawCanvas(w, h)
    -- Reset all game state (same as old drawWelcome)
    startingBalance = 10000
    realizedPnl = 0
    pnl = 0
    tendies = 1
    position = 0
    avgPrice = 0
    prevPosition = 0
    tradeCount = 0
    carryPosition = false
    prices = {}
    minutePrices = {}
    currentPrice = RANDOM_BASE or 32.40
    currentBid = currentPrice - 0.01
    currentAsk = currentPrice + 0.01
    prevPrice = currentPrice
    dataMode = nil
    csvData = nil
    csvIndex = 0
    rwIndex = 0
    predIndex = 0
    easyPhase = 0
    rewindTicks = 0
    stateSnapshots = {}
    currentDay = 1
    removeAllOrderLines()
    tradeMarkers = {}
    particles = {}
    milestonesHit = {}
    tickPaused = false
    speedMult = 10 ^ (-0.4)
    buyStopHeld = false
    sellStopHeld = false
    stopRepeatTimer = 0
    rewindHeld = false
    forwardHeld = false
    rewindButtonWasHeld = false
    avatarOffX = 0
    avatarOffY = 0

    Buttons = {}

    -- Dark background
    love.graphics.setColor(0.02, 0.03, 0.04)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Draw all sprites (wsb always last, on top)
    if canvasSprites then
        for _, s in ipairs(canvasSprites) do
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(s.image, s.x, s.y, 0, s.scale, s.scale)
        end
    end
    if canvasWsb then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(canvasWsb.image, canvasWsb.x, canvasWsb.y, 0, canvasWsb.scale, canvasWsb.scale)
    end

    -- Hint text at bottom
    local hintFont = love.graphics.newFont("fonts/default.ttf", sy(22))
    local prev = love.graphics.getFont()
    love.graphics.setFont(hintFont)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.printf("tap anywhere to start", 0, h - sy(60), w, "center")
    love.graphics.setFont(prev)

    -- Reset button (top-right corner)
    local resetW, resetH = sx(80), sy(32)
    local resetX = w - resetW - sx(16)
    local resetY = sy(16)
    regButton("canvas_reset", resetX, resetY, resetW, resetH, "", nil, function()
        resetCanvasPositions()
    end)
    love.graphics.setColor(0.25, 0.28, 0.32)
    love.graphics.rectangle("line", resetX, resetY, resetW, resetH, sy(5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("RESET", resetX, resetY + (resetH - (btnActionFont:getHeight() or sy(20))) / 2, resetW, "center", 0.55, 0.30, 0.30)

    -- SAVE DEFAULT button (debug only)
    if instrumentConfig and instrumentConfig.debug and instrumentConfig.debug.unlockAll then
        local defW, defH = sx(130), sy(32)
        local defX = resetX - defW - sx(10)
        local defY = sy(16)
        regButton("canvas_save_default", defX, defY, defW, defH, "", nil, function()
            saveCanvasDefault()
        end)
        love.graphics.setColor(0.20, 0.35, 0.25)
        love.graphics.rectangle("line", defX, defY, defW, defH, sy(5))
        if btnActionFont then love.graphics.setFont(btnActionFont) end
        Button.printfWithHalo("SAVE DEFAULT", defX, defY + (defH - (btnActionFont:getHeight() or sy(20))) / 2, defW, "center", 0.30, 0.75, 0.40)
    end

    love.graphics.setFont(prev)
end

function handleCanvasClick(mx, my)
    -- Check reset / save-default buttons first
    local rb = Buttons["canvas_reset"]
    if rb and Button.hit(rb, mx, my) then rb.onClick(); return end
    local db = Buttons["canvas_save_default"]
    if db and Button.hit(db, mx, my) then db.onClick(); return end
    -- Check wsb first (always on top)
    if canvasWsb
       and mx >= canvasWsb.x and mx <= canvasWsb.x + canvasWsb.w
       and my >= canvasWsb.y and my <= canvasWsb.y + canvasWsb.h then
        return  -- clicked wsb, stay on canvas
    end
    -- Check other sprites (reverse = topmost first)
    if canvasSprites then
        for i = #canvasSprites, 1, -1 do
            local s = canvasSprites[i]
            if mx >= s.x and mx <= s.x + s.w
               and my >= s.y and my <= s.y + s.h then
                return  -- clicked a sprite, stay on canvas
            end
        end
    end
    -- Clicked empty space -> advance
    SCREEN = SCREENS.INITIALS
end


