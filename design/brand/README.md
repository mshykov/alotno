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
| `alotno-icon-1024.png` | Square, full-bleed app-icon master (indigo falcon on lavender), generated from `alotno-logo.svg` |

## Regenerating all icons
Every app/site icon is derived from `alotno-logo.svg` by a single script:

```sh
scripts/gen-icons.sh
```

It produces the full-bleed **lavender** falcon tile at every size for macOS, iOS,
Android, Windows, the web (`apple-touch-icon.png`, `icon.png` for the
header/hero, `og-image.png`), and the `alotno-icon-1024.png` master.

**Not regenerated (intentionally):**
- the **favicon** (`apps/web/public/favicon.{svg,ico}`, `favicon-16/32.png`) —
  kept as the white-bird-on-blue mark.
- the macOS **menu-bar tray icon** (`apps/app/assets/tray_icon.png`) — a
  monochrome *template* image that macOS tints per light/dark menu bar.
