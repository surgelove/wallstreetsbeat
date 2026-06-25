-- ── CONTROL: SLIDER ──
local theme = require("controls.theme")

local Slider = {}

function Slider.new(id, x, y, w, h, opts)
    opts = opts or {}
    return {
        id = id, x = x, y = y, w = w, h = h,
        min = opts.min or 0,
        max = opts.max or 100,
        value = opts.value or opts.min or 0,
        step = opts.step or 0,
        label = opts.label or "",
        accentColor = opts.accentColor,
        onChange = opts.onChange or function() end,
        _dragging = false,
        _dragVertical = false,
    }
end

function Slider.hit(s, mx, my)
    -- Fat-finger friendly: expand hit area to cover label on left and value on right
    local hPadL = sx(18)   -- covers label text area
    local hPadR = sx(72)   -- covers gap + value number area
    local vPad = sy(16)
    return mx >= s.x - hPadL and mx <= s.x + s.w + hPadR
       and my >= s.y - vPad and my <= s.y + s.h + vPad
end

function Slider.draw(s, ghostValue)
    local f = math.max(0, math.min(1, (s.value - s.min) / (s.max - s.min)))
    local cx, cy = s.x, s.y + s.h / 2

    -- Colors: use custom accent or default gold
    local ar, ag, ab = 0.94, 0.71, 0.16  -- default gold
    if s.accentColor then ar, ag, ab = s.accentColor[1], s.accentColor[2], s.accentColor[3] end

    -- Track outline
    love.graphics.setColor(ar, ag, ab, 0.4)
    love.graphics.setLineWidth(3)
    love.graphics.line(cx, cy, cx + s.w, cy)
    -- Track fill (up to current handle)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(cx, cy, cx + s.w * f, cy)

    -- Ghost handle (dim, shows where the crawling speed is)
    if ghostValue ~= nil then
        local gf = math.max(0, math.min(1, (ghostValue - s.min) / (s.max - s.min)))
        local gx = cx + s.w * gf
        local ghostR = sy(12)
        love.graphics.setColor(ar, ag, ab, 0.3)
        love.graphics.circle("fill", gx, cy, ghostR)
        love.graphics.setColor(1, 1, 1, 0.25)
        love.graphics.setLineWidth(1)
        love.graphics.circle("line", gx, cy, ghostR)
    end

    -- Thumb (current target handle)
    local tx = cx + s.w * f
    local thumbR = sy(16)
    love.graphics.setColor(ar, ag, ab)
    love.graphics.circle("fill", tx, cy, thumbR)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setLineWidth(1.5)
    love.graphics.circle("line", tx, cy, thumbR)
    love.graphics.setLineWidth(1)

    -- Label
    if s.label ~= "" then
        love.graphics.setColor(theme.color.fgDim)
        love.graphics.printf(s.label, cx, cy - 20, s.w, "center")
    end
end

function Slider.press(s, mx, my)
    if Slider.hit(s, mx, my) then
        s._dragging = true
        Slider._updateValue(s, mx)
        return true
    end
    return false
end

function Slider.drag(s, mx)
    if s._dragging then
        Slider._updateValue(s, mx)
    end
end

function Slider.release(s)
    s._dragging = false
end

function Slider._updateValue(s, mx)
    local f = math.max(0, math.min(1, (mx - s.x) / s.w))
    local raw = s.min + f * (s.max - s.min)
    if s.step > 0 then
        raw = math.floor(raw / s.step + 0.5) * s.step
    end
    s.value = math.max(s.min, math.min(s.max, raw))
    s.onChange(s.value)
end

-- ── VERTICAL SLIDER ──
function Slider.hitVertical(s, mx, my)
    local hPad = sx(30)
    local vPad = sy(8)
    return mx >= s.x - hPad and mx <= s.x + s.w + hPad
       and my >= s.y - vPad and my <= s.y + s.h + vPad
end

