# Refactoring Plan — wallstreetsbeat

> Codebase review conducted 2026-06-28. ~7,500 lines of Lua across 12 main files.

---

## Executive Summary

The codebase is functional and feature-rich, but suffers from **severe code duplication** (especially in stop-order logic), **pervasive global variable usage**, **very long functions**, **per-frame font creation**, and a **stale duplicate** of `ui.lua` in `src/`. There are also inconsistent defaults between `config.lua` and code fallbacks.

---

## Critical Issues

### 1. Stale Duplicate: `src/ui.lua` (~1,230 lines)

`src/ui.lua` is an **older copy** of `ui.lua` that is not loaded by `main.lua`. It contains divergent logic (hardcoded `5` for iterations, `RobotoMono` font, missing `drawGimmicks`/`drawCanvas`). Its continued presence causes confusion and merge drift.

**Action:** Delete `src/ui.lua` and the `src/` directory entirely. Also clean up junk files `zidZmZy2` and `ziSEU3hn` in the project root.

---

### 2. Stop-Order Logic Duplicated Across Files

The buy-stop/sell-stop creation logic (including the new reshuffle-at-1.5× logic) is duplicated in **7 locations** (6 to fix, 1 genuinely different):

| Location | File | Lines | Fix? |
|----------|------|-------|------|
| `createBuyStop()` | `main.lua` | ~1150-1165 | Source — keep |
| `createSellStop()` | `main.lua` | ~1168-1185 | Source — keep |
| `btn-sell-stop` onClick | `ui.lua` | ~744-760 | Call `createSellStop()` |
| `btn-buy-stop` onClick | `ui.lua` | ~805-820 | Call `createBuyStop()` |
| `buy-stop` action | `replay.lua` | ~230-250 | Call `createBuyStop()` |
| `sell-stop` action | `replay.lua` | ~250-270 | Call `createSellStop()` |
| Cross-mode auto-trade | `game.lua` | ~695-735 | Leave (places N stops in a loop) |

**Action:** `main.lua` already defines `createBuyStop()` / `createSellStop()` as globals. The fix is simply to **call them** from `ui.lua` and `replay.lua` instead of inlining:

```lua
-- ui.lua btn-buy-stop onClick:
regButton("btn-buy-stop", ..., function() createBuyStop() end)

-- replay.lua buy-stop action:
elseif action == "buy-stop" then createBuyStop()
```

No new module needed — the functions are already accessible globally. The `game.lua` cross-mode case is genuinely different (places N stops in a loop) and should stay separate.

---

### 3. PL-Stop Logic Duplicated 3×

| Location | File | Lines |
|----------|------|-------|
| `btn-sl` onClick | `ui.lua` | ~760-783 |
| `pl-stop` action | `replay.lua` | ~286-313 |
| `keypressed "tab"` | `main.lua` | ~1075-1082 |

**Action:** Unlike buy/sell stops, there is no existing `createPLStop()` global. Add one to `main.lua` (alongside `createBuyStop`/`createSellStop`) and call it from all 3 locations.

---

### 4. Per-Frame Font Creation (Performance)

`drawTrading` in `ui.lua` calls `love.graphics.newFont()` **20+ times per frame** (lines ~479, 526, 566, 602, 737, 969, 983, 1011, 1026, 1134, 1169, 1191, 1272...). Font creation is expensive.

**Action:** Cache all fonts in `love.load` as globals. **Important:** fonts must be created **after** `recalcSafeArea()` runs, since `sy()` depends on `safeWidth`/`safeHeight`. On window resize, fonts should be re-created.

```lua
-- After recalcSafeArea() in love.load:
fonts = {
    bigBtn   = love.graphics.newFont("fonts/default.ttf", sy(99)),
    small    = love.graphics.newFont("fonts/default.ttf", sy(20)),
    header   = love.graphics.newFont("fonts/default.ttf", sy(28)),
    -- etc.
}
```

Reference `fonts.bigBtn` in draw functions.

---

### 5. `drawTrading` is ~830 Lines

The single worst function in the codebase (`ui.lua` lines 453-1287). It draws the top bar, chart, side panels, betting chart, bottom bar, and tendy overlay all in one function.

**Action:** Split into:

| New Function | Responsibility |
|--------------|----------------|
| `drawTopBar(w, h)` | Balance, P&L, speed indicator |
| `drawChartPanel(w, h)` | Chart area + order lines |
| `drawSidePanels(w, h)` | Buy/Sell/Stop buttons |
| `drawBettingPanel(w, h)` | Betting odds chart |
| `drawBottomBar(w, h)` | THRUST/BAGS/DEGENERACY/CROSSERS |
| `drawTendyOverlay(w, h)` | Tendy drops, heart animation |

