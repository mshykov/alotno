//! Alotno's conversion engine — the single, portable source of truth.
//!
//! This crate is pure Rust and contains **all** of Alotno's conversion logic.
//! It compiles unchanged to:
//!   * `wasm32-unknown-unknown` for the browser (via `bindings/wasm`)
//!   * native targets for the Flutter apps (via `apps/app/rust`)
//!
//! The shells (`apps/*`) only do file I/O and UI — never conversion.
//!
//! ## Output families
//! * **raster**: WebP (pure-Rust; optional libwebp for native lossy parity)
//! * **vector**: SVG (vtracer) → which then derives PDF and EPS
//!
//! Everything starts from one decode stage ([`decode`]) and a common
//! [`RgbaImage`].

mod decode;
mod options;
mod raster;
mod vector;

pub use decode::RgbaImage;
pub use options::{
    ColorMode, ConvertError, CurveType, DrawStyle, GroupBy, Preset, Stacking, StrokeStyle,
    SvgOptions, SvgVersion, WebpOptions,
};

// ---------------------------------------------------------------------------
// Vector outputs
// ---------------------------------------------------------------------------

/// PNG bytes → SVG string. The headline conversion, shared by every platform.
pub fn png_to_svg(png_bytes: &[u8], options: &SvgOptions) -> Result<String, ConvertError> {
    let rgba = decode::png_to_rgba(png_bytes)?;
    vector::trace::to_svg(rgba, options)
}

/// SVG string → PDF bytes (vector). Traced SVGs are path-only, so no fonts.
pub fn svg_to_pdf(svg: &str) -> Result<Vec<u8>, ConvertError> {
    vector::pdf::from_svg(svg)
}

/// SVG string → EPS string (vector PostScript). Ported from the Electron prototype.
pub fn svg_to_eps(svg: &str) -> Result<String, ConvertError> {
    vector::eps::from_svg(svg)
}

/// SVG string → DXF string (AutoCAD R12 ASCII, lines-only).
pub fn svg_to_dxf(svg: &str) -> Result<String, ConvertError> {
    vector::dxf::from_svg(svg)
}

/// Convenience: PNG → SVG → PDF in one call.
pub fn png_to_pdf(png_bytes: &[u8], options: &SvgOptions) -> Result<Vec<u8>, ConvertError> {
    svg_to_pdf(&png_to_svg(png_bytes, options)?)
}

/// Convenience: PNG → SVG → EPS in one call.
pub fn png_to_eps(png_bytes: &[u8], options: &SvgOptions) -> Result<String, ConvertError> {
    svg_to_eps(&png_to_svg(png_bytes, options)?)
}

/// Convenience: PNG → SVG → DXF in one call.
pub fn png_to_dxf(png_bytes: &[u8], options: &SvgOptions) -> Result<String, ConvertError> {
    svg_to_dxf(&png_to_svg(png_bytes, options)?)
}

// ---------------------------------------------------------------------------
// Raster outputs
// ---------------------------------------------------------------------------

/// PNG bytes → WebP bytes. Pure-Rust by default (works in WASM); native builds
/// with the `libwebp` feature get higher-quality lossy encoding.
pub fn png_to_webp(png_bytes: &[u8], options: &WebpOptions) -> Result<Vec<u8>, ConvertError> {
    let rgba = decode::png_to_rgba(png_bytes)?;
    raster::webp::encode(&rgba, options)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Smallest valid PNG: 1x1, RGBA.
    const TINY_PNG: &[u8] = &[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44,
        0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F,
        0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00,
        0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];

    #[test]
    fn decodes_a_valid_png() {
        let img = decode::png_to_rgba(TINY_PNG).expect("should decode");
        assert_eq!((img.width, img.height), (1, 1));
        assert_eq!(img.pixels.len(), 4);
    }

    #[test]
    fn rejects_garbage() {
        assert!(decode::png_to_rgba(b"not a png").is_err());
    }

    #[test]
    fn webp_lossless_roundtrips() {
        let webp = png_to_webp(TINY_PNG, &WebpOptions { lossless: true, ..Default::default() })
            .expect("encode");
        assert!(webp.starts_with(b"RIFF"));
    }
}
