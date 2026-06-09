//! Browser binding: exposes the Alotno core to JavaScript via wasm-bindgen.
//!
//! The core (built here WITHOUT the `libwebp` feature) handles every conversion,
//! including WebP — so the web produces the same output as native, and gets
//! lossless WebP, which `canvas.toBlob` cannot.

use alotno_core::{
    png_to_dxf, png_to_eps, png_to_pdf, png_to_svg, png_to_webp, webp_lossy_supported, OptionsDto,
    SvgOptions, WebpOptions,
};
use wasm_bindgen::prelude::*;

/// Whether this (WASM) build can produce lossy WebP. Always `false` today — the
/// browser build is pure-Rust and lossless-only — so the UI can disable/relabel
/// any lossy control. Mirrors the native binding for surface parity.
#[wasm_bindgen(js_name = webpLossySupported)]
pub fn webp_lossy_supported_wasm() -> bool {
    webp_lossy_supported()
}

/// Deserialize the JS options object into the shared core [`OptionsDto`] (every
/// field optional, camelCase, unknown keys ignored), then map to `SvgOptions`.
/// All parsing/default/stroke logic lives once in the core — see `OptionsDto`.
fn parse_opts(js: JsValue) -> Result<SvgOptions, JsError> {
    let dto: OptionsDto = if js.is_undefined() || js.is_null() {
        OptionsDto::default()
    } else {
        serde_wasm_bindgen::from_value(js)
            .map_err(|e| JsError::new(&format!("invalid options: {e}")))?
    };
    Ok(dto.into())
}

/// Call once on module load to get readable panic messages in the console.
#[wasm_bindgen(start)]
pub fn init() {
    console_error_panic_hook::set_once();
}

/// PNG bytes → SVG string.
#[wasm_bindgen(js_name = pngToSvg)]
pub fn png_to_svg_wasm(png_bytes: &[u8], options_js: JsValue) -> Result<String, JsError> {
    png_to_svg(png_bytes, &parse_opts(options_js)?).map_err(|e| JsError::new(&e.to_string()))
}

/// PNG bytes → PDF bytes (vector).
#[wasm_bindgen(js_name = pngToPdf)]
pub fn png_to_pdf_wasm(png_bytes: &[u8], options_js: JsValue) -> Result<Vec<u8>, JsError> {
    png_to_pdf(png_bytes, &parse_opts(options_js)?).map_err(|e| JsError::new(&e.to_string()))
}

/// PNG bytes → EPS string (vector PostScript).
#[wasm_bindgen(js_name = pngToEps)]
pub fn png_to_eps_wasm(png_bytes: &[u8], options_js: JsValue) -> Result<String, JsError> {
    png_to_eps(png_bytes, &parse_opts(options_js)?).map_err(|e| JsError::new(&e.to_string()))
}

/// PNG bytes → DXF string (AutoCAD R12 ASCII, lines-only).
#[wasm_bindgen(js_name = pngToDxf)]
pub fn png_to_dxf_wasm(png_bytes: &[u8], options_js: JsValue) -> Result<String, JsError> {
    png_to_dxf(png_bytes, &parse_opts(options_js)?).map_err(|e| JsError::new(&e.to_string()))
}

/// PNG bytes → WebP bytes. `lossless` works here too (canvas can't); `mono`
/// desaturates to grayscale.
#[wasm_bindgen(js_name = pngToWebp)]
pub fn png_to_webp_wasm(
    png_bytes: &[u8],
    quality: f32,
    lossless: bool,
    mono: bool,
) -> Result<Vec<u8>, JsError> {
    png_to_webp(
        png_bytes,
        &WebpOptions {
            quality,
            lossless,
            grayscale: mono,
        },
    )
    .map_err(|e| JsError::new(&e.to_string()))
}
