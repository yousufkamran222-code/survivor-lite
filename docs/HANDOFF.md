# Context handoff: solo mobile game (survivor-lite roguelite)

Read this first. It summarises two planning conversations in a previous Claude session. The user will also paste that session's game-ideas comparison, so it is not repeated in detail here.

## Your job in this session
1. Bootstrap the GitHub repo per the "Repo and workflow" section below (`CLAUDE.md`, folder structure, CI workflows, asset tooling).
2. Write the one-page game spec (mechanics, upgrade list, enemy list, difficulty curve, ad placements) and the full development pipeline.
3. Build a playable build in the first session, published as a web build so the user can playtest on his phone immediately.
4. Keep the long-term goal in view: a genuinely polished game, not just a shipped one. See "Path to polish".

## About the user and constraints
- Yousuf, A Level student (A2) in Karachi. Studies and exams come first, so realistic time is about 6-8 hours a week, with pauses around exams.
- Solo operation. No team, no artist.
- Hardware: a basic PC with a GTX 750 Ti (weak). Do NOT plan around heavy editors, 3D, or GPU-intensive tooling. Testing happens on his Android phone, ideally plus one cheap low-end phone.
- Budget is tiny. Target the whole first game for under about USD 150.
- Motivation: earn something, and have a real shipped, monetised product with analytics as strong material for his university applications (CS, scholarship-focused).
- He wants to move fast. Cut scope, not critical-path steps.
- Working style: keep explanations concise, and make minimal, surgical fixes when iterating on code rather than rewrites.
- He has a GitHub account and is willing to set Actions secrets (walk him through each one).

## Locked decisions
- **Genre:** survivor-lite roguelite (Vampire Survivors style). Drag to move, auto-attack, enemies swarm, pick 1 of 3 upgrades per level, 3-5 minute runs, light between-run meta-progression for D7+ retention.
- **Engine: Godot 4, Compatibility renderer** (confirmed by the user). Chosen because projects are plain text (`.gd`, `.tscn`, `.json`), run headless, and suit old GPUs. Unity is ruled out.
- **Web playtest build is a hard requirement** (confirmed). Every merge publishes a browser build (GitHub Pages) so he can playtest on his phone in seconds.
  - **It is a dev tool only, never the product.** The shipped game is a native Android app (AAB/APK). The web build cannot test ads, haptics, real touch and audio latency, Android lifecycle behaviour, or true low-end performance.
  - **Cadence:** web build on every merge for fast logic, UI and rough-feel checks. A signed APK from CI on every milestone and before any session where he judges feel or performance, tested on the real phones. Final polish sign-off is APK-only.
- **v1 scope cap:** one character, one map, about 8 enemy types, about 10 upgrades, one mode.
- **Platform:** Android only at first. iOS later if numbers justify it.
- **Monetisation:** ads are about 80-90% of revenue. Rewarded video first ("revive", "double gold", "reroll upgrades"), interstitial every 2-3 deaths, banners avoided. IAP is a small add-on: remove-ads, a starter pack, cosmetics or boosts.
- **Ad mediation:** AdMob directly for v1. AppLovin MAX or LevelPlay later, when scaling.
- **Analytics:** Firebase, tracking D1/D7 retention, session length, ad impressions per user.
- **Audience:** design for global (Tier 1) players. Pakistani LTV is about USD 0.04 versus about USD 1 in the US (hyper-casual figures from the attached deck). No Pakistan-only or cricket game.
- **Art direction:** one flat style with simple shapes, built mostly from scripts plus CC0 packs. No custom shaders or complex scenes.
- **Low-end phone performance:** object pooling, a cap on on-screen enemies, and watch sprite counts.
- **Theme and twist: STILL UNDECIDED.** The genre is crowded, so brainstorm a distinct setting or weapon system with him early.

## Repo and workflow

### Constraint that shapes everything
A cloud Claude Code session can write code and run commands but cannot open the Godot editor, cannot play the game, and can reach little of the web. So the repo must let Claude work and verify without those. Prefer building scenes from code and keep editor use minimal, since `.tscn` files are fiddly to hand-edit.

