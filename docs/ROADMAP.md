# Roadmap: from survivor-lite to "the infection" game

Decided 2026-11-01 with Yousuf. This file is the plan; `PIPELINE.md` tracks release milestones.

## The hook
**You are the infection.** Two systems carry the identity:
- **A. Conversion:** kills have a chance to convert enemies into your allies. Each enemy type also acts as an ally unit (a converted Spitter shoots for you, a converted Lump tanks).
- **B. Territory:** loop out of your land and back in to claim everything you enclosed (Paper.io-style). Your land is a safe-ish base: no spawns, enemies slowed and damaged, you get a buff. Enemies on your land eat it back.

Together they form a light tower defence: converts garrison your land, and your land makes converts matter. The arena is a bounded round dish, and the HUD shows **"% infected"**, which is also the ad hook: the dish turns your colour.

Positioning: "Plague Inc. meets Vampire Survivors", cartoon-cute. Don't borrow anyone's name or art.

## Step 0: Spitter fix: **done 2026-11-02** (Antibodies destroy enemy shots they touch; Yousuf's choice)
Diagnosis: Spitters hover at 290 px, beyond Antibodies' reach (85-150 px). Their shots scale with enemy damage growth (about 22 per shot at 4:00), and bolts target the nearest enemy, so ranged enemies get ignored.
- Antibodies (and Immune Wall) destroy enemy shots they touch.
- Cap Spitters at about 12 alive (`waves.pool` per-enemy `max_alive`).
- Shot damage grows at half the melee rate.

## Prototype 1: territory only: **built and playtested 2026-11-02; kept as the "Infection" game mode**
Playtest verdict (Yousuf): it feels nice and the land is a real safe zone, but erosion was so fast that he turtled in a small radius (sub-10% infected) and still survived 5:00. Changes made:
- Erosion slowed (0.35 → 0.12/s), and the home-turf advantage softened (enemies slowed 25% instead of 30%, DoT 2.5/s instead of 4).
- **Claim XP:** 0.15 XP per tile claimed, so big loops pay off.
- **Pressure:** the spawn budget (+200% at 100% infected) and enemy HP (+150%) scale with % infected, so expanding is a trade-off.
- The Infection mode uses its own XP curve (the bounded dish yields about 3x the kills).
- Next questions: is expanding now worth the risk? Is the grid too coarse (64 → 96)?

**Game modes decision:** keep both, and future prototypes become modes too (`data/modes.json`).
Test question: **does claiming feel good while being chased?**
- A bounded dish (radius about 1500 px) with a 64x64 tile grid. The player and enemies stay inside.
- You start with a home patch, and its small core can never be lost.
- Leaving your land draws a trail. Re-entering claims the trail plus everything it encloses (a flood-fill when the loop closes). A trail that isn't closed within about 8 s fades.
- **Claim burst:** enemies on newly claimed tiles lose 40% of their max HP. Looping around a crowd feels great.
- Your land: no spawns there, enemies on it are slowed 30% and take damage over time, and you deal +20% damage and regenerate.
- Erosion: enemies standing on your tiles turn them neutral. Elites erode 4x faster, the boss 10x.
- HUD: % infected, plus a trail that blinks as its timer runs out. Results show % infected.
- A menu toggle switches between Classic and Territory so you can compare the two.
- Done when: tests pass, the sim runs in both modes, and a phone playtest gives a verdict.

## Prototype 2: conversion only: **built 2026-11-02 as the "Swarm" mode, awaiting playtest**
As built:
- Killed enemies (not elites or the boss) convert at 9% base (+3% per Viral Load level) into allies, up to 20 (+6 per Incubation level).
- Allies are stored in the same arrays as enemies with a team flag. They have 2x HP and 1.25x speed, chase enemies near them (leashed to you) or trail behind you, fight on a 0.25 s melee tick, and expire after 40 s.
- Converted Spitters shoot for you. Weapons, contact damage, territory and spawn caps all ignore allies.
- Swarm-only upgrades are marked with `"modes": ["swarm"]` in `upgrades.json`.
- Bot (seeds 600/700/800 × 8): win ~25%, p50 4:22-5:00, ~76 conversions and 10-15 peak allies per run, 0 evolutions (the Swarm passives dilute the pool; revisit). Perf: 0.81 ms per step at 150+ enemies.
- Not yet done: enemies retargeting allies (they still chase you, and allies intercept them), elite conversion.

