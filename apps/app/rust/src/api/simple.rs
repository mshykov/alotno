//! The Flutter-facing API. `flutter_rust_bridge_codegen generate` reads this
//! module and produces the Dart bindings in `lib/src/rust/`.
//!
//! All real conversion logic lives in `alotno-core`; this is just the thin edge
//! that crosses the bridge. (This crate is the Flutter FFI binding — it must live
//! inside the Flutter project so cargokit can build it for each target.)

use alotno_core::{
    png_to_dxf, png_to_eps, png_to_pdf, png_to_svg, png_to_webp, ColorMode, CurveType, DrawStyle,
    GroupBy, Preset, Stacking, StrokeStyle, SvgOptions, SvgVersion, WebpOptions,
};

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Quick proof the Dart→Rust→alotno-core chain is linked and callable.
#[flutter_rust_bridge::frb(sync)]
pub fn engine_info() -> String {
    "Alotno engine linked ✓ (alotno-core via FFI)".to_string()
}

/// Bridge-friendly mirror of the core SVG options (strings map via core `parse`).
pub struct TraceOptions {
    pub preset: String,
    pub color_mode: String,
    pub curve_type: String,
    pub stacking: String,
    pub posterize_steps: u8,
    pub threshold: u8,
    pub version: String,
    pub draw_style: String,
    pub group_by: String,
    /// Empty string = keep each shape's traced color.
    pub stroke_color: String,
    pub stroke_width: f32,
    pub non_scaling_stroke: bool,
    pub fixed_size: bool,
    pub adobe_compat: bool,
    pub clip_overflow: bool,
}

impl Default for TraceOptions {
    fn default() -> Self {
        TraceOptions {
            preset: "high".into(),
            color_mode: "mono".into(),
            curve_type: "curves".into(),
            stacking: "cutouts".into(),
            posterize_steps: 4,
            threshold: 128,
            version: "1.1".into(),
            draw_style: "fill".into(),
            group_by: "none".into(),
            stroke_color: "#000000".into(),
            stroke_width: 1.0,
            non_scaling_stroke: false,
            fixed_size: false,
            adobe_compat: false,
            clip_overflow: false,
        }
    }
}

impl From<TraceOptions> for SvgOptions {
    fn from(o: TraceOptions) -> Self {
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
                color: if o.stroke_color.is_empty() { None } else { Some(o.stroke_color) },
                width: o.stroke_width,
                non_scaling: o.non_scaling_stroke,
            },
            fixed_size: o.fixed_size,
            adobe_compat: o.adobe_compat,
            clip_overflow: o.clip_overflow,
        }
    }
}

// ---- Vector outputs ----

pub fn trace_png_to_svg(png_bytes: Vec<u8>, options: TraceOptions) -> Result<String, String> {
    png_to_svg(&png_bytes, &options.into()).map_err(|e| e.to_string())
}

pub fn convert_png_to_pdf(png_bytes: Vec<u8>, options: TraceOptions) -> Result<Vec<u8>, String> {
    png_to_pdf(&png_bytes, &options.into()).map_err(|e| e.to_string())
}

pub fn convert_png_to_eps(png_bytes: Vec<u8>, options: TraceOptions) -> Result<String, String> {
    png_to_eps(&png_bytes, &options.into()).map_err(|e| e.to_string())
}

pub fn convert_png_to_dxf(png_bytes: Vec<u8>, options: TraceOptions) -> Result<String, String> {
    png_to_dxf(&png_bytes, &options.into()).map_err(|e| e.to_string())
}

// ---- Raster output ----

pub fn convert_png_to_webp(
    png_bytes: Vec<u8>,
    quality: f32,
    lossless: bool,
    mono: bool,
) -> Result<Vec<u8>, String> {
    png_to_webp(&png_bytes, &WebpOptions { quality, lossless, grayscale: mono })
        .map_err(|e| e.to_string())
}
