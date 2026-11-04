# Session handoff: Petri Panic (read this first in a new session)

Written 2026-11-03 at the end of the first long build session (12 commits on `claude/bold-brown-h48pfg`, head `abca8db` "Progress tracking (Profile, achievements, leaderboard stubs) and menu redesign" plus this doc). It is the complete working context: who the owner is, how we work, how the code is built, every gotcha we hit, the current balance, the feedback history, and what comes next. `CLAUDE.md` is the short rulebook; this is the long version. `docs/HANDOFF.md` is the **original** planning handoff from before any code existed. It is historical context only; where they differ, this file wins.

---

## 0. First 10 minutes in a new session (checklist)

1. Read `CLAUDE.md`, then this file, then skim `docs/PIPELINE.md` (dated log) and `docs/ROADMAP.md` (plan).
2. Set up the tools (section 3). Godot 4.7.2 + export templates, then `godot --headless --path . --import` **twice**.
3. Run the tests: `godot --headless --path . -s res://tests/run_tests.gd` should report **159 tests, 0 failure(s)**. Some `ERROR: Parse JSON failed` lines are expected: one test deliberately corrupts a save file.
4. `git status` / `git log --oneline` should show the branch `claude/bold-brown-h48pfg`: **Yousuf's main branch** (the default branch). A new cloud session may be checked out on a session branch (e.g. `ccr-...`); Yousuf wants all work on `claude/bold-brown-h48pfg`, so check it out (`git fetch origin claude/bold-brown-h48pfg && git checkout -B claude/bold-brown-h48pfg origin/claude/bold-brown-h48pfg`) and push there.
5. Ask Yousuf for his latest playtest notes if he hasn't given any. Work is driven by his phone playtests.

---

## 1. The owner and how to work with him

- **Yousuf**, an A-Level student in Karachi. About 6-8 hours a week, with pauses around exams. Solo: no team, no artist. Weak PC (GTX 750 Ti); tests on his Android phone (and ideally a cheap one).
- Goals: a real shipped, monetised Android game with analytics, both for income and for university applications (CS, scholarships). He wants to **move fast but end up genuinely polished**.
- **Communication style that works:**
  - Concise and concrete. Lead with what changed and what he should test.
  - Use tables for options and for "your note → change".
  - End with numbered questions for his next playtest.
  - Always give the **APK link** (the Actions run URL) and say "uninstall the old one first" (debug builds are signed with a fresh key each time until he adds the keystore secrets).
  - Quote sim numbers before and after any balance change, briefly.
- **He decides the design; you propose.** On open design questions, give 2-4 options with a clear recommendation (AskUserQuestion works well for multi-choice). When he says "go ahead with it", implement fully. When he says "discuss"/"plan"/"don't implement", **only plan**.
- He prefers **minimal, surgical changes** over rewrites, and data changes over code changes.
- He playtests by playing on his phone and reports qualitative notes (e.g. "the ranged enemy seems way more powerful", "too easy once I had a swarm", "fps dropped to 20 with lots of effects"). Treat his notes as ground truth over the bot.
- He has set up GitHub Pages (web build) and installs APKs from Actions artifacts. He has **not** yet added the keystore secrets, a Play Console account, AdMob or PSEB (`docs/SETUP.md` §2 and §4). Remind him when relevant, but don't nag.

---

## 2. Current state (what exists)

