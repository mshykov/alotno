# Roadmap

Sequenced by *learning and leverage*, not by platform count. Each phase ends with
something shippable and demoable.

## Phase 0 — Foundation ✅ (this commit)
- Monorepo skeleton, Rust core API, WASM + FFI binding stubs, design-token
  pipeline, docs. Toolchains documented, not yet all installed.

## Phase 1 — Web (the wedge)
The lowest-friction surface: no install, no Apple tax, validates the engine.
- [ ] Install Rust + `wasm-pack`; `cargo test` the core; build the WASM pkg.
- [ ] Astro marketing page at **alotno.app** using the design tokens.
- [ ] In-browser converter: drag PNG → SVG / PDF / WebP (all via the WASM core), download result.
- [ ] Deploy (Cloudflare Pages — same vendor as the domain).

## Phase 2 — Desktop (macOS first)
The Flutter app, reusing the same core via FFI.
- [ ] Install Flutter; `flutter create apps/app` for desktop targets.
- [ ] Wire `flutter_rust_bridge`; call `trace_png_to_svg` / `convert_png_to_webp`.
- [ ] Build the UI from `tokens.dart` to match the web app.
- [ ] Sign + notarize for macOS (Developer ID), then enable Windows + Linux.
- [ ] Retire `legacy/electron-mac` once parity is reached.

## Phase 3 — Mobile
- [ ] Enable iOS + Android targets on the *same* Flutter project.
- [ ] Platform file-picker / share-sheet integration; the engine is unchanged.

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

## Guardrails
- New conversion behavior goes in `core/` only — never reimplemented in an app.
- New visual styling goes in `design/tokens.json` only — never hardcoded.
- A platform shell may only add: file I/O, platform UI chrome, and the WebP/EPS
  edge encoders.
