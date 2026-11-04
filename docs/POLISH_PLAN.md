# Polish sweep plan (agreed direction 2026-11-02)

Yousuf's brief: make kills and damage more satisfying (he likes the current damage numbers), make the player model nicer and more satisfying to steer and turn, suggest more polish, and make the game **as light as possible on every phone**: least battery drain, and the highest frame rate the screen supports (his phone is 90 Hz; the goal is 60+ everywhere and 90/120 where the screen allows).

**Yousuf's decisions (2026-11-02):** perf first (Phase 0 → 1 → 2 → 3 → 4); crits and kill streaks are **visual only** (no new mechanics, balance untouched); the new player is a **faceless cell**; **generated music** (synthesised loops in `tools/build_assets.py`).

Status: **phases 0-4 built (2026-11-03)**; HUD declutter done 2026-11-04 (the dot strip became a BUILD button + overlay), plus kill/number juice v3. Each phase ends with an APK playtest plus the on-device benchmark from Phase 0. Tick items off here as they land, and log them in `PIPELINE.md`.

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

**Phone baseline (Phase 0, build 4316537):**
- APK: `120Hz | 87.7 fps avg 11.40 p95 13.89 worst 24.4 ms, slow 18.6% | sim 1.79 view 1.21 hud 1.94 ms | dc 104`. Not capped at 60: the screen is 120 Hz and the APK already averages 88, so no Gradle work is needed for high refresh.
- Web: `?Hz | 48.1 fps avg 20.80 p95 28.76 worst 115.0 ms, slow 10.9% | sim 2.45 view 1.91 hud 2.45 ms | dc 95`.
- The HUD cost more than the whole simulation; ~6.5 ms of the APK frame is engine/GPU (draw calls). Target: 120 fps (8.3 ms).

**Chunk 1 (2026-11-03), desktop bench before → after:** 71-75 → 87 fps, HUD 0.40 → 0.10-0.12 ms, draw calls 93-104 → 53-55.
- HUD split into cached layers: the owned-upgrade strip + button labels redraw only on change; the top bars/readouts redraw on change at most 20x a second; only animated parts draw every frame.
- `IconAtlas`: every upgrade icon (and evolved weapon icon) baked once at startup into one texture via a one-shot SubViewport; the HUD strip draws same-texture quads (one batch) with the level numbers in a second batch.
- Battery: `perf.menu_max_fps` 60 for menus, shop, results and pickers; `perf.pause_max_fps` 30; runs uncapped.
- Phone after chunk 1 (build 110f7d6): **APK 117.4 fps on 120 Hz (was 87.7), p95 10.0 ms, slow 1.4% (was 18.6%), HUD 0.42 ms (was 1.94), dc 52 (was 104)**; web 56.0 fps (was 48.1), slow 1.7% (was 10.9%).

**Chunk 2 (2026-11-03): sim and view.**
- Profiling showed **enemy separation was ~70% of the sim** (bench.gd: 1.14 → 0.33 ms/step with it switched off). Separation is now **time-based** (`World.SEP_PASSES_PER_S` = 30 passes/s, each pass 1/3 of the enemies): identical at the sims' 30 steps/s (Classic and Nucleus sims byte-identical before/after), 2x less work per frame at 60 fps and 4x less at 120. The 9-cell search is now one flat loop (faster than nested `range`). bench.gd at 150+ enemies: **1.14 → 0.63 ms/step**, no balance change.
- Tried and **rejected**: searching only the 2x2 nearest cells (another ~20%), because crowds clumped and Classic bot wins jumped 33% → 54%.
- View profile: the top layer (player, effects, damage numbers) was about half. **Damage numbers now come from `DigitAtlas`** (digits baked once at startup, white with a dark outline), drawn last in one batch; same look.
- The benchmark's "view" now includes the batched sprite layers' draw time (it was missing): **`Benchmark.VERSION` 2**, don't compare v1 and v2 view numbers.
- The desktop is CPU-rasterised, so it can't show GPU-side gains; phone numbers decide.
- Still open: effects as packed arrays instead of dictionaries, the grid's per-cell Array allocations, the dish-darkening ring (Infection/Nucleus only).

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

**Phone after Phase 1 chunk 2 (a6de2fe):** APK `114.1 fps avg 8.77 p95 10.61, slow 0.2% | sim 1.50 view 1.83 hud 0.62 | dc 61` (busier run: fx 28); web 58.2 fps, p95 19.05. Phase 1 declared good enough for now (Yousuf, 2026-11-03).

