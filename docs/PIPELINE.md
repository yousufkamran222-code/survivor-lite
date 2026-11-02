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
| M2 | Feel and balance pass from phone playtests. Low-end perf check on APK (60 fps at 170+ enemies confirmed on Yousuf's phone). Fun pass: dash, elites + chests, 4 evolutions, rare pickups (done, needs playtest). Pick the final theme and name | **in progress** |
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
