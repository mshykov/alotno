//! The Flutter-facing API surface.
//!
//! `flutter_rust_bridge_codegen` reads this file and generates the Dart bindings
//! into `apps/app/lib/src/rust/`. Keep signatures simple (bytes, strings,
//! primitives, plain structs) so they cross the bridge cleanly.

use alotno_core::{
    png_to_dxf, png_to_eps, png_to_pdf, png_to_svg, png_to_webp, ColorMode, CurveType, DrawStyle,
    GroupBy, Preset, Stacking, StrokeStyle, SvgOptions, SvgVersion, WebpOptions,
};

/// Flat, bridge-friendly mirror of the core SVG options. Strings map via the
/// core's `parse` helpers (e.g. preset "coarse".."superFine").
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

/// PNG bytes → SVG string.
pub fn trace_png_to_svg(png_bytes: Vec<u8>, options: TraceOptions) -> Result<String, String> {
    png_to_svg(&png_bytes, &options.into()).map_err(|e| e.to_string())
}

/// PNG bytes → PDF bytes (vector).
pub fn convert_png_to_pdf(png_bytes: Vec<u8>, options: TraceOptions) -> Result<Vec<u8>, String> {
    png_to_pdf(&png_bytes, &options.into()).map_err(|e| e.to_string())
}

/// PNG bytes → EPS string (vector PostScript).
pub fn convert_png_to_eps(png_bytes: Vec<u8>, options: TraceOptions) -> Result<String, String> {
    png_to_eps(&png_bytes, &options.into()).map_err(|e| e.to_string())
}

/// PNG bytes → DXF string (AutoCAD R12 ASCII, lines-only).
pub fn convert_png_to_dxf(png_bytes: Vec<u8>, options: TraceOptions) -> Result<String, String> {
    png_to_dxf(&png_bytes, &options.into()).map_err(|e| e.to_string())
}

// ---- Raster output ----

/// PNG bytes → WebP bytes (libwebp lossy / pure-Rust lossless on native).
pub fn convert_png_to_webp(
    png_bytes: Vec<u8>,
    quality: f32,
    lossless: bool,
) -> Result<Vec<u8>, String> {
    png_to_webp(&png_bytes, &WebpOptions { quality, lossless }).map_err(|e| e.to_string())
}