**Built 2026-11-03 (all knobs in `balance.json` `juice`, presentation only):**
- Hit pulse: enemies pop up to +22% size while their hit flash lasts (`hit_pulse`); 2 sparks per hit, at most 6 hits' worth per frame (`hit_sparks_per_frame`).
- Damage numbers v2 (still the digit atlas): pop-in (`num_pop`), hits on the same enemy within `num_merge_s` merge into one growing total, bigger and gold by share of the enemy's max HP (`num_big_scale`). World's `hit` event now carries `uid` and `frac` (presentation data only).
- Kills: batched kill ring (new `ShapeTextures.ring`), goo splats on the floor (new `ShapeTextures.splat`, ring buffer of `splat_max` 50, fade over `splat_s` 3 s, under everything), alternating `kill`/`kill2` sounds whose pitch climbs with the streak (`kill_pitch_step`, `kill_pitch_max`).
- Big moments: elite kill 0.08 s hit-stop + gold shower; boss kill 0.8 s slow-motion at 30% (`slowmo_boss_s`, `slowmo_scale`).
- Shake: smooth layered sines instead of a new random offset each frame (no buzz at 120 fps), `shake_mult` for the future setting.
- Cosmetic streak: "x25" top-right from `streak_show` (10) kills chained within `streak_window_s` (1.2 s); gold from 50; chime at 25/50/100/200/400. **Replaced 2026-11-04** by the World-side kill streak (`balance.streak`, SPEC core loop step 8).
- Cost (desktop, alternating runs): view +0.15 ms, HUD +0.08 ms, ~3% fps under software rendering. Balance sims unchanged (presentation only).
- Asset tool: new sounds must be appended at the **end** of `build_sfx()` (the noise generator is shared; inserting earlier changes every later sound).

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

