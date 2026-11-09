# Launch readiness: known problems to fix before release

Collected 2026-11-05 from an independent "Play Store critic" review of the whole game, plus deferred balance items. **Not being worked on now** (Yousuf: re-assess and address as launch gets near, i.e. around M3-M5). Tick items off here as they're done.

## Blockers (rejection or outright failure)
- [ ] **No AAB, no real ads, no consent flow.** (AAB done 2026-11-09: `store.yml`; ads + UMP next in M3 step 2.) `export_presets.cfg` has `gradle_build/use_gradle_build=false`; `android.yml` builds an APK only (Play needs an AAB). `ad_service.gd` only uses `StubAdBackend`. There is no Google UMP consent (needed for EEA/UK AdMob traffic) and no Families/COPPA handling. → M3: Gradle build + AdMob plugin + UMP consent as one item; gate on "AAB uploads to the internal track".
- [ ] **Developer account age.** Play Console, the payments profile and AdMob need an 18+ account holder. If Yousuf is under 18, a parent must own the accounts. This blocks the 14-day closed-test clock, so settle it first.
- [x] **Target SDK / 16 KB pages unverified.** (Done 2026-11-09: template targets API 36; `store.yml` fails on any arm64 library under 16 KB alignment. Re-check when plugins add native libs.) Play requires target API 35 (likely 36 for submissions after Aug 2026). Android 15+ targets need 16 KB-aligned native libraries, including the AdMob/Firebase plugin `.so` files. → Check the merged manifest; run `zipalign -c -P 16` on the AAB in CI.
- [x] **Debug flags would ship.** (Done 2026-11-09: the store build forces them off via the `store` feature tag.) `balance.json` `debug.show_perf: true`, `dev_tools: true`, `dev_password: "1289"`; the pck is unencrypted, so the code is readable (it gives +10,000 gold and all Virulence levels, a leaderboard cheat). The menu shows "dev build" and the perf bar. → CI step that fails tag/release builds if any debug flag is on, or gate the tools on `OS.is_debug_build()`.
- [x] **Android Back quits the app mid-run.** (Done 2026-11-09.) `application/config/quit_on_go_back` isn't set to false, so Back kills a run, and on menus exits straight to the launcher. → Set it to false; route Back per screen (pause in a run, back on sub-screens, a quit confirm on the menu).

