-- ── CONSTANTS ──

-- Design resolution (all pixel values derived from this)
BASE_W, BASE_H = 1920, 1080

-- Scale helpers: convert design values to actual pixels
function sx(v) return math.floor(v * safeWidth / BASE_W) end
function sy(v) return math.floor(v * safeHeight / BASE_H) end

-- Price rounding helper: round to 3 decimal places
function round3(x) return math.floor(x * 1000 + 0.5) / 1000 end

-- Default stop step percentage (matching config.lua)
DEFAULT_STOP_STEP_PCT = 0.001

-- Named constants for magic numbers
REWIND_MAX_TICKS = 720    -- max ticks that can be rewound (1 hour at 12 ticks/min)
TENDY_MAX = 10            -- max tendies a player can hold
TICKS_PER_MINUTE = 12     -- trading ticks per minute of market time

-- Font auto-sizing helper: shrink font until text fits, returns (font, size)
function fitFont(text, maxW, startSize, minSize, fontFile)
    fontFile = fontFile or "fonts/default.ttf"
    minSize = minSize or sy(15)
    startSize = startSize or sy(78)
    local size = startSize
    local font = love.graphics.newFont(fontFile, size)
    while font:getWidth(text) > maxW and size > minSize do
        size = size - 1
        font = love.graphics.newFont(fontFile, size)
    end
    return font, size
end

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
EASY_BASE = 50.00
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
    PANEL_W = sx(247.5)
    APP_PAD = sx(12)
    TOPBAR_H = sy(120)
    BOTBAR_H = sy(120)
    PILL_GAP = sy(9)
    PILL_R = sy(18)
end
