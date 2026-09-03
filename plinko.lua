-- ── VOLATILITY DROP MINIGAME ──
-- Dropping a tendy on REDEEM launches this overlay. A ball drops through a
-- triangular peg field and settles into one of the reward slots at the bottom.
-- The ball physically bounces with the SAME bounciness as the chart ball
-- (it reuses ballGravity / ballBounce / ballFriction).
-- Slot payouts are fixed dollar amounts distributed randomly to the slots each
-- round. The payout of the landed slot always matches the displayed amount.

local Plinko = {}

Plinko.N = 12
Plinko.pool = {2000, 1000, 500, 200, 100, 0, -100, -200, -300, -400, -500, -600}
Plinko.amt = {}       -- exact dollar reward each slot pays this round (shuffled from pool)
Plinko.pegWid = {3, 4, 4, 5, 5, 6, 6, 6}   -- few pins per row (8 sparse rows)

-- Board geometry
Plinko.bx, Plinko.by, Plinko.bw, Plinko.bh = 0, 0, 0, 0
Plinko.pegs = {}               -- {x, y, r}
Plinko.slotY = 0
Plinko.slotH = 0
Plinko.slotW = 0
Plinko.ballR = 0

-- Physics / state
Plinko.active = false
Plinko.phase = "idle"          -- idle|fall|settle|done
Plinko.vx = 0
Plinko.vy = 0
Plinko.x = 0
Plinko.y = 0
Plinko.slot = -1
Plinko.reward = 0
Plinko.awarded = false
Plinko.settleTimer = 0
Plinko.closeTimer = 0
Plinko.hitRed = false
Plinko.inSlot = false   -- ball landed in a slot and is bouncing
Plinko.stuckTimer = 0   -- time ball has been motionless above the slots (fallen/balanced)

function Plinko._reset()
    Plinko.active = false
    Plinko.pegs = {}
    Plinko.phase = "idle"
    Plinko.slot = -1
    Plinko.reward = 0
    Plinko.awarded = false
    Plinko.hitRed = false
    Plinko.closeTimer = 0
    Plinko.inSlot = false
    Plinko.stuckTimer = 0
end

function Plinko.currentBalance()
    return math.max(0, (startingBalance or 10000) + (realizedPnl or 0))
end

-- Dollar reward / loss for slot i (exact, precomputed when the round started so
-- the landed slot always pays the displayed amount).
function Plinko.rewardFor(i)
    return Plinko.amt[(i or 0) + 1] or 0
end

-- Random drop x, always from the centre plus/minus 80% of the available space.
function Plinko._dropX()
    local pad = sx(20)
    local half = (Plinko.bw / 2) - pad
    local maxOff = half * 0.8
    return Plinko.bx + (Plinko.bw / 2) + (math.random() * 2 - 1) * maxOff
end

