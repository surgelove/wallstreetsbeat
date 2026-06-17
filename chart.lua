-- ── CHART RENDERING ──
chartX = 0
chartY = 0
chartW = 0
chartH = 0
safeScale = 1  -- scale factor to fill screen (like Balatro)

function recalcSafeArea(winW, winH)
    local w, h
    if winW then
        w, h = winW, winH
    else
        w, h = love.graphics.getDimensions()
    end
    -- Always landscape: swap if portrait
    if h > w then w, h = h, w end
    -- Internal 720p like Balatro, scaled to fill screen
    safeWidth = 1280
    safeHeight = 720
    safeScale = math.min(w / safeWidth, h / safeHeight)
    local sw = math.floor(safeWidth * safeScale)
    local sh = math.floor(safeHeight * safeScale)
    safeLeft = math.floor((w - sw) / 2)
    safeTop = math.floor((h - sh) / 2)
end

function recalcLayout()
    local w, h = safeWidth, safeHeight
    chartX = PANEL_W
    chartY = TOPBAR_H + 8
    chartW = w - PANEL_W * 2
    chartH = h - TOPBAR_H - BOTBAR_H - 8 * 2 - 6
end

function toPct(price)
    if basePrice == 0 then return 0 end
    return ((price / basePrice) - 1) * 100
end

function fromPct(pct)
    return basePrice * (1 + pct / 100)
end