**Rework 2026-11-02 after playtest: bodyguard swarm.** Playtest verdict: "kinda" fun. It got busy and chaotic, using the swarm cost more HP than just kiting, 20 felt too few but "more" wasn't the fix, and the swarm upgrades were weaker than weapon upgrades. Changes:
- Allies hold a slowly turning ring around the player (80-150 px), so they help while you kite. Melee allies body-block and brawl with whatever reaches them, ranged allies fire outward, and every ally soaks enemy shots that hit it.
- Cap 12 (+3 per Incubation level). Conversions on a full swarm **feed** it: +6% power to all allies (max +150%) plus a heal.
- New ally look: a hollow cell with a nucleus and no eyes, in our colour.
- Hive Mind replaces Hijack: +1% weapon damage per living ally plus ally power. Viral Load also heals 1 HP per conversion.
- Bot bug found and fixed: it fled its own allies. Bot, seeds 600/700/800 × 8: bodyguard swarm ~54% win, p50 5:00, peak allies 12-15; the same mode with conversion off was ~42%. So the swarm is now a net positive.

Original plan:
- Each kill has a convert chance (an upgrade raises it). Converts keep their type's behaviour, retarget enemies, have a lifetime or HP, and share the enemy cap (`conversion.max_allies`).
- Allies are shown in your colour. Enemies target the nearest of the player or an ally.
- New upgrades: Viral Load (convert chance), Hijack (convert stats), Incubation (a bigger cap).
- Test question: does a growing swarm feel like power without hiding the danger?

## Prototype 3: "Nucleus" mode (tower defence): **step 1 built 2026-11-02, awaiting playtest**
Yousuf's choices (2026-11-02): germs go for the nucleus but switch to you when close; build by **standing on a pad**; **12 numbered waves**, then on a win you may **continue into endless Free Mode**; only the **nucleus dying** ends the run (you respawn).

### The mode in one paragraph
A big host **nucleus** sits at the centre of a bounded dish. Germs pour in from 3-4 **vents** on the rim (they pulse before a wave so you see where trouble comes from) and march on the nucleus, switching to you when you come within aggro range. Kills give **biomass** (a run-only currency, separate from XP and gold). Around the nucleus are 6 glowing **build pads**: stand on one, a ring fills over about 1 s, and it builds (first time: pick 1 of 4 towers in a small popup) or upgrades the tower if you can pay. You still have your weapons, dash and banked level-ups, and you plug the gaps your towers leave. If you die you reform at the nucleus after about 5 s while the towers keep fighting. Clear wave 12 (boss wave) to win; the victory screen offers **COLLECT** or **KEEP GOING** (Free Mode: endless, ever-harder waves for a best-wave record and leaderboard).

### Rules (all numbers live in data, these are starting values)
- **Nucleus:** 1000 HP, regenerates a little during breathers. Enemies that reach it stop and attack it on a melee tick; Spitters shoot it. HUD: big nucleus HP bar at the top, flashes and shakes when hit; off-screen arrow when you're far away.
- **Targeting:** each enemy targets the player if within `aggro_radius` (about 220 px), otherwise the nucleus. No pathfinding: straight lines plus the existing separation; vent positions create natural lanes. Allies (Swarm) don't exist in this mode.
- **Biomass:** gained directly on kill (no pickup to chase; elites/boss give more), plus a bonus for clearing a wave. Shown next to the wave counter.
- **Pads and towers:** 6 pads at about 260 px from the nucleus. 4 tower types that reuse the existing weapon code from a fixed origin, 3 levels each:
  | Tower | Based on | Role |
  |---|---|---|
  | Bolt Spire | Pulse Bolt | Single target, long range, focuses elites |
  | Antibody Post | Antibodies | Orbs around the pad; block Spitter shots near the nucleus |
  | Fever Node | Fever Pulse | Area pulse + slow; crowd control at the core |
  | Spark Coil | Nerve Spark | Chain lightning; good against Spores |
  Your **might and haste** (level-ups and meta) also apply to towers, so the survivor half keeps mattering. No selling in v1.
