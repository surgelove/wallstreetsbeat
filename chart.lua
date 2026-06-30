-- ── CHART RENDERING ──
local theme = require("controls.theme")
chartX = 0
chartY = 0
chartW = 0
chartH = 0
playPawsImage = nil
playDogImage = nil
showDogImage = false

-- Chart span: starts at 15 min, grows tick by tick to 1 hour max
-- 15 min = 180 ticks, 1 hour = 720 ticks (12 ticks/min)
function getChartSpan()
    local elapsed = #prices or 0
    return math.min(REWIND_MAX_TICKS, math.max(180, elapsed))
end

-- Chart coordinate helper to eliminate 6× duplication
function getChartCoords(chartW)
    local rewindEnd = math.max(2, #prices - (rewindTicks or 0))
    local cs = getChartSpan()
    local n = math.min(rewindEnd - 1, cs)
    local startIdx = rewindEnd - n + 1
    local mn, mx = priceRange()
    local step = (chartW * 0.97) / (cs - 1)
    return {
        rewindEnd = rewindEnd,
        cs = cs,
        n = n,
        startIdx = startIdx,
        mn = mn,
        mx = mx,
        step = step,
    }
end
function updateToboggan(dt)
    if SCREEN ~= SCREENS.TRADING or not isFeatureUnlocked("mediumMA") or not cachedXEE or not isFeatureUnlocked("skier") then
        tobogganAirborne = false
        return
    end
    local w, h = chartW, chartH
    if w <= 0 or h <= 0 then return end
    local c = getChartCoords(w)
    if not c or c.n < 2 then return end
    local rewindEnd, cs, n, startIdx, mn, mx, step = c.rewindEnd, c.cs, c.n, c.startIdx, c.mn, c.mx, c.step
    local cX, cY2 = chartX, chartY
    
    -- Helper: get MA y at a chart x position
    local function maYAtX(x)
        local relX = x - cX
        local idx = startIdx + math.floor(relX / step + 0.5)
        if idx < startIdx or idx > rewindEnd then return nil end
        local val = cachedXEE[idx]
        if not val then return nil end
        return priceToY(toPct(val), mn, mx, cY2, h)
    end
    
    if tobogganAirborne then
        tobogganAirVY = tobogganAirVY + tobogganAirGravity * dt
        tobogganX = tobogganX + tobogganAirVX * dt
        tobogganY = tobogganY + tobogganAirVY * dt
        tobogganAngle = math.atan2(tobogganAirVY, tobogganAirVX)
        
        local groundY = maYAtX(tobogganX)
        if groundY and tobogganY >= groundY - sy(3) then
            tobogganY = groundY
            tobogganAirborne = false
            tobogganProgress = (tobogganX - cX) / (step * (n - 1))
        end
        
        if tobogganY > cY2 + h + 100 or tobogganX < cX - 100 or tobogganX > cX + w + 100 then
            tobogganAirborne = false
            tobogganProgress = 0
        end
        return
    end
    
    -- Compute current slope to determine speed (chairlift = 0.5x uphill, skier = 1.3x downhill)
    local curRelIdx = math.floor(tobogganProgress * (n - 1)) + 1
    local curVi = startIdx + curRelIdx - 1
    if curVi > rewindEnd then curVi = rewindEnd end
    if curVi < startIdx then curVi = startIdx end
    local curSlope = 0
    local pIdx = math.max(startIdx, curVi - 3)
    local nIdx = math.min(rewindEnd, curVi + 3)
    local cpv = cachedXEE[pIdx]
    local cnv = cachedXEE[nIdx]
    if cpv and cnv then
        local cpX = cX + (pIdx - startIdx) * step
        local cpY = priceToY(toPct(cpv), mn, mx, cY2, h)
        local cnX = cX + (nIdx - startIdx) * step
        local cnY = priceToY(toPct(cnv), mn, mx, cY2, h)
        curSlope = (cnY - cpY) / math.max(1, cnX - cpX)
    end
    local isUphill = curSlope < -0.02
    local speed
    if isUphill then
        speed = 0.05
        wasOnChairlift = true
        skierMomentum = 0
    else
        -- Just left the chairlift: start slow at the peak
        if wasOnChairlift then
            skierMomentum = 0
            wasOnChairlift = false
        end
        -- Accelerate downhill
        skierMomentum = math.min(0.2, skierMomentum + dt * 0.04)
        speed = skierMomentum
    end
    
    -- Advance progress left to right, loop
    tobogganProgress = tobogganProgress + dt * speed
    if tobogganProgress > 1 then tobogganProgress = tobogganProgress - 1; skierMomentum = 0; wasOnChairlift = false end
    
    local relIdx = math.floor(tobogganProgress * (n - 1)) + 1
    local vi = startIdx + relIdx - 1
    if vi > rewindEnd then vi = rewindEnd end
    if vi < startIdx then vi = startIdx end
    local v = cachedXEE[vi]
    if not v then tobogganX = -100; return end
    local px = cX + (vi - startIdx) * step
    local py = priceToY(toPct(v), mn, mx, cY2, h)
    
    -- Slope and launch detection
    local prevIdx = math.max(startIdx, vi - 3)
    local nextIdx = math.min(rewindEnd, vi + 3)
    local pv = cachedXEE[prevIdx]
    local nv = cachedXEE[nextIdx]
    if pv and nv then
        local prevX = cX + (prevIdx - startIdx) * step
        local prevY = priceToY(toPct(pv), mn, mx, cY2, h)
        local nextX = cX + (nextIdx - startIdx) * step
        local nextY = priceToY(toPct(nv), mn, mx, cY2, h)
        local slope = (nextY - prevY) / math.max(1, nextX - prevX)
        tobogganAngle = math.atan2(nextY - prevY, nextX - prevX)
        
        -- Launch when going over a peak: slope transitions from steep up to steep down
        local prevSlope
        local ppIdx = math.max(startIdx, vi - 6)
        local ppv = cachedXEE[ppIdx]
        if ppv then
            local ppX = cX + (ppIdx - startIdx) * step
            local ppY = priceToY(toPct(ppv), mn, mx, cY2, h)
            prevSlope = (prevY - ppY) / math.max(1, prevX - ppX)
            if prevSlope and prevSlope < -0.2 and slope > 0.2 and skierMomentum > 0.05 then
                tobogganAirborne = true
                local speed = (step * TOBOGGAN_SPEED * (n - 1)) / dt  -- approximate px/sec
                speed = speed * 0.016  -- scale down
                tobogganAirVX = math.cos(tobogganAngle) * speed * 1.5
                tobogganAirVY = math.sin(tobogganAngle) * speed * 1.5 - 120
                tobogganX = px
                tobogganY = py
                return
            end
        end
    end
    
    tobogganX = px
    tobogganY = py
end

function recalcSafeArea(winW, winH)
    local w, h
    if winW then
        w, h = winW, winH
    else
        w, h = love.graphics.getDimensions()
    end
    -- Always landscape: swap if portrait
    if h > w then w, h = h, w end
    -- Internal 1080p, scaled to fill screen
    safeWidth = 1920
    safeHeight = 1080
    safeScale = math.min(w / safeWidth, h / safeHeight)
    local sw = math.floor(safeWidth * safeScale)
    local sh = math.floor(safeHeight * safeScale)
    safeLeft = math.floor((w - sw) / 2)
    safeTop = math.floor((h - sh) / 2)
end

function recalcLayout()
    applyScaling()
    local w, h = safeWidth, safeHeight
    chartX = PANEL_W
    chartY = TOPBAR_H + sy(12)
    chartW = w - PANEL_W * 2
    chartH = h - TOPBAR_H - BOTBAR_H - sy(9) - sy(12) * 2
end

function toPct(price)
    if basePrice == 0 then return 0 end
    return ((price / basePrice) - 1) * 100
end

function fromPct(pct)
    return basePrice * (1 + pct / 100)
end

function priceRange()
    local rewindEnd = math.max(2, #prices - (rewindTicks or 0))
    local cs = getChartSpan()
    local n = math.min(rewindEnd - 1, cs)
    if n < 2 then return -1, 1 end
    local visPcts = {}
    for i = rewindEnd - n + 1, rewindEnd do
        table.insert(visPcts, toPct(prices[i]))
    end
    local all = {}
    for _, v in ipairs(visPcts) do table.insert(all, v) end
    if isFeatureUnlocked("orderLines") then
        for _, line in ipairs(orderLines) do
            table.insert(all, toPct(line.price))
        end
    end
    if #all == 0 then return -1, 1 end
    local mn = all[1]
    local mx = all[1]
    for i = 2, #all do
        if all[i] < mn then mn = all[i] end
        if all[i] > mx then mx = all[i] end
    end
    local span = mx - mn
    local pad = math.max(span * 0.05, 0.1)
    return mn - pad, mx + pad
end

function priceToY(pct, mn, mx, cY, cH)
    return cY + cH - ((pct - mn) / (mx - mn)) * cH * 0.82 - cH * 0.08
end

function yToPrice(y, mn, mx, cY, cH)
    local pct = mx - ((y - cY - cH * 0.08) / (cH * 0.82)) * (mx - mn)
    return fromPct(pct)
end

function sma(data, period)
    local result = {}
    for i = 1, #data do
        if i < period then
            table.insert(result, nil)
        else
            local sum = 0
            for j = i - period + 1, i do
                sum = sum + data[j]
            end
            table.insert(result, sum / period)
        end
    end
    return result
end

function ema(data, period)
    -- EMA seeded with first available price, valid from bar 1 onward.
    local result = {}
    local k = 2 / (period + 1)
    -- Find first real price as seed
    local seed = nil
    for i = 1, #data do
        if data[i] then seed = data[i]; break end
    end
    if not seed then return result end
    
    local emaVal = seed
    for i = 1, #data do
        if data[i] then
            emaVal = data[i] * k + emaVal * (1 - k)
        end
        result[i] = emaVal  -- valid even during nils (holds last value)
    end
    return result
end

function tema(data, period)
    -- Triple EMA: 3*EMA1 - 3*EMA2 + EMA3, seeded from first price, valid from bar 1.
    local e1 = ema(data, period)
    local e2 = ema(e1, period)
    local e3 = ema(e2, period)
    
    local result = {}
    for i = 1, #data do
        if e1[i] and e2[i] and e3[i] then
            result[i] = 3 * e1[i] - 3 * e2[i] + e3[i]
        else
            result[i] = nil
        end
    end
    return result
end

function computeMA(data, maType, period)
    if maType == "TEMA" then return tema(data, period)
    elseif maType == "EMA" then return ema(data, period)
    else return sma(data, period) end
end

cachedXER = nil
cachedXEE = nil

function recalcMAs()
    if not prices or #prices == 0 then return end
    cachedXER = computeMA(prices, xerMAType or "TEMA", xerMAPeriod or 15)
    cachedXEE = computeMA(prices, xeeMAType or "EMA", xeeMAPeriod or 15)
end

function drawChart()
    local w, h = chartW, chartH
    if w <= 0 or h <= 0 then return end
    local c = getChartCoords(w)
    if not c or c.n < 2 then
        love.graphics.setColor(0.11, 0.13, 0.16)
        love.graphics.rectangle("fill", chartX, chartY, w, h, PILL_R)
        return
    end
    local rewindEnd, cs, n, startIdx, mn, mx, step = c.rewindEnd, c.cs, c.n, c.startIdx, c.mn, c.mx, c.step
    local cX, cY = chartX, chartY
    local cH = h
    
    love.graphics.setScissor(
        safeLeft + math.floor(cX * safeScale),
        safeTop + math.floor(cY * safeScale),
        math.floor(w * safeScale),
        math.floor(h * safeScale)
    )
    
    -- Background (rounded to match header/footer pills)
    love.graphics.setColor(0.04, 0.05, 0.06)
    love.graphics.rectangle("fill", cX, cY, w, h, PILL_R)
    
    -- Grid lines
    if isFeatureUnlocked("gridLines") then
        love.graphics.setColor(0.20, 0.20, 0.22)
        love.graphics.setLineWidth(math.max(1, sy(0.75)))
        local gf = fonts.default37
        love.graphics.setFont(gf)
        local showPrice = (chartDisplay or "pct") == "price"
        for i = 0, 6 do
            local y = cY + h * 0.06 + (h * 0.88) * (i / 6)
            love.graphics.line(cX, y, cX + w, y)
            local val = mx - (mx - mn) * (i / 6)
            local lbl
            if showPrice then
                local price = fromPct(val)
                if price >= 1000 then
                    lbl = string.format("%.0f", price)
                elseif price >= 1 then
                    lbl = string.format("%.2f", price)
                else
                    lbl = string.format("%.4f", price)
                end
            else
                local prefix = val >= 0 and "+" or ""
                lbl = prefix .. string.format("%.2f%%", val)
            end
            love.graphics.setColor(0.60, 0.60, 0.65)
            love.graphics.print(lbl, cX + 2, y - gf:getHeight() - 1)
        end
    end
    
    -- Visible prices
    local visible = {}
    for i = startIdx, rewindEnd do
        table.insert(visible, prices[i])
    end
    
    -- XER MA (purple, crosser)
    if isFeatureUnlocked("slowMA") and cachedXER then
        love.graphics.setColor(0.70, 0.35, 1.0, 0.85)
        love.graphics.setLineWidth(math.max(1, sy(3)))
        for i = 2, n do
            local vi = startIdx + i - 1
            local v = cachedXER[vi]
            local pv = cachedXER[vi - 1]
            if v and pv then
                local x1 = cX + (i - 2) * step
                local y1 = priceToY(toPct(pv), mn, mx, cY, h)
                local x2 = cX + (i - 1) * step
                local y2 = priceToY(toPct(v), mn, mx, cY, h)
                love.graphics.line(x1, y1, x2, y2)
            end
        end
    end
    
    -- XEE MA (blue, crossee)
    if isFeatureUnlocked("mediumMA") and cachedXEE then
        love.graphics.setColor(0.20, 0.55, 1.0, 0.85)
        love.graphics.setLineWidth(math.max(1, sy(3)))
        for i = 2, n do
            local vi = startIdx + i - 1
            local v = cachedXEE[vi]
            local pv = cachedXEE[vi - 1]
            if v and pv then
                local x1 = cX + (i - 2) * step
                local y1 = priceToY(toPct(pv), mn, mx, cY, h)
                local x2 = cX + (i - 1) * step
                local y2 = priceToY(toPct(v), mn, mx, cY, h)
                love.graphics.line(x1, y1, x2, y2)
            end
        end
    end
    
    -- Rider on the XEE MA (blue line): skier downhill, chairlift uphill
    if isFeatureUnlocked("skier") and isFeatureUnlocked("mediumMA") and cachedXEE and tobogganX > 0 then
        local tx, ty, ta = tobogganX, tobogganY, tobogganAngle
        local ts = sy(24)
        local goingUp = ta < -0.02     -- negative slope = climbing (Y decreases)
        love.graphics.push()
        love.graphics.translate(tx, ty)
        love.graphics.rotate(ta)
        
        if goingUp then
            -- ── CHAIRLIFT (uphill) ──
            -- Cable wire above
            local cableY = -ts * 1.3
            love.graphics.setColor(0.35, 0.35, 0.4, 0.7)
            love.graphics.setLineWidth(math.max(1, sy(1.5)))
            love.graphics.line(-ts * 0.8, cableY, ts * 0.8, cableY)
            -- Hanger pole
            love.graphics.setColor(0.5, 0.5, 0.55, 1)
            love.graphics.setLineWidth(math.max(1, sy(3)))
            love.graphics.line(0, cableY, 0, -ts * 0.1)
            -- Chair seat
            love.graphics.setColor(0.55, 0.35, 0.15, 1)
            love.graphics.rectangle("fill", -ts * 0.4, -ts * 0.1, ts * 0.8, sy(7.5), sy(3))
            -- Chair back
            love.graphics.rectangle("fill", -ts * 0.3, -ts * 0.7, sy(6), ts * 0.6, sy(3))
            -- Safety bar
            love.graphics.setColor(0.5, 0.5, 0.55, 1)
            love.graphics.setLineWidth(math.max(1, sy(2.25)))
            love.graphics.line(-ts * 0.35, -ts * 0.4, ts * 0.25, -ts * 0.4)
            -- Rider sitting in chair
            love.graphics.setColor(0.15, 0.15, 0.22, 1)
            love.graphics.setLineWidth(math.max(1, sy(2.25)))
            love.graphics.line(0, -ts * 0.1, 0, -ts * 0.55)  -- torso
            love.graphics.setColor(0.95, 0.85, 0.7, 1)
            love.graphics.circle("fill", 0, -ts * 0.7, sy(6))  -- head
            -- Legs dangling
            love.graphics.setColor(0.15, 0.15, 0.22, 1)
            love.graphics.line(0, -ts * 0.1, -ts * 0.2, ts * 0.45)
            love.graphics.line(0, -ts * 0.1, ts * 0.2, ts * 0.45)
        else
            -- ── SKIER (downhill / flat) ──
            local pad = sy(3)  -- small padding above MA line
            -- Skis sit right on the line + pad
            love.graphics.setColor(0.85, 0.25, 0.15, 1)
            love.graphics.setLineWidth(math.max(1, sy(4.5)))
            love.graphics.line(-ts * 0.7, pad, ts * 0.5, pad)
            love.graphics.line(-ts * 0.6, pad + sy(4.5), ts * 0.6, pad + sy(4.5))
            -- Ski poles
            love.graphics.setColor(0.6, 0.6, 0.65, 1)
            love.graphics.setLineWidth(math.max(1, sy(2.25)))
            love.graphics.line(-ts * 0.15, -ts * 0.5, -ts * 0.6, pad + sy(4.5))
            love.graphics.line(ts * 0.1, -ts * 0.5, ts * 0.5, pad + sy(4.5))
            -- Body leaning forward
            love.graphics.setColor(0.15, 0.15, 0.22, 1)
            love.graphics.setLineWidth(math.max(1, sy(3)))
            love.graphics.line(0, -ts * 0.15, ts * 0.35, -ts * 0.8)
            -- Arms (pole grip)
            love.graphics.line(ts * 0.15, -ts * 0.55, -ts * 0.1, -ts * 0.5)
            love.graphics.line(ts * 0.15, -ts * 0.55, ts * 0.35, -ts * 0.05)
            -- Head
            love.graphics.setColor(0.95, 0.85, 0.7, 1)
            love.graphics.circle("fill", ts * 0.45, -ts * 0.9, sy(6))
            -- Goggles
            love.graphics.setColor(0.1, 0.2, 0.3, 1)
            love.graphics.rectangle("fill", ts * 0.35, -ts * 1.02, sy(12), sy(4.5), sy(1.5))
        end
        love.graphics.setLineWidth(math.max(1, sy(1.5)))
        love.graphics.pop()
    end
    
    -- Price line (always visible — threshold 0 feature)
    local lastY = cY + h / 2
    love.graphics.setColor(0.78, 0.83, 0.88)
    love.graphics.setLineWidth(math.max(1, sy(2.25)))
    for i = 2, n do
        local x1 = cX + (i - 2) * step
        local y1 = priceToY(toPct(visible[i - 1]), mn, mx, cY, h)
        local x2 = cX + (i - 1) * step
        local y2 = priceToY(toPct(visible[i]), mn, mx, cY, h)
        love.graphics.line(x1, y1, x2, y2)
    end
    lastY = priceToY(toPct(visible[n]), mn, mx, cY, h)
    
    -- Order lines on chart
    if isFeatureUnlocked("orderLines") then
        for _, line in ipairs(orderLines) do
            local y = priceToY(toPct(line.price), mn, mx, cY, h)
            local r, gr, bv = 0.63, 0.63, 0.75
            if line.type == "buy-stop" then r, gr, bv = 0, 0.80, 0.41 end
            if line.type == "sell-stop" then r, gr, bv = 0.91, 0.25, 0.38 end
            love.graphics.setColor(r, gr, bv, 0.7)
            love.graphics.setLineWidth(math.max(1, sy(1.5)))
            love.graphics.line(cX, y, cX + w, y)
            
            -- Drag handle (circle near right end) with X inside
            local handleR = sy(15)
            local hx, hy = cX + w - handleR - sy(4.5), y
            love.graphics.setColor(r, gr, bv, 0.8)
            love.graphics.circle("fill", hx, hy, handleR)
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.setLineWidth(math.max(1, sy(2.25)))
            love.graphics.circle("line", hx, hy, handleR)
            love.graphics.setLineWidth(math.max(1, sy(1.5)))
            -- X inside handle with static white halo (no jiggle)
            local orderFont = fonts.default37
            love.graphics.setFont(orderFont)
            local xFh = orderFont:getHeight()
            local xW = orderFont:getWidth("X")
            local xx = hx - xW / 2
            local xy = hy - xFh / 2
            -- White halo
            love.graphics.setColor(1, 1, 1, 0.35)
            for dx = -1, 1 do
                for dy = -1, 1 do
                    if dx ~= 0 or dy ~= 0 then
                        love.graphics.print("X", xx + dx, xy + dy)
                    end
                end
            end
            -- Black X on top
            love.graphics.setColor(0, 0, 0, 0.75)
            love.graphics.print("X", xx, xy)
            
            local names = { ["buy-stop"] = "BS", ["sell-stop"] = "SS", ["stop-loss"] = "PLS" }
            local label = (names[line.type] or "?") .. " " .. string.format("%.2f", line.price)
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.rectangle("fill", cX, y - 7, 55, 14)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(label, cX + 2, y - 5)
        end
    end
    
    -- Time label (shifted left to make room for paw/dog image)
    if currentTime and currentTime ~= "" then
        love.graphics.setColor(0.74, 0.80, 0.83)
        local timeFont = fonts.default37
        love.graphics.setFont(timeFont)
        local label = (rewindTicks or 0) > 0 and "REWINDING" or currentTime
        local fh = timeFont:getHeight()
        local tw = timeFont:getWidth(label)
        
        -- Load images lazily
        if not playPawsImage then
            local ok, img = pcall(love.graphics.newImage, "sprites/play_paws.png")
            if ok then playPawsImage = img end
        end
        if not playDogImage then
            local ok, img = pcall(love.graphics.newImage, "sprites/play_dog.png")
            if ok then playDogImage = img end
        end
        
        local img = showDogImage and playDogImage or playPawsImage
        if img then
            -- Target vertical size: paws at 30% scale
            local targetH = (playPawsImage and playPawsImage:getHeight() or img:getHeight()) * 0.3
            local scale = targetH / img:getHeight()
            local iw, ih = img:getWidth() * scale, img:getHeight() * scale
            local ix = cX + w - iw - 2
            local iy = cY + h - ih - 2
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, ix, iy, 0, scale, scale)
            
            -- Speech bubble when ball is waiting (dog saying "gimme\nball")
            if ballPhase == "waiting" then
                local bubbleFont = fonts.default30
                love.graphics.setFont(bubbleFont)
                local lines = {"gimme", "ball"}
                local bw = 0
                for _, l in ipairs(lines) do
                    local lw = bubbleFont:getWidth(l)
                    if lw > bw then bw = lw end
                end
                local bh = #lines * bubbleFont:getHeight() + sy(12)
                bw = bw + sy(18)
                local bx = ix + iw / 2 - bw / 2
                local by = iy - bh - sy(9)
                -- Bubble background
                love.graphics.setColor(1, 1, 1, 0.95)
                love.graphics.rectangle("fill", bx, by, bw, bh, sy(6))
                -- Outline
                love.graphics.setColor(0.15, 0.15, 0.18, 0.9)
                love.graphics.setLineWidth(math.max(1, sy(3)))
                love.graphics.rectangle("line", bx, by, bw, bh, sy(6))
                love.graphics.setLineWidth(math.max(1, sy(1.5)))
                -- Tail triangle pointing down
                local tailX = ix + iw / 2
                local tailY = by + bh
                love.graphics.polygon("fill", tailX - sy(6), tailY, tailX, tailY + sy(9), tailX + sy(6), tailY)
                -- Text
                love.graphics.setColor(0.10, 0.10, 0.12)
                for li, l in ipairs(lines) do
                    local lw = bubbleFont:getWidth(l)
                    love.graphics.print(l, bx + (bw - lw) / 2, by + sy(6) + (li - 1) * bubbleFont:getHeight())
                end
            end
            
            love.graphics.print(label, ix - tw - sx(9), cY + h - fh - 2)
            -- Register clickable region for the image
            if regButton then
                regButton("btn-paws", ix, iy, iw, ih, "", nil, function()
                    showDogImage = not showDogImage
                    tickPaused = showDogImage
                end)
            end
        else
            love.graphics.print(label, cX + w - tw - 10, cY + h - fh - 10)
        end
    end
    
    -- Trade markers
    local firstIdx = startIdx - 1
    for _, m in ipairs(tradeMarkers) do
        local relIdx = m.idx - firstIdx + 1
        if relIdx >= 1 and relIdx <= n then
            local x = cX + (relIdx - 1) * step
            local y = priceToY(toPct(m.price), mn, mx, cY, h)
            
            if m.type == "star-win" then
                -- Pct text first (left of marker): 3s visible, 2s fade
                if m.pct then
                    local elapsed = love.timer.getTime() - (m.time or 0)
                    if elapsed < 5 then
                        local alpha = elapsed < 3 and 1 or (1 - (elapsed - 3) / 2)
                        love.graphics.setColor(0, 0.78, 0.41, alpha)
                        local s = (m.pct >= 0 and "+" or "") .. string.format("%.2f%%", m.pct)
                        local tw = love.graphics.getFont():getWidth(s)
                        love.graphics.print(s, x - tw - 16, y + 8)
                    end
                end
                -- Draw a golden 5-pointed asterisk
                local armR = sy(21)
                love.graphics.setColor(theme.color.gold)
                love.graphics.setLineWidth(math.max(1, sy(6)))
                for i = 0, 4 do
                    local angle = math.pi / 2 + i * 2 * math.pi / 5
                    love.graphics.line(x, y, x + math.cos(angle) * armR, y - math.sin(angle) * armR)
                end
                love.graphics.setLineWidth(math.max(1, sy(1.5)))
            elseif m.type == "star-lose" then
                -- Pct text first (left of marker): 3s visible, 2s fade
                if m.pct then
                    local elapsed = love.timer.getTime() - (m.time or 0)
                    if elapsed < 5 then
                        local alpha = elapsed < 3 and 1 or (1 - (elapsed - 3) / 2)
                        love.graphics.setColor(0.91, 0.25, 0.38, alpha)
                        local s = (m.pct >= 0 and "+" or "") .. string.format("%.2f%%", m.pct)
                        local tw = love.graphics.getFont():getWidth(s)
                        love.graphics.print(s, x - tw - sx(24), y + sy(12))
                    end
                end
                love.graphics.setColor(0.91, 0.25, 0.38)
                love.graphics.setLineWidth(math.max(1, sy(6)))
                love.graphics.line(x - sx(15), y - sy(15), x + sx(15), y + sy(15))
                love.graphics.line(x + sx(15), y - sy(15), x - sx(15), y + sy(15))
                love.graphics.setLineWidth(math.max(1, sy(1.5)))
            elseif m.type == "buy" then
                love.graphics.setColor(0, 0.78, 0.41)
                love.graphics.circle("fill", x, y, 12)
                love.graphics.setColor(0, 0, 0)
                love.graphics.circle("line", x, y, 12)
            elseif m.type == "sell" then
                love.graphics.setColor(0.91, 0.25, 0.38)
                love.graphics.circle("fill", x, y, 12)
                love.graphics.setColor(0, 0, 0)
                love.graphics.circle("line", x, y, 12)
            end
        end
    end
    
    -- Particles
    for _, p in ipairs(particles) do
        local alpha = p.life / p.maxLife
        love.graphics.setColor(p.r or 0, p.g or 0.78, p.b or 0.41, alpha)
        local ps = (p.size or 2.5) * alpha
        if p.shape == "star" then
            -- 4-point star
            local sx, sy_p = p.x, p.y
            love.graphics.setLineWidth(math.max(1, ps * 0.35))
            love.graphics.line(sx - ps, sy_p, sx + ps, sy_p)
            love.graphics.line(sx, sy_p - ps, sx, sy_p + ps)
            love.graphics.line(sx - ps * 0.7, sy_p - ps * 0.7, sx + ps * 0.7, sy_p + ps * 0.7)
            love.graphics.line(sx + ps * 0.7, sy_p - ps * 0.7, sx - ps * 0.7, sy_p + ps * 0.7)
            love.graphics.setLineWidth(1)
        else
            love.graphics.circle("fill", p.x, p.y, ps)
        end
    end
    
    -- Bouncing ball
    if ballPhase and ballImage then
        local growScale = 1
        if ballPhase == "waiting" then
            local elapsed = 2.0 - ballTimer
            growScale = math.min(1, elapsed / 2.0)
        elseif ballPhase == "shrinking" then
            growScale = math.max(0, ballShrinkTimer / 0.5)
        end
        local scale = ballRadius * 2 / ballImage:getHeight() * growScale
        love.graphics.setColor(1, 1, 1, growScale)
        love.graphics.draw(ballImage, ballX, ballY, ballAngle, scale, scale, ballImage:getWidth() / 2, ballImage:getHeight() / 2)
    end
    
    -- Thin off-white border around chart area
    love.graphics.setColor(0.78, 0.83, 0.88, 0.25)
    love.graphics.setLineWidth(math.max(1, sy(1.5)))
    love.graphics.rectangle("line", cX, cY, w, h, PILL_R)
    love.graphics.setLineWidth(math.max(1, sy(1.5)))
    
    -- VHS rewind effect
    if (rewindTicks or 0) > 0 then
        local seed = love.timer.getTime() * 100
        -- Scan lines
        love.graphics.setColor(0, 0, 0, 0.15)
        for y = cY, cY + h, sy(4.5) do
            if (seed + y) % 7 < 3 then
                love.graphics.rectangle("fill", cX, y, w, sy(1.5))
            end
        end
        -- Horizontal distortion bar
        local barY = cY + ((seed * 3) % h)
        local barH = sy(6)
        love.graphics.setColor(0.9, 0.9, 0.95, 0.1)
        love.graphics.rectangle("fill", cX, barY, w, barH)
        love.graphics.setColor(0.1, 0.1, 0.15, 0.08)
        love.graphics.rectangle("fill", cX + (seed % 40), barY + barH, w, sy(1.5))
        -- Random static dots
        for i = 1, 30 do
            local dx = cX + (seed * (i + 7) * 137) % w
            local dy = cY + (seed * (i + 3) * 251) % h
            love.graphics.setColor(1, 1, 1, 0.1 + (i % 3) * 0.1)
            love.graphics.rectangle("fill", dx, dy, sy(3), sy(1.5))
        end
    end
    
    if isFeatureUnlocked("snow") and (isFeatureUnlocked("slowMA") or isFeatureUnlocked("mediumMA")) then
        drawSnow()
    end
    
    -- Current price: white glowing circle on top of everything
    local cpR = sy(12)
    local cpx = cX + (n - 1) * step
    -- Outer glow (larger, fading)
    love.graphics.setColor(1, 1, 1, 0.08)
    love.graphics.circle("fill", cpx, lastY, cpR * 3)
    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.circle("fill", cpx, lastY, cpR * 2)
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.circle("fill", cpx, lastY, cpR * 1.4)
    -- Bright center
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.circle("fill", cpx, lastY, cpR)
    
    love.graphics.setScissor()
end
