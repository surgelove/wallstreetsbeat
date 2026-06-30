-- ── REPLAY / DEMO SYSTEM ──
-- Records and replays automated trading sequences for demos.
-- A replay script defines: which CSV dataset to use, and a list of
-- timestamped actions (buy/sell/flat) that fire automatically as ticks advance.

local Replay = {}

-- Global used by button.lua to show pressed state during replay
replayFlashBtn = nil

-- ── REPLAY SCRIPTS ──
-- Each script:
--   name        – display name on the DEMO button
--   csvDay      – which CSV file date to use (e.g. "2026-01-02")
--   instrument  – which instrument within that CSV (e.g. "BITU")
--   groupName   – the group shown in the top bar (e.g. "BITCOIN")
--   events      – sequence of { time="HH:MM", action="...", message="..." }

Replay.scripts = {
    {
        name = "CLASSIC BITCOIN",
        csvDay = "2026-01-02",
        instrument = "BITU",
        groupName = "BITCOIN",
        events = {
            { time = "09:33", action = "buy",       message = "BITU dipped to daily low — buy the dip" },
            { time = "09:40", action = "thrust", value = 0.8, message = "Speed up through the quiet section" },
            { time = "09:51", action = "sell",      message = "Price bounced to intraday high — take profit" },
            { time = "10:15", action = "sell",      message = "Momentum reversed — short the pullback" },
            { time = "10:30", action = "leverage", value = 3,  message = "Upping the ante — 3x leverage" },
            { time = "10:45", action = "buy",       message = "Short squeezed — cover and go flat" },
            { time = "11:00", action = "thrust", value = 0.5, message = "Slow down — afternoon consolidation" },
            { time = "11:20", action = "buy",       message = "Bull flag forming — re-enter long" },
            { time = "15:55", action = "flat",      message = "End of day — close everything" },
        },
    },
    {
        name = "SCALP SESSION",
        csvDay = "2026-01-02",
        instrument = "BITU",
        groupName = "BITCOIN",
        events = {
            { time = "09:35", action = "buy",       message = "Opening shakeout — quick scalp entry" },
            { time = "09:44", action = "sell",      message = "Green candle streak — collect profits" },
            { time = "10:00", action = "sell",      message = "Resistance rejected — short the rejection" },
            { time = "10:08", action = "buy",       message = "Support held — cover short" },
            { time = "10:30", action = "buy",       message = "V-shape recovery — ride the wave" },
            { time = "10:38", action = "sell",      message = "Overbought on 1-min — quick flip" },
            { time = "11:00", action = "buy",       message = "Consolidation breakout — last scalp" },
            { time = "11:15", action = "flat",      message = "Lunch lull — step away green" },
        },
    },
    {
        name = "MOON BAGGER",
        csvDay = "2026-01-02",
        instrument = "BITU",
        groupName = "BITCOIN",
        events = {
            { time = "09:30", action = "buy",       message = "Opening price looks cheap — load up" },
            { time = "09:48", action = "buy",       message = "Healthy dip — average down" },
            { time = "09:50", action = "pl-stop",   message = "Protect downside — set stop loss" },
            { time = "09:52", action = "sell-stop", message = "Insurance if momentum turns — sell stop" },
            { time = "10:15", action = "buy-stop",  message = "Breakout above resistance — buy stop" },
            { time = "15:55", action = "flat",      message = "Close into the close — lock gains" },
        },
    },
    {
        name = "ALL BUTTONS",
        csvDay = "2026-01-02",
        instrument = "BITU",
        groupName = "BITCOIN",
        events = {
            { time = "09:31", action = "sell",        message = "Opening direction — entry short" },
            { time = "09:33", action = "buy-stop",   message = "Place buy stop above resistance" },
            { time = "09:37", action = "bags", value = 3, message = "More trades per press — 4 iterations" },
            { time = "09:40", action = "sell",       message = "Quick reversal — flip to short" },
            { time = "09:42", action = "sell-stop",  message = "Place sell stop below support" },
            { time = "09:45", action = "buy",        message = "Momentum shifting — buy back" },
            { time = "09:48", action = "pl-stop",    message = "Lock in gains — set trailing stop" },
            { time = "09:52", action = "leverage", value = 5, message = "Feeling confident — 5x leverage" },
            { time = "09:55", action = "flat",       message = "Neutral — reassess" },
            { time = "10:00", action = "sell",       message = "Bearish engulfing — short" },
            { time = "10:05", action = "sell-stop",  message = "Add sell stop as insurance" },
            { time = "10:10", action = "thrust", value = 0.9, message = "Volatility picking up — speed up" },
            { time = "10:15", action = "buy-stop",   message = "Bullish pennant — buy stop above" },
            { time = "10:30", action = "buy",        message = "Breakout confirmed — go long" },
            { time = "11:00", action = "leverage", value = 2, message = "Dial back — reduce to 2x" },
            { time = "11:30", action = "thrust", value = 0.4, message = "Easing off — slower ticks" },
            { time = "15:55", action = "flat",       message = "End of day — close position" },
        },
    },
}