**Built 2026-11-03** (Yousuf on Phase 2: "feels good"):
- **Movement weight** (World): velocity eases toward the stick, full speed in `player.accel_s` 0.07 s, stop in `decel_s` 0.09 s; a dash exits still moving its way. **Stick response** (Main): speed is rescaled from 0 at the dead-zone edge (no jump) with `juice.stick_curve` 1.25 for fine control.
- Sims, Classic × 8 runs: seeds 600/700/800 before 25/38/38% → after 63/38/63%; fresh seeds 900/1000/1100 easing off 38/38/38% vs on 25/50/25%. Six seeds together ≈ 36% vs 44%, inside the noise of 8-run samples: **no real balance shift**.
- **Look** (WorldView, visual only): generated `ShapeTextures.player_cell` (glow, bright membrane rim, organelles; radial shading so it can rotate), squash/stretch along the movement (`cell_squash` 0.1, `dash_stretch` 0.3), idle breathing (`cell_breathe`), `cilia` 12 hairs waving faster with speed, squish on hurt, glossy nucleus that swings toward the aim at `turn_rate` 14 rad/s (World's aim still snaps).
- **Joystick:** direction marker on the base rim past the dead zone.

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

**Update 2026-11-03: the generated music was replaced by CC0 tracks (Juhani Junkala, "5 Chiptunes (Action)"; D-015), and the runtime audio buses were removed (silent on web). The music notes below are historical.**

**Music + Settings built 2026-11-03** (Yousuf on Phase 3: "feels good"; asked for music and settings first):
- **Music** (`tools/build_assets.py` `build_music()`, own RNG so the sound effects never change; `assets/processed/music/`, imported with loop on, QOA-compressed): `menu` (90 BPM, 21 s, Am-F-C-G pad + slow arpeggio + bubble blips) and the run in two synced 16 s layers at 120 BPM: `run_base` (pad, bass, arpeggio) always on, `run_drive` (kick, hats, snare, bright arpeggio) faded in by `Sfx.set_intensity()` from Main: run clock in timed modes, waves in Nucleus (low in breathers), full for bosses and Free Mode. Checked numerically: even loudness per bar, no clipping, silent loop seams.
- **Audio buses** "Music" and "SFX" (created at startup); music ducks under boss/bomb/death/evolve sounds.
- **Settings screen** (`SettingsScreen`, from the menu's new SETTINGS tile and from pause): Music and Effects volume sliders, Vibration on/off (all vibration goes through `Sfx.vibrate`), Screen shake Off/Low/Normal/High (multiplies `juice.shake_mult`), Frame rate Battery 30 / 60 / Max (menus still at most 60, pause 30), Show FPS. Stored in `profile.settings` (free-form, no format change); an old "muted" flag becomes both volumes at 0.

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


### Phase 4, UI round (built 2026-11-03; Yousuf on music: "fine for now")
- **Transitions:** overlays fade in with the column rising into place (`UiKit.reveal`); screens rebuilt in place (menu, shop, profile, settings) cross-fade (`UiKit.fade_in`); every button squashes slightly while held (`UiKit.press_feedback`).
- **Profile** (`ProfileScreen`): lifetime stat tiles, a best-run card per mode (icon, best time, score/kills/runs), achievements done-first with rounded progress bars and an overall completion bar.
- **Level-up:** "LEVEL n" header with a picks chip; cards with a glowing icon, accent stripe, NEW/LV chip, the shop's tier bar with the next level pulsing, and an evolution chip.
- **Chest:** reward cards that spin and land with a particle burst; evolutions get a gold card and an "EVOLUTION!" banner.
- **Results:** stats card; score and gold count up with rising ticks (`UiKit.count_up`); NEW BEST stamps in; new achievements pop in one by one; the double-gold ad counts gold up from the old total; PLAY AGAIN is the primary (gold) button.
- **Fix (Yousuf):** the Profile only scrolled from the gaps between boxes. `UiKit.panel` now uses `MOUSE_FILTER_PASS` (PanelContainer defaults to STOP), so drags over tiles, cards and achievements reach the `DragScroll`.

### Phase 4, telegraphs and hints (built 2026-11-03)
- **Telegraphs** (WorldView, visual only, timings from World): Lancer wind-up draws its exact dash lane (diameter-wide, filling with a line and an arrowhead); a Spitter's mouth glows with a closing ring for the last `spit_telegraph_s` (0.5 s) before a shot, and stays lit while ready; the Mother Cell shows a closing ring for `boss_telegraph_s` (0.7 s) before a burst.
- **First-run hints** (`data/hints.json`, validated; a test checks every event hint names an event World emits): shared (move, dash, first level-up → UPGRADE, first elite → chest) plus per mode (Infection claim + erosion, Swarm allies, Nucleus defend/build/upgrade). Triggered by run time (`at`) or a World event; one banner at a time above the buttons (higher when the tower bar is up); each shown once ever (`Save.hints_seen` in `profile.settings`); Settings → "Show tips again". The old Infection/Swarm start toasts were replaced; none during the benchmark.
- Phase 4 list is now done except the optional items (HUD declutter).

### Kill and damage-number juice v3; BUILD overlay (2026-11-04)
Yousuf: kills "aren't very satisfying"; the numbers are nice but could be better; the owned-upgrade dot strip was unreadable. Presentation only (sims unaffected); knobs in `balance.json` `juice`.
- **Damage numbers v3:** each number hops out sideways and falls under gravity (`num_rise` 260, `num_spread` 70, `num_grav` 900, `num_life_s` 0.7) instead of a straight rise; a springy pop (big, slight squash, settle; `num_pop` 0.7) that replays on every merge with a small hop; colour by hit size white → yellow → orange → hot pink (`num_big_scale` 0.7); the **killing blow** turns hot pink, pops again, grows (`num_kill_scale` 0.3) and lingers; numbers shrink away at the end. World's `kill` event now carries `uid` (presentation data).
- **Kills:** a white flash where the germ died (`kill_flash_scale`), 8 particles (was 5) that burst fast and slow down (`kill_burst_drag` 7), two of them white sparks; **multi-kill punch**: 6+ kills in one frame give a shake (`multikill_shake` 0.6 per kill, max 7) and a white ring sized by the count.
- **BUILD overlay** (`BuildScreen`): the HUD's left-edge dot strip is replaced by a BUILD button (top left, below the boss/Nucleus bars: weapon icons + "+N" upgrades). Tap it (or B) to pause and see every weapon and upgrade: icon, name, LV n / max, tier bar, what it does, and its evolution path (evolved / ready / needs X); RESUME or Back to continue. First-time hint on the first pick.
- Cost (xvfb `bench_render.gd`, 2 runs each): before 75.5-76.3 fps, view 0.74-0.77 ms, dc 63-70; after 75.1-79.0 fps, view 0.76-0.85 ms, dc 67-68 (noise).

### Satisfaction round 1: camera + XP loop (2026-11-04)
From the "look and feel" idea list (sets of two; Yousuf picked these first). Knobs in `balance.json` `juice` unless noted.
- **Camera** (WorldView): look-ahead `cam_lead_s` 0.35 s of velocity (~60 px at full speed), eased at `cam_lead_rate`; slow zoom-out to 0.92 between `cam_crowd_from` 60 and +`cam_crowd_span` 100 hostiles; zoom punches (`cam_punch_*`: level 0.035, streak milestone 0.03, elite 0.03, evolution 0.06, boss 0.07) decaying at `cam_punch_decay`. Culling, the background and the HUD's off-screen arrows use the zoom.
- **XP loop:** gems hop out of kills with a squash on landing (`gem_hop_s` 0.28, `gem_hop_h` 18; World keeps `g_born` per gem for this); the pickup sound climbs while gems stream in (`pickup_pitch_step` 0.03 up to +0.6, chain gap `pickup_chain_s` 0.35); XP bar 16 → 22 px with a highlight, a bright tip, a glow that pulses faster from 75% full, and a flash + sweep on fill (drawn every frame; the bar body stays in the cached layer).
- **Level-up shockwave** (gameplay, `balance.xp.levelup_wave` radius 220, knock 420, no damage; closer germs pushed harder; knock resist applies) with a bright ring. Bot sims in PIPELINE.

### Satisfaction round 2: danger readability + weapons (2026-11-04)
Yousuf picked set 4 (minus the HP ring) and set 5 (minus muzzle flashes, replaced by per-weapon cell animations). Presentation only; knobs in `juice`.
- **Low HP** (below `lowhp_frac` 0.3): a soft red vignette on the four screen edges (four baked gradient strips, `lowhp_width` 150, `lowhp_alpha` 0.3; no full-screen fill) and a heartbeat ("lub-dub", new generated `heartbeat` sound appended at the end of `build_sfx()`) that speeds from `heartbeat_slow_s` 1.0 to `heartbeat_fast_s` 0.55 as HP drops; each beat pulses the vignette.
- **Hit direction:** a faint red bloom at the screen edge on the side the hit came from (`hurt_dir_alpha` 0.22, `hurt_dir_s` 0.45; hits from about the same side refresh one bloom, at most 3). World's `hurt` event now carries `from`.
- **Weapon animations on the cell** (one per owned weapon, each in its own zone so they stack, 1-3 cheap draws each): Fever Pulse = warm glow behind the cell that swells as it charges and flares on the pulse; Antibodies = three thin arcs turning outside the cilia; Pulse Bolt = the nucleus charges and flashes on each shot; Nerve Spark = a tiny zig-zag crackle on the rim (faster when evolved). Evolution colours via `_wcolor`.
- **Bigger evolutions:** Cytotoxic Storm bolts get a soft glow, a comet tail and a white core (same sprite batch); Immune Wall orbs a wide halo and white core; Fever Spike a thicker ring plus an inner white ring; Neural Storm a wide glow + white-hot core on the arcs.
- **Evolution moment:** queued while the chest is open and played once you're back in play: `evolution_freeze_s` 0.35 freeze, white flash, two rings, a 24-spark burst in the evolution colour, a zoom punch and shake, the name as a banner ("IMMUNE WALL!" / "EVOLVED"), the evolve chime and a buzz.
- Cost (xvfb `bench_render.gd`, all 4 weapons): after 68-85 fps, view 0.69-0.87 ms; previous commit 75-81 fps, view 0.66-0.76 ms (noise).
- **Evolution moment v2 (2026-11-04, Yousuf: "not big enough, freeze too short, didn't feel like a moment"):** a frozen sequence of `evolution_seq_s` 1.9 s (world not stepped, input ignored): charge for `evolution_burst_s` 0.75 s (field dims, camera pushes in by `evolution_zoom` 0.35, sparks rush into the cell, the cell glows in the evolution colour, "EVOLVING..." grows, a chime) → burst (white flash, rings, 24-spark explosion, heavy shake, evolve + impact sounds, long buzz) → banner (evolved icon, "EVOLUTION!", the name popping in, the effect text) while the camera punches then eases back. Several evolutions from one chest play in turn.

### Satisfaction round 3: end of run + claim fill (2026-11-04)
Yousuf picked set 6 (both) and, from set 7, only the animated claim fill.
- **Results highlights card:** damage share per source as bars that grow in (weapons with their evolved name/colour, Swarm allies, towers, dash, infected land, bombs, plague; top 5 at 1%+), plus chips: biggest hit (and what dealt it), best streak, most-killed germ. World now tags damage by source (`World._src`, `damage_by`, `biggest_hit`/`biggest_src`), counting **effective** damage (no overkill, so instant kills don't dominate; 1e6 kills don't count as the biggest hit). Best streak moved from the stats rows into the card.
- **Gold fly-in** (v2 after Yousuf: "very buggy and looks bad"): a wallet pill sits top-right on the results screen; on PLAY AGAIN / Menu, up to `gold_fly_max_coins` 20 coins rise in a stream from the run's gold (`gold_fly_gap_s` 0.06, `gold_fly_s` 0.6, cubic ease-in-out along a curve that rises first). The run total counts **down** as each coin leaves and the wallet counts **up** as it lands (climbing chime, punch); buttons are locked meanwhile. Bug fixed: tapping before the "+N gold" count-up finished let it keep overwriting the number (`UiKit.count_up` now returns its tween so it can be stopped).
- **Animated claim fill (Infection):** claimed tiles appear in a wave spreading from where the loop closed (`claim_fill_speed` 1600 px/s, at most `claim_fill_max_s` 0.7 s for big loops), each flashing white as the wave reaches it (replaces the instant white flash). View only: World claims instantly as before.
