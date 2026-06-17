-- ── CONSTANTS ──

-- Design resolution (all pixel values derived from this)
BASE_W, BASE_H = 1920, 1080

-- Scale helpers: convert design values to actual pixels
function sx(v) return math.floor(v * safeWidth / BASE_W) end
function sy(v) return math.floor(v * safeHeight / BASE_H) end

-- Layout (set by applyScaling after safe area is computed)
PANEL_W = 0
APP_PAD = 0
TOPBAR_H = 0
BOTBAR_H = 0
PILL_GAP = 0
PILL_R = 0

-- Trading
TICK_INTERVAL = 0.067
RANDOM_BASE = 32.40
RW_TOTAL = 391 * 12
shareInc = 100
shareMax = 1000
startingBalance = 10000

-- Safe area
safeLeft = 0
safeTop = 0
safeWidth = 1920   -- default before recalcSafeArea
safeHeight = 1080
safeScale = 1

function applyScaling()
    PANEL_W = sx(110)
    APP_PAD = sx(5)
    TOPBAR_H = sy(44)
    BOTBAR_H = sy(34)
    PILL_GAP = sy(4)
    PILL_R = sy(8)
end