**Game:** "Petri Panic" (working title; theme: microbes in a petri dish, you're a white cell with a "you are the infection" angle). It's a portrait one-thumb survivor-lite in Godot 4.7.2 (Compatibility renderer).

| Area | Status |
|---|---|
| Core loop | Drag-anywhere joystick (base locks where you touch), auto weapons, XP gems, **banked level-ups** (UPGRADE button bottom-left with count badge; no pausing popups), 5:00 runs, boss (Mother Cell) at 3:50, death → revive (rewarded stub ad) → results → menu |
| Content | 8 enemy types, 4 weapons, 11 general passives (incl. 4 dash cards) + 3 Swarm-only passives, 4 evolutions, elites every 40 s with chests, 3 rare pickups (vacuum/heal/bomb) |
| Dash | Button bottom-right / second-finger tap / Space. 2.0 s cooldown, charges, Lunge/Afterimage/Adrenaline/Double Flagella cards; Afterimage decoy has its own 6 s cooldown |
| Game modes | **Infection** (bounded dish, loop-claim territory), **Swarm** (kills convert into allies you command: Guard / Hunt / Harvest from a fan-out button left of Outbreak; the run pauses while the fan is open), **Nucleus** (tower defence), **Classic** (open field). Picked on the menu via mode cards |
| Meta | 15 permanent upgrades, 96 tiers (~17k gold), scrolling shop with icons and current totals |
| Progress | `Profile` (v3): lifetime stats incl. best kill streak, per-mode records, 21 achievements, run score, NEW BEST, Profile screen. Versioned JSON save with backup and legacy import |
| Online | `Online` facade + stub (leaderboards/achievements/cloud API). **Play Games not connected yet**, planned for after M3 |
| Polish | Vector icons for everything (IconArt), card UI with level pips, pick bursts, chest slot-machine with icons, BUILD button + paused build overlay (`BuildScreen`, replaced the old dot strip), redesigned animated main menu |
| Ads/analytics | `Ads` facade with stub (fake ad overlay); `Analytics.event` prints only. AdMob/Firebase not wired yet (M3) |
| CI | Tests + 4-run balance smoke on every push; web build → GitHub Pages; Android debug/release APK on manual dispatch or `v*` tag |
| Perf | 60 fps at 170+ enemies on Yousuf's phone (APK). Sim ~0.6-1.0 ms per step on desktop at peak. `debug.show_perf` is ON (yellow readout); turn it off before release |

**Milestones** (`docs/PIPELINE.md`): M0 and M1 done; **M2 in progress** (feel/balance/fun, which is where all the recent work has been). M3 (release plumbing) through M6 not started.

---

## 3. Environment setup (fresh cloud container)

The container is ephemeral. Godot is **not** preinstalled; a new session must install it (about 1 min plus a 1.2 GB template download):

```bash
mkdir -p /tmp/claude-0/godot && cd /tmp/claude-0/godot
V=4.7.2
curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/${V}-stable/Godot_v${V}-stable_linux.x86_64.zip && unzip -o -q godot.zip
ln -sf /tmp/claude-0/godot/Godot_v${V}-stable_linux.x86_64 /usr/local/bin/godot
# Export templates (only needed for local web export; CI has its own):
curl -sSL -o templates.tpz https://github.com/godotengine/godot/releases/download/${V}-stable/Godot_v${V}-stable_export_templates.tpz
mkdir -p ~/.local/share/godot/export_templates/${V}.stable && unzip -q -o templates.tpz -d tpl
mv tpl/templates/web_* tpl/templates/version.txt ~/.local/share/godot/export_templates/${V}.stable/ && rm -rf tpl templates.tpz
cd /home/user/survivor-lite && godot --headless --path . --import && godot --headless --path . --import
```
- Run the template download in the background (it's large).
- **Import twice** on a fresh clone. The first pass can error on `preload()` of not-yet-imported wavs, and new `class_name` scripts aren't registered until an import runs. After adding any new `class_name` file, run `--import` before running tests, or you'll see "Could not find type X".
- Python 3 with numpy and Pillow is available (asset pipeline). Node + Playwright + Chromium are preinstalled. `xvfb-run` is available.

### Everyday commands
```bash
godot --headless --path . -s res://tests/run_tests.gd                      # 159 tests
godot --headless --path . -s res://tools/sim/balance_sim.gd -- --runs 8 --seed 600 --mode classic --json /tmp/claude-0/x.json
godot --headless --path . -s res://tools/sim/bench.gd -- --mode swarm --loaded   # perf per subsystem
python3 tools/build_assets.py                                               # regenerate SFX + bg tile, then --import
```
- **Balance sims:** each run takes ~2-10 s, so 8 runs take about 1-2 min. Run 3 seeds in parallel (`600 700 800`), each `--runs 8`, in the background, then wait with an `until [ -f ... ]; do sleep 5; done` loop. Modes: `--mode infection|swarm|classic`; `--meta` = every permanent upgrade maxed. The output JSON has p10/p50/p90 time, win_rate, level_p50, mean kills/chests/evolutions/infected/conversions/peak_allies, death_causes, and `upgrade_mean_time` (mean survival of runs that owned each upgrade).
- Sim also reports `mean_sec_per_level` and `mean_levels_by_2min` (level-up pace).
- Tuning without editing data: `--set conversion.ally_damage_mult=2.5,difficulty.damage_taken_mult=1.8` (dotted balance keys, after the mode is applied). Swarm: `--order hunt` makes the bot keep one order. Yousuf's win-rate cap needs **48 runs** (seeds 600-1100 × 8); 24-run numbers swing ±10 points.
- The standard comparison set is seeds 600/700/800 × 8 runs. Quote "before → after" win rate, p50 range and level range.

### Visual verification in the cloud (important: we cannot see the phone)
- **xvfb probe pattern (preferred, fast):** write a throwaway `probe_tmp.gd` in the repo root that `extends SceneTree`. It instantiates `res://scenes/main.tscn` (name it `"Main"`), drives it frame by frame in `_process` (call `main._start_run()`, poke `main.world`, set `main.hud.stick_active/stick_origin/stick_pos` to steer, call `main._open_banked()`, `_pick()`, `_show_shop()`, `_show_profile()`...), and saves screenshots with `root.get_texture().get_image().save_png(...)`. Run it with:
  `timeout 120 xvfb-run -a godot --path . --rendering-driver opengl3 -s res://probe_tmp.gd > /tmp/claude-0/probe/log.txt 2>&1`
  Then **delete `probe_tmp.gd` and `probe_tmp.gd.uid`** before committing, and read the PNGs (combine several with PIL to save tokens).
  - Autoloads can't be referenced by name from a SceneTree script: use `root.get_node("Save")`.
  - xvfb runs at ~100-140 fps, so convert frame counts to game time accordingly.
  - Frame-time measurements under llvmpipe are CPU-rendered, so compare *relative* numbers (`/tmp/claude-0/render_probe.gd` was the pattern: disable vsync, measure ms/frame and worst frame plus `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`).
- **Web export + Playwright:** `godot --headless --path . --export-release "Web" build/web/index.html`, serve it with `python3 -m http.server 8765` (run with `run_in_background`), and drive Chromium with `--use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader`. Slower; use it only to check WebGL-specific issues.

### CI and builds (GitHub)
- There is no `gh` CLI. Use the GitHub MCP tools (load them via ToolSearch: `mcp__github__actions_run_trigger`, `actions_list`, `actions_get`, `get_job_logs`).
- After pushing, **dispatch** `android.yml` and `web.yml` on ref `claude/bold-brown-h48pfg` (`method: run_workflow`), then poll the public API:
  `curl -sS "https://api.github.com/repos/yousufkamran222-code/survivor-lite/actions/runs?per_page=4&head_sha=$(git rev-parse HEAD)"` in an `until ... all completed` loop (sleep 20).
- `test.yml` runs automatically on push. Give Yousuf the **Android build run URL**; the APK is the artifact `petri-panic-apk-N`.
- Pages deploys from the dispatched web run (Yousuf enabled Pages with source "GitHub Actions"). `web.yml` also triggers on push to `main`, but **no `main` branch exists**: everything is on `claude/bold-brown-h48pfg`, which is the default branch.
- Push only to `claude/bold-brown-h48pfg` (`git push -u origin claude/bold-brown-h48pfg`). Don't create PRs unless asked.

### Commit conventions
- Commit messages have a clear summary line, then bullets. **Include before → after sim numbers for balance changes.** End with the attribution trailer the system provides, e.g. `Co-Authored-By: ...` and `Claude-Session: ...`.
- Before committing:
  - The tests pass.
  - `grep '"invincible"' data/balance.json` shows `false`.
  - No `probe_tmp.gd` is left behind.
  - `docs/PIPELINE.md` has a dated log entry for the change.
  - SPEC/ROADMAP/DECISIONS are updated if rules or plans changed.

---

## 4. Repository map

```
CLAUDE.md                 Short rulebook (read first). Points here.
GODOT_VERSION             4.7.2 (CI reads it)
project.godot             Portrait 720x1280, Compatibility renderer, autoloads: Save, Analytics, Sfx, Ads, Online
export_presets.cfg        "Web" (single-threaded, include_filter data/*.json) and "Android" (non-Gradle, arm64+armv7)
scenes/main.tscn          One node "Main" with scripts/game/main.gd. Everything else is built in code.
data/                     ALL tuning (see section 6)
scripts/core/             Pure logic (RefCounted, no Nodes), deterministic for a seed
  world.gd       (1428)   The whole simulation: player, enemies/allies (SoA), weapons, bullets, shots, gems,
                          chests, pickups, dash, territory hooks, conversion, level-ups. Emits events.
  territory.gd   (190)    Dish tiles (64x64), trail, loop-claim flood fill, erosion, dirty list for the view
  spawn_director.gd       Spawn budget curve, enemy pool, scripted events, elite schedule, budget_mult (pressure), hp/damage growth
  upgrades.gd             Stat summing from level tables, offer rolling, GLOBAL_STATS list
  progression.gd          XP curve, run gold, meta bonus/costs/text, run_summary + run_score + metric_value
  profile.gd     (226)    Persistent progress model: stats, records, achievements, merge(), legacy import
  game_data.gd            Loads data/*.json, apply_mode() deep-merge, validate() cross-references
  balance_bot.gd          Sim/test "player": dodge, chase loot, loop home in territory, dash, random-ish picks
scripts/game/
  main.gd        (885)    Screen flow and all UI screens (menu, shop, profile, level-up, chest, death, results, pause), input, event → sfx/haptics
  world_view.gd  (438)    Renderer: bg tile, territory texture, SpriteBatches, top layer (player, orbit, rings, chain, numbers, loot, trail), effects, camera shake
  sprite_batch.gd         Same-texture rect batching (NOT MultiMesh)
  shape_textures.gd       Generated textures: enemy blob atlas (16 eye directions), ally cell, disc, diamond
scripts/ui/
  ui_kit.gd               Theme, label/button/overlay helpers, icon_card() + Pips
  hud_overlay.gd (221)    XP bar, timer, % infected / swarm count, BUILD button (`build_rect`), Swarm order fan, arrows, toasts, notice, DASH and UPGRADE buttons, joystick, perf readout
  icon_art.gd    (170)    All vector icons (upgrades, meta, modes, trophy, sound, gold)
  upgrade_icon.gd         Control wrapper for one icon
  meta_shop.gd            Permanent-upgrade shop: tile grid + per-upgrade popup, buy VFX/sfx (MetaShop)
  drag_scroll.gd          ScrollContainer you drag anywhere (momentum; was_dragged() guards taps)
  menu_background.gd      Animated menu backdrop + hero cell
scripts/autoload/
  save_service.gd         "Save": Profile ↔ user://profile.json (+ .bak, legacy save.cfg import); old props as pass-throughs
  online_service.gd       "Online": leaderboards/achievements/cloud facade; report_run()
  stub_online_backend.gd  Local-only backend (never signed in)
  ad_service.gd           "Ads": rewarded/interstitial facade
  stub_ad_backend.gd      Fake ad overlay, always rewards
  analytics.gd            "Analytics": event(name, params) → print + ring buffer
  sfx.gd                  "Sfx": preloaded synthesised wavs, player pool, rate limits
tests/                    run_tests.gd (runner), test_case.gd (asserts), test_*.gd (159 tests)
tools/build_assets.py     Synthesises all SFX (sfxr-style) + bg_tile.png (deterministic)
tools/sim/balance_sim.gd  Bot balance runs → JSON report
tools/sim/bench.gd        Per-subsystem ms/step during a kiting run (--mode, --loaded)
assets/processed/         Generated wavs + bg_tile.png (+ .import files, committed). MANIFEST.md lists licences.
.github/                  actions/setup-godot (cached Godot + templates), workflows test/web/android
docs/                     SPEC (game rules), PIPELINE (milestones + dated log), ROADMAP (plan), DECISIONS (log),
                          SETUP (Yousuf's manual steps), HANDOFF (original), SESSION_HANDOFF (this)
```

---

## 5. Architecture in depth

### 5.1 World (`scripts/core/world.gd`)
- Constructed with `World.new(game_data_after_apply_mode, seed, meta_bonus)`. Everything comes from data: no tuning numbers in code.
- **`step(dt, move)` order:** time/victory → `_update_player` (dash, charges, decoy, regen, dish clamp) → `_update_territory` (if dish) → `_spawn` → `_rebuild_grid` → `_update_enemies` (enemies and allies, separation every `SEP_EVERY`=3 frames) → `_update_ally_combat` (if allies) → `_update_weapons` → `_update_bullets` → `_update_enemy_shots` → `_process_dead` → `_contact_damage` → `_update_gems` → `_update_pickups` (chests/items) → auto-open level-up **only if not banking**.
- **States:** `playing | levelup | chest | dead | won`. Sims and tests must handle `chest` (call `close_chest()`) and open banked level-ups themselves (`if w.pending_levelups > 0 and w.state == "playing": w.open_banked()`).
- **Enemies are struct-of-arrays:** `e_type, e_uid, e_pos, e_knock, e_hp, e_maxhp, e_flash, e_timer, e_phase, e_dir, e_hitcd, e_rad, e_spd, e_elite, e_team, e_life`. Removal is swap-remove (`_remove_enemy`). **Add any new per-enemy array to `_add_enemy` and `_remove_enemy`.**
- **Teams:** `e_team == 1` are Swarm allies living in the same arrays.
  - `query(center, radius, team=0)` and the targeting helpers (`_nearest_enemy`, `_priority_target`) return hostiles only.
  - **Any loop over `e_pos` must skip allies itself** when it should (territory DoT/erosion, the claim burst and the bot already do). The bot once fled its own allies because of this.
  - `hostile_count()` feeds the spawn cap.
- **Spatial grid:** `_grid` dict keyed by integer `_key(cx, cy)`, CELL 64. Rebuild it after removals (`_process_dead` does).
- **Damage:** `_damage(i, amount, knock, show)`. It applies land buff and Hive Mind multipliers, knock resist (elites resist more), and marks `_dead`. `_hurt(amount, cause)` for the player scales with `director.damage_mult(time)` and armor and respects `debug.invincible`.
- **Weapons** are matched by id in `_update_weapons`: bolt (aims via `_priority_target`: elites/boss first), orbit (also `_block_shots`), nova (`_fire_nova`, Fever Spike double pulse via `_nova_echo`), chain (forks for Neural Storm). Final weapon stats come from `_recompute_stats()`: level tables + evolution deltas + globals (might/haste/amount).
- **Global stats** (`Upgrades.GLOBAL_STATS`): might, haste, move, max_hp, magnet, amount, regen, xp_gain, gold_gain, armor, convert, ally_power, ally_cap, hive, convert_heal, dash_charges, dash_damage, dash_decoy, dash_cd, dash_reset. Sources: owned passives plus the meta bonus. Any new stat must be added to this list (validation enforces it for meta).
- **Level-ups:** `_update_gems` grants XP, `pending_levelups++`, and emits `level_gained`. `open_banked()` → `_open_levelup()` (rolls 3 offers via `Upgrades.roll_offers`, respecting `"modes"` and weapon slots) → state `levelup`. `choose_upgrade(id)` keeps the picker open while picks remain. `close_levelup()` is "Later".
- **Chests/evolutions:** elites and the boss drop chests (`c_pos/c_items`). Touch → `_open_chest(n)` → each item is an evolution if `ready_evolutions()` (weapon at max level + paired passive owned), else +1 level of an owned non-maxed item, else a new item, else a heal. State `chest` until `close_chest()`.
- **Rare pickups:** `i_pos/i_kind` with kinds `PICKUP_KINDS = ["vacuum","heal","bomb"]`, rolled per normal kill (`balance.pickups.chances`).
- **Dash:** `dash()` uses charges (`p_dash_charges`, `dash_max_charges()`, `dash_cooldown()`), iframes, Lunge hits (`_lunge_hits`), and the Afterimage decoy (`decoy_pos/decoy_t/decoy_cd`, `_decoy_blast`). Enemies (not elites or the boss) within `decoy_radius` chase the decoy.
- **Territory hooks:** the dish clamp, `_spawn_point` avoids land and the outside, land slows enemies, `_update_territory` (trail and claims, DoT/erosion tick), `_on_claim` (40% max HP burst plus claim XP), `_pressure()` scales spawn budget and enemy HP with % infected.
- **Kill streak** (`balance.streak`): `_add_streak()` on every hostile kill; `streak`, `streak_t` (game time, so pauses don't break it), `best_streak`. Milestones (`milestones`, then every `repeat_every`) emit `streak` {n, tier}; a break emits `streak_end`. **Hook for future streak upgrades/abilities:** `balance.streak.rewards` [{at, pickup | outbreak}] fire in `_streak_rewards()` after the kill pass (empty by default, validated); add new reward kinds there. Tiers (`tiers`: name + colour) drive the HUD. JSON numbers are floats: compare milestones with `int()`.
- **Swarm orders:** `ally_order` (`ORDER_GUARD/HUNT/HARVEST`, ids in `ORDER_IDS`), `set_ally_order(o)` (1 s cooldown `order_cd`), `_order` = the current def from `balance.conversion.orders`. `_ally_velocity` picks the goal: the ring slot (Guard; Hunt widens it), the germ from `_hunt_target` (Hunt, retargets every 3rd frame per ally), or a gem from `_harvest_target` (Harvest; `_gem_claims` spreads allies over different gems; `_grab_gems` sets `g_pull` so the gem flies to the player). Allies reuse `e_dir` as their goal (`Vector2.INF` = none). `_ally_power()` scales with `_hp_mult()` and might (`scale_with_hp`, `might_applies`), the order's `damage_mult` and the Outbreak boost. Stats: `damage_dealt`, `ally_damage` (via the `_src_ally` flag and `b_ally` per bullet), `gems_harvested`, `order_changes`.
- **Conversion (Swarm):** `_try_convert` on a normal kill (chance = base + `convert`). Allies get the hp/speed multipliers and a lifetime; on a full swarm the conversion **feeds** instead (`swarm_power` up to `feed_power_max`, plus a heal). `_ally_velocity` holds the bodyguard ring slot (teleports if too far), ranged allies shoot (`_ally_shot`), `_ally_block_shots` soaks enemy shots, and `_update_ally_combat` is the melee tick.
- **Events** (`events` array, consumed by Main then WorldView, then cleared): `ally_lost boss_killed boss_spawn chain chest claim convert dash death decoy elite_killed elite_spawn evolution evolution_ready hit hurt kill land_lost level_gained level_up nova pickup pickup_item revive shoot shot_blocked swarm_feed trail_lost upgrade victory`. Set `emit_events = false` in sims and tests for speed.

### 5.2 Modes (`data/modes.json`, `GameData.apply_mode`)
- A mode is `overrides`, deep-merged into a *copy* of `balance`, and it sets `balance.mode_id`.
  - **Infection** = territory on + XP curve (linear 4, quad 0.17).
  - **Swarm** = conversion on + XP (4, 0.16).
  - **Classic** = territory off.
- Upgrades with `"modes": [...]` only appear in those modes (World filters `upgrade_list` by `mode_id`).
- `balance.json` itself has `territory.enabled: true` and `conversion.enabled: false`; the mode overrides decide. **Tests that construct `World.new(data(), ...)` without `apply_mode` get territory ON.** Use `GameData.apply_mode(data(), "classic")` when you need the open field.
- Menu cards read `icon`, `color`, `special`, `special_label` from the mode entry.

### 5.3 Rendering (`world_view.gd`)
- Layer order (children of WorldView, drawn after the parent's `_draw`):
  1. the parent `_draw`: bg tile (`texture_repeat`) + territory texture + dish rim
  2. gems → enemy shots → enemies (blob atlas) → **allies** (ally cell) → bullets → dots (particles)
  3. the `_top` Node2D (`_draw_top`): trail, loot, elite auras, orbit, player, rings, chain, damage numbers, boss bar
- **Do not use MultiMesh**: it rendered nothing in the WebGL build. `SpriteBatch` (same-texture rects via `draw_texture_rect_region`) is the batching method.
- **Phone fill rate:** big translucent fills are expensive. Rings with r ≥ 160 draw outline only (this fixed real frame drops). Damage numbers are capped at 12 (text drawing is costly).
- Effects `fx` are dicts with `kind` dot/pop/ring/chain/claim/num, capped by `perf.max_effects`.
- Weapon colours switch to the evolution colour via `_wcolor()`.

### 5.4 UI (`main.gd`, `hud_overlay.gd`, `ui_kit.gd`, `icon_art.gd`)
- Screens are overlays from `UiKit.overlay()` (ColorRect + CenterContainer + VBox `col`), rebuilt on show with `UiKit.clear(col)`. `screen` is one of `menu | playing | levelup | chest | dead | results | paused`. `_set_screen()` toggles the HUD/view/pause button.
- **Input** (`_unhandled_input`): the UPGRADE button opens the picker; the DASH button or a second finger dashes; otherwise the touch starts the joystick (base locked; `juice.stick_follow` restores drag-along). Keys: WASD/arrows, Space = dash, E/Tab = upgrade.
- `_process` steps the world once per frame with dt clamped to 1/30 (no physics catch-up).
- Level-up cards: `UiKit.icon_card(icon, title, body, hint, have, next, total, accent, on_press)` + `_pop_in()` tween. Evolution hints come from `_evolution_hint()`.
- **Labels inside narrow containers (HBox, Grid, pills) need `autowrap_mode = AUTOWRAP_OFF`.** `UiKit.label` turns word-wrap on by default, and those labels otherwise collapse to one character per line (this bit us twice).
- The menu: `MenuBackground` (child 0 of the menu overlay; `show_hero` off for shop/profile), `_gold_pill`, `_mode_card`, `_tile_button`, and the pulsing PLAY tween.

### 5.5 Services
- **Save/Profile:**
  - `Save.profile` is the source of truth. `Save.write()` writes JSON atomically (tmp → rename via `DirAccess.rename_absolute`) after copying the old file to `.bak` (`copy_absolute`).
  - `load_save()` reads the main file → `.bak` → legacy `save.cfg` (then writes JSON).
  - Run end (`_show_results`): `Progression.run_summary` → `profile.record_run(summary, achievements, now)` → `Online.report_run` → `Save.write()`. Gold is added on collect (`profile.add_gold`), after the optional double-gold ad.
  - **`Profile.from_dict` must cast numbers** (JSON makes everything a float); a test guards this.
- **Online:** `submit_score`, `unlock_achievement`, `push_profile/pull_profile`, `report_run`. The stub logs only. A future `PlayGamesBackend` implements the same methods and is chosen when the plugin singleton exists. Conflict resolution is `Profile.merge(local, cloud)`.
- **Ads:** `Ads.show_rewarded(placement, cb)` with placements `revive`, `double_gold`, `reroll`; `Ads.show_interstitial("between_runs", next)` every 3rd death after 2 runs (not right after a rewarded ad).
- **Analytics:** events include run_start, run_end (with mode, score inputs), upgrade_pick, chest_open, evolution, pickup, death, boss_spawn/killed, meta_buy, ad events. Names are snake_case, 40 characters or fewer.
- **Sfx:** names in `SOUNDS` (preloaded from `assets/processed/sfx`). To add a sound: add a `write("name", ...)` line in `tools/build_assets.py`, run it, `--import` twice, then add it to `SOUNDS`.

---

## 6. Data reference (`data/*.json`)

- **balance.json:**
  - title, run_length_s (300), start_weapon (bolt)
  - **player:** speed 175, pickup 125, iframes, dash_*, decoy_*
  - **territory:** dish 1500, grid 64, erosion 0.12/s, slow 0.25, dps 2.5, claim burst 0.4, claim XP 0.15/tile, pressure budget ×2 / HP ×1.5 at 100%
  - **conversion:** base 0.09, max_allies 12, hp ×2, dmg ×1.5, speed ×1.6, life 40 s, ring 80-150, feed 0.06 up to 0.75
  - chests, pickups, xp (base 5, linear 3, quad 0.1)
  - **upgrades:** offers 3, bank_levelups true, max_weapons 4
  - **economy:** gold_per_kill 0.05, 8/min, boss 60, win 50
  - revive, ads, perf caps, debug (show_perf true, invincible false), juice (feel knobs, joystick, dash button), palette
- **enemies.json:** grunt (Germ), swarm (Spore), runner (Zipper), brute (Lump), spitter (ranged), charger (Lancer, dash), splitter (Mitosis), boss (Mother Cell, `fixed_hp` 1000).
- **waves.json:**
  - budget_curve (2.4 → 20/s), max_alive 170
  - hp_growth_per_min 1.2, damage_growth_per_min 0.3
  - elites: first 35 s, every 40 s, hp ×8, radius ×1.7, speed ×1.15
  - pool unlock times; scripted events: rings, boss at 230 s, final flood
- **upgrades.json:** 4 weapons (bolt/orbit/nova/chain, 5 levels each; orbit has `blocks_shots`), passives might/haste/swift/vitality/magnet/multishot(2)/regen(3), dash cards flagella2/lunge/afterimage/adrenaline, Swarm-only viral/hive/incubate. Each level row is stat deltas; `desc` is per level, or one string.
- **evolutions.json:** storm (bolt + multishot), wall (orbit + vitality, heal_on_hit), fever (nova + regen, pulses 2), neural (chain + haste, forks 3).
- **meta.json:** 15 entries `{id, name, stat, per_level, desc, fmt pct|flat, costs[]}`; costs must strictly increase (validated).
- **modes.json:** infection/swarm/nucleus/classic with overrides plus menu card fields.
- **balance.json `defense`** (Nucleus mode): nucleus hp/radius/damage taken, aggro_radius, pads, build_s, biomass rates, vents, breathers, max wave wait, respawn, per-wave enemy growth. **towers.json:** towers with per-level stats (`weapon` must be one World knows how to fire: `bolt` for now). **waves.json `defense.waves`:** duration, budget, enemies, vents, elites, boss.
- **online.json:** `score` weights; 5 `leaderboards` {id, name, mode, metric score|infected_pct|conversions|kills|time}; 21 `achievements` {id, name, desc, stat (a key of `Profile.flat()`), goal}; 3 are kill-streak ones (`best_streak` 100/250/500).

---

## 7. Balance state (bot, seeds 600/700/800 × 8, no meta)

| Mode | Win | p50 | Level p50 | Notes |
|---|---|---|---|---|
| Classic | 19% (48 runs) | 4:11-4:42 | 8-14 | After final minute + XP x0.7; ~26 s per level-up (bot) |
| Infection | 21% (48 runs) | 2:14-5:00 | 15-33 | Fastest levelling: ~10 s per level-up (bot) |
| Swarm | 15% (48 runs) | 2:17-3:44 | 9-12 | Allies ~25% of damage; damage taken x2.0, XP quad 0.27 stacks with the cut (revert to 0.22 first if slow) |
| All meta maxed | 100% | 5:00 | ~41 | Expected for a fully maxed account |

**Bot biases:**
- It dashes with perfect reflexes, so humans find the game harder.
- It never exploits decoys or territory well, and it flees the boss (understating boss kills).
- It collects gems worse than humans.

Yousuf's feel overrides the bot; use the bot for relative comparisons and catching breakage.

---

## 8. Playtest feedback history (what he said → what we did)

1. Web build lagged as enemies piled up → batched rendering (SpriteBatch), faster separation, no physics catch-up. The APK then hit 60 fps at 170+ enemies on his phone.
2. "Make the core loop more fun" → he chose all four: dash, elites + chests, evolutions, rare pickups. The opening was also made snappier.
3. Spitter (ranged) felt overpowered, especially against Antibodies → Antibodies destroy enemy shots (his choice).
4. Asked for a unique angle → "you are the infection": territory (Infection) + conversion (Swarm), kept as **game modes** (his idea) rather than choosing one.
5. Territory: claiming felt nice, but erosion was too fast, so he turtled at under 10% infected and still won → slower erosion, claim XP, pressure scaling with land, its own XP curve.
6. Swarm v1: chaotic, engaging the swarm cost more HP than kiting, upgrades weak → **bodyguard ring** rework, cap 12 + feeding, distinct ally look, Hive Mind / Viral Load heal. (A bot bug had also skewed the Swarm sims.)
7. Swarm v2: too easy/untouchable with Antibodies; fps drops with heavy effects; wanted a locked joystick → ally nerfs + Swarm XP curve; big ring fills removed; joystick base locked.
8. Level-up popups annoying → **banked level-ups only** (his spec: UPGRADE button with a count badge, a small reminder, no auto-open). Dash: 2.0 s cooldown plus four dash cards.
9. Wanted more permanent upgrades with more tiers, including dash ones (he deferred strains and the "Lab" talent tree) → 15 upgrades / 96 tiers.
10. Afterimage felt overpowered; the upgrade UI felt like plain text → decoy gets its own cooldown and smaller lure; IconArt icons, cards, VFX, chest icons, HUD strip.
11. Accounts/progress/leaderboards → Play Games later; built local progress tracking, the `Online` stub, achievements and score. The main menu "looked bad" → redesigned.
13. Nucleus step 2: towers weak vs the player, pick popup interrupted building, Free Mode too easy → non-pausing tower bar (his pick), stronger towers that grow per wave, harder waves, compounding Free Mode.
16. Asked for a kill-streak feature that's extremely satisfying at high numbers, a best-streak stat + achievement, and room for future streak-triggered upgrades → World-side streak with tiers (COMBO → CONTAGIOUS → EPIDEMIC → PANDEMIC → PLAGUE → EXTINCTION), milestone bursts, a draining timer bar, NEW BEST STREAK call-out, `best_streak` saved (Profile v3) + 3 achievements, and the `streak.rewards` hook.
15. Kills "not very satisfying", numbers could be better; the owned-upgrade dots were unreadable → damage numbers v3 (arc + gravity, springy pop, white→yellow→orange→pink by hit size, hot killing blow), kill flash + faster dragged burst, multi-kill shake/ring; a BUILD button that opens a paused overlay listing every weapon/upgrade with level, tier bar, effect and evolution path.
14. Swarm "kinda useless" (allies measured at 2.5% of damage) → his order menu (fan-out: Guard / Hunt / Harvest gems only), ally damage scaling with enemy HP + might, Outbreak boosts allies; difficulty via damage taken x2.0 and a steeper XP curve. Sacrifice order parked in SPEC "Later".
12. Upgrades shop didn't scroll (only via the thin scroll bar) and was hard to read ("0/2") → `DragScroll` (drag anywhere, momentum, drags never count as taps) + `MetaShop`: tile grid with tier bars, prices and "can buy" badges, a detail popup per upgrade with NOW → NEXT in words and a big green UPGRADE button with sound, haptics and VFX.

---

## 9. Gotchas and lessons (read before coding)

- **`pkill -f <pattern>` / `pgrep -f` can match your own shell command** if the same command line contains the pattern (e.g. it also launches the sim). That killed the shell twice and silently skipped edits. Use a separate command or a bracket trick (`pgrep -f "[b]alance_sim"`), and re-check that edits applied.
- **GDScript typing:** `:=` can't infer from Variant (Dictionary values, untyped Array elements). Use typed for-loops (`for i: int in arr`) and explicit types (`var c: Vector2 = ...`). `var x: bool = r.kind == "evolution"` needs the explicit type too.
- `match` with `continue` inside a `for` loop continues the loop (Godot 4).
- Python edits via `str.replace` with `assert s.count(old)==1` are the reliable way to patch big files. Check the counts.
- **DirAccess.copy() fails with bare file names.** Use `DirAccess.copy_absolute` / `rename_absolute`.
- **JSON numbers come back as floats.** Cast them in loaders (`Profile.from_dict`).
- **MultiMesh doesn't render in the WebGL build.** Use SpriteBatch.
- New `class_name` files need `--import` before tests can see them.
- Export: `include_filter="data/*.json"` is required or the JSON tables aren't packed.
- The bot and every loop over enemies must skip allies (`e_team == 1`).
- Tests that run the bot must open banked level-ups and close chests, or they stall.
- `test_bot_run_with_loot_is_stable` uses Classic because the Infection bot turtles and never dashes.
- Screen-sized translucent fills cause phone frame drops; keep big fx as outlines.
- **Every `draw_circle`/style box is its own draw call;** same-texture `draw_texture_rect` calls batch. In menus/UI that is drawn every frame, prefer a tinted disc texture (`ShapeTextures.disc`) and plain `draw_rect`. Check `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` (menu ~65, shop ~150, fight ~56).
- **Web canvas resolution:** the web build caps devicePixelRatio at 2 via `html/head_include` in `export_presets.cfg` (Godot otherwise renders at full device density). Web-only; the APK renders natively.
- `UiKit.label` autowraps; turn it off in narrow containers.
- **Scrolling lists:** use `DragScroll`. Buttons inside need `MOUSE_FILTER_PASS` and should ignore the press when `was_dragged()`; anything else that is `STOP` by default (ProgressBar, Panel) must be set to `IGNORE` or it blocks the drag.
- Debug builds (no keystore secrets) can't update over each other. Tell Yousuf to uninstall first.
- Analytics and the online stub print only in debug builds.
- `balance.json` `debug.show_perf` is on for playtests. **Turn it off for release builds.** `debug.invincible` must stay false.
- **No audio buses created at runtime** (`AudioServer.add_bus`): the web build plays audio through Web Audio "samples", which never connect runtime buses to the output, so every sound on them is silent (found 2026-11-03: output peak 0.45 → 0.0). `Sfx` sets volumes per player instead. Check web audio with Playwright by tapping the output with an `AnalyserNode` (see PIPELINE 2026-11-03).
- **`tools/build_assets.py`: append new sounds at the end of `build_sfx()`.** The noise generator is shared, so inserting a sound earlier silently changes every sound after it.
- Keep `docs/PIPELINE.md` dated entries appended at the end. Decisions go in `docs/DECISIONS.md` (newest last).

---

## 10. What's next (prioritised backlog)

**Immediate (when Yousuf next asks):**
1. **His playtest notes on the newest build:** menu, profile and achievements, Afterimage nerf, icons and cards, banked level-ups, dash. Expect tuning requests; do data changes first.
2. **Theme and name are still open** (working title "Petri Panic"; tagline "You are the infection"). Raise this before store work (M4).

**Planned features (agreed or proposed):**
0000. **Boss Rift** (Yousuf, later): a glowing rift opens every few minutes; optional mini-boss arena fight for a rare reward. Spec in `docs/SPEC.md` "Later".
000. **Combat depth (D-016, D-017):** Volatile dash card; Outbreak = **Frenzy v2** (Yousuf's design: 5 s, weapons x1.6, damage x1.25, half damage taken, x1.5 XP, plus a harmless 380 px **gold blast** that gilds germs worth 0.5 gold each (`outbreak.gild_radius`/`gild_gold`; replaced x3 gold); 300 kills; Plague Trail kept but off); gold counter on the HUD; UPGRADE in the right column. **Bot win rate is only a sanity alarm (±10-15 points is fine); the target is a good player's first win in ~3-5 runs.** Per-mode `balance.difficulty` knobs hold it (Classic HP x1.2 = 40%, Swarm damage taken x1.3 = 38%, Infection 25%, Nucleus 38%).
00. **Polish sweep: `docs/POLISH_PLAN.md`** (planned 2026-11-02 at Yousuf's request): Phase 0 on-device benchmark → Phase 1 performance/battery (90 Hz goal) → Phase 2 combat feel → Phase 3 player cell → Phase 4 sweep (music, settings, UI). Decisions recorded (D-014). Phase 0 (benchmark) built; waiting for his phone's benchmark lines (web + APK) before Phase 1.
0. **Nucleus (tower defence) mode: steps 1-2 built 2026-11-02 (step 1 "feels nice"); step 2 awaiting playtest.** Next is step 3 (polish, best-wave record/leaderboard/achievements, nucleus-repair ad, balance incl. the wave 6-7 spike). Spec, what step 1 includes, sim numbers and steps 2-3 in `docs/ROADMAP.md` "Prototype 3" (D-013). 
000000000. **Kill streak (D-023): awaiting playtest.** Satisfying enough at high numbers? Is a 1.0 s window right (bot best streaks p50: Classic ~70, Swarm ~150, Nucleus ~240, Infection ~430)? Next idea if wanted: streak-triggered upgrades via `balance.streak.rewards`.
00000000. **Kill/number juice v3 + BUILD overlay: awaiting playtest.** Do kills feel satisfying now? Numbers too busy with the arc? Is the BUILD button easy to find (top left, under the bars)?
0000000. **XP x0.7 (D-022): awaiting playtest.** Did level-ups stop coming every few seconds? Is Swarm now too slow? (Its own quad 0.27 stacks with the cut.)
000000. **Final minute + harder late game: awaiting playtest** (D-021). He beat Swarm and Infection first try (with a revive). Ask: does the final minute feel like a climax or a wall? Did a first win take 3-5 runs? **Difficulty levels** (unlock Lv 2+ per mode after a win) are agreed for later: spec in SPEC "Later".
00000. **Swarm orders: awaiting playtest** (D-020). The fan now pauses the run (his request). Questions: is damage taken x2 fair, is Harvest too strong (bot reaches level ~30), does Hunt read on screen? Offered but not chosen: type roles per order, one Swarm card per order. Sacrifice order: SPEC "Later".
3. **Strains (classes) with an ability button:** proposed but deferred by Yousuf ("hold off for now"). Five candidates:
   - Leukocyte / Spore Burst
   - Virus / Hijack
   - Cyst / Shell
   - Bacterium / Toxin Trail
   - Prion / Fold (no dash)

   This would add a second action button next to DASH and a strain picker on the menu. Ask before building.
4. **The "Lab"** (genome talent trees with exclusive choices and codex unlocks): deferred; current meta is flat tiers by his choice.
5. **Fun pass 2 ideas** (offered, not chosen yet):
   - Mutations: trade-off cards
   - Outbreak ultimate meter
   - Symptoms: timed dish events
   - Telegraphed boss patterns
   - Kill streaks
6. **Combine Swarm and Infection:** allies guard land and stop erosion; the boss and elites corrupt land; stars at 25/50/75% (ROADMAP Step 3).
7. Organ chapters (Bloodstream/Lungs/Gut) and Daily Outbreak (seeded, leaderboard) per ROADMAP.

**Release track:**
8. **M3 release plumbing:**
   - Switch Android export to the Gradle build and AAB.
   - Add the AdMob plugin and an `AdmobBackend` behind `Ads` (Google test IDs only in code; real IDs come from CI secrets).
   - Add Firebase Analytics behind `Analytics`.
   - Signed release via the `ANDROID_KEYSTORE_*` secrets (Yousuf must create them; see SETUP §2).
   - **Verify plugin versions support Godot 4.7 first.**
9. **Play Games Services** as `PlayGamesBackend` behind `Online`: sign-in, Saved Games with `Profile.merge`, leaderboards mapped from `data/online.json` ids, achievements. Yousuf creates the console entries (app, PGS project, SHA-1, leaderboards/achievements).
10. M4 store kit (icon, screenshots, 15 s clip, privacy policy, data safety), M5 closed test (12+ testers × 14 days), M6 release + small UA tests.

**Tech debt / polish:**
- Territory grid 64 → 96 for smoother edges (check flood-fill cost on the phone).
- `main.gd` is ~900 lines. If it grows much more, consider splitting the screens into separate scripts (ask first; he prefers minimal changes).
- Turn off `show_perf` for release; consider a hidden toggle in settings.

**Open questions for Yousuf (carry over):**
- Theme and final name.
- Strains: still wanted? Which ones?
- One genome tree per strain, or shared (if the Lab ever happens)?
- Whether to auto-open the picker when many level-ups are banked (currently never, by his choice).
