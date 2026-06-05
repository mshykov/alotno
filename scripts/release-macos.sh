#!/usr/bin/env bash
#
# Build → sign (Developer ID + hardened runtime) → DMG → notarize → staple.
# Produces a shareable, Gatekeeper-approved Alotno-<version>.dmg.
#
# ONE-TIME PREREQUISITES (see docs/releasing-macos.md):
#   1. A "Developer ID Application" certificate for the PERSONAL team 64HRGLZCS4
#      in your login keychain (create in Xcode → Settings → Accounts).
#   2. A stored notarytool credential profile named "alotno-notary":
#        xcrun notarytool store-credentials alotno-notary \
#          --apple-id maksym.shykov@gmail.com --team-id 64HRGLZCS4 \
#          --password <app-specific-password>
#
# Usage:  scripts/release-macos.sh
set -euo pipefail

TEAM_ID="64HRGLZCS4"                       # personal paid team — NEVER the work team
NOTARY_PROFILE="alotno-notary"
APP_DIR="apps/app"
ENTITLEMENTS="$APP_DIR/macos/Runner/Release.entitlements"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# --- preflight: signing identity -------------------------------------------------
IDENTITY="$( { security find-identity -v -p codesigning \
  | grep "Developer ID Application" | grep "$TEAM_ID" \
  | head -1 | sed -E 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.*)"$/\1/'; } || true )"
if [[ -z "${IDENTITY:-}" ]]; then
  echo "❌ No 'Developer ID Application' cert for team $TEAM_ID in the keychain."
  echo "   Create it: Xcode → Settings → Accounts → (gmail Apple ID) →"
  echo "   Manage Certificates → + → Developer ID Application."
  exit 1
fi
echo "✓ Signing identity: $IDENTITY"

# --- preflight: notary credentials ----------------------------------------------
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "❌ No notarytool profile '$NOTARY_PROFILE'. Create it once:"
  echo "   xcrun notarytool store-credentials $NOTARY_PROFILE \\"
  echo "     --apple-id maksym.shykov@gmail.com --team-id $TEAM_ID --password <app-specific-pw>"
  exit 1
fi
echo "✓ Notary profile: $NOTARY_PROFILE"

VERSION="$(grep '^version:' "$APP_DIR/pubspec.yaml" | sed -E 's/version:[[:space:]]*([0-9.]+).*/\1/')"
DMG="$ROOT/Alotno-$VERSION.dmg"
APP="$APP_DIR/build/macos/Build/Products/Release/Alotno.app"

# --- 1. build --------------------------------------------------------------------
echo "▸ Building release…"
( cd "$APP_DIR" && flutter build macos --release )

# --- 2. sign (inside-out: frameworks first, then the app) ------------------------
echo "▸ Signing nested frameworks…"
find "$APP/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 \
  | while IFS= read -r -d '' f; do
      codesign --force --options runtime --timestamp --sign "$IDENTITY" "$f"
    done

echo "▸ Signing the app…"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# --- 3. DMG (with /Applications shortcut) ----------------------------------------
echo "▸ Building DMG…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Alotno" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# --- 4. notarize + staple --------------------------------------------------------
echo "▸ Notarizing (this can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
echo "▸ Stapling…"
xcrun stapler staple "$DMG"

# --- 5. verify -------------------------------------------------------------------
echo "▸ Verifying…"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG" || true

echo ""
echo "✅ Done: $DMG"
echo "   Shareable + Gatekeeper-approved. Drag to /Applications to install."
