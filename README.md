# 🚀 STONKS

A LÖVE 2D trading game — start with $10,000, trade stocks across a simulated week. Balatro-style velvet background, real-time charts, TEMA/EMA indicators, and meme milestones.

<p align="center">
  <img src="stonks.png" alt="STONKS" width="400"/>
</p>

## 🎮 Gameplay

- **$10,000** starting balance
- Trade across **5 trading days** (Monday–Friday)
- **Multiple instruments**: Bitcoin-linked (BITU/SBIT), miners (DUST/GDX/NUGT), gold (GLD), oil (SCO/UCO), S&P 500 (SPXL/SPXS), and EASY mode
- **Order types**: Buy, Sell, Buy Stop, Sell Stop, Stop Loss (unlock as your balance grows)
- **Random events** and a **presidential pick** add chaos
- **Meme milestones** pop up as your balance hits thresholds
- **High scores** persist across sessions

## 📐 Resolution & Scaling

**1080p internal resolution (1920×1080, 16:9)** — like Balatro, the game renders at a fixed resolution and scales uniformly to fit any screen.

| Screen | Behavior |
|--------|----------|
| **Mac/PC** | Window defaults to 1920×1080, resizable |
| **iPhone** | Scaled to fill height, velvet background fills side bars + Dynamic Island |
| **TV (4K)** | Perfect 2× integer scale at 3840×2160 |
| **Any display** | Uniform scale, centered, background bleeds to edges |

All pixel values derive from `BASE_W, BASE_H = 1920, 1080` via `sx()`/`sy()` helpers. Change those two values and the entire UI scales.

## 🏗 Architecture

```
main.lua          — Entry point, screen routing, LOVE callbacks
constants.lua     — BASE_W/H, sx()/sy(), layout constants, trading values
config.lua        — Instruments, groups, presidents, events, milestones
chart.lua         — Chart rendering, SMA/EMA/TEMA, safe area, grid
ui.lua            — All screen UIs, button system, settings
game.lua          — Trading logic, tick(), positions, feature unlocking
data.lua          — CSV data loading, instrumentConfig
audio.lua         — Sound effects
conf.lua          — LÖVE window configuration
controls/
  background.lua  — Velvet animated background (Balatro-style)
  button.lua      — Button registry + hit testing
  slider.lua      — Speed slider control
  theme.lua       — Color themes
  init.lua        — Controls module loader
```

### Screen Flow

```
WELCOME → PRESIDENT → SELECTOR → PINS / TRADING → EOD → RECAP
                                            ↕
                                     HIGHSCORE, HIGHSCORELIST,
                                     INSTRUCTIONS, SETTINGS
```

Each screen has a `drawXxx(w, h)` function and a `handleXxxClick(mx, my)` handler. Screens clear the global `Buttons` table on entry to prevent stale button hits.

### Chart Indicators

| Indicator | Type | Period | Color |
|-----------|------|--------|-------|
| Fast MA | **TEMA** (Triple EMA) | 180 ticks (~15 min) | Purple |
| Medium MA | **EMA** | 180 ticks (~15 min) | Gold |
| Price line | Raw price | — | Light gray |

Grid labels toggle between `+1.23%` and `32.40` via the **Settings** screen.

## 🛠 Build & Run

### Prerequisites

- [LÖVE 11.5](https://love2d.org/) (`brew install love`)
- Xcode 26.5+ (for iOS)

### Desktop

```bash
make love      # Package STONKS.love
make run       # Build + launch in LÖVE
make clean     # Remove build artifacts
```

### iOS

```bash
make ios-setup # Clone LÖVE 11.5 + download iOS libraries (first time)
make ios       # Build .love, build iOS app, install on simulator, launch
```

The iOS app is branded as **STONKS** (bundle ID `com.aia.stonks`), landscape-only, with a full-screen velvet background extending under the Dynamic Island.

## 📁 Data Format

CSV files in `data/` with columns: `time, bid, ask`. Files are named by date (e.g., `2026-01-02.csv`). The game can also run in random-walk mode.

## ⚙️ Configuration

All game tuning is in `config.lua`:

- **Instruments**: trading parameters, group assignments, price ranges
- **Features**: unlock thresholds (e.g., `stopLossButton = 100` unlocks at $100 profit)
- **Events**: random news headlines
- **Presidents**: character selection with portraits
- **Milestones**: meme popups at profit thresholds

Config is accessed via the global `instrumentConfig` (not `config`).

## 🎨 Design Notes

- **Pixel filter**: `"nearest"` for crisp scaling
- **Fonts**: `default.ttf`, `RobotoMono-VariableFont_wght.ttf`, `Inter-Regular.ttf`, `pixel.ttf`
- **All sizes use `sx()`/`sy()`**: font sizes, line widths, button dimensions, spacing — everything scales from `BASE_W/BASE_H`
- **Line widths**: `math.max(1, sy(v))` ensures minimum 1px
- **EMA arrays**: use `result[i] = value` (index assignment), never `table.insert(nil)` — Lua's `#` on sparse tables is undefined
- **Scissor**: chart scissor coords multiply by `safeScale` since scissor uses screen space, not the scaled coordinate system

## 📱 iOS Technical Notes

- LÖVE 11.5 source + prebuilt xcframeworks (SDL2, freetype, Lua, ogg, vorbis, theora, modplug)
- Deployment target: iOS 26.4
- Tested on iPhone 17 simulator (iOS 27.0)
- `UILaunchScreen` in Info.plist for native full-screen (no compatibility letterboxing)
- Build bypasses asset catalog (`ASSETCATALOG_COMPILER_APPICON_NAME=""`)