function priceRange()
    local n = math.min(#prices, 720)
    local visPcts = {}
    if n == 0 then return -1, 1 end
    for i = #prices - n + 1, #prices do
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
    return cY + cH - ((pct - mn) / (mx - mn)) * cH * 0.88 - cH * 0.06
end

function yToPrice(y, mn, mx, cY, cH)
    local pct = mx - ((y - cY - cH * 0.06) / (cH * 0.88)) * (mx - mn)
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
    -- Returns EMA indexed same as data (1..#data), with nils before seeding.
    local result = {}
    local k = 2 / (period + 1)
    local emaVal = nil
    for i = 1, #data do
        if i < period then
            result[i] = nil
        elseif i == period then
            local sum = 0
            for j = 1, period do sum = sum + data[j] end
            emaVal = sum / period
            result[i] = emaVal
        else
            emaVal = data[i] * k + emaVal * (1 - k)
            result[i] = emaVal
        end
    end
    return result
end

function tema(data, period)
    -- Triple EMA: 3*EMA1 - 3*EMA2 + EMA3
    -- Inner EMAs need dense arrays, so we extract non-nil runs.
    local function dense(t, from)
        local out = {}
        for i = from, #t do
            if t[i] then table.insert(out, t[i]) end
        end
        return out
    end
    
    local e1 = ema(data, period)
    -- How many non-nil values before the first valid EMA1?
    -- e1 is valid from index 'period' onward.
    local d1 = dense(e1, period)   -- dense EMA1 values
    
    local e2 = ema(d1, period)     -- EMA of dense EMA1
    local d2 = dense(e2, period)   -- dense EMA2 values
    
    local e3 = ema(d2, period)     -- EMA of dense EMA2
    
    -- Map back: TEMA is valid starting at original index: period + (period-1) + (period-1) = 3*period - 2
    -- But d1[1] = e1[period], d2[1] = e2[period], e3[1] corresponds to e2[period]
    -- So TEMA at original index i maps to d1[i - period + 1], d2[i - 2*period + 2], e3[i - 3*period + 3]
    local result = {}
    for i = 1, #data do result[i] = nil end
    
    local start = 3 * period - 2  -- first valid TEMA index in original data
    for i = start, #data do
        local j1 = i - period + 1       -- index into d1
        local j2 = j1 - period + 1       -- index into d2
        local j3 = j2 - period + 1       -- index into e3
        if d1[j1] and d2[j2] and e3[j3] then
            result[i] = 3 * d1[j1] - 3 * d2[j2] + e3[j3]
        end
    end
    return result
end

function drawChart()
    local w, h = chartW, chartH
    if w <= 0 or h <= 0 then return end
    
    local n = math.min(#prices, 720)
    if n < 2 then
        love.graphics.setColor(0.11, 0.13, 0.16)
        love.graphics.rectangle("fill", chartX, chartY, w, h, PILL_R)
        return
    end
    
    local mn, mx = priceRange()
    local step = (w * 0.97) / (n - 1)
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
        love.graphics.setLineWidth(0.5)
        local gf = love.graphics.getFont()
        local showPrice = (chartDisplay or "pct") == "price"
        for i = 0, 6 do
            local y = cY + h * 0.06 + (h * 0.88) * (i / 6)
            love.graphics.line(cX, y, cX + w, y)
            local val = mx - (mx - mn) * (i / 6)
            local lbl
            if showPrice then
                local price = fromPct(val)
                if price >= 1000 then
                    lbl = string.format("$%.0f", price)
                elseif price >= 1 then
                    lbl = string.format("$%.2f", price)
                else
                    lbl = string.format("$%.4f", price)
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
    for i = #prices - n + 1, #prices do
        table.insert(visible, prices[i])
    end
    
    -- MA Fast (TEMA 15-min, virtually no lag)
    if isFeatureUnlocked("slowMA") then
        local mat = tema(prices, 180)
        love.graphics.setColor(0.48, 0.41, 0.93, 0.60)
        love.graphics.setLineWidth(2.0)
        for i = 2, n do
            local vi = #prices - n + i
            local v = mat[vi]
            local pv = mat[vi - 1]
            if v and pv then
                local x1 = cX + (i - 2) * step
                local y1 = priceToY(toPct(pv), mn, mx, cY, h)
                local x2 = cX + (i - 1) * step
                local y2 = priceToY(toPct(v), mn, mx, cY, h)
                love.graphics.line(x1, y1, x2, y2)
            end
        end
    end
    
    -- MA Medium (EMA 15-min)
    if isFeatureUnlocked("mediumMA") then
        local mam = ema(prices, 180)
        love.graphics.setColor(0.70, 0.55, 0.20, 0.50)
        love.graphics.setLineWidth(2.0)
        for i = 2, n do
            local vi = #prices - n + i
            local v = mam[vi]
            local pv = mam[vi - 1]
            if v and pv then
                local x1 = cX + (i - 2) * step
                local y1 = priceToY(toPct(pv), mn, mx, cY, h)
                local x2 = cX + (i - 1) * step
                local y2 = priceToY(toPct(v), mn, mx, cY, h)
                love.graphics.line(x1, y1, x2, y2)
            end
        end
    end
    
    -- Price line
    local lastY = cY + h / 2
    if isFeatureUnlocked("priceLine") then
        love.graphics.setColor(0.78, 0.83, 0.88)
        love.graphics.setLineWidth(1.5)
        for i = 2, n do
            local x1 = cX + (i - 2) * step
            local y1 = priceToY(toPct(visible[i - 1]), mn, mx, cY, h)
            local x2 = cX + (i - 1) * step
            local y2 = priceToY(toPct(visible[i]), mn, mx, cY, h)
            love.graphics.line(x1, y1, x2, y2)
        end
        lastY = priceToY(toPct(visible[n]), mn, mx, cY, h)
        love.graphics.setColor(0.78, 0.83, 0.88, 0.27)
        love.graphics.circle("fill", cX + (n - 1) * step, lastY, 3)
    end
    
    -- Order lines on chart
    if isFeatureUnlocked("orderLines") then
        for _, line in ipairs(orderLines) do
            local y = priceToY(toPct(line.price), mn, mx, cY, h)
            local r, gr, bv = 0.63, 0.63, 0.75
            if line.type == "buy-stop" then r, gr, bv = 0, 0.80, 0.41 end
            if line.type == "sell-stop" then r, gr, bv = 0.91, 0.25, 0.38 end
            love.graphics.setColor(r, gr, bv, 0.7)
            love.graphics.setLineWidth(1)
            love.graphics.line(cX, y, cX + w, y)
            
            -- Drag handle (circle near right end) with X inside
            local handleR = 10
            local hx, hy = cX + w - handleR - 3, y
            love.graphics.setColor(r, gr, bv, 0.8)
            love.graphics.circle("fill", hx, hy, handleR)
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.setLineWidth(1.5)
            love.graphics.circle("line", hx, hy, handleR)
            love.graphics.setLineWidth(1)
            -- X inside handle with static white halo (no jiggle)
            local xFh = love.graphics.getFont():getHeight()
            local xW = love.graphics.getFont():getWidth("X")
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
    
    -- Time label
    if currentTime and currentTime ~= "" then
        love.graphics.setColor(0.74, 0.80, 0.83)
        local tm = 10
        local fh = love.graphics.getFont():getHeight()
        local tw = love.graphics.getFont():getWidth(currentTime)
        love.graphics.print(currentTime, cX + w - tw - tm, cY + h - fh - tm)
    end
    
    -- Current price horizontal line
    love.graphics.setColor(0.78, 0.83, 0.88, 0.27)
    love.graphics.setLineWidth(1)
    love.graphics.line(cX, lastY, cX + w, lastY)
    
    -- Trade markers
    local firstIdx = #prices - n
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
                local armR = 14
                love.graphics.setColor(0.94, 0.71, 0.16)
                love.graphics.setLineWidth(4)
                for i = 0, 4 do
                    local angle = math.pi / 2 + i * 2 * math.pi / 5
                    love.graphics.line(x, y, x + math.cos(angle) * armR, y - math.sin(angle) * armR)
                end
                love.graphics.setLineWidth(1)
            elseif m.type == "star-lose" then
                -- Pct text first (left of marker): 3s visible, 2s fade
                if m.pct then
                    local elapsed = love.timer.getTime() - (m.time or 0)
                    if elapsed < 5 then
                        local alpha = elapsed < 3 and 1 or (1 - (elapsed - 3) / 2)
                        love.graphics.setColor(0.91, 0.25, 0.38, alpha)
                        local s = (m.pct >= 0 and "+" or "") .. string.format("%.2f%%", m.pct)
                        local tw = love.graphics.getFont():getWidth(s)
                        love.graphics.print(s, x - tw - 16, y + 8)
                    end
                end
                love.graphics.setColor(0.91, 0.25, 0.38)
                love.graphics.setLineWidth(4)
                love.graphics.line(x - 10, y - 10, x + 10, y + 10)
                love.graphics.line(x + 10, y - 10, x - 10, y + 10)
                love.graphics.setLineWidth(1)
            elseif m.type == "buy" then
                love.graphics.setColor(0, 0.78, 0.41)
                love.graphics.circle("fill", x, y, 8)
                love.graphics.setColor(0, 0, 0)
                love.graphics.circle("line", x, y, 8)
            elseif m.type == "sell" then
                love.graphics.setColor(0.91, 0.25, 0.38)
                love.graphics.circle("fill", x, y, 8)
                love.graphics.setColor(0, 0, 0)
                love.graphics.circle("line", x, y, 8)
            end
        end
    end
    
    -- Particles
    for _, p in ipairs(particles) do
        local alpha = p.life / p.maxLife
        love.graphics.setColor(p.r or 0, p.g or 0.78, p.b or 0.41, alpha)
        love.graphics.circle("fill", p.x, p.y, 2.5 * alpha)
    end
    
    -- Thin off-white border around chart area
    love.graphics.setColor(0.78, 0.83, 0.88, 0.25)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", cX, cY, w, h, PILL_R)
    love.graphics.setLineWidth(1)
    
    love.graphics.setScissor()
end

-- ── ORDER LINE DRAGGING ──
dragLine = nil
dragStartX = 0
dragStartY = 0
dragStartTime = 0
local HANDLE_R = 12  -- fat-finger-friendly touch radius
local TAP_DIST = 6     -- max pixels to count as a tap
local TAP_TIME = 0.3   -- max seconds to count as a short tap

function pickOrderLine(mx, my)
    local n = math.min(#prices, 720)
    if n < 2 then return nil end
    local mn, mxR = priceRange()
    local w, h = chartW, chartH
    for _, line in ipairs(orderLines) do
        local y = priceToY(toPct(line.price), mn, mxR, chartY, h)
        local hx, hy = chartX + w - HANDLE_R - 3, y
        local dx, dy = mx - hx, my - hy
        if dx * dx + dy * dy <= HANDLE_R * HANDLE_R then
            dragStartX = mx
            dragStartY = my
            dragStartTime = love.timer.getTime()
            return line
        end
    end
    return nil
end

function wasOrderLineTap(mx, my)
    local dt = love.timer.getTime() - dragStartTime
    if dt > TAP_TIME then return false end
    local dx = mx - dragStartX
    local dy = my - dragStartY
    return (dx * dx + dy * dy) < TAP_DIST * TAP_DIST
end

function handleDrag(mx, my)
    if dragLine then
        local mn, mxR = priceRange()
        local newPrice = yToPrice(my, mn, mxR, chartY, chartH)
        dragLine.price = math.floor(newPrice * 1000 + 0.5) / 1000
    end
end

function endDrag()
    dragLine = nil
end
