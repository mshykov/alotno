# Alotno architecture

> The product is a PNG converter. The *point* is shipping one implementation to
> every platform. This document explains how the pieces fit — and is written to
> double as the source for a blog post.

## The thesis

A single developer maintaining "the same app everywhere" usually ends up
maintaining *N* apps that happen to look similar. Alotno refuses that. Two assets
are authored exactly once and everything else consumes them:

1. **The conversion engine** — `core/`, in Rust.
2. **The design language** — `design/tokens.json`.

Everything in `apps/` is a thin shell around those two.

## Repository layout

| Path | What it is | Stack |
|---|---|---|
| [`core/`](../core) | The conversion engine — single source of truth | Rust |
| [`bindings/wasm/`](../bindings/wasm) | Browser binding for the core | Rust + wasm-bindgen |
| [`apps/app/rust/`](../apps/app/rust) | Native binding for Flutter (lives in the app per frb) | Rust + flutter_rust_bridge |
| [`design/`](../design) | Design tokens + generators | JSON → CSS/TS/Dart |
| [`apps/web/`](../apps/web) | Marketing page + in-browser converter | Astro |
| [`apps/app/`](../apps/app) | The cross-platform app (all 6 targets) | Flutter |
| [`docs/`](.) | Architecture, features, running, releasing, roadmap | Markdown |

## Layer 1 — the engine (`core/`)

Pure Rust, no platform assumptions. One decode stage (PNG → RGBA) feeds two
output families:

- **vector** — `vtracer` traces RGBA → SVG; SVG then derives **PDF** (`svg2pdf`)
  and **EPS** (a formatter ported from the Electron prototype).
- **raster** — RGBA → **WebP** (pure-Rust encoder; native builds can opt into
  libwebp for lossy quality).

It exposes a small API (`png_to_svg`, `png_to_pdf`, `png_to_eps`, `png_to_webp`)
and knows nothing about WASM, Flutter, or JS. Module layout:
`core/src/{decode,options}.rs`, `core/src/vector/{trace,pdf,eps}.rs`,
`core/src/raster/webp.rs`.

Because it's pure Rust, the *same compiled logic* runs in two very different places:

```
core (rlib)
 ├── bindings/wasm   → wasm-bindgen → .wasm           → apps/web  (browser)
 └── apps/app/rust   → flutter_rust_bridge (cargokit)  → apps/app  (native, all OSes)
```

### Every conversion lives in the core — including WebP

An earlier draft kept WebP at the browser edge (`canvas.toBlob('image/webp')`)
to save bundle size. We reversed that, because it quietly broke the project's
core promise:

- **Different encoder = different bytes.** Canvas uses the browser's WebP encoder;
  native uses libwebp. Same PNG, same quality, *different output* — an
  inconsistency in a tool whose whole pitch is "identical everywhere."
- **Canvas can't do lossless WebP.** The web would silently lose a feature the
  desktop app has.

So **all conversions run in the Rust core**, on every platform:

| Conversion | Web (WASM) | Native (FFI) |
|---|---|---|
| PNG → SVG | core (vtracer) | core (vtracer) |
| SVG → PDF | core (svg2pdf) | core (svg2pdf) |
| SVG → EPS | core (ported formatter) | core (ported formatter) |
| SVG → DXF | core (lines-only writer) | core (lines-only writer) |
| PNG → WebP | core (pure-Rust) | core (pure-Rust lossless / libwebp lossy) |

For the full settings panel and what is / isn't supported (and why), see
[features.md](features.md).

The only WebP nuance is *lossy quality*: the WASM build uses a pure-Rust encoder
(lossless is exact; lossy is approximated), while native builds enable the
`libwebp` feature for libwebp-grade lossy. If web lossy parity ever matters,
libwebp compiles to WASM (Squoosh-style) — same code path, different backend.

The rule is now simple: **conversion logic is always in the core; the shells only
do file I/O and UI.**

### The core is panic-free — by contract

The engine is built with `panic = "abort"` (it keeps the WASM payload small).
That makes panics non-negotiable: on the web a panic doesn't unwind into a
catchable `JsError` — it traps and **poisons the whole WASM module**; on native
it would abort the host process. So the rule is:

> Every public entry point returns `Result<_, ConvertError>`, and the core must
> never panic on any input — including malformed, truncated, or hostile bytes.

Concretely that means: no `unwrap`/`expect`/unchecked indexing on input-derived
data, decode dimensions are capped before allocation (`decode::MAX_*`), the
hand-written SVG-path parsers are total (`vector::path::parse_path`), and
caller-supplied strings (e.g. stroke color) are validated before being written
into output markup. The bindings (`bindings/wasm`, `apps/app/rust`) are thin
pass-throughs that rely on this — they add no error handling of their own beyond
mapping `ConvertError` to the host's error type. Property tests
(`core/tests/path_parsers.rs`) fuzz the parsers to keep the guarantee honest.

## Layer 2 — the design language (`design/`)

`tokens.json` → a generator → three outputs (`tokens.css`, `tokens.ts`,
`tokens.dart`). Apps import the generated file for their platform. Change a brand
color once; web and Flutter both move. No app hardcodes a hex or a pixel.

## Layer 3 — the shells (`apps/`)

- **`apps/web`** (Astro): static marketing page + an in-browser converter island
  that loads the WASM core. No backend, no uploads — files never leave the tab.
- **`apps/app`** (Flutter): one Dart codebase targeting macOS, Windows, Linux,
  iOS, Android. Calls the core through the FFI bridge. Flutter renders its own UI,
  so the design tokens give pixel parity across all six targets.

## Why a monorepo

The core, the bridges, the tokens, and the apps change together. A polyrepo would
force publishing the core and tokens as packages and syncing versions across four
repos — pure overhead for one person. One repo keeps the whole system atomic and,
not incidentally, makes the architecture legible to anyone who clones it.

## Build graph

```
design/tokens.json ──► design/dist/*           (node)
core/ ──► bindings/wasm/pkg/                    (wasm-pack)
core/ ──► apps/app/rust native libs            (flutter_rust_bridge + cargokit, per target)
        ├─ apps/web   = astro + tokens.css + wasm pkg
        └─ apps/app   = flutter + tokens.dart + the rust lib (cargokit-built)
```

## What I'd write about on the blog

- Compiling one Rust crate to both WASM and native FFI, and the WebP asymmetry.
- A design-token pipeline that feeds CSS *and* Dart from one JSON file.
- The honest trade-offs of "one codebase, every platform" as a solo developer.