function Slider.drawVertical(s, label, displayValue, ghostValue)
    local f = math.max(0, math.min(1, (s.value - s.min) / (s.max - s.min)))
    local cx, cy = s.x + s.w / 2, s.y
    local ar, ag, ab = 0.94, 0.71, 0.16
    if s.accentColor then ar, ag, ab = s.accentColor[1], s.accentColor[2], s.accentColor[3] end

    -- If the label is THRUST or DEGENERACY, color the handle based on value (green→red)
    local handleR, handleG, handleB = ar, ag, ab
    local textR, textG, textB = 0, 0, 0
    local upper = label:upper()
    if upper == "THRUST" or upper == "DEGENERACY" then
        -- Interpolate: 0 = dark green, 1 = dark red
        handleR = 0.15 + f * 0.55
        handleG = 0.50 * (1 - f)
        handleB = 0.10 * (1 - f)
        textR, textG, textB = 1, 1, 1  -- white text
    end

    -- Determine thumb size from label (rotated text height = text pixel width)
    local labelFont = love.graphics.newFont("fonts/default.ttf", sy(30))
    local textW = labelFont:getWidth(label)
    local textH = labelFont:getHeight()
    local thumbH = textW + sy(20)  -- tall enough for full rotated text + padding
    local thumbHalf = thumbH / 2
    s._thumbHalf = thumbHalf

    -- Track is inset by thumbHalf so thumb stays full height at min/max
    local trackTop = cy + thumbHalf
    local trackBot = cy + s.h - thumbHalf
    local trackH = trackBot - trackTop

    -- Track background
    local trackR = sy(6)
    love.graphics.setColor(handleR, handleG, handleB, 0.12)
    love.graphics.rectangle("fill", s.x, trackTop, s.w, trackH, trackR)

    -- Thumb position (center of thumb along the inset track)
    local ty = trackTop + trackH * (1 - f)
    local thumbTop = ty - thumbHalf
    local thumbBot = ty + thumbHalf
    local thumbY = thumbTop
    local thumbHActual = thumbH  -- always full height

    -- Ghost handle
    if ghostValue ~= nil then
        local gf = math.max(0, math.min(1, (ghostValue - s.min) / (s.max - s.min)))
        local gty = trackTop + trackH * (1 - gf)
        local gTop = gty - thumbHalf
        local gBot = gty + thumbHalf
        love.graphics.setColor(handleR, handleG, handleB, 0.2)
        love.graphics.rectangle("fill", s.x, gTop, s.w, thumbH, trackR)
    end

    -- Thumb background (rounded rect)
    love.graphics.setColor(handleR, handleG, handleB, 0.85)
    love.graphics.rectangle("fill", s.x, thumbY, s.w, thumbHActual, trackR)
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", s.x, thumbY, s.w, thumbHActual, trackR)

    -- Label text rotated 90°
    love.graphics.setFont(labelFont)
    love.graphics.setColor(textR, textG, textB, 0.9)
    love.graphics.push()
    love.graphics.translate(cx, thumbY + thumbHActual / 2)
    love.graphics.rotate(-math.pi / 2)  -- rotate 90° counter-clockwise
    love.graphics.print(label, -textW / 2, -textH / 2)
    love.graphics.pop()

    -- Value at bottom (below the slider)
    local valFont = love.graphics.newFont("fonts/default.ttf", sy(26))
    love.graphics.setFont(valFont)
    love.graphics.setColor(handleR, handleG, handleB)
    local vw = valFont:getWidth(displayValue)
    love.graphics.print(displayValue, cx - vw / 2, cy + s.h + sy(4))
end

function Slider.pressVertical(s, mx, my)
    if Slider.hitVertical(s, mx, my) then
        s._dragging = true
        s._dragVertical = true
        Slider._updateValueVertical(s, my)
        return true
    end
    return false
end

function Slider.dragVertical(s, my)
    if s._dragging and s._dragVertical then
        Slider._updateValueVertical(s, my)
    end
end

function Slider.release(s)
    s._dragging = false
    s._dragVertical = false
end

function Slider._updateValueVertical(s, my)
    local thumbHalf = s._thumbHalf or (s.h * 0.1)
    local trackTop = s.y + thumbHalf
    local trackBot = s.y + s.h - thumbHalf
    local f = math.max(0, math.min(1, (trackBot - my) / (trackBot - trackTop)))
    local raw = s.min + f * (s.max - s.min)
    if s.step > 0 then
        raw = math.floor(raw / s.step + 0.5) * s.step
    end
    s.value = math.max(s.min, math.min(s.max, raw))
    s.onChange(s.value)
end

return Slider
