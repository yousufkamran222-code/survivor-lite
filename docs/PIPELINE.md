# Development and release pipeline

## Who does what
| Claude Code (cloud) | Yousuf | GitHub Actions |
|---|---|---|
| Code, data tables, tests, tools | Playtests on phone, judges feel | Tests on every push and PR |
| Balance sims, asset generation | Account steps (Play, AdMob, keystore) | Web build to Pages on `main` |
| PRs with sim numbers | Merges PRs, art-direction calls | APK on demand and on `v*` tags |

## The daily loop (about 1 hour)
1. Open the Pages link on your phone and play 2-3 runs. Check that the build SHA at the bottom of the menu matches the latest merge.
2. Write short, specific notes: "Lancer dash unreadable", "too quiet before 1:00", "level-up every 5 s is too often at 2:00".
3. Paste the notes into a Claude Code session. Claude turns them into data or code changes, runs the tests and the sim, and opens a PR quoting before/after numbers.
4. Merge the PR. About 3 minutes later the new web build is live. Repeat.
5. Before any session where you judge **feel or performance**, and at every milestone, run **Actions → Android build → Run workflow**, then install the APK on both phones.

## Verification layers
| Layer | Catches | Where |
|---|---|---|
| `tests/` (headless, seeded) | Logic bugs: damage, XP, upgrades, spawns, revive, data references | Every push |
| `balance_sim.gd` (bot runs) | Difficulty spikes, broken upgrades, run length | Every push (4-run smoke), PRs (12+ runs) |
| Playwright screenshot of web build | UI layout, boot errors | In the cloud session, ad hoc |
| Web build on phone | Feel, readability, rough UX | Every merge |
| APK on 2 phones | Performance, touch latency, audio, ads, lifecycle | Milestones and feel sessions |

