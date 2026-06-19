-- ── GAME STATE ──
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
tendies = 1
tradeCount = 0
carryPosition = false
leverage = 1

orderLines = {}
tradeMarkers = {}
particles = {}
milestonesHit = {}

-- ── HIGH SCORES ──
highScores = {}
highscoreInitials = ""
highscoreNewScore = 0

-- ── USER DATA ──
users = {}  -- { initials = { games=0, high=0, last="2026-01-01", pins={} } }
pinAwarded = nil  -- pin filename just awarded (for ACHIEVEMENT screen)

function loadUsers()
    users = {}
    local content = love.filesystem.read("users.txt")
    if content then
        for line in content:gmatch("[^\r\n]+") do
            local initials, games, high, last, pinsStr, featStr, chartDisp, defSpeed = line:match("^(%u%u%u):(%d+):([%d%.%-]+):(.*):([^:]*):([^:]*):([^:]*):([^:]*)$")
            if not initials then
                -- Old formats without chart/speed settings
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
                    defaultSpeed = tonumber(defSpeed) or 0.5,
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
        local defSpeed = string.format("%.3f", data.defaultSpeed or 0.5)
        table.insert(lines, initials .. ":" .. data.games .. ":" .. string.format("%.2f", data.high) .. ":" .. (data.last or "") .. ":" .. pinStr .. ":" .. featStr .. ":" .. chartDisp .. ":" .. defSpeed)
    end
    table.sort(lines)
    love.filesystem.write("users.txt", table.concat(lines, "\n"))
end

function saveUserSettings(initials)
    if not users[initials] then return end
    local u = users[initials]
    u.chartDisplay = chartDisplay or "pct"
    u.defaultSpeed = (speedSlider and speedSlider.value) or 0.5
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

