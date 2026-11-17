# Google Play listing kit (draft 2026-11-17)

Everything the Play Console "Main store listing" asks for. Images and videos are made locally (`build/store_kit/`, gitignored); rebuild them with the tools listed at the end.

## App details
- **App name** (max 30): `Petri Panic`
- **Short description** (max 80): `Grow from one white cell into an unstoppable infection. Dodge, dash, evolve!` (76 characters)
- **Package name** (permanent once uploaded): `com.yousufkamran.petripanic`
- **Category:** Game → Action. **Tags:** Action, Casual, Roguelike, Arcade, Survival.
- **Contains ads:** Yes (AdMob). **In-app purchases:** No (Play Billing comes after launch).
- **Privacy policy URL:** `https://yousufkamran222-code.github.io/survivor-lite/privacy.html` (from `site/privacy.html`; goes live when **Actions → GitHub Pages web build** is run. Replace `CONTACT_EMAIL` in `site/privacy.html` with your contact email first.)

## Full description (max 4000)
```
You are a single white cell in a petri dish swarming with germs. Your weapons fire on their own: you move, dash and choose how to grow.

POP GERMS, LEVEL UP, EVOLVE
Every germ you pop drops XP. Level up to pick 1 of 3 upgrades, then max a weapon and its partner to EVOLVE it: Cytotoxic Storm, Immune Wall, Fever Spike, Neural Storm.

UNLEASH AN OUTBREAK
Kills charge your Outbreak. Trigger it for a frenzy that turns the whole crowd into gold.

SKILL PAYS
Dash at the last moment for a Perfect Dodge, chain dashes into Overdrive, keep a kill streak alive for huge power, and wipe out a crowd at once for a MEGA KILL.

FOUR WAYS TO PLAY
- Classic: survive five minutes and the Mother Cell.
- Infection: loop out of your land and claim the dish.
- Swarm: turn germs into an army and give it orders.
- Nucleus: defend the core with towers.

ALWAYS SOMETHING TO CHASE
Permanent upgrades, a skill tree (The Lab) with abilities, the Virulence 1-10 difficulty ladder, daily missions and 45 cosmetics: cell skins, weapon styles, kill effects and dash trails.

One thumb, five-minute runs, no internet needed. How far can one cell spread?
```

## Graphics (in `build/store_kit/play/`)
| Item | File | Play spec |
|---|---|---|
| App icon | `icon_512.png` | 512x512 PNG, full square (Play rounds it) |
| Feature graphic | `feature_graphic_1024x500.png` | 1024x500 |
| Phone screenshots | `screenshot_1..6.png` | 1080x1920 (9:16), 2-8 required |
| Promo video | `../trailer_portrait_1080x1620.mp4` | Play takes a **YouTube link**: upload this (or a re-cut) to YouTube as unlisted/public and paste the URL |

Screenshot captions: SURVIVE THE SWARM, UNLEASH AN OUTBREAK, EVOLVE YOUR WEAPONS, CLAIM THE DISH, BEAT THE MOTHER CELL, CHAIN HUGE STREAKS.

## Other Play Console forms (answers to check, not legal advice)
- **Content rating (IARC):** cartoon violence against germs, no blood, no user interaction, no gambling. Expect around PEGI 7 / Everyone 10+.
- **Target audience:** choose **13+** (not children): the game shows AdMob ads and isn't designed for kids (LAUNCH_READINESS "Families").
- **Data safety:** collected by AdMob: device or other IDs (advertising ID), approximate location, app interactions/diagnostics; used for advertising/analytics and fraud prevention; data is encrypted in transit; users can't request deletion through you (it's Google's) but can reset the advertising ID. No account, no personal data collected by the game itself. Update this when Firebase is added.
- **Ads declaration:** yes, contains ads.

## Rebuilding the art
- Icon: `python3 tools/build_icon.py` → `assets/processed/icon/` (wired into `project.godot` and both Android presets: legacy 192 + adaptive foreground/background/monochrome).
- Frames: `tools/footage/showcase.gd` at `--resolution 1080x1920` (portrait, no `--crazygames`), `--every 15` for stills.
- Screenshots/feature graphic: `python3 tools/build_store_art.py shots SPEC.json build/store_kit/play` and `... feature FRAME.png OUT.png` (SPEC = list of {frame, caption}).
