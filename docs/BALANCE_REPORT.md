# Balance report: 2026-11-05 (after the Lab rework and shop split)

All numbers come from BalanceBot, which plays worse than a good human at high Virulence and better at "never panicking". Read them as **shape and relative change**, not truth (CLAUDE.md: the bot win rate is a sanity alarm).

**What changed in this batch:** the Lab middle nodes are now 16 play-changing nodes (no shop stats); the shop has 2× tiers at the same caps (~1.7× the gold); Lysis and Volatile no longer scale with the Virulence ramp; Genes are 4..13 per first clear and 2 per repeat win.

## 1. Win rate by Virulence (level sweep)
16 runs per cell, seed 100. Cell = win %, survival p10/p50/p90 in seconds, level_p50. "Lab" = full Lab (first fork sides) + Cloak Lv3 + maxed shop.

| Mode | V | No upgrades | Maxed shop | Shop + full Lab |
|---|---|---|---|---|
| Classic | 1 | 56% 152/300/300 L12 | 100% L40 | 100% L40 |
| | 3 | 0% 68/138/233 L2 | 69% 259/300/300 L29 | 100% L40 |
| | 5 | 0% 63/137/138 | 19% 161/234/300 L16 | 100% L43 |
| | 7 | 0% | 13% 132/201/300 L11 | 100% L42 |
| | 8 | 0% | 0% 131/200/256 L8 | 88% L20 |
| | 9 | 0% | 0% 160/203/262 L7 | 69% 250/300/300 L15 |
| | 10 | 0% | 0% 63/157/219 L4 | 81% 284/300/300 L13 |
| Infection | 1 | 19% 138/164/300 L17 | 100% L39 | 100% L45 |
| | 3 | 0% 25/34/46 | 75% 205/300/300 L40 | 100% L43 |
| | 5 | 0% | 13% 136/189/300 L24 | 100% L44 |
| | 7 | 0% | 0% 39/51/82 L8 | 100% L43 |
| | 8 | 0% | 0% 27/33/43 | 94% L43 |
| | 9 | 0% | 0% 20/23/32 | 88% L42 |
| | 10 | 0% | 0% 15/19/24 | 56% 153/300/300 L39 |
| Swarm | 1 | 25% 79/175/300 L14 | 100% L32 | 100% L31 |
| | 3 | 0% 44/62/137 | 100% L32 | 100% L31 |
| | 5 | 0% | 25% 165/196/300 L22 | 100% L34 |
| | 7 | 0% | 6% 75/142/224 L16 | 100% L34 |
| | 8-10 | 0% | 0% | **100%** L33-34 |
| Nucleus | 1 | 44% 196/208/372 L11 | 100% L18 | 100% L16 |
| | 3 | 0% 111/140/146 | 88% L19 | 100% L17 |
| | 5 | 0% | 0% 135/166/194 L12 | 100% L19 |
| | 7 | 0% | 0% 77/102/132 | 100% L20 |
| | 8 | 0% | 0% | 63% 128/320/333 L21 |
| | 9 | 0% | 0% | 44% 123/204/338 L17 |
| | 10 | 0% | 0% | 0% 80/120/138 L10 |

**Reading it:**
- **No upgrades:** only V1 is winnable (19-56%). The real target is "a good player's first win in 3-5 runs" at V1, and the bot gets there in 1-10 runs (section 3).
- **Maxed shop:** clears V3 (69-100%), sometimes V5 (0-25%), almost never V7+. That matches the design ("a maxed shop clears V3-4, barely V5").
- **Shop + full Lab:** V7-8 is easy everywhere except Nucleus V8 (63%). V9-10 is "decent" in Classic and Infection (56-88%), **too easy in Swarm (100% at V10)** and **too hard in Nucleus V10 (0%)**.

## 2. Old Lab vs new Lab (rule 2 before/after)
Maxed shop + full Lab, no ability, seed 100 (24 runs at V5/7/9, 12 at V8/10). p10/p50/p90 s, win, level_p50.

| | Old Lab (shop-stat middle nodes, after the dash fix) | New Lab (play-changing middle nodes, Lysis fix) |
|---|---|---|
| Classic V5 | 300/300/300 100% L45 | 300/300/300 100% L43 |
| Classic V7 | 236/300/300 71% L44 | 300/300/300 100% L43 |
| Classic V9 | 170/241/300 17% L20 | 190/300/300 67% L15 |
| Classic V10 | 227/300/300 50% L12 | 300/300/300 92% L12 |
| Infection V5 | 300/300/300 100% L45 | 300/300/300 100% L43 |
| Infection V7 | 300/300/300 96% L45 | 300/300/300 100% L43 |
| Infection V9 | 148/300/300 67% L44 | 300/300/300 96% L43 |
| Infection V10 | 51/188/300 17% L29 | 67/258/300 25% L27 |
| Swarm V8 | 300/300/300 100% L35 | 300/300/300 100% L34 |
| Nucleus V8 | 180/324/328 83% L20 | 124/294/331 42% L18 |

The new Lab is **stronger** in Classic and Infection at V7-9 (the new sustain nodes: Feed, Clotting, Last Stand, Evasion), **weaker** in Nucleus (where the old flat HP/damage mattered more than the new conditional nodes) and unchanged in Swarm (already at 100%).

## 3. Account progression (campaign sim)
`tools/sim/campaign_sim.gd`: a fresh profile plays up to 300 runs in one mode, always at the highest unlocked Virulence, buying the cheapest shop tier and the cheapest open Lab node after each run. Two "push" accounts per mode (seeds 1 and 2) and one "farm" account (after 5 losses in a row it replays its highest cleared level once, for repeat-win Genes).

