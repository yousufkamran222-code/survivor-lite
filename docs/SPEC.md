# Petri Panic: one-page game spec (v1)

**Pitch:** You are a lone white blood cell in a petri dish. Germs pour in from every side. Survive 5 minutes, evolve a build, kill the Mother Cell.
**Platform:** Android (portrait, one thumb). **Session:** 3-5 min runs. **Audience:** global, Tier 1 first.
**Working theme only.** See `DECISIONS.md` D-006. Every name and colour below lives in `data/`.

## Core loop
1. **Drag anywhere** to move (a floating joystick appears under the thumb). WASD or arrows on desktop. **Dash** (button bottom-right, a second-finger tap, or Space): a 0.16 s burst with brief invulnerability on a 2.0 s cooldown. Dash cards: Double Flagella (+1 charge), Lunge (dash damages what it passes through), Afterimage (a decoy on its own 6 s cooldown lures nearby non-elite germs for 1.5 s, then bursts), Adrenaline (faster recharge; elite kills refill dashes).
2. Weapons **fire automatically** at nearby germs.
3. Killed germs drop **XP gems**, which fly to you inside the pickup radius.
4. A full XP bar means **level up**, which is **banked**: the game doesn't pause. A small "LEVEL n +1 upgrade" note appears above the **UPGRADE** button (bottom-left, with a badge counting banked level-ups). Tap it (or E/Tab) whenever it suits you to **pick 1 of 3** per banked level, or tap **Later** to keep the rest banked.
5. **Elites** (big, gold-ringed, tougher versions of current enemies) arrive at 0:35 and then every 40 s, with an off-screen arrow pointing to them. Weapons focus elites and the boss when in range. Each drops a **chest**: a slot-machine reveal of 1 item (3 from the boss). It's an **evolution** if one is ready, otherwise a level of something you own.
6. **Rare pickups** drop from normal kills: **Vacuum** (pulls every gem on the map), **Heal** (+30% HP), **Bomb** (kills normal enemies on screen and damages elites and the boss).
7. Survive to **5:00** for a win. The **Mother Cell** boss arrives at 3:50.
8. **BUILD** (top-left HUD button, or B): pauses and lists every weapon and upgrade you own with its level, what it does and how it evolves.
9. **Swarm mode only: orders.** A button left of Outbreak shows the swarm's order; tap it to fan out three orders (**the run pauses** while the fan is open; tap anywhere else, Esc or Back to resume) and tap one to switch (1 s cooldown; keys 1-3): **Guard** (hold the bodyguard ring, allies take 40% less damage and knock germs back), **Hunt** (spread out and attack germs within 350 px of you, +50% ally damage), **Harvest** (fetch stray XP gems up to 1100 px away; a touched gem flies to you at full value; allies fight at 60%). Ally damage grows with enemy HP and your Enzymes/Potency, and Outbreak's frenzy boosts allies too (x1.5 damage and speed).
10. Death or win leads to results: **gold** earned, then spent in the menu on permanent upgrades. Then play again.

## Run structure and difficulty curve (`data/waves.json`)
- A spawn **budget** (points/s) ramps 2.4 → 3.8 → 5.5 → 8.5 → 13.5 → 16.9 → 24 → 30 at 0/45/90/150/180/210/240/300 s (bigger crowds from 2:30, a surge in the final minute). Each enemy costs points (Spore 0.4, Germ 1, Lump 6, ...).
- Enemy HP grows +120% per minute (not the boss), and enemy damage +40% per minute.
- **Final minute** (timed modes, from 4:00): a FINAL MINUTE warning, the timer turns red, germs move 15% faster, elites come every 20 s instead of 40 s, and the spawn budget surges. Nucleus keeps its own finale (the boss wave). The on-screen cap is 170, plus short overshoot from rings and splits.
- New enemy types unlock over time (table below). Scripted beats: Spore ring at 1:00, Zipper ring at 2:15, Lump ring at 3:20, **boss at 3:50**, final Spore flood at 4:40.
- **Targets** (checked with `tools/sim/balance_sim.gd`, then real playtests): **a good player's first win after about 3-5 runs** with no permanent upgrades (Yousuf, 2026-11-03; he won Swarm and Infection on his first try, with one revive, before the final-minute change), median first-time death 3:00-4:30, bot win rate under ~30% without meta upgrades (a sanity check, ±10-15 points is fine) and over 60% with most meta bought, a level-up roughly every 15-25 s (all XP x0.7 via `xp.gain_mult`, 2026-11-04), and the boss killed in about half of the runs that reach it.

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
15 permanent upgrades with 96 tiers in total (about 17,000 gold to max everything), bought in a drag-scrolling grid shop; tapping an upgrade opens a popup with "now → next" in words and a big UPGRADE button:
- Survival: Thick Membrane (+10 HP ×10), Cell Wall (−2% damage ×8), Repair Enzymes (+0.1 HP/s ×6).
- Offence: Potency (+4% damage ×10), Metabolism (−3% cooldowns ×8), Replication (+1 projectile ×2, expensive).
- Utility: Mobility, Absorption, Growth, Greed.
- Dash: Flagella Training (−5% dash cooldown ×6), Extra Flagellum (+1 charge), Spiked Membrane (dash damage ×5), Ghost Trail (dash decoy ×3).
- Swarm: Viral Memory (+1% convert ×5).
Early tiers cost 25-60 gold, so the first purchase comes after the first run. Costs grow ~35% per tier. At ~100-280 gold per run, maxing takes about 100-170 runs, which is the long-tail retention goal.

