-- ── CONTROL: SLIDER ──
local theme = require("controls.theme")

local Haptics = require("haptics")

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
        segments = opts.segments,
        _currentType = opts._currentType,
        onSegmentTap = opts.onSegmentTap,
        noGradient = opts.noGradient,
        _dragging = false,
        _dragVertical = false,
        _pressed = false,
        _pressX = nil,
        _pendingSegment = nil,
        _lastHapticValue = nil,
    }
end

function Slider.hit(s, mx, my)
    -- Fat-finger friendly: expand hit area to cover label on left and value on right
    local hPadL = sx(27)   -- covers label text area
    local hPadR = sx(108)   -- covers gap + value number area
    local vPad = sy(24)
    return mx >= s.x - hPadL and mx <= s.x + s.w + hPadR
       and my >= s.y - vPad and my <= s.y + s.h + vPad
end

function Slider.draw(s, label, displayValue)
    local f = math.max(0, math.min(1, (s.value - s.min) / (s.max - s.min)))
    local cx, cy = s.x, s.y + s.h / 2

    -- Colors: use custom accent or default gold
    local ar, ag, ab = 0.94, 0.71, 0.16
    if s.accentColor then ar, ag, ab = s.accentColor[1], s.accentColor[2], s.accentColor[3] end

    -- Color handle green→red based on value (like vertical sliders)
    local handleR, handleG, handleB = ar, ag, ab
    local textR, textG, textB = 0, 0, 0
    local lbl = label or s.label or ""
    local upper = lbl:upper()
    if upper ~= "" and not s.segments then
        if s.noGradient then
            textR, textG, textB = 1, 1, 1
        else
            local cf = f
            handleR = 0.05 + cf * 0.45
            handleG = 0.30 * (1 - cf)
            handleB = 0.06 * (1 - cf)
            textR, textG, textB = 1, 1, 1
        end
    end

    -- Thumb dimensions
    local labelFont = fonts.default36
    local thumbHalf
    if s.segments then
        -- Wide enough for label + all segments with breathing room
        local totalW = 0
        for _, seg in ipairs(s.segments) do
            totalW = totalW + labelFont:getWidth(seg) + sx(34)
        end
        -- Add label width if present
        if lbl and lbl ~= "" then
            totalW = totalW + labelFont:getWidth(lbl) + sx(28)
        end
        thumbHalf = (totalW + sx(16)) / 2
        handleR, handleG, handleB = ar, ag, ab
    else
        local labelW = labelFont:getWidth(lbl)
        local thumbW = labelW + sx(30)
        thumbHalf = thumbW / 2
    end
    s._thumbHalf = thumbHalf

    -- Track is inset by thumbHalf so thumb stays fully visible at edges
    local trackLeft = cx + thumbHalf
    local trackRight = cx + s.w - thumbHalf
    local trackW = trackRight - trackLeft

    -- Track line
    local trackY = cy
    love.graphics.setColor(handleR, handleG, handleB, 0.4)
    love.graphics.setLineWidth(3)
    love.graphics.line(trackLeft, trackY, trackRight, trackY)

    -- Thumb center X
    local tx = trackLeft + trackW * f

    -- Ghost handle (dim)
    if displayValue ~= nil and s.ghostValue ~= nil then
        local gf = math.max(0, math.min(1, (s.ghostValue - s.min) / (s.max - s.min)))
        local gx = trackLeft + trackW * gf
        love.graphics.setColor(handleR, handleG, handleB, 0.2)
        love.graphics.rectangle("fill", gx - thumbHalf, s.y, thumbHalf * 2, s.h, sy(9))
    end

    if s.segments then
        -- Draw segmented handle
        local thumbX = tx - thumbHalf
        local segR = sy(9)
        local segs = s.segments
        local curType = s._currentType or ""
        local n = #segs
        -- Label prefix width (e.g. "XER" or "XEE")
        local lblW = (lbl and lbl ~= "") and (labelFont:getWidth(lbl) + sx(24)) or 0
        local segStartX = thumbX + lblW
        local segAreaW = thumbHalf * 2 - lblW
        -- Calculate equal segment widths
        local totalPad = sx(4) * (n - 1)
        local segW = (segAreaW - totalPad) / n
        love.graphics.setColor(handleR * 0.5, handleG * 0.5, handleB * 0.5, 0.85)
        love.graphics.rectangle("fill", thumbX, s.y, thumbHalf * 2, s.h, segR)
        -- Draw label prefix
        if lblW > 0 then
            love.graphics.setFont(labelFont)
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.printf(lbl, thumbX, s.y + (s.h - labelFont:getHeight()) / 2 + sy(6), lblW, "center")
            -- Separator line
            love.graphics.setColor(1, 1, 1, 0.2)
            love.graphics.setLineWidth(1)
            love.graphics.line(thumbX + lblW, s.y + sy(6), thumbX + lblW, s.y + s.h - sy(6))
            love.graphics.setLineWidth(1)
        end
        -- Fixed segment button height, centered in handle
        local segBtnH = sy(36)
        local segBtnY = s.y + (s.h - segBtnH) / 2
        -- Draw segment buttons
        for i, seg in ipairs(segs) do
            local sx2 = segStartX + (i - 1) * (segW + sx(4))
            local sel = (seg == curType)
            love.graphics.setColor(sel and ar or 0.2, sel and ag or 0.22, sel and ab or 0.24, sel and 0.9 or 0.4)
            love.graphics.rectangle("fill", sx2, segBtnY, segW, segBtnH, sy(6))
            love.graphics.setFont(labelFont)
            love.graphics.setColor(sel and 1 or 0.6, sel and 1 or 0.6, sel and 1 or 0.6, sel and 1 or 0.7)
            love.graphics.printf(seg, sx2, segBtnY + (segBtnH - labelFont:getHeight()) / 2 + sy(6), segW, "center")
        end
    else
        -- Thumb background (rounded rect)
        local thumbX = tx - thumbHalf
        love.graphics.setColor(handleR, handleG, handleB, 0.85)
        love.graphics.rectangle("fill", thumbX, s.y, thumbHalf * 2, s.h, sy(9))
        love.graphics.setColor(1, 1, 1, 0.3)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", thumbX, s.y, thumbHalf * 2, s.h, sy(9))
        love.graphics.setLineWidth(1)

        -- Label text on the thumb
        love.graphics.setFont(labelFont)
        love.graphics.setColor(textR, textG, textB, 0.9)
        love.graphics.printf(lbl, thumbX, s.y + (s.h - labelFont:getHeight()) / 2 + sy(6), thumbHalf * 2, "center")
    end

    -- Value below the slider (if not the label itself)
    if displayValue then
        local valFont = fonts.default36
        love.graphics.setFont(valFont)
        love.graphics.setColor(handleR, handleG, handleB)
        local vw = valFont:getWidth(displayValue)
        love.graphics.print(displayValue, cx + s.w / 2 - vw / 2, s.y + s.h + sy(6))
    end
