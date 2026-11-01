# Things only you can do (step by step)

## 1. Turn on the web playtest build (2 minutes, do this first)
1. In the repo on GitHub, go to **Settings → Pages**. Under **Build and deployment → Source**, choose **GitHub Actions**.
2. Go to **Actions → Web playtest build → Run workflow** and pick the branch (the default branch, or `main` once it exists).
3. When it finishes (about 3-5 min), the run page shows the URL, something like `https://yousufkamran222-code.github.io/survivor-lite/`. Open it on your phone and use **Add to Home screen** for one-tap access.
4. From then on, every merge into `main` redeploys automatically.

> If the deploy step says the branch is "not allowed to deploy to github-pages", go to **Settings → Environments → github-pages** and add the branch under deployment branches (or merge into `main`).

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
