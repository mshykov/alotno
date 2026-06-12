#!/usr/bin/env bash
#
# Regenerate ALL app/site icons from the brand logo (design/brand/alotno-logo.svg):
# the indigo line-art falcon on a full-bleed light-lavender tile. Covers macOS,
# iOS, Android, Windows, the web (apple-touch + header/hero icon + manifest), the
# OG social card, and the design/brand master.
#
# Does NOT touch:
#   * the favicon (favicon.svg/.ico/-16/-32) — intentionally white-bird-on-blue.
#   * the macOS menu-bar tray icon (assets/tray_icon.png) — a monochrome *template*
#     image macOS tints per light/dark menu bar; it can't be the colored tile.
#
# Requires: rsvg-convert, sips (macOS), python3 (for the Windows .ico).
# Usage: scripts/gen-icons.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Centered, square master: the logo cropped (via viewBox) to a square centered on
# the falcon's bounding box at ~85% fill — so the bird sits dead-center in the
# tile (see design/brand/alotno-icon.svg).
SRC="design/brand/alotno-icon.svg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 1. square master ------------------------------------------------------------
echo "▸ Building 2048² master…"
rsvg-convert -w 2048 -h 2048 "$SRC" -o "$TMP/master.png"

emit() { # emit <dest.png> <pixels>
  local dest="$1" px="$2"
  sips -z "$px" "$px" "$TMP/master.png" --out "$dest" >/dev/null
  echo "  $dest (${px}px)"
}

# --- 2. macOS appiconset ---------------------------------------------------------
echo "▸ macOS app icon…"
MAC="apps/app/macos/Runner/Assets.xcassets/AppIcon.appiconset"
for s in 16 32 64 128 256 512 1024; do emit "$MAC/app_icon_$s.png" "$s"; done

# --- 3. iOS appiconset (size@scale → pixels) -------------------------------------
echo "▸ iOS app icon…"
IOS="apps/app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
declare -a IOS_MAP=(
  "Icon-App-20x20@1x:20"   "Icon-App-20x20@2x:40"   "Icon-App-20x20@3x:60"
  "Icon-App-29x29@1x:29"   "Icon-App-29x29@2x:58"   "Icon-App-29x29@3x:87"
  "Icon-App-40x40@1x:40"   "Icon-App-40x40@2x:80"   "Icon-App-40x40@3x:120"
  "Icon-App-60x60@2x:120"  "Icon-App-60x60@3x:180"
  "Icon-App-76x76@1x:76"   "Icon-App-76x76@2x:152"  "Icon-App-83.5x83.5@2x:167"
  "Icon-App-1024x1024@1x:1024"
)
for entry in "${IOS_MAP[@]}"; do emit "$IOS/${entry%%:*}.png" "${entry##*:}"; done

# --- 4. Android launcher mipmaps -------------------------------------------------
echo "▸ Android launcher…"
AND="apps/app/android/app/src/main/res"
emit "$AND/mipmap-mdpi/ic_launcher.png" 48
emit "$AND/mipmap-hdpi/ic_launcher.png" 72
emit "$AND/mipmap-xhdpi/ic_launcher.png" 96
emit "$AND/mipmap-xxhdpi/ic_launcher.png" 144
emit "$AND/mipmap-xxxhdpi/ic_launcher.png" 192

# --- 5. Web: apple-touch + header/hero icon + brand master -----------------------
echo "▸ Web + brand master…"
emit "apps/web/public/apple-touch-icon.png" 180
emit "apps/web/public/icon.png" 512          # used by the site header + hero
emit "design/brand/alotno-icon-1024.png" 1024 # README hero + app-icon master

# --- 6. Windows .ico (PNG-compressed, 256²) --------------------------------------
echo "▸ Windows .ico…"
sips -z 256 256 "$TMP/master.png" --out "$TMP/icon256.png" >/dev/null
python3 - "$TMP/icon256.png" apps/app/windows/runner/resources/app_icon.ico <<'PY'
import struct, sys
png = open(sys.argv[1], "rb").read()
# ICONDIR + one PNG-compressed ICONDIRENTRY (width/height 0 ⇒ 256).
hdr = struct.pack("<HHH", 0, 1, 1)
ent = struct.pack("<BBBBHHII", 0, 0, 0, 0, 1, 32, len(png), 6 + 16)
open(sys.argv[2], "wb").write(hdr + ent + png)
PY
echo "  apps/app/windows/runner/resources/app_icon.ico (256px)"

# --- 7. OG social card (1200×630) ------------------------------------------------
echo "▸ OG card…"
# Base64-embed the icon (rsvg won't load file:// references for security).
ICON_B64="$(base64 -i "apps/web/public/icon.png" | tr -d '\n')"
cat > "$TMP/og.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1200" height="630">
  <rect width="1200" height="630" fill="#EDF0F8"/>
  <image x="80" y="95" width="440" height="440" xlink:href="data:image/png;base64,$ICON_B64"/>
  <g font-family="Inter, Helvetica, Arial, sans-serif">
    <text x="572" y="300" font-size="120" font-weight="800" fill="#4F46E5">Alotno</text>
    <text x="576" y="368" font-size="32" font-weight="500" fill="#475569">PNG → SVG · PDF · EPS · DXF · WebP</text>
    <text x="576" y="452" font-size="38" font-weight="700" fill="#4F46E5">alotno.app</text>
  </g>
</svg>
SVG
rsvg-convert -w 1200 -h 630 "$TMP/og.svg" -o "apps/web/public/og-image.png"
echo "  apps/web/public/og-image.png (1200×630)"

echo "✅ Icons regenerated from $SRC"
