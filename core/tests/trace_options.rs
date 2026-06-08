//! End-to-end check that the previously-ignored `threshold` option now affects
//! the traced SVG (audit finding H4).

use alotno_core::{png_to_svg, ColorMode, SvgOptions};
use image::codecs::png::PngEncoder;
use image::{ExtendedColorType, ImageEncoder};

/// A horizontal grayscale gradient: dark on the left, light on the right.
fn gradient_png(w: u32, h: u32) -> Vec<u8> {
    let mut rgba = Vec::with_capacity((w * h * 4) as usize);
    for _y in 0..h {
        for x in 0..w {
            let v = (x * 255 / (w - 1)) as u8;
            rgba.extend_from_slice(&[v, v, v, 255]);
        }
    }
    let mut png = Vec::new();
    PngEncoder::new(&mut png)
        .write_image(&rgba, w, h, ExtendedColorType::Rgba8)
        .expect("encode test png");
    png
}

#[test]
fn threshold_changes_mono_output() {
    let png = gradient_png(48, 8);
    let mono = |t: u8| SvgOptions {
        color_mode: ColorMode::Mono,
        threshold: t,
        ..Default::default()
    };
    // A low cutoff marks almost nothing as ink; a high cutoff marks most of the
    // gradient as ink. The traced output must differ.
    let low = png_to_svg(&png, &mono(20)).unwrap();
    let high = png_to_svg(&png, &mono(230)).unwrap();
    assert_ne!(low, high, "threshold should change the traced mono output");
}