### Division of labour
| Claude Code (cloud) | User | GitHub Actions (CI) |
|---|---|---|
| Writes all code and data tables | Playtests on his phone, judges feel | Runs tests on every push |
| Writes tests and tooling scripts | Account steps (Play, AdMob, keystore) | Exports the Android build |
| Generates and processes assets | Art-direction calls | Publishes the web build |
| Opens PRs | Merges PRs | Signs the APK, optionally uploads to Play |

### Repo layout
- `CLAUDE.md` (root): engine and version, folder rules, coding conventions, "run tests before every PR", "never commit secrets", "ads go only through an `AdService` interface". A new session should be able to pick up the whole project from this file.
- `docs/`: spec, decision log, this handoff.
- `data/`: enemies, upgrades, waves and balance as JSON or Godot Resources. Tune numbers by editing data, not code, so changes stay small and reviewable.
- `tools/`: Python scripts for the asset pipeline.
- `tests/`: GUT or gdUnit4 tests that run headless.
- `.github/workflows/`: test, web build, Android build.

### Feedback loop
- **Logic tests** for damage, XP curves, upgrade stacking, spawn budgets and the economy, run headless with seeded randomness, so balance bugs are caught without anyone playing.
- **Web build on GitHub Pages** on every merge. The ad SDK does not work there, so `AdService` needs a stub implementation for web and test builds.
- **Android build in CI** (GitHub Actions has open network access, the cloud sandbox probably does not). Each run produces a downloadable signed APK.
- **Stretch goal:** screenshots from a software-rendered CI run so Claude can inspect UI itself. Worth trying, not essential.
- **User feedback style:** short and specific ("dash feels floaty", "wave 4 too hard"), which Claude converts into data or code changes.

### Asset pipeline
Claude cannot generate raster art directly. The split:
- **Claude generates through scripts:** shape-based sprites and UI as SVG rasterised with Python, spritesheets and atlases, resizing and compression, sound effects synthesised in Python (sfxr-style, no licensing questions), and particle and VFX configs.
- **User supplies:** the app icon and store art from an AI image tool, and any CC0 packs (Kenney, OpenGameArt).
- **Commit CC0 packs into the repo.** The sandbox cannot reliably download from kenney.nl.
- **`assets/MANIFEST.md`** lists the source and licence of every file. CC0 only, to avoid store and copyright problems.
- **Folders:** `assets/raw/` (inputs), `assets/processed/` (generated outputs), and one script that rebuilds processed from raw.

### What still needs the user's hands
- Generate the Android keystore and store it and its passwords as GitHub secrets. Never put them in the repo.
- Create the Play Console account and make the first manual upload (required before the API works). After that CI can push to closed testing through a service account.
- Create AdMob IDs. Test IDs live in code, real IDs are injected by CI.
- Final on-device checks, especially ads, which do not run on web.

## Release pipeline (compressed, critical path first)
**Start immediately:**
- Register a Google Play Console account (one-time fee of about USD 25, identity verification can take days, account holder must be 18+).
- Register with PSEB (export tax benefits) and open an AdMob account.
- Recruit 12+ testers (Nixor friends and CS revision-class students).
- Check Google's current rules. As far as known, new personal developer accounts need a **closed test with about 12 testers opted in for 14 days** before production access. This is the long pole. If his account is exempt, launch could be around day 14.

| Days | Work |
|---|---|
| 1 | Account signups, pick theme/twist, repo bootstrap (CLAUDE.md, CI, web build) |
| 2-6 | Core loop built by Claude Code. Daily phone playtests via web build, tune feel |
| 7-9 | Game-over loop, restart, score, simple menu, rewarded video (continue after death), interstitial every 2-3 deaths |
| 10 | Firebase analytics |
| 11-12 | Icon, 4-5 screenshots, store text, privacy policy, data-safety form |
| 13 | Upload to closed testing, send link to testers |
| 14-27 | 14-day tester clock. Fix bugs, polish, start planning the next game or update |
| 28 | Apply for production and release |

