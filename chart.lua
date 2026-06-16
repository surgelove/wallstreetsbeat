-- ── CHART RENDERING ──
chartX = 0
chartY = 0
chartW = 0
chartH = 0

function recalcLayout()
    local w, h = love.graphics.getDimensions()
    chartX = PANEL_W + APP_PAD
    chartY = TOPBAR_H + 5
    chartW = w - PANEL_W * 2 - APP_PAD * 2
    chartH = h - TOPBAR_H - BOTBAR_H - 10
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

function drawChart()
    local w, h = chartW, chartH
    if w <= 0 or h <= 0 then return end
    
    local n = math.min(#prices, 720)
    if n < 2 then
        love.graphics.setColor(0.11, 0.13, 0.16)
        love.graphics.rectangle("fill", chartX, chartY, w, h)
        return
    end
    
    local mn, mx = priceRange()
    local step = (w * 0.97) / (n - 1)
    local cX, cY = chartX, chartY
    local cH = h
    
    love.graphics.setScissor(cX, cY, w, h)
    
    -- Background
    love.graphics.setColor(0.04, 0.05, 0.06)
    love.graphics.rectangle("fill", cX, cY, w, h)
    
    -- Switch to clean chart font for labels
    local prevFont = love.graphics.getFont()
    if chartFont then love.graphics.setFont(chartFont) end
    
    -- Grid lines
    if isFeatureUnlocked("gridLines") then
        love.graphics.setColor(0.10, 0.13, 0.19)
        love.graphics.setLineWidth(1)
        for i = 0, 6 do
            local y = cY + h * 0.06 + (h * 0.88) * (i / 6)
            love.graphics.line(cX, y, cX + w, y)
            local val = mx - (mx - mn) * (i / 6)
            local prefix = val >= 0 and "+" or ""
            local lbl = prefix .. string.format("%.2f%%", val)
            love.graphics.setColor(0.74, 0.80, 0.83)
            love.graphics.print(lbl, cX + 2, y - 8)
        end
    end
    
    -- Visible prices
    local visible = {}
    for i = #prices - n + 1, #prices do
        table.insert(visible, prices[i])
    end
    
    -- MA Slow (30-min)
    if isFeatureUnlocked("slowMA") then
        local mas = sma(prices, 360)
        love.graphics.setColor(0.48, 0.41, 0.93, 0.33)
        love.graphics.setLineWidth(1.5)
        for i = 2, n do
            local vi = #prices - n + i
            local v = mas[vi]
            local pv = mas[vi - 1]
            if v and pv then
                local x1 = cX + (i - 2) * step
                local y1 = priceToY(toPct(pv), mn, mx, cY, h)
                local x2 = cX + (i - 1) * step
                local y2 = priceToY(toPct(v), mn, mx, cY, h)
                love.graphics.line(x1, y1, x2, y2)
            end
        end
    end
    
    -- MA Medium (10-min)
    if isFeatureUnlocked("mediumMA") then
        local mam = sma(prices, 120)
        love.graphics.setColor(0.94, 0.71, 0.16, 0.40)
        love.graphics.setLineWidth(1.5)
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
        love.graphics.print(currentTime, cX + w - 45, cY + h - 15)
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
                drawStarShape(x, y, 7, 5, 0.94, 0.71, 0.16)
                if m.pct then
                    love.graphics.setColor(0, 0.78, 0.41)
                    local s = (m.pct >= 0 and "+" or "") .. string.format("%.2f%%", m.pct)
                    love.graphics.print(s, x + 10, y - 5)
                end
            elseif m.type == "star-lose" then
                love.graphics.setColor(0.91, 0.25, 0.38)
                love.graphics.setLineWidth(3)
                love.graphics.line(x - 5, y - 5, x + 5, y + 5)
                love.graphics.line(x + 5, y - 5, x - 5, y + 5)
                if m.pct then
                    local s = (m.pct >= 0 and "+" or "") .. string.format("%.2f%%", m.pct)
                    love.graphics.print(s, x + 10, y - 5)
                end
            elseif m.type == "buy" then
                love.graphics.setColor(0, 0.78, 0.41)
                love.graphics.circle("fill", x, y, 4)
                love.graphics.setColor(0, 0, 0)
                love.graphics.circle("line", x, y, 4)
            elseif m.type == "sell" then
                love.graphics.setColor(0.91, 0.25, 0.38)
                love.graphics.circle("fill", x, y, 4)
                love.graphics.setColor(0, 0, 0)
                love.graphics.circle("line", x, y, 4)
            end
        end
    end
    
    -- Particles
    for _, p in ipairs(particles) do
        local alpha = p.life / p.maxLife
        love.graphics.setColor(p.r or 0, p.g or 0.78, p.b or 0.41, alpha)
        love.graphics.circle("fill", p.x, p.y, 2.5 * alpha)
    end
    
    -- Restore previous font
    love.graphics.setFont(prevFont)
    
    love.graphics.setScissor()
end

-- ── DRAG ──
dragLine = nil

function handleDrag(mx, my)
    if dragLine then
        local mn, mxR = priceRange()
        local relY = my - chartY
        local newPrice = yToPrice(relY, mn, mxR, chartY, chartH)
        dragLine.price = math.floor(newPrice * 1000 + 0.5) / 1000
    end
end

function endDrag()
    dragLine = nil
end

function drawStarShape(cx, cy, r, spikes, r1, g1, b1)
    local rot = math.pi / 2 * 3
    local stepA = math.pi / spikes
    love.graphics.setColor(r1, g1, b1)
    local points = {}
    for i = 0, spikes * 2 - 1 do
        local angle = rot + stepA * i
        local rad = i % 2 == 0 and r or r * 0.45
        table.insert(points, cx + math.cos(angle) * rad)
        table.insert(points, cy + math.sin(angle) * rad)
    end
    love.graphics.polygon("fill", points)
    love.graphics.setColor(0, 0, 0)
    love.graphics.setLineWidth(1)
    love.graphics.polygon("line", points)
end
