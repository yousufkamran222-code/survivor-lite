# Petri Panic: one-page game spec (v1)

**Pitch:** You are a lone white blood cell in a petri dish. Germs pour in from every side. Survive 5 minutes, evolve a build, kill the Mother Cell.
**Platform:** Android (portrait, one thumb). **Session:** 3-5 min runs. **Audience:** global, Tier 1 first.
**Working theme only.** See `DECISIONS.md` D-006. Every name and colour below lives in `data/`.

## Core loop
1. **Drag anywhere** to move (a floating joystick appears under the thumb). WASD or arrows on desktop. **Dash** (button bottom-right, a second-finger tap, or Space): a 0.16 s burst with brief invulnerability on a 3.2 s cooldown.
2. Weapons **fire automatically** at nearby germs.
3. Killed germs drop **XP gems**, which fly to you inside the pickup radius.
4. A full XP bar means **level up**: the game pauses and you **pick 1 of 3** upgrades (taps are blocked for 0.35 s so a dragging thumb can't mis-pick).
5. **Elites** (big, gold-ringed, tougher versions of current enemies) arrive at 0:35 and then every 40 s, with an off-screen arrow pointing to them. Weapons focus elites and the boss when in range. Each drops a **chest**: a slot-machine reveal of 1 item (3 from the boss). It's an **evolution** if one is ready, otherwise a level of something you own.
6. **Rare pickups** drop from normal kills: **Vacuum** (pulls every gem on the map), **Heal** (+30% HP), **Bomb** (kills normal enemies on screen and damages elites and the boss).
7. Survive to **5:00** for a win. The **Mother Cell** boss arrives at 3:50.
8. Death or win leads to results: **gold** earned, then spent in the menu on permanent upgrades. Then play again.

## Run structure and difficulty curve (`data/waves.json`)
- A spawn **budget** (points/s) ramps 1.6 → 3.5 → 5.5 → 8.5 → 13 → 17 → 20 at 0/45/90/150/210/270/300 s. Each enemy costs points (Spore 0.4, Germ 1, Lump 6, ...).
- Enemy HP grows +120% per minute (not the boss), and enemy damage +30% per minute. The on-screen cap is 170, plus short overshoot from rings and splits.
- New enemy types unlock over time (table below). Scripted beats: Spore ring at 1:00, Zipper ring at 2:15, Lump ring at 3:20, **boss at 3:50**, final Spore flood at 4:40.
- **Targets** (checked with `tools/sim/balance_sim.gd`, then real playtests): median first-time death 3:00-4:30, win rate under 30% without meta upgrades and over 60% with most meta bought, a level-up roughly every 15 s, and the boss killed in about half of the runs that reach it.

## Enemies (`data/enemies.json`), 8 types
| id | Name | Unlock | Behaviour | Role |
|---|---|---|---|---|
| grunt | Germ | 0:00 | chase | Baseline fodder |
| swarm | Spore | 0:30 | chase, groups of 6 | Fast and fragile. Tests area damage |
| runner | Zipper | 0:50 | chase, faster than you | Punishes standing still |
| spitter | Spitter | 1:15 | keeps range, shoots | Forces movement |
| brute | Lump | 1:35 | slow tank, resists knockback | Tests single-target damage |
| charger | Lancer | 2:00 | flashes, then dashes | Readable burst threat |
| splitter | Mitosis | 2:30 | splits into 2 Germs | Crowd growth |
| boss | Mother Cell | 3:50 | chase + 14-shot radial burst | Climax, gold bonus |

## Upgrades (`data/upgrades.json`), 4 weapons + 7 passives, max 4 weapons
| Upgrade | Type | Lv1 | Levels 2-5 |
|---|---|---|---|
| Pulse Bolt (start) | weapon | Shoots the nearest germ | +dmg, +1 bolt, faster, pierce |
| Antibodies | weapon | 2 orbiting blobs that also destroy enemy shots | +1 orb, +dmg, wider, faster |
| Fever Pulse | weapon | Damage + knockback ring every 3 s | +radius, +dmg, faster |
| Nerve Spark | weapon | Chain lightning, 2 jumps | +jumps, +dmg, faster |
| Enzymes | passive | +12% damage | x5 |
| Metabolism | passive | -7% cooldowns | x5 |
| Flagella | passive | +8% move speed | x5 |
| Thick Wall | passive | +20 max HP (and heal) | x5 |
| Receptors | passive | +35% pickup range | x5 |
| Replication | passive | +1 bolt, orb and jump | x2 |
| Repair | passive | +0.4 HP/s regen | x3 |
Offers are weighted, and owned items are 1.6x more likely so builds come together. If everything is maxed, you heal 20% instead.

## Evolutions (`data/evolutions.json`), one per weapon
Max the weapon (Lv 5) and own its paired passive, then open a chest. Level-up cards show the pairing.
| Weapon + passive | Evolution | What changes |
|---|---|---|
| Pulse Bolt + Replication | Cytotoxic Storm | Fan of big piercing bolts |
| Antibodies + Thick Wall | Immune Wall | Huge antibodies that heal 0.6 HP per hit |
| Fever Pulse + Repair | Fever Spike | Much wider pulse that strikes twice |
| Nerve Spark + Metabolism | Neural Storm | 3 sparks at once, longer jumps |

## Meta-progression (`data/meta.json`)
Gold per run = kills x 0.05 + 8/min survived + 60 for the boss + 50 for a win. Six permanent upgrades (max HP, damage, move speed, pickup range, XP gain, gold gain) at 30-380 gold per level. A typical run earns about 80-130 gold (2x with the rewarded ad), so the first purchase comes after the first run (the D1 hook), and buying everything takes about 25-35 runs (the D7 hook).

## Monetisation and ad placements (all through `Ads`)
| Placement | Type | When | Rule |
|---|---|---|---|
| `revive` | rewarded | Death screen, big button | Once per run. 50% HP, clears nearby enemies, 2.5 s invulnerability |
| `double_gold` | rewarded | Results screen | Once per run |
| `reroll` | rewarded | Level-up screen, small button | Re-rolls the 3 offers |
| `between_runs` | interstitial | Leaving results | Every 3rd death, never in the first 2 runs, never right after a rewarded ad |
No banners. IAP (later): remove-ads (interstitials only, rewarded stays opt-in), starter pack.

## Game feel ("juice") knobs (`balance.json` → `juice`)
Hit flash, knockback and its decay, dash afterimages, elite auras, chest reveal spin, damage numbers (capped), kill bursts, screen shake (hurt, nova, boss kill), hit-stop (hurt, boss kill), haptics on hurt and death, pitch-jittered SFX with rate limits, and joystick radius and dead zone. Tune these from playtest notes and schedule a dedicated juice pass per milestone.

## Analytics events (via `Analytics.event`)
`session_start`, `run_start`, `upgrade_pick`, `chest_open`, `evolution`, `pickup` (kind), `boss_spawn`, `boss_killed`, `death` (time, level, cause), `run_end` (won, time, level, kills, gold, elites, chests, evolutions, dashes), `meta_buy`, `ad_rewarded_start/end` (placement, rewarded), `ad_interstitial`. These are enough for D1/D7 retention, session length, ads per user and the quit point.

## Later (not v1)
More characters and maps, endless mode, daily challenge, more evolutions, cosmetics, leaderboards, iOS.
