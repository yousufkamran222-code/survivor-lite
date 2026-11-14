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

## 5. Done (2026-11-14): all six steps
Yousuf: "do all six, fast on web and sharp on apk. Make sure we don't lose much quality".

1. **Animated text at fixed sizes** (`HudOverlay._stext`, `TEXT_BASES`): the streak counter, streak name, toasts, evolution name, RUN!, the Nucleus countdown and the tutorial prompt render at one of 9 sizes and are scaled (down) to the exact size, so no new glyph sizes are rasterised mid-run.
2. **Baked HUD panel** (`BakedLayer`, scripts/ui/baked_layer.gd): the top panel, weapon strip, mode readout and boss/nucleus bars render into a SubViewport only when their signature changes (as before, ≤ 20 Hz) and show as one quad. Rendered at the screen's density with matching font oversampling (checked pixel-identical at 1.5×), premultiplied-alpha blend. The DASH/UPGRADE labels stay a normal cached layer.
3. **Settings → Graphics: Sharp / Fast** (`Save.graphics`, `Main._apply_graphics`): Fast = viewport stretch (draws at 720×1280, scales up). Default **Fast on web, Sharp on the APK**. Fast only applies when the window has more pixels than 720×1280 (+15%): on a smaller window (desktop browser) it would draw more, not less (measured: slower). Re-applied on window resize.
4. **View CPU**: the per-germ passes in the top layer and threats use local packed arrays, skip plain chasers and anything >300 px off screen, and the elite health bar/affix passes are merged; `_fill_enemies` reads packed arrays as locals.
5. **HUD text**: covered by 1 and 2 (the panel's text is only laid out when the panel changes).
6. **Web-only visual caps** (`balance.web`, `GameData.apply_web_build`): effects 140 → 110, hit sparks 6 → 4/frame, splats 50 → 40. A test guards that only visual keys can go in it.

### Results
| Measure | Before | After |
|---|---|---|
| Draw calls, benchmark (desktop) | 173 | **90-93** |
| Draw calls, one frame of the same scene | 175 | **75** |
| HUD CPU (desktop) | 0.74 ms | **0.46 ms** |
| HUD CPU (web, WebAssembly) | 1.07-2.38 ms | 0.81-1.15 ms |
| Fast vs Sharp at 1080×1920 (native, software GL) | 32.9 fps | 52.9 fps |

Limits of what the sandbox can show: its browser and xvfb render on the CPU (no GPU), and identical runs vary ±20%, so fps there says little about draw-call savings, which pay off on real phone GPUs and WebGL drivers. **The real check is Yousuf's in-game benchmark line (web and APK) before vs after.**

## 6. Round 2 (2026-11-14, after his phone lines)
His phone (build 07a3632): **APK** `108.9 fps avg 9.18 p95 11.67, slow 3.9% | sim 1.31 view 2.15 hud 1.10 | dc 90` (120 Hz screen; ~4.6 ms of our code, ~4.6 ms engine/GPU). **Web** `43.0 fps avg 23.23 p95 33.33, slow 25.8% | sim 2.92 view 3.41 hud 2.03 | dc 97` (~8.4 ms of our code, ~15 ms browser/WebGL). He wants the APK "as optimized as physically possible" for future features.

- **Benchmark v4**: `Prof` section timers (off except while the benchmark measures) and a second `PROF` line on the results screen, so the phone reports where its time goes (sim.*, view.*, hud.*, main.events).
- Bullets hit-test without building a result array per bullet (`World._bullet_hits`, same cells/order as `query()`): sim.bullets 0.18 → 0.07 ms desktop. The 4 particle batches fill in one pass over `fx`, bullets read packed arrays as locals: view.bullets_dots 0.17 → 0.09 ms. Balance sims byte-identical in all 4 modes (only the timing field differs).
- Desktop profile now (no single hot spot): sim.enemies 0.20, view.top_loop 0.17, hud.buttons 0.12, hud.text 0.12, view.fx_draw 0.10, everything else ≤ 0.09 ms.

**The ceiling in GDScript:** what's left is spread over ~16 sections of ~0.05-0.2 ms. More GDScript tuning might take another ~20-30%. The step change would be **native code (a C++ GDExtension)** for the hot loops (germ movement/separation, the spatial grid, bullets, sprite fills): typically 5-20× faster for that kind of loop. Costs: a C++ toolchain in CI for Android (arm64 + armv7) and, for the web, the dlink export templates; a second implementation to keep in step (the GDScript one stays as the reference for tests and determinism checks). Decision for Yousuf.
