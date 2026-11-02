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
