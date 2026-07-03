-- ── CONTROLS ──
local theme = require("controls.theme")
Button = require("controls.button")
Slider = require("controls.slider")
Background = require("controls.background")
local Haptics = require("haptics")

-- Shader: replaces RGB with draw color but preserves texture alpha (solid fill)
local solidColorShader = love.graphics.newShader([[
    vec4 effect(vec4 color, Image texture, vec2 texCoords, vec2 screenCoords) {
        vec4 pixel = Texel(texture, texCoords);
        return vec4(color.rgb, pixel.a * color.a);
    }
]])

-- Global button registry (for click dispatching)
Buttons = {}

-- Shared cooldown guard for all button clicks (Balatro-style input blocking)
function safeButtonClick(btn)
    if not btn or not btn.onClick then return false end
    if love.timer.getTime() - (lastButtonTime or 0) < (BUTTON_COOLDOWN or 0.3) then
        return false
    end
    btn.onClick()
    lastButtonTime = love.timer.getTime()
    Haptics.tap()
    return true
end

-- Navigate to a screen, auto-saving the previous screen for BACK buttons
function goToScreen(newScreen)
    goBackTo = SCREEN
    SCREEN = newScreen
end

-- ── PIN STATE ──
-- Sprite rotate: image to show in the rotate screen (falls back to tendyImage)
rotateSpriteImage = nil

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
        ["btn-cancel"] = "cancelButton",
        ["btn-cross"] = "cross",
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

function pickPresident()
    -- Load saved features and settings for this user
    loadUserFeatures(playerInitials)
    -- Re-enable threshold-0 features that loadUserFeatures may have reset
    refreshFeatureVisibility()
    if users[playerInitials] then
        local u = users[playerInitials]
        if u.chartDisplay then chartDisplay = u.chartDisplay end
        if u.xerMAType then xerMAType = u.xerMAType; xerMAPeriod = u.xerMAPeriod end
        if u.xeeMAType then xeeMAType = u.xeeMAType; xeeMAPeriod = u.xeeMAPeriod end
    end
end

-- ── SCREENS ──
function drawWelcome(w, h)
    -- Reset all game state when returning to welcome
    switchPreserveIndex = nil
    switchPreserveDayFile = nil
    startingBalance = 10000
    realizedPnl = 0
    pnl = 0
    tendies = 1.0
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
    speedMult = 1.0  -- default 1.0x
    buyStopHeld = false
    sellStopHeld = false
    stopRepeatTimer = 0
    rewindHeld = false
    forwardHeld = false
    rewindButtonWasHeld = false
    rewindUnlocked = false
    avatarOffX = 0
    avatarOffY = 0
end

