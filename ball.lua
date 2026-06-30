-- ── BALL PHYSICS ──
local theme = require("controls.theme")

-- Ball physics
ballPhase = nil  -- nil, "waiting", "falling", "rolling"
ballTimer = 0
ballX = 0
ballY = 0
ballVX = 0
ballVY = 0
ballAngle = 0
ballRadius = sy(12)
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

-- Toboggan riding the XEE MA (blue line)
tobogganX = 0
tobogganY = 0
tobogganAngle = 0
local tobogganSize = sy(24)
local tobogganProgress = 0  -- 0..1 across visible chart
local TOBOGGAN_SPEED = 0.195  -- 1.3x: crosses chart in ~5s
-- Airborne state
local tobogganAirborne = false
local tobogganAirVX = 0
local tobogganAirVY = 0
local tobogganAirGravity = 600  -- px/sec²
local skierMomentum = 0          -- builds up skiing downhill, resets on chairlift
local wasOnChairlift = false   -- track transition for clean reset

function updateBall(dt)
    if SCREEN ~= SCREENS.TRADING or not tickPaused or (rewindTicks or 0) > 0 or not isFeatureUnlocked("ball") then
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
        local pad = sy(9)
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
    local c = getChartCoords(w)
    if not c or c.n < 2 then return end
    local rewindEnd, cs, n, startIdx, mn, mx, step = c.rewindEnd, c.cs, c.n, c.startIdx, c.mn, c.mx, c.step
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
    -- XER MA (purple, crosser)
    if isFeatureUnlocked("slowMA") and cachedXER then
        for i = 2, n do
            local vi = startIdx + i - 1
            local v, pv = cachedXER[vi], cachedXER[vi - 1]
            if v and pv then
                local x1 = cX + (i - 2) * step
                local y1 = priceToY(toPct(pv), mn, mx, cY2, h)
                local x2 = cX + (i - 1) * step
                local y2 = priceToY(toPct(v), mn, mx, cY2, h)
                table.insert(segments, {x1, y1, x2, y2, "tema"})
            end
        end
    end
    -- XEE MA (blue, crossee)
    if isFeatureUnlocked("mediumMA") and cachedXEE then
        for i = 2, n do
            local vi = startIdx + i - 1
            local v, pv = cachedXEE[vi], cachedXEE[vi - 1]
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

