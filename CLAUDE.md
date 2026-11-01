# CLAUDE.md: Petri Panic (survivor-lite roguelite)

Read this first. With `docs/SPEC.md` and `docs/PIPELINE.md` it should be enough to pick up the project cold.

## What this is
A solo-dev mobile survivor-lite: drag to move, auto-attack, swarms, pick 1 of 3 upgrades per level, 5:00 runs, gold meta-progression between runs. Ships as a **native Android app**. The web build is a playtest tool only.
- Owner: Yousuf (A-Level student, ~6-8 h/week). He prefers concise explanations and **minimal, surgical changes** over rewrites.
- Working theme: **microbes in a petri dish** (white cell vs germs). It is not final (see `docs/DECISIONS.md`). Names, colours and text are data, so a re-theme is mostly a data edit.

## Engine and versions
- **Godot 4.7.2**, pinned in `GODOT_VERSION` (CI reads it). **Compatibility renderer only** (old GPUs, WebGL2, cheap phones).
- Portrait 720x1280, stretch `canvas_items` / `expand`.
- No addons yet. The AdMob/Firebase plugins arrive in milestone M3 and need the Gradle Android build.

## Commands (run from repo root)
```bash
godot --headless --path . --import                          # first time / after adding assets (run twice on a fresh clone)
godot --headless --path . -s res://tests/run_tests.gd       # all tests, exit 1 on failure
godot --headless --path . -s res://tools/sim/balance_sim.gd -- --runs 12 --seed 100   # balance report (JSON)
python3 tools/build_assets.py                               # regenerate assets/processed (needs numpy)
godot --headless --path . --export-release "Web" build/web/index.html   # needs export templates
```
The cloud sandbox can download Godot and the templates from GitHub releases and run all of the above. The web build can be screenshotted with Playwright plus Chromium (`--use-angle=swiftshader`) to check the UI.

## Architecture (keep it this way)
```
data/*.json          ALL tunable numbers: balance, enemies, upgrades, waves, meta. Tune here, not in code.
scripts/core/        Pure logic, no Nodes: World (the whole simulation), SpawnDirector, Upgrades,
                     Progression, GameData (load + validate), BalanceBot. Deterministic for a seed.
scripts/game/        main.gd (screen flow + UI wiring), world_view.gd (draws World, effects, camera shake)
scripts/ui/          UiKit (theme + widgets in code), HudOverlay (XP bar, timer, joystick)
scripts/autoload/    Save, Analytics, Sfx, Ads (AdService + StubAdBackend)
scenes/main.tscn     A single node. Everything else is built in code (hand-editing .tscn is fragile).
tests/               Headless tests: test_*.gd extends TestCase; the runner finds test_* methods.
tools/               build_assets.py (SFX synth), sim/balance_sim.gd (bot runs)
assets/processed/    Generated outputs (committed with their .import files). assets/raw/ = inputs.
```
- `World` owns all gameplay state as packed arrays (struct of arrays, swap-remove). It emits events (`hit`, `kill`, `nova`, `level_up`, ...) that `Main` turns into sound and haptics, and `WorldView` into effects. **Gameplay rules go in World, presentation goes in view or main.** Never put game logic in the view.
- Rendering is immediate-mode `_draw()` shapes on one CanvasItem. No per-enemy nodes.
- `GameData.validate()` checks cross-references and runs in tests and at startup.

## Rules
1. **Run the tests before every commit/PR.** Add or extend tests for any logic change. Tests must be seeded and deterministic.
2. For any balance change, run the sim before and after and quote both in the PR (p10/p50/p90 survival time, win rate, level_p50).
3. **Ads go only through `Ads` (scripts/autoload/ad_service.gd).** No ad SDK calls anywhere else. Web, desktop and tests use the stub.
4. Analytics only through `Analytics.event(name, params)`, with snake_case names of 40 characters or fewer.
5. **Never commit secrets**: keystores, passwords, service-account JSON, real AdMob IDs. CI injects them from GitHub secrets. Use AdMob **test IDs** in code.
6. Assets: CC0 only, and every non-generated file gets a line in `assets/MANIFEST.md`. Processed assets are rebuilt by `tools/build_assets.py`.
7. Prefer data edits over code edits, and small diffs over refactors. Don't rename or move files without a reason.
8. v1 scope cap: 1 character, 1 map, 8 or fewer enemy types, about 10 upgrades, 1 mode (enforced by `tests/test_data.gd`). Push new ideas to `docs/SPEC.md` "Later".
9. Turn playtest feedback ("dash feels floaty", "wave 4 too hard") into data changes first, using `balance.json` `juice` and `waves.json`.

## Performance budget (low-end Android is the target)
- On-screen enemies are capped by `waves.max_alive` (170). Scripted rings and splits may briefly exceed it, up to about 210.
- Caps: `perf.max_projectiles` 220, `max_enemy_shots` 120, `max_effects` 140, `max_damage_numbers` 40, `xp.max_gems` 120.
- Frame budget: 16.6 ms at 60 fps on the cheap test phone. Sim step about 1.1 ms on a desktop CPU at peak density (measured with `sim_ms_per_run`). If the phone drops frames, first profile `World._update_enemies` (separation) and `query()`.
- No shaders, no textures larger than 512 px, no per-frame allocations in hot loops where avoidable.

## Builds and CI (.github/workflows)
- `test.yml`: on every push and PR it runs the tests and a 4-run balance smoke, written to the job summary.
- `web.yml`: on push to `main` (or a manual run) it tests, exports the web build and deploys to GitHub Pages. The menu shows the build SHA.
- `android.yml`: manual run or a `v*` tag builds an APK artifact. Signed release if the keystore secrets exist, otherwise debug. An AAB via the Gradle build comes in M3.

## Where things stand
See `docs/PIPELINE.md` "Milestones" for the current milestone and next steps. Update it when you finish one.
