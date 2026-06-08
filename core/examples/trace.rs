//! Dev utility: trace a PNG and report the SVG size.
//!
//!   cargo run -q --example trace -- <input.png> [preset] [mono|color] [out.svg]
//!
//! preset: low | medium | high | ultra (default high)

use alotno_core::{png_to_svg, ColorMode, Preset, SvgOptions};
use std::{env, fs};

fn main() {
    let args: Vec<String> = env::args().collect();
    let path = args
        .get(1)
        .expect("usage: trace <input.png> [preset] [mono|color] [out.svg]");
    let preset = args.get(2).map(String::as_str).unwrap_or("high");
    let mode = args.get(3).map(String::as_str).unwrap_or("mono");

    let png = fs::read(path).expect("read png");
    let opts = SvgOptions {
        preset: Preset::parse(preset),
        color_mode: ColorMode::parse(mode),
        ..Default::default()
    };
    let svg = png_to_svg(&png, &opts).expect("trace");

    eprintln!(
        "{preset} {mode}: PNG {} bytes -> SVG {} bytes ({:.0} KB)",
        png.len(),
        svg.len(),
        svg.len() as f64 / 1024.0
    );
    if let Some(out) = args.get(4) {
        fs::write(out, &svg).expect("write svg");
        eprintln!("wrote {out}");
    }
}
