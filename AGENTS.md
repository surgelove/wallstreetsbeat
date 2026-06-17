# STONKS — LLM Instructions

## Project Overview
LÖVE 2D trading game. Player starts with $10,000, trades stocks across a simulated week. Built with LÖVE 11.5, targeting iOS 27, macOS, and TV.

## Resolution & Scaling (Balatro-style)
- **Internal resolution**: 1920×1080 (16:9), defined in `constants.lua` as `BASE_W, BASE_H`
- **Window**: configurable via `conf.lua` (currently 1920×1080)
- **Scaling**: `safeScale = min(screenW / safeWidth, screenH / safeHeight)` — fills screen height, side bars show background
- **`sx(v)` / `sy(v)`**: convert design pixels to actual. All layout values use these. Change `BASE_W/BASE_H` to switch resolution.
- **`applyScaling()`**: computes layout constants (PANEL_W, etc.). Called by `recalcLayout()`.
- **Portrait→landscape swap**: `recalcSafeArea` swaps w/h if h > w.
- **Background**: draws full-screen via `Background.draw(getWidth(), getHeight())` before the scale transform. Clear color set to `0.08, 0.08, 0.14` to blend any uncovered edges.
- **Playable area**: centered 16:9 box. `love.graphics.translate(safeLeft, safeTop)` then `love.graphics.scale(safeScale, safeScale)`.

## Key Files
| File | Purpose |
|------|---------|
| `main.lua` | Entry point, screen routing, LOVE callbacks, touch/mouse |
| `constants.lua` | `BASE_W/H`, `sx()/sy()`, layout vars, trading constants |
| `config.lua` | Instruments, groups, presidents, events, milestones, features |
| `chart.lua` | Chart rendering, safe area calc, SMA/EMA/TEMA, grid lines |
| `ui.lua` | All screen drawing functions, buttons, `regButton()`, settings |
| `game.lua` | Trading logic, tick(), position management, `isFeatureUnlocked()` |
| `data.lua` | CSV loading, `instrumentConfig` global, data initialization |
| `audio.lua` | Sound effects |
| `conf.lua` | LÖVE window config |
| `controls/background.lua` | Velvet animated background (Balatro-style) |
| `controls/button.lua` | Button system |
| `controls/slider.lua` | Speed slider |
| `Makefile` | `make love`, `make ios`, `make ios-setup`, `make run` |

## Screens
`SCREENS` table in `main.lua`: WELCOME → PRESIDENT → SELECTOR → PINS / TRADING → EOD → RECAP. Also: HIGHSCORE, HIGHSCORELIST, INSTRUCTIONS, SETTINGS.

Screen drawing functions follow the pattern: `drawXxx(w, h)` in `ui.lua`. Click handlers: `handleXxxClick(mx, my)`.

Each screen must clear `Buttons = {}` at the start of its draw function to avoid stale button hits.

## Chart System
- **MAs**: TEMA 15-min (period 180, purple) and EMA 15-min (period 180, gold)
- **TEMA**: Triple EMA = `3*EMA1 - 3*EMA2 + EMA3`. Uses dense array extraction for nested EMAs.
- **EMA**: Uses `result[i] = value` (index assignment), not `table.insert()`, to preserve indices.
- **Grid labels**: toggle between `+1.23%` and `32.40` via `chartDisplay` global ("pct"/"price")
- **Scissor**: must multiply chart coords by `safeScale` since scissor uses screen space
- **Settings screen**: toggles `chartDisplay` via UI buttons (not config file)

## Button System
- `regButton(id, x, y, w, h, text, subText, onClick)` — creates and registers in global `Buttons` table
- `Button.hit(btn, mx, my)` — hit test
- `Button.printfWithHalo(text, x, y, w, align, r, g, b)` — styled text
- Buttons persist across frames. Clear `Buttons = {}` when switching screens.

## Touch/Mouse Coordinates
Screen coords → game coords: `(x - safeLeft) / safeScale`, `(y - safeTop) / safeScale`

## iOS Build Pipeline
- LÖVE 11.5 source in `ios/love-source/`
- iOS libraries (xcframeworks) in `ios/love-source/platform/xcode/ios/libraries/`: SDL2, freetype, Lua, ogg, vorbis, theora, modplug
- App is STONKS-branded: bundle ID `com.aia.stonks`, product name `STONKS`
- Build command: `xcodebuild -project love.xcodeproj -target love-ios -sdk iphonesimulator26.5 CODE_SIGNING_ALLOWED=NO ASSETCATALOG_COMPILER_APPICON_NAME=""`
- `game.love` must be copied to both `ios/game.love` (for Xcode resource) and `build/Debug-iphonesimulator/STONKS.app/game.love` (post-build fuse)
- Info.plist modified: landscape-only, hidden status bar, arm64, `UILaunchScreen` for full-screen
- Deployment target: 26.4 (matching available simulator runtime)
- iPhone 17 simulator: "iPhone 17" with iOS 27.0 runtime

## Config Access
Config is loaded as global `instrumentConfig` (not `config`). Features accessed via `isFeatureUnlocked(key)`.

## Important Conventions
- Font sizes use `sy()`: `love.graphics.newFont("fonts/default.ttf", sy(13))`
- Line widths use `math.max(1, sy(v))` to ensure minimum 1px
- All layout constants computed in `applyScaling()` and stored as globals
- `safeWidth`/`safeHeight` default to `BASE_W/BASE_H` so `sx/sy` work before `recalcSafeArea()`
- The `#` operator on sparse Lua tables is unreliable — use index assignment, not `table.insert(nil)`
