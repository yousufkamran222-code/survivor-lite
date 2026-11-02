# Polish sweep plan (agreed direction 2026-11-02)

Yousuf's brief: make kills and damage more satisfying (he likes the current damage numbers), make the player model nicer and more satisfying to steer and turn, suggest more polish, and make the game **as light as possible on every phone**: least battery drain, and the highest frame rate the screen supports (his phone is 90 Hz; the goal is 60+ everywhere and 90/120 where the screen allows).

**Yousuf's decisions (2026-11-02):** perf first (Phase 0 → 1 → 2 → 3 → 4); crits and kill streaks are **visual only** (no new mechanics, balance untouched); the new player is a **faceless cell**; **generated music** (synthesised loops in `tools/build_assets.py`).

Status: **plan only.** Each phase ends with an APK playtest plus the on-device benchmark from Phase 0. Tick items off here as they land, and log them in `PIPELINE.md`.

---

## What we know today (measured 2026-11-02)

| Area | Finding | Why it matters |
|---|---|---|
| Sim | ~0.7 ms per step at 150+ enemies on a desktop CPU; `enemies` (movement + separation) is ~70% of it | Not the bottleneck on desktop; phones are ~3-5x slower, web (WASM) slower again |
| Draw calls | Fight ~56, main menu ~65 (was 119), shop ~150 (was 277) | OK after the last pass; keep new effects batched |
| HUD text | **29 `draw_string` calls** in `hud_overlay.gd`, all re-laid-out every frame (timer, wave, biomass, owned strip, toasts, perf line) | Text shaping is one of the most expensive per-frame things in Godot 2D, on CPU |
| Damage numbers | Each number is `draw_string` text, capped at 12 | Same cost; also limits how juicy they can be |
| Effects | Every fx is a `Dictionary` (26 `_add_fx` sites); kills spawn 5+ dicts | Heap allocation + slow access in a hot loop |
| World | `query()` builds a new `Array` per call (bullets × enemies per frame); events are dicts (one per hit) | Garbage + allocation every frame |
| Fill rate | Infection/Nucleus draw a **1400-px-wide arc** every frame to darken outside the dish | Huge overdraw for a static frame around the play area |
| Refresh rate | Web: the browser runs at the screen rate (90 Hz on his phone). Android: frame pacing (Swappy) on, `max_fps` 0, but **Godot 4.7 has no Android high-refresh setting** (iOS has one) | The APK may be stuck at 60 Hz on a 90 Hz phone; must check on device |
| Battery | Menus, pause and results redraw at full rate forever | Wasted power while nothing moves much |
| Movement | Velocity is instant, facing snaps to the stick | Feels twitchy/weightless; the cell "teleports" its turn |
| Player art | 3 flat circles (`_draw_player`) | Functional, not characterful |
| Audio | SFX only, **no music** | Biggest missing layer of "feel" |

---

## Phase 0: measure on the phone (small, do first): **built 2026-11-02, awaiting Yousuf's phone numbers**

As built: tap the build label on the main menu 5 times (F9 on desktop). 45 s run: Classic, seed 4242, invincible, bot-driven, run clock starting at 2:50, loadout bolt 4 / orbit 3 / nova 3 / chain 3 / might 2 / multishot 1 (~130-150 enemies, ~15 live effects, ~95 draw calls); 5 s warm-up, then 40 s measured. Result screen with COPY. `Benchmark` (scripts/game/benchmark.gd) holds the stats; bump `Benchmark.VERSION` if the scenario changes. Perf readout v2 (`debug.show_perf`): FPS + 1 s minimum, refresh rate, sim/view/HUD ms, rebuilt 4x a second. Desktop: `xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/sim/bench_render.gd`.

