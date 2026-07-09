-- ── TICKER ──
-- Continuous right-to-left scrolling marquee ticker.
-- Cycles through a list of messages, seamlessly looping.
-- Supports breaking-news items that flash red.
-- Used for social media headlines and economic news above/below the chart.

local Ticker = {}
Ticker.__index = Ticker

local SEP = "  "  -- separator between messages
local BREAKING_PREFIX = "BREAKING NEWS "
local rocketImage = love.graphics.newImage("sprites/rocket.png")

function Ticker.new(messages, showRocket)
    local self = setmetatable({}, Ticker)
    self.showRocket = showRocket or false
    -- Parse messages: support both plain strings and {text, breaking} tables
    local segTexts = {}    -- full display text for each segment (for width calc)
    local segPrefix = {}   -- "⚠️ BREAKING NEWS " or nil
    local segMsg = {}      -- the actual message text (without prefix)
    local segBreaks = {}   -- boolean: is this segment breaking?
    for _, item in ipairs(messages or {}) do
        local text, isBreaking
        if type(item) == "table" then
            text = item.text or ""
            isBreaking = item.breaking or false
        else
            text = tostring(item)
            isBreaking = false
        end
        if isBreaking then
            table.insert(segPrefix, BREAKING_PREFIX)
            table.insert(segMsg, text)
            table.insert(segTexts, BREAKING_PREFIX .. text)
        else
            table.insert(segPrefix, "")
            table.insert(segMsg, text)
            table.insert(segTexts, text)
        end
        table.insert(segBreaks, isBreaking)
    end
    self.segTexts = segTexts
    self.segPrefix = segPrefix
    self.segMsg = segMsg
    self.segBreaks = segBreaks
    self.segWidths = {}    -- pixel widths of each segment (cached after font is known)
    self.segWidthsCached = false

    -- Build the full marquee text (duplicated for seamless loop)
    local single = table.concat(segTexts, SEP)
    self.fullText = single .. SEP .. single .. SEP
    self.segCount = #segTexts

    self.offset = 0
    self.speed = sx(50)
    self.textWidth = 0   -- total width of fullText (half of this = loop point)
    self.singleLen = 0   -- set when widths are cached
    self.sepW = 0
    self.breakingFlashSpeed = 3  -- flashes per second

    -- Drag state
    self.isDragging = false
    self.lastDragX = 0
    self.dragAccum = 0  -- how far the user has dragged (for momentum)
    self._pauseTimer = 0  -- pauses auto-scroll briefly after drag

    -- Hit area (set during draw)
    self.hitX = 0
    self.hitY = 0
    self.hitW = 0
    self.hitH = 0
    return self
end

function Ticker:cacheWidths(font)
    if self.segWidthsCached then return end
    self.sepW = font:getWidth(SEP)
    self.prefixWidth = font:getWidth(BREAKING_PREFIX)
    self.rocketW = 0
    self.rocketScale = 1
    if self.showRocket then
        local iw, ih = rocketImage:getDimensions()
        local rocketH = font:getHeight()
        local rocketScale = rocketH / ih
        self.rocketW = iw * rocketScale + font:getWidth(" ")
        self.rocketScale = rocketScale
    end
    local total = 0
    for i, text in ipairs(self.segTexts) do
        local w = font:getWidth(text)
        self.segWidths[i] = self.rocketW + w
        total = total + self.rocketW + w + self.sepW
    end
    -- Single loop length = sum of all seg widths + separators (no trailing sep)
    self.singleLen = total
    -- Full text = 2 single loops + 1 trailing sep (for clean wrap)
    self.textWidth = total * 2 + self.sepW
    self.segWidthsCached = true
end

-- Find which segment index is at the given pixel offset into the single-loop text.
-- Wraps any offset into [0, singleLen) for seamless infinite scrolling.
-- Returns (segIndex, offsetWithinSegment)
function Ticker:segmentAtOffset(offset, font)
    if self.singleLen <= 0 then return 1, 0 end
    -- Wrap offset into the valid range
    local wrapped = offset % self.singleLen
    local accum = 0
    for i = 1, self.segCount do
        local segEnd = accum + self.segWidths[i] + self.sepW
        if wrapped >= accum and wrapped < segEnd then
            return i, wrapped - accum
        end
        accum = segEnd
    end
    return self.segCount, 0
