//! End-to-end conversion coverage: WebP variants (lossless/lossy/grayscale),
//! trace presets + posterized mode, and the SVG post-processing options
//! (group-by-color, clip, fixed size, versions, draw styles).

use alotno_core::{
    png_to_svg, png_to_webp, ColorMode, DrawStyle, GroupBy, Preset, StrokeStyle, SvgOptions,
    SvgVersion, WebpOptions,
};
use image::codecs::png::PngEncoder;
use image::{ExtendedColorType, ImageEncoder};

/// A small two-tone PNG (left dark, right light) so traces produce shapes.
fn two_tone_png(w: u32, h: u32) -> Vec<u8> {
    let mut rgba = Vec::with_capacity((w * h * 4) as usize);
    for _y in 0..h {
        for x in 0..w {
            let v = if x < w / 2 { 30u8 } else { 220u8 };
            rgba.extend_from_slice(&[v, v / 2, v, 255]);
        }
    }
    let mut png = Vec::new();
    PngEncoder::new(&mut png)
        .write_image(&rgba, w, h, ExtendedColorType::Rgba8)
        .expect("encode test png");
    png
}

#[test]
fn webp_lossless_lossy_and_grayscale_all_encode() {
    let png = two_tone_png(16, 16);
    let lossless = png_to_webp(
        &png,
        &WebpOptions {
            lossless: true,
            ..Default::default()
        },
    )
    .unwrap();
    assert!(lossless.starts_with(b"RIFF"));

    let lossy = png_to_webp(
        &png,
        &WebpOptions {
            lossless: false,
            quality: 50.0,
            ..Default::default()
        },
    )
    .unwrap();
    assert!(lossy.starts_with(b"RIFF"));

    let gray = png_to_webp(
        &png,
        &WebpOptions {
            lossless: true,
            grayscale: true,
            ..Default::default()
        },
    )
    .unwrap();
    assert!(gray.starts_with(b"RIFF"));
    // Grayscale output differs from the color encode of the same image.
    assert_ne!(gray, lossless);
}

#[test]
fn every_preset_traces_in_both_color_modes() {
    let png = two_tone_png(32, 16);
    for preset in [Preset::Low, Preset::Medium, Preset::High, Preset::Ultra] {
        for color_mode in [ColorMode::Mono, ColorMode::Posterized] {
            let svg = png_to_svg(
                &png,
                &SvgOptions {
                    preset,
                    color_mode,
                    ..Default::default()
                },
            )
            .unwrap();
            assert!(
                svg.contains("<svg"),
                "{preset:?}/{color_mode:?} produced no svg"
            );
        }
    }
}

#[test]
fn postprocess_options_shape_the_svg() {
    let png = two_tone_png(32, 16);
    let base = SvgOptions {
        color_mode: ColorMode::Posterized,
        ..Default::default()
    };

    // group-by-color wraps paths in <g fill=...>
    let grouped = png_to_svg(
        &png,
        &SvgOptions {
            group_by: GroupBy::Color,
            ..base.clone()
        },
    )
    .unwrap();
    assert!(grouped.contains("<g fill="));

    // clip-overflow adds the clipPath defs
    let clipped = png_to_svg(
        &png,
        &SvgOptions {
            clip_overflow: true,
            ..base.clone()
        },
    )
    .unwrap();
    assert!(clipped.contains("alotno-clip"));

    // fixed size keeps width/height; scalable drops them
    let fixed = png_to_svg(
        &png,
        &SvgOptions {
            fixed_size: true,
            ..base.clone()
        },
    )
    .unwrap();
    assert!(fixed.contains("width=\""));

    // tiny profile + adobe namespace
    let tiny = png_to_svg(
        &png,
        &SvgOptions {
            version: SvgVersion::Tiny1_2,
            adobe_compat: true,
            ..base.clone()
        },
    )
    .unwrap();
    assert!(tiny.contains("baseProfile=\"tiny\""));
    assert!(tiny.contains("ns.adobe.com"));

    // stroke styles
    let stroked = png_to_svg(
        &png,
        &SvgOptions {
            draw_style: DrawStyle::Stroke,
            stroke: StrokeStyle {
                color: Some("#112233".into()),
                width: 2.0,
                non_scaling: true,
            },
            ..base.clone()
        },
    )
    .unwrap();
    assert!(stroked.contains("stroke=\"#112233\""));
    assert!(stroked.contains("non-scaling-stroke"));

    let both = png_to_svg(
        &png,
        &SvgOptions {
            draw_style: DrawStyle::Both,
            ..base
        },
    )
    .unwrap();
    assert!(both.contains("stroke="));
    assert!(both.contains("fill="));
}
