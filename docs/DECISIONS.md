# Decision log

Newest last. Each entry gives the decision, why it was made, and what would change it.

- **D-001 Genre: survivor-lite roguelite.** It had the best balance of buildable scope, ad creative and retention (see `HANDOFF.md`).
- **D-002 Engine: Godot 4 with the Compatibility renderer, pinned to 4.7.2** (latest stable on 2026-11-01). Plain-text project, runs headless in the cloud sandbox and in CI, and suits old GPUs and WebGL2.
- **D-003 Everything built from code.** One `.tscn` with one node; UI and rendering are created in scripts. Claude can't open the editor, and hand-edited `.tscn` files are fragile.
- **D-004 Simulation separate from rendering.** `World` is a pure `RefCounted` with packed arrays. This enables deterministic tests and a headless balance bot, and it is the cheapest per-enemy cost in GDScript. Rendering is immediate-mode shapes with no sprites, which gives a cohesive flat style with no art pipeline.
- **D-005 A home-made test runner instead of GUT or gdUnit4.** Zero dependencies, no addon to vendor, about 40 lines. Revisit if we need mocking or scene tests.
- **D-006 Working theme: microbes / petri dish (working title "Petri Panic").** It is open for discussion, and a re-theme is mostly a data edit (names, colours, text). The reasons for it:
  - Circles and blobs are the natural flat-shape art, so it looks intentional rather than placeholder.
  - It reads globally with no language or culture dependency, and it is family-safe for ads.
  - The ad creative is a dish filling with colourful germs.
  - The candidate twists to evaluate in M2 are "Mitosis" (enemies that split, already in) and "infection" (killed germs briefly fight for you).
- **D-007 The web build is a dev tool only.** The single-threaded web export (`variant/thread_support=false`) works on GitHub Pages without COOP/COEP headers. The product is the Android app.
- **D-008 Ads through an `Ads` autoload with swappable backends.** Web and tests use a stub that always rewards. AdMob comes in M3 behind the same API.
- **D-009 Balance targets are checked by a bot, then by humans.** The bot is a consistent stand-in and does not represent real players. Real playtest notes override it.
- **D-010 Fun pass inside the scope cap.** Yousuf chose all four: dash, elites + chests, evolutions and rare pickups. Evolutions live in their own table (max 4, one per weapon), so the ~10-upgrade pool stays small. Weapons target elites and the boss first, so the big rewards actually get earned.
- **D-011 Game modes instead of picking one design.** After playtesting, Yousuf liked both Classic and Territory, so each prototype becomes a selectable mode. A mode is pure data: balance overrides in `data/modes.json`, applied by `GameData.apply_mode()`. This keeps one codebase and one simulation, and lets each mode tune its own curve.
- **D-012 Spitter counter: Antibodies destroy enemy shots** (Yousuf's choice) instead of capping Spitters or scaling their damage. This turns the Antibodies build into a counter for ranged enemies.