end

function Ticker:hit(mx, my)
    return mx >= self.hitX and mx <= self.hitX + self.hitW
       and my >= self.hitY and my <= self.hitY + self.hitH
end

function Ticker:press(gx)
    self.isDragging = true
    self.lastDragX = gx
    self.dragAccum = 0
end

function Ticker:drag(gx)
    if not self.isDragging then return end
    local dx = self.lastDragX - gx  -- positive = finger moved left
    self.lastDragX = gx
    self.offset = self.offset + dx
    -- No clamping — draw will wrap via segmentAtOffset
    self._pauseTimer = 2.0
end

function Ticker:release()
    if not self.isDragging then return end
    self.isDragging = false
end

function Ticker:update(dt)
    if self.fullText == "" then return end
    if self.singleLen <= 0 then return end

    -- Count down the drag pause timer
    if self._pauseTimer > 0 then
        self._pauseTimer = self._pauseTimer - dt
        return  -- don't auto-scroll while paused
    end

    self.offset = self.offset + self.speed * dt
end

-- draw signature: tickerSocial:draw(tickerX, vsY, tickerW, 1, tickerY, tickerH)
function Ticker:draw(x, chartY, w, scrollDir, y, h)
    if not self.fullText or self.fullText == "" then return end

    local font = fonts.bar48 or love.graphics.newFont("fonts/default.ttf", sy(48))
    love.graphics.setFont(font)
    self:cacheWidths(font)

    -- Background pill
    love.graphics.setColor(0.07, 0.08, 0.09)
    love.graphics.rectangle("fill", x, y, w, h, sy(4))
    love.graphics.setColor(0.78, 0.83, 0.88, 0.15)
    love.graphics.setLineWidth(math.max(1, sy(1)))
    love.graphics.rectangle("line", x, y, w, h, sy(4))

    -- Store hit area for touch/mouse interaction
    self.hitX = x
    self.hitY = y
    self.hitW = w
    self.hitH = h

    local now = love.timer.getTime()
    local flashing = math.sin(now * self.breakingFlashSpeed * math.pi * 2) > 0

    -- Clip to pill bounds
    love.graphics.setScissor(
        safeLeft + math.floor(x * safeScale),
        safeTop + math.floor(y * safeScale),
        math.floor(w * safeScale),
        math.floor(h * safeScale)
    )

    local fh = font:getHeight()
    local textY = y + (h - fh) / 2

    -- Continuous strip: offset determines where the strip starts
    local normOff = self.offset % self.singleLen
    local stripStartX = x + w - normOff  -- left edge of the full strip

    -- Draw all segments in order from the strip start, tiling to fill the pill
    local drawX = stripStartX
    while drawX < x + w + self.sepW do
        for i = 1, self.segCount do
            if drawX + self.segWidths[i] >= x - self.sepW then  -- only draw if visible
                local bulletW = 0
                if self.showRocket then
                    love.graphics.setColor(1, 1, 1, 0.8)
                    love.graphics.draw(rocketImage, drawX, textY, 0, self.rocketScale, self.rocketScale)
                    bulletW = self.rocketW
                end
                if self.segBreaks[i] then
                    -- Prefix flashes red
                    if flashing then
                        love.graphics.setColor(1, 0.15, 0.15)
                    else
                        love.graphics.setColor(0.85, 0.85, 0.90)
                    end
                    love.graphics.print(self.segPrefix[i], drawX + bulletW, textY)
                    -- Message always white
                    love.graphics.setColor(0.85, 0.85, 0.90)
                    love.graphics.print(self.segMsg[i], drawX + bulletW + self.prefixWidth, textY)
                else
                    love.graphics.setColor(0.85, 0.85, 0.90)
                    love.graphics.print(self.segTexts[i], drawX + bulletW, textY)
                end
            end
            drawX = drawX + self.segWidths[i]
            -- Draw separator after each segment
            if i < self.segCount then
                love.graphics.print(SEP, drawX, textY)
                drawX = drawX + self.sepW
            end
        end
        -- After last segment, add trailing separator before looping
        love.graphics.print(SEP, drawX, textY)
        drawX = drawX + self.sepW
    end

    love.graphics.setScissor()
end

return Ticker
