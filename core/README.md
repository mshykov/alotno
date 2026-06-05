# `alotno-core`

The conversion engine. **All** of Alotno's conversion logic lives here, once, in
pure Rust, and is consumed by every platform via WASM or FFI.

## Module layout

```
src/decode.rs                 PNG → RGBA (shared input)
src/options.rs                SvgOptions, WebpOptions, enums + parse() helpers
src/vector/trace.rs           RGBA → SVG (vtracer) + post-processing
src/vector/svg_postprocess.rs  version / draw style / grouping / stroke / clip
src/vector/path.rs            shared path tokenizer + curve flattening
src/vector/pdf.rs             SVG  → PDF (svg2pdf)
src/vector/eps.rs             SVG  → EPS (ported from the Electron prototype)
src/vector/dxf.rs             SVG  → DXF (lines-only, R12 ASCII)
src/raster/webp.rs            RGBA → WebP (pure-Rust; optional libwebp)
```

## Public API

```rust
use alotno_core::{png_to_svg, png_to_pdf, png_to_eps, png_to_dxf, png_to_webp,
                  SvgOptions, WebpOptions, Preset, ColorMode, DrawStyle, SvgVersion};

let opts = SvgOptions {
    preset: Preset::High,
    color_mode: ColorMode::Posterized,
    draw_style: DrawStyle::Stroke,
    version: SvgVersion::Tiny1_2,
    ..Default::default()
};
let svg: String  = png_to_svg(&png, &opts)?;   // styled SVG
let pdf: Vec<u8> = png_to_pdf(&png, &opts)?;   // PNG → SVG → PDF
let eps: String  = png_to_eps(&png, &opts)?;   // PNG → SVG → EPS
let dxf: String  = png_to_dxf(&png, &opts)?;   // PNG → SVG → DXF (lines-only)

let webp: Vec<u8> = png_to_webp(&png, &WebpOptions { quality: 82.0, lossless: false })?;
```

Every `SvgOptions` enum has a `parse(&str)` so bindings map UI strings without
duplicating logic. Supported vs. omitted settings: [`docs/features.md`](../docs/features.md).

### WebP feature flag

WebP works everywhere by default (pure-Rust encoder — lossless is exact). Build
with `--features libwebp` on **native** targets for libwebp-grade *lossy* output;
the WASM build deliberately omits it. See [`src/raster/webp.rs`](src/raster/webp.rs).

## Build & test

```sh
cargo test -p alotno-core              # runs the decode tests
cargo build -p alotno-core --release   # native build
cargo doc  -p alotno-core --open       # browse the API
```

## Implementation notes

- Vectorization uses [`vtracer`](https://crates.io/crates/vtracer) (visioncortex).
  Preset → tracer-parameter mapping lives in [`src/svg.rs`](src/svg.rs).
- Errors cross the binding boundary as plain strings (`ConvertError`) so WASM/FFI
  callers get readable messages.
- ⚠️ `vtracer`'s `Config` fields shift between releases. This is written against
  the **0.6** line; if you bump it, verify field names compile. The original
  `potrace`-based presets are preserved in
  [`../legacy/electron-mac/electron/main.cjs`](../legacy/electron-mac/electron/main.cjs)
  for reference.
