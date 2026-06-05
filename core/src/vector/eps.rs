//! SVG → EPS (vector PostScript).
//!
//! A faithful Rust port of the formatter from the Electron prototype
//! (`legacy/electron-mac/electron/main.cjs`, `svgToEps`). Emits `<path>` geometry
//! as PostScript. Path parsing helpers are shared in `super::path`.

use super::path::{attr_str, path_elements, svg_attr_number, tokenize};
use crate::options::ConvertError;

pub(crate) fn from_svg(svg: &str) -> Result<String, ConvertError> {
    let w = svg_attr_number(svg, "width").unwrap_or(1000.0);
    let h = svg_attr_number(svg, "height").unwrap_or(1000.0);

    let mut ps = String::new();
    ps.push_str("%!PS-Adobe-3.0 EPSF-3.0\n");
    ps.push_str(&format!("%%BoundingBox: 0 0 {} {}\n", w.ceil() as i64, h.ceil() as i64));
    ps.push_str("%%Creator: Alotno\n%%EndComments\ngsave\n");

    for attrs in path_elements(svg) {
        let d = match attr_str(&attrs, "d") {
            Some(d) => d,
            None => continue,
        };
        let fill = attr_str(&attrs, "fill");
        let stroke = attr_str(&attrs, "stroke");
        let stroke_width = attr_str(&attrs, "stroke-width")
            .and_then(|s| s.parse::<f64>().ok())
            .unwrap_or(1.0);

        emit_path(&mut ps, &d, h);

        if let Some(rgb) = fill.as_deref().and_then(hex_to_rgb) {
            ps.push_str(&format!("{:.3} {:.3} {:.3} setrgbcolor\n", rgb.0, rgb.1, rgb.2));
            ps.push_str(if stroke.as_deref().map_or(false, is_paint) {
                "gsave fill grestore\n"
            } else {
                "fill\n"
            });
        }
        if let Some(rgb) = stroke.as_deref().filter(|s| is_paint(s)).and_then(hex_to_rgb) {
            ps.push_str(&format!("{:.3} {:.3} {:.3} setrgbcolor\n", rgb.0, rgb.1, rgb.2));
            ps.push_str(&format!("{stroke_width} setlinewidth\nstroke\n"));
        }
    }

    ps.push_str("grestore\n%%EOF\n");
    Ok(ps)
}

/// Emit one path's M/L/C/Z commands as PostScript, flipping Y (PS origin = bottom).
fn emit_path(ps: &mut String, d: &str, height: f64) {
    let tokens = tokenize(d);
    let fy = |y: f64| height - y;
    let (mut cx, mut cy, mut sx, mut sy) = (0.0, 0.0, 0.0, 0.0);
    let num = |t: &str| t.parse::<f64>().unwrap_or(0.0);
    ps.push_str("newpath\n");

    let mut i = 0;
    while i < tokens.len() {
        match tokens[i].as_str() {
            t @ ("M" | "m") => {
                let (x, y) = (num(&tokens[i + 1]), num(&tokens[i + 2]));
                cx = if t == "m" { cx + x } else { x };
                cy = if t == "m" { cy + y } else { y };
                sx = cx;
                sy = cy;
                ps.push_str(&format!("{:.3} {:.3} moveto\n", cx, fy(cy)));
                i += 3;
            }
            t @ ("L" | "l") => {
                let (x, y) = (num(&tokens[i + 1]), num(&tokens[i + 2]));
                cx = if t == "l" { cx + x } else { x };
                cy = if t == "l" { cy + y } else { y };
                ps.push_str(&format!("{:.3} {:.3} lineto\n", cx, fy(cy)));
                i += 3;
            }
            t @ ("C" | "c") => {
                let rel = t == "c";
                let b = |k: usize, base: f64| num(&tokens[i + k]) + if rel { base } else { 0.0 };
                let (x1, y1) = (b(1, cx), b(2, cy));
                let (x2, y2) = (b(3, cx), b(4, cy));
                let (x, y) = (b(5, cx), b(6, cy));
                ps.push_str(&format!(
                    "{:.3} {:.3} {:.3} {:.3} {:.3} {:.3} curveto\n",
                    x1, fy(y1), x2, fy(y2), x, fy(y)
                ));
                cx = x;
                cy = y;
                i += 7;
            }
            "Z" | "z" => {
                ps.push_str("closepath\n");
                cx = sx;
                cy = sy;
                i += 1;
            }
            _ => i += 1,
        }
    }
}

fn is_paint(s: &str) -> bool {
    !s.is_empty() && s != "none"
}

/// `#rgb` or `#rrggbb` → 0.0–1.0 RGB triple.
fn hex_to_rgb(h: &str) -> Option<(f64, f64, f64)> {
    let x = h.strip_prefix('#')?;
    let full = if x.len() == 3 {
        x.chars().flat_map(|c| [c, c]).collect::<String>()
    } else {
        x.to_string()
    };
    if full.len() < 6 {
        return None;
    }
    let p = |a: usize| u8::from_str_radix(&full[a..a + 2], 16).ok().map(|v| v as f64 / 255.0);
    Some((p(0)?, p(2)?, p(4)?))
}
