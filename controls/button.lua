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

-- Draw swaying text with a white halo around each letter
local function printfWithHalo(text, x, y, w, align, r, g, b, a)
    if not text or text == "" then return end
    local font = love.graphics.getFont()
    local t = love.timer.getTime()
    local speed = 2.5
    local swayAmp = 1.2
    local bounceAmp = 0.8
    local phase = 0.8

    -- Split into lines
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    local fh = font:getHeight()
    local totalH = #lines * fh
    local lineStartY = y + (0)  -- caller already centers vertically

    for li, line in ipairs(lines) do
        local totalW = font:getWidth(line)
        local startX = x
        if align == "center" then
            startX = x + (w - totalW) / 2
        end
        local cx = startX
        local ly = lineStartY + (li - 1) * fh

        for ci = 1, #line do
            local ch = line:sub(ci, ci)
            local cw = font:getWidth(ch)
            local si = (li - 1) * 10 + ci  -- unique index across lines
            local sway = math.sin(t * speed + si * phase) * swayAmp
            local bounce = math.cos(t * speed * 0.7 + si * phase * 1.3) * bounceAmp

            -- Halo
            love.graphics.setColor(1, 1, 1, 0.25)
            love.graphics.print(ch, cx + sway - 1, ly + bounce - 1)
            love.graphics.print(ch, cx + sway + 1, ly + bounce - 1)
            love.graphics.print(ch, cx + sway - 1, ly + bounce + 1)
            love.graphics.print(ch, cx + sway + 1, ly + bounce + 1)
            -- Main text
            love.graphics.setColor(r, g, b, a or 1)
            love.graphics.print(ch, cx + sway, ly + bounce)
            cx = cx + cw
        end
    end
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
    local prevFont = love.graphics.getFont()
    if btnActionFont then love.graphics.setFont(btnActionFont) end

    local fh = love.graphics.getFont():getHeight()
    local displayText = btn.text:gsub(" ", "\n")

    local pad = 8
    if btn.locked then
        btn._locked = true
        love.graphics.setColor(0, 0, 0, 0.35)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, theme.cornerRadius)
        -- Padlock icon on top-right
        if padlockImage then
            local plSize = 24
            love.graphics.setColor(1, 1, 1, 0.7)
            love.graphics.draw(padlockImage, btn.x + btn.w - plSize - 4, btn.y + 4, 0, plSize / padlockImage:getWidth(), plSize / padlockImage:getHeight())
        end
        love.graphics.setColor(0.45, 0.45, 0.45)
        love.graphics.printf(displayText, btn.x, btn.y + (btn.h - fh * 2) / 2, btn.w, "center")
        if btn.subText then
            love.graphics.setColor(0.45, 0.45, 0.45)
            love.graphics.printf(btn.subText, btn.x, btn.y + btn.h - fh - pad, btn.w, "center")
        end
        love.graphics.setFont(prevFont)
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

    -- Text with white halo — centered vertically, handles multi-line
    local ty = isPressed and 1 or 0
    local numLines = 1
    for _ in displayText:gmatch("\n") do numLines = numLines + 1 end
    printfWithHalo(displayText, btn.x, btn.y + (btn.h - fh * numLines) / 2 + ty, btn.w, "center", fg[1], fg[2], fg[3])
    if btn.subText then
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.printf(btn.subText, btn.x, btn.y + btn.h - fh - pad, btn.w, "center")
    end

    love.graphics.setFont(prevFont)
end

Button.printfWithHalo = printfWithHalo

return Button