## Monetisation and ad placements (all through `Ads`)
| Placement | Type | When | Rule |
|---|---|---|---|
| `revive` | rewarded | Death screen, big button | Once per run. 50% HP, clears nearby enemies, 2.5 s invulnerability |
| `double_gold` | rewarded | Results screen | Once per run |
| `reroll` | rewarded | Level-up screen, small button | Re-rolls the 3 offers |
| `between_runs` | interstitial | Leaving results | Every 3rd death, never in the first 2 runs, never right after a rewarded ad |
No banners. IAP (later): remove-ads (interstitials only, rewarded stays opt-in), starter pack.

## Game feel ("juice") knobs (`balance.json` → `juice`)
Hit flash, knockback and its decay, damage numbers that arc out and fall (colour by hit size, hot-pink killing blow), kill flash + burst, multi-kill shake, dash afterimages, elite auras, chest reveal spin, damage numbers (capped), kill bursts, screen shake (hurt, nova, boss kill), hit-stop (hurt, boss kill), haptics on hurt and death, pitch-jittered SFX with rate limits, and joystick radius and dead zone. Tune these from playtest notes and schedule a dedicated juice pass per milestone.

## Analytics events (via `Analytics.event`)
`session_start`, `run_start`, `upgrade_pick`, `chest_open`, `evolution`, `pickup` (kind), `boss_spawn`, `boss_killed`, `death` (time, level, cause), `run_end` (won, time, level, kills, gold, elites, chests, evolutions, dashes), `meta_buy`, `ad_rewarded_start/end` (placement, rewarded), `ad_interstitial`. These are enough for D1/D7 retention, session length, ads per user and the quit point.

## Later (not v1)
More characters and maps, endless mode, daily challenge, more evolutions, cosmetics, leaderboards, iOS.
- **Difficulty levels (agreed for later, 2026-11-03):** beating a mode unlocks Lv 2, 3, ... for that mode (like heat/danger levels). Each level adds one modifier from data (faster germs, extra elites, a tougher boss, ...) and +20% gold, so the first win stays a celebration, good players get a ladder, and a maxed account has something to beat (it wins 100% today). Needs: per-mode unlocked/selected level in `Profile` (bump `Profile.VERSION`), a level selector on the mode card, a `difficulty_levels` table merged like mode overrides, per-level records/leaderboards.
- **Sacrifice order (Swarm, 2026-11-03, revisit later):** a 4th swarm order: every ally bursts at once for damage based on its remaining HP, spending the swarm for a panic clear. Held back because it overlaps with Outbreak as a panic button; it would need a cost (e.g. no conversions for a while) or a different trigger so it doesn't become the obvious answer.
- **Boss Rift (Yousuf's idea, 2026-11-03):** every few minutes a glowing rift opens; step in (your choice) and the run freezes while you fight a unique mini-boss with special attack patterns for ~20 s in a cleared arena. Win: pick a rare reward (1 of 3 upgrades, or a guaranteed evolution step). Lose or run out of time: back to the run as it was (damage taken in the arena carries over, so it's a real risk). Open points: a new boss vs the 8-enemy-type cap (or a Mother Cell variant with new patterns); implement as a separate arena World that the run's World waits behind.
