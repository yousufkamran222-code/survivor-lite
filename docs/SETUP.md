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

## 3. Install a test APK on your phone
**Actions → Android build → Run workflow**, then download the `petri-panic-apk-N` artifact from the run (a zip containing the apk). On the phone, allow "install unknown apps" for your browser or file manager and open the apk.

## 4. Accounts (start on day 1, verification takes days)
- [ ] **Google Play Console** developer account ($25 one-time; the account holder must be 18+). Choose a *personal* account. Note whether it says you need a closed test with 12 testers for 14 days.
- [ ] **AdMob** account. Don't create real ad units until M3; we develop with Google's test IDs. **Never tap your own live ads.**
- [ ] **PSEB** registration (export tax benefit). Confirm the details with an accountant.
- [ ] **Testers:** collect 12+ Gmail addresses from people who will actually install and open the game over 14 days.

## 5. Later (M3/M4)
- Firebase project, with `google-services.json` added as a CI secret (not committed).
- A Play Console service account JSON as a CI secret, so CI can upload to closed testing (after your first manual upload).
- App icon and store art from an image tool (512x512 icon, 1024x500 feature graphic).