-- All 9 pin meme filenames
local ALL_PINS = {
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

function awardRandomPin(initials)
    -- Auto-create user entry if missing (defensive)
    if not users[initials] then
        users[initials] = { games = 0, high = 0, last = "", pins = {}, features = {} }
    end
    if not users[initials].pins then users[initials].pins = {} end
    local owned = {}
    for _, p in ipairs(users[initials].pins) do
        owned[p] = true
    end
    local available = {}
    for _, p in ipairs(ALL_PINS) do
        if not owned[p] then table.insert(available, p) end
    end
    local pick
    if #available == 0 then
        pick = ALL_PINS[math.random(#ALL_PINS)]
    else
        pick = available[math.random(#available)]
        table.insert(users[initials].pins, pick)
    end
    saveUsers()
    return pick
end

function getUserPins(initials)
    if not users[initials] then return {} end
    return users[initials].pins or {}
end

function hasAnyPins(initials)
    local p = getUserPins(initials)
    return p and #p > 0
end

function getExistingUsers()
    local list = {}
    for initials, _ in pairs(users) do
        table.insert(list, initials)
    end
    table.sort(list)
    return list
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
    end
end

function saveUserFeature(initials, featureKey)
    if not users[initials] then return end
    if not users[initials].features then users[initials].features = {} end
    for _, f in ipairs(users[initials].features) do
        if f == featureKey then return end  -- already saved
    end
    table.insert(users[initials].features, featureKey)
    saveUsers()
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
        return v * (100 / basePrice) * (leverage or 1)
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
        endDayButton = "END DAY",
        slowMA = "TEMA",
        mediumMA = "EMA",
        gridLines = "GRID LINES",
    }
    for k, threshold in pairs(featureUnlocks) do
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

function isFeatureUnlocked(key)
    if instrumentConfig and instrumentConfig.debug and instrumentConfig.debug.unlockAll then
        return true
    end
    return featureConfig[key] ~= false
end

-- ── TRADING ──
function buy()
    if position >= shareMax then return end
    local perTrade = math.min(100, math.max(1, math.floor(100 / (tradeIterations or 1))))
    -- Don't exceed remaining room to max long
    if position >= 0 then
        perTrade = math.min(perTrade, shareMax - position)
        if perTrade <= 0 then return end
    end
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
        spawnParticles(fillPrice, #prices, "cold")
    else
        table.insert(tradeMarkers, { price = fillPrice, type = "buy", idx = #prices })
        spawnParticles(fillPrice, #prices, "cold")
        playBuy()
    end
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
        spawnParticles(fillPrice, #prices, "warm")
    else
        table.insert(tradeMarkers, { price = fillPrice, type = "sell", idx = #prices })
        spawnParticles(fillPrice, #prices, "warm")
        playSell()
    end
    updatePosition()
end

function closePosition()
    if position == 0 or not avgPrice then return end
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
    position = 0
    avgPrice = 0
    updatePosition()
end

function closeAllPositions(label)
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

-- ── TICK ──
function tick()
    if tickPaused or not dataMode then return end
    prevPrice = currentPrice
    
    if dataMode == "csv" then
        if csvIndex >= #csvData then
            dataMode = nil
            saveUserData(playerInitials, startingBalance + realizedPnl)
            if position ~= 0 then
                SCREEN = SCREENS.EOD
            else
                SCREEN = SCREENS.RECAP
            end
            return
        end
        local row = csvData[csvIndex + 1]
        csvIndex = csvIndex + 1
        currentBid = row.bid
        currentAsk = row.ask
        currentTime = row.time
        currentPrice = math.floor(((row.bid + row.ask) / 2) * 1000 + 0.5) / 1000
        table.insert(prices, currentPrice)
    else
        rwIndex = rwIndex + 1
        if rwIndex >= RW_TOTAL then
            dataMode = nil
            saveUserData(playerInitials, startingBalance + realizedPnl)
            if position ~= 0 then
                SCREEN = SCREENS.EOD
            else
                SCREEN = SCREENS.RECAP
            end
            return
        end
        if dataMode == "predictable" then
            predIndex = predIndex + 1
            local t = predIndex / 60
            local price
            if predIndex < 360 then
                -- Calm opening: small waves 0.5-0.8%, 5-8 min periods
                local calmAmp = EASY_BASE * 0.004  -- ~0.4% base
                local wave1 = math.sin(t * 5.0 + easyPhase) * calmAmp
                local wave2 = math.sin(t * 7.0 + easyPhase + 1.7) * calmAmp * 0.5
                local noise = (math.random() - 0.5) * 0.015
                price = EASY_BASE + wave1 + wave2 + noise
            else
                -- Big waves after 10 AM
                local bigT = (predIndex - 360) / 60  -- reset t for big waves
                local ampVar = 1.0 + math.sin(bigT * 0.031) * 0.7
                local amp = EASY_BASE * 0.025 * ampVar
                local wave1 = math.sin(bigT * 0.70 + easyPhase) * amp
                local wave2 = math.sin(bigT * 1.50 + easyPhase + 1.2) * amp * 0.4
                local drift = bigT * 0.003
                local noise = (math.random() - 0.5) * 0.03
                price = EASY_BASE + wave1 + wave2 + drift + noise
            end
            currentPrice = math.floor(price * 1000 + 0.5) / 1000
        else
            local delta = (math.random() - 0.495) * 0.06
            currentPrice = math.floor((currentPrice + delta) * 1000 + 0.5) / 1000
        end
        currentBid = math.floor((currentPrice - 0.01) * 1000 + 0.5) / 1000
        currentAsk = math.floor((currentPrice + 0.01) * 1000 + 0.5) / 1000
        currentTime = rwTime(rwIndex)
        table.insert(prices, currentPrice)
    end
    
    checkCrossings()
    updatePosition()
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
    local min = math.floor(idx / 12)
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
    local marker = { price = px, idx = py }  -- px = fillPrice, py = #prices (idx)
    for i = 1, 20 do
        local angle = (math.pi * 2 * i) / 20 + math.random() * 0.5
        local speed = 0.3 + math.random() * 0.6
        local c = palette[i % #palette + 1]
        table.insert(particles, {
            marker = marker,
            offsetX = 0, offsetY = 0,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            life = 20 + math.random() * 15,
            maxLife = 35,
            r = c[1], g = c[2], b = c[3]
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
    currentBid = math.floor((currentPrice - 0.01) * 1000 + 0.5) / 1000
    currentAsk = math.floor((currentPrice + 0.01) * 1000 + 0.5) / 1000
    prevPrice = currentPrice
    rewindTicks = 0
    tickPaused = false
    showDogImage = false
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
    local fh = sy(30)
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

function updateParticles(dt)
    local n = math.min(#prices, 720)
    for i = #particles, 1, -1 do
        local p = particles[i]
        -- Recalculate center from marker position on chart
        if p.marker and n >= 2 and chartW > 0 then
            local mn, mx = priceRange()
            local step = (chartW * 0.97) / (n - 1)
            local firstIdx = #prices - n
            local relIdx = p.marker.idx - firstIdx
            if relIdx >= 1 and relIdx <= n then
                local cx = chartX + (relIdx - 1) * step
                local cy = priceToY(toPct(p.marker.price), mn, mx, chartY, chartH)
                p.x = cx + p.offsetX
                p.y = cy + p.offsetY
            end
        elseif p.isUnlock then
            p.x = p.ox + p.offsetX
            p.y = p.oy + p.offsetY
        end
        p.offsetX = p.offsetX + p.vx
        p.offsetY = p.offsetY + p.vy
        p.life = p.life - dt * 60
        if p.life <= 0 then
            table.remove(particles, i)
        end
    end
end

-- ── SKIP TO 15:55 ──
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
            local mid = math.floor(((row.bid + row.ask) / 2) * 1000 + 0.5) / 1000
            table.insert(prices, mid)
        end
        csvIndex = target
        if csvIndex <= #csvData then
            local row = csvData[csvIndex]
            if row then
                currentBid = row.bid
                currentAsk = row.ask
                currentTime = row.time
                currentPrice = math.floor(((row.bid + row.ask) / 2) * 1000 + 0.5) / 1000
                prevPrice = currentPrice
            end
        end
    else
        local target = math.min(4620, RW_TOTAL - 1)
        for i = rwIndex + 1, target do
            local price
            if dataMode == "predictable" then
                predIndex = predIndex + 1
                local t = predIndex / 60
                if predIndex < 360 then
                    local calmAmp = EASY_BASE * 0.004
                    local wave1 = math.sin(t * 5.0 + easyPhase) * calmAmp
                    local wave2 = math.sin(t * 7.0 + easyPhase + 1.7) * calmAmp * 0.5
                    local noise = (math.random() - 0.5) * 0.015
                    price = EASY_BASE + wave1 + wave2 + noise
                else
                    local bigT = (predIndex - 360) / 60
                    local ampVar = 1.0 + math.sin(bigT * 0.031) * 0.7
                    local amp = EASY_BASE * 0.025 * ampVar
                    local wave1 = math.sin(bigT * 0.70 + easyPhase) * amp
                    local wave2 = math.sin(bigT * 1.50 + easyPhase + 1.2) * amp * 0.4
                    local drift = bigT * 0.003
                    local noise = (math.random() - 0.5) * 0.03
                    price = EASY_BASE + wave1 + wave2 + drift + noise
                end
            else
                local delta = (math.random() - 0.495) * 0.06
                price = currentPrice + delta
            end
            currentPrice = math.floor(price * 1000 + 0.5) / 1000
            table.insert(prices, currentPrice)
        end
        rwIndex = target
        currentTime = rwTime(rwIndex)
        currentBid = math.floor((currentPrice - 0.01) * 1000 + 0.5) / 1000
        currentAsk = math.floor((currentPrice + 0.01) * 1000 + 0.5) / 1000
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
    if currentDay > 5 then
        local finalScore = startingBalance + realizedPnl
        saveUserData(playerInitials, finalScore)
        loadHighScores()
        highscoreNewScore = finalScore
        highscoreInitials = ""
        SCREEN = SCREENS.HIGHSCORE
        return
    end
    local isCarrying = carryPosition
    local savedMode = dataMode
    local savedGroup = csvGroupName
    
    startingBalance = startingBalance + realizedPnl
    realizedPnl = 0
    pnl = 0
    tradeCount = 0
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
    
    -- Award a random pin for surviving the day, then show achievement
    pinAwarded = awardRandomPin(playerInitials)
    SCREEN = SCREENS.ACHIEVEMENT
    -- Store routing target for when player taps CONTINUE
    achievementNextScreen = SCREENS.SELECTOR
    achievementCarryMode = isCarrying
    achievementSavedMode = savedMode
    achievementSavedGroup = savedGroup
end

introText = ""
instrumentText = "RANDOM"

function startGame(name)
    if name == "RANDOM" then
        dataMode = "random"
        applyConfig("RANDOM")
        rwIndex = 0
        currentTime = rwTime(0)
        instrumentText = "RANDOM"
        prices = {}
        minutePrices = {}
        table.insert(prices, RANDOM_BASE)
        basePrice = RANDOM_BASE
        currentPrice = RANDOM_BASE
        currentBid = math.floor((RANDOM_BASE - 0.01) * 1000 + 0.5) / 1000
        currentAsk = math.floor((RANDOM_BASE + 0.01) * 1000 + 0.5) / 1000
        stateSnapshots = { { position = 0, avgPrice = 0, pnl = 0, realizedPnl = 0, total = 10000 } }
        SCREEN = SCREENS.TRADING
    elseif name == "EASY" then
        dataMode = "predictable"
        applyConfig("EASY")
        predIndex = 0
        easyPhase = math.random() * math.pi * 2  -- random start direction
        currentTime = rwTime(0)
        instrumentText = "EASY"
        prices = {}
        minutePrices = {}
        table.insert(prices, EASY_BASE)
        basePrice = EASY_BASE
        currentPrice = EASY_BASE
        currentBid = math.floor((EASY_BASE - 0.01) * 1000 + 0.5) / 1000
        currentAsk = math.floor((EASY_BASE + 0.01) * 1000 + 0.5) / 1000
        stateSnapshots = { { position = 0, avgPrice = 0, pnl = 0, realizedPnl = 0, total = 10000 } }
        SCREEN = SCREENS.TRADING
    else
        local members = getGroupMembers(name)
        if #members == 0 then return end
        local inst = members[math.random(#members)]
        
        local availDays = {}
        for day, data in pairs(csvFileData) do
            if data[inst] then table.insert(availDays, day) end
        end
        if #availDays == 0 then return end
        
        csvDayFile = availDays[math.random(#availDays)]
        dataMode = "csv"
        csvInstrument = inst
        csvGroupName = name
        applyConfig(inst)
        csvData = interpolate5s(csvFileData[csvDayFile][inst])
        csvIndex = 0
        instrumentText = name
        
        prices = {}
        minutePrices = {}
        local row = csvData[1]
        local mid = math.floor(((row.bid + row.ask) / 2) * 1000 + 0.5) / 1000
        basePrice = mid
        table.insert(prices, mid)
        currentPrice = mid
        currentBid = row.bid
        currentAsk = row.ask
        currentTime = row.time
        
        SCREEN = SCREENS.TRADING
    end
end

-- ── CSV INTERPOLATION ──
function interpolate5s(minuteData)
    local result = {}
    for i = 1, #minuteData do
        local curr = minuteData[i]
        local nxt = minuteData[math.min(i + 1, #minuteData)]
        for j = 0, 11 do
            local t = j / 12
            local noise = 0
            if math.random() > 0.4 then
                noise = (math.random() - 0.5) * (0.005 + math.random() * 0.015) * 2
            end
            table.insert(result, {
                bid = math.floor((curr.bid + (nxt.bid - curr.bid) * t + noise) * 1000 + 0.5) / 1000,
                ask = math.floor((curr.ask + (nxt.ask - curr.ask) * t + noise) * 1000 + 0.5) / 1000,
                time = curr.time,
                date = curr.date
            })
        end
    end
    return result
end
