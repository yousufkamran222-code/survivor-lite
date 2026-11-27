# CrazyGames build plan (2026-11-27: **rejected at QA** ("overall quality does not yet meet the expectations"); **Phase Q (quality pass) in progress on branch `crazygames1`**; A6 SDK for later; Phase B only if invited)

Goal: ship Petri Panic on CrazyGames as a **parallel web launch** while the Play Store verification and 14-day closed test run. Play Store launch prep stays the priority; this fits into the waiting weeks.
Decisions so far (Yousuf, 2026-11-15): do both; **name stays "Petri Panic"**; on desktop the **dish widens to fill landscape** (no letterbox).
Requirements source: docs.crazygames.com (requirements/technical, gameplay, ads, account-integration, game-covers, sdk/*, resources/basic-launch-metrics), read 2026-11-15.

## How CrazyGames works (the short version)
1. **Basic Launch**: a small test audience for 7-21 days (ends at ≥7 days AND ≥500 plays, or after 21 days). **No ads, no revenue, SDK optional.**
2. They score **average playtime (target 10+ min), Day-1 retention (10-15%), conversion (≥80% play 1+ min), cover CTR** (scored for Basic Launches starting on/after 2026-11-23) against other games.
3. Good numbers → invite to **Full Launch**: SDK integration, second QA, global release, ads + revenue share.
So the work splits into **Phase A (Basic Launch build)** and **Phase B (Full Launch, only if invited)**.

## Current state vs. requirements
| Requirement | Today | Work |
|---|---|---|
| Initial download ≤ 20 MB (mobile homepage), loads < 10 s | ~15 MB gzipped (wasm 10.1 MB + pck 5.3 MB), no threads (no COOP/COEP needed) | none; keep an eye on it |
| ≤ 1,500 files, relative paths | ~8 files | none |
| Playable in **landscape on desktop**; mobile orientation set at submission | portrait only (720x1280, `canvas_items` + `expand`) | **biggest job** (A2) |
| Text legible at DPR 1 in 1280x720 / 1920x1080 / 800x450 frames | portrait canvas in a 720-high frame = ×0.56 text | A2 |
| No fullscreen button, avoid Escape and Ctrl/Cmd+W | Escape closes the Swarm order fan | A1 |
| No external/app-store links, no other portal's branding | itch-only page; none in game as far as known | A1 audit |
| Same physics at 60/144/165 Hz | one step per frame, dt clamped to 1/30, menu fps = display rate | A4 check + test |
| No dead buttons (Basic has no ads) | the stub ad backend grants rewards on web | A1: no-ads backend hides ad buttons |
| Guests can play, no external logins | no logins | none |
| Only CrazyGames ads (Full) | AdMob is Android-only | B1 backend |
| No revive offer on every death, never reward on ad error, no midgame + revive combo | revive max 1 per run, interstitial every 3 deaths | B1 tune |
| Cloud-safe saves (Full: Data module, 1 MB string values) | Profile JSON in `user://` (IndexedDB on web) | B2 backend |
| PEGI 12, English | yes | none |
| 3 covers + 2 silent trailers (16:9 and 2:3, 15-20 s) | none | A5 (reused for the Play Store) |

## Phase A: Basic Launch build (no SDK)

**A1. Separate "CrazyGames" export + cleanup** (**done 2026-11-15**, PIPELINE; Skip tutorial from A4 done with it)
- New export preset `CrazyGames` (Web, same filters as `Web`, custom feature `crazygames`), output `build/crazygames/` zipped for upload.
- `GameData.apply_crazygames_build()` (like `apply_store_build`): forces `debug.dev_tools/show_perf/invincible` off, merges a `balance.crazygames` block (overrides that apply only to this build; empty to start).
- `Ads`: a `NoAdsBackend` on this build (nothing ever ready), so revive, double gold, reroll and the "+75" menu chip are all hidden. **Check that every placement hides itself when no ad is ready** (and that no screen waits on an ad).
- Hide what doesn't apply: Settings → Developer, "Privacy options (ads)", any Quit button, leaderboard/achievement surfaces that would look broken (local Profile achievements are fine), itch/Play mentions, the build SHA label (or keep it small: harmless).
- Keys: replace Escape (Swarm orders fan) with right-click or tap outside; make sure the page doesn't scroll on Space/arrows/wheel and no context menu appears (`head_include`: `user-select:none`, `preventDefault` on those keys while the canvas has focus).
- CI: `crazygames.yml` (manual) builds the zip as an artifact; `tests/test_data.gd` checks the preset's feature tag and that this build forces debug flags off.

**A2. Landscape: widen the dish** (the big one; prototype first)
- Runtime switch on aspect ratio (`root.size_changed`): portrait keeps today's layouts exactly; **landscape** (width > height) gets landscape layouts. Handles CrazyGames resizing the frame and fullscreen mid-run. Mobile stays portrait (set at submission), so phones never see the landscape path.
- **Fairness rule:** the world area on screen stays the same as portrait (portrait shows 720x1280 world units; landscape shows ~1280x720, the same diagonal), via the camera zoom in `WorldView`. Enemies keep spawning off-screen (`perf.spawn_min_distance` 760 > the half-diagonal ~734), so **balance and the sims are unchanged**. Showing even more dish would need wider spawn distances, so that is a gameplay change and needs the sim (later, if wanted).
- **HUD** (`HudOverlay`): a landscape arrangement: top panel (the baked `BakedLayer`, 720 wide) centred or top-left, weapon strip under it, action buttons (UPGRADE, Outbreak, ability, DASH, orders) in the bottom-right corner, joystick hidden when using keys. Keep the draw-call budget (bake signature unchanged).
- **Menus/overlays** (menu carousel, mode picker, level-up, results, BUILD, shop, Lab, Style, Profile, missions, settings): first pass = today's 720-wide column centred, with the dish/menu background filling the sides; level-up cards and results laid out wider where it's cheap (3 cards side by side already fit).
- **Text size decision (measure first):** at a 1280x720 frame the logical 1280 height shrinks text to ×0.56. Step 1 is screenshots of every screen at 1280x720, 1920x1080 and 800x450 (Playwright + Chromium, `--use-angle=swiftshader`). If body text is under ~14 px real, raise the UI scale in landscape (logical height ~1000 instead of 1280, using `DragScroll` where a screen gets too tall). Decide from the screenshots.
- Tests: a layout test that builds each screen at 2276x1280 / 1280x720 logical sizes and checks nothing falls outside the viewport.

**A3. Desktop controls and prompts**
- Already there: WASD/arrows move, Space dash, E/Tab, F, R, Q, B, 1-4. Mouse drag works (touch emulation).
- Tutorial/coach/hint text and the controls page say "drag" or "tap"; on desktop (keyboard used, or no touch screen) show key names ("WASD to move", "SPACE to dash"). Data: a `desktop` text variant per beat in `onboarding.json`, picked by Main.
- Show the key next to each HUD button in landscape (small "SPACE", "E").

**A4. Web-portal fit checks**
- High refresh rate: run the World at dt 1/144 and 1/60 in a test and compare kill/damage rates and timings (things tied to frame counts such as `World.SEP_EVERY` separation are the suspects). Fix anything that isn't time-based.
- Patient Zero for portal players (playtime metric): add **Skip tutorial** after the first beats (their quality guideline: skippable onboarding) and check the 3-minute length. The bounce right after the prologue is the biggest risk to the 10-minute average.
- Chromebook (4 GB) smoothness: Graphics = Fast by default on web already; check a 1920x1080 fullscreen frame in the render bench.
- Sitelock: the build only runs on CrazyGames domains and localhost: test locally from `127.0.0.1`.

**A5. Store assets and submission** (covers + trailers + page text **made 2026-11-17**: `build/store_kit/`, `docs/CRAZYGAMES_SUBMISSION.md`; left for Yousuf: account, terms, upload)
- 3 covers: 1920x1080 (16:9), 800x1200 (2:3), 800x800 (1:1); only the title as text, no borders/icons/logos. These decide the CTR metric, so they're worth real effort.
- 2 trailers, 15-20 s, silent, no black bars or "Play now" text, starting on the cover: one 1080p 16:9 (landscape build), one 1080p 2:3 (portrait). Option: record bot runs with Godot Movie Maker, then edit.
- Page text: description, controls (desktop keys + mobile touch), tags (survivor, roguelite, io-like), mobile orientation **portrait**.
- His account steps: CrazyGames developer account, billing (Tipalti, or "Hold payments"), **read the developer terms** (revenue share, minimum age, exclusivity bonus: +50% for 2 months if not on other browser portals; ask whether the restricted itch playtest page counts).
- Preview the upload on crazygames.com/preview, then submit → Initial QA → Basic Launch.

**A6. Minimal SDK for the mobile homepage (agreed 2026-11-26, not started: Yousuf will say when)**
Found at upload: without the SDK the portal counts the **total uncompressed file size** (44.1 MB: `index.wasm` ~38 MB is the Godot engine, `index.pck` ~6 MB), and only games with an initial download **under 20 MB** can appear on the **mobile homepage** (the 50 MB hard limit passes). Compressed (gzip -9) the build is ~15 MB (wasm 9.6 + pck 5.5). With the SDK, the initial download is measured from the start of loading to the first `gameplayStart`; their docs don't say whether that is compressed bytes. He submitted without it (option A) so QA could start.
- **Do (B, agreed):** add the CrazyGames SDK in the CrazyGames preset only (no ads in Basic Launch): `loadingStart/Stop` and `gameplayStart/Stop` (run start/resume vs. menus, pause, level-up picker, results), behind a facade (rule 3), nothing else reads it. Upload as a **new version of the same game** and read the size the portal measures. This is also the first part of B1, so B1 later only adds ads.
- **If still ≥ 20 MB (C, decide then):** a slimmer engine: a custom Godot 4.7.2 web export template with 3D and unused modules disabled (scons `disable_3d=yes`, a `custom.py` profile / build-profile file), built in CI and used by the CrazyGames preset only. Several hours; check the 2D Compatibility renderer still draws everything the same (footage/screenshot compare) and re-run the tests.
- Keep watching the size: the 50 MB limit leaves ~6 MB of room for new assets while the SDK is absent.

## Phase Q: quality pass after the rejection (started 2026-11-27, branch `crazygames1`)
**What happened:** QA rejected the build on 2026-11-27 with the generic template; the only specific line was "The overall quality of the game does not yet meet the expectations of our platform". Yousuf replied asking for 1-2 lines of specifics and whether a resubmission after a major update is possible (no answer yet).
**Audit (2026-11-27):** the CrazyGames export played in Chromium at 1280x720 and 1920x1080 for the first ~60 s of game time (`tools/footage`-style Playwright capture: WASD in squares, E + click the first card, Space, Q). A portal reviewer meets **Patient Zero** first (loads in ~1 s), so the first minute is the tutorial. Findings, worst first:
1. **"I'm dying" from the start:** simple movement took HP 100 → 20 by 0:09; the hidden `hp_floor` 0.2 is below `juice.lowhp_frac` 0.3, so the red edge vignette + heartbeat stay on for the rest of the tutorial.
2. **Stop-start:** ~10 coach lines and 3 freezes (level-ups, DASH pause) in the first 35 s; it reads as a lesson, not a game.
3. **Empty screen:** a small cluster in the middle of a big dark dish, ~5-15 germs for the first 20 s. In landscape, ambient germs spawn on a 1000-1100 ring: just off the sides but ~520 units above/below the view (~6 s of walking), so the top and bottom stay empty.
4. **Level-up on desktop:** no keys to pick a card (mouse only); the coach line shows through on both sides of the card column; "Later (keep 1)" means nothing to a newcomer.
5. Small: a touch-joystick ghost is drawn as the move hint on desktop; the tagline "You are the infection." while you play the white cell shooting germs; HUD text small at 1280x720; an unexplained red enemy name ("GERM", "SPORE": what hit you) under the cell.
6. **Visual punch:** shots are small dots and kills are small next to the portal's new releases.
Not checked: sound, real fps (software rendering in the sandbox), the menu after the prologue.

**Rule for this phase:** fixes go behind the CrazyGames build (`balance.crazygames`, read by Main only when `crazygames`) unless they are plain bugs that are harmless everywhere (then noted below). Android/itch gameplay stays byte-identical; the sims (which never apply the CrazyGames block) are unchanged except where a landscape run is simulated with `--set`.

| Step | Fix | Where | Status |
|---|---|---|---|
| Q1 | Health in Patient Zero: `hp_floor` 0.35 (above `lowhp_frac`, so no permanent red edge/heartbeat), damage taken ×0.5, regen 2 HP/s | `crazygames.prologue.overrides` → `GameData.apply_prologue(d, cg)` | **done** (test `test_crazygames_prologue`) |
| Q2 | Fewer interruptions: silent `fire`/`gems`/`dodged` beats, shorter lines (per-beat overrides by id) | `crazygames.prologue.beats` → `GameData.prologue_beats(d, cg)` | **done**: first 35 s go from ~10 lines to ~7 |
| Q3 | Fuller screen: landscape spawns on a box just outside the view (`perf.spawn_box_x/_y`, 0 = the old ring) + a denser prologue (budget curve, beat spawn counts) | World `_spawn_point`, `crazygames.landscape.perf`, `crazygames.prologue` | prologue density **done** (with Q1/Q2: `waves_overrides.budget_curve`, more germs in move/fire/gems); spawn box todo (sim before/after) |
| Q4 | Level-up: 1-4 pick a card (all builds: plain keyboard support), key chips on the cards and "Pick later (E)" in landscape, E closes the picker; the coach line is hidden while any overlay is up (bug, all builds) | Main `_show_levelup`, `_unhandled_input`, `_set_screen` | todo |
| Q5 | WASD keycaps instead of the joystick ghost (landscape); tagline from `crazygames.tagline`; bigger landscape UI if every screen still fits (`landscape_ui_height`, checked with screenshots); no "what hit you" label in the CrazyGames prologue | HudOverlay, Main, balance | todo |
| Q6 | Visual punch (presentation only): bigger bolt sprites (`juice.bullet_scale`), bigger kill flash/burst, merged on this build only from `crazygames.presentation` | `GameData.apply_crazygames_build`, WorldView | todo |
| Q7 | Verify: tests, rebuild the export, re-run the 1280x720/1920x1080 capture and compare; then Yousuf plays it before any resubmission | tools | todo |

## Phase B: Full Launch (only if invited)
**B1. CrazyGames SDK behind our facades** (rule 3: no SDK calls outside `Ads`/`Online`/`Save`)
- Godot 4 addon (`crazysdk-godot-4`, Godot Asset Library beta store): pin a version, check its licence and Godot 4.7 support, excluded from the Android and itch presets.
- `CrazyAdsBackend` in `Ads`: rewarded (revive, double gold, reroll, menu gold) and midgame (between runs; SDK cooldown 3 min). Pause + mute on `ad_started`, resume on `ad_finished`/`ad_error`, **no reward on error/unfilled/adblock**, and the game stays fully playable with an adblocker.
- Ad-rule tuning in `balance.crazygames`: revive not offered on every death (e.g. not on the first death of a session, or only after 2:00), and no midgame ad in the same death flow as a revive offer.
- `gameplay_start/stop` from Main (run start/resume vs. menus, pause, level-up picker, results); `happy_time` on a win, evolution or MEGA KILL (sparingly); honour `muteAudio` from game settings.

**B2. Saves through the Data module**
- A Data-module backend in `Save`: the Profile JSON as one string value (check its size stays far under 1 MB), guest data local, syncs on CrazyGames login; same `Profile.from_dict` path, no format change. Select "Progress Save" at submission.
- Optional: auto-login with the CrazyGames account (username on the Profile screen); never our own login.

**B3.** Re-QA, then a weekly update rhythm (updates go live the same day). Watch their dashboard (playtime, D1, conversion) and feed it back into balance/onboarding the same way as phone playtests.

## Order and rough effort (at 6-8 h/week for him; build work done in cloud sessions)
| Step | Who | Size |
|---|---|---|
| Account, billing, read the terms | Yousuf | 1 h |
| A1 export + cleanup | Claude | small (1 session) |
| A2 prototype + screenshots → text-size decision | Claude, then Yousuf picks | 1 session |
| A2 HUD + screens in landscape | Claude | 1-2 sessions |
| A3 desktop prompts, A4 checks + Skip tutorial | Claude | 1 session |
| A5 covers, trailers, page text | Yousuf (with help: Movie Maker clips, cover drafts) | several hours |
| Submit → QA → Basic Launch (7-21 days) | Yousuf | waiting |
| A6 minimal SDK (mobile homepage), when he says | Claude | under 1 session (+ C: 1 session if needed) |
| B1-B3 if invited | Claude | 1-2 sessions |

## Open questions for Yousuf
1. Developer terms: what revenue share, the minimum age, and is the exclusivity bonus worth taking the itch page down for?
2. A Skip button for Patient Zero on this build (recommended), or keep it unskippable?
3. Landscape text: decide from the A2 screenshots.
4. Covers: draw them himself, commission, or start from in-game renders?