-- ── STATE (set when a replay is active) ──
Replay.active = false         -- true while a replay is running
Replay.script = nil           -- reference to current script table
Replay.eventIndex = 0         -- next event to fire (1-based)
Replay.fired = {}             -- set of event indices already fired
Replay.toast = ""             -- message to show when next event fires
Replay.toastTimer = 0
Replay.flashBtn = nil         -- button ID to visually press
Replay.flashTimer = 0         -- how long the button stays pressed

-- Slider flash state (sliders don't use the Button system)
Replay.flashSliderObj = nil   -- slider object being flashed
Replay.flashSliderTimer = 0   -- how long the slider flash lasts

-- Map replay actions to trading screen button IDs
local ACTION_BTN_MAP = {
    buy       = "btn-buy",
    sell      = "btn-sell",
    flat      = "btn-flat",
    ["buy-stop"]  = "btn-buy-stop",
    ["sell-stop"] = "btn-sell-stop",
    ["pl-stop"]   = "btn-sl",
}

-- Map slider action names to global slider objects
local ACTION_SLIDER_MAP = {
    thrust    = "speedSlider",
    leverage  = "levSlider",
    bags      = "iterSlider",
}

-- Human-readable labels for each action
local ACTION_LABELS = {
    buy       = "BUY",
    sell      = "SELL",
    flat      = "CLOSE POSTN",
    ["buy-stop"]  = "BUY STOP",
    ["sell-stop"] = "SELL STOP",
    ["pl-stop"]   = "PL STOP",
    thrust    = "THRUST",
    leverage  = "DEGENERACY",
    bags      = "BAGS",
}

-- ── INIT ──
-- Call after game state is set up for a replay session.
-- Returns the group name to use for startGame().
function Replay.start(scriptIdx)
    local scripts = Replay.scripts
    if #scripts == 0 then return nil end
    local idx = scriptIdx or 1
    if idx < 1 or idx > #scripts then idx = 1 end
    Replay.script = scripts[idx]
    Replay.active = true
    Replay.eventIndex = 1
    Replay.fired = {}
    Replay.toast = ""
    Replay.toastTimer = 0
    Replay.flashBtn = nil
    Replay.flashTimer = 0
    Replay.flashSliderObj = nil
    Replay.flashSliderTimer = 0
    replayFlashBtn = nil
    return Replay.script
end

function Replay.stop()
    Replay.active = false
    Replay.script = nil
    Replay.eventIndex = 0
    Replay.fired = {}
    Replay.toast = ""
    Replay.toastTimer = 0
    Replay.flashBtn = nil
    Replay.flashTimer = 0
    Replay.flashSliderObj = nil
    Replay.flashSliderTimer = 0
    replayFlashBtn = nil
end

-- ── TICK ──
-- Called from game.lua tick() to check if any replay events should fire.
-- currentTime is the "HH:MM" string from the tick.
function Replay.tick(currentTime)
    if not Replay.active or not Replay.script then return end
    local events = Replay.script.events
    if not events or Replay.eventIndex > #events then return end

    local ev = events[Replay.eventIndex]
    if not ev then return end

    -- The event fires when the game clock reaches or surpasses its time
    -- For "HH:MM" comparison, lexicographic works since times are 0-padded
    if currentTime >= ev.time then
        -- Fire the event
        if not Replay.fired[Replay.eventIndex] then
            Replay.fired[Replay.eventIndex] = true
            Replay.executeAction(ev)
            -- Flash the corresponding button or slider so it looks pressed
            local btnId = ACTION_BTN_MAP[ev.action]
            if btnId then
                replayFlashBtn = btnId
                Replay.flashBtn = btnId
                Replay.flashTimer = 0.3  -- pressed for 0.3 seconds
            end
            -- Flash the corresponding slider if it's a slider action
            local sliderName = ACTION_SLIDER_MAP[ev.action]
            if sliderName then
                local slider = _G[sliderName]
                if slider then
                    Replay.flashSliderObj = slider
                    Replay.flashSliderTimer = 0.5
                end
            end
            -- Show what happened and why
            local label = ACTION_LABELS[ev.action] or ev.action:upper()
            local why = ev.message and (": " .. ev.message) or ""
            Replay.toast = label .. why
            Replay.toastTimer = 4
        end
        -- Always advance to next event
        Replay.eventIndex = Replay.eventIndex + 1
    end
end

-- ── EXECUTE ──
function Replay.executeAction(ev)
    local action = ev.action
    if action == "buy" then
        buy()
    elseif action == "sell" then
        sell()
    elseif action == "flat" then
        closePosition()
    elseif action == "buy-stop" then
        local count = 0
        local highest = -math.huge
        local closest = math.huge
        local highestIdx
        for i, l in ipairs(orderLines) do
            if l.type == "buy-stop" then
                count = count + 1
                if l.price > highest then highest = l.price; highestIdx = i end
                if l.price < closest then closest = l.price end
            end
        end
        local step = currentPrice * (instrumentConfig.stopStepPct or 0.004)
        if count < (tradeIterations or 1) then
            local price = highest == -math.huge and (currentAsk + step) or (highest + step)
            addOrderLine("buy-stop", round3(price))
        elseif closest ~= math.huge and (closest - currentAsk) >= 1.5 * step then
            table.remove(orderLines, highestIdx)
            addOrderLine("buy-stop", round3(currentAsk + step))
        end
    elseif action == "sell-stop" then
        local count = 0
        local lowest = math.huge
        local closest = -math.huge
        local lowestIdx
        for i, l in ipairs(orderLines) do
            if l.type == "sell-stop" then
                count = count + 1
                if l.price < lowest then lowest = l.price; lowestIdx = i end
                if l.price > closest then closest = l.price end
            end
        end
        local step = currentPrice * (instrumentConfig.stopStepPct or 0.004)
        if count < (tradeIterations or 1) then
            local price = lowest == math.huge and (currentBid - step) or (lowest - step)
            addOrderLine("sell-stop", round3(price))
        elseif closest ~= -math.huge and (currentBid - closest) >= 1.5 * step then
            table.remove(orderLines, lowestIdx)
            addOrderLine("sell-stop", round3(currentBid - step))
        end
    elseif action == "thrust" then
        local val = ev.value
        if val and speedSlider then
            val = math.max(speedSlider.min, math.min(speedSlider.max, val))
            speedSlider.value = val
            speedSlider.onChange(val)
            -- Apply speed immediately — no ramp for demo
            thrustRampActive = false
            effectiveSpeedMult = speedMult
        end
    elseif action == "leverage" then
        local val = ev.value
        if val and levSlider then
            val = math.max(levSlider.min, math.min(levSlider.max, val))
            levSlider.value = val
            levSlider.onChange(val)
        end
    elseif action == "bags" then
        local val = ev.value
        if val and iterSlider then
            val = math.max(iterSlider.min, math.min(iterSlider.max, val))
            iterSlider.value = val
            iterSlider.onChange(val)
        end
    elseif action == "pl-stop" then
        createPLStop()
    end
end

-- ── UPDATE ──
-- Called from love.update(dt).
function Replay.update(dt)
    if Replay.toastTimer > 0 then
        Replay.toastTimer = Replay.toastTimer - dt
    end
    -- Clear button flash after timer expires
    if Replay.flashTimer > 0 then
        Replay.flashTimer = Replay.flashTimer - dt
        if Replay.flashTimer <= 0 then
            Replay.flashBtn = nil
            replayFlashBtn = nil
        end
    end
    -- Clear slider flash after timer expires
    if Replay.flashSliderTimer > 0 then
        Replay.flashSliderTimer = Replay.flashSliderTimer - dt
        if Replay.flashSliderTimer <= 0 then
            Replay.flashSliderObj = nil
        end
    end
end

-- ── DRAW OVERLAY ──
-- Draw a "DEMO" badge and the script name on the trading screen.
function Replay.draw(w, h)
    if not Replay.active then return end

    -- DEMO badge (top-center)
    local badgeW = sx(300)
    local badgeH = sy(48)
    local badgeX = w / 2 - badgeW / 2
    local badgeY = TOPBAR_H + sy(6)

    love.graphics.setColor(0.91, 0.25, 0.38, 0.85)
    love.graphics.rectangle("fill", badgeX, badgeY, badgeW, badgeH, sy(9))
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setLineWidth(math.max(1, sy(1.5)))
    love.graphics.rectangle("line", badgeX, badgeY, badgeW, badgeH, sy(9))
    love.graphics.setLineWidth(math.max(1, sy(1.5)))

    local badgeFont = fonts.default33
    love.graphics.setFont(badgeFont)
    love.graphics.setColor(1, 1, 1, 0.95)
    local label = "DEMO"
    if Replay.script then
        label = label .. " | " .. Replay.script.name
    end
    love.graphics.printf(label, badgeX, badgeY + (badgeH - badgeFont:getHeight()) / 2, badgeW, "center")

    -- Latest action toast (fades over time)
    if Replay.toastTimer > 0 then
        local alpha = math.min(1, Replay.toastTimer)
        local previewFont = fonts.default27
        love.graphics.setFont(previewFont)
        local maxW = badgeW - sx(12)
        -- Word-wrap: iterate over UTF-8 characters to avoid splitting multi-byte chars
        local lines = {}
        local currentLine = ""
        local currentLineW = 0
        local spaceStart = nil  -- index of last space in currentLine (in chars)
        for word in Replay.toast:gmatch("%S+") do
            local wordW = previewFont:getWidth(word)
            if currentLine == "" then
                currentLine = word
                currentLineW = wordW
            elseif currentLineW + previewFont:getWidth(" ") + wordW <= maxW then
                currentLine = currentLine .. " " .. word
                currentLineW = currentLineW + previewFont:getWidth(" ") + wordW
            else
                table.insert(lines, currentLine)
                currentLine = word
                currentLineW = wordW
            end
        end
        if currentLine ~= "" then
            table.insert(lines, currentLine)
        end
        -- If wrapping produced nothing or a single over-wide word, fall back to truncation
        if #lines == 0 and Replay.toast ~= "" then
            table.insert(lines, Replay.toast)
        end
        local lineH = sy(30)
        local startY = badgeY + badgeH + sy(3) + sy(6)
        for li, line in ipairs(lines) do
            local ly = startY + (li - 1) * lineH
            love.graphics.setColor(0.94, 0.71, 0.16, alpha * 0.9)
            love.graphics.printf(line, badgeX, ly, badgeW, "center")
        end
    end

    -- Flash ring around the pressed button (pulsing glow)
    if Replay.flashBtn and Replay.flashTimer > 0 then
        local btn = Buttons[Replay.flashBtn]
        if btn then
            local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 20)
            local glowR = 4 + pulse * 6
            -- Outer glow ring
            love.graphics.setColor(0.94, 0.71, 0.16, pulse * 0.5)
            love.graphics.setLineWidth(math.max(1, sy(glowR)))
            love.graphics.rectangle("line", btn.x - sy(3), btn.y - sy(3), btn.w + sy(6), btn.h + sy(6), sy(12))
            love.graphics.setLineWidth(math.max(1, sy(1.5)))
            -- Inner bright ring
            love.graphics.setColor(1, 1, 1, pulse * 0.7)
            love.graphics.setLineWidth(math.max(1, sy(2.25)))
            love.graphics.rectangle("line", btn.x - 1, btn.y - 1, btn.w + 2, btn.h + 2, sy(12))
            love.graphics.setLineWidth(math.max(1, sy(1.5)))
        end
    end

    -- Flash glow around a slider that was adjusted
    if Replay.flashSliderObj and Replay.flashSliderTimer > 0 then
        local sl = Replay.flashSliderObj
        local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 18)
        local pad = sy(12)
        love.graphics.setColor(0.48, 0.41, 0.93, pulse * 0.5)
        love.graphics.setLineWidth(math.max(1, sy(5 + pulse * 3)))
        love.graphics.rectangle("line", sl.x - pad, sl.y - pad, sl.w + pad * 2, sl.h + pad * 2, sy(15))
        love.graphics.setLineWidth(math.max(1, sy(1.5)))
        -- Inner bright ring
        love.graphics.setColor(1, 1, 1, pulse * 0.6)
        love.graphics.setLineWidth(math.max(1, sy(2.25)))
        love.graphics.rectangle("line", sl.x - 2, sl.y - 2, sl.w + 4, sl.h + 4, sy(15))
        love.graphics.setLineWidth(math.max(1, sy(1.5)))
    end

    -- Upcoming event preview (shown before it fires)
    if Replay.active and Replay.script and Replay.eventIndex <= #Replay.script.events then
        local ev = Replay.script.events[Replay.eventIndex]
        if ev and not Replay.fired[Replay.eventIndex] then
            local fade = 0.5 + 0.5 * math.sin(love.timer.getTime() * 3)
            love.graphics.setColor(0.78, 0.83, 0.88, fade * 0.6)
            local nextFont = fonts.default24
            love.graphics.setFont(nextFont)
            local nextLabel = "NEXT: " .. (ACTION_LABELS[ev.action] or ev.action:upper()) .. " @" .. ev.time
            love.graphics.printf(nextLabel, badgeX, badgeY + badgeH + sy(3 + 30), badgeW, "center")
            -- Show the message (truncated if too long)
            if ev.message then
                local msg = ev.message
                local msgFont = fonts.default21
                love.graphics.setFont(msgFont)
                love.graphics.setColor(0.78, 0.83, 0.88, fade * 0.4)
                love.graphics.printf(msg, badgeX, badgeY + badgeH + sy(3 + 30 + 28), badgeW, "center")
            end
        end
    end
end

return Replay
