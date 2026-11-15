# CrazyGames build plan (draft 2026-11-15, not started)

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

**A1. Separate "CrazyGames" export + cleanup** (small, data-first)
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

**A5. Store assets and submission** (mostly Yousuf; reusable for the Play Store)
- 3 covers: 1920x1080 (16:9), 800x1200 (2:3), 800x800 (1:1); only the title as text, no borders/icons/logos. These decide the CTR metric, so they're worth real effort.
- 2 trailers, 15-20 s, silent, no black bars or "Play now" text, starting on the cover: one 1080p 16:9 (landscape build), one 1080p 2:3 (portrait). Option: record bot runs with Godot Movie Maker, then edit.
- Page text: description, controls (desktop keys + mobile touch), tags (survivor, roguelite, io-like), mobile orientation **portrait**.
- His account steps: CrazyGames developer account, billing (Tipalti, or "Hold payments"), **read the developer terms** (revenue share, minimum age, exclusivity bonus: +50% for 2 months if not on other browser portals; ask whether the restricted itch playtest page counts).
- Preview the upload on crazygames.com/preview, then submit → Initial QA → Basic Launch.

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
| B1-B3 if invited | Claude | 1-2 sessions |

## Open questions for Yousuf
1. Developer terms: what revenue share, the minimum age, and is the exclusivity bonus worth taking the itch page down for?
2. A Skip button for Patient Zero on this build (recommended), or keep it unskippable?
3. Landscape text: decide from the A2 screenshots.
4. Covers: draw them himself, commission, or start from in-game renders?