**After launch:**
- Run small paid tests (USD 50-100) to measure real CPI and retention.
- The source deck's go/no-go gate is 50-70% day-1 ROAS. A solo dev with a tiny budget may not hit it, so also watch D1 retention (roughly 35%+ is decent).
- If numbers are weak, iterate on the core loop or move on. If strong, scale spend gradually and add mediation.
- He wants to run proper ads **only after the game is perfected and polished**. Ad creative potential matters (a screen full of enemies and explosions makes a strong 15s clip).
- Longer term: ship 3-5 small games a year, expecting one to carry the rest.

## Path to polish
The setup supports polish, but polish does not come automatically from automation. Plan for it explicitly:
- **Game feel is the human-judgment layer.** Hit-stop, screen shake, damage numbers, knockback, pickup magnetism, level-up fanfare and audio feedback should be built as tunable parameters in `data/`, so playtest feedback converts into quick edits. Schedule dedicated "juice passes".
- **Balance:** use headless simulations (bots playing thousands of seeded runs) to find broken upgrades and difficulty spikes before humans see them. Tune against target run length (3-5 min) and target death-wave distribution.
- **Performance budget:** test on the low-end phone every iteration. Set an explicit frame-time and enemy-count budget in `CLAUDE.md`.
- **Art:** the weakest link for a solo dev with no raster generation. Keep a cohesive flat style, invest in the icon and store art (they drive installs), and consider buying or commissioning a small cohesive pack later if the numbers justify it.
- **Telemetry-driven iteration:** use Firebase data after the closed test and soft launch to find where players quit, then fix that.
- **Release gates:** do not start proper paid UA until D1/D7 retention and session length are healthy and a few real players have stress-tested the game.

## Pitfalls to design around
- Privacy policy and the Play data-safety form are mandatory. Do them around day 11, not at the end.
- Use AdMob **test IDs** during development. Never tap your own live ads (account ban risk).
- Rewarded-video placement drives revenue. Make "continue" and "double reward" prominent.
- SDK setup (AdMob, Firebase) is where time disappears, so wire it up early.
- Godot's AdMob plugin situation (maintenance, version compatibility, custom Gradle build) is the most fragile part of the stack.

## Facts to verify (not confirmed, do not assume)
- Google Play closed-test requirement (12 testers / 14 days) and whether it applies to his account.
- Whether Google Play merchant payouts (needed for IAP) are supported for Pakistani developers. Historically restricted, so check the current merchant-country list before relying on IAP. AdMob ad revenue via wire to a local bank is the safer path.
- Pakistan tax and export details from the deck: 0.25% final tax on export proceeds (Section 154A) for PSEB-registered exporters, extended to 2029, plus simplified State Bank export-payment rules (April 2026). Confirm with an accountant.
- Current Godot version, Compatibility-renderer behaviour, the AdMob and Firebase plugin versions and setup steps.
- That the cloud sandbox can fetch Godot from GitHub releases and run it headless (test on day one). If not, run tests in CI only.

## Source material
The user attached a Pakistan & Counting deck, "Game Development in Pakistan" (Unlocking Growth, Season 04), as supplementary context only. Useful numbers:
- Hyper-casual ad revenue per daily user is about USD 0.02-0.05 on Android.
- Cost per install has risen to about USD 3-5 (from under USD 1).
- CEGA offers free, equity-free incubation in Karachi and Lahore (cohort 2 applications opened in 2026). Worth a look later.
- Tier 1 home studio set-up is about PKR 600-800K for two people. This plan deliberately spends far less, since it is one person on existing hardware.

## Open items for this session
1. Decide theme and twist for the survivor-lite.
2. Bootstrap the repo: `CLAUDE.md`, folders, test harness, web-build and Android-build workflows, `AdService` interface with stub.
3. Confirm the sandbox can run Godot headless and fetch what it needs.
4. Write the one-page spec and full pipeline plan, then get the first playable web build to his phone.
5. Check the status of his Play Console, AdMob and PSEB registrations and his tester list.
