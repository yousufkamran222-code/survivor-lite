# Petri Panic (working title)

A survivor-lite roguelite for Android: one thumb, 5-minute runs, swarms of germs, pick 1 of 3 upgrades per level. Built with Godot 4.7 (Compatibility renderer).

- **Play the latest web playtest build:** GitHub Pages for this repo (see `docs/SETUP.md` §1 to enable it).
- **Spec:** `docs/SPEC.md` · **Pipeline and milestones:** `docs/PIPELINE.md` · **Your setup steps:** `docs/SETUP.md`
- **For Claude Code sessions:** start with `CLAUDE.md`.

```bash
godot --headless --path . --import
godot --headless --path . -s res://tests/run_tests.gd
godot --headless --path . -s res://tools/sim/balance_sim.gd -- --runs 12
```
