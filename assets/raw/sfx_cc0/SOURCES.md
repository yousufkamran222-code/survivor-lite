# CC0 sound sources (inputs for tools/build_assets.py)

All files here are CC0 (public domain dedication), downloaded from OpenGameArt
on 2026-11-06 and converted to mono 16-bit WAV (`ffmpeg -ac 1 -c:a pcm_s16le`,
the punches also resampled from 96 kHz to 44.1 kHz). No other edits; trimming,
layering and pitching happen in `tools/build_assets.py`. `.gdignore` keeps Godot
from importing them (only the processed results ship).

| Folder | Files | Author | Source |
|---|---|---|---|
| `ezduzziteh_squish/` | squish_01..04 | EZduzziteh | https://opengameart.org/content/squish-sounds-effects |
| `independent_nu/` | impactsplat01, impactsplat03 | Independent.nu (submitted by qubodup) | https://opengameart.org/content/8-wet-squish-slurp-impacts |
| `independent_nu/` | impactcrunch04 | Independent.nu (submitted by qubodup) | https://opengameart.org/content/5-break-crunch-impacts |
| `qubodup_punch/` | punch01, punch03 | qubodup | https://opengameart.org/content/punch |
| `starninjas_impact/` | impact_8 | StarNinjas | https://opengameart.org/content/10-impactshield-blocks |
| `joth_chunky_explosion/` | chunky_explosion | Joth | https://opengameart.org/content/chunky-explosion |
