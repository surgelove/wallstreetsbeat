-- ── CONTROLS ──
local theme = require("controls.theme")
Button = require("controls.button")
Slider = require("controls.slider")

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
    love.graphics.setColor(0.78, 0.83, 0.88)
    love.graphics.printf("YOUR PRESIDENT IS...", 0, h * 0.08, w, "center")
    
    if currentPresident then
        local img = presidentImages[currentPresident.name]
        if img then
            local iw, ih = img:getDimensions()
            local scale = math.min(150 / iw, 150 / ih)
            local dw, dh = iw * scale, ih * scale
            love.graphics.draw(img, (w - dw) / 2, h * 0.2, 0, scale, scale)
        end
        love.graphics.setColor(0.94, 0.71, 0.16)
        love.graphics.printf(currentPresident.name, 0, h * 0.2 + 170, w, "center")
    end
    
    -- Breaking news
    if currentEvent ~= "" then
        love.graphics.setColor(0.91, 0.25, 0.38)
        love.graphics.printf("BREAKING NEWS", 0, h * 0.55, w, "center")
        love.graphics.setColor(0.78, 0.83, 0.88)
        love.graphics.printf(currentEvent, 0, h * 0.55 + 25, w, "center")
    end
    
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.printf("TAP TO CONTINUE", 0, h * 0.8, w, "center")
end

-- ── SCREENS ──
function drawWelcome(w, h)
    love.graphics.setBackgroundColor(0.04, 0.04, 0.06)
    if welcomeImage then
        local imgW, imgH = welcomeImage:getDimensions()
        local scale = math.min(w / imgW, h / imgH, 1)
        local dw, dh = imgW * scale, imgH * scale
        love.graphics.draw(welcomeImage, (w - dw) / 2, (h - dh) / 2, 0, scale, scale)
    end
end

