# Session handoff: Petri Panic (read this first in a new session)

Last updated **2026-11-06** at the end of the third long session (Lab phase 1 + abilities → dash/Virulence scaling fix → Lab middle-node rework + shop tier split → balance report + campaign sim → economy fixes → LAUNCH_READINESS + COOP_DESIGN docs → elite/boss threats, lulls/surges → elite/boss HP floors + health bars → evolution-strength shop upgrades → UI overhaul steps 1-6 ("glossy chunky": design system, motion, level-up, HUD, results, art) → evolution tiers bias level-up offers → kill feel (CC0 sounds, hit squash, gold crits, MEGA KILL)). It is the complete working context: who the owner is, how we work, how the code is built, every gotcha we hit, the current balance, the feedback history, and what comes next. `CLAUDE.md` is the short rulebook; this is the long version. `docs/HANDOFF.md` is the **original** planning handoff from before any code existed. It is historical context only; where they differ, this file wins.

**Where we stopped (2026-11-06):** everything Yousuf asked for is built, pushed (`926f154` and later doc commits) and on itch.io; the last APK is run #51 (before the kill-feel commit, so build a new one when he asks). He said **"balancing seems fine for now"** (early game maybe a bit hard; his idea: a "watch an ad for gold" button on the main menu later). The newest work, waiting for his playtest: the **kill feel** pass (CC0 squelch sounds, hit squash, gold crits, MEGA KILL) and the **UI overhaul**. No new feature is agreed yet: ask him what's next (open kill-feel ideas he hasn't picked are in §10).

---

## 0. First 10 minutes in a new session (checklist)

1. Read `CLAUDE.md`, then this file, then skim `docs/PIPELINE.md` (dated log) and `docs/ROADMAP.md` (plan).
2. Set up the tools (section 3). Godot 4.7.2 + export templates, then `godot --headless --path . --import` **twice**.
3. Run the tests: `godot --headless --path . -s res://tests/run_tests.gd` should report **256 tests, 0 failure(s)**. Some `ERROR: Parse JSON failed` lines are expected: one test deliberately corrupts a save file.
4. `git status` / `git log --oneline` should show the branch `claude/bold-brown-h48pfg`: **Yousuf's main branch** (the default branch). A new cloud session may be checked out on a session branch (e.g. `ccr-...`); Yousuf wants all work on `claude/bold-brown-h48pfg`, so check it out (`git fetch origin claude/bold-brown-h48pfg && git checkout -B claude/bold-brown-h48pfg origin/claude/bold-brown-h48pfg`) and push there.
5. Ask Yousuf for his latest playtest notes if he hasn't given any. Work is driven by his phone playtests. Nothing big is agreed as the next feature (see the "Where we stopped" note above and §10).
6. For web builds and the APK, see §3 "CI and builds": install butler + the web export templates, push with `tools/web_push.sh` after every change, dispatch `android.yml`, and give him the run URL without waiting on CI.

---

## 1. The owner and how to work with him

- **Yousuf**, an A-Level student in Karachi. About 6-8 hours a week, with pauses around exams. Solo: no team, no artist. Weak PC (GTX 750 Ti); tests on his Android phone (and ideally a cheap one).
- Goals: a real shipped, monetised Android game with analytics, both for income and for university applications (CS, scholarships). He wants to **move fast but end up genuinely polished**.
- **Communication style that works:**
  - Concise and concrete. Lead with what changed and what he should test.
  - Use tables for options and for "your note → change".
  - End with numbered questions for his next playtest.
  - After every change: push the **web build to itch.io** (`tools/web_push.sh`; he plays at light213.itch.io/petri and checks the build SHA at the bottom of the menu) and give the **APK link** (the Actions run URL; say "uninstall the old one first": debug builds are signed with a fresh key each time until he adds the keystore secrets). Don't sit waiting on CI: GitHub's queue has been slow; he asked why a task took 15 minutes once.
  - Quote sim numbers before and after any balance change, briefly.