Similarly, `drawSettings` (~210 lines) and `drawPins` (~210 lines) should be assessed and split into sub-functions for readability — e.g., `drawSettingsHeader`, `drawSettingsToggles`, `drawSettingsBackButton` / `drawPinGrid`, `drawPinPreview`, `drawPinControls`.

---

## High Priority

### 6. Price Rounding Helper

`math.floor(x * 1000 + 0.5) / 1000` appears **30+ times** across all files.

**Action:** Add to `constants.lua`:

```lua
function round3(x) return math.floor(x * 1000 + 0.5) / 1000 end
```

### 7. Chart Coordinate Setup Duplicated 6×

This block appears in `drawChart`, `updateBall`, `updateToboggan`, `updateSnow`, `drawSnow`, `pickOrderLine`:

```lua
local rewindEnd = math.max(2, #prices - (rewindTicks or 0))
local cs = getChartSpan()
local n = math.min(rewindEnd - 1, cs)
local startIdx = rewindEnd - n + 1
local mn, mx = priceRange()
local step = (w * 0.97) / (cs - 1)
```

**Action:** Extract `getChartCoords(w)` returning a table with all fields.

### 8. Mouse/Touch Handlers Duplicated (~320 lines)

`love.mousepressed` and `love.touchpressed` are near-identical ~70-line blocks. Same for `love.mousereleased`/`love.touchreleased` (~90 lines each).

**Action:** Extract shared handlers. Note: mouse is single-pointer (no `id`), touch supports multi-touch with multiple simultaneous IDs — the shared handler must account for this:

```lua
local function handlePress(gx, gy, id, isTouch) ... end
local function handleRelease(gx, gy, id, isTouch) ... end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    handlePress(x, y, "mouse", false)
end
function love.touchpressed(id, x, y)
    handlePress(x, y, id, true)
end
```

The `isTouch` flag lets the handler distinguish multi-touch tracking (touch) from single-pointer (mouse).

### 9. Rewind Acceleration Formula Duplicated 2×

The `if ht <= 5 then ... elseif ht <= 10 then ... else ... end` block appears twice in `love.update` (`main.lua` ~178-186 and ~196-204).

**Action:** Extract `rewindSpeedMul(holdTime)` function.

### 10. Duplicated SFX Functions

`playBuy`, `playSell`, `playStar`, `playX` in `audio.lua` are identical except for the filename.

**Action:** Replace with a single `playSFX(name)` function. Keep `playBuy`/`playSell`/etc. as **globals** (not `local`) since they're called from `game.lua`, `main.lua`, and `chart.lua`:

```lua
function playSFX(name)
    local src = love.audio.newSource("sounds/" .. name .. ".wav", "static")
    src:setVolume(0.3)
    src:play()
end
function playBuy()  playSFX("buy")  end
function playSell() playSFX("sell") end
function playStar() playSFX("star") end
function playX()    playSFX("x")    end
```

Note: This still creates a new `Source` per call. For further optimization, cache sources in a table and `:clone()` or `:stop()` before replay.

---

## Medium Priority

### 11. Global Variable Traceability (~90+ globals)

The codebase uses globals extensively with no central registry:

| File | Globals Declared |
|------|-----------------|
| `game.lua` | `prices`, `position`, `avgPrice`, `pnl`, `realizedPnl`, `tendies`, `orderLines`, `tradeMarkers`, `particles`, `leverage`, `tradeCount`, `highScores`, `users` (~40 total) |
| `main.lua` | `SCREEN`, `speedMult`, `tickPaused`, `rewindTicks`, `pressedButtonId`, `canvasDragSprite`, `touchId`, `tendyDragActive`, `heartBeatScale` (~30 total) |
| `chart.lua` | `chartX/Y/W/H`, `ballPhase`, `ballX/Y`, `tobogganX/Y`, `cachedXER/XEE`, `snowflakes`, `dragLine` (~20 total) |

**Note:** Globals are the norm in LÖVE games — wrapping everything in `State.position` adds a table lookup per access with little benefit. The real problem is **traceability**: there's no single place to see what state exists. 

**Action:** Add a `state.lua` file that documents (as comments) all shared globals grouped by category. This gives traceability without refactoring every access. Optionally, group related state into tables (`rewind = {ticks, held, holdTime, ...}`) where it makes sense.

### 12. `config.lua` Duplicate `EASY` Key

`EASY` appears twice in `instruments` (lines ~12 and ~14). The second silently overwrites the first.

**Action:** Remove the duplicate or rename one.

### 13. Inconsistent `stopStepPct` Defaults

`config.lua` sets `stopStepPct = 0.001`, but every code fallback uses `0.004`:

