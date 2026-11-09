# Asset manifest

Every asset file must be listed here with its source and licence. **CC0 or self-generated only; fonts may also be SIL OFL (Yousuf, 2026-11-06).**

| Path | Source | Licence |
|---|---|---|
| `assets/processed/bg_tile.png` | Drawn by `tools/build_assets.py` | Original work (project-owned) |
| `assets/processed/sfx/*.wav` | Built by `tools/build_assets.py`: most synthesised; kill1-6, thump, crunch, crit, hit, mega, bomb are trimmed/pitched/layered from `assets/raw/sfx_cc0/` | Original work / CC0 |
| `assets/raw/sfx_cc0/*/*.wav` | CC0 recordings from OpenGameArt (EZduzziteh, Independent.nu, qubodup, StarNinjas, Joth), converted to mono WAV; per-file sources in `assets/raw/sfx_cc0/SOURCES.md` (`.gdignore`: not imported) | CC0 |
| `assets/raw/juhani_junkala_action_chiptunes/*.ogg` | Juhani Junkala, "5 Chiptunes (Action)" ([OpenGameArt](https://opengameart.org/content/5-chiptunes-action)); the pack's WAVs re-encoded to OGG Vorbis q3 (`ffmpeg -c:a libvorbis -q:a 3`), renamed `title_screen`, `level_1..3`, `ending`; `INFO.txt` is the pack's licence note | CC0 |
| `icon.svg` | Hand-written SVG in this repo | Original work (project-owned) |

Raw third-party inputs (e.g. Kenney CC0 packs) go in `assets/raw/<pack-name>/`, together with the pack's licence file and a row in this table.
| `assets/raw/lilita_one/LilitaOne-Regular.ttf` + `OFL.txt` | Lilita One by Juan Montoreano, from the Google Fonts repository (github.com/google/fonts, `ofl/lilitaone`); unmodified (the name "Lilita" is a Reserved Font Name, so the file must not be altered) | SIL Open Font License 1.1 |

## Third-party code
| Path | Source | Licence |
|---|---|---|
| `addons/admob/` | Poing Studios Godot AdMob plugin v5.1.0 (github.com/poingstudios/godot-admob-plugin), incl. its Android libraries in `android/bin/`; sample scenes, docs and AI skills removed; `ios/bin/package.gd` is our marker (iOS unused). Its editor art (`assets/`) is excluded from exports | MIT (`addons/admob/LICENSE`) |