end

function Slider._segmentAt(s, mx, my)
    if not s.segments then return nil end
    local thumbHalf = s._thumbHalf or sx(60)
    local cx = s.x
    local trackLeft = cx + thumbHalf
    local trackRight = cx + s.w - thumbHalf
    local trackW = trackRight - trackLeft
    local f = math.max(0, math.min(1, (s.value - s.min) / (s.max - s.min)))
    local tx = trackLeft + trackW * f
    local thumbX = tx - thumbHalf
    -- Check Y: must be on the handle
    if my < s.y or my > s.y + s.h then return nil end
    -- Label prefix offset
    local labelFont = fonts.default36
    local lblW = (s.label and s.label ~= "") and (labelFont:getWidth(s.label) + sx(24)) or 0
    local segStartX = thumbX + lblW
    local segAreaW = thumbHalf * 2 - lblW
    local n = #s.segments
    local totalPad = sx(4) * (n - 1)
    local segW = (segAreaW - totalPad) / n
    for i = 1, n do
        local sx2 = segStartX + (i - 1) * (segW + sx(4))
        if mx >= sx2 and mx <= sx2 + segW then
            return s.segments[i]
        end
    end
    return nil
end

function Slider._thumbHit(s, mx, my)
    local thumbHalf = s._thumbHalf or sx(60)
    local cx = s.x
    local trackLeft = cx + thumbHalf
    local trackRight = cx + s.w - thumbHalf
    local trackW = trackRight - trackLeft
    local f = math.max(0, math.min(1, (s.value - s.min) / (s.max - s.min)))
    local tx = trackLeft + trackW * f
    return mx >= tx - thumbHalf and mx <= tx + thumbHalf
       and my >= s.y and my <= s.y + s.h
