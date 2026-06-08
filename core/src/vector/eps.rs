//! SVG → EPS (vector PostScript).
//!
//! A faithful Rust port of the formatter from the Electron prototype
//! (`legacy/electron-mac/electron/main.cjs`, `svgToEps`). Emits `<path>` geometry
//! as PostScript. Path parsing helpers are shared in `super::path`.

use super::path::{attr_str, parse_path, path_elements, svg_attr_number, PathCmd};
use crate::options::ConvertError;

/// Clamp a parsed SVG dimension to a sane, finite range for the BoundingBox.
/// Guards against NaN/inf or absurd values from a malformed `<svg>` tag.
fn clamp_dim(v: f64) -> i64 {
    if !v.is_finite() || v <= 0.0 {
        1000
    } else {
        v.ceil().min(1_000_000.0) as i64
    }
}

pub(crate) fn from_svg(svg: &str) -> Result<String, ConvertError> {
    let w = svg_attr_number(svg, "width").unwrap_or(1000.0);
    let h = svg_attr_number(svg, "height").unwrap_or(1000.0);

    let mut ps = String::new();
    ps.push_str("%!PS-Adobe-3.0 EPSF-3.0\n");
    ps.push_str(&format!(
        "%%BoundingBox: 0 0 {} {}\n",
        clamp_dim(w),
        clamp_dim(h)
    ));
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

        // SVG's default fill is black; `fill="none"` disables it. An unparseable
        // color falls back to black rather than silently dropping the shape.
        let fill_rgb = match fill.as_deref() {
            Some(f) if !is_paint(f) => None,
            Some(f) => Some(hex_to_rgb(f).unwrap_or((0.0, 0.0, 0.0))),
            None => Some((0.0, 0.0, 0.0)),
        };
        let stroke_rgb = stroke
            .as_deref()
            .filter(|s| is_paint(s))
            .and_then(hex_to_rgb);

        // Nothing to paint → don't leave a dangling path in the PS graphics state.
        if fill_rgb.is_none() && stroke_rgb.is_none() {
            continue;
        }

        emit_path(&mut ps, &d, h);

        if let Some(rgb) = fill_rgb {
            ps.push_str(&format!(
                "{:.3} {:.3} {:.3} setrgbcolor\n",
                rgb.0, rgb.1, rgb.2
            ));
            ps.push_str(if stroke_rgb.is_some() {
                "gsave fill grestore\n"
            } else {
                "fill\n"
            });
        }
        if let Some(rgb) = stroke_rgb {
            ps.push_str(&format!(
                "{:.3} {:.3} {:.3} setrgbcolor\n",
                rgb.0, rgb.1, rgb.2
            ));
            ps.push_str(&format!("{stroke_width} setlinewidth\nstroke\n"));
        }
    }

    ps.push_str("grestore\n%%EOF\n");
    Ok(ps)
}

/// Emit one path as PostScript, flipping Y (PS origin = bottom). Parsing is
/// delegated to the shared, panic-free [`parse_path`].
fn emit_path(ps: &mut String, d: &str, height: f64) {
    let fy = |y: f64| height - y;
    ps.push_str("newpath\n");
    for cmd in parse_path(d) {
        match cmd {
            PathCmd::Move { x, y } => ps.push_str(&format!("{:.3} {:.3} moveto\n", x, fy(y))),
            PathCmd::Line { x, y } => ps.push_str(&format!("{:.3} {:.3} lineto\n", x, fy(y))),
            PathCmd::Curve {
                x1,
                y1,
                x2,
                y2,
                x,
                y,
            } => ps.push_str(&format!(
                "{:.3} {:.3} {:.3} {:.3} {:.3} {:.3} curveto\n",
                x1,
                fy(y1),
                x2,
                fy(y2),
                x,
                fy(y)
            )),
            PathCmd::Close => ps.push_str("closepath\n"),
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
    let p = |a: usize| {
        u8::from_str_radix(&full[a..a + 2], 16)
            .ok()
            .map(|v| v as f64 / 255.0)
    };
    Some((p(0)?, p(2)?, p(4)?))
}