**Run on which each Virulence level was first cleared**

| Account | V1 | V2 | V3 | V4 | V5 | V6 | V7 | V8 | V9 | V10 | Hours |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Classic push 1 | 3 | 8 | 16 | 28 | 32 | 33 | 44 | 52 | 134 | 254 | 10.0 |
| Classic push 2 | 1 | 2 | 28 | 36 | 46 | 48 | 64 | 70 | - | - | 13.0 (300 runs) |
| Classic farm | 3 | 8 | 22 | 36 | 47 | 61 | 81 | 102 | 256 | 261 | 13.5 |
| Infection push 1 | 9 | 17 | 21 | 29 | 52 | 106 | 130 | - | - | - | 8.5 |
| Infection push 2 | 10 | 12 | 23 | 37 | 45 | 110 | 136 | 183 | - | - | 6.9 |
| Infection farm | 9 | 17 | 21 | 36 | 50 | 90 | 107 | 177 | - | - | 9.9 |
| Swarm push 1 | 1 | 2 | 17 | 18 | 23 | 34 | 37 | 76 | 88 | - | 9.9 |
| Swarm farm | 1 | 2 | 10 | 12 | 15 | 24 | 41 | 58 | 185 | 190 | 6.9 |
| Nucleus push 1 | 5 | 13 | 21 | 25 | 116 | 190 | 226 | - | - | - | 11.0 |
| Nucleus push 2 | 5 | 6 | 7 | 8 | 159 | 190 | - | - | - | - | ~11 |

**Shop (29,496 gold for everything):**

| Mode | Gold per run | Shop 25% / 50% / 100% at run |
|---|---|---|
| Classic | 50-90 | 115-123 / 226-241 / not by 300 (~400 runs) |
| Nucleus | 70-105 | 98-106 / 184-187 / not by 300 (75% at ~270) |
| Infection | 65-190 | 36-37 / 74-86 / **88-140** |
| Swarm | 95-260 | 28-36 / 50-64 / **102-146** |

**Lab (238 Genes for everything):** Genes earned in 300 runs: **49-85 (push)**, **59-91 (farm)**. That's 20-38% of the Lab. **No account ever reached an ability.** A whole mode's first clears are worth only 85 Genes (4+5+…+13), and the bot pushes far more than it repeats.

## 4. What an average player's journey looks like (bot-based estimate)
Average run length is ~1.5-2.5 min (the bot dies early at its frontier; a won run is 5:00).

1. **First session (runs 1-10, ~20-30 min):** first V1 win (Classic or Swarm within 1-3 runs, Infection ~10). Gold buys the cheap first shop tiers (+5 HP, +2% damage) every run, so every run ends with a purchase. **Good.**
2. **Days 1-3 (runs 10-50, ~2 h):** V2-V5 fall one by one, roughly every 5-15 runs. The first Lab nodes arrive with the first Genes (4-8 per clear). **Good pacing.**
3. **The wall (runs 50-150+, 3-6 h):** V6-V9 take 20-100+ runs each. Shop tiers now cost 150-600 gold against 70-190 gold per run (Classic/Nucleus: one tier every 2-6 runs). Genes trickle in only on a new clear, so the Lab barely moves (20-35%). **This is where players would quit:** a long grind with the second progression layer mostly frozen.
4. **Endgame (V9-10):** reached only by Swarm and Classic accounts after 190-260 runs (7-13 h), without abilities ever unlocked.

## 5. Problems found and suggested fixes
**Status (2026-11-05):** #1 and #2 are applied (Yousuf chose the recommended fixes): Genes per completed minute at V3+ (`lab.genes.per_minute` 1, `per_minute_max` 5) and `economy.mode_gold_mult` (Classic ×2.0, Nucleus ×1.8, in `modes.json`). **#3 (Swarm + Lab too strong) and #4 (Nucleus V10 wall) are deferred**, tracked in SESSION_HANDOFF §10 and ROADMAP. #5 (V6/V9 spikes) is open.

1. **Genes are far too scarce (biggest issue).** The Lab is meant to carry players through V7-10, but at most ~38% of it is affordable by then. Options:
   - (a) **Genes on every run that gets far:** e.g. 1 Gene per completed minute at V3+ (a 5:00 win = 5). That gives ~2-3 per run, so the full Lab takes ~100 runs.
   - (b) Bigger first clears (e.g. 10, 12, …, 28 → 190 per mode) and repeat wins worth 4.
   - (c) Halve Lab costs (full Lab ~120).
   My pick is **(a)**: losing runs still feed the Lab, which keeps the wall from feeling frozen.
2. **Classic and Nucleus pay too little gold:** ~400 runs to max the shop vs ~120 in Infection and Swarm. Raise `economy.gold_per_kill` / `gold_per_minute` for those modes (a per-mode `gold_mult` in `modes.json`), or lower the shop's top tiers.
3. **Swarm + full Lab is too strong** (100% at V10). Likely the sustain nodes (Feed + Clotting + Last Stand) stack with allies soaking hits. Measure with `--labx feed,clot,last_stand`, then tone down per mode.
4. **Nucleus V10 is a 0% wall** even with everything, and the new Lab is weaker there (83% → 42% at V8). The defence nodes rarely matter when the nucleus, not you, is what dies. Nucleus-specific Lab nodes (the planned "Specialisations" row) or a lower Nucleus `ramp_scale`.
5. **V6 and V9 are spike levels:** Thin membrane (V6) and Virulent (V9) cost 20-100+ runs on their own in several accounts.
