# Marketing plan (zero budget, ~1 hour a week)

Written 2026-11-11. Constraints from Yousuf: budget $0 (a couple of dollars at most), as little time as possible, whatever platforms give the best odds, and launch as soon as M3 is done.

## 1. The timeline problem first

The core game is ready, but launching within 2 weeks of today isn't possible:

- **No Play Console account yet.** It costs $25 one-off. Google requires the account holder to be an adult, so a parent may need to own it. Identity verification can take a few days.
- **Closed test:** personal accounts created after Nov 2023 need **12+ testers opted in for 14 days in a row** before Google grants production access. Organisation accounts are exempt, but they need a D-U-N-S number, which isn't worth it. Internal testing doesn't count towards this.
- **Production review** after that, usually a few days.

**Realistic launch: about 3-4 weeks after the Play Console account exists.** Use that wait for marketing: posting now means the first clips already have views when the game goes live.

| When | Game | Marketing |
|---|---|---|
| Week 0 (now) | M3 step 3 (Firebase). Create the Play Console account | Lock the name. Make the accounts (§3). Recruit testers (§5). First 2-3 clips |
| Week 1 | M3 step 4. Upload the AAB to closed testing, **start the 14 days** | 3 clips a week. Draft the store listing (§6) |
| Week 2-3 | Fix bugs from testers and Firebase | 3 clips a week. Finish the store kit. Write the launch posts |
| Launch week | Apply for production, then go live | Launch posts (§7). Link in every bio |
| After | Updates from data | 2-3 clips a week; repost the best clips |

## 2. What actually works at $0

Paid ads aren't worth it at this budget: a few dollars buys a handful of installs and teaches you nothing. Free short-form video is how solo mobile games get found now, and this game has two advantages for it:

1. **It's already 9:16 portrait** (720x1280), so screen recordings are native TikTok/Reels/Shorts videos with no editing.
2. **It looks chaotic on screen in the first second:** hundreds of germs, MEGA KILL slow motion, evolutions, the Mother Cell. That is exactly what short-video feeds reward.

**Goal for launch:** not "go viral". It's **12+ testers, then the first ~100-500 real players**, so the Firebase data shows where people quit. One clip can blow up by luck; posting regularly is what gives it that chance.

## 3. Platforms: one clip, three apps

Record once and post the **same clip** to all three. Every extra platform costs about 2 minutes and gives the clip another chance:

| Platform | Why | Note |
|---|---|---|
| **TikTok** | Best odds: new accounts get shown to strangers | Add a trending sound at low volume under the game audio |
| **YouTube Shorts** | Long-lived, searchable. The 15-30 s store trailer is a YouTube link anyway | Title = the hook text |
| **Instagram Reels** | The account that was already agreed | Same clip; post it as a Reel, not a photo post |

Use the **same handle everywhere** (e.g. `@petripanicgame`, once the name is locked). Put the itch.io link in each bio now and switch it to the Play Store link at launch.

**Reddit** (free, one post per milestone, not weekly): r/godot (loves "made in Godot" showcases and is very friendly), r/IndieDev, r/indiegames, then r/AndroidGaming at launch. Read each subreddit's self-promotion rules first and reply to every comment.

**Skip for now:** Discord servers, X/Twitter and a website. They're time sinks before you have players.

## 4. The weekly routine (~45-60 min a week)

**3 clips a week**, about 15 minutes each:

1. Play a run with the phone's built-in screen recorder on (Android: quick settings → Screen record). Turn the perf bar off (Settings → Developer). Dev gold is fine for showing late-game builds.
2. Trim it to **7-20 seconds**, starting on the action. The first second decides whether people scroll past.
3. Add one line of hook text (the in-app text tool is enough) and post it to all three apps.

Batch it: record 3 runs in one sitting and post one clip every 2-3 days (all three apps let you schedule posts).

**Possible shortcut:** Godot's Movie Maker mode can render gameplay to video headless. I could try rendering seeded bot runs (a MEGA KILL, an evolution, a Mother Cell fight) in the cloud, so your job would be just posting. Real play usually looks better, so treat this as a backup for busy weeks.

### Clip ideas (each one matches a feature the game already has)

