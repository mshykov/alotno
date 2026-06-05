//! Browser binding: exposes the Alotno core to JavaScript via wasm-bindgen.
//!
//! The core (built here WITHOUT the `libwebp` feature) handles every conversion,
//! including WebP — so the web produces the same output as native, and gets
//! lossless WebP, which `canvas.toBlob` cannot.

use alotno_core::{
    png_to_dxf, png_to_eps, png_to_pdf, png_to_svg, png_to_webp, ColorMode, CurveType, DrawStyle,
    GroupBy, Preset, Stacking, StrokeStyle, SvgOptions, SvgVersion, WebpOptions,
};
use serde::Deserialize;
use wasm_bindgen::prelude::*;

/// Options passed from JS as a plain object. Every field is optional; unknown
/// keys are ignored. Strings map via the core's `parse` helpers.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", default)]
struct JsOptions {
    preset: String, // or "lineFitTolerance" wording (coarse/medium/fine/superFine)
    color_mode: String,
    curve_type: String,
    stacking: String,
    posterize_steps: u8,
    threshold: u8,
    version: String,
    draw_style: String,
    group_by: String,
    stroke_color: Option<String>,
    stroke_width: f32,
    non_scaling_stroke: bool,
    fixed_size: bool,
    adobe_compat: bool,
    clip_overflow: bool,
}

impl Default for JsOptions {
    fn default() -> Self {
        JsOptions {
            preset: "high".into(),
            color_mode: "mono".into(),
            curve_type: "curves".into(),
            stacking: "cutouts".into(),
            posterize_steps: 4,
            threshold: 128,
            version: "1.1".into(),
            draw_style: "fill".into(),
            group_by: "none".into(),
            stroke_color: Some("#000000".into()),
            stroke_width: 1.0,
            non_scaling_stroke: false,
            fixed_size: false,
            adobe_compat: false,
            clip_overflow: false,
        }
    }
}

impl From<JsOptions> for SvgOptions {
    fn from(o: JsOptions) -> Self {
        SvgOptions {
            preset: Preset::parse(&o.preset),
            color_mode: ColorMode::parse(&o.color_mode),
            curve_type: CurveType::parse(&o.curve_type),
            stacking: Stacking::parse(&o.stacking),
            posterize_steps: o.posterize_steps,
            threshold: o.threshold,
            version: SvgVersion::parse(&o.version),
            draw_style: DrawStyle::parse(&o.draw_style),
            group_by: GroupBy::parse(&o.group_by),
            stroke: StrokeStyle {
                color: o.stroke_color,
                width: o.stroke_width,
                non_scaling: o.non_scaling_stroke,
            },
            fixed_size: o.fixed_size,
            adobe_compat: o.adobe_compat,
            clip_overflow: o.clip_overflow,
        }
    }
}

fn parse_opts(js: JsValue) -> Result<SvgOptions, JsError> {
    let o: JsOptions = if js.is_undefined() || js.is_null() {
        JsOptions::default()
    } else {
        serde_wasm_bindgen::from_value(js).map_err(|e| JsError::new(&format!("invalid options: {e}")))?
    };
    Ok(o.into())
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

/// PNG bytes → WebP bytes. `lossless` works here too (canvas can't).
#[wasm_bindgen(js_name = pngToWebp)]
pub fn png_to_webp_wasm(png_bytes: &[u8], quality: f32, lossless: bool) -> Result<Vec<u8>, JsError> {
    png_to_webp(png_bytes, &WebpOptions { quality, lossless }).map_err(|e| JsError::new(&e.to_string()))
}
