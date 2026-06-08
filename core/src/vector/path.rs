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

/// One absolute drawing command, the resolved output of [`parse_path`].
///
/// Relative commands are converted to absolute, the shorthand `H`/`V` become
/// lines, and the curve shorthands `S`/`Q`/`T`/`A` (which vtracer never emits)
/// degrade to a straight line to their endpoint — a documented, lossy-but-safe
/// fallback that keeps subpaths connected instead of dropping or mis-parsing them.
pub(crate) enum PathCmd {
    Move {
        x: f64,
        y: f64,
    },
    Line {
        x: f64,
        y: f64,
    },
    Curve {
        x1: f64,
        y1: f64,
        x2: f64,
        y2: f64,
        x: f64,
        y: f64,
    },
    Close,
}

/// True if a token begins a command letter (vs. a numeric run).
fn is_command(tok: &str) -> bool {
    tok.as_bytes().first().is_some_and(u8::is_ascii_alphabetic)
}

/// Parse an SVG path `d` string into a flat list of **absolute** [`PathCmd`]s.
///
/// This is the single, bounds-checked parser shared by the EPS and DXF emitters.
/// It is total: any input — truncated (`"M"`), malformed, or with trailing junk
/// — yields a (possibly empty) command list and **never panics**, which is a
/// hard requirement for the WASM/FFI boundary (`panic = "abort"`).
///
/// SVG quirks handled: relative commands, implicit repeated commands (e.g.
/// `M 0 0 1 1 2 2` is a moveto followed by two implicit linetos), and the
/// `H`/`V` shorthands. See [`PathCmd`] for the `S`/`Q`/`T`/`A` fallback.
pub(crate) fn parse_path(d: &str) -> Vec<PathCmd> {
    let tokens = tokenize(d);
    let mut cmds = Vec::new();
    // current point, and the start of the current subpath (for Z)
    let (mut cx, mut cy, mut sx, mut sy) = (0.0_f64, 0.0_f64, 0.0_f64, 0.0_f64);
    let mut i = 0;
    let mut cmd: u8 = 0; // active command letter; 0 = none seen yet

    // Read `n` numeric operands starting at `i` WITHOUT advancing on failure.
    // Returns None if fewer than `n` numeric tokens remain (truncated input).
    let take = |i: usize, n: usize| -> Option<Vec<f64>> {
        let mut vals = Vec::with_capacity(n);
        for k in 0..n {
            let t = tokens.get(i + k)?;
            if is_command(t) {
                return None;
            }
            vals.push(t.parse::<f64>().unwrap_or(0.0));
        }
        Some(vals)
    };

    while i < tokens.len() {
        if is_command(&tokens[i]) {
            cmd = tokens[i].as_bytes()[0];
            i += 1;
        } else if cmd == 0 {
            // Numeric token before any command — malformed; skip it.
            i += 1;
            continue;
        }

        let rel = cmd.is_ascii_lowercase();
        match cmd.to_ascii_uppercase() {
            b'M' => {
                let Some(v) = take(i, 2) else { break };
                i += 2;
                cx = if rel { cx + v[0] } else { v[0] };
                cy = if rel { cy + v[1] } else { v[1] };
                sx = cx;
                sy = cy;
                cmds.push(PathCmd::Move { x: cx, y: cy });
                // Per SVG: coordinates following a moveto are implicit linetos.
                cmd = if rel { b'l' } else { b'L' };
            }
            b'L' => {
                let Some(v) = take(i, 2) else { break };
                i += 2;
                cx = if rel { cx + v[0] } else { v[0] };
                cy = if rel { cy + v[1] } else { v[1] };
                cmds.push(PathCmd::Line { x: cx, y: cy });
            }
            b'H' => {
                let Some(v) = take(i, 1) else { break };
                i += 1;
                cx = if rel { cx + v[0] } else { v[0] };
                cmds.push(PathCmd::Line { x: cx, y: cy });
            }
            b'V' => {
                let Some(v) = take(i, 1) else { break };
                i += 1;
                cy = if rel { cy + v[0] } else { v[0] };
                cmds.push(PathCmd::Line { x: cx, y: cy });
            }
            b'C' => {
                let Some(v) = take(i, 6) else { break };
                i += 6;
                let b = |dx: f64, base: f64| if rel { base + dx } else { dx };
                let (x1, y1) = (b(v[0], cx), b(v[1], cy));
                let (x2, y2) = (b(v[2], cx), b(v[3], cy));
                let (x, y) = (b(v[4], cx), b(v[5], cy));
                cmds.push(PathCmd::Curve {
                    x1,
                    y1,
                    x2,
                    y2,
                    x,
                    y,
                });
                cx = x;
                cy = y;
            }
            // Unsupported curve shorthands: consume the right operand count and
            // emit a line to the endpoint (never produced by vtracer; see PathCmd).
            b'S' | b'Q' => {
                let Some(v) = take(i, 4) else { break };
                i += 4;
                cx = if rel { cx + v[2] } else { v[2] };
                cy = if rel { cy + v[3] } else { v[3] };
                cmds.push(PathCmd::Line { x: cx, y: cy });
            }
            b'T' => {
                let Some(v) = take(i, 2) else { break };
                i += 2;
                cx = if rel { cx + v[0] } else { v[0] };
                cy = if rel { cy + v[1] } else { v[1] };
                cmds.push(PathCmd::Line { x: cx, y: cy });
            }
            b'A' => {
                let Some(v) = take(i, 7) else { break };
                i += 7;
                cx = if rel { cx + v[5] } else { v[5] };
                cy = if rel { cy + v[6] } else { v[6] };
                cmds.push(PathCmd::Line { x: cx, y: cy });
            }
            b'Z' => {
                cx = sx;
                cy = sy;
                cmds.push(PathCmd::Close);
                cmd = 0; // Z takes no operands; require a new command next.
            }
            _ => {
                // Unknown command letter: skip any operands that follow it.
                cmd = 0;
            }
        }
    }
    cmds
}

