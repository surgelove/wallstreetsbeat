-- ── VELVET ANIMATED BACKGROUND (Balatro-style) ──
-- Soft, slow-moving gradients that create a fabric-like effect

local bg = {}

-- Orb: a large soft blob that slowly drifts
local orbs = {}

local COLORS = {
    {0.35, 0.18, 0.22},  -- burgundy
    {0.20, 0.25, 0.40},  -- blue
    {0.40, 0.22, 0.25},  -- wine
    {0.22, 0.30, 0.20},  -- green
}

function bg.init()
    for i = 1, 4 do
        orbs[i] = {
            x = math.random() * 1.2 - 0.1,
            y = math.random() * 1.2 - 0.1,
            r = 0.3 + math.random() * 0.4,
            dx = (math.random() - 0.5) * 0.015,
            dy = (math.random() - 0.5) * 0.015,
            color = COLORS[i],
            alpha = 0.15 + math.random() * 0.15,
        }
    end
end

function bg.update(dt)
    for _, orb in ipairs(orbs) do
        orb.x = orb.x + orb.dx * dt
        orb.y = orb.y + orb.dy * dt
        -- Wrap around edges
        if orb.x < -0.2 then orb.x = 1.2 end
        if orb.x > 1.2 then orb.x = -0.2 end
        if orb.y < -0.2 then orb.y = 1.2 end
        if orb.y > 1.2 then orb.y = -0.2 end
        -- Slowly drift color
        orb.alpha = orb.alpha + (math.random() - 0.5) * 0.02 * dt
        orb.alpha = math.max(0.10, math.min(0.30, orb.alpha))
    end
end

function bg.draw(w, h)
    -- Draw base background (full screen)
    love.graphics.setColor(0.12, 0.12, 0.16, 1)
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
