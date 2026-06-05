//! RGBA → WebP.
//!
//! ## Why WebP lives in the core (not at the browser edge)
//! Alotno's promise is identical output everywhere. `canvas.toBlob('image/webp')`
//! would give the web a *different* encoder than native AND can't do lossless.
//! Encoding here means the same bytes and the same features on every platform.
//!
//! ## The pure-Rust / libwebp split
//! * **Lossless** uses the pure-Rust `image-webp` encoder — compiles to WASM,
//!   so the web gets lossless too.
//! * **Lossy** uses pure-Rust by default; enable the `libwebp` feature on native
//!   builds for libwebp-quality lossy output. (A WASM libwebp build, Squoosh-
//!   style, is a future option if web lossy parity becomes important.)

use crate::decode::RgbaImage;
use crate::options::{ConvertError, WebpOptions};

pub(crate) fn encode(image: &RgbaImage, options: &WebpOptions) -> Result<Vec<u8>, ConvertError> {
    if options.lossless {
        encode_lossless_pure(image)
    } else {
        encode_lossy(image, options.quality)
    }
}

/// Pure-Rust lossless WebP via `image-webp`. WASM-safe.
fn encode_lossless_pure(image: &RgbaImage) -> Result<Vec<u8>, ConvertError> {
    use image_webp::{ColorType, WebPEncoder};
    let mut out = Vec::new();
    WebPEncoder::new(&mut out)
        .encode(&image.pixels, image.width, image.height, ColorType::Rgba8)
        .map_err(|e| ConvertError::Encode(e.to_string()))?;
    Ok(out)
}

/// Lossy WebP. libwebp when the feature is on (native, best quality)...
#[cfg(feature = "libwebp")]
fn encode_lossy(image: &RgbaImage, quality: f32) -> Result<Vec<u8>, ConvertError> {
    let encoder = webp::Encoder::from_rgba(&image.pixels, image.width, image.height);
    Ok(encoder.encode(quality).to_vec())
}

/// ...otherwise pure-Rust. `image-webp` is lossless-only today, so the WASM build
/// currently produces lossless bytes even when "lossy" is requested. Documented,
/// not silent — revisit if/when a pure-Rust lossy encoder lands, or compile
/// libwebp to WASM. `quality` is accepted for API stability.
#[cfg(not(feature = "libwebp"))]
fn encode_lossy(image: &RgbaImage, _quality: f32) -> Result<Vec<u8>, ConvertError> {
    encode_lossless_pure(image)
}