/// A single subpath flattened to absolute points, plus whether it was closed.
pub(crate) struct Polyline {
    pub points: Vec<(f64, f64)>,
    pub closed: bool,
}

/// Flatten a path `d` (absolute or relative) into polylines, sampling cubic
/// Béziers into `steps` segments. Used for line-only output (DXF). Built on
/// [`parse_path`], so it inherits the same total/panic-free guarantee.
pub(crate) fn flatten_to_polylines(d: &str, steps: usize) -> Vec<Polyline> {
    let steps = steps.max(1);
    let mut polys: Vec<Polyline> = Vec::new();
    let mut cur: Vec<(f64, f64)> = Vec::new();
    let (mut cx, mut cy) = (0.0_f64, 0.0_f64);

    let flush = |polys: &mut Vec<Polyline>, cur: &mut Vec<(f64, f64)>, closed: bool| {
        if cur.len() >= 2 {
            polys.push(Polyline {
                points: std::mem::take(cur),
                closed,
            });
        } else {
            cur.clear();
        }
    };

    for cmd in parse_path(d) {
        match cmd {
            PathCmd::Move { x, y } => {
                flush(&mut polys, &mut cur, false);
                cx = x;
                cy = y;
                cur.push((cx, cy));
            }
            PathCmd::Line { x, y } => {
                cx = x;
                cy = y;
                cur.push((cx, cy));
            }
            PathCmd::Curve {
                x1,
                y1,
                x2,
                y2,
                x,
                y,
            } => {
                for s in 1..=steps {
                    let u = s as f64 / steps as f64;
                    let iu = 1.0 - u;
                    let bx = iu * iu * iu * cx
                        + 3.0 * iu * iu * u * x1
                        + 3.0 * iu * u * u * x2
                        + u * u * u * x;
                    let by = iu * iu * iu * cy
                        + 3.0 * iu * iu * u * y1
                        + 3.0 * iu * u * u * y2
                        + u * u * u * y;
                    cur.push((bx, by));
                }
                cx = x;
                cy = y;
            }
            PathCmd::Close => flush(&mut polys, &mut cur, true),
        }
    }
    flush(&mut polys, &mut cur, false);
    polys
}
