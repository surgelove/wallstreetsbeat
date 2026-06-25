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
        Button.printfWithHalo(currentEvent, 0, h * 0.55 + 25, w, "center", 0.78, 0.83, 0.88)
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
    -- Dark vignette behind the image so it pops against the velvet
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", 0, 0, w, h)
    if welcomeImage then
        local imgW, imgH = welcomeImage:getDimensions()
        local scale = math.min(w / imgW, h / imgH, 0.85)
        local dw, dh = imgW * scale, imgH * scale
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(welcomeImage, (w - dw) / 2, (h - dh) / 2, 0, scale, scale)
    end
end

function drawSelector(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CHOOSE INSTRUMENT", 0, h * 0.08, w, "center", 0.94, 0.71, 0.16)
    
    local items = { "RANDOM" }
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
    
    -- PINS button — special entry below the grid
    local lastIdx = #items
    local pinsRow = math.floor(lastIdx / cols) + 1
    local pinsBx = startX + 0 * (btnW + gap)
    local pinsBy = startY + pinsRow * (btnH + gap) + gap
    regButton("sel_PINS", pinsBx, pinsBy, btnW, btnH, "PINS", nil, function()
        SCREEN = SCREENS.PINS
    end)
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
        SCREEN = SCREENS.SETTINGS
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", setX, setY, setW, setH, sy(5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("SETTINGS", setX, setY + (setH - btnActionFont:getHeight()) / 2, setW, "center", 0.35, 0.42, 0.48)

    love.graphics.setFont(prev)
end



function drawTrading(w, h)
    local topH = TOPBAR_H
    local botH = BOTBAR_H
    local prevFont = love.graphics.getFont()
    
    -- Top bar pill
    love.graphics.setColor(0.07, 0.08, 0.09)
    love.graphics.rectangle("fill", PILL_R, 8, w - PILL_R * 2, topH - 8, PILL_R)
    love.graphics.setColor(0.78, 0.83, 0.88, 0.25)
    love.graphics.setLineWidth(math.max(1, sy(1)))
    love.graphics.rectangle("line", PILL_R, 8, w - PILL_R * 2, topH - 8, PILL_R)
    
    -- Avatar square at top-right of pill, rounded like the pill
    local avSize = 28
    local avX = w - PILL_R - avSize - 6
    local avY = 8 + (topH - 8 - avSize) / 2
    
    -- Stencil to clip avatar image to rounded rect
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
    
    -- Border on top of avatar
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", avX, avY, avSize, avSize, PILL_R)
    love.graphics.setLineWidth(math.max(1, sy(1)))
    
    -- Top bar uses Monaco
    if topFont then love.graphics.setFont(topFont) end
    
    -- Instrument name (clickable to restart) — gold, button font, same padding as avatar
    regButton("btn-instrument", PILL_R + 14, 5, 150, topH, "", nil, function()
        currentDay = 1
        SCREEN = SCREENS.SELECTOR
        position = 0; avgPrice = 0; realizedPnl = 0; pnl = 0; tradeCount = 0
        prices = {}; orderLines = {}; tradeMarkers = {}; particles = {}
        removeAllOrderLines()
    end)
    -- Vertically center all header content within the pill (pill y=3, height=topH-3)
    local cy = 8 + (topH - 8) / 2 - 3  -- center Y of the pill
    
    if btnActionFont then
        love.graphics.setFont(btnActionFont)
        local bfh = btnActionFont:getHeight()
        local text = instrumentText or "RANDOM WALK"
        local numLines = 1
        for _ in text:gmatch("\n") do numLines = numLines + 1 end
        Button.printfWithHalo(text, PILL_R + 14, cy - (bfh * numLines) / 2, 150, "left", 0.94, 0.71, 0.16)
        love.graphics.setFont(topFont)
    end
    
    -- ASK/BID vertical labels with values beside them
    local tfh = topFont:getHeight()
    local sFh = 9
    local sFont = love.graphics.newFont("fonts/RobotoMono-VariableFont_wght.ttf", sFh)
    local sStackH = 3 * sFh
    local sTop = cy - sStackH / 2
    local ax = w * 0.3
    
    love.graphics.setFont(sFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    for i = 1, 3 do
        love.graphics.print(string.sub("ASK", i, i), ax, sTop + (i - 1) * sFh)
    end
    love.graphics.setFont(headerValueFont)
    love.graphics.setColor(0.95, 0.15, 0.25)
    love.graphics.printf(string.format("%.2f", currentAsk), ax + 12, cy - headerValueFont:getHeight() / 2 + 2, 65, "left")
    
    love.graphics.setFont(sFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    for i = 1, 3 do
        love.graphics.print(string.sub("BID", i, i), ax + 95, sTop + (i - 1) * sFh)
    end
    love.graphics.setFont(headerValueFont)
    love.graphics.setColor(0, 0.78, 0.41)
    love.graphics.printf(string.format("%.2f", currentBid), ax + 95 + 12, cy - headerValueFont:getHeight() / 2 + 2, 65, "left")
    
    -- P&L
    local total = startingBalance + pnl + realizedPnl
    
    -- Vertical labels (UNR, REA, TOT) with amounts beside them, centered in pill
    local ux = w * 0.6
    local smallFh = 9
    local smallFont = love.graphics.newFont("fonts/RobotoMono-VariableFont_wght.ttf", smallFh)
    local stackH = 3 * smallFh
    local stackTop = cy - stackH / 2
    
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    for i = 1, 3 do
        love.graphics.print(string.sub("UNR", i, i), ux, stackTop + (i - 1) * smallFh)
    end
    love.graphics.setFont(headerValueFont)
    if pnl == 0 then
        love.graphics.setColor(0.55, 0.55, 0.60)
    else
        love.graphics.setColor(pnl > 0 and 0 or 0.91, pnl > 0 and 0.78 or 0.25, 0.41)
    end
    love.graphics.printf(fmtPnl(pnl), ux + 12, cy - headerValueFont:getHeight() / 2 + 2, 65, "left")
    
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    for i = 1, 3 do
        love.graphics.print(string.sub("REA", i, i), ux + 85, stackTop + (i - 1) * smallFh)
    end
    love.graphics.setFont(headerValueFont)
    if realizedPnl == 0 then
        love.graphics.setColor(0.55, 0.55, 0.60)
    else
        love.graphics.setColor(realizedPnl > 0 and 0 or 0.91, realizedPnl > 0 and 0.78 or 0.25, 0.41)
    end
    love.graphics.printf(fmtPnl(realizedPnl), ux + 85 + 12, cy - headerValueFont:getHeight() / 2 + 2, 80, "left")
    
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    for i = 1, 3 do
        love.graphics.print(string.sub("TOT", i, i), ux + 180, stackTop + (i - 1) * smallFh)
    end
    love.graphics.setFont(headerValueFont)
    love.graphics.setColor((total - startingBalance) >= 0 and 0 or 0.91, (total - startingBalance) >= 0 and 0.78 or 0.25, 0.41)
    love.graphics.printf("$" .. fmtMoney(total), ux + 180 + 12, cy - headerValueFont:getHeight() / 2 + 2, 120, "left")
    
    -- Restore default font after top bar
    love.graphics.setFont(prevFont)
    
    -- Chart
    drawChart()
    
    -- No panel backgrounds — velvet shows through behind buttons
    
    -- Side panel buttons
    local padX, gap = 8, 8
    local btnH = (h - topH - botH - 20 - gap * 3) / 4
    local panelY = topH + gap
    
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
        if count >= 5 then return end
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
        if count >= 5 then return end
        local step = currentPrice * (instrumentConfig.stopStepPct or 0.004)
        local price = highest == -math.huge and (currentAsk + step) or (highest + step)
        addOrderLine("buy-stop", math.floor(price * 1000 + 0.5) / 1000)
    end)
    drawBtnBox("btn-buy-stop", 0.15, 0.15, 0.20, 0, 0.78, 0.41, 0, 0.78, 0.41)
    regButton("btn-flat", rx, panelY + (btnH + gap) * 2, PANEL_W - padX * 2, btnH, "CLOSE POSTN", nil, closePosition)
    drawBtnBox("btn-flat", 0.15, 0.15, 0.20, 0.50, 0.50, 0.52, 0.69, 0.69, 0.69)
    regButton("btn-endday", rx, panelY + (btnH + gap) * 3, PANEL_W - padX * 2, btnH, "END DAY", nil, skipTo1555)
    drawBtnBox("btn-endday", 0.15, 0.15, 0.20, 0.78, 0.50, 0.60, 0.78, 0.50, 0.60)
    
    -- Bottom bar pill
    love.graphics.setColor(0.07, 0.08, 0.09)
    love.graphics.rectangle("fill", PILL_R, h - botH - 8, w - PILL_R * 2, botH, PILL_R)
    love.graphics.setColor(0.78, 0.83, 0.88, 0.25)
    love.graphics.setLineWidth(math.max(1, sy(1)))
    love.graphics.rectangle("line", PILL_R, h - botH - 8, w - PILL_R * 2, botH, PILL_R)
    
    local posLabel = position == 0 and "FLAT" or (position > 0 and ("LONG " .. math.abs(position)) or ("SHORT " .. math.abs(position)))
    local posR, posG, posB = position == 0 and 0.35 or (position > 0 and 0 or 0.91),
                              position == 0 and 0.42 or (position > 0 and 0.78 or 0.25),
                              position == 0 and 0.48 or (position > 0 and 0.41 or 0.38)
    if btnActionFont then
        local prev = love.graphics.getFont()
        love.graphics.setFont(btnActionFont)
        local bfh = btnActionFont:getHeight()
        Button.printfWithHalo(posLabel, APP_PAD + 14, (h - botH - 8) + (botH - bfh) / 2 - 1, 80, "left", posR, posG, posB)
        love.graphics.setFont(prev)
    else
        love.graphics.setColor(posR, posG, posB)
        love.graphics.print(posLabel, APP_PAD + 14, h - botH + 6)
    end
    -- SPD vertical label + speed slider
    local bCy = (h - botH - 8) + botH / 2 - 3
    local bSmallFh = 9
    local bSmallFont = love.graphics.newFont("fonts/RobotoMono-VariableFont_wght.ttf", bSmallFh)
    local bStackH = 3 * bSmallFh
    local bStackTop = bCy - bStackH / 2
    if speedSlider then
        local slX = APP_PAD + 14 + 80 + 36
        local slW = math.max(40, (w / 2 + 10 - slX - 10) / 2)
        local bCy = (h - botH - 8) + botH / 2 - 3
        speedSlider.x = slX
        speedSlider.y = bCy - 10
        speedSlider.w = slW
        speedSlider.h = 44
        -- SPD vertical label before slider
        love.graphics.setFont(bSmallFont)
        love.graphics.setColor(0.90, 0.90, 0.93)
        for i = 1, 3 do
            love.graphics.print(string.sub("SPD", i, i), slX - 18, bStackTop + (i - 1) * bSmallFh)
        end
        Slider.draw(speedSlider)
        -- Speed value label right of slider
        local spd = speedMult or 1
        love.graphics.setColor(0.94, 0.71, 0.16)
        love.graphics.setFont(headerValueFont)
        love.graphics.printf(string.format("%.1fx", spd), slX + slW + 12, bCy - headerValueFont:getHeight() / 2 + 2, 60, "left")
    end
    
    -- Vertical labels in bottom bar (AVG, TRA, STP) matching top bar style
    local bPrevFont = love.graphics.getFont()
    local bcy = (h - botH - 8) + botH / 2 - 3  -- center Y of bottom pill
    
    -- 4 columns distributed from center to right edge
    local bColStart = w / 2 + 25
    local bColEnd = w - PILL_R - 50
    local bColW = math.max(50, (bColEnd - bColStart) / 3)
    local bLabels = { { "AVG", bColStart + bColW * 0, avgPrice, "%.2f" },
                      { "TRA", bColStart + bColW * 1, tradeCount, "%d" },
                      { "STP", bColStart + bColW * 2, #orderLines, "%d" } }
    
    for _, item in ipairs(bLabels) do
        local label, lx, val, fmt = item[1], item[2], item[3], item[4]
        love.graphics.setFont(bSmallFont)
        love.graphics.setColor(0.90, 0.90, 0.93)
        for i = 1, 3 do
            love.graphics.print(string.sub(label, i, i), lx, bStackTop + (i - 1) * bSmallFh)
        end
        love.graphics.setFont(headerValueFont)
        love.graphics.setColor(0.78, 0.83, 0.88)
        love.graphics.printf(string.format(fmt, val or 0), lx + 12, bcy - headerValueFont:getHeight() / 2 + 2, bColW - 12, "left")
    end

    -- Day display — extreme right, same font as FLAT, symmetric inset
    if currentDay and weekDays then
        local dayStr = weekDays[currentDay] or ""
        if dayStr ~= "" and btnActionFont then
            local prev = love.graphics.getFont()
            love.graphics.setFont(btnActionFont)
            local bfh = btnActionFont:getHeight()
            local dayX = w - PILL_R
            local dayY = (h - botH - 8) + (botH - bfh) / 2 - 1
            Button.printfWithHalo(dayStr, dayX - 100, dayY, 100, "right", 0.30, 0.60, 0.95)
            love.graphics.setFont(prev)
        end
    end

    love.graphics.setFont(bPrevFont)
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
    Button.printfWithHalo("DAY COMPLETE!", 0, h * 0.08, w, "center", 0.94, 0.71, 0.16)
    
    -- Financial summary — use btnActionFont for the body text
    local text = string.format("Starting Balance\n$%s\n\nDay P&L\n%s$%s\n\nFinal Balance\n$%s",
                               fmtMoney(startingBalance), sign, fmtPnl(dayPnl), fmtMoney(total))
    love.graphics.setColor(0.78, 0.83, 0.88)
    love.graphics.printf(text, w * 0.3, h * 0.15, w * 0.4, "center")
    
    -- CONTINUE button
    regButton("recap-continue", w * 0.7 - 60, h * 0.5, 120, 40, "CONTINUE", nil, continueTrading)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.rectangle("line", w * 0.7 - 60, h * 0.5, 120, 40, 3)
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CONTINUE", w * 0.7 - 60, h * 0.5 + (40 - btnActionFont:getHeight()) / 2, 120, "center", 0.94, 0.71, 0.16)
    
    -- START OVER button
    regButton("recap-restart", w * 0.7 - 60, h * 0.5 + 55, 120, 40, "START OVER", nil, function()
        love.event.quit("restart")
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", w * 0.7 - 60, h * 0.5 + 55, 120, 40, 3)
    Button.printfWithHalo("START OVER", w * 0.7 - 60, h * 0.5 + 55 + (40 - btnActionFont:getHeight()) / 2, 120, "center", 0.35, 0.42, 0.48)
    
    love.graphics.setFont(prev)
end

-- ── CLICK HANDLERS ──
function handleSelectorClick(mx, my)
    for id, b in pairs(Buttons) do
        if id:find("^sel_") and Button.hit(b, mx, my) and b.onClick then
            b.onClick()
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

-- ── HIGH SCORE SCREEN ──
function drawHighscore(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    
    -- Heading
    Button.printfWithHalo("WEEK COMPLETE!", 0, h * 0.05, w, "center", 0.94, 0.71, 0.16)
    
    -- Final tally
    local total = highscoreNewScore
    local weekPnl = total - 10000
    local sign = weekPnl >= 0 and "+" or "-"
    local text = string.format("Final Balance\n$%s\n\nWeek P&L\n%s$%s",
                               fmtMoney(total), sign, fmtPnl(weekPnl))
    love.graphics.setColor(0.78, 0.83, 0.88)
    love.graphics.printf(text, 0, h * 0.12, w, "center")
    
    -- Initials entry
    local showCursor = math.floor(love.timer.getTime() * 2) % 2 == 0
    local entryLabel = "ENTER INITIALS"
    love.graphics.setColor(0.60, 0.60, 0.65)
    love.graphics.printf(entryLabel, 0, h * 0.35, w, "center")
    
    local initials = highscoreInitials
    if initials == "SAVED" then
        love.graphics.setColor(0, 0.78, 0.41)
        love.graphics.printf("SAVED!", 0, h * 0.41, w, "center")
    else
        local display = initials
        if showCursor and #initials < 3 then
            display = display .. "_"
        else
            display = display .. " "
        end
        -- Check if it's a new high score
        local isNew = isNewHighScore(highscoreNewScore)
        if isNew then
            love.graphics.setColor(0.94, 0.71, 0.16)
            love.graphics.printf("NEW HIGH SCORE!", 0, h * 0.47, w, "center")
        end
        love.graphics.setColor(0.78, 0.83, 0.88)
        Button.printfWithHalo(display, w * 0.5 - 60, h * 0.39, 120, "center", 0.78, 0.83, 0.88)
    end
    
    -- High scores list
    local listY = h * 0.53
    love.graphics.setColor(0.60, 0.60, 0.65)
    love.graphics.printf("─ HIGH SCORES ─", 0, listY, w, "center")
    listY = listY + 28
    
    local smallFont = love.graphics.newFont("fonts/default.ttf", 18)
    love.graphics.setFont(smallFont)
    for i, entry in ipairs(highScores) do
        local rank = i .. "."
        local line = string.format("%-4s %s  $%s", rank, entry.initials, fmtMoney(entry.score))
        if entry.initials == highscoreInitials and entry.score == highscoreNewScore then
            love.graphics.setColor(0.94, 0.71, 0.16)
        else
            love.graphics.setColor(0.78, 0.83, 0.88)
        end
        love.graphics.printf(line, w * 0.5 - 120, listY, 240, "center")
        listY = listY + 24
    end
    
    -- Continue button
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    regButton("hs-continue", w * 0.5 - 60, h * 0.88, 120, 40, "CONTINUE", nil, function()
        if highscoreInitials ~= "" and highscoreInitials ~= "SAVED" then
            addHighScore(highscoreInitials, highscoreNewScore)
        end
        SCREEN = SCREENS.WELCOME
        currentDay = 1
    end)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.rectangle("line", w * 0.5 - 60, h * 0.88, 120, 40, 3)
    Button.printfWithHalo("CONTINUE", w * 0.5 - 60, h * 0.88 + (40 - btnActionFont:getHeight()) / 2, 120, "center", 0.94, 0.71, 0.16)
    
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
    Button.printfWithHalo("HIGH SCORES", 0, h * 0.08, w, "center", 0.94, 0.71, 0.16)
    
    -- High scores list
    local listY = h * 0.20
    local smallFont = love.graphics.newFont("fonts/default.ttf", sy(20))
    love.graphics.setFont(smallFont)
    
    if #highScores == 0 then
        love.graphics.setColor(0.60, 0.60, 0.65)
        love.graphics.printf("No high scores yet!", 0, listY, w, "center")
    else
        for i, entry in ipairs(highScores) do
            local rank = i .. "."
            local line = string.format("%-4s  %-3s   $%s", rank, entry.initials, fmtMoney(entry.score))
            if i == 1 then
                love.graphics.setColor(0.94, 0.71, 0.16)
            elseif i == 2 then
                love.graphics.setColor(0.78, 0.83, 0.88)
            elseif i == 3 then
                love.graphics.setColor(0.60, 0.45, 0.30)
            else
                love.graphics.setColor(0.50, 0.55, 0.60)
            end
            love.graphics.printf(line, w * 0.5 - 140, listY, 280, "center")
            listY = listY + 30
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
    local bodyFont = love.graphics.newFont("fonts/default.ttf", sy(18))
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
    
    local lineY = h * 0.20
    for _, line in ipairs(lines) do
        love.graphics.printf(line, 0, lineY, w, "center")
        lineY = lineY + 26
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
    
    local bodyFont = love.graphics.newFont("fonts/default.ttf", sy(16))
    love.graphics.setFont(bodyFont)
    
    -- Y-Axis display toggle
    love.graphics.setColor(0.78, 0.83, 0.88)
    love.graphics.printf("Y-AXIS DISPLAY", 0, h * 0.22, w, "center")
    
    local btnW, btnH = 160, 40
    local gap = 20
    local totalW = btnW * 2 + gap
    local startX = w / 2 - totalW / 2
    local btnY = h * 0.32
    
    -- PCT button
    local pctSelected = (chartDisplay or "pct") == "pct"
    regButton("set_pct", startX, btnY, btnW, btnH, "", nil, function()
        chartDisplay = "pct"
    end)
    if pctSelected then
        love.graphics.setColor(0.48, 0.41, 0.93)
        love.graphics.rectangle("fill", startX, btnY, btnW, btnH, 5)
    else
        love.graphics.setColor(0.25, 0.28, 0.32)
        love.graphics.rectangle("line", startX, btnY, btnW, btnH, 5)
    end
    Button.printfWithHalo("%", startX, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.78, 0.83, 0.88)
    
    -- PRICE button
    local priceSelected = (chartDisplay or "pct") == "price"
    regButton("set_price", startX + btnW + gap, btnY, btnW, btnH, "", nil, function()
        chartDisplay = "price"
    end)
    if priceSelected then
        love.graphics.setColor(0.48, 0.41, 0.93)
        love.graphics.rectangle("fill", startX + btnW + gap, btnY, btnW, btnH, 5)
    else
        love.graphics.setColor(0.25, 0.28, 0.32)
        love.graphics.rectangle("line", startX + btnW + gap, btnY, btnW, btnH, 5)
    end
    Button.printfWithHalo("$ PRICE", startX + btnW + gap, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.78, 0.83, 0.88)
    
    -- BACK button
    local backW, backH = sx(100), sy(36)
    local backX = w - backW - sx(20)
    local backY = h - backH - sy(14)
    regButton("set_back", backX, backY, backW, backH, "", nil, function()
        SCREEN = SCREENS.SELECTOR
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)
    
    love.graphics.setFont(prev)
end

function handleSettingsClick(mx, my)
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
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
    local ordered = {
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


