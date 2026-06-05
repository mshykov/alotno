# Brand assets

The Alotno mark: a falcon whose wing dissolves from **pixels into vector
line-art** — a visual pun on the product (PNG → SVG). Indigo, matching the design
tokens.

| File | Use |
|---|---|
| `alotno-logo.svg` | Vector source of truth — web header, README, scalable use (931 paths, real vector) |
| `alotno-logo.pdf` | Vector, for print |
| `alotno-logo.webp` | 76 KB web-optimized raster |
| `alotno-logo.png` | 1024px raster (downscaled from a 4.8 MB original; prefer the SVG) |
| `alotno-icon-1024.png` | Square, full-bleed crop used to generate the macOS app icon |

## macOS app icon
Generated from `alotno-icon-1024.png` into
`apps/app/macos/Runner/Assets.xcassets/AppIcon.appiconset/` (all sizes via `sips`).

> ⚠️ **Interim.** This was square-cropped out of the original *presentation
> mockup* (the logo came on a white card with a drop shadow). It's clean, but:
> - the fine crosshatch detail softens below ~32px (icons should read at 16px), and
> - it's light-on-light, which is flatter in the Dock than the filled-squircle norm.
>
> For a polished icon, commission a **simplified falcon glyph on a filled
> squircle** (indigo or white) designed for 16px legibility. Regenerate with:
> ```sh
> for s in 16 32 64 128 256 512 1024; do
>   sips -z $s $s design/brand/alotno-icon-1024.png \
>     --out apps/app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$s.png
> done
> ```
