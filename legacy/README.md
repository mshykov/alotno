# legacy/

The original **Electron** Mac prototype of Alotno (when it was "PNG Converter").
Kept for reference, **not built or shipped** anymore — the Flutter app in
`apps/app` replaces it.

## Why keep it
- `electron-mac/electron/main.cjs` holds the proven `potrace` presets and the
  SVG→EPS formatter. These inform the Rust port in `core/` and the EPS edge
  encoders in the app shells.
- `electron-mac/RELEASE.md` documents the macOS Developer ID signing +
  notarization flow, which still applies to the Flutter macOS build.

Delete this folder once `apps/app` reaches feature parity (see
[../docs/roadmap.md](../docs/roadmap.md), Phase 2).
