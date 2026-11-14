# Performance analysis and plan (2026-11-14)

Trigger: Yousuf saw low frame rates on the web build even early in a run. Web is our proxy for a low-end phone. All numbers below were measured in the cloud session with the existing tools (`tools/sim/bench_render.gd`, `tools/sim/bench.gd`, the in-game benchmark, and draw-call probes that hide one part of the screen at a time).

## 1. What changed since the last tuning (2026-11-03)

The same 45 s benchmark fight (`Benchmark` v3, desktop xvfb, CPU-rendered):

| | 2026-11-03 (after Phase 1) | 2026-11-14 |
|---|---|---|
| fps | ~87 | **~58** |
| draw calls | 53-61 | **172-178** |
| view CPU | ~0.40 ms | 0.94-0.99 ms |
| HUD CPU | ~0.10 ms | 0.70-0.75 ms |
| sim CPU | 0.7-0.8 ms | 0.69-0.77 ms |

The simulation didn't get slower. **Drawing did:** the UI overhaul ("glossy chunky", HUD top panel + weapon strip + disc buttons), the art pass (glows), cosmetics and the skill-move visuals roughly tripled the draw calls and doubled to septupled the view/HUD CPU time.

## 2. Where the frame goes

### Draw calls (benchmark fight, ~170 total)
| Part | Draw calls |
|---|---|
| HUD top panel (`_bars_layer`: HP/XP bars, level disc, timer, kills, gold) | **~61** |
| HUD owned-upgrades strip (`_strip_layer`) | **~33** |
| HUD live layer (buttons, streak, joystick, coach, toasts) | **~31** |
| Everything in the dish (floor, germs, bullets, gems, effects, player) | ~43 |

So **~125 of ~170 draw calls are the HUD**. The cached layers save CPU (they only re-record when their signature changes) but not draw calls: the GPU still draws every command every frame. Godot's Compatibility renderer merges consecutive commands only when they share a type and texture, and the HUD interleaves text (font atlas), flat shapes, arcs/lines, and textures, so nearly every command is its own call. On WebGL each call is expensive (JavaScript → WebGL → ANGLE validation), so this hurts the web far more than the APK.

Early game (5 germs on screen) is already **~93 draw calls**, which matches "low fps even early".

### CPU (our GDScript)
- Desktop native, benchmark: sim 0.7 + view 0.95 + HUD 0.7 ≈ 2.4 ms.
- **Web (WebAssembly in desktop Chromium): sim 1.18 + view 1.43 + HUD 1.07 ≈ 3.7 ms**, 43.7 fps, p95 29 ms, **slow frames 21.5%**, worst 58 ms.
- Phone web was measured at ~3.5-6× desktop native on 2026-11-03, so today's phone-web estimate is ≈ sim 2.6 + view 4.5 + HUD 4 ≈ **11 ms** of our code alone, before the engine's own work and the 170 draw calls. That is over a 60 fps budget (16.7 ms) once the engine is added.
- Sim breakdown (`bench.gd`, 150+ germs): 0.54 ms/step, of which enemy movement/separation 0.35. Not the problem.
- Early game our CPU is tiny (sim 0.1 + view 0.15 + HUD 0.16 ms), so early-game drops are rendering, not logic.

### Hitches (the "slow frames" and worst-frame spikes)
- **Text drawn at a new font size renders all its letters again** (CPU rasterising, then a texture upload). The kill-streak counter animates its size every kill (`int(_streak_font(n) * pop)`, sizes ~40-140 with a 10 px outline), as do toasts (`int(40 * pop)`) and the streak name. Early runs, when the streak keeps hitting new sizes, pay this repeatedly. (The tutorial prompt had the same problem: fixed in pass B by scaling instead.)

### Resolution (fill rate)
- `window/stretch/mode = canvas_items` draws at the screen's **native** resolution. A phone browser is often 1080×2400 or more (devicePixelRatio ~2.5-3), about **2.8× the pixels** of the 720×1280 design size.
- Measured (software renderer, 1080×1920 window): canvas_items **32.9 fps** → `viewport` stretch (draws at 720×1280, then scales up) **52.9 fps**. The cost is slightly softer text and edges on high-resolution screens.

## 3. Plan, in order of payoff per effort

| # | Change | Expected effect | Effort | Risk |
|---|---|---|---|---|
| 1 | **Fixed-size animated text**: streak counter, streak name, toasts pop with a scale transform at one font size (as the coach already does) | Removes the glyph-rasterising hitches (worst frames, slow %), especially early | Small | Low (looks the same) |
| 2 | **HUD draw-call diet**: render the top panel and the owned strip into textures (a SubViewport per layer, re-rendered only when their signature changes; one draw call each), and group the live layer's draws by kind (all shapes, then all text) | Draw calls ~170 → ~60-70 (back to the tuned level), HUD CPU down | Medium | Low-medium (visual check needed) |
| 3 | **Performance graphics setting**: "Graphics: Sharp / Fast" in Settings switches the window's stretch mode to `viewport` (720×1280 then scaled) at runtime; default **Fast on web** (and offered on Android) | Up to ~1.6× on fill-limited devices (measured 33 → 53 fps at 1080×1920) | Small | Low (softer text; it's an option) |
| 4 | **View CPU**: skip the per-germ elite/telegraph loop when no elites or affixes exist (counters kept by World), cut `draw_arc` segment counts on small rings, cache per-frame colour math; consider packed arrays for `fx` (dictionaries are slow in WebAssembly) | View 0.95 → ~0.5 ms desktop (~2 ms saved on phone web) | Medium | Low |
| 5 | **HUD CPU**: cache shaped text (`TextLine`) for strings that rarely change (timer per second, kills, gold) instead of shaping 50 strings a frame | HUD 0.7 → ~0.3 ms | Small-medium | Low |
| 6 | Web-only: lower `perf` caps on web (effects, damage numbers, particles) via `GameData` when `OS.has_feature("web")` | Fewer sprites in big fights | Small | Gameplay unchanged (visual only) |

Not worth it now: the simulation (0.5 ms/step at 150+ germs, already tuned), threads on web (needs cross-origin isolation headers that itch.io doesn't give everywhere).

**Measure every step** with `tools/sim/bench_render.gd` (desktop) and the web benchmark (export + Chromium, see below), and ask Yousuf for the in-game benchmark line on his phone (tap the build label 5 times) for web and APK before and after.

## 4. How the web numbers were taken
Export the web build with a temporary hook that calls `start_benchmark()` when the URL has `?bench` (not committed), serve it locally, open it in Playwright's Chromium (`--use-angle=swiftshader`, 405×720) and read the `BENCH v3 web` line from the console. Swiftshader renders on the CPU, so compare **our** CPU numbers (sim/view/HUD) and draw calls between runs, not raw fps against a phone.
