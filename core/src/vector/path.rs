//! Shared SVG-path helpers used by the EPS and DXF emitters and the
//! post-processor: tokenizing `d` strings, scanning `<path>` elements, reading
//! attributes, and flattening curves to polylines.

/// Split a path `d` string into command letters and numeric tokens.
pub(crate) fn tokenize(d: &str) -> Vec<String> {
    let mut out = Vec::new();
    let bytes = d.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i] as char;
        if c.is_ascii_alphabetic() {
            out.push(c.to_string());
            i += 1;
        } else if c.is_ascii_digit() || c == '-' || c == '.' || c == '+' {
            let start = i;
            i += 1;
            while i < bytes.len() {
                let n = bytes[i] as char;
                if n.is_ascii_digit() || n == '.' || n == '-' || n == '+' || n == 'e' || n == 'E' {
                    i += 1;
                } else {
                    break;
                }
            }
            out.push(d[start..i].to_string());
        } else {
            i += 1;
        }
    }
    out
}

/// Attribute substrings of each `<path ...>` element in document order.
pub(crate) fn path_elements(svg: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = svg;
    while let Some(start) = rest.find("<path") {
        let after = &rest[start + 5..];
        if let Some(end) = after.find('>') {
            let attrs = after[..end].strip_suffix('/').unwrap_or(&after[..end]);
            out.push(attrs.to_string());
            rest = &after[end + 1..];
        } else {
            break;
        }
    }
    out
}

/// Read `name="value"` from an attribute string.
pub(crate) fn attr_str(attrs: &str, name: &str) -> Option<String> {
    let key = format!("{name}=\"");
    let start = attrs.find(&key)? + key.len();
    let end = attrs[start..].find('"')? + start;
    Some(attrs[start..end].to_string())
}

/// Read a numeric attribute from the opening `<svg>` tag (e.g. width/height).
pub(crate) fn svg_attr_number(svg: &str, name: &str) -> Option<f64> {
    let tag = &svg[svg.find("<svg")?..];
    let tag = &tag[..tag.find('>')?];
    let raw = attr_str(tag, name)?;
    raw.trim_end_matches(|c: char| !c.is_ascii_digit() && c != '.')
        .parse()
        .ok()
}

/// A single subpath flattened to absolute points, plus whether it was closed.
pub(crate) struct Polyline {
    pub points: Vec<(f64, f64)>,
    pub closed: bool,
}

/// Flatten a path `d` (M/L/C/Z, absolute or relative) into polylines, sampling
/// cubic Béziers into `steps` segments. Used for line-only output (DXF).
pub(crate) fn flatten_to_polylines(d: &str, steps: usize) -> Vec<Polyline> {
    let tokens = tokenize(d);
    let num = |t: &str| t.parse::<f64>().unwrap_or(0.0);
    let mut polys: Vec<Polyline> = Vec::new();
    let mut cur: Vec<(f64, f64)> = Vec::new();
    let (mut cx, mut cy, mut sx, mut sy) = (0.0, 0.0, 0.0, 0.0);

    let flush = |polys: &mut Vec<Polyline>, cur: &mut Vec<(f64, f64)>, closed: bool| {
        if cur.len() >= 2 {
            polys.push(Polyline { points: std::mem::take(cur), closed });
        } else {
            cur.clear();
        }
    };

    let mut i = 0;
    while i < tokens.len() {
        match tokens[i].as_str() {
            t @ ("M" | "m") => {
                flush(&mut polys, &mut cur, false);
                let (x, y) = (num(&tokens[i + 1]), num(&tokens[i + 2]));
                cx = if t == "m" { cx + x } else { x };
                cy = if t == "m" { cy + y } else { y };
                sx = cx;
                sy = cy;
                cur.push((cx, cy));
                i += 3;
            }
            t @ ("L" | "l") => {
                let (x, y) = (num(&tokens[i + 1]), num(&tokens[i + 2]));
                cx = if t == "l" { cx + x } else { x };
                cy = if t == "l" { cy + y } else { y };
                cur.push((cx, cy));
                i += 3;
            }
            t @ ("C" | "c") => {
                let rel = t == "c";
                let b = |k: usize, base: f64| num(&tokens[i + k]) + if rel { base } else { 0.0 };
                let (x1, y1) = (b(1, cx), b(2, cy));
                let (x2, y2) = (b(3, cx), b(4, cy));
                let (x, y) = (b(5, cx), b(6, cy));
                for s in 1..=steps {
                    let u = s as f64 / steps as f64;
                    let iu = 1.0 - u;
                    let bx = iu * iu * iu * cx + 3.0 * iu * iu * u * x1 + 3.0 * iu * u * u * x2 + u * u * u * x;
                    let by = iu * iu * iu * cy + 3.0 * iu * iu * u * y1 + 3.0 * iu * u * u * y2 + u * u * u * y;
                    cur.push((bx, by));
                }
                cx = x;
                cy = y;
                i += 7;
            }
            "Z" | "z" => {
                cx = sx;
                cy = sy;
                flush(&mut polys, &mut cur, true);
                i += 1;
            }
            _ => i += 1,
        }
    }
    flush(&mut polys, &mut cur, false);
    polys
}