function drawSelector(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.printf("CHOOSE INSTRUMENT", 0, h * 0.08, w, "center")
    
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
            love.graphics.setColor(0.48, 0.41, 0.93)
        else
            love.graphics.setColor(0.12, 0.14, 0.16)
            love.graphics.rectangle("line", bx, by, btnW, btnH, 5)
            love.graphics.setColor(0.78, 0.83, 0.88)
        end
        love.graphics.printf(name, bx, by + (btnH - 14) / 2, btnW, "center")
    end
end

function drawIntro(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    love.graphics.setColor(0.78, 0.83, 0.88)
    love.graphics.printf(introText or "", 50, h * 0.25, w - 100, "center")
    
    local bw, bh = 120, 40
    local bx = (w - bw) / 2
    local by = h * 0.55
    regButton("intro_ok", bx, by, bw, bh, "OK", nil, function()
        SCREEN = SCREENS.TRADING
        initTradingSession()
    end)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.rectangle("line", bx, by, bw, bh, 3)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.printf("OK", bx, by + (bh - 14) / 2, bw, "center")
end

function drawTrading(w, h)
    local topH = TOPBAR_H
    local botH = BOTBAR_H
    
    -- Top bar background
    love.graphics.setColor(0.07, 0.08, 0.09)
    love.graphics.rectangle("fill", 0, 0, w, topH)
    
    -- Instrument name (clickable to restart)
    regButton("btn-instrument", APP_PAD, 5, 150, topH, "", nil, function()
        SCREEN = SCREENS.WELCOME
        position = 0; avgPrice = 0; realizedPnl = 0; pnl = 0; tradeCount = 0
        prices = {}; orderLines = {}; tradeMarkers = {}; particles = {}
        removeAllOrderLines()
    end)
    
    -- Prices
    love.graphics.setColor(0.72, 0.19, 0.30)
    local askLbl = "ASK"
    love.graphics.printf(askLbl, w * 0.3, 2, 50, "center")
    love.graphics.setColor(0.72, 0.19, 0.30)
    love.graphics.printf(string.format("%.2f", currentAsk), w * 0.3, 18, 50, "center")
    
    love.graphics.setColor(0, 0.78, 0.41)
    love.graphics.printf("BID", w * 0.3 + 60, 2, 50, "center")
    love.graphics.setColor(0, 0.78, 0.41)
    love.graphics.printf(string.format("%.2f", currentBid), w * 0.3 + 60, 18, 50, "center")
    
    -- P&L
    local total = startingBalance + pnl + realizedPnl
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.printf("UNREAL", w * 0.6, 2, 60, "center")
    love.graphics.setColor(pnl >= 0 and 0 or 0.91, pnl >= 0 and 0.78 or 0.25, 0.41)
    love.graphics.printf(fmtPnl(pnl), w * 0.6, 18, 60, "center")
    
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.printf("REALIZED", w * 0.6 + 70, 2, 70, "center")
    love.graphics.setColor(realizedPnl >= 0 and 0 or 0.91, realizedPnl >= 0 and 0.78 or 0.25, 0.41)
    love.graphics.printf(fmtPnl(realizedPnl), w * 0.6 + 70, 18, 70, "center")
    
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.printf("TOTAL", w * 0.6 + 150, 2, 80, "center")
    love.graphics.setColor((total - startingBalance) >= 0 and 0 or 0.91, (total - startingBalance) >= 0 and 0.78 or 0.25, 0.41)
    love.graphics.printf("$" .. fmtMoney(total), w * 0.6 + 150, 18, 100, "center")
    
    -- Chart
    drawChart()
    
    -- Left panel background
    love.graphics.setColor(0.07, 0.08, 0.09)
    love.graphics.rectangle("fill", 0, topH, PANEL_W, h - topH - botH)
    
    -- Right panel background
    love.graphics.rectangle("fill", w - PANEL_W, topH, PANEL_W, h - topH - botH)
    
    -- Side panel buttons
    local panelY = topH + 5
    local btnH = (h - topH - botH - 20) / 4 - 5
    
    -- Left panel
    local lx = 5
    regButton("btn-sell", lx, panelY, PANEL_W - 10, btnH, "SELL", "Market", sell)
    drawBtnBox("btn-sell", 0.72, 0.19, 0.30, 0, 0, 0)
    regButton("btn-sell-stop", lx, panelY + (btnH + 5), PANEL_W - 10, btnH, "SELL STOP", nil, function()
        addOrderLine("sell-stop", math.floor((currentBid - currentPrice * 0.004) * 1000 + 0.5) / 1000)
    end)
    drawBtnBox("btn-sell-stop", nil, nil, nil, 0.72, 0.19, 0.30, 0.72, 0.19, 0.30)
    regButton("btn-sl", lx, panelY + (btnH + 5) * 2, PANEL_W - 10, btnH, "PL STOP", nil, function()
        if position == 0 then return end
        local slPrice = position > 0 and math.floor((currentBid - currentPrice * 0.008) * 1000 + 0.5) / 1000 or math.floor((currentAsk + currentPrice * 0.008) * 1000 + 0.5) / 1000
        addOrderLine("stop-loss", slPrice)
    end)
    drawBtnBox("btn-sl", nil, nil, nil, 0.78, 0.60, 0.13, 0.78, 0.60, 0.13)
    regButton("btn-cancel", lx, panelY + (btnH + 5) * 3, PANEL_W - 10, btnH, "CANCEL", nil, removeAllOrderLines)
    drawBtnBox("btn-cancel", nil, nil, nil, 0.35, 0.42, 0.48, 0.35, 0.42, 0.48)

    -- Right panel
    local rx = w - PANEL_W + 5
    regButton("btn-buy", rx, panelY, PANEL_W - 10, btnH, "BUY", "Market", buy)
    drawBtnBox("btn-buy", 0, 0.78, 0.41, 0, 0, 0)
    regButton("btn-buy-stop", rx, panelY + (btnH + 5), PANEL_W - 10, btnH, "BUY STOP", nil, function()
        addOrderLine("buy-stop", math.floor((currentAsk + currentPrice * 0.004) * 1000 + 0.5) / 1000)
    end)
    drawBtnBox("btn-buy-stop", nil, nil, nil, 0, 0.78, 0.41, 0, 0.78, 0.41)
    regButton("btn-flat", rx, panelY + (btnH + 5) * 2, PANEL_W - 10, btnH, "CLOSE", nil, closePosition)
    drawBtnBox("btn-flat", nil, nil, nil, 0.69, 0.69, 0.69, 0.69, 0.69, 0.69)
    regButton("btn-endday", rx, panelY + (btnH + 5) * 3, PANEL_W - 10, btnH, "END DAY", nil, skipTo1555)
    drawBtnBox("btn-endday", nil, nil, nil, 0.78, 0.50, 0.60, 0.78, 0.50, 0.60)
    
    -- Bottom bar
    love.graphics.setColor(0.07, 0.08, 0.09)
    love.graphics.rectangle("fill", 0, h - botH, w, botH)
    
    local posLabel = position == 0 and "FLAT" or (position > 0 and "LONG" or "SHORT")
    love.graphics.setColor(position == 0 and 0.35 or (position > 0 and 0 or 0.91),
                           position == 0 and 0.42 or (position > 0 and 0.78 or 0.25),
                           position == 0 and 0.48 or (position > 0 and 0.41 or 0.38))
    love.graphics.print(posLabel, APP_PAD + 5, h - botH + 6)
    love.graphics.setColor(0.78, 0.83, 0.88)
    love.graphics.print(string.format("Qty %d", math.abs(position)), APP_PAD + 60, h - botH + 6)
    
    if avgPrice and avgPrice > 0 then
        love.graphics.print(string.format("Avg %.2f", avgPrice), APP_PAD + 130, h - botH + 6)
    else
        love.graphics.print("Avg —", APP_PAD + 130, h - botH + 6)
    end
    love.graphics.print(string.format("Trades %d  Stops %d", tradeCount, #orderLines), APP_PAD + 240, h - botH + 6)
end

function drawEOD(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    
    love.graphics.setColor(0.78, 0.83, 0.88)
    local posDir = position > 0 and "LONG" or "SHORT"
    local text = string.format("Open position: %s %d @ %.2f\n\nClose at market or carry to next day?",
                               posDir, math.abs(position), avgPrice or 0)
    love.graphics.printf(text, 50, h * 0.3, w - 100, "center")
    
    regButton("eod-close", w * 0.35 - 60, h * 0.5, 120, 40, "CLOSE", nil, function()
        closeAllPositions("MARKET CLOSED")
        SCREEN = SCREENS.RECAP
    end)
    love.graphics.setColor(0.72, 0.19, 0.30)
    love.graphics.rectangle("fill", w * 0.35 - 60, h * 0.5, 120, 40, 3)
    love.graphics.setColor(0, 0, 0)
    love.graphics.printf("CLOSE", w * 0.35 - 60, h * 0.5 + 10, 120, "center")

    regButton("eod-keep", w * 0.65 - 60, h * 0.5, 120, 40, "KEEP", nil, function()
        carryPosition = true
        SCREEN = SCREENS.RECAP
    end)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.rectangle("line", w * 0.65 - 60, h * 0.5, 120, 40, 3)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.printf("KEEP", w * 0.65 - 60, h * 0.5 + 10, 120, "center")
end

function drawRecap(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    
    local total = startingBalance + realizedPnl
    local dayPnl = realizedPnl
    local sign = dayPnl >= 0 and "+" or ""
    
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.printf("DAY COMPLETE!", w * 0.1, h * 0.1, w * 0.3, "center")
    
    local text = string.format("Starting Balance\n$%s\n\nDay P&L\n%s$%s\n\nFinal Balance\n$%s",
                               fmtMoney(startingBalance), sign, fmtPnl(dayPnl), fmtMoney(total))
    love.graphics.setColor(0.78, 0.83, 0.88)
    love.graphics.printf(text, w * 0.3, h * 0.15, w * 0.4, "center")
    
    regButton("recap-continue", w * 0.7 - 60, h * 0.5, 120, 40, "CONTINUE", nil, continueTrading)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.rectangle("line", w * 0.7 - 60, h * 0.5, 120, 40, 3)
    love.graphics.setColor(0.94, 0.71, 0.16)
    love.graphics.printf("CONTINUE", w * 0.7 - 60, h * 0.5 + 10, 120, "center")

    regButton("recap-restart", w * 0.7 - 60, h * 0.5 + 55, 120, 40, "START OVER", nil, function()
        love.event.quit("restart")
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", w * 0.7 - 60, h * 0.5 + 55, 120, 40, 3)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.printf("START OVER", w * 0.7 - 60, h * 0.5 + 65, 120, "center")
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


