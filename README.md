<div align="center">

# Alotno

**One image-conversion engine. Every platform. Identical design.**

PNG → WebP · SVG (vector trace) · EPS — on the web, macOS, Windows, Linux, iOS, and Android.

</div>

---

## Why this repo exists

Alotno is a deliberately over-architected take on a simple tool. The point isn't
the converter — it's proving that a **single developer** can ship the *same*
product, with the *same* design and the *same* behavior, to *every* platform,
without reimplementing the logic five times.

That goal drives every decision here:

- **One engine, written once.** *All* conversion logic — PNG → SVG, PDF, EPS,
  DXF, and WebP, plus the SVG styling pipeline — lives in a Rust crate
  ([`core/`](core)) and is compiled to **WebAssembly** for the browser and to a
  **native library** for the desktop/mobile apps. There is exactly one
  implementation of each conversion in this repository.
  ([Feature support map](docs/features.md).)
- **One design language.** The system is specified in [`DESIGN.md`](DESIGN.md)
  and encoded in [`design/tokens.json`](design/tokens.json), which is *generated*
  into CSS variables, TypeScript, and Dart. Every UI consumes the same source, so
  the apps can't visually drift.
- **One repository.** A monorepo keeps the core, the design system, and every app
  in lockstep. The architecture is the deliverable, so it lives in one place.

## Architecture at a glance

```
                       ┌─────────────────────────┐
                       │   core/  (Rust crate)    │   ← the only conversion logic
                       │ PNG→SVG·PDF·EPS·DXF·WebP  │
                       └────────────┬────────────┘
              compiles to ──────────┼───────────── compiles to
                  ┌─────────────────┴───────────────────┐
                  ▼                                       ▼
        ┌──────────────────┐                  ┌────────────────────────┐
        │ bindings/wasm    │                  │ bindings/ffi           │
        │ (wasm-bindgen)   │                  │ (flutter_rust_bridge)  │
        └────────┬─────────┘                  └───────────┬────────────┘
                 ▼                                         ▼
        ┌──────────────────┐                  ┌────────────────────────┐
        │ apps/web (Astro) │                  │ apps/app (Flutter)     │
        │ marketing + tool │                  │ macOS · Windows · Linux│
        │                  │                  │ iOS · Android          │
        └──────────────────┘                  └────────────────────────┘

        design/tokens.json ──generates──▶ CSS vars · TS · Dart  (consumed by both)
```

### Everything converts in the core

PNG → SVG (vtracer), SVG → PDF (svg2pdf), SVG → EPS (a ported formatter), and
PNG → WebP all live in the Rust core and compile to both WASM and native. That
keeps output **identical on every platform** — including lossless WebP, which the
browser's `canvas.toBlob` can't produce. The only per-platform code is file I/O
and UI. The single nuance (pure-Rust vs. libwebp lossy WebP) is documented in
[`docs/architecture.md`](docs/architecture.md).

## Layout

| Path | What it is | Stack |
|---|---|---|
| [`core/`](core) | The conversion engine — single source of truth | Rust |
| [`bindings/wasm/`](bindings/wasm) | Browser binding for the core | Rust + wasm-bindgen |
| [`bindings/ffi/`](bindings/ffi) | Native binding for Flutter | Rust + flutter_rust_bridge |
| [`design/`](design) | Design tokens + generators | JSON → CSS/TS/Dart |
| [`apps/web/`](apps/web) | Marketing page + in-browser converter | Astro |
| [`apps/app/`](apps/app) | The cross-platform app (all 6 targets) | Flutter |
| [`docs/`](docs) | Architecture write-up (blog source material) | Markdown |
| [`legacy/`](legacy) | The original Electron Mac prototype, kept for reference | Electron |

## Roadmap

- **Phase 1 — Web.** Marketing page at [alotno.app](https://alotno.app) + the
  converter running fully in-browser via WASM. No uploads, no backend.
- **Phase 2 — Desktop.** The Flutter app on macOS (signed + notarized), then
  Windows and Linux from the same codebase.
- **Phase 3 — Mobile.** iOS and Android from the same Flutter codebase.

See [docs/roadmap.md](docs/roadmap.md).

## Getting started

Each surface has its own README with exact commands:

- Core engine → [`core/README.md`](core/README.md)
- Design tokens → [`design/README.md`](design/README.md)
- Web app → [`apps/web/README.md`](apps/web/README.md)
- Flutter app → [`apps/app/README.md`](apps/app/README.md)

Toolchains you'll need: [Rust](https://rustup.rs) (+ `wasm-pack`),
[Node 20+](https://nodejs.org) with `pnpm`, and the
[Flutter SDK](https://docs.flutter.dev/get-started/install).

## License

[MIT](LICENSE) © Maksym Shykov
