# Releasing Alotno (signed + notarized, distributed outside the App Store)

This produces a signed, notarized, Gatekeeper-approved `.dmg` that users can
download and run without warnings. It is **not** a Mac App Store listing (that
would require sandboxing — see the note at the bottom).

---

## One-time setup

### 1. Apple Developer account
- Enroll in the **Apple Developer Program** ($99/yr). A free account cannot
  create the certificate below.

### 2. Create a "Developer ID Application" certificate
You currently only have *Apple Development* certificates, which **cannot** sign
for distribution. Create the right one:

- Xcode → Settings → Accounts → select your team → **Manage Certificates** →
  **+** → **Developer ID Application**.
- Verify it landed in your keychain:
  ```sh
  security find-identity -v -p codesigning | grep "Developer ID Application"
  ```
  You should see something like `Developer ID Application: Your Name (TEAMID)`.

### 3. Create an app-specific password for notarization
- Go to https://appleid.apple.com → Sign-In & Security → **App-Specific Passwords**.
- Generate one (e.g. labelled "alotno-notarize"). Save it.

### 4. Find your Team ID
- https://developer.apple.com/account → Membership → **Team ID** (10 chars).

### 5. Set credentials as environment variables
electron-builder reads these automatically when `notarize: true`:
```sh
export APPLE_ID="your-apple-id@example.com"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="YOURTEAMID"
```
(Keep these out of git — they're covered by `.gitignore` if you put them in `.env`.)

---

## Before each release

1. **Replace the placeholder icon** at `build/icon.icns` with the real Alotno
   icon (1024×1024 source → `.icns`; e.g. `iconutil` or an app like Image2icon).
2. **Bundle id** is `app.alotno` (reverse-domain of alotno.app) in `package.json`
   (`build.appId`). Keep it stable across releases.
3. **Bump the version** in `package.json`.

---

## Build

```sh
npm install          # regenerates the lockfile (electron-builder replaced @electron/packager)
npm run dist
```

`electron-builder` will: build for arm64 + x64, code-sign with your Developer ID
cert, staple a hardened runtime, submit to Apple's notary service, wait for the
result, staple the ticket, and emit `release/Alotno-1.0.0-arm64.dmg` (+ x64, + zips).

### Verify the output
```sh
# Signature valid + hardened runtime
codesign -dv --verbose=4 "release/mac-arm64/Alotno.app"
# Notarization stapled
xcrun stapler validate "release/mac-arm64/Alotno.app"
# Gatekeeper accepts it
spctl -a -vvv -t install "release/mac-arm64/Alotno.app"
```
All three should pass. Then ship the `.dmg`.

---

## Troubleshooting
- **"No identity found" / signs ad-hoc** → the Developer ID Application cert is
  missing or not in the login keychain (step 2).
- **Notarization fails with "invalid"** → run
  `xcrun notarytool log <submission-id> --apple-id ... --team-id ... --password ...`
  to see which binary was rejected. Usually an unsigned native lib — the
  `entitlements.mac.plist` + `disable-library-validation` handle `sharp`.
- **App crashes on launch after signing** → almost always a missing hardened-
  runtime entitlement; the JIT/unsigned-memory keys in `build/entitlements.mac.plist`
  are required for Electron.

---

## If you later want the actual Mac App Store
That's a different build (`mas` target) and requires:
- The **App Sandbox** entitlement (`com.apple.security.app-sandbox`).
- Reworking file output: under the sandbox the app can't create files next to a
  selected source file. You'd have to require the user to pick an **output
  folder** (which grants write access to it) and add
  `com.apple.security.files.user-selected.read-write`.
- *Apple Distribution* + *Mac Installer Distribution* certs and a provisioning profile.
Ask and I'll set up a parallel `mas` configuration.