- **Waves:** a table in `waves.json` (`defense.waves`): per wave a budget, enemy pool, active vents, elites, and the boss on wave 12. The next wave starts after a short breather (about 6 s, "Wave 5 in 3..2..1") once the field is nearly clear, or after a max timer so turtling can't stall. HUD: "WAVE 7/12".
- **Free Mode (after the win):** waves 13+ are generated from the last wave (budget and HP x about 1.15 per wave, an elite every wave, a boss every 5). The run already counts as a win; Free Mode adds gold per wave and records **best wave**. When the nucleus falls in Free Mode, the results screen still shows a win.
- **Player death:** no game over; respawn timer (`defense.respawn_s`). The `revive` ad is replaced by an optional rewarded **"Repair nucleus +50%"**, once per run, offered when the nucleus drops below 25%.
- Meta upgrades, banked level-ups, dash, chests and pickups all work as in other modes (own XP curve via the mode overrides).

### How it fits the code (for the build session)
- `data/modes.json`: new `"nucleus"` entry, overrides `defense.enabled: true`, territory off, its own XP curve, menu card (icon, colour, `special: best_wave`).
- `data/balance.json`: new `defense` block (nucleus hp/regen/radius, aggro_radius, pad count/radius/build time, biomass per kill/elite/wave, respawn_s, free-mode scaling). `data/towers.json` (new file in `GameData.FILES`): 4 towers x 3 levels with costs, each pointing at a weapon id plus stat deltas; validated like upgrades.
- **The dish without territory:** today the bounded dish (clamp, rim, spawn points) only exists when `territory.enabled`. Split the dish clamp/spawn logic from claiming (e.g. `territory.claiming: false`) rather than duplicating it. Check this first.
- `World` (rules stay in World): nucleus state (`core_pos`, `core_hp`), `_enemy_target(i)` used by enemy movement, enemy-vs-core contact damage, towers as small parallel arrays (`t_pad`, `t_type`, `t_level`, `t_cd`), `_update_towers()` reusing the weapon fire helpers with an origin, pad build progress in `_update_player`, biomass, respawn state, wave state machine (`wave`, `wave_state: spawning|breather`, `free_mode`). New events: `core_hit`, `core_low`, `tower_built`, `tower_upgraded`, `wave_start`, `wave_clear`, `respawn`, `defense_won`. New states: `tower_pick` (popup), `defense_won` (continue choice).
- `SpawnDirector`: wave-table mode (spawn at active vents) alongside the time-based budget.
- `WorldView`: nucleus, pads (with the fill ring), towers (few, so plain draws are fine), vent pulses. `HudOverlay`: nucleus bar, wave counter, biomass, respawn countdown. `Main`: tower-pick popup (reuse the card/popup style), continue screen, sounds/haptics.
- `Profile`: add `best_wave` to the per-mode record fields; make sure old saves without it load (default 0 in `from_dict`/`_record`; bump `Profile.VERSION` if the format changes). `online.json`: "Nucleus: best wave" leaderboard + 2-3 achievements.
- Bot: walk to a pad when biomass covers the next build/upgrade, otherwise fight near the nucleus. Sim report: waves cleared, nucleus HP left, towers built, win rate, best free-mode wave.
- Tests: nucleus damage and loss condition, aggro switch, pad build cost/progress, tower fires from its pad, wave table determinism, free-mode scaling, respawn, save loads without `best_wave`.
- Scope: CLAUDE.md rule 8 gets "4 tower types (Nucleus mode only, reusing the weapons)". Perf: at most 6 towers; their shots go through the existing bullet caps.

