-- ── GAME STATE ──
dataMode = nil
csvData = nil
csvIndex = 0
csvInstrument = nil
csvGroupName = ""
csvDayFile = nil
rwIndex = 0
basePrice = 0
currentTime = ""
instrumentText = "RANDOM\nWALK"
introText = ""

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
tradeCount = 0
carryPosition = false

orderLines = {}
tradeMarkers = {}
particles = {}
milestonesHit = {}

function scalePnl(v)
    if basePrice and basePrice > 0 then
        return v * (100 / basePrice)
    end
    return 0
end

function fmtPnl(v)
    return string.format("%.2f", math.abs(v))
end

function fmtMoney(v)
    local s = string.format("%.2f", v)
    local k
    repeat
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
end

function refreshFeatureVisibility()
    local totalPnl = realizedPnl + pnl
    for k, threshold in pairs(featureUnlocks) do
        if totalPnl >= threshold then
            featuresUnlocked[k] = true
        end
        featureConfig[k] = featuresUnlocked[k]
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
    local fillPrice = currentAsk
    if position < 0 then
        local closed = math.min(shareInc, math.abs(position))
        realizedPnl = realizedPnl + scalePnl((avgPrice - fillPrice) * closed)
        position = position + shareInc
        if position == 0 then avgPrice = 0 end
    else
        if position == 0 then
            avgPrice = fillPrice
        else
            avgPrice = (avgPrice * position + fillPrice * shareInc) / (position + shareInc)
        end
        position = position + shareInc
    end
    tradeCount = tradeCount + 1
    table.insert(tradeMarkers, { price = fillPrice, type = "buy", idx = #prices })
    spawnParticles(fillPrice, #prices, "cold")
    playBuy()
    updatePosition()
end

function sell()
    if position <= -shareMax then return end
    local fillPrice = currentBid
    if position > 0 then
        local closed = math.min(shareInc, position)
        realizedPnl = realizedPnl + scalePnl((fillPrice - avgPrice) * closed)
        position = position - shareInc
        if position == 0 then avgPrice = 0 end
    else
        if position == 0 then
            avgPrice = fillPrice
        else
            avgPrice = (avgPrice * math.abs(position) + fillPrice * shareInc) / (math.abs(position) + shareInc)
        end
        position = position - shareInc
    end
    tradeCount = tradeCount + 1
    table.insert(tradeMarkers, { price = fillPrice, type = "sell", idx = #prices })
    spawnParticles(fillPrice, #prices, "warm")
    playSell()
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
        pct = pct
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
    local limits = { ["buy-stop"] = 10, ["sell-stop"] = 10, ["stop-loss"] = 999 }
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
            if position ~= 0 then
                SCREEN = SCREENS.EOD
            else
                SCREEN = SCREENS.RECAP
            end
            return
        end
        local delta = (math.random() - 0.495) * 0.06
        currentPrice = math.floor((currentPrice + delta) * 1000 + 0.5) / 1000
        currentBid = math.floor((currentPrice - 0.01) * 1000 + 0.5) / 1000
        currentAsk = math.floor((currentPrice + 0.01) * 1000 + 0.5) / 1000
        currentTime = rwTime(rwIndex)
        table.insert(prices, currentPrice)
    end
    
    checkCrossings()
    updatePosition()
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
            currentBid = row.bid
            currentAsk = row.ask
            currentTime = row.time
            currentPrice = math.floor(((row.bid + row.ask) / 2) * 1000 + 0.5) / 1000
            prevPrice = currentPrice
        end
    else
        local target = math.min(4620, RW_TOTAL - 1)
        for i = rwIndex + 1, target do
            local delta = (math.random() - 0.495) * 0.06
            currentPrice = math.floor((currentPrice + delta) * 1000 + 0.5) / 1000
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
    dataMode = nil
    removeAllOrderLines()
    tradeMarkers = {}
    particles = {}
    milestonesHit = {}
    
    if carryPosition then
        carryPosition = false
    else
        position = 0
        avgPrice = 0
        prevPosition = 0
    end
    
    updatePosition()
    SCREEN = SCREENS.SELECTOR
end

introText = ""
instrumentText = "RANDOM WALK"

function startGame(name)
    if name == "RANDOM" then
        dataMode = "random"
        applyConfig("RANDOM")
        rwIndex = 0
        currentTime = rwTime(0)
        instrumentText = "RANDOM WALK"
        prices = {}
        minutePrices = {}
        table.insert(prices, RANDOM_BASE)
        basePrice = RANDOM_BASE
        currentPrice = RANDOM_BASE
        currentBid = math.floor((RANDOM_BASE - 0.01) * 1000 + 0.5) / 1000
        currentAsk = math.floor((RANDOM_BASE + 0.01) * 1000 + 0.5) / 1000
        local weekday = math.random(1, 5)
        local days = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday" }
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