## Milestones
| # | Goal | Status |
|---|---|---|
| **M0** | Repo bootstrap: CLAUDE.md, CI, tests, sim, web build, AdService stub | **done** |
| **M1** | Core loop playable: 8 enemies, 11 upgrades, boss, level-ups, death, results, meta shop, stub ads, SFX | **done (first pass)** |
| M2 | Feel and balance pass from phone playtests. Low-end perf check on APK (60 fps at 170+ enemies confirmed on Yousuf's phone). Fun pass: dash, elites + chests, 4 evolutions, rare pickups (done, needs playtest). Pick the final theme and name. **The Lab** + Abilities done (2026-11-05). Elite/boss threats, HP floors, evolution-strength shop (2026-11-05/06). UI overhaul "glossy chunky" steps 1-6 + kill feel (2026-11-06), awaiting playtest. Balance "fine for now" (Yousuf, 2026-11-06) | **in progress** |
| M3 | Android release plumbing: Gradle build and AAB, AdMob plugin and `AdmobBackend` (test IDs), Firebase Analytics, signed release via secrets | |
| M4 | Store kit: icon, 4-5 screenshots, short 15 s gameplay capture, store text, privacy policy, data-safety form | |
| M5 | Closed test: upload the AAB, 12+ testers opted in for 14 days, fix bugs, iterate on telemetry | |
| M6 | Production release, then small paid UA tests ($50-100) to measure CPI, D1/D7 and ROAS | |

## Release calendar (compressed, critical path first)
The **14-day closed test** (if it applies to your account) is the long pole, so start the accounts on day 1.
| Day | Work |
|---|---|
| 1 | Accounts: Play Console ($25), AdMob, PSEB. Recruit testers. Enable Pages. Pick the theme |
| 2-6 | M2 feel and balance via daily phone playtests |
| 7-10 | M3: AAB, AdMob (test IDs), Firebase |
| 11-12 | M4 store kit, privacy policy, data safety |
| 13 | Upload to closed testing and send the link to testers |
| 14-27 | Tester clock: fix, polish, read telemetry |
| 28 | Apply for production and release |

## Release gates
- **Closed test → production:** no crash or ANR seen in a week, a median session of 2 runs or more, and every ad placement verified on a real device with test IDs.
- **Production → paid UA:** D1 ≥ 35%, D7 ≥ 10%, median session ≥ 6 min, and no single upgrade dominating sim win rates.

## Facts to verify (not yet confirmed)
- Whether the Play closed-test requirement (12 testers, 14 days) applies to your account type. Check Play Console when you register.
- That Pakistan is supported for Play merchant payouts before relying on IAP. AdMob payouts by wire are the safer path.
- The current Godot AdMob plugin (e.g. Poing Studios `godot-admob-android`) and Firebase plugin versions that support Godot 4.7. Check before M3.
- PSEB, tax and SBP export details with an accountant.

## Balance baseline (bot, 2026-11-01)
| | runs | p10 | p50 | p90 | win | boss kill | level p50 | kills | gold |
|---|---|---|---|---|---|---|---|---|---|
| no meta | 16 | 1:14-2:07 | ~3:05 | 5:00 | 31% | 13% | 10-13 | ~455 | ~85 |
| all meta (`--meta`, before early-game softening) | 8 | 5:00 | 5:00 | 5:00 | 100% | 13% | 16 | ~910 | ~170 |

Known bot bias: it flees the boss, so the boss kill rate is understated, and a human will engage it. Make the first M2 tuning decisions from phone playtests.

### 2026-11-01 performance pass
First phone web playtest: frame drops once enemies pile up behind a kiting player.
- Browser, Chromium software GL, 405x720, 160-175 enemies: **23-29 fps → 57-60 fps**.
- Sim step at 150+ enemies (`tools/sim/bench.gd`, desktop CPU): **1.76 ms → 0.72 ms**.
- Changes: batched sprite rendering (`SpriteBatch`), tiled background texture, enemy separation every 3rd frame per enemy, cached per-type stats and integer grid keys, one clamped sim step per frame (no physics catch-up spiral), and an on-screen perf readout (`debug.show_perf`).
- Rebalance after the change (tighter crowds made area weapons stronger): `hp_growth_per_min` 0.55 → 0.65. Bot, seeds 600/700 × 8 runs: before 25-38% win, p50 2:54-3:14; after 38-50% win, p50 3:03-5:00.

### 2026-11-01 fun pass (dash, elites, chests, evolutions, pickups)
Goal: give runs mid-goals and a build payoff instead of "circle while stats rise".
- Added dash (button, second-finger tap or Space), elites every 40 s (from 0:35) with chests, 4 evolutions (weapon Lv5 + paired passive, opened from a chest), rare pickups (vacuum, heal, bomb), off-screen arrows, toasts, and evolution hints on level-up cards.
- Snappier opening: bolt range 460 → 580, cooldown 0.75 → 0.55, opening spawn budget 1.6 → 2.4/s, pickup radius 105 → 125.
- Re-tuned for the stronger player: enemy HP growth 0.65 → 1.2/min, new `damage_growth_per_min` 0.3, gold per kill 0.08 → 0.05.
- Bot after (seeds 600/700/800 × 8, no meta): win 25-50% (~42%), p10 2:21-3:24, p50 3:32-5:00, level p50 11-20, ~3.1 chests and ~0.7 evolutions per run, boss killed ~38%. All meta: 88% win.
- Bot bias: it dashes with perfect reflexes, so humans will find it harder. Next tuning comes from the phone playtest.

### 2026-11-02 prototype 1: territory
Built per `docs/ROADMAP.md`: bounded dish, loop-claiming with flood fill, claim burst, land slow/DoT/buff, erosion, % infected, and a Classic/Territory menu toggle.
- Bot, territory on (seeds 600/700/800 × 8, no meta): win 13-38% (~30%), p10 2:08-2:55, p50 3:12-3:46, level p50 23-27, ~4.3 chests and ~1.1 evolutions per run, mean infected 6-10% (the bot's loops are small, so humans should claim far more).
- Perf: 0.80 ms per step at 150+ enemies (was 0.60).
- Open questions for the playtest: does claiming feel good while chased? Is erosion too fast? Should the grid be finer (64 → 96) for smoother edges?

### 2026-11-02 game modes, Spitter fix, territory tuning
- Modes: Infection (territory) and Classic, picked from the main menu. The upgrade shop moved to its own screen.
- Antibodies destroy enemy shots on contact.
- Infection tuning from the playtest (see ROADMAP). Bot, seeds 600/700/800 × 8:
  - before (prototype 1): win ~30%, p50 3:12-3:46, level 23-27, infected 6-10%, ~1.1 evolutions
  - after: win ~34% (0-63% by seed), p50 2:55-5:00, level 20-32, **infected 12-21%**, ~1 evolution; top killer: Lump (brute)
- Classic after the Spitter fix (seed 600 × 8): win 25%, p50 4:52, level 15.

### 2026-11-02 prototype 2: Swarm mode (conversion)
- Built per ROADMAP; see its Prototype 2 section for rules and numbers.
- Tuning: base chance 0.06 → 0.09 and ally lifetime 30 → 40 s. Before: win ~25%, peak allies 6-10. After: win ~25%, p50 4:22-5:00, peak allies 10-15.

### 2026-11-02 Swarm rework: bodyguard formation
- See ROADMAP Prototype 2 "Rework" for rules. Data: max_allies 20 → 12, ally_hp_mult 2 → 3, ally_damage_mult 1.2 → 2, plus new ring/feed keys.
- Fixed a bot bug: it treated allies as threats (this also biased the earlier Swarm numbers).
- Bot, seeds 600/700/800 × 8: before (roaming swarm, buggy bot) win ~25%, p50 4:22-5:00. After: win ~54%, p10 2:35-3:55, p50 5:00, level 15-17, peak allies 12-15. Control (conversion off): ~42%.

### 2026-11-03 playtest fixes: Swarm too easy, frame spikes, joystick
- Swarm "untouchable" with the swarm plus Antibodies: ally HP ×3 → ×2, damage ×2 → ×1.5, feed cap +150% → +75%, feed heal 15% → 8%, and Swarm gets its own XP curve (linear 4, quad 0.16). Bot, seeds 600/700/800 × 8: before ~54% win, p50 5:00, level 15-17; after ~42% win, p50 3:24-5:00, level 10-13.
- Frame spikes with heavy late-game effects at only ~80 enemies: the simulation was cheap (0.58 ms per step fully loaded, `bench.gd --loaded`). The cause was rendering, where screen-sized translucent ring fills (Fever Spike, vacuum, bomb) are heavy on phone fill rate. Big rings now draw only their outline, and damage numbers are capped at 12. Probe (xvfb, loaded Swarm build): worst frame ~30-35 ms → ~20-28 ms. The perf readout now also shows draw calls and live effects.
- Joystick: the base stays where you first touch (`juice.stick_follow` = false; true restores the drag-along base).

### 2026-11-03 banked level-ups and dash upgrades
- Level-ups no longer pause the game (`upgrades.bank_levelups`). They bank up behind an UPGRADE button with a count badge, a small reminder note appears on each level-up, and the picker has a "Later" option. Per Yousuf: banking only, no auto-open.
- Dash: base cooldown 3.2 → 2.0 s, charges, and 4 dash cards (Double Flagella, Lunge, Afterimage, Adrenaline).
- Bot (it opens banked picks immediately), Classic, seeds 600/700/800 × 8: before win ~34%, p50 2:56-5:00, level 11-16; after win ~29%, p50 3:25-4:43, level 12-20 (within noise; the 4 extra cards dilute the bot's random picks).

### 2026-11-03 deeper permanent upgrades
- `data/meta.json`: 6 upgrades / 22 tiers → 15 upgrades / 96 tiers (~17k gold total), including 4 dash upgrades and a Swarm one. The shop scrolls and shows current totals. Validation checks stats and that costs increase. Runs now start with full dash charges.
- New-player balance is unchanged (no meta). All meta maxed, Classic, seeds 600/700 × 8: before (old shop) 88-100% win; after 100% win, level 41. That's expected for a fully maxed account; harder difficulty tiers are the long-term answer.

### 2026-11-03 Afterimage nerf and upgrade polish
- Afterimage felt overpowered in play. Cause: with a 2 s dash and charges, a decoy could be up almost constantly. Fix: its own 6 s cooldown (4.5 s at Lv2), lure 2.0 → 1.5 s, radius 360 → 260 px, elites ignore it. The bot doesn't exploit decoys, so its numbers barely move (Classic 3 × 8: win 29% → 34%, within noise).
- Polish: `IconArt` vector icons for every upgrade, evolution and permanent upgrade (no image files). Level-up cards show an icon, level pips and a category-coloured border, with a staggered pop-in. Picking gives a coloured burst and a note. Level-ups flash the XP bar and pulse a ring. Chests spin through icons and land on the reward (evolutions get a star). The HUD has an owned-upgrades strip on the left edge, and the shop shows icons.

### 2026-11-03 progress tracking and main menu polish
- `Profile` (pure) replaces the flat save: lifetime stats (kills per enemy type, time played, evolutions found, ...), per-mode records, 18 achievements (`data/online.json`), and `merge()` for future cloud sync. `Save` stores it as versioned JSON (`user://profile.json`) with an atomic write and a `.bak` fallback, and imports the old `save.cfg` once. A test caught a real bug: `DirAccess.copy` with bare file names failed, so no backup was ever written. It now uses `copy_absolute`.
- `Online` facade + `StubOnlineBackend`: leaderboards (5, by score/infected %/conversions), achievements and cloud save API. Play Games plugs in later as another backend.
- Run score (`data/online.json` score weights) on the results screen, with "NEW BEST!" and newly unlocked achievements.
- Main menu redesign: animated dish background with a hero cell, outlined title and tagline, gold pill, mode cards with icons and per-mode bests, pulsing PLAY, and icon tiles for Upgrades/Profile/Sound. New Profile screen: lifetime stats, best runs, achievements with progress bars.

### 2026-11-02 upgrades shop redesign (Yousuf: "doesn't scroll, hard to read")
- **Scrolling:** the shop's buttons swallowed the press, so the list only moved via the thin scroll bar. New `DragScroll` (scripts/ui/drag_scroll.gd): drag anywhere to scroll (finger or mouse) with momentum; a press that turns into a drag never counts as a tap. Also used on the Profile screen (its achievement bars now ignore input so they don't block the drag).
- **Readability:** `MetaShop` (scripts/ui/meta_shop.gd) replaces the text-button list with a 3-column grid of tiles: big icon, name, a segmented tier bar, the price with a coin (greyed when you can't afford it), "MAXED" in gold, and a pulsing green badge plus green border when you can buy the next level.
- **Detail popup per upgrade:** icon on a glowing halo, description, tier bar and "Level 3 of 10", **NOW → NEXT** in words ("+30 max HP" → "+40 max HP", from the new `label` field in `data/meta.json`), and a big green 3D UPGRADE button with the price. On buy: new `upgrade` chime (pitch climbs per level), haptic tick, particle burst and rings, the icon punches, the new segment flashes, the gold counter ticks down; the final tier gets a gold burst, the evolve sound and a "MAXED!" stamp. Can't afford: grey button saying "Need N more gold"; tapping it plays a soft `deny` sound and shakes. Tap outside or X to close.
- Logic: purchases moved into `Profile.buy_meta()` (tested), `Progression.meta_effect_text()` (tested), `GameData.validate()` requires a `label` per permanent upgrade. Save format unchanged. 94 tests.

### 2026-11-02 menu/web performance pass (Yousuf: "constant 45 fps on web, menus jittery")
- Measured (xvfb, relative): no gameplay regression from the shop change (fight 18.2 → 16.9 ms, ~56 draw calls). But the **menu cost more than a fight** (119 draw calls) and the new shop 277.
- `MenuBackground`: every circle is now one tinted disc texture, so they batch (menu 119 → 65 draw calls). `TierBar` uses plain rects instead of rounded style boxes (shop 277 → 150).
- **Web only:** Godot renders the canvas at the phone's full devicePixelRatio (≈1236×2745 on a 3× phone, 2.6-3× more pixels than the 720 layout needs, plus the browser's compositing copy). `export_presets.cfg` `head_include` now caps devicePixelRatio at 2 (824×1830, still sharper than 720). Playwright, 3× phone, CPU-rendered: menu 6.4 → 12.2 fps (relative). Touch mapping, swipe-scroll and taps verified in the exported build. The APK is unaffected.
- Shop tiles now show what one level gives ("+4% damage") under the name.

### 2026-11-02 Nucleus mode (tower defence), step 1
- New mode "Nucleus" (plan: `docs/ROADMAP.md` Prototype 3, D-013). Defend a central nucleus for 12 waves; germs come from rim vents and switch to you when close; kills give biomass; stand on one of 6 pads to build/upgrade a Bolt Spire (3 levels); you respawn after 5 s; only the nucleus falling ends the run.
- Data: `balance.defense`, `data/towers.json` (new, validated), `waves.defense.waves` (12 waves; weights/groups from `waves.pool`), mode entry + menu card + leaderboard. "Adaptable" achievement goal 3 → 4 (now 4 modes).
- Code: World (nucleus, aggro targeting, pads/towers, wave state machine, biomass, respawn, per-wave enemy scaling; the dish clamp no longer needs territory), SpawnDirector wave mode (+ fix: a wave could stay "spawning" forever when the leftover budget couldn't buy the already-picked enemy; regression test), bot, sim fields (waves cleared, towers, nucleus left), WorldView (rim, nucleus, pads, towers, vents, fx), HUD, Main (events, results, no revive in this mode).
- Bot sims: see ROADMAP "Step 1 as built" (~30% win, bimodal at wave 6-7). Classic/Infection unchanged (identical seeded results before/after). 110 tests.

### 2026-11-02 Nucleus mode, step 2
- Yousuf's step-1 verdict: "feels nice". Step 2: Antibody Post, Fever Node (slow) and Spark Coil towers; tower-pick popup; 3-2-1 countdown, boss warning and longer pre-boss breather; win screen with COLLECT or KEEP GOING into endless Free Mode. Details and sim numbers in ROADMAP "Step 2 as built". 115 tests.

### 2026-11-02 Nucleus step-2 playtest fixes
- Non-pausing tower bar replaces the pick popup; stronger towers that grow per wave; harder waves; Free Mode compounds. Sim `--free` flag. Numbers in ROADMAP "Step 2 playtest → changes". 116 tests.

### 2026-11-02 Polish Phase 0: on-device benchmark
- Hidden benchmark (tap the build label 5 times; F9 on desktop): a fixed 45 s heavy Classic fight that ends with one pasteable line (fps, avg/p95/worst frame ms, % hitches, sim/view/HUD ms, draw calls, refresh rate). Perf readout v2. `tools/sim/bench_render.gd` for desktop comparisons. Baseline and findings in `docs/POLISH_PLAN.md` Phase 0. 120 tests.

### 2026-11-03 Polish Phase 1, chunk 1: HUD layers, icon atlas, menu frame cap
- Yousuf's phone baseline: APK 87.7 fps on a 120 Hz screen (HUD 1.94 ms, dc 104), web 48.1 fps. Changes: cached HUD layers, baked icon atlas for the HUD strip, menu/pause frame caps. Desktop bench 71-75 → 87 fps, HUD 0.40 → ~0.11 ms, dc ~100 → ~54. Details in `docs/POLISH_PLAN.md`.

### 2026-11-03 Polish Phase 1, chunk 2: separation and damage numbers
- Phone after chunk 1: APK 87.7 → 117.4 fps (120 Hz), hitches 18.6% → 1.4%; web 48 → 56 fps. Chunk 2: time-based enemy separation (sims identical; sim step 1.14 → 0.63 ms in bench.gd), damage numbers from a baked digit atlas, benchmark v2 counts sprite batches in "view". A 2x2 separation search was rejected (Classic bot wins 33% → 54%). Details in `docs/POLISH_PLAN.md`.

### 2026-11-03 Polish Phase 2: combat feel
- Hit pulse + sparks, merging/popping/gold damage numbers, kill rings, floor goo splats, kill-sound pitch ladder with a second variant, elite hit-stop + gold shower, boss slow-mo, smooth shake, cosmetic "x25" streak. Presentation only (balance sims unchanged). Details in `docs/POLISH_PLAN.md` Phase 2.

### 2026-11-03 Polish Phase 3: the player cell
- Eased movement (accel 0.07 s / decel 0.09 s), rescaled stick response, a new generated cell (rim, organelles, cilia, squash/stretch, breathing, hurt squish, nucleus that leads turns), joystick direction marker. Sims: no real balance shift (6 seeds × 8, ≈36% vs 44%, noise). Details in `docs/POLISH_PLAN.md` Phase 3.

### 2026-11-03 XP gem cap fix (Yousuf: "around level 20 enemies weren't dropping XP")
- Real bug: at the 120-gem cap (`xp.max_gems`), new XP merged into a **random** gem, often far off-screen, so nearby kills dropped nothing visible. Infection sat at the cap 12% of a bot run, with 73% of uncollected XP far off-screen at the end. Now the gem farthest from the player folds into its nearest neighbour and the new gem drops where the germ died (no XP lost; the random draw is kept so the RNG sequence is unchanged). Regression test added.
- Also normal: each level needs more XP (level 20 needs ~100-140 XP vs ~10 early).
- Rejected first try: merging into the gem nearest the kill.
- Bot sims, Infection × 8, seeds 600/700/900/1000/1100: before 25/38/38/25/38% (≈33%) → after 13/13/25/13/0% (≈13%); p50 roughly unchanged (164-190 s vs 166-222 s), level 19-22 vs 18-24. Likely the greedy bot now runs into crowds for gems that used to vanish. Humans get correctly placed XP; watch Infection difficulty in the next playtest.

### 2026-11-03 Polish Phase 4: music and settings
- Generated music (menu loop; run loop in two synced layers, the drive layer fading in with intensity), Music/SFX buses with ducking, and a Settings screen (volumes, vibration, shake, frame rate, FPS readout) from the menu and pause. Details in `docs/POLISH_PLAN.md` Phase 4.

### 2026-11-03 Web audio fix; music direction
- Yousuf: no sound at all on web since the music build. Cause: the "Music"/"SFX" buses were created at runtime, and the web build's Web Audio sample path never connects runtime buses to the output. Verified in Chromium by routing the output through an `AnalyserNode`: peak 0.45 (before) → 0.0000 (broken) → 0.4548 (fixed). Fix: no extra buses; `Sfx` applies the Music/Effects volumes per player.
- Feedback on the generated music: "trash". Agreed: hand-synthesised melodic music won't reach the quality of composed tracks. Next: CC0 tracks from OpenGameArt (FreePD has shut down), chosen by Yousuf.

### 2026-11-03 Real music: Juhani Junkala, "5 Chiptunes (Action)" (CC0)
- Yousuf loved this pack (not "4 Chiptunes"). The WAVs (50 MB) re-encoded to OGG Vorbis q3 (4.1 MB) in `assets/raw/juhani_junkala_action_chiptunes/` with the pack's `INFO.txt` (CC0) and a MANIFEST row. Every track plays at full level from first to last sample (made as loops), so each loops whole (`loop=true` on import).
- Menu: Title Screen. Runs: a random Level 1-3; while a boss is alive, a 1.5 s cross-fade to a different level track and back. Win results: Ending. Generated music removed.
- Verified in Chromium (AnalyserNode on the output): menu music peak 0.43 with no taps; a run with effects 0.69.

### 2026-11-03 Phase 4 UI: transitions, restyled screens, counting results
- Overlay reveals and screen cross-fades, button press squash, restyled Profile (`ProfileScreen`), level-up cards, chest reveal and results with count-ups. Details in `docs/POLISH_PLAN.md` Phase 4.

### 2026-11-03 Enemy telegraphs, first-run hints, Profile scroll fix
- Lancer dash lanes, Spitter charge glow, Mother Cell burst ring; one-time hints from `data/hints.json` (time or event triggered, Settings can reset). Profile panels now pass drags to the scroll list (Yousuf: it only scrolled from the gaps). 122 tests. Details in `docs/POLISH_PLAN.md` Phase 4.

### 2026-11-03 Card + permanent upgrade audit and fixes (Yousuf: "a bit buggy/confused")
- Audit: every stat fed by both a card and a permanent upgrade, measured in-game. Charges (up to 4), damage, haste, HP, pickup range and projectiles stacked correctly. Three dash problems fixed:
  1. **Adrenaline Lv3 could do nothing:** card + permanent cooldown cuts were added and hit the 0.4x floor (full Flagella Training: Lv2 and Lv3 both 0.80 s). They now multiply (floor 0.3x): every level helps; full permanent + Lv3 ≈ 0.77 s. Same as before without permanent upgrades.
  2. **Afterimage cooldown:** Ghost Trail's half-levels counted toward the card's Lv2 cooldown (card Lv1 gave 4.5 s while its text said 6 s). Only the card's own Lv2 shortens it now; Ghost Trail grows the burst.
  3. **Wording:** Lunge/Afterimage Lv1 text now leads with the boost ("+20 dash damage: ...", "Decoy burst +100%: ..."), and level-up cards show **BOOST** instead of NEW when a permanent upgrade already gives that effect.
- Sims: Classic, no permanent upgrades, seed 600 × 6: identical before/after (50% win, p50 5:00, level 18); all permanent upgrades maxed, seeds 600/700 × 6: 100% win, level 41 both before and after. Regression tests added. 124 tests.

### 2026-11-03 Volatile, Outbreak meter, UPGRADE pill
- **Volatile** (dash card, 3 levels, `requires_stat: dash_damage`): germs the dash kills burst for (15% + 15%/level) of their max HP in a 50 + 20/level px radius; burst kills chain up to 2 generations. Scope: 16 shared cards (5 dash).
- **Outbreak meter** (`balance.outbreak`, all modes): kills fill it (180 kills; elite 15%, boss 50%), tap the button above DASH (or Q) for a 5 s frenzy: weapons x1.6 speed, all damage x1.25; the meter can't fill during it. Bot triggers it when crowded. A test caught a float bug (120 x 1/120 never reached 1.0).
- **UPGRADE** is now a top-right pill beside pause; Nucleus tower bar and hint banner moved up; streak counter lower.
- Classic bot sims, seeds 600/700/800 x 8: before 50/25/38% (p10 2:39-2:58, p50 4:02-5:00, level 14-15); first tuning (120 kills, 6 s, x1.8) 38/75/63%; final (180 kills, 5 s, x1.6) 63/25/25% (~38%, p50 3:15-5:00, level 17-19). Benchmark v3 (the bot uses Outbreak). 127 tests; a fragile test now checks elites were *met*, not killed.

### 2026-11-03 Outbreak fires bomb + vacuum + heal; UPGRADE in the right column
- Yousuf: Outbreak "too underpowered, especially early"; his idea: fire all three rare pickups. Chosen: bomb + vacuum + heal at once, then a 4 s frenzy (x1.6 weapons, x1.25 damage), every 250 kills. Outbreak's bomb and vacuum are local (`outbreak.bomb_radius` 380, `vacuum_radius` 700; the pickups themselves keep 720 / whole map). Announced as one burst (no three separate toasts). `outbreak.pickups` is validated.
- UPGRADE is now a bigger round button in the right column above Outbreak and DASH (the top-right pill was "too small and too at the top"); the Nucleus tower bar and hint banner moved left/narrowed to keep that column clear.
- **Balance, Classic bot, seeds 600/700/800 x 8 (win | level):** before (frenzy only) 63/25/25% (~38%) | 17-19; pickups+frenzy, 200 kills, full-screen bomb/vacuum 88/63/63% | 27-34; 300 kills 75/75/75% | 32-34; local vacuum 700, 250 kills 88/75/63% | 25-34; no vacuum 88/63/75% | 23-31; **local bomb 380 (shipped) 63/100/88% (~83%) | 22-30**; no heal 63/75/50% | 22-25. Any version works as an extra life the bot fires at the perfect moment. Open question for Yousuf: keep and raise difficulty elsewhere, or tone Outbreak down. 128 tests.

### 2026-11-03 Outbreak back to frenzy-only (interim)
- Yousuf: "nerf this thing to the ground"; the pickup version is out. Data only: `outbreak.pickups` [] , 180 kills, 5 s frenzy (x1.6 weapons, x1.25 damage): the config measured at ~38% Classic bot wins (63/25/25%, level 17-19). The pickup mechanism stays in code (tested) but unused. Next: design an *active* Outbreak (creates an opportunity the player must exploit, like the dash) instead of a panic button.

### 2026-11-03 Outbreak = Plague Trail (D-017)
- Tap a full Outbreak meter (180 kills): for 6 s the player leaves a violet toxic trail (points every 22 px, fading over 3 s). Germs within 30 px of it are infected for 3 s and lose 35% of their max HP per second (elites x0.2, bosses x0.05); an infected germ that dies infects germs within 60 px. Checked 10x a second; trail drawn as one sprite batch; infected germs tint violet (plague ticks don't white-flash). The frenzy's weapon speed and damage are set to 1.0 (neutral). Violet because every germ colour family except violet is taken.
- Boss Rift idea recorded in SPEC "Later" and the handoff backlog.
- **Yousuf's constraint: Classic bot wins must stay at or under 40-45%.** Classic bot, x 8 runs: before (frenzy) 63/25/25% (~38%) on seeds 600/700/800; Plague 0.25 HP/s 25/25/25%; **Plague 0.35 HP/s (shipped) 38/13/0% on 600/700/800 and 13/38/25% on 900/1000/1100: 21% over 48 runs**, p50 2:47-4:13, level 9-23. The bot doesn't herd germs into the trail, so humans get more out of it. 130 tests.

### 2026-11-03 Outbreak = Frenzy v2 (Yousuf's design), gold counter, per-mode difficulty
- Yousuf: Plague Trail "too gimmicky" (enemies die before it matters). His design: a ~5 s frenzy with the original buffs (weapons x1.6, damage x1.25), plus **half damage taken**, **triple gold from kills** (`World.frenzy_kills`, `bonus_gold_kills()`, `Progression.run_gold(..., bonus_kills)`), **XP x1.5**. Plague Trail switched off in data (`outbreak.plague_trail` false; code and tests kept). Meter: 300 kills.
- **Gold counter** on the HUD next to the kills (`World.run_gold_now()`, same maths as the results screen). Note: a kill is 0.05 gold, so the frenzy's triple gold adds only a few gold per frenzy.
- **Key finding:** Classic was already above Yousuf's 40-45% cap *without* Outbreak: 50% over 48 runs (seeds 600-1100 x 8; earlier "38%" figures came from 24 runs and were noise). Frenzy at 180 kills: 59%; 300 kills: 52%; 300 kills + 4 s: 56%.
- **Per-mode difficulty** (`balance.difficulty`: `enemy_hp_mult`, `damage_taken_mult` (player only), set via `modes.json`): Classic enemy HP x1.2 -> **40%** (38/38/50/38/50/25, p50 3:31-5:00, level 15-17). Swarm: HP x1.2 47%, x1.3 56% (allies inherit enemy HP), convert 7% 56%, **damage taken x1.3 -> 38%** (25/50/38/38, level 11-23). Infection 25% and Nucleus 38% (2 seeds x 8) without knobs. 132 tests.

### 2026-11-03 Outbreak gold blast (D-019)
- Replaces x3 gold (Yousuf's idea): triggering Outbreak sends a no-damage 380 px gold ring; germs inside are gilded (gold tint, `World.e_gild`) and pay `outbreak.gild_gold` 0.5 each when killed (vs 0.05), with a coin sparkle + pickup tick. Toast "OUTBREAK! N GILDED". `gold_mult` set to 1.0.
- Bot, Classic seeds 600/700 x 8: survival unchanged (38% win, p50 4:16 / 4:06, level 15). Mean bot gold seed 600: 92.6 (x3) -> 116.6 (gild). 133 tests.

### 2026-11-03 Swarm orders, ally scaling, Outbreak boosts the swarm (D-020)
- Yousuf: the swarm is "kinda useless". Measured with a new sim stat (`mean_ally_damage_share`): allies dealt 2.5% of all damage. Fixes: ally damage scales with enemy HP and your might; a fan-out **order menu** (Guard / Hunt / Harvest, his idea) left of Outbreak; Outbreak's frenzy also boosts allies x1.5. Details and the tuning path in ROADMAP Prototype 2 "Orders rework".
- **Swarm bot, seeds 600-1100 x 8 (48 runs): before 48% win, p10 2:19-3:38, p50 3:56-5:00, p90 5:00, level p50 11-23, ally share 2.5% → after 40% win, p10 1:20-2:30, p50 2:38-5:00, p90 2:47-5:00, level p50 14-30, ally share 22%.** Same settings without conversions: 9% (the swarm is worth +31 points; it was ~+8). Data: `conversion.ally_damage_mult` 2.0, Swarm `damage_taken_mult` 2.0, Swarm XP quad 0.22. Watch on the phone: damage taken x2 is steep, so lean on Guard when hurt.
- Classic, Nucleus and Infection sims byte-identical before/after (seed 600 x 6). Bench (`--mode swarm --loaded`, ~20 allies): Guard 0.48, Hunt 0.49, Harvest 0.53 ms/step.
- Tools: sim `--order guard|hunt|harvest` (bot keeps one order) and `--set key.path=value,...` (tuning overrides without editing data); bench `--order`. New sim fields: `mean_ally_damage_share`, `mean_gems_harvested`, `mean_order_changes`. Analytics `swarm_order`. One new hint (first conversion). 146 tests.

### 2026-11-03 Swarm order fan pauses the run
- Yousuf ("really love these changes"): pause while the fan is open. Main stops stepping while `hud.orders_open`; the field dims with "SWARM ORDERS / Paused"; tap an order to switch and resume, tap anywhere else (or Esc / Android Back) to resume without switching; other keys are ignored while it's open. The 3 s auto-close is gone. No sim change (the sim never opens the fan). 146 tests.

### 2026-11-03 Harder, more satisfying late game: bigger crowds + final minute (D-021)
- Yousuf beat Swarm and Infection on his first try with no permanent upgrades (one revive each; he'd have lost without it). Target: a good player's first win after about 3-5 runs. The bot cap is now only a sanity alarm (±10-15 points is fine).
- Finding: in Classic the 170 cap is full from 1:00 (the bot drags its crowd), in Infection/Swarm almost never. More budget alone made the bot *stronger* (more kills, more XP: Classic 40%, Infection 36%, Swarm 44%), so the final minute also needed real bite (not HP sponges).
- Data: budget curve x1.25-1.3 from 2:30 and a surge from 4:00 (`waves.budget_curve` ... 240: 24, 300: 30); enemy damage growth 0.3 → 0.4/min; **final minute** (`waves.final_minute_s` 240): germs x1.15 speed (`final_speed_mult`), elites every 20 s (`elites.final_from_s`/`final_every_s`), FINAL MINUTE warning (toast, boss sound, shake, red timer); Swarm XP quad 0.22 → 0.27 (Harvest feeds lots of XP). Boss bar moved below the SWARM/INFECTED readout (they overlapped).
- **Bot, seeds 600-1100 x 8 (48 runs per mode), before → after:**
  - Classic: win 40% → 27%, p10 2:22-3:05 → 2:18-3:08, p50 3:31-5:00 → 2:56-5:00, p90 5:00 → 4:44-5:00, level 15-17 → 12-18
  - Infection: win 31% → 27%, p10 1:56-3:07 → 1:56-2:41, p50 2:48-5:00 → 2:31-3:42, p90 5:00 → 2:59-5:00, level 20-34 → 20-26
  - Swarm: win 40% → 27%, p10 1:19-2:30 → 1:08-2:18, p50 2:37-5:00 → 2:26-5:00, p90 2:47-5:00 → 3:26-5:00, level 14-30 → 13-32
  - Nucleus: byte-identical (wave mode; no final minute). Peak enemies unchanged (~210).
- Sim `--set` now also takes `waves.*` keys. 150 tests.

### 2026-11-04 Slower level-ups: XP x0.7 in every mode (D-022)
- Yousuf: still won Swarm and Infection on the first try; damage feels fine, but "a new level-up every few seconds". Fix: `balance.xp.gain_mult` 0.7 (all gems and Infection claim XP, every mode; stacks with Growth/xp_gain and the Outbreak x1.5). New sim stats: `mean_sec_per_level`, `mean_levels_by_2min`.
- **Bot, seeds 600-1100 x 8 (48 runs per mode), before → after:**
  - Classic: win 27% → 19%, p10 2:18-3:08 → 2:19-2:50, p50 2:56-5:00 → 4:11-4:42, p90 4:44-5:00 → 4:42-5:00, level p50 12-18 → 8-14; levels by 2:00 7.0 → 5.2
  - Infection: win 27% → 21%, p10 1:56-2:41 → 1:50-2:19, p50 2:31-3:42 → 2:14-5:00, p90 2:59-5:00 → 2:46-5:00, level p50 20-26 → 15-33; levels by 2:00 14.3 → 10.8
  - Swarm: win 27% → 15%, p10 1:08-2:18 → 1:29-2:17, p50 2:26-5:00 → 2:17-3:44, p90 3:26-5:00 → 3:23-5:00, level p50 13-32 → 9-12; levels by 2:00 9.6 → 6.7
  - Nucleus: win 32% → 31%, p50 2:22-5:59 → 2:24-6:09, level p50 9-17 → 8-14; levels by 2:00 7.0 → 5.4
- Swarm drops the most because its own steeper curve (quad 0.27, from the final-minute pass) stacks with the cut; if it feels slow, revert that to 0.22 first. 151 tests.

### 2026-11-04 Kill/number juice v3 and the BUILD overlay
- Damage numbers arc and fall, pop springily, colour by hit size, and the killing blow turns hot pink; kills flash white and burst harder; 6+ kills in a frame shake and ring. The unreadable owned-upgrade strip is now a BUILD button that opens a paused overlay of everything you own (level, tier bar, effect, evolution path). Details and costs in `docs/POLISH_PLAN.md` "Kill and damage-number juice v3". Presentation only: no balance change. 152 tests.

### 2026-11-04 Kill streak (D-023)
- Yousuf: a kill-streak counter that's extremely satisfying at high numbers, the best streak as a stat with achievements, ready for future streak-triggered upgrades/abilities.
- **World** owns the streak (`balance.streak`: 1.0 s window, milestones 25/50/100/150/250/350/500 then every 250, 6 named tiers): `streak`, `streak_t` (game time, so pauses and the order fan don't break it), `best_streak`, events `streak` / `streak_end`. **Hook:** `balance.streak.rewards` [{at, pickup | outbreak}], applied after the kill pass, validated, empty by default (so no balance change; sims byte-identical in all 4 modes).
- **HUD:** big right-aligned "x123" below the toasts: punches and jitters on every kill (harder in higher tiers), grows roughly with log(streak), tier colour (the top tier shimmers), tier name and a draining timer bar; milestones swell the tier name and ring it, with a chime climbing per tier, haptics and shake; a broken streak floats away. NEW BEST STREAK! once per run when you pass your lifetime best (≥25). The kill-sound pitch ladder now follows World's streak.
- **Progress:** `best_streak` in the run summary, Profile stats and per-mode records (**Profile.VERSION 2 → 3**; old saves load it as 0; merge keeps the max), results and Profile screens, achievements Chain Reaction (100), Plague Bearer (250), Extinction Event (500). Sim reports `best_streak_p50/p90` (bot p50: Classic 66, Swarm 149, Nucleus 242, Infection 431: kills in the dish are nearly continuous; 0.6 s still gave 175, so the tiers were scaled up instead).
- Bug caught by a test: JSON milestones are floats, so `Array.has(25)` never matched. 159 tests.

### 2026-11-04 Satisfaction round 1: camera + XP loop
- Camera look-ahead, crowd zoom-out, zoom punches; gems hop out of kills; pickup chime ladder; XP bar glow/flash; **level-up shockwave** (shoves germs within 220 px, no damage). Details in `docs/POLISH_PLAN.md` "Satisfaction round 1".
- **Bot, seeds 600-1100 x 8 (48 runs per mode), before → after (shockwave is the only gameplay change):**
  - Classic: win 19% → 15%, p10 2:19-2:50 → 1:58-3:04, p50 4:11-4:42 → 2:19-4:11, p90 4:42-5:00 → 3:28-5:00, level p50 8-14 → 8-13
  - Infection: win 21% → 19%, p10 1:50-2:19 → 1:28-2:16, p50 2:14-5:00 → 2:22-3:29, p90 2:46-5:00 → 2:41-5:00, level p50 15-33 → 15-20
  - Swarm: win 15% → 15%, p10 1:29-2:17 → 1:25-2:22, p50 2:17-3:44 → 2:17-4:40, p90 3:23-5:00 → 3:21-5:00, level p50 9-12 → 10-13
  - Nucleus: win 31% → 40%, p50 2:24-6:09 → 2:55-6:06, p90 3:22-6:13 → 6:01-6:11, level p50 8-14 → 9-14 (pushing germs off the nucleus buys the towers time)
  - All inside the ±10-15 point alarm band. The kiting bot loses a little in Classic (germs knocked out of orbit/pulse reach); humans should feel it as breathing room. 159 tests.

### 2026-11-04 Satisfaction round 2: danger readability + weapons
- Low-HP edge vignette + heartbeat, subtle hit-direction bloom, a cheap animation on the cell per owned weapon (stacking by zone), bigger evolved weapon visuals, and an evolution moment after the chest. Presentation only (World's `hurt` event gains `from`; no rule changes, so no sim change). New generated sound `heartbeat`. Details in `docs/POLISH_PLAN.md` "Satisfaction round 2". 160 tests.

### 2026-11-04 Evolution moment v2; developer gold tools
- Evolution moment is now a ~1.9 s frozen sequence (charge, burst, banner): see `docs/POLISH_PLAN.md` "Evolution moment v2".
- Developer tools in Settings (`balance.debug.dev_tools`, on for playtests, off for release): **+10,000 gold** (not counted as earned) and **Refund upgrades** (all permanent-upgrade gold back). For testing permanent upgrades on any build, e.g. a fresh web host with an empty save. 162 tests.

### 2026-11-04 Web playtests move to itch.io
- GitHub Pages' deploy step timed out twice ("updating_pages" for 10 min) although the build itself passed. Yousuf chose itch.io (free, made for browser games, restricted page, no file-size problem: index.wasm is 39.5 MB, over Cloudflare Pages' 25 MB cap).
- `tools/web_push.sh`: stamps the build SHA, exports, `butler push build/web light213/petri:html5`. Run from the cloud session after each change (no dependency on Actions). `web.yml` now does the same as a manual backup (Pages removed).

### 2026-11-04 Satisfaction round 3: results highlights, gold fly-in, claim fill
- See `docs/POLISH_PLAN.md` "Satisfaction round 3". World gains damage-by-source accounting (stats only; sims byte-identical in all 4 modes; the sim's ally share now counts effective damage, Swarm 0.33 → 0.35). 164 tests.

### 2026-11-04 Gold fly-in v2
- Yousuf: the fly-in was "very buggy and looks bad". Now a smooth rising stream: run total counts down as coins leave, wallet counts up as they land, buttons locked; fixed the count-up overwriting the number when you tapped early. Presentation only. 164 tests.

### 2026-11-04 Boss Rift, Phase 1 (D-025)
- Built per ROADMAP "Prototype 4": rift 5-10 s after Outbreak, arena inside the same World (run frozen), Phage Carrier + Seeker Phage (bait it into its owner), 1-HP ejection with a 2.5 s frozen grace, four Rift Powers (Lance / Barrage / Phalanx / Heatwave) on a button left of DASH. Arena tuning with `tools/sim/rift_bench.gd` (numbers in ROADMAP).
- **Bot, seeds 600-1100 x 8 (48 runs per mode), before → after:**
  - Classic: win 15% → 15%, p10 1:58-3:04 → 1:57-3:53, p50 2:19-4:11 → 2:52-4:31, p90 3:28-5:00 → 4:15-5:00, level p50 8-13 → 8-14; rifts entered 42, won 18, timed out 22, ejected 2; 34 phage hits on the Carrier
  - Infection: win 19% → 25%, p10 1:28-2:16 → 1:37-2:23, p50 2:22-3:29 → 2:40-3:18, p90 2:41-5:00 → 3:41-5:00, level p50 15-20 → 17-21; rifts entered 191 (~4 per run: Outbreak fills fast in the dish), won 59
  - Swarm: win 15% → 6%, p10 1:25-2:22 → 1:25-2:17, p50 2:17-4:40 → 1:59-3:21, p90 3:21-5:00 → 2:14-4:12, level p50 10-13 → 7-13; rifts entered 54, won 19 (Swarm's x2 damage taken also applies in the arena)
  - Nucleus: win 40% → 30%, p50 2:55-6:06 → 2:51-6:01, level p50 9-14 → 10-15; rifts entered 47, won 22
  - All within the ±10-15 alarm band. The bot beats the Carrier 31-47% of the time in real runs (it baits imperfectly with odd builds); humans should do better. 176 tests.

### 2026-11-04 Boss Rift shelved
- Yousuf: scrap the rift inside the existing modes for now (revisit bosses later). `balance.rift.enabled` false; code/tests/harness kept. Bot sims, seed 600 x 8 per mode: byte-identical to before the rift (Classic, Infection, Swarm, Nucleus), so the balance is back to the pre-rift numbers (Classic 15%, Infection 19%, Swarm 15%, Nucleus 40% over 48 runs). 177 tests.

### 2026-11-04 Virulence 1-10 (D-027)
- `data/difficulty.json` (10 levels, validated), `GameData.apply_virulence()` (stacks levels 2..N + compounding ramp, per-mode `ramp_scale`), World hooks for germ speed / knock resist / shot speed, Mother Cell HP ramp, gold and score multipliers, Profile v4 (`records.<mode>.virulence` = highest cleared, `settings.virulence` = selected), menu selector, results "VIRULENCE n CLEARED!", HUD "Vn", 2 achievements, sim `--level N`.
- Virulence 1 = the game as before (sims byte-identical; a resist-cap bug that nudged the Mother Cell at level 1 was caught by that check).
- **Tuning with every permanent upgrade maxed (`--meta`), seeds 600/700/800 x 6 = 18 runs per level, bot win rate:**
  - flavour modifiers only: Classic 100% at levels 1-10 (no effect on a maxed account)
  - linear ramp HP +125%/DMG +50% per level: Classic L3 42%, L4 17%, L5 34%, L6 17%, L10 0%; +80%/+35%: L3 78%, L4 44%, L5 39%, L6 28%, L8 6%; +90%/+40%: L3 56%, L4 33%, L5 28%, L6 28%, L7 11%, L10 6%
  - **shipped, compounding HP x1.5 / DMG x1.22:** Classic L3 72%, L4 44%, **L5 22%**, L6 11%, L8 0%, L10 0%; Swarm L3 67%, L5 22%, L8 6%; Infection (x0.85) L3 72%, L4 61%, L5 22%, L8 0%; Nucleus (x0.55) L3 89%, L5 22%, L8 0%. (Full ramp in Nucleus: L3 22%, L5 0%; Infection full: L5 6%.)
- 187 tests.

### 2026-11-05 Developer tools behind a code; unlock all Virulence levels
- Settings → DEVELOPER opens an on-screen keypad (works on APK and web without a keyboard); the code is `balance.debug.dev_password` (1289) and stays unlocked until the app closes. New toggle "All Virulence levels": every level in every mode selectable (`settings.dev_all_virulence`), records and achievements untouched; off restores real progress. 189 tests.

### 2026-11-05 The Lab + Abilities: design agreed (not started)
- Discussed with Yousuf and written up in ROADMAP "Next: the Lab + Abilities" (D-028, D-029): Genes from Virulence wins, 4 branches with forks and keystones, cheap gold respec, abilities (Stasis / Engulf / Cloak / Mitosis) with one equipped via an Abilities menu, replacing Strains. Target for players: full Lab + shop clears V7-8 easily, V9-10 decently. He'll start it in a new session.

### 2026-11-06 Evolution tiers bias level-up offers
- `World.offer_bias()` → `Upgrades.roll_offers(..., bias)`: a weapon's shop evolution tiers raise its offer weight ×(1 + 1.5 × share of tiers), its partner passive ×(1 + 0.75 × share) (`upgrades.evo_offer_bias` / `evo_partner_bias`). Equal tiers = equal odds. Sim V5 maxed shop, 24 runs seed 100, before → after: Classic p10/p50/p90 138/211/300 → 189/250/300, win 13% → 17%, L18 → L22; Infection 122/147/241 → 118/158/261, win 4% → 4%, L21 → L22. 254 tests.

### 2026-11-06 Kill feel: CC0 sounds, hit squash, crits, MEGA KILL
- Sounds from CC0 OpenGameArt recordings (Kenney's site blocks automated downloads): 6 squelch kill variants with a synth low pop, a deep thump under 6+ kills in a frame, a crunch on elite kills, a punch on crits, a dry tap for hits, a chunky explosion for MEGA KILL and the bomb pickup. Sources in `assets/raw/sfx_cc0/SOURCES.md`.
- Germs squash along their knockback, hit sparks fly along the shot, crit numbers are big and gold.
- MEGA KILL: 25 kills within 0.3 s → 0.7 s slow motion (×0.35), white + gold shockwave rings, boom, toast; 8 s cooldown. Bot: ~0-1 per run (fresh), ~5 (maxed shop).
- Render bench A/B with the squash on/off: 66-69 fps both (noise). 256 tests.

### 2026-11-06 Cosmetics v1 (D-038)
- `data/cosmetics.json` (24 items: 9 cell skins, 7 weapon styles, 8 pop styles; validated), `Cosmetics` (pure rules: unlocked/equipped/buy/look, retroactive challenge + prestige unlocks from `Profile.flat()`), Profile v7 (`cosmetics` = bought; equipped in `settings.cosmetics`; v6 saves load with defaults; merge keeps purchases from both copies).
- Drawing: `CosmeticArt` shared by the run (`WorldView.set_look`), the STYLE screen preview and swatches, and the menu hero. Skins: body/nucleus/cilia/glow + patterns (spots, stars, sparkle, bubbles, flame, glitch). Weapon styles recolour the 4 weapons (and their evolved look) and can swap bolt/orbit shapes (star, heart, diamond). Pop styles: particle shape (square/star/ring/coin/disc), colours, motion (gravity, drag, flutter, upward), splat, ring, flash and sound. New textures in `ShapeTextures` (star, square, heart, coin) and 5 synth pop sounds (`build_pop_sfx`, existing sounds byte-identical).
- STYLE tile on the menu (`StyleScreen`): live preview (your cell shooting germs that pop with the selected style and sound), tabs, item grid with price / challenge %, BUY (auto-equips) / EQUIP / progress bar. Results: "NEW STYLE" chips. Settings → Developer → "All cosmetics" On/Off. Analytics `cosmetic_buy`, `cosmetic_equip`.
- Render bench A/B (default vs Golden + Starlight + Fireworks): 66.5-69.9 vs 65.6-66.6 fps, +3-6 draw calls (noise level). Balance untouched (visual only). 269 tests.

### 2026-11-06 Cosmetics: more items + dash Trails
- 20 more items (44 total): skins Chrome (shine), Tiger (stripes), Rainbow (colour cycles); weapon styles Abyss, Neon (stars), Royal (gems, 6,000 gold); pops Squeaky, Slime, Shatter, Zap, Melody, Kaboom, each with its own new synth/CC0 sound (`pop_squeak/slime/glass/zap/chime/boom`, loudness matched to the squelch; older sounds byte-identical). **Melody** plays a pentatonic scale up and down: kill n of a streak = note n, so a streak is a tune and a break restarts it.
- New category **Trails** (dash): Afterimage (default), Sparkle, Bubble Stream, Flame, Hearts (1,000 dashes), Lightning (500 Lancers), Rainbow (V3), Comet (V7). Particles per second of dash, not per frame (same at 60/120 fps), own SpriteBatch (cap 120). The STYLE preview cell now drifts and dashes every 2.2 s so trails show.
- 272 tests (3 new: melody notes, trail emission rate, rainbow colour).

### 2026-11-07 New-player start: Patient Zero, staged unlocks, mode coaches (D-039)
- `data/onboarding.json` + `Tutorial` (scripted beats inside a World: start actions, repeating spawns, one condition or a timeout, prompt text/target/slow motion) + `Onboarding` (prologue rotation, score, medals, unlock rules, announcements, coaches, ad gating) + Profile v8 (`onboarding`; older saves that had played get everything unlocked).
- **Patient Zero:** first launch starts it with the title over the dish. 14 beats teach every core mechanic and end with an evolution, a ×100+ streak, Outbreak and a weakened Mother Cell. Bot: 104-110 s of game time, score ~1,030-1,190 (Silver); medals 500/900/1,300; the Gold medal unlocks the new **Prototype** skin. Replays rotate the showcased evolution (Storm → Wall → Fever → Neural) and the elite affix.
- **Staged menu:** locked mode cards and tiles show what opens them; unlock popups (NICE!) once each, NEW badges until opened; the Virulence row appears after the first win; Style comes with a free pick; Patient Zero button with best medal. New players start in Classic.
- **Coaches:** Infection (loop to claim, erosion), Swarm (allies, order fan with slow motion), Nucleus (defend, pad pointer, build). Shared text hints are skipped once the prologue has taught them.
- No reroll/double-gold/between-run ads in the first 3 runs. Settings → Developer → "Replay new-player start".
- Fixes found on the way: a refused damage number (effects list full) was still registered and crashed the next merge; the chest reels touched freed cards if closed mid-spin.
- 290 tests (18 new: the bot finishes the prologue with an evolution and a boss kill, can't die, rotation, forced offers, score/medals, unlock rules, announcements, free pick, coaches finish in their modes, veteran saves, merge).
- Fix (Yousuf: unlock text cut off bottom-right): the locked-tile/mode banner was anchored wrongly; now a full-width panel over the hero cell's space (follows the menu on any screen shape), one at a time; clearer wording ("Play 2 more runs to unlock", "Win a run (it earns Genes) to unlock", cards "3 more runs or a win").
