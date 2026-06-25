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

function Slider.draw(s)
    local f = math.max(0, math.min(1, (s.value - s.min) / (s.max - s.min)))
    local cx, cy = s.x, s.y + s.h / 2

    -- Colors: use custom accent or default gold
    local ar, ag, ab = 0.94, 0.71, 0.16  -- default gold
    if s.accentColor then ar, ag, ab = s.accentColor[1], s.accentColor[2], s.accentColor[3] end

    -- Track outline
    love.graphics.setColor(ar, ag, ab)
    love.graphics.setLineWidth(3)
    love.graphics.line(cx, cy, cx + s.w, cy)
    -- Track fill
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(cx, cy, cx + s.w * f, cy)

    -- Thumb
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

return Slider