Desktop baseline (xvfb, CPU-rendered, 2 runs): 70.9-74.6 fps, avg 13.4-14.1 ms, p95 15.3-16.7 ms; **our code is only sim 0.7-0.8 + view 0.4 + HUD 0.4 ms**, the rest is software rasterising (the GPU's job on a phone); dc 93-99. Finding: the HUD's owned-upgrades icon strip costs ~60 draw calls once 6 upgrades are owned (dc 41 → ~100).

Original plan:

We can't see the phone, so every perf step needs numbers from it.

1. **In-game benchmark** (hidden: tap the build label on the menu 5 times): plays 40 s of a scripted max-load fight (bot-driven, fixed seed, ~170 enemies, effects on), then shows and logs:
   - avg / p95 / worst frame ms and FPS,
   - sim ms, view (fill + draw) ms, HUD ms,
   - draw calls,
   - the screen refresh rate (`DisplayServer.screen_get_refresh_rate()`) and whether we actually reach it.
   Same scenario on web and APK, so Yousuf can paste one line per build.
2. **Perf readout v2** (`debug.show_perf`): FPS + 1 s minimum, frame ms split (sim / view / HUD), refresh rate. Off by default for release; toggle in Settings (Phase 4).
3. **Desktop render bench** (`tools/sim/bench_render.gd`, xvfb, vsync off): the same scenario, frame time per subsystem, for before/after comparisons in commits.

Done when: Yousuf has posted the benchmark line for web and APK on his phone.

---

## Phase 1: performance and battery (large, top priority)

Targets: **a steady 90 fps on Yousuf's phone at peak load** (11.1 ms/frame), **a steady 60 on the cheap test phone**, menus at a low capped rate. Quote benchmark before/after in every commit.

### 1.1 Refresh rate and frame pacing
- Check on device what the APK runs at (benchmark shows it). If it's stuck at 60 on a 90 Hz screen:
  - try the Swappy modes (`display/window/frame_pacing/android/swappy_mode`),
  - otherwise request the display's top rate from Android (`Surface.setFrameRate` / preferred display mode). That needs the Gradle build, which is M3 work anyway: pull the Gradle switch forward if needed.
- Keep the one-step-per-frame sim with the 1/30 clamp (already frame-rate independent).

### 1.2 Battery
- **Frame cap by screen:** menus, shop, profile, results, pause run at **30 fps** (`Engine.max_fps`); runs at the screen rate. Pause uses `OS.low_processor_usage_mode` (redraws only when something changes).
- **Settings → Frame rate:** Battery saver (30) / Balanced (60) / Max (screen rate). Default Max during runs.

### 1.3 CPU: text
- HUD: draw static labels once; redraw a value only when it changes (cache with `TextLine`, or separate `Label` nodes updated on change). Target: from 29 text layouts per frame to ~0-3.
- **Damage numbers and toasts from a digit/glyph atlas** (generated texture, like the enemy atlas) drawn through `SpriteBatch`: one batched call for all numbers, no text shaping. Also unlocks the juicier numbers in Phase 2.

### 1.4 CPU: allocations and hot loops
- `World.query()` into a reusable buffer (no new `Array` per call); same for `_dead`, gem and bullet loops.
- Effects as packed arrays (struct of arrays, like `World`) instead of dictionaries; particles stay in `SpriteBatch`.
- Hit events: one aggregated "hits this frame" list instead of a dict per hit.
- `SpriteBatch`: try building one vertex/UV/colour array per batch and submitting it in a single call (`RenderingServer.canvas_item_add_triangle_array`) instead of one `draw_texture_rect_region` per sprite; keep it only if it's faster on web and APK (MultiMesh stays banned).
- Enemy update: profile separation (the biggest sim cost) on the phone; options are a larger `SEP_EVERY` at high counts, or skipping off-screen separation.

### 1.5 GPU: fill rate and overdraw
- Replace the 1400-px "darken outside the dish" arc with a few screen-clipped quads, or a pre-baked vignette texture, drawn only where the rim is visible.
- Audit translucent full-screen layers (bg tile + territory texture + glows + menu dim rects); cut what isn't seen.
- Optional **render scale** for very weak phones (render at 0.75 and upscale) in Settings, if the benchmark shows fill-rate limits.

### 1.6 Smaller items
- Physics isn't used: lower `physics_ticks_per_second` (or confirm it's ~free).
- Check `Sfx` player count and web audio latency.

---

## Phase 2: combat feel (medium)

Keep the current damage-number look; make every hit and kill read and feel better. All cheap: sprites through `SpriteBatch`, numbers from the atlas, knobs in `balance.json` `juice`.