```lua
local sp = instrumentConfig.stopStepPct or 0.004  -- 12+ locations
```

**Action:** Change all `or 0.004` fallbacks to `or 0.001` to match `config.lua`. Define `DEFAULT_STOP_STEP_PCT = 0.001` in `constants.lua` and use it everywhere for consistency.

### 14. `theme.lua` Underused

`theme.lua` defines a color palette, but most code hardcodes RGB values instead. The gold color `{0.94, 0.71, 0.16}` appears **20+ times** across `ui.lua`, `slider.lua`, `replay.lua`.

**Action:** Replace all hardcoded colors with `theme.color.*` references.

### 15. `controls/init.lua` is Dead Code

`ui.lua` requires each control directly (`require("controls.button")`, etc. at lines 2-5). The `init.lua` module is never required by any file.

**Action:** Delete `controls/init.lua`.

### 16. `Slider.release` Defined Twice (Dead First Definition)

In `slider.lua`, `Slider.release` is defined at line ~104 (horizontal only: clears `_dragging`) and again at line ~249 (clears `_dragging` AND `_dragVertical`). The second is a superset added when vertical sliders were introduced. The first definition is dead — it's overridden before it's ever used.

**Action:** Remove the first (line ~104) definition.

### 17. `audio.lua` — `initAudio` is an Empty Stub

`initAudio()` is called from `main.lua:41` but the function body is empty. It's a placeholder, not dead code — but it should either be removed or implemented.

**Action:** Remove the empty stub and its call, or implement it if initialization is needed.

---

## Low Priority

### 18. Magic Numbers → Named Constants

| Value | Meaning | Locations |
|-------|---------|------------|
| `0.004` | stopStepPct fallback | 12+ |
| `10000` | starting balance | `game.lua`, `ui.lua` |
| `100` | max shares per trade | `game.lua` 356, 403 |
| `720` | rewind tick cap | `main.lua` (3×) |
| `10` | tendy cap | `main.lua`, `ui.lua` (5×) |
| `0.067` | tick interval | `constants.lua`, `main.lua` |
| `0.88`, `0.06` | chart Y insets | `chart.lua` (10×) |
| `0.97` | chart width factor | `chart.lua` (6×) |
| `0.94, 0.71, 0.16` | gold color | 20+ locations |
| `125` | music BPM fallback | `audio.lua`, `game.lua`, `main.lua` |
| `0.3` | default speed | `main.lua` (3×) |
| `12` | ticks per minute | `game.lua` (3×) |
| `391` | `RW_TOTAL` base | `constants.lua` |

### 19. `drawInfoCol` / `drawInfoColGrad` Near-Identical

`ui.lua` lines ~1199 and ~1218 — the only difference is label color.

**Action:** Merge into one function with a label color parameter.

### 20. Font Auto-Sizing Pattern Duplicated 4×

The `while font:getWidth(text) > maxW and fontSize > min do fontSize = fontSize - 1; font = newFont(...) end` pattern appears in `ui.lua` at lines ~478, ~602, ~1134, ~1169.

**Action:** Extract `fitFont(text, maxW, startSize, minSize)` helper.

### 21. `buy()` / `sell()` Near-Mirror Functions

`game.lua` lines ~350-400 and ~400-450 — ~50 lines each with similar structure. However, they have genuinely different P&L math (buy closes shorts and goes long; sell closes longs and goes short), different fill prices (`currentAsk` vs `currentBid`), and different marker moods (`"cold"` vs `"warm"`).

**Action:** Extract shared helpers for the duplicated parts (e.g., `addTradeMarker(type, price, mood)`, `computePct(prevAvg, fillPrice)`) rather than forcing a single `trade(direction)` function. The validation and P&L branches are different enough that merging would add complexity, not reduce it.

### 22. `closePosition` / `closeAllPositions` Nearly Identical

`game.lua` — `closeAllPositions(label)` is called from `ui.lua:1302` with `"MARKET CLOSED"` but the `label` param is never used inside the function. The two functions differ in two ways: `closeAllPositions` adds a result marker with P&L (while `closePosition` does not), and `closePosition` calls `rewardRhythmTap()` (while `closeAllPositions` does not).

**Action:** Merge into one function with optional flags (`addMarker`, `rewardRhythm`), or have `closePosition` call `closeAllPositions` internally and add the rhythm tap afterward.

### 23. Duplicated Price Generation Formula

The "predictable" wave formula (`calmAmp`, `wave1`, `wave2`, `noise`, `bigT`, `ampVar`) appears in both `tick()` and `skipTo1555()` in `game.lua`.

**Action:** Extract `predictablePrice(predIndex)` function.