- **He decides the design; you propose.** On open design questions, give 2-4 options with a clear recommendation (AskUserQuestion works well for multi-choice). When he says "go ahead with it", implement fully. When he says "discuss"/"plan"/"don't implement", **only plan**.
- He prefers **minimal, surgical changes** over rewrites, and data changes over code changes.
- He playtests by playing on his phone and reports qualitative notes (e.g. "the ranged enemy seems way more powerful", "too easy once I had a swarm", "fps dropped to 20 with lots of effects"). Treat his notes as ground truth over the bot.
- He plays the web build on itch.io (restricted page, account `light213`, project `petri`) and installs APKs from Actions artifacts. On the web build he uses Settings → DEVELOPER (code 1289) → +10,000 gold / all Virulence levels to test. He has **not** yet added the keystore secrets, a Play Console account, AdMob or PSEB (`docs/SETUP.md` §2 and §4). Remind him when relevant, but don't nag.

---

## 2. Current state (what exists)

**Game:** "Petri Panic" (working title; theme: microbes in a petri dish, you're a white cell with a "you are the infection" angle). It's a portrait one-thumb survivor-lite in Godot 4.7.2 (Compatibility renderer).

| Area | Status |
|---|---|
| Core loop | Drag-anywhere joystick (base locks where you touch), auto weapons, XP gems (x0.7 gain, level-up shockwave), **banked level-ups** (round UPGRADE button in the right column with a count badge; no pausing popups), 5:00 runs with a FINAL MINUTE from 4:00, boss (Mother Cell) at 3:50, Outbreak frenzy button, kill streak, death → revive (rewarded stub ad) → results (highlights card, gold fly-in) → menu |
| Content | 8 enemy types, 4 weapons, 16 shared cards (incl. 5 dash cards, Volatile) + 3 Swarm-only passives, 4 evolutions (with a frozen evolution sequence), elites every 40 s (20 s in the final minute) with chests, 3 rare pickups (vacuum/heal/bomb) |
| Dash | Button bottom-right / second-finger tap / Space. 2.0 s cooldown, charges, Lunge/Afterimage/Adrenaline/Double Flagella cards; Afterimage decoy has its own 6 s cooldown |
| Game modes | **Infection** (bounded dish, loop-claim territory), **Swarm** (kills convert into allies you command: Guard / Hunt / Harvest from a fan-out button left of Outbreak; the run pauses while the fan is open), **Nucleus** (tower defence), **Classic** (open field). Picked on the menu via mode cards |
| Meta | **Gold shop**: 19 permanent upgrades, 237 tiers, 39,736 gold to max (tiers split in two in Profile v6; 4 of them are evolution strength, which also bias level-up offers). **The Lab** (Genes from Virulence wins/minutes): 4 branches × 8 nodes (play-changing nodes, a fork, a keystone, an ability node), respec for gold. **Abilities**: Stasis / Engulf / Cloak / Mitosis, one equipped (Abilities screen), button left of DASH. **Virulence 1-10** difficulty ladder per mode (selector on the mode card) |
| Progress | `Profile` (v6): lifetime stats incl. best kill streak, per-mode Virulence cleared/selected, Genes + Lab + equipped ability, per-mode records, 23 achievements, run score, NEW BEST, Profile screen. Versioned JSON save with backup and legacy import |
| Online | `Online` facade + stub (leaderboards/achievements/cloud API). **Play Games not connected yet**, planned for after M3 |
| Polish | **"Glossy chunky" UI** (2026-11-06): glossy 9-slice buttons with press squash, Lilita One display font, cards, staggered entrances; redesigned level-up (category frames, now→next stats, slide-in, pick animation), HUD (top panel, weapon strip, glossy disc buttons), results (banner, count-up tiles, rewards card); art pass (shaded germs, new floor, glows). Vector icons (IconArt), chest slot-machine, paused build overlay (`BuildScreen`), animated main menu. **Kill feel**: CC0 squelch/impact sounds, hit squash, gold crits, MEGA KILL. Elites have affixes + health bars; the Mother Cell has phases, slam, pull, spiral |
| Ads/analytics | `Ads` facade with stub (fake ad overlay); `Analytics.event` prints only. AdMob/Firebase not wired yet (M3) |
| CI | Tests + 4-run balance smoke on every push; web build → itch.io via `tools/web_push.sh` from the session (`web.yml` = manual backup); Android debug/release APK on manual dispatch or `v*` tag |
| Perf | 60 fps at 170+ enemies on Yousuf's phone (APK). Sim ~0.6-1.0 ms per step on desktop at peak. `debug.show_perf` and `debug.dev_tools` are ON for playtests; turn both off before release |
| Shelved | **Boss Rift** (built 2026-11-04, then switched off: `balance.rift.enabled` false; code, tests and `tools/sim/rift_bench.gd` kept). The Rift Power button/meter is the planned base for Lab abilities |

**Milestones** (`docs/PIPELINE.md`): M0 and M1 done; **M2 in progress** (feel/balance/fun/UI, which is where all the recent work has been). Next after M2: M3 release plumbing (`docs/LAUNCH_READINESS.md` lists the known blockers). M3 (release plumbing) through M6 not started.

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
# butler (itch.io uploads; BUTLER_API_KEY is in the environment):
mkdir -p /tmp/claude-0/dl/butler && cd /tmp/claude-0/dl/butler && curl -sSL -o butler.zip https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default && unzip -q -o butler.zip && chmod +x butler
cd /home/user/survivor-lite && tools/web_push.sh /tmp/claude-0/dl/butler/butler   # export + upload to light213/petri:html5
```
- Run the template download in the background (it's large).
- **Import twice** on a fresh clone. The first pass can error on `preload()` of not-yet-imported wavs, and new `class_name` scripts aren't registered until an import runs. After adding any new `class_name` file, run `--import` before running tests, or you'll see "Could not find type X".
- Python 3 with numpy and Pillow is available (asset pipeline). Node + Playwright + Chromium are preinstalled. `xvfb-run` is available.

### Everyday commands
```bash
godot --headless --path . -s res://tests/run_tests.gd                      # 189 tests
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
- After pushing, **dispatch** `android.yml` on ref `claude/bold-brown-h48pfg` (`method: run_workflow`) and give Yousuf the run URL straight away (don't sit polling: GitHub's queue has been slow). Push the web build with `tools/web_push.sh`. To check runs, use the public API:
  `curl -sS "https://api.github.com/repos/yousufkamran222-code/survivor-lite/actions/runs?per_page=4&head_sha=$(git rev-parse HEAD)"` in an `until ... all completed` loop (sleep 20).
- `test.yml` runs automatically on push. Give Yousuf the **Android build run URL**; the APK is the artifact `petri-panic-apk-N`.
- **Web builds go to itch.io** (since 2026-11-04; GitHub Pages' deploy kept timing out): project `light213/petri`, channel `html5`, restricted page owned by Yousuf. From this session after every change: install the web export templates (`templates/web_*` from the 4.7.2 tpz into `~/.local/share/godot/export_templates/4.7.2.stable/`) and butler (`curl -sSL -o butler.zip https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default`), then `tools/web_push.sh /path/to/butler`. It reads `BUTLER_API_KEY` from the environment (set in the cloud environment settings; never print or commit it). `web.yml` (manual dispatch) does the same from Actions with the repo secret `BUTLER_API_KEY`. The web export is ~44 MB (index.wasm 39.5 MB), too big for hosts with 25 MB per-file caps (Cloudflare Pages). New host = fresh browser save: Settings → Developer → +10,000 gold.
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
  lab.gd                  The Lab rules: tiers, forks, costs, bonus(), full_owned() (pure)
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
  lab_screen.gd           The Lab: branch columns, node popup, Genes pill, two-tap respec (LabScreen)
  abilities_screen.gd     Ability cards with EQUIP (AbilitiesScreen)
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
tests/                    run_tests.gd (runner), test_case.gd (asserts), test_*.gd (189 tests)
tools/build_assets.py     Synthesises all SFX (sfxr-style) + bg_tile.png (deterministic)
tools/sim/balance_sim.gd  Bot balance runs → JSON report
tools/sim/bench.gd        Per-subsystem ms/step during a kiting run (--mode, --loaded)
tools/sim/rift_bench.gd   Boss Rift arena harness: 24 fights, bait vs --nobait (Carrier HP tuning)
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
- **Offer odds:** `Upgrades.roll_offers(..., bias)` multiplies weights by `World.offer_bias()`: shop evolution tiers (`evo_<weapon>`) boost that weapon by ×(1 + `upgrades.evo_offer_bias` × share of tiers) and its evolution partner by ×(1 + `evo_partner_bias` × share). Equal tiers give equal odds; no tiers, no change.
- **Kill feel (presentation only):** Main `_on_kill_streak` (random squelch of `Sfx.KILLS`, pitch by radius × streak), `_on_kills` (multikill thump + MEGA KILL detection: `juice.mega_*`, `_start_slowmo`), `elite_killed` → crunch, crit hits → `crit`. WorldView: hit squash from `e_knock`, directional sparks, gold crit numbers (`num_crit_scale`), `mega_kill(at)`.
- **Rare pickups:** `i_pos/i_kind` with kinds `PICKUP_KINDS = ["vacuum","heal","bomb"]`, rolled per normal kill (`balance.pickups.chances`).
- **Dash:** `dash()` uses charges (`p_dash_charges`, `dash_max_charges()`, `dash_cooldown()`), iframes, Lunge hits (`_lunge_hits`), and the Afterimage decoy (`decoy_pos/decoy_t/decoy_cd`, `_decoy_blast`). Enemies (not elites or the boss) within `decoy_radius` chase the decoy.
- **Territory hooks:** the dish clamp, `_spawn_point` avoids land and the outside, land slows enemies, `_update_territory` (trail and claims, DoT/erosion tick), `_on_claim` (40% max HP burst plus claim XP), `_pressure()` scales spawn budget and enemy HP with % infected.
- **Boss Rift** (`balance.rift`, World section "Boss Rift"): `rift_state` NONE/PENDING/OPEN/ACTIVE; `trigger_outbreak()` schedules it. ACTIVE (and the exit `rift_grace`) hand `step()` to `_step_rift()`, which runs only the player, Rift Power, the Carrier (`_update_rift_boss`: drift, spread, Seeker Phage `m_state` 0-3), weapons, bullets, shots and contact damage; everything else in the World is untouched (frozen). The arena is `RIFT_CENTER` (100000, 0); `_in_dish` clamps to it. The Carrier is a "boss" enemy identified by `rift_uid` (own colour/name/AI; `_process_dead` and `_contact_damage` special-case it). `_hurt` at 0 HP in the arena calls `_rift_exit("eject")` (1 HP, 2.5 s grace). Rift Powers: `rift_power`, `rift_power_lv`, `rp_kills` meter (kills outside the arena), `use_rift_power()`, multi-step effects in `_update_rift_power` (Barrage bolts are `b_ally` 3 = source "power"). Anything new that drives a World must cope with the rift (the bot's `_rift_move`).
- **Damage by source:** set `_src` (bolt/orbit/nova/chain/allies/towers/dash/land/bomb/outbreak/revive/other) around anything that calls `_damage`; it adds effective damage (capped at remaining HP) to `damage_by` and tracks `biggest_hit`/`biggest_src` (ignoring 1e6 instant kills). Bullets map `b_ally` 0/1/2 to bolt/allies/towers (`BULLET_SRC`). New damage code must set `_src`, or it shows as nothing on the results card.
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
- `SpriteBatch.add(pos, size, color, rot, aspect)`: `aspect` ≠ 1 stretches the rect (area kept); used for the hit squash from `e_knock`. Glows (`ShapeTextures.glow`, `_draw_glows`) sit under the batches. `mega_kill(at)` = flash + two outline rings (no big fills).
- Weapon colours switch to the evolution colour via `_wcolor()`.

### 5.4 UI (`main.gd`, `hud_overlay.gd`, `ui_kit.gd`, `icon_art.gd`)
- Screens are overlays from `UiKit.overlay()` (ColorRect + CenterContainer + VBox `col`), rebuilt on show with `UiKit.clear(col)`. `screen` is one of `menu | playing | levelup | chest | dead | results | paused`. `_set_screen()` toggles the HUD/view/pause button.
- **Input** (`_unhandled_input`): the UPGRADE button opens the picker; the DASH button or a second finger dashes; otherwise the touch starts the joystick (base locked; `juice.stick_follow` restores drag-along). Keys: WASD/arrows, Space = dash, E/Tab = upgrade.
- `_process` steps the world once per frame with dt clamped to 1/30 (no physics catch-up).
- Level-up (redesigned 2026-11-06): `_show_levelup` builds cards via `_upgrade_card` inside per-card slot Controls (`_card_slot`, sized deferred by `_fit_card`, so consecutive level-ups don't misplace them), `_slide_in`, `_pick_animated`; owned cards show now→next lines (`STAT_NAMES`, `_stat_lines`); "Later" keeps the same offers (`World._kept_offers`). Evolution hints come from `_evolution_hint()`.
- Glossy style: `UiKit.gloss` / `style_button(b, kind)`, `UiKit.display(label)` (Lilita One), `UiKit.card()`, `press_feedback`, `fade_in` / `reveal` / `stagger`. HUD drawn in `HudOverlay` (`_bar`, `_rrect`, `_text`, `_gloss_disc`, cached layers). Results: `_build_results`, `_stat_tile`.
- Audio: `Sfx.play(name, jitter, pitch)`; `Sfx.GROUP` shares one rate limit across variants (the six `Sfx.KILLS`). Main `_on_kill_streak(radius)` picks a random squelch; `_on_kills` handles the multikill thump and MEGA KILL; `_start_slowmo(secs, scale)` (boss kill, mega kill).
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
- **lab.json:** `genes` {first_clear[10] = 4..13, repeat_win 2, dev_grant}, `respec_gold`, `tuning`, `abilities` {id: {name, branch, color, desc, levels[{duration_s, kills}], ...}}, `repriced` / `retired` (old costs, refunded by `Profile.migrate_lab`), 4 `branches` {id, name, role, color, icon, nodes[{id, icon?, tier 1-7, name, label|desc, fmt, effects {stat: per level}, costs[], fork?, keystone?, ability?}]}; validated by `GameData._validate_lab`. Full Lab = 238 Genes.
- **meta.json** (split into 2× tiers at the same caps on 2026-11-05, Profile v6; full shop 29,496 gold): 15 entries `{id, name, stat, per_level, desc, fmt pct|flat, costs[]}`; costs must strictly increase (validated).
- **modes.json:** infection/swarm/nucleus/classic with overrides plus menu card fields.
- **balance.json `defense`** (Nucleus mode): nucleus hp/radius/damage taken, aggro_radius, pads, build_s, biomass rates, vents, breathers, max wave wait, respawn, per-wave enemy growth. **towers.json:** towers with per-level stats (`weapon` must be one World knows how to fire: `bolt` for now). **waves.json `defense.waves`:** duration, budget, enemies, vents, elites, boss.
- **difficulty.json:** Virulence ladder: name, gold/score per level, `hp_growth` 1.5 / `damage_growth` 1.22 (compounding), `ramp_scale` per mode (nucleus 0.55, infection 0.85), 10 `levels` {name, desc, mods}; mods are `GameData.VIRULENCE_MODS` (validated). Applied by `GameData.apply_virulence(apply_mode(data, mode), level)` in Main and in the sim (`--level N`).
- **online.json:** `score` weights; 5 `leaderboards` {id, name, mode, metric score|infected_pct|conversions|kills|time}; 21 `achievements` {id, name, desc, stat (a key of `Profile.flat()`), goal}; 3 are kill-streak ones (`best_streak` 100/250/500).

---

## 7. Balance state (bot, seeds 600-1100 × 8 = 48 runs per mode, no meta, Virulence 1)

| Mode | Win | p50 | Level p50 | Notes |
|---|---|---|---|---|
| Classic | 15% | 2:19-4:11 | 8-13 | After final minute, XP x0.7, level-up shockwave |
| Infection | 19% | 2:22-3:29 | 15-20 | Fastest levelling (~10 s per level-up) |
| Swarm | 15% | 2:17-4:40 | 10-13 | Allies ~25-30% of damage; damage taken x2.0; XP quad 0.27 |
| Nucleus | 40% | 2:55-6:06 | 9-14 | Shockwave helped it most |
| **Since 2026-11-06 (elite/boss HP floors)** | Classic 0%, Infection 0%, Swarm ~2%, Nucleus ~33% (V1, no meta) | | | The bot can't outlast a Mother Cell it can't burst; the table above is from before. Yousuf: "balancing seems fine for now" |
| V5, full shop, 24 runs seed 100 (after the evolution offer bias) | Classic 17% (p50 4:10, L22), Infection 4% (p50 2:38, L22) | | | PIPELINE 2026-11-06 |
| All shop upgrades maxed (`--meta`) | V1-2 ~100%; V3 72%, V4 44%, **V5 22%**, V6 11%, V8 0% (Classic) | | | The Virulence ramp; other modes in PIPELINE 2026-11-04 |

The bot win rate is a **sanity alarm**, not the target (±10-15 points is fine). Yousuf's real target: a good player's first win after about 3-5 runs with no upgrades; with the full shop, clear V3-4 and barely V5; with the future Lab + shop, V7-8 easily and V9-10 decently.

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
17. "Pause when the order fan is open" → done. He then won Swarm and Infection on his first try → bigger crowds from 2:30 + a FINAL MINUTE (faster germs, elites every 20 s, surge, warning, red timer); still too easy, and "level-ups every few seconds" → XP x0.7 (his "about 30%"); bot cap becomes only a sanity alarm.
18. Feel rounds (his picks from an idea list, two sets at a time): camera look-ahead + crowd zoom-out + zoom punches; gem hop, pickup chime ladder, XP bar glow; level-up shockwave (push, no damage); low-HP vignette + heartbeat; subtle hit-direction bloom; per-weapon cell animations (stackable, cheap); bigger evolved visuals; evolution moment v2 (1.9 s frozen charge/burst/banner, after "not big enough"); results highlights (damage per source) + gold fly-in v2 (after "buggy, looks bad": run total counts down, wallet counts up); animated Infection claim fill. He **rejected**: enemies-alive set (wobble/blink/spawn pop-in/per-type deaths/goo build-up), the HP ring, muzzle flashes, the living-dish background.
19. Kill streak: wanted it extremely satisfying, a stat + achievements, future hooks → see item 16 (tiers scaled to x500 because late-game kills are nearly continuous).
20. GitHub Pages deploys kept timing out → web builds moved to itch.io (his account, restricted page), pushed from the session with butler; dev gold tools added because the new host starts with an empty save.
21. Boss Rift (his design: rift after Outbreak, 1-HP ejection with a frozen grace, a power from your strongest weapon, a homing missile to bait into its owner) → built and tuned; "decent, figured it out after several failed attempts", then **shelved** from the existing modes (revisit bosses later).
22. Virulence 1-10 (his: fixed ladder, 10 levels, per mode, replayable older levels, no elite steps, full shop clears 3-4 / barely 5) → built; flavour modifiers alone did nothing to a maxed account, so a compounding HP/damage ramp was added.
23. Developer tools behind a code (1289, on-screen keypad) + "All Virulence levels" toggle.
24. The Lab + Abilities (his: Genes, 4 branches, cheap gold respec, V7-8 easy / V9-10 decent with everything; abilities like invisibility and time stop; one equipped via a separate Abilities menu; later a node to switch mid-run; abilities replace Strains) → **built 2026-11-05** (phase 1 Lab, phase 2 abilities).
12. Upgrades shop didn't scroll (only via the thin scroll bar) and was hard to read ("0/2") → `DragScroll` (drag anywhere, momentum, drags never count as taps) + `MetaShop`: tile grid with tier bars, prices and "can buy" badges, a detail popup per upgrade with NOW → NEXT in words and a big green UPGRADE button with sound, haptics and VFX.
25. Dash dealt thousands at high Virulence → dash family / abilities scale with in-run growth only (`_power_scale()` divides out Virulence); Lysis and Volatile fixed the same way.
26. Lab middle nodes just repeated shop stats → all new play-changing nodes (his picks), more nodes per branch; shop tiers split in two at the same caps (Profile v6); a balance report (`docs/BALANCE_REPORT.md`) and an account sim (`campaign_sim.gd`). Deferred by him: Swarm + full Lab too strong, Nucleus V10 wall.
27. Asked for a Play Store critic pass (not to implement) → `docs/LAUNCH_READINESS.md`. Co-op discussion → `docs/COOP_DESIGN.md` (post-launch).
28. Core pace discussion: keep enemy damage; make **elites and bosses much more dangerous without more damage** → elite affixes (charge/brood/volley/magnet), Mother Cell phases/slam/pull/spiral, lulls then surges, danger telegraphs.
29. "Bosses still die too quickly when evolved" → HP floors from `player_dps_estimate()` (elites ≥6 s, Mother Cell ≥30 s) + elite health bars. Bot V1 timed-mode wins fell to ~0%; options were offered, he hasn't asked to change it.
30. Evolution strength shop upgrades (4 × 12 tiers; base evolutions weaker, today's strength at ~50-60% of tiers) → built; then "whichever weapon's evolution tiers are higher shows up more at level-up, equal tiers = equal odds" → `World.offer_bias()`.
31. UI evaluation → his pick "glossy chunky" (Kenney font, then OFL allowed → Lilita One), done in 6 steps. Fixed on the way: jittery gold animation, broken Lab scrolling, level-up cards misplaced on a second consecutive level-up, "Later" re-rolling the cards.
32. "Kills not satisfying enough compared to other mobile games" → his picks from an idea list: CC0 sounds (2), hit feel (3), MEGA KILL (first idea of 6). Not picked yet: germ pop animations per type (1), carnage stains that build up (4), chain-reaction kills as a base rule (5), gem vacuum stream + cha-ching (6b).
33. "Balancing seems fine for now" (2026-11-06); early game a bit difficult → his idea for later: a "watch an ad for gold" button on the main menu (goes through `Ads`).

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
- `balance.json` `debug.show_perf` and `debug.dev_tools` (Settings → DEVELOPER → keypad code `debug.dev_password` (1289) → +10,000 gold, refund all permanent upgrades, "All Virulence levels" toggle = `settings.dev_all_virulence`, which unlocks every level in every mode without touching records/achievements; Profile.dev_grant_gold / refund_meta / dev_all_virulence) are on for playtests. **Turn both off for release builds.** `debug.invincible` must stay false.
- **No audio buses created at runtime** (`AudioServer.add_bus`): the web build plays audio through Web Audio "samples", which never connect runtime buses to the output, so every sound on them is silent (found 2026-11-03: output peak 0.45 → 0.0). `Sfx` sets volumes per player instead. Check web audio with Playwright by tapping the output with an `AnalyserNode` (see PIPELINE 2026-11-03).
- **`tools/build_assets.py`: append new sounds at the end of `build_sfx()`.** The noise generator is shared, so inserting a sound earlier silently changes every sound after it.
- Keep `docs/PIPELINE.md` dated entries appended at the end. Decisions go in `docs/DECISIONS.md` (newest last).

---

## 10. What's next (prioritised backlog)

**Next (2026-11-06):** nothing new is agreed. Ask Yousuf what he wants next, offering the items below.
1. **Kill feel playtest** (built 2026-11-06, `926f154`; nobody has heard the sounds yet, since the sandbox has no audio): are any of the new sounds too loud, quiet or annoying (6 squelch variants, multikill `thump`, elite `crunch`, `crit`, `hit` tap, `mega`/`bomb` explosion; volumes in `Sfx.VOLUME_DB`, gaps in `MIN_GAP_MS`)? Does the hit squash read on the phone (`juice.hit_squash` 0.3)? Is MEGA KILL too rare or too common (`juice.mega_kill_count` 25 in 0.3 s, 8 s cooldown; bot ~0-1 per run fresh, ~1 in Infection/Swarm, ~5 maxed)? **Kill-feel ideas he hasn't picked yet:** (a) germs swell then pop like water balloons, a different death per type (splitters tear, armoured ones crack, the Mother Cell bursts in stages); (b) carnage stains that build up on the dish over a run (measure WebGL cost first; long-lived low-detail stains with a higher cap is the safe version); (c) chain-reaction kills as a base rule (a germ that dies to heavy overkill splashes its neighbours; Volatile/Overkill as the big version; gameplay, so sim it); (d) gem vacuum as a stream with rising pitch and a "cha-ching" at the end. Note: in an earlier feel round (§8 item 18) he **rejected** per-type deaths and goo build-up, so mention that when offering (a)/(b).
2. **UI overhaul playtest** (steps 1-6 done 2026-11-06, "glossy chunky"): his notes on the level-up, HUD, results, menu art. Details of what was built: CLAUDE.md "UI look" and PIPELINE 2026-11-06 entries.
3. **Watch an ad for gold on the main menu** (his idea, 2026-11-06, for the slightly hard early game): a rewarded ad through `Ads` only, probably with a daily cap; not built.
4. **Elite/boss HP floors (2026-11-06)** made timed-mode V1 bot wins ~0% (the bot can't survive 3:50-5:00 with an un-burstable Mother Cell). He has since said "balancing seems fine for now", so leave it unless his playtests say otherwise. Options if needed: spawn her later (e.g. 4:20), lower `min_life_s`, or pay a big bonus / end the run early when she's killed. Tune threats via `enemies.json` boss (`hunt_mult`, `aim_every_s`, `slam_every_s`) and `waves.elites` (`hunt_mult`, affix numbers).
5. **Balance report 2026-11-05 (`docs/BALANCE_REPORT.md`).** Done: Genes per minute survived at V3+ and per-mode gold (Classic ×2, Nucleus ×1.8). **Deferred (Yousuf, deal with later):** (a) Swarm + full Lab wins 100% even at V10: measure with `--labx feed,clot,last_stand` (sustain nodes + allies soaking hits are the suspects), then tone down per mode; (b) Nucleus V10 is 0% even with everything: Nucleus-only Lab nodes (the planned "Specialisations" row) or a lower Nucleus `ramp_scale`. Also open: V6 (Thin membrane) and V9 (Virulent) are spike levels; the economy overshoots (a fresh account reaches V10 in ~40 runs in Classic/Swarm; a softer setting was offered, not chosen).
6. **Abilities playtest** (built 2026-11-05): do they feel like skill/utility? Are recharges (135-240 kills) right?
7. **Lab playtest**: are the Gene amounts and node costs fair? Do the forks feel like real choices? Use Settings → Developer "+50 Genes" to try it.

Done this session, for reference (details in PIPELINE): dash/ability/Lysis/Volatile scaling divides out Virulence (`_power_scale()`, `_vhp()`); Lab middle-node rework; shop tier split (Profile v6); elite affixes + Mother Cell threats + lulls/surges; HP floors + elite health bars; evolution-strength shop upgrades + offer bias; UI steps 1-6; kill feel.

**Awaiting his playtest notes** (ask when he's played):
- Virulence 1-10 (D-027): does each step feel fair? Is V2 (germs x1.5 HP) too big a jump without upgrades? Where does he get stuck with his upgrades?
- Feel rounds 1-3, the kill streak, the BUILD overlay, Swarm orders: mostly confirmed "fine"; watch for anything that gets annoying over long sessions (pickup chime ladder, heartbeat, camera look-ahead, crowd zoom-out).

**Agreed for later / deferred by him** (details in SPEC "Later" and ROADMAP):
- **Boss Rift / bosses**: shelved 2026-11-04 (D-026). Revisit later, maybe as its own mode, with more bosses and a reward pool. Don't delete the code.
- **Mode-specific Lab nodes** (Specialisations row).
- **Later abilities**: Fever Aura, Antigen Mark, Repulse, Hijack; a Lab node to switch abilities mid-run.
- **Streak-triggered upgrades** via `balance.streak.rewards` (hook built, empty).
- **Sacrifice order** (Swarm): parked; overlaps Outbreak.
- Swarm extras offered but not chosen: type roles per order, one Swarm card per order.
- Nucleus step 3: build/upgrade VFX, best-wave record + leaderboard/achievements, nucleus-repair ad, smoothing the wave 6-7 spike.
- Ideas never picked: Mutations (trade-off cards), Symptoms (timed dish events), combining Swarm + Infection (ROADMAP Step 3), organ chapters (Bloodstream/Lungs/Gut), Daily Outbreak (seeded + leaderboard), daily missions/cosmetics, more maps/evolutions, iOS.
- **Strains** are replaced by Lab abilities (D-029); the "one genome tree per strain" question is moot.

**Release track** (full checklist of known blockers and issues: `docs/LAUNCH_READINESS.md`, to re-assess near launch):
- **M3 release plumbing:** Android export to the Gradle build and AAB; AdMob plugin + `AdmobBackend` behind `Ads` (Google test IDs only in code; real IDs from CI secrets); Firebase Analytics behind `Analytics`; signed release via the `ANDROID_KEYSTORE_*` secrets (Yousuf must create them; SETUP §2). **Verify plugin versions support Godot 4.7 first.**
- **Play Games Services** as `PlayGamesBackend` behind `Online`: sign-in, Saved Games with `Profile.merge`, leaderboards from `data/online.json`, achievements. Yousuf creates the console entries.
- M4 store kit (icon, screenshots, 15 s clip, privacy policy, data safety), M5 closed test (12+ testers × 14 days), M6 release + small UA tests.
- Before release: `debug.show_perf` false, `debug.dev_tools` false, `debug.invincible` false.
- His account steps still open: keystore secrets, Play Console, AdMob, PSEB.

**Tech debt:**
- Territory grid 64 → 96 for smoother edges (check flood-fill cost on the phone).
- `main.gd` is ~1,900 lines; splitting screens into scripts would help (ask first; he prefers minimal changes).
- Hint entries for the shelved rift (`rift`, `rift_bait` in `data/hints.json`) never fire while it's off; harmless.

**Open questions for Yousuf:**
- Theme and final name ("Petri Panic" is a working title); decide before M4.
- Whether to auto-open the picker when many level-ups are banked (currently never, by his choice).