1. **Hits:** a short squash-and-recover on the hit enemy (scale from `e_flash`, no extra state), a tiny spark burst at the impact point in the weapon's colour, small directional knockback tuning.
2. **Damage numbers v2:**
   - pop in (scale 1.4 → 1), then rise and fade,
   - rapid hits on the same enemy merge into one growing total instead of a spray,
   - bigger hits are bigger and warmer in colour.
3. **Kills:**
   - a layered death pop (squash, burst ring, particles in the enemy's colour),
   - a short-lived **goo splat** on the floor (fades over ~3 s, capped, one batch),
   - XP gems burst out with a little bounce instead of appearing in place,
   - 2-3 kill sound variants with a rising **pitch ladder** on quick successive kills.
4. **Big moments:**
   - elite kill: ~80 ms hit-stop, gold shower, ring,
   - boss kill: 0.5 s slow-motion,
   - level-up: a quick pulse and chime.
5. **Screen shake v2:** trauma-based (squared falloff) and directional (pushes away from the hit), with a strength setting.
6. **Visual-only streaks (decided):** big hits look bigger (no crit mechanic), and a cosmetic kill-streak counter ("x25") whose sound climbs; no XP bonus, no balance change.

---

## Phase 3: the player cell (medium)

1. **Movement feel** (in `World`, knobs in `juice` / `player`):
   - short acceleration and deceleration (~0.08 s / ~0.10 s) so the cell has weight but still responds instantly,
   - a smoothstep response curve past the dead zone for fine control.
   Top speed unchanged, so balance stays put; sim before/after to confirm.
2. **Turning:** facing rotates smoothly toward the stick (~14 rad/s) instead of snapping; the nucleus leads the turn so direction changes look deliberate.
3. **New look** (generated textures, 2-3 textured draws, cheaper than today's 4 circles):
   - a soft membrane with a rim light, cytoplasm gradient and a nucleus with a couple of organelles,
   - **squash and stretch** along the movement direction (up to ~10% at full speed),
   - an idle "breathing" wobble,
   - small cilia that wave faster with speed,
   - a stretched dash pose plus the existing afterimages,
   - a squish and red flash when hurt.
4. **Joystick visuals:** subtle direction arrow on the knob, cleaner base; options for floating/fixed and sensitivity in Settings.

---

## Phase 4: the rest of the sweep (my suggestions; pick what you want)

1. **Music:**
   - a calm menu loop and a run loop that builds intensity with time or waves (generated in `tools/build_assets.py`, or CC0 tracks listed in `assets/MANIFEST.md`),
   - SFX and music volume, with ducking on big hits.
2. **Settings screen** (menu + pause):
   - music and SFX volume, vibration on/off, screen-shake strength,
   - frame rate (Battery / 60 / Max), show FPS, joystick mode.
   Stored in `Profile.settings` (already a free-form dict, so no save-format change).
3. **UI consistency:**
   - fade/slide screen transitions, press-scale on every button,
   - results screen counts up score and gold,
   - Profile, level-up and chest screens restyled to match the new shop,
   - HUD declutter.
4. **Enemy readability:** spawn pop-in, Lancer dash telegraph line, Spitter charge-up glow, clearer elite aura.
5. **First-run hints** per mode (move, dash, upgrade button, loop to claim, pads), shown once.
6. **Release hygiene:** `show_perf` off by default (toggle in Settings), benchmark hidden.

---

## Order and size

| # | Phase | Size | Why this order |
|---|---|---|---|
| 0 | Measure on the phone | small | Every later perf claim needs a phone number |
| 1 | Performance + battery | large (2-3 sessions) | Top priority; also builds the cheap sprite/number tech Phase 2 uses |
| 2 | Combat feel | medium | Built on the batched effects from Phase 1, so juice doesn't cost frames |
| 3 | Player cell | medium | Independent; can swap with 2 |
| 4 | Sweep | large, à la carte | Pick items by value |

Risks: WebGL and Android behave differently (always verify on the APK); a high refresh rate on Android may require pulling the Gradle build (M3) forward; every new effect must go through `SpriteBatch` or the atlas, or Phase 1's gains get eaten.
