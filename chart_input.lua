-- ── CHART INPUT (order-line dragging) ──
local theme = require("controls.theme")

-- ── ORDER LINE DRAGGING ──
dragLine = nil
dragStartX = 0
dragStartY = 0
dragStartTime = 0
local HANDLE_R = 12  -- fat-finger-friendly touch radius
local TAP_DIST = 6     -- max pixels to count as a tap
local TAP_TIME = 0.3   -- max seconds to count as a short tap

function pickOrderLine(mx, my)
    local cs = getChartSpan()
    local n = math.min(#prices, cs)
    if n < 2 then return nil end
    local mn, mxR = priceRange()
    local w, h = chartW, chartH
    local threshold = math.max(sy(30), HANDLE_R)
    local bestLine = nil
    local bestDist = threshold
    for _, line in ipairs(orderLines) do
        local y = priceToY(toPct(line.price), mn, mxR, chartY, h)
        if mx >= chartX and mx <= chartX + w then
            local dist = math.abs(my - y)
            if dist <= bestDist then
                bestDist = dist
                bestLine = line
            end
        end
    end
    if bestLine then
        dragStartX = mx
        dragStartY = my
        dragStartTime = love.timer.getTime()
    end
    return bestLine
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
        dragLine.price = round3(newPrice)
    end
end

function endDrag()
    dragLine = nil
end