| # | Clip | Hook text |
|---|---|---|
| 1 | MEGA KILL slow motion + shockwave | "25 kills in 0.3 seconds" |
| 2 | A weapon evolving, then shredding the screen | "Wait for the evolution..." |
| 3 | Mother Cell phase 3 spiral, dodged | "The final boss of the petri dish" |
| 4 | Perfect Dodge into Overdrive | "Dash at the last possible frame" |
| 5 | Infection: claiming a huge loop of territory | "Drawing a circle around 100 germs" |
| 6 | Swarm: a converted germ army on Hunt | "I turned the germs against each other" |
| 7 | Nucleus: towers holding wave 12 | "Tower defence, but you're a white blood cell" |
| 8 | Melody pop skin (kills play a tune) | "Every kill plays the next note" |
| 9 | First run vs maxed-account run, side by side | "Run 1 vs run 50" |
| 10 | Dying at 4:59 | "So close." (fails do numbers) |
| 11 | Devlog: "I'm a student making a mobile game solo" + gameplay | Story posts build followers. Share only what you're comfortable sharing |
| 12 | A poll: "Which skin next?" / "Name this germ" | Comments help reach |

Repost a clip that worked 2-3 weeks later with a new hook. That's normal and it works.

## 5. Testers (the real launch bottleneck)

- **Recruit 20, not 12**, because some never opt in. Ask friends, Nixor, and the CS revision class. Each person only has to join the test with their Google account, install the game and keep it for 14 days.
- Send one short message with the opt-in link and "please keep it installed for 2 weeks, and tell me one thing you hated".
- Backup: tester-swap communities (e.g. r/AndroidClosedTesting, r/TestersCommunity) where devs test each other's apps. Free, but expect low-effort testers.
- Testers are also your first reviewers at launch. Ask for an honest rating. **Never offer rewards for reviews or do review swaps**: that breaks Play policy.

## 6. Store listing (part of M4; free tools only)

The store page is the most important marketing asset. Everything above sends people to it.

- **Lock the name before posting anything** (D-006 is still open). Search the Play Store and Google for clashes. Renaming later loses search history and makes the handles wrong.
- **Icon:** bold, readable at 48 px, one big shape (the white cell with an angry germ). Make it in an AI image tool or Canva (free).
- **Feature graphic** (1024x500): Canva, free.
- **8 screenshots** of real gameplay chaos, each with a 3-5 word caption ("Evolve your weapons", "Outlast 5 minutes", "4 game modes", "Play offline").
- **Short description** (80 characters) with search words, e.g.: "Survive the swarm! A bullet-heaven roguelite: auto-attack, evolve, play offline."
- **Keywords for the full description:** roguelite, survivor, bullet heaven, auto shooter, offline, one-thumb, short runs, upgrades.
- **Wording:** avoid "pandemic", "virus outbreak" and "infection" in the store text and any ad creatives. They can trigger Google's sensitive-events review (LAUNCH_READINESS). "Germs", "microbes" and "petri dish" are fine.
- Keep the art looking aimed at teens and adults, not children (Families-policy risk).
- **Trailer:** your best 3 clips stitched into 15-30 s, uploaded to YouTube and linked in the listing.

## 7. Launch week

- Post "It's out!" on all three apps with the best clip. Pin it, and put the Play link in every bio.
- Post once each on r/AndroidGaming, r/IndieDev and r/godot, following each sub's rules. A short honest story works best ("student solo dev, first game, made in Godot, free and playable offline").
- Message every tester and friend: "it's live, an honest review would really help".

## 8. How to tell what's working

- **Play Console → Store listing conversion:** under ~25% of visitors installing means the icon/screenshots need work.
- **Firebase (M3 step 3):** day-1 retention, where runs end, whether people finish Patient Zero.
- **Clips:** note views per clip in a simple list and make more of the kinds that win.

## 9. What Claude can do vs what only you can do

| Claude (cloud session) | Yousuf |
|---|---|
| Draft store text, captions, hook lines and tester messages | Own the Play Console, social accounts and posting |
| Render bot clips with Movie Maker (to try) and screenshots via xvfb | Record real play on the phone |
| Code an in-app review prompt after a win (Play In-App Review, post-launch) | Recruit testers, reply to comments |
| Track the plan in this doc | Make or pick the icon and feature graphic |
