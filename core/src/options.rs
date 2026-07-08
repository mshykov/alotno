//! Public options and error types for the conversion engine.
//!
//! These mirror the controls the original Electron prototype exposed
//! (see `legacy/electron-mac/electron/main.cjs`) so behavior stays familiar,
//! but they're now defined once and shared by every platform.
//!
//! Each enum has a `parse(&str)` so the WASM/FFI bindings can map their
//! string-keyed UI options without duplicating the matching logic.

/// Quality/detail preset. Maps to concrete tracer parameters in `svg.rs`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Preset {
    Low,
    Medium,
    #[default]
    High,
    Ultra,
}

impl Preset {
    /// Accepts preset names and the UI's "Line Fit Tolerance" wording.
    pub fn parse(s: &str) -> Preset {
        match s.to_ascii_lowercase().as_str() {
            "low" | "coarse" => Preset::Low,
            "medium" => Preset::Medium,
            "ultra" | "super fine" | "superfine" | "super_fine" => Preset::Ultra,
            _ => Preset::High, // "high" | "fine"
        }
    }
}

/// Monochrome (black/white trace) vs. posterized (multi-color) output.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ColorMode {
    #[default]
    Mono,
    Posterized,
}

impl ColorMode {
    pub fn parse(s: &str) -> ColorMode {
        match s.to_ascii_lowercase().as_str() {
            "posterized" | "color" => ColorMode::Posterized,
            _ => ColorMode::Mono,
        }
    }
}

/// Allowed curve output. vtracer can emit straight lines (Polygon) or cubic
/// Bézier splines (Spline). Quadratic/arcs/elliptical (vectorizer.ai's panel)
/// are intentionally NOT offered — vtracer can't produce them. See docs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum CurveType {
    /// Cubic Bézier splines.
    #[default]
    Curves,
    /// Straight polyline segments only.
    Lines,
}

impl CurveType {
    pub fn parse(s: &str) -> CurveType {
        match s.to_ascii_lowercase().as_str() {
            "lines" | "line" | "polygon" => CurveType::Lines,
            _ => CurveType::Curves,
        }
    }
}

/// "Shape Stacking" in the UI. Cutouts = shapes are carved out of the ones
/// below; Stacked = opaque shapes painted on top of each other.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Stacking {
    #[default]
    Cutouts,
    Stacked,
}

impl Stacking {
    pub fn parse(s: &str) -> Stacking {
        match s.to_ascii_lowercase().as_str() {
            "stacked" => Stacking::Stacked,
            _ => Stacking::Cutouts,
        }
    }
}

/// Target SVG profile, applied as a post-processing rewrite.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SvgVersion {
    V1_0,
    #[default]
    V1_1,
    Tiny1_2,
}

impl SvgVersion {
    pub fn parse(s: &str) -> SvgVersion {
        match s.to_ascii_lowercase().as_str() {
            "1.0" | "10" => SvgVersion::V1_0,
            "tiny" | "tiny1.2" | "1.2" => SvgVersion::Tiny1_2,
            _ => SvgVersion::V1_1,
        }
    }
}

/// "Draw Style": how each shape is painted. (The reference UI's "stroke shared
/// edges once" needs shared-edge dedup geometry we don't do, so it's omitted
/// rather than faked.)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DrawStyle {
    /// Solid filled shapes (default).
    #[default]
    Fill,
    /// Outline each shape, no fill.
    Stroke,
    /// Fill and outline.
    Both,
}

impl DrawStyle {
    pub fn parse(s: &str) -> DrawStyle {
        match s.to_ascii_lowercase().as_str() {
            "stroke" => DrawStyle::Stroke,
            "both" => DrawStyle::Both,
            _ => DrawStyle::Fill,
        }
    }
}

/// "Group By": how paths are wrapped in `<g>` elements.
/// (Parent/Layer from the reference UI need containment hierarchy we don't
/// compute yet, so they're omitted rather than faked.)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum GroupBy {
    #[default]
    None,
    Color,
}

impl GroupBy {
    pub fn parse(s: &str) -> GroupBy {
        match s.to_ascii_lowercase().as_str() {
            "color" => GroupBy::Color,
            _ => GroupBy::None,
        }
    }
}

/// Stroke styling, used by the `Stroke` / `Both` draw styles and the
/// Gap Filler / Stroke Style sections of the UI.
#[derive(Debug, Clone)]
pub struct StrokeStyle {
    /// Hex color (e.g. "#000000"). `None` keeps each shape's traced color.
    pub color: Option<String>,
    pub width: f32,
    /// Keep stroke width constant regardless of zoom (`vector-effect`).
    pub non_scaling: bool,
}

impl Default for StrokeStyle {
    fn default() -> Self {
        StrokeStyle {
            color: Some("#000000".into()),
            width: 1.0,
            non_scaling: false,
        }
    }
}

/// All knobs for a PNG → SVG conversion. Construct with `..Default::default()`.
///
/// Tracing fields drive vtracer; the rest are applied as post-processing on the
/// resulting SVG (and therefore carry through to PDF/EPS/DXF derived from it).
#[derive(Debug, Clone)]
pub struct SvgOptions {
    // --- tracing (vtracer) ---
    /// Detail level. In the UI this is "Line Fit Tolerance"
    /// (Coarse=Low … Super Fine=Ultra).
    pub preset: Preset,
    pub color_mode: ColorMode,
    pub curve_type: CurveType,
    pub stacking: Stacking,
    /// Number of color layers when `color_mode == Posterized` (2–8).
    pub posterize_steps: u8,
    /// Black/white cutoff for `Mono` mode (0–255).
    pub threshold: u8,