end

function Slider.press(s, mx, my)
    if s.segments then
        local seg = Slider._segmentAt(s, mx, my)
        if seg then
            s._pressed = true
            s._dragging = false
            s._pressX = mx
            s._pendingSegment = seg
            return true
        end
    end
    if Slider._thumbHit(s, mx, my) then
        s._pressed = true
        s._dragging = false
        s._pressX = mx
        return true
    end
    return false
end

function Slider.drag(s, mx)
    if s._pressed then
        -- Dead zone: only convert to drag if moved more than 8px
        if math.abs(mx - s._pressX) < sx(8) then
            return
        end
        s._pressed = false
        s._pendingSegment = nil
        s._dragging = true
    end
    if s._dragging then
        Slider._updateValue(s, mx)
    end
end

function Slider._snapValue(s, raw)
    if s.step > 0 then
        raw = math.floor(raw / s.step + 0.5) * s.step
    end
    return math.max(s.min, math.min(s.max, raw))
end

function Slider._applyValue(s, value)
    s.value = value
    local threshold = s.step > 0 and (s.step * 0.5) or (s.max - s.min) * 0.02
    if s._lastHapticValue ~= nil and math.abs(s.value - s._lastHapticValue) >= threshold then
        Haptics.tap(0.01)
    end
    s._lastHapticValue = s.value
    s.onChange(s.value)
end

function Slider._updateValue(s, mx)
    local f = math.max(0, math.min(1, (mx - s.x) / s.w))
    local raw = s.min + f * (s.max - s.min)
    Slider._applyValue(s, Slider._snapValue(s, raw))
end

-- ── VERTICAL SLIDER ──
function Slider.hitVertical(s, mx, my)
    local hPad = sx(45)
    local vPad = sy(12)
    return mx >= s.x - hPad and mx <= s.x + s.w + hPad
       and my >= s.y - vPad and my <= s.y + s.h + vPad
end

