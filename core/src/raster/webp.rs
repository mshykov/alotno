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
    // "Mono" desaturates to grayscale before encoding (color mode applies to the
    // raster output too, not just the vector trace).
    let owned;
    let img = if options.grayscale {
        owned = to_grayscale(image);
        &owned
    } else {
        image
    };
    if options.lossless {
        encode_lossless_pure(img)
    } else {
        encode_lossy(img, options.quality)
    }
}

/// Desaturate RGBA to grayscale (luminance), preserving alpha.
fn to_grayscale(image: &RgbaImage) -> RgbaImage {
    let mut px = image.pixels.clone();
    let mut i = 0;
    while i + 3 < px.len() {
        let y = (0.299 * px[i] as f32 + 0.587 * px[i + 1] as f32 + 0.114 * px[i + 2] as f32)
            .round() as u8;
        px[i] = y;
        px[i + 1] = y;
        px[i + 2] = y;
        i += 4;
    }
    RgbaImage {
        width: image.width,
        height: image.height,
        pixels: px,
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
