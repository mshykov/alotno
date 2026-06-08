//! PNG → SVG vectorization, built on `vtracer` (visioncortex).
//!
//! `vtracer` produces materially better color/curve tracing than the `potrace`
//! the Electron prototype used, and being pure Rust it compiles cleanly to WASM.
//!
//! NOTE: vtracer's public API has shifted slightly across releases. This targets
//! the 0.6 line; if you bump the crate, re-check the `Config` field names and the
//! `convert` signature with `cargo doc -p vtracer --open`.

use super::svg_postprocess;
use crate::decode::RgbaImage;
use crate::options::{ColorMode, ConvertError, CurveType, Preset, Stacking, SvgOptions};
use visioncortex::{ColorImage, PathSimplifyMode};
use vtracer::{ColorMode as VColorMode, Config, Hierarchical};

/// Per-preset tuning. Higher detail = smaller speckle filter + tighter fitting.
struct Tuning {
    filter_speckle: usize,
    color_precision: i32,
    layer_difference: i32,
    corner_threshold: i32,
    length_threshold: f64,
    splice_threshold: i32,
    path_precision: u32,
}

fn tuning_for(preset: Preset) -> Tuning {
    // `path_precision` is decimal places per coordinate — the dominant factor in
    // output size. 8 (the old Ultra value) is sub-pixel nonsense that bloated a
    // simple icon to megabytes; 1–3 is visually identical and far smaller.
    // For color mode, larger `layer_difference` + smaller `color_precision` +
    // a non-trivial `filter_speckle` keep the layer/path count from exploding.
    match preset {
        Preset::Low => Tuning {
            filter_speckle: 12,
            color_precision: 4,
            layer_difference: 32,
            corner_threshold: 80,
            length_threshold: 6.0,
            splice_threshold: 60,
            path_precision: 1,
        },
        Preset::Medium => Tuning {
            filter_speckle: 6,
            color_precision: 5,
            layer_difference: 24,
            corner_threshold: 70,
            length_threshold: 4.0,
            splice_threshold: 45,
            path_precision: 2,
        },
        Preset::High => Tuning {
            filter_speckle: 4,
            color_precision: 6,
            layer_difference: 16,
            corner_threshold: 60,
            length_threshold: 4.0,
            splice_threshold: 45,
            path_precision: 2,
        },
        Preset::Ultra => Tuning {
            filter_speckle: 2,
            color_precision: 7,
            layer_difference: 12,
            corner_threshold: 50,
            length_threshold: 3.0,
            splice_threshold: 30,
            path_precision: 3,
        },
    }
}

pub(crate) fn to_svg(image: RgbaImage, options: &SvgOptions) -> Result<String, ConvertError> {
    let color_image = to_color_image(&image, options);
    let t = tuning_for(options.preset);

    // vtracer exposes no explicit "number of color layers" or binary-cutoff
    // knob, so the two posterize/mono options are honored elsewhere:
    //   * `posterize_steps` → `layer_difference` (more steps = more bands), here.
    //   * `threshold`       → applied to the image in `to_color_image` (Mono).
    let layer_difference = match options.color_mode {
        ColorMode::Posterized => posterize_layer_difference(options.posterize_steps),
        ColorMode::Mono => t.layer_difference,
    };

    let config = Config {
        color_mode: match options.color_mode {
            ColorMode::Mono => VColorMode::Binary,
            ColorMode::Posterized => VColorMode::Color,
        },
        hierarchical: match options.stacking {
            Stacking::Cutouts => Hierarchical::Cutout,
            Stacking::Stacked => Hierarchical::Stacked,
        },
        filter_speckle: t.filter_speckle,
        color_precision: t.color_precision,
        layer_difference,
        mode: match options.curve_type {
            CurveType::Curves => PathSimplifyMode::Spline,
            CurveType::Lines => PathSimplifyMode::Polygon,
        },
        corner_threshold: t.corner_threshold,
        length_threshold: t.length_threshold,
        splice_threshold: t.splice_threshold,
        max_iterations: 10,
        path_precision: Some(t.path_precision),
    };

    let svg = vtracer::convert(color_image, config).map_err(ConvertError::Trace)?;
    // Apply style/version/grouping post-processing to the raw traced SVG.
    Ok(svg_postprocess::apply(svg.to_string(), options))
}

/// Map the requested posterize step count (2–8) to vtracer's `layer_difference`.
/// vtracer has no explicit layer-count parameter; `layer_difference` inversely
/// controls how many color bands appear, so more steps → smaller difference →
/// more layers. Clamped to a range that stays visually sensible.
fn posterize_layer_difference(steps: u8) -> i32 {
    let steps = i32::from(steps.clamp(2, 8));
    (256 / steps).clamp(16, 128)
}

/// Luminance threshold for Mono mode: pixels at or below `threshold` become
/// black ink, the rest white; alpha is preserved so transparent areas stay
/// background. This makes the `threshold` option actually control the mono
/// cutoff (vtracer's Binary mode does its own clustering otherwise).
fn binarize(pixels: &[u8], threshold: u8) -> Vec<u8> {
    let mut out = Vec::with_capacity(pixels.len());
    for px in pixels.chunks_exact(4) {
        let lum = 0.299 * f32::from(px[0]) + 0.587 * f32::from(px[1]) + 0.114 * f32::from(px[2]);
        let v = if lum <= f32::from(threshold) { 0 } else { 255 };
        out.extend_from_slice(&[v, v, v, px[3]]);
    }
    out
}

fn to_color_image(image: &RgbaImage, options: &SvgOptions) -> ColorImage {
    // visioncortex ColorImage stores tightly-packed RGBA, exactly like our buffer.
    // For Mono, binarize by the threshold first so the cutoff is user-controlled.
    let pixels = match options.color_mode {
        ColorMode::Mono => binarize(&image.pixels, options.threshold),
        ColorMode::Posterized => image.pixels.clone(),
    };
    ColorImage {
        pixels,
        width: image.width as usize,
        height: image.height as usize,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn posterize_steps_more_steps_more_layers() {
        // More steps must not produce a coarser (larger) layer_difference.
        assert!(posterize_layer_difference(8) < posterize_layer_difference(2));
        // Clamped into the sensible band.
        assert_eq!(posterize_layer_difference(0), 128); // clamps up to 2 steps
        assert!((16..=128).contains(&posterize_layer_difference(8)));
    }

    #[test]
    fn binarize_respects_threshold() {
        // One mid-gray pixel (lum ~150).
        let gray = [150u8, 150, 150, 255];
        // Low threshold → pixel is above cutoff → white.
        assert_eq!(binarize(&gray, 10)[0], 255);
        // High threshold → pixel is at/below cutoff → black.
        assert_eq!(binarize(&gray, 200)[0], 0);
        // Alpha preserved.
        assert_eq!(binarize(&gray, 200)[3], 255);
    }
}
