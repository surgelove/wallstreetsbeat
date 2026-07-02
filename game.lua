-- ── GAME STATE ──
local Haptics = require("haptics")
dataMode = nil
csvData = nil
csvIndex = 0
csvInstrument = nil
csvGroupName = ""
csvDayFile = nil
rwIndex = 0
predIndex = 0
easyPhase = 0
rewindTicks = 0
stateSnapshots = {}
basePrice = 0
currentTime = ""
instrumentText = "RANDOM\nWALK"
introText = ""
currentDay = 1
weekDays = { "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY" }

prices = {}
minutePrices = {}
currentPrice = RANDOM_BASE or 32.40
currentBid = currentPrice - 0.01
currentAsk = currentPrice + 0.01
prevPrice = currentPrice

position = 0
avgPrice = 0
prevPosition = 0
pnl = 0
realizedPnl = 0
tendies = 1.0
tradeCount = 0
carryPosition = false
leverage = 1
positionLeverage = 1
followPlPrice = nil
followDist = nil

orderLines = {}
tradeMarkers = {}
particles = {}
milestonesHit = {}
bullBetPct = 0
bearBetPct = 0
bullEntryOddsSum = 0
bullEntryCount = 0
bearEntryOddsSum = 0
bearEntryCount = 0
bettingPnl = 0
bullBetMarkers = {}
bearBetMarkers = {}
currentBullOdds = 0
currentBearOdds = 0

-- ── HIGH SCORES ──
highScores = {}
highscoreInitials = ""
highscoreNewScore = 0

-- ── USER DATA ──
users = {}  -- { initials = { games=0, high=0, last="2026-01-01", features={} } }

function loadUsers()
    users = {}
    local content = love.filesystem.read("users.txt")
    if content then
        for line in content:gmatch("[^\r\n]+") do
            local initials, games, high, last, pinsStr, featStr, chartDisp = line:match("^(%u%u%u):(%d+):([%d%.%-]+):(.*):([^:]*):([^:]*):([^:]*)$")
            if not initials then
                -- Old format with defaultSpeed (8 fields)
                initials, games, high, last, pinsStr, featStr, chartDisp = line:match("^(%u%u%u):(%d+):([%d%.%-]+):(.*):([^:]*):([^:]*):([^:]*):[^:]*$")
            end
            if not initials then
                -- Older formats without chart/speed settings
                initials, games, high, last, pinsStr, featStr = line:match("^(%u%u%u):(%d+):([%d%.%-]+):(.*):([^:]-):(.*)$")
                if not initials then
                    initials, games, high, last, pinsStr = line:match("^(%u%u%u):(%d+):([%d%.%-]+):(.*):(%S-)$")
                    if not initials then
                        initials, games, high, last = line:match("^(%u%u%u):(%d+):([%d%.%-]+):(.*)$")
                    end
                end
            end
            if initials then
                local pinList = {}
                if pinsStr and pinsStr ~= "" then
                    for p in pinsStr:gmatch("[^,]+") do
                        table.insert(pinList, p)
                    end
                end
                local featList = {}
                if featStr and featStr ~= "" then
                    for f in featStr:gmatch("[^,]+") do
                        table.insert(featList, f)
                    end
                end
                users[initials] = {
                    games = tonumber(games) or 0,
                    high = tonumber(high) or 0,
                    last = last or "",
                    pins = pinList,
                    features = featList,
                    chartDisplay = chartDisp or "pct",

                }
            end
        end
    end
end

function saveUsers()
    local lines = {}
    for initials, data in pairs(users) do
        local pinStr = table.concat(data.pins or {}, ",")
        local featStr = table.concat(data.features or {}, ",")
        local chartDisp = data.chartDisplay or "pct"
        table.insert(lines, initials .. ":" .. data.games .. ":" .. string.format("%.2f", data.high) .. ":" .. (data.last or "") .. ":" .. pinStr .. ":" .. featStr .. ":" .. chartDisp)
    end
    table.sort(lines)
    love.filesystem.write("users.txt", table.concat(lines, "\n"))
end

function saveUserSettings(initials)
    if not users[initials] then return end
    local u = users[initials]
    u.chartDisplay = chartDisplay or "pct"
    u.xerMAType = xerMAType; u.xerMAPeriod = xerMAPeriod
    u.xeeMAType = xeeMAType; u.xeeMAPeriod = xeeMAPeriod
    saveUsers()
end

function saveUserData(initials, finalScore)
    if not users[initials] then
        users[initials] = { games = 0, high = 0, last = "", pins = {}, features = {} }
    end
    local u = users[initials]
    u.games = u.games + 1
    if finalScore > u.high then u.high = finalScore end
    u.last = os.date("%Y-%m-%d")
    saveUsers()
end

function getExistingUsers()
    local list = {}
    for initials, _ in pairs(users) do
        table.insert(list, initials)
    end
    table.sort(list)
    return list
end

-- Find a spot on the canvas that doesn't overlap existing sprites
function findEmptyCanvasSpot(sw, sh)
    local pad = sx(30)
    local margin = sx(60)
    local step = sx(100)  -- spiral step size
    -- Collect all existing rects
    local rects = {}
    if canvasWsb then
        table.insert(rects, { x = canvasWsb.x, y = canvasWsb.y, w = canvasWsb.w, h = canvasWsb.h })
    end
    for _, s in ipairs(canvasSprites) do
        table.insert(rects, { x = s.x, y = s.y, w = s.w, h = s.h })
    end
    -- Helper: check if a rect overlaps any existing rect
    local function overlaps(r)
        for _, e in ipairs(rects) do
            if r.x + r.w > e.x and r.x < e.x + e.w and r.y + r.h > e.y and r.y < e.y + e.h then
                return true
            end
        end
        return false
    end
    -- Spiral search outward from center
    local cx = safeWidth / 2 - sw / 2
    local cy = safeHeight / 2 - sh / 2
    -- Clamp to margins
    local function clampToBounds(x, y)
        return math.max(margin, math.min(safeWidth - sw - margin, x)),
               math.max(margin, math.min(safeHeight - sh - margin, y))
    end
    -- Check center first
    local cx2, cy2 = clampToBounds(cx, cy)
    if not overlaps({ x = cx2, y = cy2, w = sw + pad, h = sh + pad }) then
        return cx2, cy2
    end
    -- Spiral outward
    local dx, dy = 0, -1  -- direction vector (starting going up from center)
    local sx, sy = 0, 0   -- offset from center in steps
    local maxSteps = math.ceil(math.max(safeWidth, safeHeight) / step) * 2
    for i = 1, maxSteps * maxSteps do
        -- Check current position
        local px, py = clampToBounds(cx + sx * step, cy + sy * step)
        if not overlaps({ x = px, y = py, w = sw + pad, h = sh + pad }) then
            return px, py
        end
        -- Advance spiral
        if sx == sy or (sx < 0 and sx == -sy) or (sx > 0 and sx == 1 - sy) then
            dx, dy = -dy, dx  -- turn clockwise
        end
        sx, sy = sx + dx, sy + dy
    end
    -- Fallback: random
    return math.random(margin, safeWidth - sw - margin), math.random(margin, safeHeight - sh - margin)
