//! SVG → DXF (AutoCAD R12 ASCII), **lines-only**.
//!
//! Traced paths are flattened to polylines and written as `LWPOLYLINE` entities.
//! Arc/spline DXF variants from the reference UI need an arc-fitting stage we
//! don't have yet (documented limitation) — this covers the common CAD-import case.
//!
//! Hand-written ASCII DXF: no extra crate, and it compiles cleanly to WASM.

use super::path::{attr_str, flatten_to_polylines, path_elements, svg_attr_number};
use crate::options::ConvertError;

/// Bézier flattening resolution for line-only output.
const FLATTEN_STEPS: usize = 8;

pub(crate) fn from_svg(svg: &str) -> Result<String, ConvertError> {
    let height = svg_attr_number(svg, "height").unwrap_or(1000.0);

    let mut out = String::new();
    // Minimal R12 header + ENTITIES section.
    out.push_str("0\nSECTION\n2\nENTITIES\n");

    for attrs in path_elements(svg) {
        let d = match attr_str(&attrs, "d") {
            Some(d) => d,
            None => continue,
        };
        for poly in flatten_to_polylines(&d, FLATTEN_STEPS) {
            write_lwpolyline(&mut out, &poly.points, poly.closed, height);
        }
    }

    out.push_str("0\nENDSEC\n0\nEOF\n");
    Ok(out)
}

fn write_lwpolyline(out: &mut String, points: &[(f64, f64)], closed: bool, height: f64) {
    if points.len() < 2 {
        return;
    }
    out.push_str("0\nLWPOLYLINE\n8\n0\n"); // entity on layer "0"
    out.push_str("90\n");
    out.push_str(&points.len().to_string());
    out.push('\n');
    out.push_str("70\n");
    out.push_str(if closed { "1\n" } else { "0\n" }); // closed flag
    for &(x, y) in points {
        // DXF Y is bottom-up; SVG Y is top-down — flip so output isn't mirrored.
        out.push_str(&format!("10\n{:.4}\n20\n{:.4}\n", x, height - y));
    }
}
