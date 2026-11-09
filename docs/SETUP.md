# Things only you can do (step by step)

## 1. Web playtest build (itch.io, set up 2026-11-04)
The web build is on your itch.io project **light213/petri** (restricted page), at light213.itch.io/petri. Claude uploads a new build after every change with `tools/web_push.sh` (using butler and the `BUTLER_API_KEY` you added to the cloud environment); the menu shows the build code so you can tell which version you're playing.
- If a new Claude session can't upload, check that `BUTLER_API_KEY` is still set in the cloud environment settings (environment menu in the session's title bar → Edit), and as a GitHub repository secret for the backup workflow (**Actions → Web playtest build → Run workflow**).
- The itch page settings (one-time, already done): "This file will be played in the browser", viewport 720 x 1280, Mobile friendly (portrait), Fullscreen button.
- A new host starts with an empty save: use Settings → DEVELOPER (code 1289) → +10,000 gold / All Virulence levels.
- GitHub Pages is no longer used (its deploy step kept timing out).

## 2. Android signing keystore → GitHub secrets (10 minutes, needed before Play upload)
Do this once on your PC. Java is required for `keytool`; Android Studio bundles it, or install Temurin JDK 17.
```bash
keytool -genkeypair -v -keystore petri-release.keystore -alias petri -keyalg RSA -keysize 2048 -validity 10000
```
It asks for a password (use a long one) and your name and country. Then:
- **Back up `petri-release.keystore` and the password somewhere safe** (a password manager or a USB drive). If you lose it you can never update the app.
- **Never commit it.** `.gitignore` already blocks `*.keystore`.

Base64-encode it for GitHub:
- Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("petri-release.keystore")) | Set-Clipboard`
- Linux/macOS: `base64 -w0 petri-release.keystore`

On GitHub, go to **Settings → Secrets and variables → Actions → New repository secret** and add:
| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the base64 text |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `petri` |

The next **Android build** run produces a signed release APK. Without these secrets it produces a debug APK, which is fine for testing on your own phones.

## 3. Test the APK on your phone (step by step)
The web build is only for quick checks. **Judge feel and performance on the APK**, because it runs natively and is usually much faster than the browser.

**A. Build it (about 4 minutes)**
1. On GitHub, open the repo and go to the **Actions** tab, then **Android build** in the left list.
2. Click **Run workflow**, keep the branch as it is, and press the green **Run workflow** button.
3. Wait for the green tick, then open the run. At the bottom, under **Artifacts**, click **petri-panic-apk-N** to download it. You must be logged in to GitHub; on the phone, use the GitHub website in Chrome rather than the app.

**B. Install it**
1. The download is a **.zip**. Open it in the phone's **Files** app (Files by Google can do this), tap it and choose **Extract**. You get `petri-panic.apk`.
2. Tap `petri-panic.apk`. Android asks you to allow installing from this source: tap **Settings**, turn on **Allow from this source** (for Files or Chrome), then go back.
3. Tap **Install**. If Play Protect warns "app not scanned" or "unsafe", tap **More details**, then **Install anyway**. It's your own unsigned test build, and the warning is normal.
4. **Updating to a newer build:** until you add the signing secrets (§2), every CI build is signed with a different throwaway key, so Android refuses to install over the old one ("App not installed" or "package conflicts"). **Uninstall the old version first** (this also resets your gold). Once the §2 secrets exist, builds install over each other and your progress is kept.

**C. What to test (about 15 minutes per phone, ideally the cheap one too)**
At the bottom of the screen you'll see a yellow line like `58 fps 165 enemies sim 1.1 ms`. That's the performance readout.
- [ ] **Performance:** play past 2:30 (the busiest part) and note the **lowest fps** you see and the enemy count at that moment. 55-60 is great, 40-50 is OK, below 30 needs work.
- [ ] **Controls:** does the joystick respond instantly? Does the player stop when you lift your finger?
- [ ] **Sound:** do hits and level-ups sound in time with the action, or late?
- [ ] **Vibration:** a short buzz when you're hit, a longer one on death.
- [ ] **Interruptions:** press Home mid-run, then come back. The game should be paused. Do the same with the Back button.
- [ ] **Level-up screen:** can you mis-tap a card while dragging? (There's a 0.35 s guard.)
- [ ] **Heat and battery** after 3 runs: is the phone warm?
- [ ] **Readability:** can you tell enemy types apart? Can you see Lancers flash before they dash?

**D. Send me notes like this**
> Cheap phone (Samsung A10): lowest 34 fps at 3:10 with 170 enemies, sim 4 ms. Joystick fine. Sound ~0.2 s late. Lancers hard to see.

Phone model, fps, time and enemy count let me pin down whether the drawing or the simulation is the bottleneck.

## 4. Accounts (start on day 1, verification takes days)
- [ ] **Google Play Console** developer account ($25 one-time; the account holder must be 18+). Choose a *personal* account. Note whether it says you need a closed test with 12 testers for 14 days.
- [ ] **AdMob** account. Don't create real ad units until M3; we develop with Google's test IDs. **Never tap your own live ads.**
- [ ] **PSEB** registration (export tax benefit). Confirm the details with an accountant.
- [ ] **Testers:** collect 12+ Gmail addresses from people who will actually install and open the game over 14 days.

## 5. Later (M3/M4)
- Firebase project, with `google-services.json` added as a CI secret (not committed).
- A Play Console service account JSON as a CI secret, so CI can upload to closed testing (after your first manual upload).
- App icon and store art from an image tool (512x512 icon, 1024x500 feature graphic).

## 6. AdMob (when your account is ready, M3 step 2 is built)
The game shows Google's **test ads** until you add these. Never tap your own live ads.
1. In AdMob: **Apps → Add app** → Android, not yet on Play → name "Petri Panic". Copy the **App ID** (`ca-app-pub-…~…`).
2. **Ad units → Add**: one **Rewarded** ("rewarded") and one **Interstitial** ("between runs"). Copy each **Ad unit ID** (`ca-app-pub-…/…`).
3. GitHub → Settings → Secrets and variables → Actions → add `ADMOB_APP_ID`, `ADMOB_REWARDED_ID`, `ADMOB_INTERSTITIAL_ID`.
4. The next **Store build (AAB)** uses them. Test APKs keep test ads on purpose.
5. In AdMob → **Privacy & messaging**, create a **GDPR message** (and the US states message) for the app, so the consent form appears for EU/UK players.