## Major (installs, retention, ratings, revenue)
- [x] **Run gold can be lost.** (Done 2026-11-09: credited + saved when results open.) Gold is only credited in `_collect()` after the results animation; `record_run` has already saved without it. If the double-gold ad kills the activity (common on low-RAM phones) or the app is swiped away, the gold is gone. → Credit + save in `_show_results`; animate a display-only number.
- [ ] **No cloud save or backup; weak corrupt-save handling.** (Partly done 2026-11-09: Auto Backup on in the store build, corrupt/newer saves kept aside, backup never overwritten by a corrupt file. Cloud save via Play Games: M3 step 4.) Online is a stub; Godot disables `allowBackup` by default, so a reinstall or phone change wipes hours of progress. If `profile.json` and `.bak` both fail to parse, a fresh profile is written and then overwrites the backup. No guard against a newer-version save. → Play Games Saved Games (or Auto Backup) in M3; never overwrite the backup after a failed parse.
- [x] **First-time experience.** (Done 2026-11-07, D-039: Patient Zero prologue, Classic first, staged mode unlocks, Virulence hidden until the first win, no ad prompts in the first 3 runs.) The default mode is Infection, the hardest and most conceptual (bot V1 win 19% vs Classic 56%). The first screen shows 4 modes, the Virulence picker (with duplicated "Win to unlock" text) and 4 nav buttons. A "Reroll (watch ad)" appears on the first level-up. → Start in Classic; unlock modes after the first win or N runs; hide Virulence until the first clear; no ad prompts in the first 2-3 runs.
- [ ] **Economy.** See `docs/BALANCE_REPORT.md`. Genes per minute and per-mode gold were added 2026-11-05, but now overshoot (Classic/Swarm reach V10 in ~40 runs). Shop tiers like "+1% resist" feel like nothing (fewer, chunkier tiers?). V6 and V9 are spike levels.
- [ ] **Scope bloat.** 4 modes × 10 Virulence levels, shop, 7-tier Lab, 4 abilities, Outbreak, streaks, evolutions, towers, swarm orders and shelved Rift code; `world.gd` ~3,400 lines, `main.gd` ~2,000. Every balance change needs a large sim matrix while M3/M4 haven't started. → Feature freeze before launch; consider launching with 2 modes (cut Nucleus to an update).
- [ ] **HUD overload in the right-thumb zone.** UPGRADE, Outbreak, ability, DASH (and Swarm orders) are stacked bottom-right; BUILD is low-contrast; no left-handed layout; banked level-ups pile up unspent. → Fewer buttons, a mirrored layout option, a nudge/auto-open after N banked picks.
- [ ] **Monetisation thin and unmeasurable.** 3 rewarded placements + an interstitial every 3 deaths; no IAP ("remove ads", starter pack); Nucleus has no revive ad. Analytics prints only: no FTUE funnel, no `ad_impression` revenue event, so the D1/D7/ROAS gates can't be measured. → Firebase + funnel and paid-event logging in M3; "remove interstitials" IAP once Pakistan merchant payouts are confirmed.
- [ ] **Families-policy risk.** Cute cartoon germs and one-thumb play may read as child-directed. → Declare 13+ (or 16+), keep store art adult-toned, set AdMob under-age tags from the consent result; the privacy policy and Data Safety form must disclose AdMob/Firebase data (Advertising ID, device and diagnostic data).
- [ ] **Store kit near zero.** The icon is a 128 px SVG of circles; no adaptive icon (foreground/background/monochrome); no feature graphic, screenshots, video, store text or privacy-policy URL. The name and theme are still "working" (D-006) and the name isn't checked for trademarks. "Infection", "Pandemic", "Virulent" may draw sensitive-events review on ad creatives. → Lock the name early (renaming after launch loses store-search history); adaptive icon; 8 screenshots of real gameplay chaos.
- [ ] **Low-end performance unproven.** (60 fps default done 2026-11-09.) Only one real phone tested. The default frame rate was "Max" (90/120 Hz) in runs, which means heat and battery drain. → Default to 60 fps; test on a ~$100 Android Go-class phone and Firebase Test Lab / the pre-launch report; watch for ANRs when AdMob initialises.

## Minor (polish)
- [ ] The Lab bottom bar clips the last row; "RESPEC (150 gold)" wraps.
- [ ] The level-up card reads "Evolves max Antibodies" (unclear); the first level-up is titled "LEVEL 1".
- [ ] English only, strings hard-coded in `main.gd` and the UI (no `tr()`), so localising the store listing or game later is costly.
- [ ] Accessibility: meaning carried by colour (germ types, branches, rarity); no colour-blind palette or text-size option; low-contrast grey-on-purple secondary text.
- [ ] `version/code` comes from the CI run number; pin a monotonic scheme before M5.
- [ ] Shelved Boss Rift code, hints and analytics ship though disabled.
- [ ] Leaderboards/achievements go to a local stub; if their UI is visible at launch it will look broken.
- [ ] The package name `com.yousufkamran.petripanic` is permanent once uploaded; confirm it's intended.

## Deferred balance items
- [ ] Swarm + full Lab wins 100% even at V10 (suspects: Feed/Clotting/Last Stand + allies soaking hits; measure with `--labx feed,clot,last_stand`).
- [ ] Nucleus V10 is 0% even fully upgraded; the new Lab is weaker there (V8 83% → 42%). Nucleus-only Lab nodes ("Specialisations") or a lower Nucleus `ramp_scale`.
- [ ] The economy overshoots after the 2026-11-05 fixes (see above).

## Critic's "fix first" order
1. Confirm the account holder's age; create the accounts and recruit testers.
2. M3 plumbing in one push: AAB, target SDK + 16 KB check, AdMob + UMP, Firebase with funnel and revenue events, cloud save or Auto Backup.
3. Data-loss and quit bugs: Back handling, gold credited before the results animation, safer corrupt-save handling.
4. First-time experience: Classic first, progressive mode unlocks, no early ad prompts, CI forcing debug flags off.
5. Finish the economy, then lock the name and icon and build the store kit.