function Plinko.start()
    Plinko._reset()
    Plinko.active = true
    tickPaused = true
    -- Use the real tennis-ball sprite (the one the chart ball / dog uses).
    Plinko.img = nil
    local ok, im = pcall(love.graphics.newImage, "sprites/play_ball.png")
    if ok then Plinko.img = im end

    -- Layout a triangle: rows of pegs widening downward. Play field.
    Plinko.bw = sx(1180)
    Plinko.bh = sy(760)
    Plinko.bx = (1920 - Plinko.bw) / 2
    Plinko.by = sy(110)

    Plinko.ballR = sx(24)      -- bigger ball
    Plinko.pegR = sx(11)

    -- Fill the play area with pins. Placements are random but pinned to a grid
    -- with a jitter budget that keeps any two adjacent pins at least a full
    -- ball-diameter apart (surface to surface), so the ball can always pass.
    local ballD = Plinko.ballR * 2                 -- ball diameter
    local minSurf = ballD + sx(6)                  -- required surface gap
    local minCenter = minSurf + Plinko.pegR * 2    -- min center-to-center gap
    Plinko.pegs = {}

    -- Wide clear corridors on both sides so the ball never wedges/stacks
    -- against a screen edge. The pin field only spans the inner play area.
    local edgeInset = math.max(sx(120), Plinko.ballR * 2 + sx(70))
    local innerW = Plinko.bw - edgeInset * 2

    -- Choose column spacing (over innerW) so even at max jitter gaps stay open.
    local cols = math.max(6, math.floor(innerW / (minCenter * 1.15 + sx(30))))
    local dx = innerW / cols
    local maxJ = math.max(0, (dx - minCenter) / 2)  -- random offset that keeps neighbors apart
    local pgTop = Plinko.by + sy(60)
    local pgBot = Plinko.by + Plinko.bh - sy(150)
    -- Vertical row separation also respects the minimum center gap.
    local dy = math.max(sx(60), minCenter - sx(2))

    local peg = 0
    local row = 0
    local y = pgTop
    while y < pgBot do
        row = row + 1
        local off = (row % 2) * (dx / 2)
        local x0 = Plinko.bx + edgeInset + off
        local n = math.floor((innerW - off) / dx)
        for c = 0, n do
            peg = peg + 1
            local jx = (math.random() - 0.5) * (maxJ * 2)
            local jy = (math.random() - 0.5) * (math.min(dy, maxJ) * 2)
            table.insert(Plinko.pegs, {
                x = x0 + c * dx + jx,
                y = y + jy,
                r = Plinko.pegR,
                red = math.random() < 0.05,   -- ~5% of pins are red
                order = peg,
            })
        end
        y = y + dy
    end

    Plinko.slotW = Plinko.bw / Plinko.N
    Plinko.slotY = Plinko.by + Plinko.bh - Plinko.slotH
    Plinko.slotH = sy(96)

    -- Distribute the fixed payout pool randomly across the reward slots.
    Plinko.amt = {}
    local pool = {}
    for _, v in ipairs(Plinko.pool or {}) do table.insert(pool, v) end
    -- Fisher-Yates shuffle of the pool, then assign to slots in order.
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    for i = 1, Plinko.N do
        Plinko.amt[i] = pool[i] or 0
    end

    -- Ball isn't dropped yet: first the pins cascade in.
    local startY = Plinko.by + sy(30)
    Plinko.x = Plinko._dropX()
    Plinko.y = startY
    Plinko.vx = 0
    Plinko.vy = 0
    Plinko.ang = 0
    Plinko.ballScale = 1
    Plinko.revealStep = 0.006
    Plinko.appearTimer = 0
    Plinko.revealCount = #Plinko.pegs
    Plinko.phase = "reveal"
    Plinko.settleTimer = 0
    Plinko.stuckTimer = 0
end