end

function loadUserFeatures(initials)
    -- Clear all previously loaded features
    for k, _ in pairs(featureUnlocks) do
        featuresUnlocked[k] = false
        featureConfig[k] = false
    end
    if not users[initials] then return end
    if not users[initials].features then users[initials].features = {} end
    for _, f in ipairs(users[initials].features) do
        featuresUnlocked[f] = true
        featureConfig[f] = true
        -- If this is a sprite unlock, load it onto the canvas
        if f:find("^sprite_") then
            if f == "sprite_play_paws" then pawsSpriteUnlocked = true end
            if f == "sprite_play_dog" then dogSpriteUnlocked = true end
            if f == "sprite_play_ball" then ballSpriteUnlocked = true end
            if f == "sprite_tendy" then tendySpriteUnlocked = true end
            local fileName = f:gsub("^sprite_", "") .. ".png"
            -- Check if already loaded
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

function saveUserFeature(initials, featureKey)
    if not initials or initials == "" then return end
    if not users[initials] then
        users[initials] = { games = 0, high = 0, last = "", pins = {}, features = {} }
    end
    if not users[initials].features then users[initials].features = {} end
    for _, f in ipairs(users[initials].features) do
        if f == featureKey then return end  -- already saved
    end
    table.insert(users[initials].features, featureKey)
    saveUsers()
end

function unlockCanvasSprite(fileName, initials)
    local featKey = "sprite_" .. fileName:gsub("%.png$", ""):gsub("[^%w_]", "_")
    -- Check if already unlocked
    if users[initials] and users[initials].features then
        for _, f in ipairs(users[initials].features) do
            if f == featKey then return false end
        end
    end
    -- Load the sprite image
    local ok, img = pcall(love.graphics.newImage, "sprites/" .. fileName)
    if not ok then return false end
    local iw, ih = img:getDimensions()
    local spriteConfig = instrumentConfig and instrumentConfig.canvasSprites or {}
    local sizePct = 0.2  -- default from config
    for _, sc in ipairs(spriteConfig) do
        if sc.file == fileName then
            sizePct = sc.size or sizePct
            break
        end
    end
    local targetSize = sizePct * safeHeight
    local scale = math.min(1, targetSize / math.max(iw, ih))
    local sw, sh = iw * scale, ih * scale
    local x, y = findEmptyCanvasSpot(sw, sh)
    local entry = {
        image = img,
        file = fileName,
        x = x,
        y = y,
        scale = scale,
        w = sw,
        h = sh,
    }
    table.insert(canvasSprites, entry)
    -- Save to user profile
    if initials and initials ~= "" then
        saveUserFeature(initials, featKey)
    end
    -- Show unlock notification
    local displayName = fileName:gsub("%.png$", ""):gsub("_", " "):upper()
    unlockMsg = displayName .. " UNLOCKED!"
    unlockTimer = 2
    unlockAlpha = 1
    unlockSpriteImg = img
    -- Schedule haptic celebration: 5 random pops over 1.5s
    hapticPops = {}
    fireworkX = safeWidth / 2
    fireworkY = safeHeight / 2 - sy(90)
    for i = 1, 5 do
        table.insert(hapticPops, love.timer.getTime() + math.random() * 1.5)
    end
    table.sort(hapticPops)
    return true
end

function deleteUser(initials)
    users[initials] = nil
    -- Also remove from high scores
    loadHighScores()
    local filtered = {}
    for _, entry in ipairs(highScores) do
        if entry.initials ~= initials then
            table.insert(filtered, entry)
        end
    end
    highScores = filtered
    saveHighScores()
    saveUsers()
end

function loadHighScores()
    highScores = {}
    local content = love.filesystem.read("highscores.txt")
    if content then
        for line in content:gmatch("[^\r\n]+") do
            local initials, score = line:match("^(%u+):([%d%.%-]+)$")
            if initials and score then
                table.insert(highScores, { initials = initials, score = tonumber(score) })
            end
        end
    end
    table.sort(highScores, function(a, b) return a.score > b.score end)
end

function saveHighScores()
    local lines = {}
    for _, entry in ipairs(highScores) do
        table.insert(lines, entry.initials .. ":" .. string.format("%.2f", entry.score))
    end
    love.filesystem.write("highscores.txt", table.concat(lines, "\n"))
end

function addHighScore(initials, score)
    table.insert(highScores, { initials = initials, score = score })
    table.sort(highScores, function(a, b) return a.score > b.score end)
    -- Keep top 10
    while #highScores > 10 do
        table.remove(highScores)
    end
    saveHighScores()
end