    // --- post-processing (style) ---
    pub version: SvgVersion,
    pub draw_style: DrawStyle,
    pub group_by: GroupBy,
    pub stroke: StrokeStyle,
    /// Emit explicit width/height (Fixed Size) vs. a scalable viewBox only.
    pub fixed_size: bool,
    /// Adobe Compatibility Mode — add the attributes Illustrator expects.
    pub adobe_compat: bool,
    /// Clip any geometry outside the canvas bounds.
    pub clip_overflow: bool,
}

/// Plain, string-keyed mirror of [`SvgOptions`] shared by the language bindings.
///
/// This centralizes the three things that previously drifted between the WASM
/// and native bindings: the string→enum parsing, the default values, and the
/// stroke-color convention (empty string = keep each shape's traced color).
/// Bindings build an `OptionsDto` from their wire format and call `.into()`.
///
/// With the `serde` feature (enabled by the WASM binding) it deserializes
/// directly from a camelCase JS object; every field is optional.
#[derive(Debug, Clone)]
#[cfg_attr(feature = "serde", derive(serde::Deserialize))]
#[cfg_attr(feature = "serde", serde(rename_all = "camelCase", default))]
pub struct OptionsDto {
    pub preset: String,
    pub color_mode: String,
    pub curve_type: String,
    pub stacking: String,
    pub posterize_steps: u8,
    pub threshold: u8,
    pub version: String,
    pub draw_style: String,
    pub group_by: String,
    /// Empty string keeps each shape's traced color (no stroke override).
    pub stroke_color: String,
    pub stroke_width: f32,
    pub non_scaling_stroke: bool,
    pub fixed_size: bool,
    pub adobe_compat: bool,
    pub clip_overflow: bool,
}

impl Default for OptionsDto {
    fn default() -> Self {
        OptionsDto {
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

impl From<OptionsDto> for SvgOptions {
    fn from(o: OptionsDto) -> Self {
        let stroke_color = {
            let c = o.stroke_color.trim();
            if c.is_empty() {
                None
            } else {
                Some(c.to_string())
            }
        };
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
                color: stroke_color,
                // Sanitize the caller-supplied width at the boundary: a
                // NaN/inf/≤0 value from JS or FFI would otherwise be written
                // verbatim as `stroke-width="NaN"` into the output SVG (and on
                // into PDF/EPS/DXF), silently corrupting it instead of failing.
                // Fall back to 1.0.
                width: if o.stroke_width.is_finite() && o.stroke_width > 0.0 {
                    o.stroke_width
                } else {
                    1.0
                },
                non_scaling: o.non_scaling_stroke,
            },
            fixed_size: o.fixed_size,
            adobe_compat: o.adobe_compat,
            clip_overflow: o.clip_overflow,
        }
    }
}

/// Options for WebP encoding.
#[derive(Debug, Clone)]
pub struct WebpOptions {
    /// Lossy quality, 0–100. Ignored when `lossless` is true.
    pub quality: f32,
    /// Lossless encoding. Always honored, even in the pure-Rust/WASM build
    /// (this is the feature `canvas.toBlob` can't provide on the web).
    pub lossless: bool,
    /// Desaturate to grayscale before encoding ("Mono" color mode for raster).
    pub grayscale: bool,
}

impl Default for WebpOptions {
    fn default() -> Self {
        WebpOptions {
            quality: 82.0,
            lossless: false,
            grayscale: false,
        }
    }
}

impl Default for SvgOptions {
    fn default() -> Self {
        SvgOptions {
            preset: Preset::default(),
            color_mode: ColorMode::default(),
            curve_type: CurveType::default(),
            stacking: Stacking::default(),
            posterize_steps: 4,
            threshold: 128,
            version: SvgVersion::default(),
            draw_style: DrawStyle::default(),
            group_by: GroupBy::default(),
            stroke: StrokeStyle::default(),
            fixed_size: false,
            adobe_compat: false,
            clip_overflow: false,
        }
    }
}

/// Errors surfaced to every binding. Kept stringly-typed at the boundary so
/// WASM/FFI callers get a clear message without leaking Rust error types.
#[derive(Debug, Clone)]
pub enum ConvertError {
    /// Input rejected before decoding — malformed, or larger than the engine's
    /// safety limits (see `decode`). Distinct from `Decode` so callers can tell
    /// "bad/oversized input" from "decoder failure".
    InvalidInput(String),
    Decode(String),
    Trace(String),
    Encode(String),
}

impl core::fmt::Display for ConvertError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            ConvertError::InvalidInput(m) => write!(f, "invalid input: {m}"),
            ConvertError::Decode(m) => write!(f, "failed to decode image: {m}"),
            ConvertError::Trace(m) => write!(f, "failed to trace image: {m}"),
            ConvertError::Encode(m) => write!(f, "failed to encode output: {m}"),
        }
    }
}

impl std::error::Error for ConvertError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn non_finite_or_nonpositive_stroke_width_falls_back_to_1() {
        for bad in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY, -1.0, 0.0] {
            let dto = OptionsDto {
                stroke_width: bad,
                ..OptionsDto::default()
            };
            let opts: SvgOptions = dto.into();
            assert_eq!(
                opts.stroke.width, 1.0,
                "width {bad} should fall back to 1.0"
            );
        }
    }

    #[test]
    fn valid_stroke_width_is_preserved() {
        let dto = OptionsDto {
            stroke_width: 2.5,
            ..OptionsDto::default()
        };
        let opts: SvgOptions = dto.into();
        assert_eq!(opts.stroke.width, 2.5);
    }
}
