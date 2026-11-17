# CrazyGames submission kit (draft 2026-11-17)

Everything the developer-portal form asks for, ready to paste. Files are made by `tools/footage/` (see the end).

## Title
Petri Panic

## Short description (one line)
Grow from one white cell into an unstoppable infection: dodge, dash and evolve your way through a dish full of germs.

## Description
You are a single white cell dropped into a petri dish that is swarming with germs. Your weapons fire on their own, so all you do is move, dash and choose how to grow.

Every germ you pop drops XP. Level up to pick 1 of 3 upgrades, max a weapon and its partner to EVOLVE it into something ridiculous, and keep a kill streak going to power up even more. When the dish gets crowded, unleash an OUTBREAK and turn the crowd into gold. Survive five minutes and the Mother Cell herself, then spend your gold on permanent upgrades and come back stronger.

- 4 modes: Classic survival, Infection (loop out and claim the dish), Swarm (turn germs into an army) and Nucleus (defend the core with towers)
- 4 weapons, each with its own evolution
- Skill moves: Perfect Dodge, Overdrive, Clutch Claims and MEGA KILLS
- Virulence 1-10 difficulty ladder, a skill tree (The Lab), abilities and daily missions
- 45 cosmetics: cell skins, weapon styles, kill effects and dash trails

## Controls
Desktop:
- WASD or arrow keys: move
- Space: dash
- E: open your banked upgrades
- Q: Outbreak
- R: ability
- B: see your build
- 1-3: Swarm orders / 1-4: build towers (Nucleus)
- P: pause
- Mouse: click buttons; you can also drag to move

Mobile (portrait): drag anywhere to move, tap DASH and the other buttons.

## Tags / category
Action, Survival, Roguelite, Bullet hell, Upgrade, Arcade, Casual, Io (category suggestion: Action)

## Technical answers
- Orientation on mobile: **portrait**. Desktop plays in landscape.
- Engine: Godot 4.7 (web export, no threads, no special server headers).
- Initial download: ~15 MB.
- Progress save: local for now (Data Module integration comes with Full Launch).
- Ads: none (Basic Launch). In-game purchases: none.
- Multiplayer: no.

## Files
| Item | File (made locally, not in git) | Spec |
|---|---|---|
| Cover 16:9 | `build/store_kit/cover_landscape_1920x1080.png` | 1920x1080, title only |
| Cover 2:3 | `build/store_kit/cover_portrait_800x1200.png` | 800x1200, title only |
| Cover 1:1 | `build/store_kit/cover_square_800x800.png` | 800x800, title only |
| Trailer 16:9 | `build/store_kit/trailer_landscape_1920x1080.mp4` | 1080p, 60 fps, silent, ~19 s, starts on the cover |
| Trailer 2:3 | `build/store_kit/trailer_portrait_1080x1620.mp4` | 1080x1620, 60 fps, silent, ~17 s, starts on the cover |
| Game build | `build/crazygames.zip` (`tools/crazygames_build.sh`) or the `crazygames.yml` artifact | |

## How the footage is made (to redo it after changes)
- `tools/footage/showcase.gd`: plays a scripted shot of the real game (bot or scripted path, invincible) at a fixed 60 fps and saves PNG frames. Shots: horde, outbreak, evolution, dash, swarm, infection, boss, nucleus, cover. Landscape = `--crazygames` at 1920x1080; portrait = 1080x1620.
- `tools/footage/edit.py`: `encode` turns frames into a clip; `trailer SPEC.json` cuts clips into a trailer that opens on the cover, with short crossfades.
- `tools/footage/cover.py`: puts the title (Lilita One, gold with a dark outline) on a rendered frame.
- Everything is deterministic: the same shot and seed give the same footage.

## Yousuf's publishing checklist (in order)
1. **Download the store kit** from the cloud session before it ends: `build/store_kit/` (covers, trailers, raw clips; plus `play/` for Google Play). If it's gone, a new session can regenerate it with `tools/footage/` (about 1-2 hours of rendering).
2. **Create the developer account** at developer.crazygames.com (sign up, verify email).
3. **Read the developer terms** (linked in the portal, `files.crazygames.com/documents/developer_terms_*.pdf`). Check: the revenue share %, the minimum age (if 18+, a parent may need to own the account), and the exclusivity bonus (+50% for 2 months if the game isn't on other browser portals). Ask their support whether the restricted itch.io playtest page counts; if it does and you want the bonus, unpublish it before Full Launch.
4. **Billing**: in the portal set up payouts (Tipalti) or choose "Hold payments" for now (needed before submitting).
5. **Get the game zip**: GitHub → Actions → **CrazyGames build** → Run workflow (branch `claude/bold-brown-h48pfg`) → download the artifact `petri-panic-crazygames-N` (a folder of files; zip it if the portal wants a .zip). Or ask Claude to run `tools/crazygames_build.sh`.
6. **Test it locally once**: unzip into a new folder, run `python -m http.server 8010` there, open `http://localhost:8010` (fresh port = no cached old build), play a run, check the menu shows the right build SHA.
7. **Submit a game** in the portal: upload the build; title **Petri Panic**; paste the description, controls and tags from this file; **mobile orientation: portrait**; no multiplayer, no in-game purchases; leave "Progress Save (Data Module)" off for now (no SDK yet).
8. **Upload the covers** (landscape 1920x1080, portrait 800x1200, square 800x800) and the **two trailers** (16:9 and 2:3) from `build/store_kit/`.
9. **Preview** it on crazygames.com/preview (desktop: a wide window and fullscreen; phone: portrait), then **submit for QA**.
10. **After QA → Basic Launch** (7-21 days, at least 500 plays, no ads/revenue). Watch the dashboard: average playtime (target 10+ min), day-1 retention (10-15%), conversion (80%+). Send the numbers to Claude; if invited to Full Launch, ask Claude to do Phase B (SDK ads + Data-module saves) from `docs/CRAZYGAMES_PLAN.md`.
