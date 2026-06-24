# STONKS — LLM Instructions

## Project Overview
LÖVE 2D trading game. Player starts with $10,000, trades stocks across a simulated week. Built with LÖVE 11.5, targeting iOS 27, macOS, and TV.

## Resolution & Scaling (Balatro-style)
- **Playable area**: 1920×1080 (16:9). Design reference is 1280×720 in `BASE_W, BASE_H`, scaled 1.5× by `sx()/sy()`
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
| `Makefile` | `make love`, `make run`, `make ios`, `make ios-device`, `make ios-clean` |

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

### Critical: Use Regular Xcode, NOT Xcode-beta
SDL2 (prebuilt xcframework in `ios/love-source/platform/xcode/ios/libraries/SDL2.xcframework`) lacks UIScene lifecycle support. Building with the iOS 27 SDK (Xcode-beta) causes `EXC_BREAKPOINT` crash at launch. Always use regular Xcode.app with SDK 26.5.

### Project Setup
- LÖVE 11.5 source in `ios/love-source/`
- Xcode project: `ios/love-source/platform/xcode/love.xcodeproj`
- Target: `love-ios` → builds `STONKS.app`
- Bundle ID: `com.aia.stonks`, product name: `STONKS`
- iOS libraries (xcframeworks) in `ios/love-source/platform/xcode/ios/libraries/`: SDL2, freetype, Lua, ogg, vorbis, theora, modplug
- Info.plist: `ios/love-source/platform/xcode/ios/love-ios.plist` — landscape-only, hidden status bar, arm64, `UILaunchScreen` for full-screen
- pbxproj has `SDKROOT = iphoneos;` and `IPHONEOS_DEPLOYMENT_TARGET = 26.0;` on all love-ios configs (Debug, Release, Distribution)

### Makefile Targets
| Command | SDK | What it does |
|---------|-----|-------------|
| `make ios` | `iphonesimulator26.5` | Build for iOS simulator |
| `make ios-device` | `iphoneos26.5` | Build for physical iPhone (signed) |
| `make ios-setup` | — | Check iOS build dependencies |
| `make ios-clean` | — | Remove `ios/build/` artifacts |

Both `ios` and `ios-device` run `make love` first, copy `wallstreetsbeat.love` into the Xcode project, run `xcodebuild`, then fuse `game.love` into the `.app` bundle.

### Deploying to the Simulator
```bash
make ios
xcrun simctl uninstall booted com.aia.stonks   # optional: remove old version
xcrun simctl install booted ios/build/Debug-iphonesimulator/STONKS.app
xcrun simctl launch booted com.aia.stonks
```

### Deploying to the iPhone (SurgeLove)
```bash
# 1. Build
make ios-device

# 2. Install (phone MUST be unlocked, on home screen, and trusted)
xcrun devicectl device install app --device "SurgeLove" \
  ios/build/Debug-iphoneos/STONKS.app

# 3. Launch
xcrun devicectl device process launch --device "SurgeLove" com.aia.stonks
```

Device details:
- Name: `SurgeLove`
- UDID: `00008150-000111A90E86401C`
- Type: iPhone 17 (iPhone18,3) running iOS 27.0

### Troubleshooting Device Deploy
- `CoreDeviceError 4016`: device is locked or not trusted. Unlock to home screen, re-trust, re-plug USB.
- Check availability: `xcrun devicectl list devices | grep SurgeLove`
- Close Xcode-beta before using CLI — it can hold the device lock.
- App installed but black screen: old SDK 27 build cached. Delete app from device first.

### Simulator Quick Start
```bash
# Create iPhone 17 sim (one-time):
xcrun simctl create "iPhone 17" "com.apple.CoreSimulator.SimDeviceType.iPhone-17"

# Boot and launch:
xcrun simctl boot "iPhone 17"
make ios
xcrun simctl install booted ios/build/Debug-iphonesimulator/STONKS.app
xcrun simctl launch booted com.aia.stonks
```

## Config Access
Config is loaded as global `instrumentConfig` (not `config`). Features accessed via `isFeatureUnlocked(key)`.

## Important Conventions
- Font sizes use `sy()`: `love.graphics.newFont("fonts/default.ttf", sy(20))` — value is in 1280×720 reference, scales to 1080p
- Line widths use `math.max(1, sy(v))` to ensure minimum 1px
- All layout constants computed in `applyScaling()` and stored as globals
- `safeWidth`/`safeHeight` default to 1920×1080 so `sx/sy` work before `recalcSafeArea()`
- The `#` operator on sparse Lua tables is unreliable — use index assignment, not `table.insert(nil)`
uild 