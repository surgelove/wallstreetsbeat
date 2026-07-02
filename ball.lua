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
-- Impact speed (px/s into the surface) below which the ball is treated as
-- resting/rolling instead of bouncing. Above it, it bounces.
BALL_REST_SPEED = 60
-- How much tangential (along-surface) speed survives a bounce.
BALL_TANGENT_KEEP = 0.92
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
tobogganSize = sy(24)
tobogganProgress = 0  -- 0..1 across visible chart
TOBOGGAN_SPEED = 0.195  -- 1.3x: crosses chart in ~5s
-- Airborne state
tobogganAirborne = false
tobogganAirVX = 0
tobogganAirVY = 0
tobogganAirGravity = 600  -- px/sec²
skierMomentum = 0          -- builds up skiing downhill, resets on chairlift
wasOnChairlift = false   -- track transition for clean reset

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
        local spawnX = narrowChartX or chartX
        local spawnW = narrowChartW or chartW
        ballX = spawnX + pad + ballRadius + math.random() * (spawnW - pad * 2 - ballRadius * 2)
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
    -- Use narrowed chart coordinates (matching what the chart actually draws)
    local cX = narrowChartX or chartX
    local ballChartW = narrowChartW or w
    local c = getChartCoords(ballChartW)
    if not c or c.n < 2 then return end
    local rewindEnd, cs, n, startIdx, mn, mx, step = c.rewindEnd, c.cs, c.n, c.startIdx, c.mn, c.mx, c.step
    local cY2 = chartY
    
    -- Build surface: XEE MA only (direct Y lookup matching chart exactly)
    local segments = {}
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
    
    local r = ballRadius
    
    -- Helper: surface (interpolated Y) that the ball is resting on / colliding with
    -- at an X position. Only returns surfaces that overlap the ball vertically
    -- (within r above the ball centre), so the ball is never grabbed from below
    -- and never snapped up onto a line that is above it (prevents "railing up").
    -- Returns y, dx, dy, isRealSurface (false for chart bottom).
    local function surfaceAt(x, centerY)
        local bestY, bestDx, bestDy, bestReal
        for _, seg in ipairs(segments) do
            local x1, y1, x2, y2, stype = seg[1], seg[2], seg[3], seg[4], seg[5]
            local segMin, segMax = math.min(x1, x2), math.max(x1, x2)
            if x >= segMin and x <= segMax then
                local dx, dy = x2 - x1, y2 - y1
                local t = dx ~= 0 and (x - x1) / dx or 0
                local y = y1 + t * dy
                -- Surface must not be more than one radius above the ball centre
                -- (i.e. within the ball's body or below it).
                if y >= centerY - r then
                    if bestY == nil or y < bestY then
                        bestY = y; bestDx, bestDy = dx, dy; bestReal = stype ~= "bottom"
                    end
                end
            end
        end
        return bestY, bestDx, bestDy, bestReal
    end
    
    -- ── Unified continuous physics (falling + rolling in one model) ──
    -- Gravity is ALWAYS applied, so the ball can never climb a slope on its own.
    -- Collisions place the ball exactly on the line and reflect only the velocity
    -- component into the surface, so it bounces where it touches and rolls
    -- naturally under gravity along whatever slope it rests on.
    if ballPhase == "falling" or ballPhase == "grounded" then
        -- Integrate
        ballVY = ballVY + ballGravity * dt
        ballX = ballX + ballVX * dt
        ballY = ballY + ballVY * dt
        
        local surfaceY, dx, dy, isReal = surfaceAt(ballX, ballY)
        if surfaceY and ballY + r >= surfaceY then
            -- Contact: sit exactly on the line
            ballY = surfaceY - r
            ballOnReal = isReal
            
            -- Upward surface normal
            local len = math.sqrt(dx * dx + dy * dy)
            local nx, ny
            if len > 0 then
                nx, ny = dy / len, -dx / len       -- perpendicular to (dx,dy)
                if ny > 0 then nx, ny = -nx, -ny end -- ensure it points up (screen -y)
            else
                nx, ny = 0, -1
            end
            
            -- Split velocity into normal / tangential components
            local vn = ballVX * nx + ballVY * ny        -- <0 = moving into surface
            local vtx = ballVX - vn * nx
            local vty = ballVY - vn * ny
            
            if vn < 0 then
                local impact = -vn
                if impact > BALL_REST_SPEED then
                    -- Fast enough to bounce: reflect the normal component
                    ballVX = vtx * BALL_TANGENT_KEEP + (-vn * ballBounce) * nx
                    ballVY = vty * BALL_TANGENT_KEEP + (-vn * ballBounce) * ny
                    ballPhase = "falling"
                else
                    -- Resting / rolling: kill the tiny into-surface velocity,
                    -- keep the tangential part (gravity's downhill pull lives here)
                    ballVX = vtx
                    ballVY = vty
                    ballPhase = "grounded"
                end
            else
                -- Separating from the surface
                ballPhase = "falling"
            end
            
            -- Rolling friction along the surface
            ballVX = ballVX * math.pow(ballFriction, dt * 60)
            if ballPhase == "grounded" and math.abs(ballVX) < 0.5 then ballVX = 0 end
        else
            -- No surface underfoot: free fall
            ballPhase = "falling"
            ballOnReal = false
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