function Plinko.update(dt)
    if not Plinko.active then return end

    -- Pins cascade in one after another before the ball is released.
    if Plinko.phase == "reveal" then
        Plinko.appearTimer = Plinko.appearTimer + dt
        if Plinko.appearTimer * (1 / (Plinko.revealStep or 0.006)) >= (Plinko.revealCount or 0) then
            Plinko.phase = "fall"
        end
        return
    end

    if Plinko.phase == "fall" then
        -- Reuse the chart-ball physics numbers so bounciness matches the chart.
        local g = ballGravity or 800
        local b = ballBounce or 0.75
        local keep = BALL_TANGENT_KEEP or 0.92   -- tangential keep on bounce
        local rest = BALL_REST_SPEED or 60
        local r = Plinko.ballR

        -- Integrate with gravity (LÖVE y-down)
        Plinko.vy = Plinko.vy + g * dt
        Plinko.x = Plinko.x + Plinko.vx * dt
        Plinko.y = Plinko.y + Plinko.vy * dt
        -- Rolling rotation driven by horizontal velocity (like the real ball)
        Plinko.ang = (Plinko.ang or 0) + (Plinko.vx / r) * dt

        -- Boundaries: keep inside board horizontally (never leave). Pull the
        -- ball back in with force whenever it touches a side, so it can't hug
        -- and stick to a wall.
        local minExitVX = sx(160)
        if Plinko.x < Plinko.bx + r + sx(2) then
            Plinko.x = Plinko.bx + r + sx(2)
            Plinko.vx = math.max(minExitVX, math.abs(Plinko.vx) * (b or 0.75))
        elseif Plinko.x > Plinko.bx + Plinko.bw - r - sx(2) then
            Plinko.x = Plinko.bx + Plinko.bw - r - sx(2)
            Plinko.vx = -math.max(minExitVX, math.abs(Plinko.vx) * (b or 0.75))
        end

        -- Collide with pegs (circles) using the ball restitution. Touching a red
        -- pin busts the run: reward is 0 and the Plinko closes.
        local hitRed = false
        for _, peg in ipairs(Plinko.pegs) do
            local ddx = Plinko.x - peg.x
            local ddy = Plinko.y - peg.y
            local minD = r + peg.r
            local d2 = ddx * ddx + ddy * ddy
            if d2 < minD * minD and d2 > 0 then
                local d = math.sqrt(d2)
                local nx = ddx / d
                local ny = ddy / d
                -- push the ball out of the peg
                Plinko.x = peg.x + nx * minD
                Plinko.y = peg.y + ny * minD
                if peg.red then
                    hitRed = true
                    break
                end
                -- reflect only the incoming normal component
                local vn = Plinko.vx * nx + Plinko.vy * ny
                if vn < 0 then
                    local impact = -vn
                    local vtx = Plinko.vx - vn * nx
                    local vty = Plinko.vy - vn * ny
                    if impact > rest then
                        Plinko.vx = vtx * keep + impact * b * nx
                        Plinko.vy = vty * keep + impact * b * ny
                    else
                        Plinko.vx = vtx * keep
                        Plinko.vy = vty * keep
                    end
                end
            end
        end

        if hitRed then
            -- Touched a red pin: every reward slot loses 10% of its value, then
            -- this ball deflates and a fresh one drops from the top so the
            -- round continues (no immediate payout for the dead ball, but the
            -- board is worth less).
            for i = 1, Plinko.N do
                if Plinko.amt[i] ~= 0 then
                    Plinko.amt[i] = math.floor((Plinko.amt[i] or 0) * 0.9 + 0.5)
                end
            end
            Plinko.vx = 0
            Plinko.vy = 0
            Plinko.ballScale = 1
            Plinko.phase = "deflate"
            return
        end

        -- Has the ball fallen past the pegs into the catch/slot zone? Once
        -- inside, pick the slot beneath it and let it keep bouncing off the
        -- slot floor until it comes to rest (only then is it awarded).
        local lastPegY = 0
        for _, p in ipairs(Plinko.pegs) do if p.y > lastPegY then lastPegY = p.y end end

        -- Caught/respawn: if the ball gets stuck (balanced on a pin, wedged so
        -- it barely moves) while still above the slot zone, drop a fresh ball
        -- from the top instead of letting the run hang forever.
        if not Plinko.inSlot and Plinko.y < lastPegY + sy(60) then
            local speed = math.abs(Plinko.vx) + math.abs(Plinko.vy)
            if speed > sx(35) then
                -- Moving (falling/bouncing): clear the stuck timer.
                Plinko.stuckTimer = 0
            else
                -- (Almost) motionless above the slots: it's balancing/wedged.
                Plinko.stuckTimer = (Plinko.stuckTimer or 0) + dt
                if (Plinko.stuckTimer or 0) > 0.55 then
                    -- Drop a fresh ball from the top (same as a red-pin respawn).
                    Plinko.x = Plinko._dropX()
                    Plinko.y = Plinko.by + sy(24)
                    Plinko.vx = 0
                    Plinko.vy = 0
                    Plinko.ang = 0
                    Plinko.ballScale = 1
                    Plinko.stuckTimer = 0
                end
            end
        end

        if not Plinko.inSlot and Plinko.y >= lastPegY + sy(60) then
            local col = math.max(0, math.min(Plinko.N - 1, math.floor((Plinko.x - Plinko.bx) / Plinko.slotW)))
            Plinko.slot = col
            Plinko.inSlot = true   -- leave the peg field; settle in this column
            Plinko.phase = "settle"
            Plinko.settleTimer = 0
            -- The ball may still be above the slot; gravity keeps pulling it
            -- down and it bounces on the slot floor until it stops.
        end
    elseif Plinko.phase == "settle" then
        -- The ball bounces freely inside its selected slot column until its
        -- speed dies out, then it gets pocketed and only THEN the payout lands.
        local g = ballGravity or 800
        local b = ballBounce or 0.75
        local rest = BALL_REST_SPEED or 60
        local r = Plinko.ballR
        local cx = Plinko.bx + Plinko.slotW * (Plinko.slot + 0.5)
        local maxH = math.max(r, Plinko.slotW / 2 - r)

        Plinko.vy = Plinko.vy + g * dt
        -- gentle horizontal centering pull so it doesn't flat-stick a wall
        local dxCol = cx - Plinko.x
        Plinko.vx = Plinko.vx + math.max(-40, math.min(40, dxCol * 4)) * dt
        -- strong horizontal damping once inside the slot
        Plinko.vx = Plinko.vx * math.max(0, 1 - 7 * dt)
        Plinko.x = Plinko.x + Plinko.vx * dt
        -- clamp inside the slot walls
        if Plinko.x < cx - maxH then Plinko.x = cx - maxH; Plinko.vx = math.abs(Plinko.vx) * 0.3
        elseif Plinko.x > cx + maxH then Plinko.x = cx + maxH; Plinko.vx = -math.abs(Plinko.vx) * 0.3 end
        Plinko.y = Plinko.y + Plinko.vy * dt
        -- bounce off the slot floor
        local floorY = Plinko.slotY + Plinko.slotH - r
        if Plinko.y >= floorY then
            Plinko.y = floorY
            if Plinko.vy > rest then
                Plinko.vy = -Plinko.vy * b
                Plinko.vx = Plinko.vx * math.max(0, 1 - 2 * dt)  -- friction on each bounce
            else
                Plinko.vy = 0
            end
        end
        Plinko.ang = (Plinko.ang or 0) + (math.max(0, Plinko.vx / r)) * dt

        -- Detect near-rest on the floor after it has had a couple of bounces:
        -- then ease it into the pocket and award.
        Plinko.settleTimer = Plinko.settleTimer + dt
        local speed = math.abs(Plinko.vx) + math.abs(Plinko.vy)
        local onFloor = Plinko.y >= floorY - sy(2)
        if Plinko.settleTimer > 0.4 and speed < 25 and onFloor then
            Plinko.phase = "done-fall"
            Plinko.pocketY = Plinko.slotY + Plinko.slotH * 0.72
            Plinko.vx, Plinko.vy = 0, 0
        end
    elseif Plinko.phase == "done-fall" then
        -- ease into the pocket, THEN award.
        local targetY = Plinko.pocketY or (Plinko.slotY + Plinko.slotH * 0.72)
        Plinko.y = Plinko.y + math.max(sy(6), (targetY - Plinko.y) * 0.2)
        if Plinko.y >= targetY - sy(2) then
            Plinko.y = targetY
            Plinko.phase = "done"
            Plinko.inSlot = true
            Plinko.reward = Plinko.rewardFor(Plinko.slot)
            if not Plinko.awarded then
                Plinko.awarded = true
                realizedPnl = (realizedPnl or 0) + Plinko.reward
            end
            Plinko.closeTimer = 1.15
        end
    elseif Plinko.phase == "done" then
        -- Briefly show the result, then close the overlay automatically.
        if (Plinko.closeTimer or 0) > 0 then
            Plinko.closeTimer = Plinko.closeTimer - dt
            if Plinko.closeTimer <= 0 then
                Plinko.close()
                tickPaused = false
            end
        end
    elseif Plinko.phase == "deflate" then
        -- Shrink the busted ball away, then drop a fresh one from the top.
        Plinko.ballScale = math.max(0, (Plinko.ballScale or 1) - dt * 3.4)
        if Plinko.ballScale <= 0 then
            Plinko.x = Plinko._dropX()
            Plinko.y = Plinko.by + sy(24)
            Plinko.vx = 0
            Plinko.vy = 0
            Plinko.ang = 0
            Plinko.ballScale = 1
            Plinko.inSlot = false
            Plinko.phase = "fall"
        end
    end
