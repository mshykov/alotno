//! The shared input stage: PNG bytes → RGBA pixels. Every conversion starts here.

use crate::options::ConvertError;

/// Decoded RGBA image: width, height, and tightly-packed `RGBA` bytes.
pub struct RgbaImage {
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
}

pub(crate) fn png_to_rgba(png_bytes: &[u8]) -> Result<RgbaImage, ConvertError> {
    let img = image::load_from_memory(png_bytes)
        .map_err(|e| ConvertError::Decode(e.to_string()))?
        .to_rgba8();
    let (width, height) = img.dimensions();
    Ok(RgbaImage {
        width,
        height,
        pixels: img.into_raw(),
    })
}
