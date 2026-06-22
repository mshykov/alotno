# Roadmap

Sequenced by *learning and leverage*, not by platform count. Each phase ends with
something shippable and demoable.

## Phase 0 — Foundation ✅
Monorepo skeleton, Rust core API, WASM + FFI bindings, design-token pipeline, docs.

## Phase 1 — Web (the wedge) ✅
The lowest-friction surface: no install, no Apple tax, validates the engine.
- [x] Rust core + `wasm-pack` build; `cargo test` the core.
- [x] Astro marketing page at **alotno.app** built from the design tokens.
- [x] In-browser converter: drag PNG → SVG / PDF / EPS / DXF / WebP via the WASM
  core (conversion runs in a Web Worker), download result.
- [x] Deployed to Cloudflare Pages.

## Phase 2 — Desktop (macOS) ✅
The Flutter app, reusing the same core via FFI.
- [x] Flutter desktop; `flutter_rust_bridge` wired to the core.
- [x] macos_ui shell built from `tokens.dart`; sidebar with presets/recents/settings.
- [x] Menu-bar quick-convert; signed + notarized DMG (Developer ID); auto-release.

## Phase 3 — Mobile (iOS) ✅
- [x] iOS target on the same Flutter project; shared Material UI.
- [x] "Open with Alotno" intake (Files), multi-file queue, Save-to-Photos (WebP),
  share-sheet output, light Cupertino touches.

## In progress / next

### Distribution
- [ ] **TestFlight** (iOS) — needs an App Store Connect record + distribution cert.
- [ ] **Google Play** (Android) — needs the Android SDK/NDK toolchain + Play account.
- [ ] **Windows + Linux desktop** — scaffolding exists; not yet built/tested.

### iOS Share Extension
- [ ] Appear in the Photos/share-sheet row (needs an Xcode target + App Group);
  today intake is via the Files "Open in" document-type registration.

## Deferred / known limitations

### Lossy WebP on the web (libwebp → WASM)
Web WebP export is **lossless-only**; native (the Flutter app) gets libwebp-grade
lossy. This is surfaced honestly — `core::webp_lossy_supported()` returns `false`
in the WASM build, and the web UI locks the "Lossless" toggle on accordingly (see
`core/src/raster/webp.rs`).

Closing the gap needs one of:
- an **Emscripten-compiled libwebp** module (Squoosh-style) loaded by the convert
  Web Worker — the C library can't compile to `wasm32-unknown-unknown` directly
  (no wasm libc; `cc`/clang have no wasm target), so it must be a separate,
  pre-built `.wasm` artifact with its own JS glue; or
- a **pure-Rust lossy (VP8) WebP encoder** once one exists — `image-webp` is
  lossless-only today and there's no maintained pure-Rust lossy encoder.

Deferred until web lossy parity is a real need; lossless WebP (which the browser
`canvas.toBlob` cannot produce) already ships on the web.

### Android build verification
Android intake/config code is committed but **build-unverified** — no Android
SDK/NDK in the dev or CI environment yet. CI builds macOS + iOS (simulator); the
native macOS app build is the regression gate for the app layer.

## Guardrails
- New conversion behavior goes in `core/` only — never reimplemented in an app.
- New visual styling goes in `design/tokens.json` only — never hardcoded.
- A platform shell may only add: file I/O, platform UI chrome, and the WebP/EPS
  edge encoders.
