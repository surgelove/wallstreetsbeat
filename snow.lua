-- ── SNOW SYSTEM ──
local theme = require("controls.theme")

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
    if SCREEN ~= SCREENS.TRADING or not dataMode
       or not isFeatureUnlocked("snow")
       or not (isFeatureUnlocked("slowMA") or isFeatureUnlocked("mediumMA")) then
        snowflakes = {}
        snowSettled = {}
        return
    end
    
    local w, h = chartW, chartH
    if w <= 0 or h <= 0 then return end
    local c = getChartCoords(w)
    if not c or c.n < 2 then return end
    local rewindEnd, cs, n, startIdx, mn, mx, step = c.rewindEnd, c.cs, c.n, c.startIdx, c.mn, c.mx, c.step
    local cX, cY2 = chartX, chartY
    
    -- Compute XEE MA (crossee, blue) for snow to cling to
    -- Helper: get XEE MA info at a given chart X
    local function maInfoAt(x)
        local relX = x - cX
        local idx = startIdx + math.floor(relX / step + 0.5)
        if idx < startIdx or idx > rewindEnd then return nil end
        if cachedXEE and cachedXEE[idx] then
            local yy = priceToY(toPct(cachedXEE[idx]), mn, mx, cY2, h)
            return idx, yy
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
            size = sy(6) + math.random() * sy(9),
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
        
        local idx, maY = maInfoAt(fl.x)
        if idx then
            if fl.y >= maY - sy(6) then
                table.insert(snowSettled, {
                    idx = idx,
                    yOffset = fl.y - maY,
                    size = fl.size,
                    alpha = fl.alpha,
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
    -- Draw falling flakes (no push/pop to avoid stack overflow)
    for _, fl in ipairs(snowflakes) do
        love.graphics.setColor(1, 1, 1, fl.alpha)
        drawSnowflake(fl.x, fl.y, fl.size, fl.snowType, fl.alpha)
    end
    
    -- Draw settled flakes on XEE MA (blue)
    if #snowSettled > 0 then
local w, h = chartW, chartH
        local c = getChartCoords(w)
        if not c then return end
        local rewindEnd, cs, n, startIdx, mn, mx, step = c.rewindEnd, c.cs, c.n, c.startIdx, c.mn, c.mx, c.step
        local cX, cY2 = chartX, chartY
        
        for _, s in ipairs(snowSettled) do
            if cachedXEE and cachedXEE[s.idx] then
                local relIdx = s.idx - startIdx + 1
                local sx = cX + (relIdx - 1) * step
                local sy2 = priceToY(toPct(cachedXEE[s.idx]), mn, mx, cY2, h) + s.yOffset
                
                -- Blue-tinted to match XEE MA (no push/pop to avoid stack overflow)
                love.graphics.setColor(0.20, 0.55, 1.0, s.alpha * 0.65)
                drawSnowflake(sx, sy2, s.size, s.snowType, s.alpha * 0.65)
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
