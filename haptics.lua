-- ── HAPTICS MODULE ──
-- Isolated haptic feedback for iOS.
-- Uses love.system.vibrate (implemented via native/haptics.mm on iOS).
-- On other platforms pcall silently fails — no crash, no feedback.

local Haptics = {}

--- Play a subtle tap via the iOS Taptic Engine.
-- @tparam number duration Seconds of vibration (default 0.02 = light tap)
function Haptics.tap(duration)
    pcall(love.system.vibrate, duration or 0.02)
end

return Haptics
