# Co-op mode: design and feasibility

**Status:** idea / design draft (2026-11-05). **Not before launch:** planned as a post-launch update, once the game is on Google Play. Nothing here is built. Open decisions are marked **[decide]**.

## 1. Pitch
2-4 friends in the same dish. A simple Classic or Infection run at **Virulence 1** with co-op modifiers: shared XP, a down/revive system, and each player bringing a different Lab ability as their role. A separate **Tethered** mode links players with a tether that hurts germs (and, in Infection, claims land when you loop it).

## 2. Feasibility summary
**Verdict: doable post-launch, roughly 2-3 months at 6-8 h/week.** Most of the work is networking and lobbies, not gameplay.

What already helps:
- All gameplay lives in `World`, separate from rendering and sound (`WorldView`, `Main`). One phone can run the World and the others only draw what it sends.
- Level-ups are already **banked and non-pausing** (`balance.upgrades.bank_levelups`), which a shared world needs.
- Nucleus mode already has a **downed → respawn** state (`p_down`), the base for revive.
- The four Lab abilities (Stasis, Engulf, Cloak, Mitosis) already give natural roles.
- Bot sims and seeded tests exist, so co-op balance can be checked the same way (a "party of bots").

The hard parts:
1. **No real-time multiplayer from Google.** Play Games Services removed real-time multiplayer in 2020; it now covers only sign-in, saved games, leaderboards and achievements. Lobbies, invites and relays need a separate service (section 6).
2. **`World` assumes one player.** `p_pos`, `p_hp`, `p_vel`, dash state, iframes, ability state, `_hurt`, contact damage, pickups and enemy targeting are all single values. They become per-player arrays (the same struct-of-arrays style the enemies use). This is the biggest code change, mechanical but wide; the tests catch regressions.
3. **Pausing states.** Chests (`state == "chest"`), the level-up picker (`"levelup"`) and the BUILD overlay pause the run. In co-op they must not pause: each player opens their own picker while the world keeps running (for example with a short personal invulnerability window while the picker is open).
4. **Mobile reality.** If the host closes the app, the run ends (host migration is out of scope). Drop-outs and reconnects need handling; poor mobile connections need tolerance.
5. **Performance.** Four players' weapons multiply bullets and effects; the existing caps (`perf.max_projectiles` 220, `max_effects` 140) must hold on the cheap phone, and the host phone pays for the simulation (~0.7 ms per step today on desktop for one player).

## 3. Networking model
**Recommended: host-authoritative snapshots.**
- One phone (the host) runs `World` exactly as today. Clients send their **input** (joystick vector, dash, ability, Outbreak, level-up picks) every frame.
- The host sends **state snapshots** about 20 times a second: player positions/HP/state, enemy positions + type + HP fraction, bullets, gems, pickups, and the gameplay events (`hit`, `kill`, `nova`, ...) that drive effects and sound.
- Clients **interpolate** between snapshots for everything, and **predict their own movement** locally so steering feels instant (corrected toward the host's position).
- Size: about 170 enemies × ~6 bytes ≈ 1 KB per snapshot plus bullets and events, so roughly 20-40 KB/s. Fine on mobile data; can be delta-compressed later.

**Rejected: lockstep** (every phone simulates the same World from shared inputs). It needs bit-identical results on every device. GDScript maths (sin/cos, float rounding) can differ between phones, and one laggy phone stalls everyone. Not worth the risk on Android.

**Transport:** Godot's high-level multiplayer API (`MultiplayerAPI` + ENet for LAN, or WebRTC / the relay service's transport online), behind a new facade so no SDK calls leak into gameplay code (same rule as `Ads` and `Online`).

## 4. Features
### 4.1 Co-op core (Classic or Infection, V1)
- **Party size 2-4.** Germ HP and spawn budget scale with party size, for example HP ×(1 + 0.5 per extra player) and budget ×(1 + 0.6 per extra player). Numbers go in a `coop` block in `balance.json` and are tuned with party-of-bots sims.
- **Shared XP:** everyone levels together, but each player picks their own card. Simple, and nobody falls behind.
- **Gold and Genes:** everyone gets their own reward at the end. **[decide]** full rewards, or reduced so co-op isn't the best farm.
- **Outbreak:** one shared meter; any player can trigger it, and the frenzy applies to all.
- **Germ targeting:** each germ chases the nearest living player (one more loop in enemy targeting).