### 24. No Error Handling in CSV Parsing

`data.lua` `initData` — `tonumber` on CSV fields can silently produce `nil`.

**Action:** Add validation and error messages.

### 25. No Tests

No test files exist anywhere.

**Action:** Add a `tests/` directory with busted or luaunit tests for trading logic, MA calculations, and price rounding.

---

## Functions Over 50 Lines

| Function | File | Approx Lines |
|----------|------|-------------|
| `drawTrading` | `ui.lua` | **~830** |
| `drawChart` | `chart.lua` | ~250 |
| `updateBall` | `chart.lua` | ~200 |
| `drawSettings` | `ui.lua` | ~210 |
| `drawPins` | `ui.lua` | ~210 |
| `love.load` | `main.lua` | ~140 |
| `tick` | `game.lua` | ~130 |
| `love.update` | `main.lua` | ~120 |
| `drawHighscore` | `ui.lua` | ~115 |
| `Replay.executeAction` | `replay.lua` | ~100 |
| `Replay.draw` | `replay.lua` | ~100 |
| `love.mousereleased` | `main.lua` | ~90 |
| `love.touchreleased` | `main.lua` | ~90 |
| `Button.draw` | `controls/button.lua` | ~80 |
| `Slider.drawVertical` | `controls/slider.lua` | ~80 |
| `love.mousepressed` | `main.lua` | ~70 |
| `love.touchpressed` | `main.lua` | ~70 |

---

## Architectural Concerns

1. **Tight coupling across modules**: `game.lua` calls `goToScreen()` (routing) and `playBuy()` (audio). `ui.lua` onClick handlers mutate `position`, `realizedPnl`, `tendies` directly. `game.lua` ↔ `replay.lua` ↔ `ui.lua` all call each other's functions. Works because everything is global, but changes in one file can silently break another. (Note: LÖVE games don't follow MVC — the framework's `love.load/update/draw` pattern is the norm. The real issue is coupling, not missing MVC.)
2. **Mixed concerns in `chart.lua`**: Chart rendering + ball physics + snow system + input handling (order-line dragging) all in one file. Should be split into `chart.lua`, `ball.lua`, `snow.lua`, `chart_input.lua`.
3. **`drawCanvas` duplicates `drawWelcome`'s state reset** (`ui.lua` ~2715-2745): 30 lines of state reset copied from `drawWelcome` (line 213). `drawWelcome` is no longer called by `love.draw` (CANVAS screen uses `drawCanvas` instead), but it's the source of the duplicated logic. Should be extracted into a shared `resetGameState()` function.

---

## Priority Order

| # | Task | Impact | Effort |
|---|------|--------|--------|
| 1 | Delete `src/ui.lua` | Removes confusion | Trivial |
| 2 | Call existing `createBuyStop()`/`createSellStop()` from `ui.lua` + `replay.lua`; add `createPLStop()` | Eliminates 6× duplication | Low |
| 3 | Cache fonts in `love.load` | Performance | Low |
| 4 | Add `round3()` helper | Eliminates 30+ duplications | Trivial |
| 5 | Add `getChartCoords()` helper | Eliminates 6× duplication | Low |
| 6 | Unify mouse/touch handlers | Eliminates ~320 lines | Medium |
| 7 | Split `drawTrading` | Readability | Medium |
| 8 | Extract `rewindSpeedMul()` | Eliminates 2× duplication | Trivial |
| 9 | Fix `config.lua` duplicate `EASY` | Bug fix | Trivial |
| 10 | Use `theme.color.*` | Consistency | Medium |
| 11 | Document globals in `state.lua` | Traceability | Low |
| 12 | Split `chart.lua` into modules | Architecture | High |
| 13 | Add tests | Reliability | High |
| 14 | Remove dead code (`controls/init.lua`, first `Slider.release`, empty `initAudio`) | Cleanup | Trivial |
| 16 | Extract `fitFont()` helper | Eliminates 4× duplication | Low |
| 17 | Merge `drawInfoCol`/`drawInfoColGrad` | Eliminates near-duplicate | Trivial |
| 18 | Add CSV validation in `data.lua` | Robustness | Low |
| 19 | Split `drawSettings` (~210 lines) and `drawPins` (~210 lines) into sub-functions | Readability | Medium |
| 20 | Extract shared `buy()`/`sell()` helpers | Reduces duplication | Medium |
| 21 | Merge `closePosition`/`closeAllPositions` | Eliminates duplication | Low |
| 22 | Extract `predictablePrice()` formula | Eliminates 2× duplication | Low |
| 23 | Replace magic numbers with named constants | Maintainability | Medium |
| 24 | Align `stopStepPct` fallbacks with config | Consistency | Trivial |