function isNewHighScore(score)
    if #highScores < 10 then return true end
    return score > highScores[#highScores].score
end

function scalePnl(v)
    if basePrice and basePrice > 0 then
        return v * (100 / basePrice) * (positionLeverage or 1)
    end
    return 0
end

function fmtPnl(v)
    return string.format("%.0f", math.abs(v))
end

function fmtMoney(v)
    local s = string.format("%.0f", v)
    local k
    repeat
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
end

function refreshFeatureVisibility()
    local totalPnl = realizedPnl + pnl
    local featureNames = {
        buyStopButton = "BUY STOP",
        sellStopButton = "SELL STOP",
        stopLossButton = "P&L STOP",
        cancelButton = "CANCEL ALL",

        slowMA = "TEMA",
        mediumMA = "EMA",
        gridLines = "GRID LINES",

        cross = "CROSS",
        algo2 = "FOLLOW",
        algo3 = "ALGO 3",
        algo4 = "ALGO 4",
        algo5 = "ALGO 5",
        algo6 = "ALGO 6",
        algo7 = "ALGO 7",
        algo8 = "ALGO 8",
        algo9 = "ALGO 9",
    }
    for k, threshold in pairs(featureUnlocks) do
        if threshold ~= math.huge then  -- skip debug-only features (snow, ball, skier)
            local wasUnlocked = featuresUnlocked[k]
            if totalPnl >= threshold then
                featuresUnlocked[k] = true
            end
            featureConfig[k] = featuresUnlocked[k]
            if not wasUnlocked and featuresUnlocked[k] and featureNames[k] then
                unlockMsg = featureNames[k] .. " unlocked!"
                unlockTimer = 1
                unlockAlpha = 1
                spawnUnlockParticles(unlockMsg)
                saveUserFeature(playerInitials, k)
            end
        end
    end
end

function isFeatureUnlocked(key)
    -- Debug toggle can explicitly disable a feature even when unlockAll is on
    if featureConfig[key] == false then
        return false
    end
    if instrumentConfig and instrumentConfig.debug and instrumentConfig.debug.unlockAll then
        return true
    end
    return featureConfig[key] ~= false
end

-- ── TRADING ──
function rewardRhythmTap(manual)
    if manual and lastTradeTapTime and lastTradeTapTime > 0 then
        local now = love.timer.getTime()
        local beatInterval = 60 / (musicBPM or 125)
        local delta = now - lastTradeTapTime
        local offBeat = math.abs(delta - beatInterval) / beatInterval
        if offBeat < 0.20 then
            rhythmBeatCount = (rhythmBeatCount or 0) + 1
            if rhythmBeatCount % 4 == 0 and (tendies or 0) < 10 then
                tendies = math.min(TENDY_MAX, (tendies or 0) + 1)
                print("[DEBUG] Tendy awarded: rhythm tap (count=" .. rhythmBeatCount .. ", total=" .. tendies .. ")")
                if rhythmHearts then table.insert(rhythmHearts, { t = 0.5, type = "tendy" }) end
            else
                if rhythmHearts then table.insert(rhythmHearts, { t = 0.5, type = "heart" }) end
            end
        end
    end
    lastTradeTapTime = love.timer.getTime()
end

function buy()
    if position >= shareMax then return end
    local perTrade = math.min(100, math.max(1, math.floor(100 / (tradeIterations or 1))))
    -- Don't exceed remaining room to max long
    if position >= 0 then
        perTrade = math.min(perTrade, shareMax - position)
        if perTrade <= 0 then return end
    end
    playBuy()  -- sound immediately after confirming trade is valid
    if manualTradeFlag then rewardRhythmTap(true); manualTradeFlag = false end
    local fillPrice = currentAsk
    local prevPosition = position
    local prevAvg = avgPrice
    if position < 0 then
        local closed = math.min(perTrade, math.abs(position))
        realizedPnl = realizedPnl + scalePnl((avgPrice - fillPrice) * closed)
        position = position + perTrade
        if position == 0 then avgPrice = 0 end
    else
        if position == 0 then
            avgPrice = fillPrice
            positionLeverage = leverage  -- capture leverage for new position
        else
            avgPrice = (avgPrice * position + fillPrice * perTrade) / (position + perTrade)
        end
        position = position + perTrade
    end
    tradeCount = tradeCount + 1
    if prevPosition < 0 and position == 0 then
        local closed = math.min(perTrade, math.abs(prevPosition))
        local rawPnl = (prevAvg - fillPrice) * closed
        local pct = prevAvg > 0 and ((prevAvg - fillPrice) / prevAvg) * 100 or 0
        addResultMarker(rawPnl >= 0, fillPrice, pct)
    elseif prevPosition < 0 and position > 0 then
        local closed = math.abs(prevPosition)
        local rawPnl = (prevAvg - fillPrice) * closed
        local pct = prevAvg > 0 and ((prevAvg - fillPrice) / prevAvg) * 100 or 0
        addResultMarker(rawPnl >= 0, fillPrice, pct)
        table.insert(tradeMarkers, { price = fillPrice, type = "buy", idx = #prices })
        table.insert(delayedParticles, { timer = 0, price = fillPrice, idx = #prices, mood = "cold" })
    else
        table.insert(tradeMarkers, { price = fillPrice, type = "buy", idx = #prices })
        table.insert(delayedParticles, { timer = 0, price = fillPrice, idx = #prices, mood = "cold" })
    end
    Haptics.tap()
    updatePosition()
end

function sell()
    if position <= -shareMax then return end
    local perTrade = math.min(100, math.max(1, math.floor(100 / (tradeIterations or 1))))
    -- Don't exceed remaining room to max short
    if position <= 0 then
        perTrade = math.min(perTrade, shareMax + position)
        if perTrade <= 0 then return end
    end
    playSell()  -- sound immediately after confirming trade is valid
    if manualTradeFlag then rewardRhythmTap(true); manualTradeFlag = false end
    local fillPrice = currentBid
    local prevPosition = position
    local prevAvg = avgPrice
    if position > 0 then
        local closed = math.min(perTrade, position)
        realizedPnl = realizedPnl + scalePnl((fillPrice - avgPrice) * closed)
        position = position - perTrade
        if position == 0 then avgPrice = 0 end
    else
        if position == 0 then
            avgPrice = fillPrice
            positionLeverage = leverage  -- capture leverage for new position
        else
            avgPrice = (avgPrice * math.abs(position) + fillPrice * perTrade) / (math.abs(position) + perTrade)
        end
        position = position - perTrade
    end
    tradeCount = tradeCount + 1
    if prevPosition > 0 and position == 0 then
        local closed = math.min(perTrade, prevPosition)
        local rawPnl = (fillPrice - prevAvg) * closed
        local pct = prevAvg > 0 and ((fillPrice - prevAvg) / prevAvg) * 100 or 0
        addResultMarker(rawPnl >= 0, fillPrice, pct)
    elseif prevPosition > 0 and position < 0 then
        local closed = prevPosition
        local rawPnl = (fillPrice - prevAvg) * closed
        local pct = prevAvg > 0 and ((fillPrice - prevAvg) / prevAvg) * 100 or 0
        addResultMarker(rawPnl >= 0, fillPrice, pct)
        table.insert(tradeMarkers, { price = fillPrice, type = "sell", idx = #prices })
        table.insert(delayedParticles, { timer = 0, price = fillPrice, idx = #prices, mood = "warm" })
    else
        table.insert(tradeMarkers, { price = fillPrice, type = "sell", idx = #prices })
        table.insert(delayedParticles, { timer = 0, price = fillPrice, idx = #prices, mood = "warm" })
    end
    Haptics.tap()
    updatePosition()
end

function closePosition()
    closeAllPositions()
    if position == 0 and manualTradeFlag then
        rewardRhythmTap(true)
        manualTradeFlag = false
    end
end

-- Manual button wrappers (rhythm-eligible)
function manualBuy()
    manualTradeFlag = true
    buy()
end

function manualSell()
    manualTradeFlag = true
    sell()
end

function manualClose()
    manualTradeFlag = true
    closePosition()
end

function closeAllPositions()
    if position ~= 0 and avgPrice then
        local fillPrice = position > 0 and currentBid or currentAsk
        local closedPnl
        if position > 0 then
            closedPnl = (fillPrice - avgPrice) * position
        else
            closedPnl = (avgPrice - fillPrice) * math.abs(position)
        end
        realizedPnl = realizedPnl + scalePnl(closedPnl)
        local pct = ((fillPrice - avgPrice) / avgPrice) * 100
        addResultMarker(closedPnl >= 0, currentPrice, pct)
    end
    position = 0
    avgPrice = 0
    positionLeverage = 1
    followPlPrice = nil
    followDist = nil
    updatePosition()
end

function addResultMarker(win, price, pct)
    table.insert(tradeMarkers, {
        price = price,
        type = win and "star-win" or "star-lose",
        idx = #prices,
        pct = pct,
        time = love.timer.getTime()
    })
    if win then playStar() else playX() end
end

function updatePosition()
    local unrealized = 0
    if position ~= 0 and avgPrice then
        if position > 0 then
            unrealized = scalePnl((currentBid - avgPrice) * position)
        else
            unrealized = scalePnl((avgPrice - currentAsk) * math.abs(position))
        end
    end
    pnl = unrealized
    -- Remove PL stop when flat
    if position == 0 then
        for i = #orderLines, 1, -1 do
            if orderLines[i].type == "stop-loss" then
                table.remove(orderLines, i)
            end
        end
    end
    refreshFeatureVisibility()
end

-- ── STOPS ──
function addOrderLine(typ, price)
    local count = 0
    for _, l in ipairs(orderLines) do
        if l.type == typ then count = count + 1 end
    end
    local limits = { ["buy-stop"] = (tradeIterations or 1), ["sell-stop"] = (tradeIterations or 1), ["stop-loss"] = 999 }
    if count >= (limits[typ] or 999) then return end
    
    table.insert(orderLines, {
        type = typ,
        price = price,
        dragging = false
    })
end

function removeAllOrderLines()
    orderLines = {}
end

function removeOrderLinesByType(typ)
    for i = #orderLines, 1, -1 do
        if orderLines[i].type == typ then
            table.remove(orderLines, i)
        end
    end
end

function removeOrderLine(line)
    for i, l in ipairs(orderLines) do
        if l == line then
            table.remove(orderLines, i)
            return
        end
    end
end

function checkCrossings()
    local triggered = {}
    for _, line in ipairs(orderLines) do
        if line.type == "buy-stop" then
            if (prevPrice < line.price and currentPrice >= line.price) or
               (prevPrice > line.price and currentPrice <= line.price) then
                table.insert(triggered, { line = line, action = "buy" })
            end
        elseif line.type == "sell-stop" then
            if (prevPrice < line.price and currentPrice >= line.price) or
               (prevPrice > line.price and currentPrice <= line.price) then
                table.insert(triggered, { line = line, action = "sell" })
            end
        elseif line.type == "stop-loss" then
            if position ~= 0 and
               ((prevPrice < line.price and currentPrice >= line.price) or
                (prevPrice > line.price and currentPrice <= line.price)) then
                table.insert(triggered, { line = line, action = "flat" })
            end
        end
    end
    
    for _, t in ipairs(triggered) do
        for i = #orderLines, 1, -1 do
            if orderLines[i] == t.line then
                table.remove(orderLines, i)
                break
            end
        end
        if t.action == "flat" then
            closePosition()
        elseif t.action == "buy" then
            buy()
        elseif t.action == "sell" then
            sell()
        end
    end
end

-- Predictable price formula: calm waves 0-360 ticks, big waves after
function predictablePrice(predIndex, easyPhase)
    local t = predIndex / 60
    if predIndex < 360 then
        local calmAmp = EASY_BASE * 0.004
        local wave1 = math.sin(t * 5.0 + easyPhase) * calmAmp
        local wave2 = math.sin(t * 7.0 + easyPhase + 1.7) * calmAmp * 0.5
        local noise = (math.random() - 0.5) * 0.015
        return EASY_BASE + wave1 + wave2 + noise
    else
        local bigT = (predIndex - 360) / 60
        local ampVar = 1.0 + math.sin(bigT * 0.031) * 0.7
        local amp = EASY_BASE * 0.025 * ampVar
        local wave1 = math.sin(bigT * 0.70 + easyPhase) * amp
        local wave2 = math.sin(bigT * 1.50 + easyPhase + 1.2) * amp * 0.4
        local drift = bigT * 0.003
        local noise = (math.random() - 0.5) * 0.03
        return EASY_BASE + wave1 + wave2 + drift + noise
    end
end

-- ── TICK ──
function tick()
    if tickPaused or not dataMode then return end
    prevPrice = currentPrice
    
    if dataMode == "csv" then
        if csvIndex >= #csvData then
            dataMode = nil
            Replay.stop()
            settleBets()
            saveUserData(playerInitials, startingBalance + realizedPnl)
            if position ~= 0 then
                goToScreen(SCREENS.EOD)
            else
                goToScreen(SCREENS.RECAP)
            end
            return
        end
        local row = csvData[csvIndex + 1]
        csvIndex = csvIndex + 1
        currentBid = row.bid
        currentAsk = row.ask
        currentTime = row.time
        currentPrice = round3((row.bid + row.ask) / 2)
        table.insert(prices, currentPrice)
        -- minutePrices: one entry per minute for CSV
        if currentTime ~= lastCsvMinute then
            table.insert(minutePrices, currentPrice)
            lastCsvMinute = currentTime
            -- Ramp thrust up toward target each minute
            if thrustRampActive and effectiveSpeedMult and speedMult and effectiveSpeedMult < speedMult then
                effectiveSpeedMult = math.min(speedMult, effectiveSpeedMult + 0.1)
            end
        end
        -- Replay: check for automated demo actions
        Replay.tick(currentTime)
    else
        rwIndex = rwIndex + 1
        if rwIndex >= RW_TOTAL then
            dataMode = nil
            Replay.stop()
            settleBets()
            saveUserData(playerInitials, startingBalance + realizedPnl)
            if position ~= 0 then
                goToScreen(SCREENS.EOD)
            else
                goToScreen(SCREENS.RECAP)
            end
            return
        end
        if dataMode == "predictable" then
            predIndex = predIndex + 1
            currentPrice = round3(predictablePrice(predIndex, easyPhase))
        else
            local delta = (math.random() - 0.495) * 0.06
            currentPrice = round3(currentPrice + delta)
        end
        currentBid = round3(currentPrice - 0.01)
        currentAsk = round3(currentPrice + 0.01)
        currentTime = rwTime(rwIndex)
        table.insert(prices, currentPrice)
        -- minutePrices: one entry per minute (every 12 ticks)
        if rwIndex % TICKS_PER_MINUTE == 0 then
            table.insert(minutePrices, currentPrice)
            -- Ramp thrust up toward target each minute
            if thrustRampActive and effectiveSpeedMult and speedMult and effectiveSpeedMult < speedMult then
                effectiveSpeedMult = math.min(speedMult, effectiveSpeedMult + 0.1)
            end
        end
        -- Replay: check for automated demo actions
        Replay.tick(currentTime)
    end
    
    checkCrossings()
    updatePosition()
    
    -- FOLLOW algo: trailing stop-loss
    if activeAlgos and activeAlgos["algo2"] and position ~= 0 then
        local plPrice = nil
        for _, l in ipairs(orderLines) do
            if l.type == "stop-loss" then
                plPrice = l.price
                break
            end
        end
        if plPrice then
            local isSL = (position > 0 and plPrice < currentPrice) or (position < 0 and plPrice > currentPrice)
            if isSL then
                -- Re-capture distance if PL was just moved (user dragged it)
                if not followPlPrice or followPlPrice ~= plPrice then
                    followDist = math.abs(currentPrice - plPrice)
                    followPlPrice = plPrice
                end
                -- Trail: move PL to maintain distance from current price
                local newPl
                if position > 0 then
                    newPl = currentPrice - followDist
                    if newPl > plPrice then
                        plPrice = newPl
                    end
                else
                    newPl = currentPrice + followDist
                    if newPl < plPrice then
                        plPrice = newPl
                    end
                end
                -- Apply the updated PL
                for i = #orderLines, 1, -1 do
                    if orderLines[i].type == "stop-loss" then
                        orderLines[i].price = round3(plPrice)
                        followPlPrice = round3(plPrice)
                        break
                    end
                end
            else
                -- TP mode: clear follow state
                followPlPrice = nil
                followDist = nil
            end
        else
            followPlPrice = nil
            followDist = nil
        end
    else
        followPlPrice = nil
        followDist = nil
    end
    -- Cross mode: auto-trading
    if crossValues and crossIndex then
        local mode = crossValues[crossIndex]
        if (mode == "ALL" or mode == "STOPS") and #prices >= 2 then
            recalcMAs()
            local xer = cachedXER and cachedXER[#cachedXER]
            local xee = cachedXEE and cachedXEE[#cachedXEE]
            if xer and xee then
                local currentRelation = xer > xee and 1 or (xer < xee and -1 or 0)
                if prevXERvsXEE ~= 0 and prevXERvsXEE ~= currentRelation then
                    if mode == "ALL" then
                        local savedIters = tradeIterations
                        tradeIterations = 1  -- full 100 shares
                        if currentRelation == 1 then
                            closePosition()
                            buy()
                        else
                            closePosition()
                            sell()
                        end
                        tradeIterations = savedIters
                    elseif mode == "STOPS" then
                        closePosition()
                        local step = currentPrice * (instrumentConfig.stopStepPct or DEFAULT_STOP_STEP_PCT)
                        local n = (tradeIterations or 1)
                        if currentRelation == 1 then
                            -- Bullish cross: place buy-stops above price
                            for i = #orderLines, 1, -1 do
                                if orderLines[i].type == "sell-stop" then
                                    table.remove(orderLines, i)
                                end
                            end
                            for _ = 1, n do
                                local highest = -math.huge
                                for _, l in ipairs(orderLines) do
                                    if l.type == "buy-stop" and l.price > highest then
                                        highest = l.price
                                    end
                                end
                                local price = highest == -math.huge and (currentAsk + step) or (highest + step)
                                addOrderLine("buy-stop", round3(price))
                            end
                        else
                            -- Bearish cross: place sell-stops below price
                            for i = #orderLines, 1, -1 do
                                if orderLines[i].type == "buy-stop" then
                                    table.remove(orderLines, i)
                                end
                            end
                            for _ = 1, n do
                                local lowest = math.huge
                                for _, l in ipairs(orderLines) do
                                    if l.type == "sell-stop" and l.price < lowest then
                                        lowest = l.price
                                    end
                                end
                                local price = lowest == math.huge and (currentBid - step) or (lowest - step)
                                addOrderLine("sell-stop", round3(price))
                            end
                        end
                    end
                end
                prevXERvsXEE = currentRelation
            end
        end
    end
    -- Snapshot state for rewind
    table.insert(stateSnapshots, {
        position = position,
        avgPrice = avgPrice,
        pnl = pnl,
        realizedPnl = realizedPnl,
        total = startingBalance + realizedPnl + pnl,
    })
end

function rwTime(idx)
    local min = math.floor(idx / TICKS_PER_MINUTE)
    local total = 9 * 60 + 30 + min
    local h = math.floor(total / 60)
    local m = total % 60
    return string.format("%02d:%02d", h, m)
end

-- ── PARTICLES ──
function spawnParticles(px, py, mood)
    local palette
    if mood == "cold" then
        palette = {
            {0, 0.78, 0.41},   -- green
            {0.20, 0.80, 0.60}, -- turquoise
            {0.10, 0.60, 0.80}, -- teal
            {0.30, 0.45, 0.75}, -- blue
            {0.20, 0.70, 0.30}, -- bright green
            {0.15, 0.85, 0.70}, -- mint
            {0.40, 0.55, 0.90}, -- periwinkle
            {0.10, 0.90, 0.50}, -- spring green
        }
    else
        palette = {
            {0.91, 0.25, 0.38}, -- red
            {0.95, 0.50, 0.15}, -- orange
            {0.94, 0.71, 0.16}, -- gold
            {0.85, 0.35, 0.55}, -- pink
            {0.90, 0.60, 0.20}, -- amber
            {0.80, 0.30, 0.30}, -- crimson
            {0.95, 0.65, 0.35}, -- peach
            {0.85, 0.45, 0.10}, -- burnt orange
        }
    end
    local marker = { price = px, idx = py }
    local count = 50 + math.random(30)
    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local speed = 2.0 + math.random() * 6.0
        local c = palette[math.random(#palette)]
        table.insert(particles, {
            marker = marker,
            offsetX = 0, offsetY = 0,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            life = 30 + math.random() * 40,
            maxLife = 70,
            r = c[1], g = c[2], b = c[3],
            shape = math.random() < 0.35 and "star" or "circle",
            size = 5.0 + math.random() * 10.0,
        })
    end
end

-- ── CHART REWIND ──
function restoreRewindState()
    local rew = rewindTicks or 0
    if rew <= 0 then return end
    local idx = #prices - rew
    if idx >= 1 and stateSnapshots[idx] then
        local s = stateSnapshots[idx]
        position = s.position
        avgPrice = s.avgPrice
        pnl = s.pnl
        realizedPnl = s.realizedPnl
    end
end

function resumeFromRewind()
    local rew = rewindTicks or 0
    if rew <= 0 then return end
    local newLen = #prices - rew
    if newLen < 1 then newLen = 1 end
    for i = newLen + 1, #prices do prices[i] = nil end
    -- Truncate snapshots
    for i = newLen + 1, #stateSnapshots do stateSnapshots[i] = nil end
    -- Remove trade markers and particles beyond new end
    for i = #tradeMarkers, 1, -1 do
        if tradeMarkers[i].idx > newLen then table.remove(tradeMarkers, i) end
    end
    for i = #particles, 1, -1 do
        if particles[i].marker and particles[i].marker.idx > newLen then
            table.remove(particles, i)
        end
    end
    if dataMode == "random" or dataMode == "predictable" then
        rwIndex = math.max(0, rwIndex - rew)
        if dataMode == "predictable" then
            predIndex = math.max(0, predIndex - rew)
        end
    elseif dataMode == "csv" then
        csvIndex = math.max(0, csvIndex - rew)
    end
    currentPrice = prices[newLen]
    currentBid = round3(currentPrice - 0.01)
    currentAsk = round3(currentPrice + 0.01)
    prevPrice = currentPrice
    rewindTicks = 0
    tickPaused = false
    showDogImage = false
    rewindUnlocked = false
    updatePosition()
end

-- ── UNLOCK NOTIFICATION ──
unlockMsg = nil
unlockTimer = 0
unlockAlpha = 0

-- Firework particles for unlock text bursts
function spawnUnlockParticles(message)
    local cx = safeWidth / 2
    local cy = safeHeight / 2
    local palette = {
        {0.94, 0.71, 0.16}, {0.91, 0.25, 0.38}, {0.0,  0.78, 0.41},
        {0.48, 0.41, 0.93}, {0.95, 0.50, 0.15}, {0.20, 0.80, 0.60},
    }
    local fh = sy(45)
    local textW = string.len(message) * fh * 0.6
    local startX = cx - textW / 2
    for i = 1, #message do
        local lx = startX + (i - 1) * fh * 0.6 + fh * 0.3
        for j = 1, 8 do
            local angle = (math.pi * 2 * j) / 8 + math.random() * 0.5
            local speed = 1.0 + math.random() * 1.5
            local c = palette[(i + j) % #palette + 1]
            table.insert(particles, {
                ox = lx, oy = cy,
                offsetX = 0, offsetY = 0,
                vx = math.cos(angle) * speed,
                vy = math.sin(angle) * speed,
                life = 30 + math.random() * 15,
                maxLife = 45,
                r = c[1], g = c[2], b = c[3],
                isUnlock = true,
            })
        end
    end
end

function spawnFireworkBurst(cx, cy)
    cx = cx or math.random(sx(100), safeWidth - sx(100))
    cy = cy or math.random(sy(100), safeHeight - sy(100))
    -- Spread origin around the center point, outside the sprite bounds
    local spread = sy(120)
    local ox = cx + (math.random() - 0.5) * spread * 2
    local oy = cy + (math.random() - 0.5) * spread * 2
    local palette = {
        {0.94, 0.71, 0.16}, {0.91, 0.25, 0.38}, {0.0,  0.78, 0.41},
        {0.48, 0.41, 0.93}, {0.95, 0.50, 0.15}, {0.20, 0.80, 0.60},
        {1.0,  1.0,  1.0},  {0.70, 0.30, 0.85},
    }
    for j = 1, 12 do
        local angle = math.random() * math.pi * 2
        local speed = 3.0 + math.random() * 4.0
        local c = palette[math.random(#palette)]
        table.insert(particles, {
            ox = ox, oy = oy,
            offsetX = 0, offsetY = 0,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed - 0.5,
            life = 30 + math.random() * 25,
            maxLife = 55,
            r = c[1], g = c[2], b = c[3],
            isUnlock = true,
        })
    end
end

function updateParticles(dt)
    -- Process delayed particle spawns
    for i = #delayedParticles, 1, -1 do
        local dp = delayedParticles[i]
        dp.timer = dp.timer - dt
        if dp.timer <= 0 then
            spawnParticles(dp.price, dp.idx, dp.mood)
            table.remove(delayedParticles, i)
        end
    end
    local cs = getChartSpan()
    local n = math.min(#prices, cs)
    for i = #particles, 1, -1 do
        local p = particles[i]
        -- Recalculate center from marker position on chart
        if p.marker and n >= 2 and (narrowChartW or 0) > 0 then
            local mn, mx = priceRange()
            local step = ((narrowChartW or chartW) * 0.97) / (cs - 1)
            local firstIdx = #prices - n
            local relIdx = p.marker.idx - firstIdx
            if relIdx >= 1 and relIdx <= n then
                local cx = (narrowChartX or chartX) + (relIdx - 1) * step
                local cy = priceToY(toPct(p.marker.price), mn, mx, chartY, chartH)
                p.x = cx + p.offsetX
                p.y = cy + p.offsetY
            end
        elseif p.isUnlock then
            p.x = p.ox + p.offsetX
            p.y = p.oy + p.offsetY
        end
        p.offsetX = p.offsetX + p.vx * dt * 60
        p.offsetY = p.offsetY + p.vy * dt * 60
        p.life = p.life - dt * 60
        if p.life <= 0 then
            table.remove(particles, i)
        end
    end
end

-- ── SKIP TO 15:55 ──
function settleBets()
    if bullBetPct == 0 and bearBetPct == 0 then return end
    local open = prices[1]
    local close = prices[#prices]
    if not open or not close or open == close then return end
    local bullWins = close > open
    local winPct = bullWins and bullBetPct or bearBetPct
    local losePct = bullWins and bearBetPct or bullBetPct
    local betAmount = math.floor(startingBalance * winPct / 100)
    local loseAmount = math.floor(startingBalance * losePct / 100)
    realizedPnl = realizedPnl + betAmount - loseAmount
    bettingPnl = bettingPnl + betAmount - loseAmount
    if winPct > 0 then
        toastMsg = string.format("%s WINS! +$%d", bullWins and "BULL" or "BEAR", betAmount)
        toastTimer = 3
    end
    bullBetPct = 0
    bearBetPct = 0
    bullEntryOddsSum = 0
    bullEntryCount = 0
    bearEntryOddsSum = 0
    bearEntryCount = 0
end

function skipTo1555()
    if not dataMode then return end
    if position ~= 0 then
        toastMsg = "Close your position first"
        toastTimer = 2
        return
    end
    removeAllOrderLines()
    tickPaused = true
    
    if dataMode == "csv" then
        local target = csvIndex + 1
        for i = csvIndex + 1, #csvData do
            if csvData[i].time >= "15:55" then
                target = i
                break
            end
            if i == #csvData then target = i end
        end
        for i = csvIndex + 1, target do
            local row = csvData[i]
            local mid = round3((row.bid + row.ask) / 2)
            table.insert(prices, mid)
        end
        csvIndex = target
        if csvIndex <= #csvData then
            local row = csvData[csvIndex]
            if row then
                currentBid = row.bid
                currentAsk = row.ask
                currentTime = row.time
                currentPrice = round3((row.bid + row.ask) / 2)
                prevPrice = currentPrice
            end
        end
    else
        local target = math.min(4620, RW_TOTAL - 1)
        for i = rwIndex + 1, target do
            local price
            if dataMode == "predictable" then
                predIndex = predIndex + 1
                price = predictablePrice(predIndex, easyPhase)
            else
                local delta = (math.random() - 0.495) * 0.06
                price = currentPrice + delta
            end
            currentPrice = round3(price)
            table.insert(prices, currentPrice)
        end
        rwIndex = target
        currentTime = rwTime(rwIndex)
        currentBid = round3(currentPrice - 0.01)
        currentAsk = round3(currentPrice + 0.01)
        prevPrice = currentPrice
    end
    updatePosition()
    tickPaused = false
end

function initTradingSession()
    recalcLayout()
    updatePosition()
end

function continueTrading()
    currentDay = currentDay + 1

    -- Unlock sprites for finishing specific days
    local spriteUnlocked = false
    if currentDay == 2 then
        spriteUnlocked = unlockCanvasSprite("come_back.png", playerInitials)
    elseif currentDay == 3 then
        spriteUnlocked = unlockCanvasSprite("come_back_no.png", playerInitials)
    elseif currentDay == 4 then
        spriteUnlocked = unlockCanvasSprite("hide_cats_eyes.png", playerInitials)
    elseif currentDay == 5 then
        spriteUnlocked = unlockCanvasSprite("diamond_hands.png", playerInitials)
    elseif currentDay == 6 then
        spriteUnlocked = unlockCanvasSprite("horse_squinting.png", playerInitials)
    end

    if currentDay > 5 then
        local finalScore = startingBalance + realizedPnl
        saveUserData(playerInitials, finalScore)
        loadHighScores()
        highscoreNewScore = finalScore
        highscoreInitials = ""
        goToScreen(SCREENS.HIGHSCORE)
        return
    end
    local isCarrying = carryPosition
    local savedMode = dataMode
    local savedGroup = csvGroupName
    
    startingBalance = startingBalance + realizedPnl
    realizedPnl = 0
    pnl = 0
    tradeCount = 0
    bettingPnl = 0
    bullBetPct = 0
    bearBetPct = 0
    bullEntryOddsSum = 0
    bullEntryCount = 0
    bearEntryOddsSum = 0
    bearEntryCount = 0
    bullBetMarkers = {}
    bearBetMarkers = {}
    prices = {}
    minutePrices = {}
    csvData = nil
    csvIndex = 0
    csvInstrument = nil
    csvGroupName = ""
    csvDayFile = nil
    basePrice = 0
    rwIndex = 0
    predIndex = 0
    easyPhase = 0
    rewindTicks = 0
    stateSnapshots = {}
    dataMode = nil
    removeAllOrderLines()
    tradeMarkers = {}
    particles = {}
    milestonesHit = {}
    
    if isCarrying then
        carryPosition = false
    else
        position = 0
        avgPrice = 0
        prevPosition = 0
    end
    
    updatePosition()
    
    -- Only show achievement screen when a new sprite was unlocked
    if spriteUnlocked then
        goToScreen(SCREENS.ACHIEVEMENT)
        -- Store routing target for when player taps CONTINUE
        achievementNextScreen = SCREENS.SELECTOR
        achievementCarryMode = isCarrying
        achievementSavedMode = savedMode
        achievementSavedGroup = savedGroup
    else
        goToScreen(SCREENS.SELECTOR)
    end
end

introText = ""
instrumentText = "RANDOM"

-- ── DEMO / REPLAY ──
function startDemo(scriptIdx)
    Replay.stop()
    local script = Replay.start(scriptIdx)
    if not script then
        toastMsg = "No demo scripts available"
        toastTimer = 2
        return
    end

    -- Reset game state
    position = 0
    avgPrice = 0
    pnl = 0
    realizedPnl = 0
    tendies = 1.0
    tradeCount = 0
    carryPosition = false
    orderLines = {}
    activeAlgos = {}
    tradeMarkers = {}
    particles = {}
    rhythmHearts = {}
    delayedParticles = {}
    bullBetPct = 0
    bearBetPct = 0
    bullEntryOddsSum = 0
    bullEntryCount = 0
    bearEntryOddsSum = 0
    bearEntryCount = 0
    bettingPnl = 0
    bullBetMarkers = {}
    bearBetMarkers = {}

    speedMult = 0.3
    effectiveSpeedMult = 0.3
    thrustRampActive = false
    -- Reset sliders to their game defaults (matching love.load)
    if speedSlider then
        local spd = 0.3
        speedSlider.value = spd
        speedSlider.onChange(spd)
    end
    if levSlider then
        local lev = instrumentConfig.defaultLeverage or 1
        levSlider.value = lev
        levSlider.onChange(lev)
        leverage = lev
    end
    if iterSlider then
        local iters = instrumentConfig.defaultIterations or 10
        tradeIterations = iters
        local iterPos = 1
        for i, v in ipairs(ITER_VALUES) do
            if v == iters then iterPos = i; break end
        end
        iterSlider.value = iterPos
        iterSlider.onChange(iterPos)
    end

    -- Use the script's CSV data
    -- csvFileData keys include the "data/" prefix from files.lua, so we need to match
    local inst = script.instrument
    local dayKey = "data/" .. script.csvDay
    local group = script.groupName

    -- Find the matching day key (could be exact or partial match)
    local data = nil
    local matchedDay = nil
    for d, csv in pairs(csvFileData) do
        if d == dayKey then
            data = csv
            matchedDay = d
            break
        end
    end
    if not data then
        for d, csv in pairs(csvFileData) do
            if d:find(script.csvDay) then
                data = csv
                matchedDay = d
                break
            end
        end
    end
    if not data or not data[inst] then
        toastMsg = "Demo data not found: " .. script.csvDay .. "/" .. inst
        toastTimer = 3
        Replay.stop()
        return
    end

    dataMode = "csv"
    csvInstrument = inst
    csvGroupName = group
    csvDayFile = matchedDay or ("data/" .. script.csvDay)
    applyConfig(inst)
    csvData = interpolate5s(data[inst])
    csvIndex = 0
    instrumentText = group

    -- Reset all timing state for fresh ticks
    tickPaused = false
    tickTimer = 0
    rewindTicks = 0
    rewindHeld = false
    rewindHoldTime = 0
    rewindTendieConsumed = false
    wasRewinding = false
    prevRewindEnd = 0
    pressedButtonId = nil

    prices = {}
    minutePrices = {}
    lastCsvMinute = ""
    local row = csvData[1]
    local mid = round3((row.bid + row.ask) / 2)
    basePrice = mid
    table.insert(prices, mid)
    table.insert(minutePrices, mid)
    lastCsvMinute = row.time
    currentPrice = mid
    currentBid = row.bid
    currentAsk = row.ask
    currentTime = row.time
    stateSnapshots = { { position = 0, avgPrice = 0, pnl = 0, realizedPnl = 0, total = 10000 } }
    -- Use demo initials for scoring
    playerInitials = "DEM"

    goToScreen(SCREENS.TRADING)
end

function startGame(name)
    Replay.stop()
    orderLines = {}
    activeAlgos = {}
    speedMult = 0.3
    effectiveSpeedMult = 0.3
    thrustRampActive = false
    if speedSlider then
        speedSlider.value = 0.3
    end
    if levSlider then
        levSlider.value = 1
        levSlider.onChange(1)
    end
    if name == "RANDOM" then
        switchPreserveIndex = nil
        switchPreserveDayFile = nil
        dataMode = "random"
        applyConfig("RANDOM")
        rwIndex = 0
        currentTime = rwTime(0)
        instrumentText = "RANDOM"
        prices = {}
        minutePrices = {}
        table.insert(prices, RANDOM_BASE)
        table.insert(minutePrices, RANDOM_BASE)
        basePrice = RANDOM_BASE
        currentPrice = RANDOM_BASE
        currentBid = round3(RANDOM_BASE - 0.01)
        currentAsk = round3(RANDOM_BASE + 0.01)
        stateSnapshots = { { position = 0, avgPrice = 0, pnl = 0, realizedPnl = 0, total = 10000 } }
        goToScreen(SCREENS.TRADING)
    elseif name == "EASY" then
        switchPreserveIndex = nil
        switchPreserveDayFile = nil
        dataMode = "predictable"
        applyConfig("EASY")
        predIndex = 0
        easyPhase = math.random() * math.pi * 2  -- random start direction
        currentTime = rwTime(0)
        instrumentText = "EASY"
        prices = {}
        minutePrices = {}
        table.insert(prices, EASY_BASE)
        table.insert(minutePrices, EASY_BASE)
        basePrice = EASY_BASE
        currentPrice = EASY_BASE
        currentBid = round3(EASY_BASE - 0.01)
        currentAsk = round3(EASY_BASE + 0.01)
        stateSnapshots = { { position = 0, avgPrice = 0, pnl = 0, realizedPnl = 0, total = 10000 } }
        goToScreen(SCREENS.TRADING)
    else
        local members = getGroupMembers(name)
        if #members == 0 then return end
        local inst = members[math.random(#members)]
        
        -- Use preserved index/day file when switching instruments mid-day
        local startIdx = 0
        if switchPreserveIndex and switchPreserveDayFile then
            -- Check if the new instrument has data on the preserved day
            if csvFileData[switchPreserveDayFile] and csvFileData[switchPreserveDayFile][inst] then
                csvDayFile = switchPreserveDayFile
                startIdx = switchPreserveIndex
            end
            switchPreserveIndex = nil
            switchPreserveDayFile = nil
        end
        if startIdx == 0 then
            local availDays = {}
            for day, data in pairs(csvFileData) do
                if data[inst] then table.insert(availDays, day) end
            end
            if #availDays == 0 then return end
            csvDayFile = availDays[math.random(#availDays)]
        end
        
        dataMode = "csv"
        csvInstrument = inst
        csvGroupName = name
        applyConfig(inst)
        csvData = interpolate5s(csvFileData[csvDayFile][inst])
        csvIndex = math.min(startIdx, #csvData)
        stateSnapshots = { { position = 0, avgPrice = 0, pnl = 0, realizedPnl = 0, total = 10000 } }
        instrumentText = name
        
        prices = {}
        minutePrices = {}
        lastCsvMinute = ""
        -- Catch up to the preserved index
        local limit = math.min(#csvData, csvIndex + 1)
        local lastRow
        for idx = 1, limit do
            lastRow = csvData[idx]
            if lastRow then
                local mid = round3((lastRow.bid + lastRow.ask) / 2)
                table.insert(prices, mid)
                if lastRow.time ~= lastCsvMinute then
                    table.insert(minutePrices, mid)
                    lastCsvMinute = lastRow.time
                end
                if idx == limit then
                    currentPrice = mid
                    currentBid = lastRow.bid
                    currentAsk = lastRow.ask
                    currentTime = lastRow.time
                end
            end
        end
        basePrice = prices[1] or currentPrice
        
        goToScreen(SCREENS.TRADING)
    end
end

-- ── CSV INTERPOLATION ──
function interpolate5s(minuteData)
    local result = {}
    for i = 1, #minuteData do
        local curr = minuteData[i]
        local nxt = minuteData[math.min(i + 1, #minuteData)]
        for j = 0, 11 do
            local t = j / TICKS_PER_MINUTE
            local noise = 0
            if math.random() > 0.4 then
                noise = (math.random() - 0.5) * (0.005 + math.random() * 0.015) * 2
            end
            table.insert(result, {
                bid = round3(curr.bid + (nxt.bid - curr.bid) * t + noise),
                ask = round3(curr.ask + (nxt.ask - curr.ask) * t + noise),
                time = curr.time,
                date = curr.date
            })
        end
    end
    return result
end
