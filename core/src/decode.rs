//! The shared input stage: PNG bytes → RGBA pixels. Every conversion starts here.

use std::io::Cursor;

use image::{ImageReader, Limits};

use crate::options::ConvertError;

/// Largest accepted side length, in pixels. A PNG header can *declare*
/// dimensions up to 2^31 each; without a cap a tiny crafted file forces a huge
/// allocation (a decompression-bomb DoS), and on the 32-bit `wasm32` target the
/// `width * height * 4` buffer math can overflow `usize`. Both are closed here.
pub(crate) const MAX_SIDE: u32 = 30_000;

/// Largest accepted pixel count (width × height). Bounds total RGBA memory to
/// ~400 MB and guarantees `width * height * 4` fits comfortably in a 32-bit
/// `usize`, so downstream tracing/encoding can't overflow.
pub(crate) const MAX_PIXELS: u64 = 100_000_000;

/// Upper bound on bytes the decoder may allocate while decoding. Belt-and-braces
/// alongside the dimension caps above.
const MAX_ALLOC_BYTES: u64 = 512 * 1024 * 1024;

/// Decoded RGBA image: width, height, and tightly-packed `RGBA` bytes.
pub struct RgbaImage {
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
}

/// Read a PNG's pixel dimensions without decoding the pixel data. Used by the
/// shells for queue thumbnails/labels, so dimension parsing lives in the core
/// (not re-implemented per platform).
pub(crate) fn dimensions(png_bytes: &[u8]) -> Result<(u32, u32), ConvertError> {
    limited_reader(png_bytes)?
        .into_dimensions()
        .map_err(|e| ConvertError::Decode(e.to_string()))
}

/// Whether the given dimensions exceed the engine's safety caps.
fn exceeds_limits(w: u32, h: u32) -> bool {
    w > MAX_SIDE || h > MAX_SIDE || (w as u64) * (h as u64) > MAX_PIXELS
}

/// Build a format-guessed PNG reader with the engine's safety limits applied.
fn limited_reader(png_bytes: &[u8]) -> Result<ImageReader<Cursor<&[u8]>>, ConvertError> {
    let mut reader = ImageReader::new(Cursor::new(png_bytes))
        .with_guessed_format()
        .map_err(|e| ConvertError::Decode(e.to_string()))?;
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_SIDE);
    limits.max_image_height = Some(MAX_SIDE);
    limits.max_alloc = Some(MAX_ALLOC_BYTES);
    reader.limits(limits);
    Ok(reader)
}

pub(crate) fn png_to_rgba(png_bytes: &[u8]) -> Result<RgbaImage, ConvertError> {
    // Validate the declared dimensions *before* allocating the pixel buffer, so
    // an oversized image fails fast with a clear error rather than OOM-aborting.
    let (w, h) = limited_reader(png_bytes)?
        .into_dimensions()
        .map_err(|e| ConvertError::Decode(e.to_string()))?;
    if exceeds_limits(w, h) {
        return Err(ConvertError::InvalidInput(format!(
            "image too large: {w}x{h} exceeds {MAX_SIDE}px per side or {MAX_PIXELS} total pixels"
        )));
    }

    let img = limited_reader(png_bytes)?
        .decode()
        .map_err(|e| ConvertError::Decode(e.to_string()))?
        .to_rgba8();
    let (width, height) = img.dimensions();
    Ok(RgbaImage {
        width,
        height,
        pixels: img.into_raw(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn small_images_are_within_limits() {
        assert!(!exceeds_limits(1, 1));
        assert!(!exceeds_limits(1024, 1024));
        assert!(!exceeds_limits(10_000, 9_000)); // 90M px, under MAX_PIXELS
    }

    #[test]
    fn oversize_dimensions_are_rejected() {
        assert!(exceeds_limits(MAX_SIDE + 1, 1)); // side cap
        assert!(exceeds_limits(1, MAX_SIDE + 1));
        assert!(exceeds_limits(20_000, 20_000)); // 400M px, over MAX_PIXELS
    }
}
