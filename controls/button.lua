-- ── CONTROL: BUTTON (Balatro-style) ──
-- Rounded rect + drop shadow + 3D embossed top edge

local theme = require("controls.theme")

local Button = {}

-- Helper: create a lighter version of a color
local function lighter(c, amt)
    return { math.min(1, c[1] + amt), math.min(1, c[2] + amt), math.min(1, c[3] + amt) }
end

-- Helper: create a darker version of a color
local function darker(c, amt)
    return { math.max(0, c[1] - amt), math.max(0, c[2] - amt), math.max(0, c[3] - amt) }
end

function Button.new(id, x, y, w, h, text, subText, opts)
    opts = opts or {}
    local bg = opts.bg or theme.color.surface
    return {
        id = id, x = x, y = y, w = w, h = h,
        text = text, subText = subText,
        bg = bg,
        fg = opts.fg or theme.color.fg,
        border = opts.border or bg,
        style = opts.style or "filled",
        onClick = opts.onClick or function() end,
        locked = opts.locked or false,
        lockThreshold = opts.lockThreshold,
        _locked = false,
    }
end

function Button.hit(btn, mx, my)
    return mx >= btn.x and mx <= btn.x + btn.w
       and my >= btn.y and my <= btn.y + btn.h
end

function Button.draw(btn)
    if btn.locked then
        btn._locked = true
        love.graphics.setColor(0.12, 0.12, 0.17, 0.5)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, theme.cornerRadius)
        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.print("🔒", btn.x + btn.w - 20, btn.y + 2)
        love.graphics.setColor(0.4, 0.4, 0.45)
        love.graphics.printf(btn.text, btn.x, btn.y + 5, btn.w, "center")
        if btn.subText then
            love.graphics.setColor(0.4, 0.4, 0.45)
            love.graphics.printf(btn.subText, btn.x, btn.y + btn.h - 14, btn.w, "center")
        end
        return
    end

    btn._locked = false
    local bg, fg = btn.bg, btn.fg
    local so = theme.shadowOffset
    local cr = theme.cornerRadius
    local isPressed = (pressedButtonId == btn.id)

    if btn.style == "filled" then
        if isPressed then
            -- PRESSED STATE: pushed in, no shadow, reversed emboss
            -- Darker body (pushed in)
            love.graphics.setColor(darker(bg, 0.08))
            love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, cr)
            -- Dark inset shadow at top
            love.graphics.setColor(darker(bg, 0.15))
            love.graphics.rectangle("fill", btn.x + 2, btn.y, btn.w - 4, 2, 1)
        else
            -- 1) Drop shadow (offset down-right)
            love.graphics.setColor(0, 0, 0, 0.4)
            love.graphics.rectangle("fill", btn.x + so, btn.y + so, btn.w, btn.h, cr)

            -- 2) Dark bottom edge (emboss base)
            love.graphics.setColor(darker(bg, 0.12))
            love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, cr)

            -- 3) Main body (slightly shorter from bottom for emboss)
            love.graphics.setColor(bg)
            love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h - theme.emboss, cr)

            -- 4) Light highlight strip at top (1px)
            love.graphics.setColor(lighter(bg, 0.15))
            love.graphics.rectangle("fill", btn.x + 2, btn.y + 1, btn.w - 4, 2, 1)
        end
    else
        -- Outline style: just border + subtle shadow
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.rectangle("fill", btn.x + 1, btn.y + 1, btn.w, btn.h, cr)
        love.graphics.setColor(btn.border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h, cr)
        love.graphics.setLineWidth(1)
        fg = btn.border
    end

    -- Text (shift down 1px when pressed)
    local ty = isPressed and 1 or 0
    love.graphics.setColor(fg)
    love.graphics.printf(btn.text, btn.x, btn.y + (btn.h - 14) / 2 + ty, btn.w, "center")
    if btn.subText then
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.printf(btn.subText, btn.x, btn.y + btn.h - 14, btn.w, "center")
    end
end

return Button