### 4.2 Down and revive
- At 0 HP a player is **downed**: they crawl slowly and can't attack, with a **bleed-out timer** (~20 s).
- A teammate standing next to them for **~3 s** revives them at ~30% HP (a ring fills, as on Nucleus build pads).
- The run ends when **every** player is down.
- Optional: one free self-revive per run. The existing revive ad could become "revive the whole party".
- **Feasibility: easy.** Builds on the Nucleus downed state and the pad-fill ring UI.

### 4.3 Roles = abilities
- Each player brings their equipped Lab ability, **no duplicates in a party**, so roles fall out naturally:

  | Ability | Role | In co-op |
  |---|---|---|
  | Stasis | Controller | Freezes germs for everyone; teammates line up shots |
  | Engulf | Tank | Wades into crowds and soaks contact |
  | Cloak | Decoy / scout | Germs lose them and chase teammates (or a planted decoy) |
  | Mitosis | Damage | Clone adds firepower |

- Optional small role passives, for example "Tank: germs prefer to target you", "Controller: +20% Stasis radius".
- A player with no ability unlocked yet gets a basic co-op ability (for example a heal pulse), so new players can join.
- **Feasibility: easy** (abilities exist); tuning is the work.

### 4.4 Tethered (a separate co-op mode)
- Players are linked by a tether with a maximum length; at full stretch it pulls them together.
- **The tether damages germs that cross it** (a line hit-check each step, like a laser).
- **In Infection, a closed loop formed by the tether claims land.** This is a genuinely new mechanic that only co-op can offer.
- 3-4 players: a chain (A-B-C-D) or a ring. **[decide]**
- **Feasibility: easy to medium** (distance constraint + segment hit-check; the loop-claim reuses Territory's flood fill).

## 5. Open decisions
1. **Upgrades in co-op [decide]:** players bring their own shop + Lab bonuses (rewarding, but a maxed friend carries a new one), or everyone is normalised at V1. Suggested middle ground: bring them, and scale germs to the party's **average** power.
2. **Friends only or random matchmaking [decide]:** friends via room codes / invite links is much simpler, and random matchmaking needs players online at the same time, which a new game won't have. **Recommendation: friends only.**
3. **Rewards [decide]:** full or reduced gold and Genes.
4. **Which base mode first [decide]:** Classic (simplest) or Infection (more interesting with the tether).
5. **Tether topology for 3-4 players [decide].**
6. **Co-op leaderboards and achievements:** probably yes, via `Online`.

## 6. Lobby / relay service options
Needed for online play (not for same-Wi-Fi play).

| Option | Cost | Notes |
|---|---|---|
| **W4 Cloud** | Free tier, then paid | Made by Godot core developers; Godot-native lobbies and relay |
| **Epic Online Services (EOS)** | Free | Lobbies, P2P with relay fallback; community Godot plugin |
| **Nakama** (Heroic Labs) | Free to self-host; paid cloud | Open source; matchmaking, parties, realtime |
| Own relay / signalling server | A small VPS | Cheapest per month, but most work plus a TURN server for NAT traversal |

**Lean: EOS or W4** (free or cheap at small scale). Verify Godot 4.7 support at the time; this changes quickly.

## 7. Phased plan (post-launch)
0. **Now (pre-launch):** build nothing. Just avoid making `World` more single-player-shaped (keep player state in one place, keep input as data).
1. **Per-player refactor + same-Wi-Fi co-op** with Godot's ENet. No servers; proves the fun cheaply. Includes shared XP, party scaling, non-pausing pickers, down/revive. Party-of-bots sim for tuning.
2. **Online:** room codes through the chosen relay service, reconnect handling, roles (no duplicate abilities), co-op rewards.
3. **Tethered mode** and co-op leaderboards/achievements.

Rough effort at 6-8 h/week: phase 1 ≈ 4-6 weeks, phase 2 ≈ 3-4 weeks, phase 3 ≈ 2-3 weeks. Testing needs at least 2 real phones (more for 4-player).

## 8. Risks
- Scope: co-op is a large feature for a solo developer; it competes with post-launch fixes and content. Ship phase 1 only if it's clearly fun.
- Host leaves = run over (accept for v1).
- Network quality on mobile data: test on real 4G, not only Wi-Fi.
- Balance across party sizes and mixed upgrade levels (decision 1).
- The relay service's pricing or Godot support changing.
