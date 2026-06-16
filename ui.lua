-- ── CONTROLS ──
local theme = require("controls.theme")
Button = require("controls.button")
Slider = require("controls.slider")
Background = require("controls.background")

-- Global button registry (for click dispatching)
Buttons = {}

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
    local gap = 10
    local btnW = math.min(140, (w - 100 - gap * (cols - 1)) / cols)
    local btnH = 50
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
            love.graphics.rectangle("line", bx, by, btnW, btnH, 5)
            Button.printfWithHalo(name, bx, by + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.48, 0.41, 0.93)
        else
            love.graphics.setColor(0.12, 0.14, 0.16)
            love.graphics.rectangle("line", bx, by, btnW, btnH, 5)
            Button.printfWithHalo(name, bx, by + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.78, 0.83, 0.88)
        end
    end
    love.graphics.setFont(prev)
end



function drawTrading(w, h)
    local topH = TOPBAR_H
    local botH = BOTBAR_H
    local prevFont = love.graphics.getFont()
    
    -- Top bar pill
    love.graphics.setColor(0.07, 0.08, 0.09)
    love.graphics.rectangle("fill", PILL_R, 8, w - PILL_R * 2, topH - 8, PILL_R)
    
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
    love.graphics.setLineWidth(1)
    
    -- Top bar uses Monaco
    if topFont then love.graphics.setFont(topFont) end
    
    -- Instrument name (clickable to restart) — gold, button font, same padding as avatar
    regButton("btn-instrument", PILL_R + 14, 5, 150, topH, "", nil, function()
        SCREEN = SCREENS.WELCOME
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
    regButton("btn-cancel", lx, panelY + (btnH + gap) * 3, PANEL_W - padX * 2, btnH, "CANCEL", nil, removeAllOrderLines)
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
    regButton("btn-flat", rx, panelY + (btnH + gap) * 2, PANEL_W - padX * 2, btnH, "CLOSE", nil, closePosition)
    drawBtnBox("btn-flat", 0.15, 0.15, 0.20, 0.50, 0.50, 0.52, 0.69, 0.69, 0.69)
    regButton("btn-endday", rx, panelY + (btnH + gap) * 3, PANEL_W - padX * 2, btnH, "END DAY", nil, skipTo1555)
    drawBtnBox("btn-endday", 0.15, 0.15, 0.20, 0.78, 0.50, 0.60, 0.78, 0.50, 0.60)
    
    -- Bottom bar pill
    love.graphics.setColor(0.07, 0.08, 0.09)
    love.graphics.rectangle("fill", PILL_R, h - botH - 8, w - PILL_R * 2, botH, PILL_R)
    
    local posLabel = position == 0 and "FLAT" or (position > 0 and ("LONG " .. math.abs(position)) or ("SHORT " .. math.abs(position)))
    local posR, posG, posB = position == 0 and 0.35 or (position > 0 and 0 or 0.91),
                              position == 0 and 0.42 or (position > 0 and 0.78 or 0.25),
                              position == 0 and 0.48 or (position > 0 and 0.41 or 0.38)
    if btnActionFont then
        local prev = love.graphics.getFont()
        love.graphics.setFont(btnActionFont)
        local bfh = btnActionFont:getHeight()
        Button.printfWithHalo(posLabel, APP_PAD + 14, (h - botH - 8) + (botH - bfh) / 2 - 3, 80, "left", posR, posG, posB)
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
        speedSlider.h = 20
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
    local sign = dayPnl >= 0 and "+" or ""
    
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


