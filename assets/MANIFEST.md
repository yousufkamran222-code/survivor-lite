# Asset manifest

Every asset file must be listed here with its source and licence. **CC0 or self-generated only.**

| Path | Source | Licence |
|---|---|---|
| `assets/processed/bg_tile.png` | Drawn by `tools/build_assets.py` | Original work (project-owned) |
| `assets/processed/sfx/*.wav` | Synthesised by `tools/build_assets.py` (no samples) | Original work (project-owned) |
| `assets/raw/juhani_junkala_action_chiptunes/*.ogg` | Juhani Junkala, "5 Chiptunes (Action)" ([OpenGameArt](https://opengameart.org/content/5-chiptunes-action)); the pack's WAVs re-encoded to OGG Vorbis q3 (`ffmpeg -c:a libvorbis -q:a 3`), renamed `title_screen`, `level_1..3`, `ending`; `INFO.txt` is the pack's licence note | CC0 |
| `icon.svg` | Hand-written SVG in this repo | Original work (project-owned) |

Raw third-party inputs (e.g. Kenney CC0 packs) go in `assets/raw/<pack-name>/`, together with the pack's licence file and a row in this table.
| `assets/raw/kenney_fonts/*.ttf` (Kenney Future, Future Narrow, Rocket, Blocks) + `License.txt` | Kenney "Kenney Fonts" pack (www.kenney.nl), via the public mirror github.com/ereborstudios/kenney-fonts (kenney.nl blocks scripted downloads) | CC0 |
| `assets/raw/kenney_fonts/Kenney Future Narrow KX.ttf` | Kenney Future Narrow with K, X, k, x redrawn by `tools/patch_font.py` (the originals read as H). The UI display font | CC0 (derived) |