function drawSelector(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    Buttons = {}
    local prev = love.graphics.getFont()
    
    -- Title (big, like "YOUR INITIALS")
    if fonts.default99 then love.graphics.setFont(fonts.default99) end
    Button.printfWithHalo("CHOOSE INSTRUMENT", 0, h * 0.055, w, "center", unpack(theme.color.gold))

    -- Day and total (bottom of screen, same padding as BACK button)
    
    local items = { "RANDOM", "EASY" }
    local sorted = {}
    for g, _ in pairs(groups) do table.insert(sorted, g) end
    table.sort(sorted)
    for _, g in ipairs(sorted) do table.insert(items, g) end
    
    local cols = 4
    local gap = sx(14)
    local btnW = sx(300)
    local btnH = sy(110)
    local gridW = cols * btnW + (cols - 1) * gap
    local startX = (w - gridW) / 2
    local startY = h * 0.2
    
    for i, name in ipairs(items) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local bx = startX + col * (btnW + gap)
        local by = startY + row * (btnH + gap)
        regButton("sel_" .. name, bx, by, btnW, btnH, name, nil, function() startGame(name) end)
        local isR = (name == "RANDOM")
        if isR then
            love.graphics.setColor(0.48, 0.41, 0.93)
            love.graphics.rectangle("line", bx, by, btnW, btnH, sy(7.5))
            if btnActionFont then love.graphics.setFont(btnActionFont) end
            Button.printfWithHalo(name, bx, by + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.48, 0.41, 0.93)
        else
            love.graphics.setColor(0.12, 0.14, 0.16)
            love.graphics.rectangle("line", bx, by, btnW, btnH, sy(7.5))
            if btnActionFont then love.graphics.setFont(btnActionFont) end
            Button.printfWithHalo(name, bx, by + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.78, 0.83, 0.88)
        end
    end
    
    -- Utility row: PINS, SCORES, DEMO, HELP, SETTINGS, GIMMICKS (6 items, evenly spread)
    local lastIdx = #items
    local utilRow = math.floor(lastIdx / cols)
    local utilGap = sx(14)
    local utilCols = 6
    local utilBtnW = sx(230)
    local utilBtnH = sy(85)
    local utilGridW = utilCols * utilBtnW + (utilCols - 1) * utilGap
    local utilStartX = (w - utilGridW) / 2
    local utilY = startY + (utilRow + 1) * (btnH + gap) + sy(10)
    
    local utils = {
        { id = "PINS", label = "PINS", r = 0.85, g = 0.65, b = 0.10,
          onClick = function() goToScreen(SCREENS.PINS) end },
        { id = "HIGHSCORES", label = "SCORES", r = 0, g = 0.78, b = 0.41,
          onClick = function() loadHighScores(); goToScreen(SCREENS.HIGHSCORELIST) end },
        { id = "DEMO", label = "DEMO", r = 0.91, g = 0.25, b = 0.38,
          onClick = function() goToScreen(SCREENS.DEMO) end },
        { id = "INSTRUCTIONS", label = "HELP", r = 0.35, g = 0.42, b = 0.80,
          onClick = function() goToScreen(SCREENS.INSTRUCTIONS) end },
        { id = "SETTINGS", label = "SETTINGS", r = 0.48, g = 0.41, b = 0.93,
          onClick = function() goToScreen(SCREENS.SETTINGS) end },
        { id = "GIMMICKS", label = "GIMMICKS", r = 0.70, g = 0.30, b = 0.85,
          onClick = function() goToScreen(SCREENS.GIMMICKS) end,
          debug = true },
    }
    local debugMode = instrumentConfig and instrumentConfig.debug and instrumentConfig.debug.unlockAll
    local visibleIdx = 0
    for _, util in ipairs(utils) do
        if util.debug and not debugMode then
            -- skip debug-only buttons when not in debug mode
        else
            local ux = utilStartX + visibleIdx * (utilBtnW + utilGap)
            local btn = regButton("sel_" .. util.id, ux, utilY, utilBtnW, utilBtnH, util.label, nil, util.onClick)
            if util.locked then btn.locked = true end
            love.graphics.setColor(util.r, util.g, util.b)
            love.graphics.setLineWidth(math.max(1, sy(3)))
            love.graphics.rectangle("line", ux, utilY, utilBtnW, utilBtnH, sy(7.5))
            love.graphics.setLineWidth(math.max(1, sy(1.5)))
            if btnActionFont then love.graphics.setFont(btnActionFont) end
            Button.printfWithHalo(util.label, ux, utilY + (utilBtnH - btnActionFont:getHeight()) / 2, utilBtnW, "center", util.r, util.g, util.b)
            visibleIdx = visibleIdx + 1
        end
    end
    
    -- Day and total (bottom center, same padding as BACK)
    local dayName = weekDays[currentDay] or "MONDAY"
    local totalBalance = (startingBalance or 10000) + (realizedPnl or 0)
    local botFont = fonts.default36
    love.graphics.setFont(botFont)
    love.graphics.setColor(0.50, 0.50, 0.55)
    love.graphics.printf("This is " .. dayName .. " and our balance is " .. string.format("$%.2f", totalBalance), 0, h - sy(30) - botFont:getHeight(), w, "center")

    -- BACK button (bottom-right)
    local backW, backH = sx(240), sy(92)
    local backX = w - backW - sx(30)
    local backY = h - backH - sy(30)
    regButton("sel_back", backX, backY, backW, backH, "", nil, function()
        switchPreserveIndex = nil
        switchPreserveDayFile = nil
        if goBackTo then
            SCREEN = goBackTo
            goBackTo = nil
        else
            SCREEN = SCREENS.CANVAS
        end
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)

    -- CANVAS button (bottom-left, same size as BACK)
    local cW, cH = sx(240), sy(92)
    local cX = sx(30)
    regButton("sel_canvas", cX, backY, cW, cH, "", nil, function()
        switchPreserveIndex = nil
        switchPreserveDayFile = nil
        goToScreen(SCREENS.CANVAS)
    end)
    love.graphics.setColor(0.50, 0.50, 0.55)
    love.graphics.rectangle("line", cX, backY, cW, cH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CANVAS", cX, backY + (cH - btnActionFont:getHeight()) / 2, cW, "center", 0.50, 0.50, 0.55)

    love.graphics.setFont(prev)
end

-- ── DEMO SELECTOR ──
function drawDemo(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    Buttons = {}
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CHOOSE DEMO", 0, h * 0.08, w, "center", 0.91, 0.25, 0.38)
    
    local scripts = Replay.scripts
    local cols = 2
    local gap = sx(15)
    local btnW = math.min(sx(420), (w - sx(150) - gap * (cols - 1)) / cols)
    local btnH = sy(90)
    local gridW = cols * btnW + (cols - 1) * gap
    local startX = (w - gridW) / 2
    local startY = h * 0.2
    
    for i, script in ipairs(scripts) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local bx = startX + col * (btnW + gap)
        local by = startY + row * (btnH + gap)
        regButton("demo_" .. i, bx, by, btnW, btnH, script.name, nil, function()
            startDemo(i)
        end)
        love.graphics.setColor(0.91, 0.25, 0.38)
        love.graphics.setLineWidth(math.max(1, sy(3)))
        love.graphics.rectangle("line", bx, by, btnW, btnH, sy(7.5))
        love.graphics.setLineWidth(math.max(1, sy(1.5)))
        Button.printfWithHalo(script.name, bx, by + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", unpack(theme.color.gold))
    end
    
    -- BACK button
    local backW, backH = sx(240), sy(92)
    local backX = w - backW - sx(30)
    local backY = h - backH - sy(30)
    regButton("demo_back", backX, backY, backW, backH, "", nil, function()
        goToScreen(SCREENS.SELECTOR)
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(7.5))
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)
    
    love.graphics.setFont(prev)
end

function handleDemoClick(mx, my)
    for id, b in pairs(Buttons) do
        if id:find("^demo_") and Button.hit(b, mx, my) then
            safeButtonClick(b)
            return
        end
    end
    for id, b in pairs(Buttons) do
        if id == "demo_back" and Button.hit(b, mx, my) then
            safeButtonClick(b)
            return
        end
    end
end

-- ── ALGOS OVERLAY (on top of trading screen) ──
function drawAlgosOverlay(w, h)
    Buttons = {}  -- fresh buttons for overlay (trading buttons still underneath)
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end

    -- Dimmed background
    love.graphics.setColor(0.02, 0.03, 0.04, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, h)

    Button.printfWithHalo("ALGOS", 0, h * 0.06, w, "center", 0.48, 0.41, 0.93)

    local algos = (instrumentConfig and instrumentConfig.algos) or {}
    local cols = 3
    local gap = sx(15)
    local btnW = math.min(sx(260), (w - sx(120) - gap * (cols - 1)) / cols)
    local btnH = sy(120)
    local gridW = cols * btnW + (cols - 1) * gap
    local startX = (w - gridW) / 2
    local startY = h * 0.18

    for i, algo in ipairs(algos) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local bx = startX + col * (btnW + gap)
        local by = startY + row * (btnH + gap)
        local unlocked = isFeatureUnlocked(algo.key)

        regButton("algo_" .. algo.key, bx, by, btnW, btnH, "", nil, unlocked and function()
            if activeAlgos[algo.key] then
                activeAlgos[algo.key] = nil
                -- CROSS off: reset to OFF mode so it stops trading
                if algo.key == "cross" then
                    crossIndex = 1
                end
            else
                activeAlgos[algo.key] = true
                -- CROSS on: cycle to next mode
                if algo.key == "cross" then
                    crossIndex = (crossIndex % #crossValues) + 1
                end
            end
        end or nil)

        local isActive = unlocked and activeAlgos[algo.key]
        if isActive then
            -- Active: bright accent fill with white border
            local ar, ag, ab = algo.color[1], algo.color[2], algo.color[3]
            love.graphics.setColor(ar, ag, ab, 0.85)
            love.graphics.rectangle("fill", bx, by, btnW, btnH, sy(7.5))
            love.graphics.setColor(1, 1, 1, 0.95)
            love.graphics.setLineWidth(math.max(1, sy(3)))
            love.graphics.rectangle("line", bx, by, btnW, btnH, sy(7.5))
            love.graphics.setLineWidth(math.max(1, sy(1.5)))
            -- Brighter white text with glow
            local numLines = 1
            for _ in algo.label:gmatch("\n") do numLines = numLines + 1 end
            local labelH = btnActionFont:getHeight() * numLines
            Button.printfWithHalo(algo.label, bx, by + (btnH - labelH) / 2, btnW, "center", 1, 1, 1)
        elseif unlocked then
            -- Unlocked but off: colored border, dark fill
            local ar, ag, ab = algo.color[1], algo.color[2], algo.color[3]
            love.graphics.setColor(ar, ag, ab, 0.3)
            love.graphics.rectangle("fill", bx, by, btnW, btnH, sy(7.5))
            love.graphics.setColor(ar, ag, ab, 0.8)
            love.graphics.setLineWidth(math.max(1, sy(2.25)))
            love.graphics.rectangle("line", bx, by, btnW, btnH, sy(7.5))
            love.graphics.setLineWidth(math.max(1, sy(1.5)))
            local numLines = 1
            for _ in algo.label:gmatch("\n") do numLines = numLines + 1 end
            local labelH = btnActionFont:getHeight() * numLines
            Button.printfWithHalo(algo.label, bx, by + (btnH - labelH) / 2, btnW, "center", 1, 1, 1)
        else
            love.graphics.setColor(0.25, 0.28, 0.32)
            love.graphics.rectangle("line", bx, by, btnW, btnH, sy(7.5))
            love.graphics.setColor(0.45, 0.45, 0.45)
            if btnActionFont then love.graphics.setFont(btnActionFont) end
            local numLines = 1
            for _ in algo.label:gmatch("\n") do numLines = numLines + 1 end
            local labelH = btnActionFont:getHeight() * numLines
            love.graphics.printf(algo.label, bx, by + (btnH - labelH) / 2, btnW, "center")
            if padlockImage then
                local plSize = 20
                love.graphics.setColor(1, 1, 1, 0.5)
                love.graphics.draw(padlockImage, bx + btnW - plSize - 4, by + 4, 0, plSize / padlockImage:getWidth(), plSize / padlockImage:getHeight())
            end
        end
    end

    -- BACK / CLOSE button
    local backW, backH = sx(200), sy(84)
    local backX = w - backW - sx(30)
    local backY = h - backH - sy(30)
    regButton("algo_back", backX, backY, backW, backH, "", nil, function()
        algosOverlayVisible = false
        tickPaused = false
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)

    love.graphics.setFont(prev)
end

-- ── QUIT CONFIRMATION OVERLAY ──
function drawQuitOverlay(w, h)
    Buttons = {}
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end

    -- Dimmed background
    love.graphics.setColor(0.02, 0.03, 0.04, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Build list of traded days
    local traded = {}
    for d = 1, currentDay - 1 do
        table.insert(traded, weekDays[d])
    end
    local tradedStr = table.concat(traded, ", ")
    local currentDayName = weekDays[currentDay] or "MONDAY"

    -- Title
    Button.printfWithHalo("ARE YOU SURE?", 0, h * 0.20, w, "center", 0.91, 0.25, 0.38)

    -- Body text
    local bodyFont = fonts.default33
    love.graphics.setFont(bodyFont)
    love.graphics.setColor(0.78, 0.83, 0.88)

    local total = (startingBalance or 10000) + (realizedPnl or 0)
    local rp = realizedPnl or 0
    local pnlStr = rp >= 0 and string.format("+$%.2f", rp) or string.format("-$%.2f", math.abs(rp))

    local msg
    if #traded > 0 then
        msg = "You traded " .. tradedStr .. "\nand this is " .. currentDayName .. "."
    else
        msg = "This is " .. currentDayName .. "."
    end
    msg = msg .. "\n\nRealized: " .. pnlStr
    msg = msg .. "\nTotal: " .. string.format("$%.2f", total)
    msg = msg .. "\n\nAre you sure you want to quit\nto the main screen?"

    local lines = {}
    for line in msg:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    local lineH = bodyFont:getHeight()
    local totalH = #lines * lineH
    local textY = h * 0.35
    for i, line in ipairs(lines) do
        love.graphics.printf(line, sx(100), textY + (i - 1) * lineH, w - sx(200), "center")
    end

    -- YES button
    local btnW, btnH = sx(260), sy(80)
    local gap = sx(40)
    local totalBW = btnW * 2 + gap
    local startX = w / 2 - totalBW / 2
    local btnY = h * 0.62

    regButton("quit_yes", startX, btnY, btnW, btnH, "", nil, function()
        showQuitOverlay = false
        tickPaused = false
        canvasPositionsLoaded = false
        goToScreen(SCREENS.CANVAS)
    end)
    love.graphics.setColor(0.91, 0.25, 0.38)
    love.graphics.rectangle("line", startX, btnY, btnW, btnH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("YES", startX, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.91, 0.25, 0.38)

    -- NO button
    regButton("quit_no", startX + btnW + gap, btnY, btnW, btnH, "", nil, function()
        showQuitOverlay = false
        tickPaused = false
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", startX + btnW + gap, btnY, btnW, btnH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("NO", startX + btnW + gap, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.35, 0.42, 0.48)

    love.graphics.setFont(prev)
end

-- ── SWITCH INSTRUMENT OVERLAY ──
function drawSwitchOverlay(w, h)
    Buttons = {}
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end

    -- Dimmed background
    love.graphics.setColor(0.02, 0.03, 0.04, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Title
    Button.printfWithHalo("CHANGE INSTRUMENT?", 0, h * 0.25, w, "center", 0.94, 0.71, 0.16)

    -- Body text
    local bodyFont = fonts.default33
    love.graphics.setFont(bodyFont)
    love.graphics.setColor(0.78, 0.83, 0.88)

    local lines = {
        "Changing instrument mid-day",
        "closes your current position.",
        "",
        "Are you sure?",
    }
    local lineH = bodyFont:getHeight()
    local textY = h * 0.38
    for i, line in ipairs(lines) do
        love.graphics.printf(line, sx(100), textY + (i - 1) * lineH, w - sx(200), "center")
    end

    -- YES button
    local btnW, btnH = sx(260), sy(80)
    local gap = sx(40)
    local totalBW = btnW * 2 + gap
    local startX = w / 2 - totalBW / 2
    local btnY = h * 0.60

    regButton("sw_yes", startX, btnY, btnW, btnH, "", nil, function()
        closeAllPositions()
        switchPreserveIndex = csvIndex
        switchPreserveDayFile = csvDayFile
        showSwitchOverlay = false
        tickPaused = false
        switchOverlayTimer = 1.0
    end)
    love.graphics.setColor(0.91, 0.25, 0.38)
    love.graphics.rectangle("line", startX, btnY, btnW, btnH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("YES", startX, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.91, 0.25, 0.38)

    -- NO button
    regButton("sw_no", startX + btnW + gap, btnY, btnW, btnH, "", nil, function()
        showSwitchOverlay = false
        tickPaused = false
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", startX + btnW + gap, btnY, btnW, btnH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("NO", startX + btnW + gap, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.35, 0.42, 0.48)

    love.graphics.setFont(prev)
end

function handleAlgosOverlayClick(mx, my)
    if Buttons["algo_back"] and Button.hit(Buttons["algo_back"], mx, my) then
        Buttons["algo_back"].onClick()
        return
    end
    for id, b in pairs(Buttons) do
        if id:find("^algo_") and Button.hit(b, mx, my) and b.onClick then
            safeButtonClick(b)
            return
        end
    end
end

-- ── TUTORIAL OVERLAY ──
function drawTrading(w, h)
    Buttons = {}
    local prevFont = love.graphics.getFont()
    drawTopBar(w, h)
    drawChartPanel(w, h)
    drawSidePanels(w, h)
    local showBetting = false
    if showBetting then drawBettingPanel(w, h) end
    drawBottomBar(w, h)
    love.graphics.setFont(prevFont)
    drawTendyOverlay(w, h)
end

-- ── TOP BAR ──
function drawTopBar(w, h)
    local topH = TOPBAR_H
    
    -- Top bar pill
    love.graphics.setColor(0.07, 0.08, 0.09)
    love.graphics.rectangle("fill", 0, sy(9), w, topH - sy(9), PILL_R)
    love.graphics.setColor(0.78, 0.83, 0.88, 0.25)
    love.graphics.setLineWidth(math.max(1, sy(1.5)))
    love.graphics.rectangle("line", 0, sy(9), w, topH - sy(9), PILL_R)
    
    if topFont then love.graphics.setFont(topFont) end
    
    local instNameW = sx(255)
    regButton("btn-instrument", PILL_R + sx(21), sy(8), instNameW, topH, "", nil, function()
        if dataMode then
            showSwitchOverlay = true
            tickPaused = true
        end
    end)
    local cy = sy(9) + (topH - sy(9)) / 2 - 3
    
    local text = instrumentText or "RANDOM"
    local instFont, instFontSize = fitFont(text, instNameW - sx(6))
    love.graphics.setFont(instFont)
    local ifh = instFont:getHeight()
    Button.printfWithHalo(text, PILL_R + sx(21), cy - ifh / 2, instNameW, "left", unpack(theme.color.gold))
    love.graphics.setFont(topFont)
    
    midStart = PILL_R + sx(21) + instNameW + sx(30)
    
    -- Avatar square
    local avSize = topH - sy(36)
    local avX = w - PILL_R - avSize - sy(18) + avatarOffX
    local avY = sy(9) + (topH - sy(9) - avSize) / 2 + avatarOffY
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
    love.graphics.setLineWidth(math.max(1, sy(2.25)))
    love.graphics.rectangle("line", avX, avY, avSize, avSize, PILL_R)
    love.graphics.setLineWidth(math.max(1, sy(1.5)))
    
    local midEnd = avX - sx(30)
    local midW = midEnd - midStart
    local colW = midW / 6
    local totalColW = colW * 1.5
    
    local sFont = fonts.default36
    local pillTopY = sy(9)
    local labelY = pillTopY + sy(4.5)
    local numberY = labelY + sy(36) + sy(1.5)
    
    -- AKS
    love.graphics.setFont(sFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    love.graphics.print("AKS", midStart + sx(21), labelY)
    love.graphics.setFont(headerValueBigFont)
    love.graphics.setColor(1, 0, 0)
    love.graphics.printf(string.format("%.2f", currentAsk), midStart + sx(21), numberY, colW - sx(21) - sx(15), "left")
    
    -- DIB
    love.graphics.setFont(sFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    love.graphics.print("DIB", midStart + colW + sx(21), labelY)
    love.graphics.setFont(headerValueBigFont)
    love.graphics.setColor(0, 1, 0.1)
    love.graphics.printf(string.format("%.2f", currentBid), midStart + colW + sx(21), numberY, colW - sx(21) - sx(15), "left")
    
    -- Betting P&L
    local bpnl = bettingPnl or 0
    if bullBetPct > 0 then
        local ba = math.floor(startingBalance * bullBetPct / 100)
        local eo = bullEntryCount > 0 and (bullEntryOddsSum / bullEntryCount) or 0.5
        local co = currentBullOdds or 0
        bpnl = bpnl + ((eo > 0 and math.floor(ba * co / eo) or 0) - ba)
    end
    if bearBetPct > 0 then
        local ba = math.floor(startingBalance * bearBetPct / 100)
        local eo = bearEntryCount > 0 and (bearEntryOddsSum / bearEntryCount) or 0.5
        local co = currentBearOdds or 0
        bpnl = bpnl + ((eo > 0 and math.floor(ba * co / eo) or 0) - ba)
    end
    local total = startingBalance + pnl + realizedPnl + (bpnl - (bettingPnl or 0))
    local smallFont = fonts.default36
    
    -- UNREGARDED
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    love.graphics.print("UNREGARDED", midStart + colW * 2 + sx(21), labelY)
    love.graphics.setFont(headerValueBigFont)
    if pnl == 0 then love.graphics.setColor(0.55, 0.55, 0.60) else love.graphics.setColor(pnl > 0 and 0 or 1, pnl > 0 and 1 or 0, pnl > 0 and 0.1 or 0) end
    love.graphics.printf(fmtPnl(pnl), midStart + colW * 2 + sx(21), numberY, colW - sx(21) - sx(15), "left")
    
    -- REGARDED
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    love.graphics.print("REGARDED", midStart + colW * 3 + sx(21), labelY)
    love.graphics.setFont(headerValueBigFont)
    if realizedPnl == 0 then love.graphics.setColor(0.55, 0.55, 0.60) else love.graphics.setColor(realizedPnl > 0 and 0 or 1, realizedPnl > 0 and 1 or 0, realizedPnl > 0 and 0.1 or 0) end
    love.graphics.printf(fmtPnl(realizedPnl), midStart + colW * 3 + sx(21), numberY, colW - sx(21) - sx(15), "left")
    
    -- BETS
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    love.graphics.print("BETS", midStart + colW * 4 + sx(21), labelY)
    love.graphics.setFont(headerValueBigFont)
    if bpnl == 0 then love.graphics.setColor(0.55, 0.55, 0.60) else love.graphics.setColor(bpnl > 0 and 0 or 1, bpnl > 0 and 1 or 0, bpnl > 0 and 0.1 or 0) end
    love.graphics.printf(fmtPnl(bpnl), midStart + colW * 4 + sx(21), numberY, colW - sx(21) - sx(15), "left")
    
    -- $TOTAL
    local totalStr
    if total >= 1000000 then totalStr = "$1M"
    elseif total >= 100000 then totalStr = string.format("$%sK", fmtMoney(math.floor(total / 1000)))
    else totalStr = "$" .. fmtMoney(total) end
    local totalAvailW = totalColW - sx(21) - sx(15)
    local totalFont, totalFontSize = fitFont(totalStr, totalAvailW)
    love.graphics.setFont(totalFont)
    local totalFh = totalFont:getHeight()
    love.graphics.setColor((total - startingBalance) >= 0 and 0 or 1, (total - startingBalance) >= 0 and 1 or 0, (total - startingBalance) >= 0 and 0.1 or 0)
    love.graphics.printf(totalStr, midStart + colW * 5 + sx(21), cy - totalFh / 2 + 2, totalAvailW, "left")
end

-- ── CHART PANEL ──
function drawChartPanel(w, h)
    local vsW = sx(99)
    local vsY = chartY
    local vsH = chartH
    
    local savedChartX = chartX
    local savedChartW = chartW
    chartX = chartX + vsW + sx(6)
    chartW = chartW - vsW * 2 - sx(12)
    narrowChartX = chartX
    narrowChartW = chartW
    useNarrowChartW = true  -- flag for ball physics to use narrowed width
    
    drawChart()
    
    -- Left vertical sliders: DEGENERACY (top half) + SCOPE (bottom half)
    if levSlider then
        local halfH = (vsH - sy(6)) / 2
        levSlider.x = savedChartX
        levSlider.y = vsY
        levSlider.w = vsW
        levSlider.h = halfH
        Slider.drawVertical(levSlider, "DEGENERACY", (leverage or 1) .. "x")
    end
    if scopeSlider then
        local halfH = (vsH - sy(6)) / 2
        scopeSlider.x = savedChartX
        scopeSlider.y = vsY + halfH + sy(6)
        scopeSlider.w = vsW
        scopeSlider.h = halfH
        Slider.drawVertical(scopeSlider, "SCOPE", "")
    end
    
    -- Right vertical sliders: THRUST (top half) + BAGS (bottom half)
    if speedSlider then
        local rvsX = savedChartX + savedChartW - vsW
        local halfH = (vsH - sy(6)) / 2
        local eff = effectiveSpeedMult or 0.6
        local ghostVal = thrustRampActive and (math.log10(eff) + 0.5229) / 1.5229 or nil
        speedSlider.x = rvsX
        speedSlider.y = vsY
        speedSlider.w = vsW
        speedSlider.h = halfH
        Slider.drawVertical(speedSlider, "THRUST", string.format("%.1fx", speedMult or 1), ghostVal)
    end
    if iterSlider then
        local rvsX = savedChartX + savedChartW - vsW
        local halfH = (vsH - sy(6)) / 2
        iterSlider.x = rvsX
        iterSlider.y = vsY + halfH + sy(6)
        iterSlider.w = vsW
        iterSlider.h = halfH
        Slider.drawVertical(iterSlider, "BAGS", (tradeIterations or 1) .. "x")
    end
    
    chartX = savedChartX
    chartW = savedChartW
    
    -- Tendies display
    tendyHitAreas = {}
    if tendyImage then
        local innerChartX = savedChartX + vsW + sx(6)
        local innerChartW = savedChartW - vsW * 2 - sx(12)
        local tendyH = sy(84)
        local tw, th = tendyImage:getDimensions()
        local tendyScale = tendyH / th
        local tendyW = tw * tendyScale
        local overlapPct = 0.65
        local tendyStep = tendyW * (1 - overlapPct)
        local wholeTendies = math.floor(tendies)
        local frac = tendies - wholeTendies
        local totalIcons = wholeTendies + (frac > 0.001 and 1 or 0)
        local rightEdge = innerChartX + innerChartW - sx(9)
        local tendiesX = rightEdge - tendyW - (totalIcons - 1) * tendyStep
        local tendiesY = vsY + sy(9)
        for i = 0, totalIcons - 1 do
            local tx = tendiesX + i * tendyStep
            table.insert(tendyHitAreas, { x = tx, y = tendiesY, w = tendyW, h = tendyH, idx = i })
            if not (tendyDragActive and tendyDragSlot == i) then
                local alpha = (i == totalIcons - 1 and frac > 0.001) and frac or 1.0
                love.graphics.setColor(1, 1, 1, alpha)
                love.graphics.draw(tendyImage, tx, tendiesY, 0, tendyScale, tendyScale)
            end
        end
    end
    
    -- Rewind button
    if dataMode and (rewindUnlocked or (rewindTicks or 0) > 0) and (rewindTicks or 0) < REWIND_MAX_TICKS then
        local innerChartX = savedChartX + vsW + sx(6)
        local rwW = sx(210)
        local rwH = sy(72)
        local rwX = innerChartX + sx(12)
        local rwY = vsY + sy(12)
        regButton("btn-rewind", rwX, rwY, rwW, rwH, "REWIND", nil, function() end)
        love.graphics.setColor(0.91, 0.25, 0.38, 0.85)
        love.graphics.rectangle("fill", rwX, rwY, rwW, rwH, sy(9))
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle("line", rwX, rwY, rwW, rwH, sy(9))
        if btnActionFont then love.graphics.setFont(btnActionFont) end
        local fh = btnActionFont:getHeight()
        Button.printfWithHalo("REWIND", rwX, rwY + (rwH - fh) / 2, rwW, "center", 1, 1, 1)
    end
end

-- ── SIDE PANELS ──
function drawSidePanels(w, h)
    local padX, gap = sx(12), sy(12)
    local chartTop = TOPBAR_H + sy(12)
    local chartBot = h - BOTBAR_H - sy(9) - sy(12)
    local chartH = chartBot - chartTop
    local panelY = chartTop
    local btnH = math.floor((chartH - gap * 4) / 4.5)
    local halfH = math.floor(btnH / 2)
    
    -- Left panel
    local lx = padX
    local bigBtnFont = fonts.default99
    regButton("btn-sell", lx, panelY, PANEL_W - padX * 2, btnH, "SELL", nil, { onClick = manualSell, font = bigBtnFont })
    drawBtnBox("btn-sell", 0.72, 0.19, 0.30, 0.45, 0.05, 0.05)
    regButton("btn-sell-stop", lx, panelY + (btnH + gap), PANEL_W - padX * 2, btnH, "SELL STOP", nil, createSellStop)
    drawBtnBox("btn-sell-stop", 0.15, 0.15, 0.20, 0.72, 0.19, 0.30, 0.72, 0.19, 0.30)
    regButton("btn-sl", lx, panelY + (btnH + gap) * 2, PANEL_W - padX * 2, btnH, "PL STOP", nil, createPLStop)
    drawBtnBox("btn-sl", 0.15, 0.15, 0.20, 0.78, 0.60, 0.13, 0.78, 0.60, 0.13)
    regButton("btn-cancel", lx, panelY + (btnH + gap) * 3, PANEL_W - padX * 2, btnH, "CANCEL STOPS", nil, removeAllOrderLines)
    drawBtnBox("btn-cancel", 0.15, 0.15, 0.20, 0.35, 0.42, 0.48, 0.35, 0.42, 0.48)
    local halfH2 = math.floor(btnH / 2)
    local bottomY = panelY + (btnH + gap) * 4
    regButton("btn-settings", lx, bottomY, PANEL_W - padX * 2, halfH2, "SETTINGS", nil, function()
        goBackTo = SCREEN; goToScreen(SCREENS.SETTINGS)
    end)
    drawBtnBox("btn-settings", 0.15, 0.15, 0.20, 0.60, 0.60, 0.65, 0.60, 0.60, 0.65)
    
    -- Right panel
    local rx = w - PANEL_W + padX
    regButton("btn-buy", rx, panelY, PANEL_W - padX * 2, btnH, "BUY", nil, { onClick = manualBuy, font = bigBtnFont })
    drawBtnBox("btn-buy", 0, 0.78, 0.41, 0.05, 0.40, 0.15)
    regButton("btn-buy-stop", rx, panelY + (btnH + gap), PANEL_W - padX * 2, btnH, "BUY STOP", nil, createBuyStop)
    drawBtnBox("btn-buy-stop", 0.15, 0.15, 0.20, 0, 0.78, 0.41, 0, 0.78, 0.41)
    regButton("btn-flat", rx, panelY + (btnH + gap) * 2, PANEL_W - padX * 2, btnH, "CLOSE POSTN", nil, manualClose)
    drawBtnBox("btn-flat", 0.15, 0.15, 0.20, 0.50, 0.50, 0.52, 0.69, 0.69, 0.69)
    regButton("btn-cross", rx, panelY + (btnH + gap) * 3, PANEL_W - padX * 2, btnH, "ALGOS", nil, function()
        algosOverlayVisible = not algosOverlayVisible
        if algosOverlayVisible then
            tickPaused = true
        else
            tickPaused = false
        end
    end)
    drawBtnBox("btn-cross", 0.15, 0.15, 0.20, 0.48, 0.41, 0.93, 0.48, 0.41, 0.93)
    local quitLabel = Replay.active and "EXIT" or "QUIT"
    regButton("btn-quit", rx, bottomY, PANEL_W - padX * 2, halfH2, quitLabel, nil, function()
        if Replay.active then
            Replay.stop()
            tickPaused = false
            SCREEN = SCREENS.SELECTOR
            goBackTo = nil
        else
            showQuitOverlay = true
            tickPaused = true
        end
    end)
    drawBtnBox("btn-quit", 0.15, 0.15, 0.20, 0.91, 0.25, 0.38, 0.91, 0.25, 0.38)
end

-- ── BOTTOM BAR ──
function drawBottomBar(w, h)
    local botH = BOTBAR_H
    -- Bottom bar pill
    love.graphics.setColor(0.07, 0.08, 0.09)
    love.graphics.rectangle("fill", 0, h - botH - sy(9), w, botH, PILL_R)
    love.graphics.setColor(0.78, 0.83, 0.88, 0.25)
    love.graphics.setLineWidth(math.max(1, sy(1.5)))
    love.graphics.rectangle("line", 0, h - botH - sy(9), w, botH, PILL_R)
    
    -- Position label (left)
    local posW = sx(180)
    local posX = APP_PAD + sx(21)
    local posLabel = position == 0 and "FLAT" or (position > 0 and "LONG" or "SHORT")
    local posR, posG, posB = position == 0 and 0.35 or (position > 0 and 0 or 1),
                              position == 0 and 0.42 or (position > 0 and 1 or 0),
                              position == 0 and 0.48 or (position > 0 and 0.1 or 0)
    -- Auto-size position label font
    local posFont, posFontSize = fitFont(posLabel, posW - sx(6))
    love.graphics.setFont(posFont)
    local posFh = posFont:getHeight()
    Button.printfWithHalo(posLabel, posX, (h - botH - sy(9)) + (botH - posFh) / 2 - 1, posW, "left", posR, posG, posB)
    
    -- Heartbeat (before day-of-week, synced to music BPM)
    local heartSize = sy(42)
    local heartSpace = heartSize * 1.4 + sx(9)
    local dayW = sx(225)
    local dayX = w - PILL_R
    local heartCX = dayX - dayW - heartSpace / 2 - sx(12)
    local heartCY = (h - botH - sy(9)) + botH / 2 - 3
    -- Load heart sprite on first draw
    if not heartImage then
        local ok, img = pcall(love.graphics.newImage, "sprites/heart.png")
        if ok then heartImage = img end
    end
    if heartImage then
        local iw, ih = heartImage:getDimensions()
        local baseScale = heartSize / ih
        local beatScale = heartBeatScale or 1.0
        local finalScale = baseScale * beatScale
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(heartImage, heartCX, heartCY, 0, finalScale, finalScale, iw / 2, ih / 2)
    end
    
    -- Day display (right) — wider to fit "Wednesday", right-aligned
    if currentDay and weekDays then
        local dayStr = weekDays[currentDay] or ""
        if dayStr ~= "" then
            local dayFont, dayFontSize = fitFont(dayStr, dayW - sx(6))
            local prev = love.graphics.getFont()
            love.graphics.setFont(dayFont)
            local dayFh = dayFont:getHeight()
            Button.printfWithHalo(dayStr, dayX - dayW, (h - botH - sy(9)) + (botH - dayFh) / 2 - 1, dayW, "right", 0.30, 0.60, 0.95)
            love.graphics.setFont(prev)
        end
    end
    
    -- Middle space: CHUNKS, THRUST, BAGS, DEGENERACY values
    local fMidStart = posX + posW + sx(15)
    local fMidEnd = w - PILL_R - dayW - heartSpace - sx(15)
    local fMidW = fMidEnd - fMidStart
    local nCols = 6
    local colW = fMidW / nCols
    
    local bCy = (h - botH - sy(9)) + botH / 2 - 3
    local bSmallFont = fonts.default36
    local bPillTopY = h - botH - sy(9)
    local bLabelY = bPillTopY + sy(4.5)
    local bNumberY = bLabelY + sy(36) + sy(1.5)
    
    local labelW = sx(27)
    local valueW = sx(96)
    
    -- Draw an info column in the bottom bar: label (white) + value (colored)
    local function drawInfoCol(label, val, colIdx, cr, cg, cb)
        local cx = fMidStart + (colIdx + 0.5) * colW
        love.graphics.setFont(bSmallFont)
        love.graphics.setColor(0.90, 0.90, 0.93)
        love.graphics.print(label, cx - colW / 2 + sx(21), bLabelY)
        love.graphics.setFont(headerValueBigFont)
        love.graphics.setColor(cr, cg, cb)
        love.graphics.printf(tostring(val), cx - colW / 2 + sx(21), bNumberY, colW - sx(21), "left")
    end
    -- Gradient colors for values (green→red, matching slider direction)
    local function gradientColor(cf)
        return cf, cf <= 0.3 and 1 or 1 - (cf - 0.3) / 0.7, 0
    end
    local thrustCf = (speedSlider and speedSlider.value) or 0.5
    local bagsCf = iterSlider and (5 - iterSlider.value) / 4 or 0.5
    local degCf = levSlider and (levSlider.value - 1) / 19 or 0.5
    
    local chunks = math.abs(position or 0)
    if position == 0 then
        drawInfoCol("CHUNKS", chunks, 0, 0.55, 0.55, 0.60)
    elseif position > 0 then
        drawInfoCol("CHUNKS", chunks, 0, 0, 1, 0.1)
    else
        drawInfoCol("CHUNKS", chunks, 0, 1, 0, 0)
    end
    drawInfoCol("THRUST", string.format("%.1fx", speedMult or 1), 1, gradientColor(thrustCf))
    drawInfoCol("BAGS", tradeIterations or 1, 2, gradientColor(bagsCf))
    drawInfoCol("DEGENERACY", (leverage or 1) .. "x", 3, gradientColor(degCf))

    -- SCOPE info
    local SCOPE_VALUES = {180, 360, 720, 1440, 999999}
    local scopeLabels = {"15M", "30M", "1H", "2H", "ALL"}
    local scopeIdx = 3
    for i, v in ipairs(SCOPE_VALUES) do
        if v == (scopeTicks or 720) then scopeIdx = i; break end
    end
    local scopeCf = (scopeIdx - 1) / 4
    drawInfoCol("SCOPE", scopeLabels[scopeIdx] or "1H", 4, gradientColor(scopeCf))

    -- ALGOS: label + 3×3 grid of squares filling the column
    local algoCol = 5
    local cx = fMidStart + (algoCol + 0.5) * colW
    local algoColX = cx - colW / 2 + sx(21)
    local algoColW = colW - sx(42)
    love.graphics.setFont(bSmallFont)
    love.graphics.setColor(0.90, 0.90, 0.93)
    love.graphics.print("ALGOS", algoColX, bLabelY)
    local sqGap = sy(4)
    local sqSizeW = math.floor((algoColW - sqGap * 2) / 3)
    -- Cap vertically to fit within the footer pill
    local availH = (bPillTopY + botH) - bNumberY - sy(3)
    local sqSizeH = math.floor((availH - sqGap * 2) / 3)
    local sqSize = math.max(sy(6), math.min(sqSizeW, sqSizeH))
    local sqGridW = 3 * sqSize + 2 * sqGap
    local sqStartX = algoColX
    local sqY = bNumberY
    local sqMaxRows = 3
    local algos = (instrumentConfig and instrumentConfig.algos) or {}
    for i, algo in ipairs(algos) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        if row < sqMaxRows then
            local sx2 = sqStartX + col * (sqSize + sqGap)
            local sy2 = sqY + row * (sqSize + sqGap)
            if activeAlgos[algo.key] then
                love.graphics.setColor(0.20, 0.80, 0.40, 0.9)
                love.graphics.rectangle("fill", sx2, sy2, sqSize, sqSize, 2)
            else
                love.graphics.setColor(0.20, 0.22, 0.26, 0.8)
                love.graphics.rectangle("fill", sx2, sy2, sqSize, sqSize, 2)
            end
        end
    end
end

-- ── BETTING PANEL ──
function drawBettingPanel(w, h)
    -- Panel 2: Betting (matches Panel 1 chart+panels layout exactly)
    love.graphics.translate(safeWidth, 0)
    local chartTop2 = TOPBAR_H + sy(12)
    local chartBot2 = h - BOTBAR_H - sy(9) - sy(12)
    local chartH2 = chartBot2 - chartTop2
    local pad2, gap2 = sx(12), sy(12)
    local betBtnH = math.floor((chartH2 - gap2) / 2)
    
    -- Chart background only (velvet shows through panels)
    love.graphics.setColor(0.04, 0.05, 0.06)
    love.graphics.rectangle("fill", PANEL_W + pad2, chartTop2, w - PANEL_W * 2 - pad2 * 2, chartH2, PILL_R)
    
    -- Bull/Bear chart: green (gain) + red (loss) from opening price
    if #prices > 1 then
        local c2x = PANEL_W + pad2
        local c2w = w - PANEL_W * 2 - pad2 * 2
        local c2y = chartTop2
        local c2h = chartH2
        local open = prices[1]
        if open and open > 0 then
            -- Scissor for chart area
            love.graphics.setScissor(
                safeLeft + math.floor((c2x + tradeSwipeOffset + safeWidth) * safeScale),
                safeTop + math.floor(c2y * safeScale),
                math.floor(c2w * safeScale),
                math.floor(c2h * safeScale)
            )
            -- Use minutePrices (one per minute) for the full-day chart
            local mp = minutePrices
            if #mp < 2 then mp = prices end
            local zeroY = c2y + c2h / 2
            local n = #mp
            local stepX = c2w / math.max(1, n - 1)
            
            -- Zero line
            love.graphics.setColor(0.35, 0.38, 0.42)
            love.graphics.setLineWidth(math.max(1, sy(0.75)))
            love.graphics.line(c2x, zeroY, c2x + c2w, zeroY)
            love.graphics.setLineWidth(1)
            
            -- Bull/Bear odds: sigmoid from open, time-weighted, 2% house cut
            local bullOddsPts = {}
            local bearOddsPts = {}
            local k = 4
            local totalMins = 6 * 60 + 25
            for i = 1, n do
                local t = math.min(1, i / totalMins)
                local retPct = open > 0 and ((mp[i] - open) / open * 100) or 0
                local rawBull = 1 / (1 + math.exp(-k * retPct * t))
                local bullVal = rawBull * 0.98
                local bearVal = (1 - rawBull) * 0.98
                currentBullOdds = bullVal
                currentBearOdds = bearVal
                table.insert(bullOddsPts, c2x + (i - 1) * stepX)
                table.insert(bullOddsPts, c2y + c2h * (1 - bullVal))
                table.insert(bearOddsPts, c2x + (i - 1) * stepX)
                table.insert(bearOddsPts, c2y + c2h * (1 - bearVal))
            end
            if #bullOddsPts >= 4 then
                love.graphics.setColor(0, 1, 0.55, 0.9)
                love.graphics.setLineWidth(math.max(1, sy(3.75)))
                love.graphics.line(bullOddsPts)
            end
            if #bearOddsPts >= 4 then
                love.graphics.setColor(1, 0.25, 0.35, 0.9)
                love.graphics.setLineWidth(math.max(1, sy(3.75)))
                love.graphics.line(bearOddsPts)
            end
            love.graphics.setLineWidth(1)
            
            -- Bet markers
            for _, m in ipairs(bullBetMarkers or {}) do
                local mx = c2x + (m.idx - 1) * stepX
                local my = c2y + c2h * (1 - m.odds)
                if m.type == "bet-win" then
                    local armR = sy(21)
                    love.graphics.setColor(theme.color.gold)
                    love.graphics.setLineWidth(math.max(1, sy(6)))
                    for i = 0, 4 do
                        local angle = math.pi / 2 + i * 2 * math.pi / 5
                        love.graphics.line(mx, my, mx + math.cos(angle) * armR, my - math.sin(angle) * armR)
                    end
                    love.graphics.setLineWidth(math.max(1, sy(1.5)))
                elseif m.type == "bet-lose" then
                    love.graphics.setColor(0.91, 0.25, 0.38)
                    love.graphics.setLineWidth(math.max(1, sy(6)))
                    love.graphics.line(mx - sx(15), my - sy(15), mx + sx(15), my + sy(15))
                    love.graphics.line(mx + sx(15), my - sy(15), mx - sx(15), my + sy(15))
                    love.graphics.setLineWidth(math.max(1, sy(1.5)))
                else
                    love.graphics.setColor(0, 1, 0.55, 1)
                    love.graphics.circle("fill", mx, my, sy(7.5))
                    love.graphics.setColor(0, 0.3, 0.15, 0.6)
                    love.graphics.circle("line", mx, my, sy(7.5))
                end
            end
            for _, m in ipairs(bearBetMarkers or {}) do
                local mx = c2x + (m.idx - 1) * stepX
                local my = c2y + c2h * (1 - m.odds)
                if m.type == "bet-win" then
                    local armR = sy(21)
                    love.graphics.setColor(theme.color.gold)
                    love.graphics.setLineWidth(math.max(1, sy(6)))
                    for i = 0, 4 do
                        local angle = math.pi / 2 + i * 2 * math.pi / 5
                        love.graphics.line(mx, my, mx + math.cos(angle) * armR, my - math.sin(angle) * armR)
                    end
                    love.graphics.setLineWidth(math.max(1, sy(1.5)))
                elseif m.type == "bet-lose" then
                    love.graphics.setColor(0.91, 0.25, 0.38)
                    love.graphics.setLineWidth(math.max(1, sy(6)))
                    love.graphics.line(mx - sx(15), my - sy(15), mx + sx(15), my + sy(15))
                    love.graphics.line(mx + sx(15), my - sy(15), mx - sx(15), my + sy(15))
                    love.graphics.setLineWidth(math.max(1, sy(1.5)))
                else
                    love.graphics.setColor(1, 0.25, 0.35, 1)
                    love.graphics.circle("fill", mx, my, sy(7.5))
                    love.graphics.setColor(0.3, 0.05, 0.08, 0.6)
                    love.graphics.circle("line", mx, my, sy(7.5))
                end
            end
            
            -- Current odds text overlay
            local oddsFont = fonts.default33
            love.graphics.setFont(oddsFont)
            local bullPct = string.format("%.0f%%", (currentBullOdds or 0) * 100)
            local bearPct = string.format("%.0f%%", (currentBearOdds or 0) * 100)
            love.graphics.setColor(0, 1, 0.55, 0.9)
            love.graphics.print("BULL " .. bullPct, c2x + sx(12), c2y + sy(6))
            love.graphics.setColor(1, 0.25, 0.35, 0.9)
            local bfh = oddsFont:getHeight()
            love.graphics.print("BEAR " .. bearPct, c2x + sx(12), c2y + c2h - bfh - sy(6))
            
            -- Current bet value
            if bullBetPct > 0 or bearBetPct > 0 then
                local valFont = fonts.default33
                love.graphics.setFont(valFont)
                local betAmount, entryOdds, currentOdds, label, cr, cg, cb
                if bullBetPct > 0 then
                    betAmount = math.floor(startingBalance * bullBetPct / 100)
                    entryOdds = bullEntryCount > 0 and (bullEntryOddsSum / bullEntryCount) or 0.5
                    currentOdds = currentBullOdds or 0
                    label = "BULL"
                    cr, cg, cb = 0, 1, 0.55
                else
                    betAmount = math.floor(startingBalance * bearBetPct / 100)
                    entryOdds = bearEntryCount > 0 and (bearEntryOddsSum / bearEntryCount) or 0.5
                    currentOdds = currentBearOdds or 0
                    label = "BEAR"
                    cr, cg, cb = 1, 0.25, 0.35
                end
                local value = entryOdds > 0 and math.floor(betAmount * currentOdds / entryOdds) or 0
                local pnl = value - betAmount
                local sign = pnl >= 0 and "+" or ""
                local valText = string.format("%s $%d (%s$%d)", label, value, sign, pnl)
                local vw = valFont:getWidth(valText)
                love.graphics.setColor(cr, cg, cb, 0.9)
                love.graphics.print(valText, c2x + c2w - vw - sx(12), c2y + c2h / 2 - valFont:getHeight() / 2)
            end
            
            love.graphics.setScissor()
            
            -- Y-axis probability labels
            local axisFont = fonts.default30
            love.graphics.setFont(axisFont)
            local axX = c2x + c2w - sx(6)
            local axfh = axisFont:getHeight()
            love.graphics.setColor(0.55, 0.58, 0.62)
            love.graphics.print("100%", axX - axisFont:getWidth("100%"), c2y + sy(3))
            love.graphics.print(" 50%", axX - axisFont:getWidth(" 50%"), zeroY - axfh / 2)
            love.graphics.print("  0%", axX - axisFont:getWidth("  0%"), c2y + c2h - axfh - sy(3))
            
            -- Time label
            if currentTime and currentTime ~= "" then
                love.graphics.setColor(0.74, 0.80, 0.83)
                local timeFont = fonts.default37
                love.graphics.setFont(timeFont)
                local label = (rewindTicks or 0) > 0 and "REWINDING" or currentTime
                local fh = timeFont:getHeight()
                local tw = timeFont:getWidth(label)
                love.graphics.print(label, c2x + c2w - tw - sx(15), c2y + c2h - fh - sy(3))
            end
        end
    end
    
    -- BET BEAR (left panel, top half)
    regButton("btn-bet-bear", pad2 + safeWidth, chartTop2, PANEL_W - pad2 * 2, betBtnH, "BET\nBEAR", nil, function()
        bearBetPct = bearBetPct + 1
        bearEntryOddsSum = bearEntryOddsSum + (currentBearOdds or 0)
        bearEntryCount = bearEntryCount + 1
        table.insert(bearBetMarkers, { idx = #minutePrices, odds = currentBearOdds })
    end)
    love.graphics.setColor(0.91, 0.25, 0.38, 0.6)
    love.graphics.rectangle("fill", pad2, chartTop2, PANEL_W - pad2 * 2, betBtnH, sy(12))
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.rectangle("line", pad2, chartTop2, PANEL_W - pad2 * 2, betBtnH, sy(12))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    local bearLabel = "BET BEAR"
    if bearBetPct > 0 then bearLabel = bearLabel .. "\n" .. bearBetPct .. "%" end
    Button.printfWithHalo(bearLabel, pad2, chartTop2 + (betBtnH - btnActionFont:getHeight() * 2) / 2, PANEL_W - pad2 * 2, "center", 1, 0.5, 0.5)
    
    -- EXIT BEAR (left panel, bottom half)
    local closeBearY = chartTop2 + betBtnH + gap2
    regButton("btn-close-bear", pad2 + safeWidth, closeBearY, PANEL_W - pad2 * 2, betBtnH, "EXIT\nBEAR", nil, function()
        if bearBetPct > 0 then
            local betAmount = math.floor(startingBalance * bearBetPct / 100)
            local entryOdds = bearEntryCount > 0 and (bearEntryOddsSum / bearEntryCount) or 0.5
            local currentOdds = currentBearOdds or 0
            local refund = entryOdds > 0 and math.floor(betAmount * currentOdds / entryOdds) or 0
            realizedPnl = realizedPnl - (betAmount - refund)
            bettingPnl = (bettingPnl or 0) + (refund - betAmount)
            local won = refund >= betAmount
            table.insert(bearBetMarkers, { idx = #minutePrices, odds = currentOdds, type = won and "bet-win" or "bet-lose", time = love.timer.getTime() })
            bearBetPct = 0
            bearEntryOddsSum = 0
            bearEntryCount = 0
        end
    end)
    love.graphics.setColor(0.91, 0.25, 0.38, 0.3)
    love.graphics.rectangle("fill", pad2, closeBearY, PANEL_W - pad2 * 2, betBtnH, sy(12))
    love.graphics.setColor(0.91, 0.25, 0.38, 0.5)
    love.graphics.rectangle("line", pad2, closeBearY, PANEL_W - pad2 * 2, betBtnH, sy(12))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("EXIT BEAR", pad2, closeBearY + (betBtnH - btnActionFont:getHeight() * 2) / 2, PANEL_W - pad2 * 2, "center", 1, 0.5, 0.5)
    
    -- BET BULL (right panel, top half)
    local rbx2 = w - PANEL_W + pad2
    regButton("btn-bet-bull", rbx2 + safeWidth, chartTop2, PANEL_W - pad2 * 2, betBtnH, "BET\nBULL", nil, function()
        bullBetPct = bullBetPct + 1
        bullEntryOddsSum = bullEntryOddsSum + (currentBullOdds or 0)
        bullEntryCount = bullEntryCount + 1
        table.insert(bullBetMarkers, { idx = #minutePrices, odds = currentBullOdds })
    end)
    love.graphics.setColor(0, 0.78, 0.41, 0.6)
    love.graphics.rectangle("fill", rbx2, chartTop2, PANEL_W - pad2 * 2, betBtnH, sy(12))
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.rectangle("line", rbx2, chartTop2, PANEL_W - pad2 * 2, betBtnH, sy(12))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    local bullLabel = "BET BULL"
    if bullBetPct > 0 then bullLabel = bullLabel .. "\n" .. bullBetPct .. "%" end
    Button.printfWithHalo(bullLabel, rbx2, chartTop2 + (betBtnH - btnActionFont:getHeight() * 2) / 2, PANEL_W - pad2 * 2, "center", 0.5, 1, 0.5)
    
    -- EXIT BULL (right panel, bottom half)
    local closeBullY = chartTop2 + betBtnH + gap2
    regButton("btn-close-bull", rbx2 + safeWidth, closeBullY, PANEL_W - pad2 * 2, betBtnH, "EXIT\nBULL", nil, function()
        if bullBetPct > 0 then
            local betAmount = math.floor(startingBalance * bullBetPct / 100)
            local entryOdds = bullEntryCount > 0 and (bullEntryOddsSum / bullEntryCount) or 0.5
            local currentOdds = currentBullOdds or 0
            local refund = entryOdds > 0 and math.floor(betAmount * currentOdds / entryOdds) or 0
            realizedPnl = realizedPnl - (betAmount - refund)
            bettingPnl = (bettingPnl or 0) + (refund - betAmount)
            local won = refund >= betAmount
            table.insert(bullBetMarkers, { idx = #minutePrices, odds = currentOdds, type = won and "bet-win" or "bet-lose", time = love.timer.getTime() })
            bullBetPct = 0
            bullEntryOddsSum = 0
            bullEntryCount = 0
        end
    end)
    love.graphics.setColor(0, 0.78, 0.41, 0.3)
    love.graphics.rectangle("fill", rbx2, closeBullY, PANEL_W - pad2 * 2, betBtnH, sy(12))
    love.graphics.setColor(0, 0.78, 0.41, 0.5)
    love.graphics.rectangle("line", rbx2, closeBullY, PANEL_W - pad2 * 2, betBtnH, sy(12))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("EXIT BULL", rbx2, closeBullY + (betBtnH - btnActionFont:getHeight() * 2) / 2, PANEL_W - pad2 * 2, "center", 0.5, 1, 0.5)
end

-- ── TENDY DRAG OVERLAY ──
function drawTendyOverlay(w, h)
    if not tendyDragActive then return end
    -- Dark backdrop
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, w, h)
    
    -- Choice zones: centered, evenly spaced
    tendyMenuZones = {}
    local zoneW = sx(390)
    local zoneH = sy(150)
    local gap = sy(30)
    local nZones = #tendyMenuChoices
    local totalH = nZones * zoneH + (nZones - 1) * gap
    local startY = (h - totalH) / 2
    local zoneX = (w - zoneW) / 2
    
    for zi, choice in ipairs(tendyMenuChoices) do
        local zy = startY + (zi - 1) * (zoneH + gap)
        local zone = { id = choice.id, label = choice.label, x = zoneX, y = zy, w = zoneW, h = zoneH }
        table.insert(tendyMenuZones, zone)
        
        -- Zone background
        love.graphics.setColor(0.15, 0.16, 0.22, 0.95)
        love.graphics.rectangle("fill", zoneX, zy, zoneW, zoneH, sy(18))
        love.graphics.setColor(0.78, 0.83, 0.88, 0.3)
        love.graphics.setLineWidth(math.max(1, sy(2.25)))
        love.graphics.rectangle("line", zoneX, zy, zoneW, zoneH, sy(18))
        love.graphics.setLineWidth(math.max(1, sy(1.5)))
        
        -- Zone label
        local zFont = fonts.default54
        love.graphics.setFont(zFont)
        love.graphics.setColor(theme.color.gold)
        love.graphics.printf(choice.label, zoneX, zy + (zoneH - zFont:getHeight()) / 2, zoneW, "center")
    end
    
    -- Dragged tendy at cursor
    if tendyImage then
        local dragSize = sy(84)
        local tw, th = tendyImage:getDimensions()
        local dragScale = dragSize / th
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.draw(tendyImage, tendyDragX - tw * dragScale / 2, tendyDragY - th * dragScale / 2, 0, dragScale, dragScale)
    end
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
        closeAllPositions()
        goToScreen(SCREENS.RECAP)
    end)
    love.graphics.setColor(0.72, 0.19, 0.30)
    love.graphics.rectangle("fill", w * 0.35 - 60, h * 0.5, 120, 40, 3)
    Button.printfWithHalo("CLOSE", w * 0.35 - 60, h * 0.5 + (40 - btnActionFont:getHeight()) / 2, 120, "center", 0, 0, 0)
    
    -- KEEP button
    regButton("eod-keep", w * 0.65 - 60, h * 0.5, 120, 40, "KEEP", nil, function()
        carryPosition = true
        goToScreen(SCREENS.RECAP)
    end)
    love.graphics.setColor(theme.color.gold)
    love.graphics.rectangle("line", w * 0.65 - 60, h * 0.5, 120, 40, 3)
    Button.printfWithHalo("KEEP", w * 0.65 - 60, h * 0.5 + (40 - btnActionFont:getHeight()) / 2, 120, "center", unpack(theme.color.gold))
    
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
    Button.printfWithHalo((weekDays[currentDay] or "DAY") .. " COMPLETE!", 0, h * 0.08, w, "center", unpack(theme.color.gold))
    
    -- Financial summary
    local text = string.format("Starting Balance\n$%s\n\nDay P&L\n%s$%s\n\nFinal Balance\n$%s",
                               fmtMoney(startingBalance), sign, fmtPnl(dayPnl), fmtMoney(total))
    love.graphics.setColor(0.78, 0.83, 0.88)
    love.graphics.setFont(fonts.default40)
    love.graphics.printf(text, w * 0.3, h * 0.15, w * 0.4, "center")
    
    -- Buttons centered, styled like selector screen
    local btnW = sx(420)
    local btnH = sy(90)
    local btnGap = sy(22.5)
    local btnX = w / 2 - btnW / 2
    local btnY = h * 0.55
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    
    -- CONTINUE button
    regButton("recap-continue", btnX, btnY, btnW, btnH, "CONTINUE", nil, continueTrading)
    love.graphics.setColor(theme.color.gold)
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, sy(7.5))
    love.graphics.setLineWidth(math.max(1, sy(3)))
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, sy(7.5))
    love.graphics.setLineWidth(math.max(1, sy(1.5)))
    Button.printfWithHalo("CONTINUE", btnX, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", unpack(theme.color.gold))
    
    -- START OVER button
    regButton("recap-restart", btnX, btnY + btnH + btnGap, btnW, btnH, "START OVER", nil, function()
        love.event.quit("restart")
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.setLineWidth(math.max(1, sy(3)))
    love.graphics.rectangle("line", btnX, btnY + btnH + btnGap, btnW, btnH, sy(7.5))
    love.graphics.setLineWidth(math.max(1, sy(1.5)))
    Button.printfWithHalo("START OVER", btnX, btnY + btnH + btnGap + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.35, 0.42, 0.48)
    
    love.graphics.setFont(prev)
end

-- ── CLICK HANDLERS ──
function handleSelectorClick(mx, my)
    for id, b in pairs(Buttons) do
        if id:find("^sel_") and Button.hit(b, mx, my) then
            if b.locked then return end
            safeButtonClick(b)
            return
        end
    end
end

function handleTradingClick(mx, my)
    -- Switch overlay takes priority
    if showSwitchOverlay then
        if Buttons["sw_yes"] and Button.hit(Buttons["sw_yes"], mx, my) then
            closeAllPositions()
            switchPreserveIndex = csvIndex
            switchPreserveDayFile = csvDayFile
            showSwitchOverlay = false
            tickPaused = false
            switchOverlayTimer = 1.0
            return
        end
        if Buttons["sw_no"] and Button.hit(Buttons["sw_no"], mx, my) then
            showSwitchOverlay = false
            tickPaused = false
            return
        end
        return
    end
    -- In demo mode, only the QUIT button is interactive
    if Replay.active then
        -- Allow only the QUIT button to be pressed
        if Buttons["btn-quit"] and Button.hit(Buttons["btn-quit"], mx, my) then
            safeButtonClick(Buttons["btn-quit"])
            return
        end
        return
    end

    -- Quit overlay takes priority
    if showQuitOverlay then
        if Buttons["quit_yes"] and Button.hit(Buttons["quit_yes"], mx, my) then
            showQuitOverlay = false
            tickPaused = false
            canvasPositionsLoaded = false
            goToScreen(SCREENS.CANVAS)
            return
        end
        if Buttons["quit_no"] and Button.hit(Buttons["quit_no"], mx, my) then
            showQuitOverlay = false
            tickPaused = false
            return
        end
        return
    end
    for id, b in pairs(Buttons) do
        if (id:find("^btn%-") or id:find("^dbg%-")) and Button.hit(b, mx, my) then
            if b.locked then
                local thresh = b.lockThreshold or "?"
                toastMsg = "Need $" .. tostring(thresh) .. " total P&L to unlock"
                toastTimer = 2
                return
            end
            safeButtonClick(b)
            return
        end
    end
end

function handleEODClick(mx, my)
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
            safeButtonClick(b)
            return
        end
    end
end

function handleRecapClick(mx, my)
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
            safeButtonClick(b)
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
    
    -- Title
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("DAY SURVIVED!", 0, h * 0.06, w, "center", unpack(theme.color.gold))
    
    -- Subtitle
    love.graphics.setColor(0.60, 0.60, 0.65)
    love.graphics.setFont(fonts.default36)
    love.graphics.printf("YOU SURVIVED A TRADING DAY", 0, h * 0.16, w, "center")

    -- Draw the unlocked sprite persistently (not timed, survives the notification fade)
    if unlockSpriteImg then
        local iw, ih = unlockSpriteImg:getDimensions()
        local targetH = h * 0.30
        local scale = targetH / ih
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(unlockSpriteImg, w / 2, h * 0.45, 0, scale, scale, iw / 2, ih / 2)
    end

    -- CONTINUE button
    local btnW, btnH = sx(330), sy(75)
    local btnX = w / 2 - btnW / 2
    local btnY = h * 0.78
    regButton("ach_continue", btnX, btnY, btnW, btnH, "CONTINUE", nil, function()
        if achievementCarryMode then
            if achievementSavedMode == "random" then
                startGame("RANDOM")
            elseif achievementSavedMode == "predictable" then
                startGame("EASY")
            elseif achievementSavedGroup and achievementSavedGroup ~= "" then
                startGame(achievementSavedGroup)
            else
                goToScreen(SCREENS.SELECTOR)
            end
        else
            goToScreen(SCREENS.SELECTOR)
        end
    end)
    love.graphics.setColor(theme.color.gold)
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CONTINUE", btnX, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", unpack(theme.color.gold))
    
    love.graphics.setFont(prev)
end

function handleAchievementClick(mx, my)
    for id, b in pairs(Buttons) do
        if id:find("^ach_") and Button.hit(b, mx, my) and b.onClick then
            safeButtonClick(b)
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
    Button.printfWithHalo("WEEK COMPLETE!", 0, h * 0.04, w, "center", unpack(theme.color.gold))
    
    local colW = w / 2
    
    -- ── LEFT COLUMN: Your result ──
    local lx = 0
    local ly = h * 0.12
    love.graphics.setColor(0.60, 0.60, 0.65)
    local labelFont = fonts.default33
    love.graphics.setFont(labelFont)
    love.graphics.printf("YOUR RESULT", lx, ly, colW, "center")
    ly = ly + sy(48)
    
    local total = highscoreNewScore
    local weekPnl = total - 10000
    local sign = weekPnl >= 0 and "+" or "-"
    love.graphics.setFont(fonts.default60)
    love.graphics.setColor(theme.color.gold)
    love.graphics.printf("$" .. fmtMoney(total), lx, ly, colW, "center")
    ly = ly + sy(72)
    
    local pnlFont = fonts.default42
    love.graphics.setFont(pnlFont)
    love.graphics.setColor(weekPnl >= 0 and 0 or 0.91, weekPnl >= 0 and 0.78 or 0.25, 0.41)
    love.graphics.printf(sign .. "$" .. fmtPnl(weekPnl) .. " P&L", lx, ly, colW, "center")
    ly = ly + sy(54)
    
    local gamesFont = fonts.default33
    love.graphics.setFont(gamesFont)
    local u = users[playerInitials]
    love.graphics.setColor(0.50, 0.55, 0.60)
    if u then
        love.graphics.printf(u.games .. " game" .. (u.games ~= 1 and "s" or "") .. " played", lx, ly, colW, "center")
        ly = ly + sy(39)
        love.graphics.printf("Best: $" .. fmtMoney(u.high), lx, ly, colW, "center")
        ly = ly + sy(39)
        love.graphics.printf(#(u.pins or {}) .. " pins collected", lx, ly, colW, "center")
    end
    
    if isNewHighScore(highscoreNewScore) then
        ly = ly + sy(54)
        love.graphics.setColor(theme.color.gold)
        if btnActionFont then love.graphics.setFont(btnActionFont) end
        love.graphics.printf("NEW HIGH SCORE!", lx, ly, colW, "center")
    end
    
    -- ── RIGHT COLUMN: Top 10 ──
    local rx = colW
    local ry = h * 0.12
    love.graphics.setColor(0.60, 0.60, 0.65)
    love.graphics.setFont(labelFont)
    love.graphics.printf("TOP 10", rx, ry, colW, "center")
    ry = ry + sy(48)
    
    local scoreFont = fonts.default36
    love.graphics.setFont(scoreFont)
    local shown = math.min(#highScores, 10)
    for i = 1, shown do
        local entry = highScores[i]
        local line = string.format("%2d. %3s  $%s", i, entry.initials, fmtMoney(entry.score))
        if entry.initials == playerInitials then
            love.graphics.setColor(theme.color.gold)
        elseif i == 1 then
            love.graphics.setColor(theme.color.gold)
        elseif i == 2 then
            love.graphics.setColor(0.78, 0.83, 0.88)
        elseif i == 3 then
            love.graphics.setColor(0.60, 0.45, 0.30)
        else
            love.graphics.setColor(0.50, 0.55, 0.60)
        end
        love.graphics.printf(line, rx, ry, colW, "center")
        ry = ry + sy(54)
    end
    
    -- CONTINUE button
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    local btnW, btnH = sx(420), sy(90)
    local btnX = w / 2 - btnW / 2
    regButton("hs-continue", btnX, h * 0.88, btnW, btnH, "CONTINUE", nil, function()
        goToScreen(SCREENS.CANVAS)
        currentDay = 1
    end)
    love.graphics.setColor(theme.color.gold)
    love.graphics.setLineWidth(math.max(1, sy(3)))
    love.graphics.rectangle("line", btnX, h * 0.88, btnW, btnH, sy(7.5))
    love.graphics.setLineWidth(math.max(1, sy(1.5)))
    Button.printfWithHalo("CONTINUE", btnX, h * 0.88 + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", unpack(theme.color.gold))
    
    love.graphics.setFont(prev)
end

function handleHighscoreClick(mx, my)
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
            safeButtonClick(b)
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
    Button.printfWithHalo("HIGH SCORES", 0, h * 0.04, w, "center", unpack(theme.color.gold))
    
    local colW = w / 2
    
    -- ── LEFT COLUMN: Your stats ──
    local lx = 0
    local ly = h * 0.12
    love.graphics.setColor(0.60, 0.60, 0.65)
    love.graphics.setFont(fonts.default33)
    love.graphics.printf("YOUR STATS", lx, ly, colW, "center")
    ly = ly + sy(48)
    
    local u = users[playerInitials]
    love.graphics.setFont(fonts.default42)
    if u then
        love.graphics.setColor(theme.color.gold)
        love.graphics.printf(playerInitials, lx, ly, colW, "center")
        ly = ly + sy(51)
        love.graphics.setColor(0.78, 0.83, 0.88)
        love.graphics.setFont(fonts.default36)
        love.graphics.printf(u.games .. " game" .. (u.games ~= 1 and "s" or "") .. " played", lx, ly, colW, "center")
        ly = ly + sy(42)
        love.graphics.printf("Best: $" .. fmtMoney(u.high), lx, ly, colW, "center")
        ly = ly + sy(42)
        love.graphics.printf(#(u.pins or {}) .. " pins collected", lx, ly, colW, "center")
    else
        love.graphics.setColor(0.50, 0.55, 0.60)
        love.graphics.printf("No stats yet", lx, ly, colW, "center")
    end
    
    -- ── RIGHT COLUMN: Top 10 ──
    local rx = colW
    local ry = h * 0.12
    love.graphics.setColor(0.60, 0.60, 0.65)
    love.graphics.setFont(fonts.default33)
    love.graphics.printf("TOP 10", rx, ry, colW, "center")
    ry = ry + sy(48)
    
    if #highScores == 0 then
        love.graphics.setColor(0.50, 0.55, 0.60)
        love.graphics.setFont(fonts.default36)
        love.graphics.printf("No scores yet!", rx, ry, colW, "center")
    else
        local scoreFont = fonts.default36
        love.graphics.setFont(scoreFont)
        local shown = math.min(#highScores, 10)
        for i = 1, shown do
            local entry = highScores[i]
            local line = string.format("%2d. %3s  $%s", i, entry.initials, fmtMoney(entry.score))
            if entry.initials == playerInitials then
                love.graphics.setColor(theme.color.gold)
            elseif i == 1 then
                love.graphics.setColor(theme.color.gold)
            elseif i == 2 then
                love.graphics.setColor(0.78, 0.83, 0.88)
            elseif i == 3 then
                love.graphics.setColor(0.60, 0.45, 0.30)
            else
                love.graphics.setColor(0.50, 0.55, 0.60)
            end
            love.graphics.printf(line, rx, ry, colW, "center")
            ry = ry + sy(54)
        end
    end
    
    -- BACK button (standard size)
    local backW, backH = sx(240), sy(92)
    local backX = w - backW - sx(30)
    local backY = h - backH - sy(30)
    regButton("hsl-back", backX, backY, backW, backH, "", nil, function()
        goToScreen(SCREENS.SELECTOR)
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)

    -- CANVAS button (bottom-left)
    local cW, cH = sx(240), sy(92)
    local cX = sx(30)
    regButton("hsl_canvas", cX, backY, cW, cH, "", nil, function() goToScreen(SCREENS.CANVAS) end)
    love.graphics.setColor(0.50, 0.50, 0.55)
    love.graphics.rectangle("line", cX, backY, cW, cH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CANVAS", cX, backY + (cH - btnActionFont:getHeight()) / 2, cW, "center", 0.50, 0.50, 0.55)
    
    love.graphics.setFont(prev)
end

function handleHighscoreListClick(mx, my)
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
            safeButtonClick(b)
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
    Button.printfWithHalo("HOW TO PLAY", 0, h * 0.08, w, "center", unpack(theme.color.gold))
    
    -- Instructions body
    love.graphics.setFont(fonts.default40)
    love.graphics.setColor(0.78, 0.83, 0.88)
    
local lines = {
        "Welcome to wallstreetsbeat!",
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
        lineY = lineY + sy(49.5)
    end
    
    -- BACK button (standard size)
    local backW, backH = sx(240), sy(92)
    local backX = w - backW - sx(30)
    local backY = h - backH - sy(30)
    regButton("instr-back", backX, backY, backW, backH, "", nil, function()
        goToScreen(SCREENS.SELECTOR)
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)

    -- CANVAS button (bottom-left)
    local cW, cH = sx(240), sy(92)
    local cX = sx(30)
    regButton("instr_canvas", cX, backY, cW, cH, "", nil, function() goToScreen(SCREENS.CANVAS) end)
    love.graphics.setColor(0.50, 0.50, 0.55)
    love.graphics.rectangle("line", cX, backY, cW, cH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CANVAS", cX, backY + (cH - btnActionFont:getHeight()) / 2, cW, "center", 0.50, 0.50, 0.55)
    
    love.graphics.setFont(prev)
end

function handleInstructionsClick(mx, my)
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
            safeButtonClick(b)
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
    
    Button.printfWithHalo("SETTINGS", 0, h * 0.08, w, "center", unpack(theme.color.gold))
    
    local bodyFont = fonts.default36
    love.graphics.setFont(bodyFont)
    
    -- Y-Axis display toggle — centered vertically
    love.graphics.setColor(0.78, 0.83, 0.88)
    local labelY = h * 0.25
    love.graphics.printf("Y-AXIS DISPLAY", 0, labelY, w, "center")
    
    local btnW, btnH = sx(270), sy(90)
    local gap = sx(30)
    local totalW = btnW * 2 + gap
    local startX = w / 2 - totalW / 2
    local btnY = labelY + sy(90)
    
    -- PCT button
    local pctSelected = (chartDisplay or "pct") == "pct"
    regButton("set_pct", startX, btnY, btnW, btnH, "", nil, function()
        chartDisplay = "pct"
    end)
    if pctSelected then
        love.graphics.setColor(0.48, 0.41, 0.93)
        love.graphics.rectangle("fill", startX, btnY, btnW, btnH, sy(7.5))
    else
        love.graphics.setColor(0.25, 0.28, 0.32)
        love.graphics.rectangle("line", startX, btnY, btnW, btnH, sy(7.5))
    end
    Button.printfWithHalo("%", startX, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.78, 0.83, 0.88)
    
    -- PRICE button
    local priceSelected = (chartDisplay or "pct") == "price"
    regButton("set_price", startX + btnW + gap, btnY, btnW, btnH, "", nil, function()
        chartDisplay = "price"
    end)
    if priceSelected then
        love.graphics.setColor(0.48, 0.41, 0.93)
        love.graphics.rectangle("fill", startX + btnW + gap, btnY, btnW, btnH, sy(7.5))
    else
        love.graphics.setColor(0.25, 0.28, 0.32)
        love.graphics.rectangle("line", startX + btnW + gap, btnY, btnW, btnH, sy(7.5))
    end
    Button.printfWithHalo("$ PRICE", startX + btnW + gap, btnY + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.78, 0.83, 0.88)
    
    -- ── MA SETTINGS ──
    local maTypes = {"MA", "EMA", "TEMA"}
    local maPeriods = {5, 10, 15, 30, 60}
    local maBtnW, maBtnH = sx(135), sy(54)
    local maGap = sx(12)
    local maY = btnY + btnH + sy(60) + sy(120)
    local bodyFont2 = fonts.default33
    
    -- Helper to draw a row of toggle buttons
    local function drawMARow(label, color, currentType, currentPeriod, prefix)
        love.graphics.setColor(0.78, 0.83, 0.88)
        love.graphics.setFont(bodyFont2)
        love.graphics.printf(label, 0, maY, w, "center")
        
        -- Type buttons
        local typeStartX = w / 2 - (#maTypes * maBtnW + (#maTypes - 1) * maGap) / 2
        for ti, t in ipairs(maTypes) do
            local bx = typeStartX + (ti - 1) * (maBtnW + maGap)
            local selected = (currentType == t)
            regButton(prefix .. "_type_" .. t, bx, maY + sy(45), maBtnW, maBtnH, "", nil, function()
                if prefix == "xer" then xerMAType = t else xeeMAType = t end
                saveUserSettings(playerInitials)
            end)
            if selected then
                love.graphics.setColor(color[1], color[2], color[3], 0.7)
                love.graphics.rectangle("fill", bx, maY + sy(45), maBtnW, maBtnH, sy(7.5))
            else
                love.graphics.setColor(0.25, 0.28, 0.32)
                love.graphics.rectangle("line", bx, maY + sy(45), maBtnW, maBtnH, sy(7.5))
            end
            Button.printfWithHalo(t, bx, maY + sy(45) + (maBtnH - btnActionFont:getHeight()) / 2, maBtnW, "center", 0.78, 0.83, 0.88)
        end
        maY = maY + sy(90)
        
        -- Period buttons
        love.graphics.setColor(0.78, 0.83, 0.88)
        love.graphics.setFont(bodyFont2)
        local perStartX = w / 2 - (#maPeriods * maBtnW + (#maPeriods - 1) * maGap) / 2
        for pi, p in ipairs(maPeriods) do
            local bx = perStartX + (pi - 1) * (maBtnW + maGap)
            local selected = (currentPeriod == p)
            regButton(prefix .. "_per_" .. p, bx, maY + sy(45), maBtnW, maBtnH, "", nil, function()
                if prefix == "xer" then xerMAPeriod = p else xeeMAPeriod = p end
                saveUserSettings(playerInitials)
            end)
            if selected then
                love.graphics.setColor(color[1], color[2], color[3], 0.7)
                love.graphics.rectangle("fill", bx, maY + sy(45), maBtnW, maBtnH, sy(7.5))
            else
                love.graphics.setColor(0.25, 0.28, 0.32)
                love.graphics.rectangle("line", bx, maY + sy(45), maBtnW, maBtnH, sy(7.5))
            end
            Button.printfWithHalo(tostring(p), bx, maY + sy(45) + (maBtnH - btnActionFont:getHeight()) / 2, maBtnW, "center", 0.78, 0.83, 0.88)
        end
        maY = maY + sy(105)
    end
    
    drawMARow("XER MA", {0.70, 0.35, 1.0}, xerMAType or "TEMA", xerMAPeriod or 15, "xer")
    drawMARow("XEE MA", {0.20, 0.55, 1.0}, xeeMAType or "EMA", xeeMAPeriod or 15, "xee")
    
    -- BACK button
    local backW, backH = sx(240), sy(92)
    local backX = w - backW - sx(30)
    local backY = h - backH - sy(30)
    regButton("set_back", backX, backY, backW, backH, "", nil, function()
        if goBackTo then
            SCREEN = goBackTo
            goBackTo = nil
        elseif prices and #prices > 0 then
            SCREEN = SCREENS.TRADING
        else
            SCREEN = SCREENS.SELECTOR
        end
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)

    -- GIMMICKS button (bottom-left, same sizing as BACK)
    local gW, gH = sx(240), sy(92)
    local gX = sx(30)
    regButton("set_gimmicks", gX, backY, gW, gH, "", nil, function()
        goToScreen(SCREENS.GIMMICKS)
    end)
    love.graphics.setColor(0.70, 0.30, 0.85)
    love.graphics.rectangle("line", gX, backY, gW, gH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("GIMMICKS", gX, backY + (gH - btnActionFont:getHeight()) / 2, gW, "center", 0.70, 0.30, 0.85)
    
    love.graphics.setFont(prev)
end

function handleSettingsClick(mx, my)
    -- Check back button explicitly
    if Buttons["set_back"] and Button.hit(Buttons["set_back"], mx, my) then
        Buttons["set_back"].onClick()
        return
    end
    -- Check gimmicks button
    if Buttons["set_gimmicks"] and Button.hit(Buttons["set_gimmicks"], mx, my) then
        Buttons["set_gimmicks"].onClick()
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
    -- Fallback: fire any other registered button's onClick (MA type/period, etc.)
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
            safeButtonClick(b)
            return
        end
    end
end

-- ── GIMMICKS SCREEN (debug only) ──
function drawGimmicks(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    Buttons = {}
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    
    Button.printfWithHalo("GIMMICKS", 0, h * 0.08, w, "center", 0.70, 0.30, 0.85)
    
    local gimmicks = {
        { key = "snow",  label = "SNOW",   desc = "Snowfall on chart" },
        { key = "ball",  label = "BALL",   desc = "Ball & dog minigame" },
        { key = "skier", label = "SKIER",  desc = "Skiing on the MA" },
        { key = "surfer", label = "SURFER", desc = "Surfing on the MA" },
    }
    
    local btnW, btnH = sx(330), sy(90)
    local gap = sy(24)
    local startY = h * 0.25
    local bodyFont = fonts.default36
    
    for i, g in ipairs(gimmicks) do
        local gy = startY + (i - 1) * (btnH + gap)
        local active = isFeatureUnlocked(g.key)
        
        -- Toggle button (non-ball gimmicks are mutually exclusive)
        regButton("gim_" .. g.key, w / 2 - btnW / 2, gy, btnW, btnH, "", nil, function()
            local excludeKeys = { snow = true, skier = true, surfer = true }
            if excludeKeys[g.key] and not featureConfig[g.key] then
                -- Turn on this gimmick, turn off all others (except ball)
                for k, _ in pairs(excludeKeys) do
                    featureConfig[k] = (k == g.key)
                end
            else
                featureConfig[g.key] = not featureConfig[g.key]
            end
        end)
        
        if active then
            love.graphics.setColor(0.20, 0.70, 0.35, 0.85)
            love.graphics.rectangle("fill", w / 2 - btnW / 2, gy, btnW, btnH, sy(7.5))
        else
            love.graphics.setColor(0.25, 0.28, 0.32)
            love.graphics.rectangle("line", w / 2 - btnW / 2, gy, btnW, btnH, sy(7.5))
        end
        
        -- Label
        if btnActionFont then love.graphics.setFont(btnActionFont) end
        local state = active and "ON" or "OFF"
        Button.printfWithHalo(g.label .. "  " .. state, w / 2 - btnW / 2, gy + (btnH - btnActionFont:getHeight()) / 2, btnW, "center", 0.78, 0.83, 0.88)
        
        -- Description
        love.graphics.setFont(bodyFont)
        love.graphics.setColor(0.50, 0.50, 0.55)
        love.graphics.printf(g.desc, w / 2 - btnW / 2, gy + btnH + sy(6), btnW, "center")
    end
    
    -- BACK button
    local backW, backH = sx(240), sy(92)
    local backX = w - backW - sx(30)
    local backY = h - backH - sy(30)
    regButton("gim_back", backX, backY, backW, backH, "", nil, function()
        SCREEN = goBackTo or SCREENS.TRADING
        goBackTo = nil
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)

    -- CANVAS button (bottom-left)
    local cW, cH = sx(240), sy(92)
    local cX = sx(30)
    regButton("gim_canvas", cX, backY, cW, cH, "", nil, function() goToScreen(SCREENS.CANVAS) end)
    love.graphics.setColor(0.50, 0.50, 0.55)
    love.graphics.rectangle("line", cX, backY, cW, cH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CANVAS", cX, backY + (cH - btnActionFont:getHeight()) / 2, cW, "center", 0.50, 0.50, 0.55)
    
    love.graphics.setFont(prev)
end

function handleGimmicksClick(mx, my)
    -- Check back button first
    if Buttons["gim_back"] and Button.hit(Buttons["gim_back"], mx, my) then
        Buttons["gim_back"].onClick()
        return
    end
    -- Fallback: fire any other registered button's onClick
    for id, b in pairs(Buttons) do
        if Button.hit(b, mx, my) and b.onClick then
            safeButtonClick(b)
            return
        end
    end
end

-- ── ROTATE SCREEN ──
function drawRotate(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    Buttons = {}
    local prev = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end

    -- Use rotateSpriteImage if set, otherwise fall back to tendyImage
    local img = rotateSpriteImage or tendyImage
    local spriteName = ""

    if fonts.default99 then love.graphics.setFont(fonts.default99) end
    Button.printfWithHalo("YOUR PINS", 0, h * 0.055, w, "center", 0.94, 0.71, 0.16)

    local bodyFont = fonts.default36
    love.graphics.setFont(bodyFont)

    -- ── Draw sprite as a card with gold backing ──
    if img then
        local iw, ih = img:getDimensions()
        local cardScale = sy(324) / ih  -- ~30% of screen height
        local cx = w / 2
        local cy = h / 2 - sy(30)
        local goldOff = sy(6)  -- gold offset for outline effect

        -- Rotation angles
        local rotYRad = math.rad(rotY or 0)
        local rotXRad = math.rad(rotX or 0)

        -- Squeeze factors: how much the sprite shrinks along each axis
        local cosY = math.cos(rotYRad)
        local cosX = math.cos(rotXRad)
        local ySqueeze = math.max(0.01, math.abs(cosY))
        local xSqueeze = math.max(0.01, math.abs(cosX))

        -- Front is visible when the combined normal points toward the viewer
        local showFront = cosY * cosX >= 0

        -- Card dimensions (squeezed)
        local cw = iw * cardScale
        local ch = ih * cardScale
        local cardW = cw * ySqueeze
        local cardH = ch * xSqueeze

        love.graphics.push()
        love.graphics.translate(cx, cy)

        -- ── Card edge thickness (3D depth) ──
        -- Fills the gap with gold using the sprite shape, so it follows the contours
        local edgeThick = sy(15)
        local sinY = math.sin(rotYRad)
        local sinX = math.sin(rotXRad)
        local yEdge = math.abs(sinY) * edgeThick  -- horizontal offset
        local xEdge = math.abs(sinX) * edgeThick  -- vertical offset
        local eOffX = cosY >= 0 and yEdge or -yEdge
        local eOffY = cosX >= 0 and xEdge or -xEdge

        -- Fill the gap between (0,0) and (eOffX, eOffY) with gold (same as back)
        if yEdge > 0.5 or xEdge > 0.5 then
            love.graphics.setShader(solidColorShader)
            local steps = math.max(1, math.floor((yEdge + xEdge) / sy(3)))
            for s = steps, 0, -1 do
                local t = steps > 0 and (s / steps) or 0
                local a = 0.5 + 0.4 * (1 - t)
                love.graphics.setColor(0.94, 0.71, 0.16, a)
                love.graphics.draw(img, eOffX * t, eOffY * t, 0,
                                   ySqueeze * cardScale, xSqueeze * cardScale,
                                   iw / 2, ih / 2)
            end
            love.graphics.setShader()
        end

        -- Dark outer edge line (sprite outline at full offset)
        if yEdge > 0.5 or xEdge > 0.5 then
            love.graphics.setColor(0.55, 0.38, 0.05, 0.75)
            love.graphics.draw(img, eOffX, eOffY, 0,
                               ySqueeze * cardScale, xSqueeze * cardScale,
                               iw / 2, ih / 2)
        end

        if showFront then
            -- ── Front: tendy sprite with subtle gold edge ──
            -- Thin gold border: just 4 diagonal offsets, no rotation
            love.graphics.setColor(0.94, 0.71, 0.16, 0.6)
            local off = sy(4)
            love.graphics.draw(img, -off, -off, 0, ySqueeze * cardScale, xSqueeze * cardScale, iw / 2, ih / 2)
            love.graphics.draw(img,  off, -off, 0, ySqueeze * cardScale, xSqueeze * cardScale, iw / 2, ih / 2)
            love.graphics.draw(img, -off,  off, 0, ySqueeze * cardScale, xSqueeze * cardScale, iw / 2, ih / 2)
            love.graphics.draw(img,  off,  off, 0, ySqueeze * cardScale, xSqueeze * cardScale, iw / 2, ih / 2)

            -- Tendy sprite on top
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(img, 0, 0, 0,
                               ySqueeze * cardScale, xSqueeze * cardScale,
                               iw / 2, ih / 2)
        else
            -- ── Back: solid gold sprite (shader replaces RGB, keeps alpha) ──
            love.graphics.setShader(solidColorShader)

            -- Shadow offset (dark gold)
            love.graphics.setColor(0.55, 0.38, 0.05, 0.7)
            love.graphics.draw(img, -sy(3), sy(3), 0,
                               ySqueeze * cardScale, xSqueeze * cardScale,
                               iw / 2, ih / 2)

            -- Solid gold base fill
            love.graphics.setColor(0.94, 0.71, 0.16, 0.9)
            love.graphics.draw(img, 0, 0, 0,
                               ySqueeze * cardScale, xSqueeze * cardScale,
                               iw / 2, ih / 2)

            love.graphics.setShader()

            -- Pin lock icon stuck to the back (centered, sized relative to the card)
            if pinLockImage then
                local plw, plh = pinLockImage:getDimensions()
                local lockSize = math.min(cardW, cardH) * 0.35  -- 35% of the smaller card dimension
                local lockScale = lockSize / math.max(plw, plh)
                love.graphics.setColor(0.55, 0.38, 0.05, 0.85)
                love.graphics.draw(pinLockImage, 0, 0, 0,
                                   ySqueeze * lockScale, xSqueeze * lockScale,
                                   plw / 2, plh / 2)
                -- Inner highlight on the lock
                love.graphics.setColor(0.94, 0.81, 0.30, 0.6)
                love.graphics.draw(pinLockImage, -sy(1), -sy(1), 0,
                                   ySqueeze * lockScale, xSqueeze * lockScale,
                                   plw / 2, plh / 2)
            end
        end

        love.graphics.pop()

        -- Store hit zone for drag interaction
        local hitR = math.max(iw, ih) * cardScale * 0.6
        rotateTendyHit = { cx = cx, cy = cy, radius = hitR }
    else
        -- Fallback if no tendy image
        love.graphics.setColor(0.35, 0.35, 0.40)
        love.graphics.rectangle("fill", w / 2 - sx(100), h / 2 - sy(100), sx(200), sy(200), sy(12))
        love.graphics.setFont(bodyFont)
        love.graphics.setColor(0.78, 0.83, 0.88)
        love.graphics.printf("No tendy sprite", 0, h / 2 - sy(10), w, "center")
        rotateTendyHit = nil
    end

    -- Bottom instruction text (same padding as BACK button)
    love.graphics.setFont(bodyFont)
    love.graphics.setColor(0.50, 0.50, 0.55)
    love.graphics.printf("Drag the sprite to rotate", 0, h - sy(30) - bodyFont:getHeight(), w, "center")

    -- ── BACK button ──
    local backW, backH = sx(240), sy(92)
    local backX = w - backW - sx(30)
    local backY = h - backH - sy(30)
    regButton("rot_back", backX, backY, backW, backH, "", nil, function()
        SCREEN = goBackTo or SCREENS.SETTINGS
        goBackTo = nil
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)

    -- CANVAS button (bottom-left)
    local cW, cH = sx(240), sy(92)
    local cX = sx(30)
    regButton("rot_canvas", cX, backY, cW, cH, "", nil, function() goToScreen(SCREENS.CANVAS) end)
    love.graphics.setColor(0.50, 0.50, 0.55)
    love.graphics.rectangle("line", cX, backY, cW, cH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CANVAS", cX, backY + (cH - btnActionFont:getHeight()) / 2, cW, "center", 0.50, 0.50, 0.55)

    love.graphics.setFont(prev)
end

function handleRotateClick(mx, my)
    if Buttons["rot_back"] and Button.hit(Buttons["rot_back"], mx, my) then
        Buttons["rot_back"].onClick()
    end
    if Buttons["rot_canvas"] and Button.hit(Buttons["rot_canvas"], mx, my) then
        Buttons["rot_canvas"].onClick()
    end
end

-- ── INITIALS SCREEN ──
function drawInitials(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    Buttons = {}
    local prev = love.graphics.getFont()
    local bodyFont = fonts.default36
    local smallFont = fonts.default27
    
    -- Title (bigger)
    if fonts.default99 then love.graphics.setFont(fonts.default99) end
    Button.printfWithHalo("YOUR INITIALS", 0, h * 0.055, w, "center", unpack(theme.color.gold))
    
    -- BACK button (bottom-right, standard position)
    local backW, backH = sx(240), sy(92)
    local backX = w - backW - sx(30)
    local backY = h - backH - sy(30)
    regButton("init_back", backX, backY, backW, backH, "", nil, function()
        SCREEN = goBackTo or SCREENS.CANVAS
        goBackTo = nil
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)
    
    -- Load existing users for display
    loadUsers()
    local existing = getExistingUsers()
    local hasExisting = #existing > 0
    
    local curY = h * 0.16
    
    if hasExisting then
        -- User cards (compact, max 2)
        local cardW = sx(510)
        local cardH = sy(68)
        local cardGap = sy(8)
        local delW = sy(54)
        local maxCards = math.min(#existing, 2)
        
        for i = 1, maxCards do
            local init = existing[i]
            local data = users[init]
            local cx = w / 2 - cardW / 2
            local cy = curY + (i - 1) * (cardH + cardGap)
            
            -- Card background
            love.graphics.setColor(0.12, 0.14, 0.18)
            love.graphics.rectangle("fill", cx, cy, cardW, cardH, sy(9))
            love.graphics.setColor(0.25, 0.28, 0.35)
            love.graphics.rectangle("line", cx, cy, cardW, cardH, sy(9))
            
            -- Initials
            if btnActionFont then love.graphics.setFont(btnActionFont) end
            love.graphics.setColor(theme.color.gold)
            local initW = btnActionFont:getWidth(init)
            love.graphics.print(init, cx + sx(20), cy + (cardH - btnActionFont:getHeight()) / 2)
            
            -- Stats
            love.graphics.setFont(smallFont)
            love.graphics.setColor(0.50, 0.55, 0.60)
            local statsText = string.format("$%s  ·  %d game%s",
                fmtMoney(data.high), data.games, data.games ~= 1 and "s" or "")
            love.graphics.print(statsText, cx + sx(20) + initW + sx(16), cy + (cardH - smallFont:getHeight()) / 2)
            
            -- Clickable button (main card)
            local mainW = cardW - delW - sx(9)
            regButton("user_" .. init, cx, cy, mainW, cardH, "", nil, function()
                playerInitials = init
                pickPresident()
                goToScreen(SCREENS.SELECTOR)
            end)
            
            -- Delete button
            local delX = cx + cardW - delW - sx(3)
            local delBtnW = delW + sx(3)
            regButton("deluser_" .. init, delX, cy, delBtnW, cardH, "", nil, function()
                deleteUser(init)
            end)
            love.graphics.setColor(0.72, 0.19, 0.30)
            love.graphics.rectangle("fill", delX, cy, delBtnW, cardH, sy(9))
            love.graphics.setColor(0.85, 0.30, 0.40)
            love.graphics.rectangle("line", delX, cy, delBtnW, cardH, sy(9))
            if btnActionFont then love.graphics.setFont(btnActionFont) end
            Button.printfWithHalo("X", delX, cy + (cardH - btnActionFont:getHeight()) / 2, delBtnW, "center", 0.94, 0.83, 0.88)
        end
        
        curY = curY + maxCards * (cardH + cardGap) + sy(16)
    else
        -- No existing users: show guidance text
        love.graphics.setColor(0.60, 0.60, 0.65)
        love.graphics.setFont(bodyFont)
        love.graphics.printf("Enter 3 letters to identify your scores", 0, curY, w, "center")
        curY = curY + sy(60)
    end
    
    -- Entry field with blinking cursor (bigger)
    local showCursor = math.floor(love.timer.getTime() * 2) % 2 == 0
    local display = playerInitials
    if showCursor and #playerInitials < 3 then
        display = display .. "_"
    end
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo(display, w * 0.5 - sx(240), curY, sx(480), "center", 0.78, 0.83, 0.88)
    curY = curY + sy(90)
    
    -- On-screen keyboard (big, fills screen)
    local keyW, keyH = sx(156), sy(108)
    local keyGap = sx(8)
    -- 7/7/7/5 row layout to fit larger keys
    local rows = { "ABCDEFG", "HIJKLMN", "OPQRSTU", "VWXYZ" }
    local totalKeyboardH = #rows * (keyH + keyGap)
    -- Compute remaining space below curY and vertically center the keyboard
    local availableH = h - curY - sy(130)  -- leave room for back button at bottom
    local keyboardTop = curY + math.max(0, (availableH - totalKeyboardH) / 2)
    
    for rIdx, row in ipairs(rows) do
        local rowW = #row * keyW + (#row - 1) * keyGap
        local rowX = w / 2 - rowW / 2
        local rowY = keyboardTop + (rIdx - 1) * (keyH + keyGap)
        for i = 1, #row do
            local ch = row:sub(i, i)
            local kx = rowX + (i - 1) * (keyW + keyGap)
            regButton("init_" .. ch, kx, rowY, keyW, keyH, "", nil, function()
                if #playerInitials < 3 then
                    playerInitials = playerInitials .. ch
                end
            end)
            love.graphics.setColor(0.25, 0.28, 0.32)
            love.graphics.rectangle("fill", kx, rowY, keyW, keyH, sy(7.5))
            love.graphics.setColor(0.78, 0.83, 0.88)
            love.graphics.printf(ch, kx, rowY + (keyH - btnActionFont:getHeight()) / 2, keyW, "center")
        end
    end
    
    -- DELETE and DONE on the last row alongside YZ keys
    local lastRowY = keyboardTop + 3 * (keyH + keyGap)
    local lastRow = "VWXYZ"
    local lastRowW = #lastRow * keyW + (#lastRow - 1) * keyGap
    -- Action buttons: DELETE left of V, DONE right of Z
    local delBtnW = sx(160)
    local doneBtnW = sx(160)
    local totalW = delBtnW + keyGap + lastRowW + keyGap + doneBtnW
    local totalX = w / 2 - totalW / 2
    
    -- DELETE button
    local delX = totalX
    regButton("init_del", delX, lastRowY, delBtnW, keyH, "", nil, function()
        playerInitials = playerInitials:sub(1, -2)
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", delX, lastRowY, delBtnW, keyH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("DEL", delX, lastRowY + (keyH - btnActionFont:getHeight()) / 2, delBtnW, "center", 0.60, 0.60, 0.65)
    
    -- VWXYZ keys
    local letterX = totalX + delBtnW + keyGap
    for i = 1, #lastRow do
        local ch = lastRow:sub(i, i)
        local kx = letterX + (i - 1) * (keyW + keyGap)
        regButton("init_" .. ch, kx, lastRowY, keyW, keyH, "", nil, function()
            if #playerInitials < 3 then
                playerInitials = playerInitials .. ch
            end
        end)
        love.graphics.setColor(0.25, 0.28, 0.32)
        love.graphics.rectangle("fill", kx, lastRowY, keyW, keyH, sy(7.5))
        love.graphics.setColor(0.78, 0.83, 0.88)
        love.graphics.printf(ch, kx, lastRowY + (keyH - btnActionFont:getHeight()) / 2, keyW, "center")
    end
    
    -- DONE button
    local doneX = letterX + #lastRow * (keyW + keyGap)
    regButton("init_done", doneX, lastRowY, doneBtnW, keyH, "", nil, function()
        if #playerInitials > 0 then
            pickPresident()
            goToScreen(SCREENS.SELECTOR)
        end
    end)
    love.graphics.setColor(theme.color.gold)
    love.graphics.rectangle("line", doneX, lastRowY, doneBtnW, keyH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("DONE", doneX, lastRowY + (keyH - btnActionFont:getHeight()) / 2, doneBtnW, "center", unpack(theme.color.gold))
    
    -- CANVAS button (bottom-left, same size as BACK)
    local cW, cH = sx(240), sy(92)
    local cX = sx(30)
    regButton("init_canvas", cX, backY, cW, cH, "", nil, function()
        SCREEN = SCREENS.CANVAS
    end)
    love.graphics.setColor(0.50, 0.50, 0.55)
    love.graphics.rectangle("line", cX, backY, cW, cH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CANVAS", cX, backY + (cH - btnActionFont:getHeight()) / 2, cW, "center", 0.50, 0.50, 0.55)

    love.graphics.setFont(prev)
end

function handleInitialsClick(mx, my)
    -- Check back button
    if Buttons["init_back"] and Button.hit(Buttons["init_back"], mx, my) then
        Buttons["init_back"].onClick()
        return
    end
    -- Check user card clicks first (including delete buttons)
    for id, b in pairs(Buttons) do
        if (id:find("^user_") or id:find("^deluser_") or id:find("^init_")) and Button.hit(b, mx, my) and b.onClick then
            safeButtonClick(b)
            return
        end
    end
end

-- ── PINS SCREEN ──
-- ── SPRITES GALLERY (replaces old PINS screen) ──
-- Shows all unlocked canvas sprites. Click one to open in the rotate screen.
function drawSpritesGallery(w, h)
    love.graphics.setBackgroundColor(0.02, 0.03, 0.04)
    Buttons = {}
    local prev = love.graphics.getFont()
    if fonts.default99 then love.graphics.setFont(fonts.default99) end

    Button.printfWithHalo("YOUR PINS", 0, h * 0.055, w, "center", unpack(theme.color.gold))

    local bodyFont = fonts.default36
    love.graphics.setFont(bodyFont)

    -- Collect all unlocked sprites from canvasSprites
    local unlocked = {}
    for _, s in ipairs(canvasSprites) do
        table.insert(unlocked, s)
    end
    -- Also include wsb.png if present
    if canvasWsb then
        table.insert(unlocked, canvasWsb)
    end

    if #unlocked == 0 then
        love.graphics.setColor(0.35, 0.42, 0.48)
        love.graphics.printf("No sprites unlocked yet", 0, h * 0.35, w, "center")
        love.graphics.setFont(bodyFont)
        love.graphics.printf("Earn them by trading!", 0, h * 0.35 + sy(45), w, "center")
    else
        -- Grid layout
        local cols = 4
        local thumbSize = sx(120)
        local thumbGap = sx(16)
        local gridW = cols * thumbSize + (cols - 1) * thumbGap
        local startX = (w - gridW) / 2
        local startY = h * 0.14
        local rows = math.ceil(#unlocked / cols)

        for idx, s in ipairs(unlocked) do
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local bx = startX + col * (thumbSize + thumbGap)
            local by = startY + row * (thumbSize + thumbGap)

            -- Thumbnail bg
            love.graphics.setColor(0.10, 0.12, 0.15)
            love.graphics.rectangle("fill", bx, by, thumbSize, thumbSize, sy(7.5))
            love.graphics.setColor(0.20, 0.22, 0.25)
            love.graphics.setLineWidth(math.max(1, sy(1.5)))
            love.graphics.rectangle("line", bx, by, thumbSize, thumbSize, sy(7.5))
            love.graphics.setLineWidth(1)

            -- Sprite thumbnail (fit inside thumbSize with padding)
            local pad = sy(8)
            local iw, ih = s.image:getDimensions()
            local sScale = math.min((thumbSize - pad * 2) / iw, (thumbSize - pad * 2) / ih)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(s.image, bx + thumbSize / 2, by + thumbSize / 2, 0, sScale, sScale, iw / 2, ih / 2)

            -- Click button
            regButton("spr_" .. idx, bx, by, thumbSize, thumbSize, "", nil, function()
                rotateSpriteImage = s.image
                goToScreen(SCREENS.ROTATE)
            end)
        end

        -- Instruction text
        love.graphics.setFont(bodyFont)
        love.graphics.setColor(0.50, 0.50, 0.55)
        love.graphics.printf("Tap a sprite to rotate it", 0, startY + rows * (thumbSize + thumbGap) + sy(20), w, "center")
    end

    -- BACK button
    local backW, backH = sx(240), sy(92)
    local backX = w - backW - sx(30)
    local backY = h - backH - sy(30)
    regButton("sg_back", backX, backY, backW, backH, "", nil, function()
        goToScreen(SCREENS.SELECTOR)
    end)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.rectangle("line", backX, backY, backW, backH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("BACK", backX, backY + (backH - btnActionFont:getHeight()) / 2, backW, "center", 0.35, 0.42, 0.48)

    -- CANVAS button (bottom-left)
    local cW, cH = sx(240), sy(92)
    local cX = sx(30)
    regButton("sg_canvas", cX, backY, cW, cH, "", nil, function() goToScreen(SCREENS.CANVAS) end)
    love.graphics.setColor(0.50, 0.50, 0.55)
    love.graphics.rectangle("line", cX, backY, cW, cH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("CANVAS", cX, backY + (cH - btnActionFont:getHeight()) / 2, cW, "center", 0.50, 0.50, 0.55)

    love.graphics.setFont(prev)
end

function handleSpritesGalleryClick(mx, my)
    if Buttons["sg_back"] and Button.hit(Buttons["sg_back"], mx, my) then
        Buttons["sg_back"].onClick()
        return
    end
    for id, b in pairs(Buttons) do
        if id:find("^spr_") and Button.hit(b, mx, my) and b.onClick then
            safeButtonClick(b)
            return
        end
    end
end



-- ── CANVAS SCREEN ──
function drawCanvas(w, h)
    -- Load any saved sprites from all known users (so they appear before initials are entered)
    for _, u in pairs(users) do
        for _, f in ipairs(u.features or {}) do
            if f:find("^sprite_") then
                local fileName = f:gsub("^sprite_", "") .. ".png"
                local already = false
                for _, s in ipairs(canvasSprites) do
                    if s.file == fileName then already = true; break end
                end
                if not already then
                    local ok, img = pcall(love.graphics.newImage, "sprites/" .. fileName)
                    if ok then
                        local iw, ih = img:getDimensions()
                        local spriteConfig = instrumentConfig and instrumentConfig.canvasSprites or {}
                        local sizePct = 0.2
                        for _, sc in ipairs(spriteConfig) do
                            if sc.file == fileName then sizePct = sc.size or sizePct; break end
                        end
                        local targetSize = sizePct * safeHeight
                        local scale = math.min(1, targetSize / math.max(iw, ih))
                        local sw, sh = iw * scale, ih * scale
                        local x, y = findEmptyCanvasSpot(sw, sh)
                        table.insert(canvasSprites, {
                            image = img, file = fileName,
                            x = x, y = y, scale = scale, w = sw, h = sh,
                        })
                    end
                end
            end
        end
    end
    -- Apply saved positions from canvas_positions.txt (only once per canvas session)
    if not canvasPositionsLoaded and canvasSprites then
        canvasPositionsLoaded = true
        local content = love.filesystem.read("canvas_positions.txt")
        if content then
            local saved = {}
            for line in content:gmatch("[^\r\n]+") do
                local file, sx, sy = line:match("^(.+):(.+):(.+)$")
                if file and sx and sy then
                    saved[file] = { x = tonumber(sx), y = tonumber(sy) }
                end
            end
            for _, s in ipairs(canvasSprites) do
                if s.file and saved[s.file] then
                    s.x = math.max(0, math.min(safeWidth - s.w, saved[s.file].x))
                    s.y = math.max(0, math.min(safeHeight - s.h, saved[s.file].y))
                end
            end
        end
    end
    -- Reset all game state (same as old drawWelcome)
    startingBalance = 10000
    realizedPnl = 0
    pnl = 0
    tendies = 1.0
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
    speedMult = 1.0  -- default 1.0x
    buyStopHeld = false
    sellStopHeld = false
    stopRepeatTimer = 0
    rewindHeld = false
    forwardHeld = false
    rewindButtonWasHeld = false
    rewindUnlocked = false
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
    local hintFont = fonts.default33
    local prev = love.graphics.getFont()
    love.graphics.setFont(hintFont)
    love.graphics.setColor(0.35, 0.42, 0.48)
    love.graphics.printf("tap anywhere to start", 0, h - sy(90), w, "center")
    love.graphics.setFont(prev)

    -- Reset button (top-right corner)
    local resetW, resetH = sx(120), sy(48)
    local resetX = w - resetW - sx(24)
    local resetY = sy(24)
    regButton("canvas_reset", resetX, resetY, resetW, resetH, "", nil, function()
        resetCanvasPositions()
    end)
    love.graphics.setColor(0.25, 0.28, 0.32)
    love.graphics.rectangle("line", resetX, resetY, resetW, resetH, sy(7.5))
    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("RESET", resetX, resetY + (resetH - (btnActionFont:getHeight() or sy(30))) / 2, resetW, "center", 0.55, 0.30, 0.30)

    love.graphics.setFont(prev)
end

function handleCanvasClick(mx, my)
    -- Check reset button first
    local rb = Buttons["canvas_reset"]
    if rb and Button.hit(rb, mx, my) then safeButtonClick(rb); return end
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
    goToScreen(SCREENS.INITIALS)
end


