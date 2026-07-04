-- ── TICKER ──
-- Scrolling marquee of trading events/quips at the bottom of the chart.

local Ticker = {}

-- Separator between items
local SEP = "  ◆  "
local SCROLL_SPEED = sx(60)  -- pixels per second

-- Internal state
local tickerItems = {}   -- list of text strings
local tickerText = ""    -- concatenated string: "item1 ◆ item2 ◆ item3 ◆ ..."
local tickerWidth = 0    -- pixel width of tickerText at the ticker font
local tickerOffset = 0   -- current scroll offset in pixels
local tickerPaused = false

function Ticker.init()
    local items = (instrumentConfig and instrumentConfig.ticker) or {}
    tickerItems = {}
    for _, v in ipairs(items) do
        if type(v) == "string" and v ~= "" then
            table.insert(tickerItems, v)
        end
    end
    -- Fallback if config has none
    if #tickerItems == 0 then
        tickerItems = {
            "BUY THE DIP",
            "HODL",
            "DIAMOND HANDS",
            "TO THE MOON",
            "NOT FINANCIAL ADVICE",
            "WAGMI",
            "NGMI",
            "PRICE GO UP",
            "PRICE GO DOWN",
            "STONKS ONLY GO UP",
        }
    end
    rebuildText()
end

function Ticker.rebuild()
    rebuildText()
end

function rebuildText()
    local parts = {}
    for _, item in ipairs(tickerItems) do
        table.insert(parts, item)
    end
    tickerText = table.concat(parts, " " .. SEP .. " ") .. " " .. SEP .. " "
    -- Use fonts.default36 (same size as AKS/DIB labels) for width measurement
    local tf = (fonts and fonts.default36) or love.graphics.newFont("fonts/default.ttf", sy(36))
    tickerWidth = tf:getWidth(tickerText)
    tickerOffset = 0  -- reset scroll on rebuild
end

function Ticker.update(dt)
    if tickerPaused then return end
    if #tickerItems == 0 or tickerWidth <= 0 then return end
    tickerOffset = tickerOffset + SCROLL_SPEED * dt
    -- Reset offset once the entire text has scrolled past
    if tickerOffset >= tickerWidth then
        tickerOffset = tickerOffset - tickerWidth
    end
end

function Ticker.pause(v)
    tickerPaused = v
end

function Ticker.draw(cX, cY, cW, cH, tickerH, rightLimitX)
    if #tickerItems == 0 then return end

    local tf = (fonts and fonts.default36)
    if not tf then return end

    -- Default tickerH if not provided (paw image height)
    local th = tickerH or sy(28)
    local tickerY = cY + cH - th - sy(2)
    local tickerX = cX + sx(6)
    -- If rightLimitX given, stop the ticker before that point
    local rightEdge = rightLimitX or (cX + cW - sx(6))
    local maxW = rightEdge - tickerX
    if maxW <= 0 then return end

    love.graphics.setFont(tf)

    -- Scissor clip to keep text inside the ticker area (no background pill)
    love.graphics.setScissor(
        safeLeft + math.floor(tickerX * safeScale),
        safeTop + math.floor(tickerY * safeScale),
        math.floor(maxW * safeScale),
        math.floor(th * safeScale)
    )

    -- Draw the scrolling text (same color as AKS/DIB labels)
    love.graphics.setColor(0.90, 0.90, 0.93)
    local x = tickerX + sx(8) - (tickerOffset % tickerWidth)
    local textY = tickerY + (th - tf:getHeight()) / 2
    -- Draw enough copies to fill the visible area
    while x < tickerX + maxW + sx(8) do
        love.graphics.print(tickerText, x, textY)
        x = x + tickerWidth
    end

    -- Restore scissor to chart bounds
    love.graphics.setScissor(
        safeLeft + math.floor(cX * safeScale),
        safeTop + math.floor(cY * safeScale),
        math.floor(cW * safeScale),
        math.floor(cH * safeScale)
    )
end

return Ticker