function Slider.drawVertical(s, label, displayValue, ghostValue)
    local f = math.max(0, math.min(1, (s.value - s.min) / (s.max - s.min)))
    local cx, cy = s.x + s.w / 2, s.y
    local ar, ag, ab = 0.94, 0.71, 0.16
    if s.accentColor then ar, ag, ab = s.accentColor[1], s.accentColor[2], s.accentColor[3] end

    -- Color the handle based on value
    local handleR, handleG, handleB = ar, ag, ab
    local textR, textG, textB = 0, 0, 0
    local upper = label:upper()
    if upper == "THRUST" or upper == "DEGEN" then
        -- Green→red gradient (risk-related)
        local cf = f
        handleR = 0.05 + cf * 0.45
        handleG = 0.30 * (1 - cf)
        handleB = 0.06 * (1 - cf)
        textR, textG, textB = 1, 1, 1
    elseif upper == "SCOPE" then
        -- Blue gradient: medium blue (short) → navy (all)
        local cf = f
        handleR = 0.25 - cf * 0.17
        handleG = 0.50 - cf * 0.42
        handleB = 0.80 - cf * 0.50
        textR, textG, textB = 1, 1, 1
    elseif upper == "BAGS" then
        -- Violet gradient: lighter (few bags) → darker (more bags)
        -- Midpoint at value 4 (cf=0.25) = (117, 57, 147)
        local cf = 1 - f  -- reverse to match info pill direction
        handleR = 0.395 + cf * 0.255
        handleG = 0.182 + cf * 0.168
        handleB = 0.485 + cf * 0.365
        textR, textG, textB = 1, 1, 1
    end

    -- Determine thumb size from label (rotated text height = text pixel width)
    local labelFont = fonts.default45
    local textW = labelFont:getWidth(label)
    local textH = labelFont:getHeight()
    local thumbH = textW + sy(30)  -- tall enough for full rotated text + padding
    local thumbHalf = thumbH / 2
    s._thumbHalf = thumbHalf

    -- Track is inset by thumbHalf so thumb stays full height at min/max
    local trackTop = cy + thumbHalf
    local trackBot = cy + s.h - thumbHalf
    local trackH = trackBot - trackTop

    -- Track background (slimmer — inset from edges)
    local trackR = sy(9)
    local trackPad = sx(15)
    love.graphics.setColor(handleR, handleG, handleB, 0.4)
    love.graphics.rectangle("fill", s.x + trackPad, trackTop, s.w - trackPad * 2, trackH, trackR)

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
    love.graphics.print(label, -textW / 2, -textH / 2 + sy(6))
    love.graphics.pop()

    -- Value at bottom (below the slider) — skip for THRUST, BAGS, and DEGEN
    if upper ~= "THRUST" and upper ~= "BAGS" and upper ~= "DEGEN" then
        local valFont = fonts.default39
        love.graphics.setFont(valFont)
        love.graphics.setColor(handleR, handleG, handleB)
        local vw = valFont:getWidth(displayValue)
        love.graphics.print(displayValue, cx - vw / 2, cy + s.h + sy(6))
    end
end

function Slider._thumbHitVertical(s, mx, my)
    local thumbHalf = s._thumbHalf or (s.h * 0.1)
    local trackTop = s.y + thumbHalf
    local trackBot = s.y + s.h - thumbHalf
    local trackH = trackBot - trackTop
    local f = math.max(0, math.min(1, (s.value - s.min) / (s.max - s.min)))
    local ty = trackTop + trackH * (1 - f)
    local thumbY = ty - thumbHalf
    local thumbH = thumbHalf * 2
    return mx >= s.x and mx <= s.x + s.w
       and my >= thumbY and my <= thumbY + thumbH
end

function Slider.pressVertical(s, mx, my)
    if Slider._thumbHitVertical(s, mx, my) then
        s._dragging = true
        s._dragVertical = true
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
    if s._pendingSegment then
        -- Was a tap on a segment — fire segment callback
        local seg = s._pendingSegment
        s._pendingSegment = nil
        s._pressed = false
        s._dragging = false
        s._dragVertical = false
        if s.onSegmentTap then
            s.onSegmentTap(seg)
        end
        return
    end
    if s._pressed then
        -- Was a tap without drag — fire onTap callback
        s._pressed = false
        if s.onTap then
            s.onTap(s)
        end
    end
    s._dragging = false
    s._dragVertical = false
end

function Slider._updateValueVertical(s, my)
    local thumbHalf = s._thumbHalf or (s.h * 0.1)
    local trackTop = s.y + thumbHalf
    local trackBot = s.y + s.h - thumbHalf
    local f = math.max(0, math.min(1, (trackBot - my) / (trackBot - trackTop)))
    local raw = s.min + f * (s.max - s.min)
    Slider._applyValue(s, Slider._snapValue(s, raw))
end

return Slider
