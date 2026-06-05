# Releasing the macOS app (signed + notarized DMG)

Produces a shareable `Alotno-<version>.dmg` that runs on any Mac without Gatekeeper
warnings. Distributed **outside** the App Store (Developer ID + notarization).

Everything is automated in [`scripts/release-macos.sh`](../scripts/release-macos.sh).
You only do the two prerequisites below **once**.

> Always the **personal** team `64HRGLZCS4` / `maksym.shykov@gmail.com`.
> Never the work team (`ZDF5LRFL76`).

## One-time setup

### 1. Developer ID Application certificate
You currently have only *Apple Development* certs — those can't sign for
distribution. Create the Developer ID cert under the personal team:

- **Xcode → Settings → Accounts** → select `maksym.shykov@gmail.com` → make sure
  the team **`64HRGLZCS4`** (your name, role *Account Holder*) is selected →
  **Manage Certificates…** → **＋** → **Developer ID Application**.
- Verify:
  ```sh
  security find-identity -v -p codesigning | grep "Developer ID Application" | grep 64HRGLZCS4
  ```
  You should see `Developer ID Application: … (64HRGLZCS4)`.

(Requires the paid Apple Developer Program membership, which the personal account has.)

### 2. Notarization credentials
- Create an **app-specific password**: https://appleid.apple.com → Sign-In & Security
  → App-Specific Passwords → generate (label e.g. "alotno-notary").
- Store it once as a keychain profile:
  ```sh
  xcrun notarytool store-credentials alotno-notary \
    --apple-id maksym.shykov@gmail.com \
    --team-id 64HRGLZCS4 \
    --password <the-app-specific-password>
  ```

## Release

```sh
scripts/release-macos.sh
```

It builds the release app, signs the frameworks + app (Developer ID, hardened
runtime, secure timestamp, with the sandbox entitlements), packages a DMG with an
`/Applications` shortcut, submits to Apple's notary service, staples the ticket,
and verifies. Output: `Alotno-<version>.dmg` at the repo root.

## What the script does (so you can audit it)
1. Auto-detects the Developer ID identity for team `64HRGLZCS4`.
2. `flutter build macos --release`.
3. Signs `FlutterMacOS.framework`, `App.framework`, `rust_lib_alotno.framework`
   (hardened runtime, no entitlements), then the `.app` (with
   `macos/Runner/Release.entitlements`).
4. `hdiutil` builds the DMG.
5. `xcrun notarytool submit --wait` then `xcrun stapler staple`.
6. `stapler validate` + `spctl` assessment.

## Troubleshooting
- **Notarization "Invalid"** → `xcrun notarytool log <id> --keychain-profile alotno-notary`
  shows which binary failed (usually an unsigned nested item or a missing hardened
  runtime flag).
- **App crashes after signing** → a hardened-runtime entitlement is missing; Flutter
  release (AOT) normally needs none, but check the crash log's signing-related lines.
- **Version** comes from `apps/app/pubspec.yaml` (`version:`); bump it per release.