### Step 1 as built (2026-11-02)
- Everything in "Rules" above except the tower-pick popup (empty pads build the Bolt Spire), Free Mode, the boss-wave intro and the repair ad. 6 pads, 4 vents (each wave lists its vents; they pulse during the countdown), 12 waves.
- Building: stand on a pad, the ring fills in 0.9 s; step off and back on for the next level. HUD: "WAVE 3 / 12" or "WAVE 4 IN 3", nucleus bar, biomass, "Hold to build / Need 45 biomass", "REFORMING 5", and an off-screen arrow to the nucleus.
- **Enemy scaling is per wave in this mode** (`defense.hp_growth_per_wave` 0.5, `damage_growth_per_wave` 0.08) instead of per minute: runs last ~6 min, and stalling a wave shouldn't make the next one tankier.
- Bot (builds the cheapest affordable pad, otherwise defends near the nucleus), seeds 600/700/800 × 8: win 63% / 13% / 13% (~30%, like Classic), p50 3:17-5:50, waves cleared p50 6-12, level 11-13. Bimodal: runs either win or fall at wave 6-7 (first Lumps + Mitosis + an elite). Tuning path on the way: time-based growth 9% win → per-wave 0.25: 96% → 0.45: 58% → 0.55: 25% → 0.5.
- Perf: 0.72 ms per step at 150+ enemies (same as the other modes).

### Build order (each step ends with a phone playtest)
1. **Core loop:** dish without claiming, nucleus + targeting + core damage + loss, respawn, 3 vents, 6 pads, biomass, **Bolt Spire only**, a simple 12-wave table, HUD. Test question: *is defending fun, and does standing on pads feel good?*
2. **Depth:** all 4 towers with 3 levels and the pick popup, wave breathers/countdown and vent telegraphs, boss wave, win → COLLECT / KEEP GOING, Free Mode scaling.
3. **Polish and meta:** build/upgrade VFX and sounds, records, leaderboard and achievements, nucleus-repair ad, sim balance pass with the bot.

### Open (decide during step 1)
- Final mode name ("Nucleus" is a placeholder).
- Does the tower-pick popup pause the game like level-ups (proposed: yes)?
- Pad count 6 vs more pads unlocking at later waves.

## Step 3: combine
- Converts on your land stop erosion and patrol its edge. Unguarded land slowly decays.
- Elites and the boss corrupt chunks of land as they walk.
- Score: survive 5:00, with stars at 25/50/75% infected.
- Re-theme from immune cell to pathogen: names, colours and a new title (to decide).
- Guided first run (about 30 s): "loop to claim", "kill to convert".

## Step 4: content for launch (before the closed test)
- **Organ campaign**, 3 chapters at launch: Bloodstream (a current pushes everything), Lungs (the dish breathes in and out), Gut (acid pools). Each gets a palette, a hazard, a boss and stars.
- **Strains (characters):** 2 at launch, each a starting weapon plus a trait.
- Then the release plumbing: M3 (AAB, AdMob, Firebase) and M4 (store kit).

## Step 5: after launch (during or after the 14-day test)
- **Daily Outbreak:** a shared daily seed with leaderboards via Play Games Services. The simulation is deterministic, so replays can verify scores.
- Daily missions and streaks, more chapters (Brain, Heart), more strains, cosmetics.

## Scope note
This deliberately lifts the v1 cap from 1 map and 1 character to the chapters and strains listed above. Update `CLAUDE.md` rule 8 when Step 4 starts.

## Accounts, progress, leaderboards (decided 2026-11-03)
- **Built:** local `Profile` with lifetime stats, per-mode records and achievements; the `Online` facade with a stub; leaderboard definitions and the score formula in `data/online.json`; the Profile screen.
- **Later (after M3's Gradle/AAB switch): Google Play Games Services** as `PlayGamesBackend` behind `Online`. Implicit sign-in, Saved Games cloud sync (resolve with `Profile.merge`: counters/records/meta take the max, achievements union, gold/settings from the newer copy), leaderboards (IDs map from `data/online.json`), achievements. Yousuf chose Play Games over Firebase. Verify the Godot 4.7-compatible plugin first.
- Leaderboard metrics (agreed): per-mode score, Infection % infected, Swarm conversions. Daily Outbreak (shared seed) comes later.