end

function Plinko.close()
    Plinko._reset()
end

function Plinko.draw()
    if not Plinko.active then return end
    local W, H = safeWidth, safeHeight

    love.graphics.setColor(0.01, 0.015, 0.02, 0.94)
    love.graphics.rectangle("fill", 0, 0, W, H)

    if btnActionFont then love.graphics.setFont(btnActionFont) end
    Button.printfWithHalo("VOLATILITY DROP", 0, sy(22), W, "center", 0.94, 0.71, 0.16)

    -- board backdrop
    love.graphics.setColor(0.06, 0.07, 0.09, 0.75)
    love.graphics.rectangle("fill", Plinko.bx - sx(16), Plinko.by - sy(16), Plinko.bw + sx(32), Plinko.bh + sy(32), sy(22))

    -- Cascading pins: reveal them one after another at the start, and mark the
    -- ~10% that are red.
    local showAll = Plinko.phase ~= "reveal"
    local revealed = -1
    if not showAll and Plinko.phase == "reveal" then
        revealed = math.floor((Plinko.appearTimer or 0) / (Plinko.revealStep or 0.006))
    end
    local count = showAll and 999999 or revealed
    for idx, p in ipairs(Plinko.pegs) do
        if showAll or idx <= count then
            if p.red then
                love.graphics.setColor(0.95, 0.20, 0.25, 1)
            else
                love.graphics.setColor(0.85, 0.88, 0.92, 0.95)
            end
            love.graphics.circle("fill", p.x, p.y, p.r)
        end
    end

    -- reward slots at bottom
    local slotY = Plinko.slotY
    for i = 1, Plinko.N do
        local s0 = Plinko.bx + (i - 1) * Plinko.slotW
        local amt = Plinko.amt[i] or 0
        local isHit = (i - 1 == Plinko.slot)
        if isHit then
            -- Highlight the landed bucket by its sign: green when positive, red otherwise.
            if amt > 0 then
                love.graphics.setColor(0.20, 0.80, 0.45, 1)
            else
                love.graphics.setColor(0.92, 0.20, 0.25, 1)
            end
        else
            love.graphics.setColor(0.16, 0.18, 0.24, 0.98)
        end
        love.graphics.rectangle("fill", s0 + 2, slotY, Plinko.slotW - 2, Plinko.slotH, sy(8))

        -- no sign shown: color carries positive(green)/negative(red)
        local absv = math.abs(amt)
        local txt = absv >= 1000 and tostring(math.floor(absv / 1000 + 0.5)) .. "K"
                  or tostring(absv)

        -- readable font; color by sign
        love.graphics.setFont(fonts.default36 or (btnActionFont or love.graphics.getFont()))
        if isHit then
            love.graphics.setColor(0, 0, 0, 0.95)
        elseif amt > 0 then
            love.graphics.setColor(0.2, 1.0, 0.5, 0.95)
        elseif amt < 0 then
            love.graphics.setColor(1.0, 0.35, 0.35, 0.95)
        else
            love.graphics.setColor(0.6, 0.6, 0.65, 0.95)
        end
        love.graphics.printf("$" .. txt, s0 + 2, slotY + (Plinko.slotH - love.graphics.getFont():getHeight()) / 2,
                             Plinko.slotW - 4, "center")
    end

    -- ball (the actual tennis ball sprite, scaled to ball radius; deflates)
    local by = Plinko.y
    if Plinko.phase == "done" and not Plinko.hitRed then by = slotY + Plinko.slotH * 0.72 end
    local bs = Plinko.ballScale or 1
    if Plinko.img then
        local scale = ((Plinko.ballR * 2) / Plinko.img:getHeight()) * bs
        love.graphics.setColor(1, 1, 1, bs)
        love.graphics.draw(Plinko.img, Plinko.x, by, Plinko.ang or 0, scale, scale,
                           Plinko.img:getWidth() / 2, Plinko.img:getHeight() / 2)
    else
        love.graphics.setColor(1, 1, 1, bs)
        love.graphics.circle("fill", Plinko.x, by, Plinko.ballR * bs)
        love.graphics.setColor(0.55, 0.6, 0.7, bs)
        love.graphics.circle("line", Plinko.x, by, Plinko.ballR * bs)
    end

    if Plinko.phase == "done" then
        local rw = Plinko.reward
        local rr, gg, bb
        local rtxt
        if rw > 0 then
            rr, gg, bb = 0.2, 1.0, 0.5
            rtxt = "YOU GAINED $" .. math.abs(rw)
        elseif rw < 0 then
            rr, gg, bb = 1.0, 0.35, 0.35
            rtxt = "YOU LOST $" .. math.abs(rw)
        else
            rr, gg, bb = 0.6, 0.6, 0.65
            rtxt = "YOU BROKE EVEN"
        end
        Button.printfWithHalo(rtxt, 0, slotY + Plinko.slotH + sy(20), W, "center", rr, gg, bb)
    end
end

return Plinko
