-- ── VELVET ANIMATED BACKGROUND (Balatro-style) ──
-- Soft, slow-moving gradients that create a fabric-like effect
-- Mood-driven: shifts to green when profitable, red when unprofitable

local bg = {}

-- Orb: a large soft blob that slowly drifts
local orbs = {}

local NEUTRAL_COLORS = {
    {0.30, 0.35, 0.55},
    {0.40, 0.25, 0.55},
    {0.25, 0.45, 0.60},
    {0.45, 0.30, 0.50},
}

local GREEN_PALETTE = {
    {0.10, 0.50, 0.25},
    {0.20, 0.70, 0.30},
    {0.15, 0.55, 0.40},
    {0.25, 0.65, 0.20},
}

local RED_PALETTE = {
    {0.55, 0.10, 0.15},
    {0.75, 0.20, 0.25},
    {0.65, 0.15, 0.20},
    {0.50, 0.25, 0.20},
}

local GRAY_PALETTE = {
    {0.30, 0.32, 0.36},
    {0.25, 0.27, 0.32},
    {0.35, 0.37, 0.40},
    {0.28, 0.30, 0.34},
}

local currentPalette = NEUTRAL_COLORS
local targetPalette = NEUTRAL_COLORS
local LERP_SPEED = 0.8  -- per second

function bg.init()
    for i = 1, 5 do
        local c = NEUTRAL_COLORS[i % #NEUTRAL_COLORS + 1]
        orbs[i] = {
            x = math.random() * 1.2 - 0.1,
            y = math.random() * 1.2 - 0.1,
            r = 0.25 + math.random() * 0.45,
            dx = (math.random() - 0.5) * 0.01,
            dy = (math.random() - 0.5) * 0.01,
            color = {c[1], c[2], c[3]},
            alpha = 0.20 + math.random() * 0.20,
        }
    end
    currentPalette = NEUTRAL_COLORS
    targetPalette = NEUTRAL_COLORS
end

function bg.setMood(mood)
    if mood == "green" then
        targetPalette = GREEN_PALETTE
    elseif mood == "red" then
        targetPalette = RED_PALETTE
    elseif mood == "gray" then
        targetPalette = GRAY_PALETTE
    end
end

function bg.setNeutral()
    targetPalette = NEUTRAL_COLORS
end

function bg.update(dt)
    -- Smoothly lerp orb colors toward target palette
    local needsSwitch = currentPalette ~= targetPalette
    if needsSwitch then
        local allClose = true
        for i, orb in ipairs(orbs) do
            local tc = targetPalette[i % #targetPalette + 1]
            orb.color[1] = orb.color[1] + (tc[1] - orb.color[1]) * math.min(1, LERP_SPEED * dt)
            orb.color[2] = orb.color[2] + (tc[2] - orb.color[2]) * math.min(1, LERP_SPEED * dt)
            orb.color[3] = orb.color[3] + (tc[3] - orb.color[3]) * math.min(1, LERP_SPEED * dt)
            if math.abs(orb.color[1] - tc[1]) > 0.01 then allClose = false end
        end
        if allClose then currentPalette = targetPalette end
    end

    for _, orb in ipairs(orbs) do
        orb.x = orb.x + orb.dx * dt
        orb.y = orb.y + orb.dy * dt
        if orb.x < -0.2 then orb.x = 1.2 end
        if orb.x > 1.2 then orb.x = -0.2 end
        if orb.y < -0.2 then orb.y = 1.2 end
        if orb.y > 1.2 then orb.y = -0.2 end
        orb.alpha = orb.alpha + (math.random() - 0.5) * 0.015 * dt
        orb.alpha = math.max(0.15, math.min(0.40, orb.alpha))
    end
end

function bg.draw(w, h)
    -- Draw base background (lighter)
    love.graphics.setColor(0.18, 0.18, 0.24, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Draw soft orbs
    for _, orb in ipairs(orbs) do
        local cx = orb.x * w
        local cy = orb.y * h
        local radius = orb.r * math.min(w, h)

        -- Draw multiple layers of the same orb for a softer gradient
        love.graphics.setColor(orb.color[1], orb.color[2], orb.color[3], orb.alpha * 0.5)
        love.graphics.circle("fill", cx, cy, radius * 1.5, 64)
        love.graphics.setColor(orb.color[1], orb.color[2], orb.color[3], orb.alpha)
        love.graphics.circle("fill", cx, cy, radius, 64)
    end
end

return bg
