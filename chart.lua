-- ── CHART RENDERING ──
chartX = 0
chartY = 0
chartW = 0
chartH = 0
playPawsImage = nil
playDogImage = nil
showDogImage = false

-- Ball physics
ballPhase = nil  -- nil, "waiting", "falling", "rolling"
ballTimer = 0
ballX = 0
ballY = 0
ballVX = 0
ballVY = 0
ballAngle = 0
ballRadius = sy(8)
ballImage = nil
ballGravity = 800
ballBounce = 0.75
ballFriction = 0.99
ballDragging = false
ballOnReal = false  -- whether ball is on a real line vs chart bottom
ballStuckTimer = 0
ballLastStuckX = 0
ballLastStuckY = 0
ballShrinkTimer = 0

function updateBall(dt)
    if SCREEN ~= SCREENS.TRADING or not tickPaused or (rewindTicks or 0) > 0 then
        ballPhase = nil
        ballShrinkTimer = 0
        ballDragging = false
        return
    end
    
    if not ballImage then
        local ok, img = pcall(love.graphics.newImage, "sprites/play_ball.png")
        if ok then ballImage = img end
    end
    if not ballImage then return end
    
    -- Compute ball radius: same as dog height minus 10%
    if playPawsImage then
        ballRadius = playPawsImage:getHeight() * 0.3 * 0.9 / 2
    end
    
    if ballPhase == nil then
        ballPhase = "waiting"
        ballTimer = 2.0
        local pad = sy(6)
        ballX = chartX + pad + ballRadius + math.random() * (chartW - pad * 2 - ballRadius * 2)
        ballY = chartY + pad + ballRadius
        ballVX = 0
        ballVY = 0
        ballAngle = 0
    end
    
    if ballPhase == "waiting" then
        ballTimer = ballTimer - dt
        if ballTimer <= 0 then
            ballPhase = "falling"
        end
        return
    end
    
    -- When being dragged, skip physics
    if ballPhase == "dragging" then return end
    
    local w, h = chartW, chartH
    if w <= 0 or h <= 0 then return end
    local rewindEnd = math.max(2, #prices - (rewindTicks or 0))
    local n = math.min(rewindEnd - 1, 720)
    if n < 2 then return end
    local startIdx = rewindEnd - n + 1
    local mn, mx = priceRange()
    local step = (w * 0.97) / (n - 1)
    local cX, cY2 = chartX, chartY
    
    -- Build surface segments from price line, MAs, and chart bottom
    local segments = {}
    -- Price line
    for i = 2, n do
        local vi = startIdx + i - 1
        local x1 = cX + (i - 2) * step
        local y1 = priceToY(toPct(prices[vi - 1]), mn, mx, cY2, h)
        local x2 = cX + (i - 1) * step
        local y2 = priceToY(toPct(prices[vi]), mn, mx, cY2, h)
        table.insert(segments, {x1, y1, x2, y2, "price"})
    end
    -- TEMA (slowMA)
    if isFeatureUnlocked("slowMA") then
        local mat = tema(prices, 180)
        for i = 2, n do
            local vi = startIdx + i - 1
            local v, pv = mat[vi], mat[vi - 1]
            if v and pv then
                local x1 = cX + (i - 2) * step
                local y1 = priceToY(toPct(pv), mn, mx, cY2, h)
                local x2 = cX + (i - 1) * step
                local y2 = priceToY(toPct(v), mn, mx, cY2, h)
                table.insert(segments, {x1, y1, x2, y2, "tema"})
            end
        end
    end
    -- EMA (mediumMA)
    if isFeatureUnlocked("mediumMA") then
        local mam = ema(prices, 180)
        for i = 2, n do
            local vi = startIdx + i - 1
            local v, pv = mam[vi], mam[vi - 1]
            if v and pv then
                local x1 = cX + (i - 2) * step
                local y1 = priceToY(toPct(pv), mn, mx, cY2, h)
                local x2 = cX + (i - 1) * step
                local y2 = priceToY(toPct(v), mn, mx, cY2, h)
                table.insert(segments, {x1, y1, x2, y2, "ema"})
            end
        end
    end
    -- Chart bottom surface (full width, for bouncing)
    table.insert(segments, {cX, cY2 + h, cX + w, cY2 + h, "bottom"})
    if #segments == 0 then return end
    
    -- Helper: find the next surface below fromY at an X position
    -- Returns y, dx, dy, isRealSurface (false for chart bottom)
    local function nextSurfaceBelow(x, fromY)
        local bestY = nil
        local bestDx, bestDy = 0, 0
        local bestReal = false
        local bestType = ""
        -- Surface priority: prefer price > tema > ema > bottom
        local priority = { price = 4, tema = 3, ema = 2, bottom = 1 }
        -- Search above the reference point so upward slopes are found
        local searchAbove = ballRadius or 8
        for _, seg in ipairs(segments) do
            local x1, y1, x2, y2, stype = seg[1], seg[2], seg[3], seg[4], seg[5]
            local segMin, segMax = math.min(x1, x2), math.max(x1, x2)
            if x >= segMin and x <= segMax then
                local dx, dy = x2 - x1, y2 - y1
                local t = dx ~= 0 and (x - x1) / dx or 0
                local y = y1 + t * dy
                -- Accept surfaces above (up to r pixels) or anywhere below
                if y > fromY - searchAbove then
                    local curPrio = priority[stype] or 0
                    local bestPrio = priority[bestType] or 0
                    local replace = false
                    if bestY == nil then
                        replace = true
                    elseif curPrio > bestPrio and y < bestY + 5 then
                        -- Higher-priority surface if it's close in Y
                        replace = true
                    elseif y < bestY then
                        -- Closer surface below
                        replace = true
                    end
                    if replace then
                        bestY = y; bestDx, bestDy = dx, dy; bestReal = stype ~= "bottom"; bestType = stype
                    end
                end
            end
        end
        if bestY then
            return bestY, bestDx, bestDy, bestReal
        end
        return nil
    end
    
    local r = ballRadius
    
    if ballPhase == "falling" then
        -- Gravity
        ballVY = ballVY + ballGravity * dt
        -- Update position
        ballX = ballX + ballVX * dt
        ballY = ballY + ballVY * dt
        
        -- Check collision with next surface below
        local surfaceY, dx, dy, isReal = nextSurfaceBelow(ballX, ballY)
        if surfaceY and ballY + r > surfaceY then
            ballY = surfaceY - r
            ballOnReal = isReal
            if ballVY > 3 then
                -- Bounce off the surface slope (tennis ball-like)
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 0 then
                    -- Surface normal pointing upward (toward the ball)
                    local nx = -dy / len
                    local ny = dx / len
                    if ny > 0 then nx = -nx; ny = -ny end
                    -- Decompose velocity into normal and tangential
                    local vn = ballVX * nx + ballVY * ny
                    local vtx = ballVX - vn * nx
                    local vty = ballVY - vn * ny
                    -- Restitution on normal, friction on tangential
                    ballVX = -vn * ballBounce * nx + vtx * 0.9
                    ballVY = -vn * ballBounce * ny + vty * 0.9
                else
                    ballVY = -ballVY * ballBounce
                    ballVX = ballVX * 0.9
                end
            else
                -- Settle on surface
                ballVY = 0
                ballPhase = "grounded"
            end
        end
    elseif ballPhase == "grounded" then
        local surfaceY, dx, dy, isReal = nextSurfaceBelow(ballX, ballY - 1)
        if surfaceY then
            -- Smooth surface follow: limit Y change to avoid teleporting
            local targetY = surfaceY - r
            local maxYDelta = math.max(1, math.abs(ballVX) * dt + 2)
            ballY = ballY + math.max(-maxYDelta, math.min(maxYDelta, targetY - ballY))
            ballOnReal = isReal
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0 then
                -- Gravity component along the slope
                local gAlong = ballGravity * (dy / len)
                -- Accelerate along the slope direction
                ballVX = ballVX + gAlong * (dx / len) * dt
            end
            -- Friction
            ballVX = ballVX * math.pow(ballFriction, dt * 60)
            
            -- Update X
            ballX = ballX + ballVX * dt
            
            -- Re-check surface at new X
            local newSurfaceY, _, _, newIsReal = nextSurfaceBelow(ballX, ballY - 1)
            if newSurfaceY and newIsReal then
                local targetY = newSurfaceY - r
                local maxYDelta = math.max(1, math.abs(ballVX) * dt + 2)
                ballY = ballY + math.max(-maxYDelta, math.min(maxYDelta, targetY - ballY))
                ballOnReal = true
            elseif newSurfaceY and not newIsReal and ballOnReal then
                -- Rolled off a real line — drop by gravity instead of snapping to bottom
                ballPhase = "falling"
                ballVY = 0
                ballOnReal = false
            elseif newSurfaceY and not newIsReal then
                -- Already on bottom — stay
                local targetY = newSurfaceY - r
                local maxYDelta = math.max(1, math.abs(ballVX) * dt + 2)
                ballY = ballY + math.max(-maxYDelta, math.min(maxYDelta, targetY - ballY))
                ballVY = 0
                if math.abs(ballVX) < 1 then ballVX = 0 end
            else
                ballPhase = "falling"
            end
            
            -- If moving fast enough downhill, could lift off
            if ballVY < -5 then
                ballPhase = "falling"
            end
        else
            ballPhase = "falling"
        end
    end
    
    -- Stuck detection: if ball stays within 10px for 1 second, shrink it away
    if ballPhase == "grounded" then
        if math.abs(ballX - ballLastStuckX) + math.abs(ballY - ballLastStuckY) < 10 then
            ballStuckTimer = ballStuckTimer + dt
            if ballStuckTimer >= 1 then
                ballPhase = "shrinking"
                ballShrinkTimer = 0.5
                ballDragging = false
                return
            end
        else
            ballStuckTimer = 0
            ballLastStuckX = ballX
            ballLastStuckY = ballY
        end
    else
        ballStuckTimer = 0
    end

    -- Shrinking phase: count down and disappear
    if ballPhase == "shrinking" then
        ballShrinkTimer = ballShrinkTimer - dt
        if ballShrinkTimer <= 0 then
            ballPhase = nil
            ballShrinkTimer = 0
        end
        return
    end

    -- Rotation based on horizontal movement (realistic rolling)
    -- distance / radius = angular displacement; pi*distance matches half-turn
    local rollDist = ballVX * dt
    ballAngle = ballAngle + rollDist / ballRadius
    
    -- Check if ball reached the paws/dog — award a tendy!
    if ballPhase == "grounded" or ballPhase == "falling" then
        local img = showDogImage and playDogImage or playPawsImage
        if img then
            local targetH = (playPawsImage and playPawsImage:getHeight() or img:getHeight()) * 0.3
            local scale = targetH / img:getHeight()
            local iw, ih = img:getWidth() * scale, img:getHeight() * scale
            local ix = cX + w - iw - 2
            local iy = cY2 + h - ih - 2
            if ballX >= ix - r and ballX <= ix + iw + r
               and ballY >= iy - r and ballY <= iy + ih + r then
                tendies = math.min(tendies + 1, 10)
                ballPhase = nil
                ballDragging = false
                return
            end
        end
    end

    -- Fell off bottom of chart (below bottom surface)
    -- Removed if too far below chart bottom
    if ballY > cY2 + h + r * 4 then
        ballPhase = nil
    end
    -- Off right edge
    if ballX > cX + w + r then
        ballPhase = nil
    end
    -- Off left
    if ballX < cX - r then
        ballPhase = nil
    end
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
    chartY = TOPBAR_H + sy(8)
    chartW = w - PANEL_W * 2
    chartH = h - TOPBAR_H - BOTBAR_H - sy(6) - sy(8) * 2
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
    local n = math.min(rewindEnd - 1, 720)
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

function drawChart()
    local w, h = chartW, chartH
    if w <= 0 or h <= 0 then return end
    
    local rewindEnd = math.max(2, #prices - (rewindTicks or 0))
    local n = math.min(rewindEnd - 1, 720)
    if n < 2 then
        love.graphics.setColor(0.11, 0.13, 0.16)
        love.graphics.rectangle("fill", chartX, chartY, w, h, PILL_R)
        return
    end
    
    local startIdx = rewindEnd - n + 1
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
        love.graphics.setLineWidth(math.max(1, sy(0.5)))
        local gf = love.graphics.newFont("fonts/default.ttf", sy(25))
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
    
    -- MA Fast (TEMA 15-min, virtually no lag)
    if isFeatureUnlocked("slowMA") then
        local mat = tema(prices, 180)
        love.graphics.setColor(0.70, 0.35, 1.0, 0.85)
        love.graphics.setLineWidth(math.max(1, sy(2)))
        for i = 2, n do
            local vi = startIdx + i - 1
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
        love.graphics.setColor(0.20, 0.55, 1.0, 0.85)
        love.graphics.setLineWidth(math.max(1, sy(2)))
        for i = 2, n do
            local vi = startIdx + i - 1
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
        love.graphics.setLineWidth(math.max(1, sy(1.5)))
        for i = 2, n do
            local x1 = cX + (i - 2) * step
            local y1 = priceToY(toPct(visible[i - 1]), mn, mx, cY, h)
            local x2 = cX + (i - 1) * step
            local y2 = priceToY(toPct(visible[i]), mn, mx, cY, h)
            love.graphics.line(x1, y1, x2, y2)
        end
        lastY = priceToY(toPct(visible[n]), mn, mx, cY, h)
        love.graphics.setColor(0.78, 0.83, 0.88, 0.27)
        love.graphics.circle("fill", cX + (n - 1) * step, lastY, sy(3))
    end
    
    -- Order lines on chart
    if isFeatureUnlocked("orderLines") then
        for _, line in ipairs(orderLines) do
            local y = priceToY(toPct(line.price), mn, mx, cY, h)
            local r, gr, bv = 0.63, 0.63, 0.75
            if line.type == "buy-stop" then r, gr, bv = 0, 0.80, 0.41 end
            if line.type == "sell-stop" then r, gr, bv = 0.91, 0.25, 0.38 end
            love.graphics.setColor(r, gr, bv, 0.7)
            love.graphics.setLineWidth(math.max(1, sy(1)))
            love.graphics.line(cX, y, cX + w, y)
            
            -- Drag handle (circle near right end) with X inside
            local handleR = sy(10)
            local hx, hy = cX + w - handleR - sy(3), y
            love.graphics.setColor(r, gr, bv, 0.8)
            love.graphics.circle("fill", hx, hy, handleR)
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.setLineWidth(math.max(1, sy(1.5)))
            love.graphics.circle("line", hx, hy, handleR)
            love.graphics.setLineWidth(math.max(1, sy(1)))
            -- X inside handle with static white halo (no jiggle)
            local orderFont = love.graphics.newFont("fonts/default.ttf", sy(25))
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
        local timeFont = love.graphics.newFont("fonts/default.ttf", sy(25))
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
                local bubbleFont = love.graphics.newFont("fonts/default.ttf", sy(20))
                love.graphics.setFont(bubbleFont)
                local lines = {"gimme", "ball"}
                local bw = 0
                for _, l in ipairs(lines) do
                    local lw = bubbleFont:getWidth(l)
                    if lw > bw then bw = lw end
                end
                local bh = #lines * bubbleFont:getHeight() + sy(8)
                bw = bw + sy(12)
                local bx = ix + iw / 2 - bw / 2
                local by = iy - bh - sy(6)
                -- Bubble background
                love.graphics.setColor(1, 1, 1, 0.95)
                love.graphics.rectangle("fill", bx, by, bw, bh, sy(4))
                -- Outline
                love.graphics.setColor(0.15, 0.15, 0.18, 0.9)
                love.graphics.setLineWidth(math.max(1, sy(2)))
                love.graphics.rectangle("line", bx, by, bw, bh, sy(4))
                love.graphics.setLineWidth(math.max(1, sy(1)))
                -- Tail triangle pointing down
                local tailX = ix + iw / 2
                local tailY = by + bh
                love.graphics.polygon("fill", tailX - sy(4), tailY, tailX, tailY + sy(6), tailX + sy(4), tailY)
                -- Text
                love.graphics.setColor(0.10, 0.10, 0.12)
                for li, l in ipairs(lines) do
                    local lw = bubbleFont:getWidth(l)
                    love.graphics.print(l, bx + (bw - lw) / 2, by + sy(4) + (li - 1) * bubbleFont:getHeight())
                end
            end
            
            love.graphics.print(label, ix - tw - sx(6), cY + h - fh - 2)
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
    
    -- Current price horizontal line
    love.graphics.setColor(0.78, 0.83, 0.88, 0.27)
    love.graphics.setLineWidth(math.max(1, sy(1)))
    love.graphics.line(cX, lastY, cX + w, lastY)
    
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
                local armR = sy(14)
                love.graphics.setColor(0.94, 0.71, 0.16)
                love.graphics.setLineWidth(math.max(1, sy(4)))
                for i = 0, 4 do
                    local angle = math.pi / 2 + i * 2 * math.pi / 5
                    love.graphics.line(x, y, x + math.cos(angle) * armR, y - math.sin(angle) * armR)
                end
                love.graphics.setLineWidth(math.max(1, sy(1)))
            elseif m.type == "star-lose" then
                -- Pct text first (left of marker): 3s visible, 2s fade
                if m.pct then
                    local elapsed = love.timer.getTime() - (m.time or 0)
                    if elapsed < 5 then
                        local alpha = elapsed < 3 and 1 or (1 - (elapsed - 3) / 2)
                        love.graphics.setColor(0.91, 0.25, 0.38, alpha)
                        local s = (m.pct >= 0 and "+" or "") .. string.format("%.2f%%", m.pct)
                        local tw = love.graphics.getFont():getWidth(s)
                        love.graphics.print(s, x - tw - sx(16), y + sy(8))
                    end
                end
                love.graphics.setColor(0.91, 0.25, 0.38)
                love.graphics.setLineWidth(math.max(1, sy(4)))
                love.graphics.line(x - sx(10), y - sy(10), x + sx(10), y + sy(10))
                love.graphics.line(x + sx(10), y - sy(10), x - sx(10), y + sy(10))
                love.graphics.setLineWidth(math.max(1, sy(1)))
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
        love.graphics.circle("fill", p.x, p.y, sy(2.5) * alpha)
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
    love.graphics.setLineWidth(math.max(1, sy(1)))
    love.graphics.rectangle("line", cX, cY, w, h, PILL_R)
    love.graphics.setLineWidth(math.max(1, sy(1)))
    
    -- VHS rewind effect
    if (rewindTicks or 0) > 0 then
        local seed = love.timer.getTime() * 100
        -- Scan lines
        love.graphics.setColor(0, 0, 0, 0.15)
        for y = cY, cY + h, sy(3) do
            if (seed + y) % 7 < 3 then
                love.graphics.rectangle("fill", cX, y, w, sy(1))
            end
        end
        -- Horizontal distortion bar
        local barY = cY + ((seed * 3) % h)
        local barH = sy(4)
        love.graphics.setColor(0.9, 0.9, 0.95, 0.1)
        love.graphics.rectangle("fill", cX, barY, w, barH)
        love.graphics.setColor(0.1, 0.1, 0.15, 0.08)
        love.graphics.rectangle("fill", cX + (seed % 40), barY + barH, w, sy(1))
        -- Random static dots
        for i = 1, 30 do
            local dx = cX + (seed * (i + 7) * 137) % w
            local dy = cY + (seed * (i + 3) * 251) % h
            love.graphics.setColor(1, 1, 1, 0.1 + (i % 3) * 0.1)
            love.graphics.rectangle("fill", dx, dy, sy(2), sy(1))
        end
    end
    
    drawSnow()
    love.graphics.setScissor()
end

-- ── SNOW SYSTEM ──
snowflakes = {}
local snowSpawnTimer = 0
local snowSpawnRate = 0.15  -- seconds between spawns
local snowMaxFlakes = 200
local snowFallSpeed = 80     -- px/sec base
local snowDrift = 20         -- horizontal drift px/sec
local snowSettled = {}       -- {idx, yOffset, size, alpha, line, snowType, angle} data-relative

-- Draw a complex snowflake with 6-fold symmetry
-- type 1-5 controls complexity (more branches, dots, inner rings)
local function drawSnowflake(x, y, size, snowType, alpha)
    local r = size
    love.graphics.setLineWidth(math.max(1, r * 0.12))
    local branches = 6
    local angleStep = math.pi * 2 / branches
    
    for b = 0, branches - 1 do
        local a = b * angleStep
        local sx, sy = math.cos(a), math.sin(a)
        
        -- Main branch
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.line(x, y, x + sx * r, y + sy * r)
        
        -- Side branches (type 2+)
        if snowType >= 2 then
            for _, t in ipairs({0.4, 0.65}) do
                local bx, by = x + sx * r * t, y + sy * r * t
                local perpLen = r * 0.25
                local px, py = -sy * perpLen, sx * perpLen
                love.graphics.setColor(1, 1, 1, alpha * 0.85)
                love.graphics.line(bx + px, by + py, bx - px, by - py)
            end
        end
        
        -- Forked tips (type 3+)
        if snowType >= 3 then
            local tipX, tipY = x + sx * r, y + sy * r
            local forkLen = r * 0.28
            local fa1 = a + 0.4
            local fa2 = a - 0.4
            love.graphics.setColor(1, 1, 1, alpha * 0.7)
            love.graphics.line(tipX, tipY, tipX + math.cos(fa1) * forkLen, tipY + math.sin(fa1) * forkLen)
            love.graphics.line(tipX, tipY, tipX + math.cos(fa2) * forkLen, tipY + math.sin(fa2) * forkLen)
        end
        
        -- Dots at tips (type 4+)
        if snowType >= 4 then
            local dotR = r * 0.1
            love.graphics.setColor(1, 1, 1, alpha * 0.6)
            love.graphics.circle("fill", x + sx * r * 0.75, y + sy * r * 0.75, dotR)
        end
        
        -- Inner ring (type 5)
        if snowType >= 5 then
            love.graphics.setColor(1, 1, 1, alpha * 0.4)
            love.graphics.circle("line", x, y, r * 0.35)
        end
    end
    
    -- Center dot
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.circle("fill", x, y, r * 0.15)
    love.graphics.setLineWidth(1)
end

function updateSnow(dt)
    if SCREEN ~= SCREENS.TRADING or not dataMode then
        snowflakes = {}
        snowSettled = {}
        return
    end
    
    local w, h = chartW, chartH
    if w <= 0 or h <= 0 then return end
    
    local rewindEnd = math.max(2, #prices - (rewindTicks or 0))
    local n = math.min(rewindEnd - 1, 720)
    if n < 2 then return end
    
    local startIdx = rewindEnd - n + 1
    local mn, mx = priceRange()
    local step = (w * 0.97) / (n - 1)
    local cX, cY2 = chartX, chartY
    
    -- Compute MA data for collision
    local temaData, emaData = nil, nil
    if isFeatureUnlocked("slowMA") then
        temaData = tema(prices, 180)
    end
    if isFeatureUnlocked("mediumMA") then
        emaData = ema(prices, 180)
    end
    
    -- Helper: get MA info at a given chart X (returns idx, Y, line)
    local function maInfoAt(x)
        local relX = x - cX
        local idx = startIdx + math.floor(relX / step + 0.5)
        if idx < startIdx or idx > rewindEnd then return nil end
        if temaData and temaData[idx] then
            local yy = priceToY(toPct(temaData[idx]), mn, mx, cY2, h)
            return idx, yy, "tema"
        end
        if emaData and emaData[idx] then
            local yy = priceToY(toPct(emaData[idx]), mn, mx, cY2, h)
            return idx, yy, "ema"
        end
        return nil
    end
    
    -- Spawn new flakes
    snowSpawnTimer = snowSpawnTimer + dt
    local spawnCount = math.floor(snowSpawnTimer / snowSpawnRate)
    snowSpawnTimer = snowSpawnTimer % snowSpawnRate
    for _ = 1, math.min(spawnCount, snowMaxFlakes - #snowflakes) do
        table.insert(snowflakes, {
            x = cX + math.random() * w,
            y = cY2 + math.random() * -40,
            vy = snowFallSpeed + math.random() * 40,
            vx = (math.random() - 0.5) * snowDrift * 2,
            size = sy(4) + math.random() * sy(6),
            alpha = 0.5 + math.random() * 0.5,
            snowType = math.random(1, 5),
            angle = math.random() * math.pi * 2,
            spin = (math.random() - 0.5) * 2,
        })
    end
    
    -- Update falling flakes
    for i = #snowflakes, 1, -1 do
        local fl = snowflakes[i]
        fl.x = fl.x + fl.vx * dt
        fl.y = fl.y + fl.vy * dt
        fl.angle = fl.angle + fl.spin * dt
        
        local idx, maY, line = maInfoAt(fl.x)
        if idx then
            if fl.y >= maY - sy(4) then
                table.insert(snowSettled, {
                    idx = idx,
                    yOffset = fl.y - maY,
                    size = fl.size,
                    alpha = fl.alpha,
                    line = line,
                    snowType = fl.snowType,
                    angle = fl.angle,
                })
                table.remove(snowflakes, i)
            end
        elseif fl.y > cY2 + h + 10 then
            table.remove(snowflakes, i)
        end
    end
end

function drawSnow()
    -- Draw falling flakes
    for _, fl in ipairs(snowflakes) do
        love.graphics.push()
        love.graphics.translate(fl.x, fl.y)
        love.graphics.rotate(fl.angle)
        drawSnowflake(0, 0, fl.size, fl.snowType, fl.alpha)
        love.graphics.pop()
    end
    
    -- Draw settled flakes: recompute screen coords from data index (never removed)
    if #snowSettled > 0 then
        local w, h = chartW, chartH
        local rewindEnd = math.max(2, #prices - (rewindTicks or 0))
        local n = math.min(rewindEnd - 1, 720)
        local startIdx = rewindEnd - n + 1
        local mn, mx = priceRange()
        local step = (w * 0.97) / (n - 1)
        local cX, cY2 = chartX, chartY
        
        local temaData, emaData = nil, nil
        if isFeatureUnlocked("slowMA") then
            temaData = tema(prices, 180)
        end
        if isFeatureUnlocked("mediumMA") then
            emaData = ema(prices, 180)
        end
        
        for _, s in ipairs(snowSettled) do
            local maData = (s.line == "tema") and temaData or emaData
            if maData and maData[s.idx] then
                local relIdx = s.idx - startIdx + 1
                local sx = cX + (relIdx - 1) * step
                local sy2 = priceToY(toPct(maData[s.idx]), mn, mx, cY2, h) + s.yOffset
                
                love.graphics.push()
                love.graphics.translate(sx, sy2)
                love.graphics.rotate(s.angle)
                local r, g, b = 0.80, 0.88, 1.0
                if s.line == "ema" then
                    r, g, b = 0.88, 0.85, 0.70
                end
                love.graphics.setColor(r, g, b, s.alpha * 0.75)
                drawSnowflake(0, 0, s.size, s.snowType, s.alpha * 0.75)
                love.graphics.pop()
            end
        end
    end
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
