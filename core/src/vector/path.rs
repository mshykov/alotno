//! Shared SVG-path helpers used by the EPS and DXF emitters and the
//! post-processor: tokenizing `d` strings, scanning `<path>` elements, reading
//! attributes, and flattening curves to polylines.

/// Split a path `d` string into command letters and numeric tokens.
///
/// Tokens **borrow** from `d` (no per-token allocation): a hostile multi-MB `d`
/// passed to the public `svg_to_*` string APIs would otherwise amplify ~10× into
/// millions of tiny heap `String`s before any output — an OOM-abort vector under
/// `panic = "abort"`. All slice bounds land on ASCII bytes.
pub(crate) fn tokenize(d: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let bytes = d.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i] as char;
        if c.is_ascii_alphabetic() {
            out.push(&d[i..i + 1]);
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
            out.push(&d[start..i]);
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
    PathParser::new(d).run()
}

/// Cursor state for [`parse_path`]: token stream, active command letter, the
/// current point, and the subpath start (for `Z`). Each SVG command is one
/// small method, so every piece stays simple and obviously bounds-checked.
struct PathParser<'a> {
    tokens: Vec<&'a str>,
    i: usize,
    /// Active command letter; 0 = none seen yet.
    cmd: u8,
    cx: f64,
    cy: f64,
    sx: f64,
    sy: f64,
    cmds: Vec<PathCmd>,
}

impl<'a> PathParser<'a> {
    fn new(d: &'a str) -> Self {
        PathParser {
            tokens: tokenize(d),
            i: 0,
            cmd: 0,
            cx: 0.0,
            cy: 0.0,
            sx: 0.0,
            sy: 0.0,
            cmds: Vec::new(),
        }
    }

    fn run(mut self) -> Vec<PathCmd> {
        while self.i < self.tokens.len() {
            if is_command(self.tokens[self.i]) {
                self.cmd = self.tokens[self.i].as_bytes()[0];
                self.i += 1;
            } else if self.cmd == 0 {
                // Numeric token before any command — malformed; skip it.
                self.i += 1;
                continue;
            }
            if !self.apply_command() {
                break; // truncated operands → stop cleanly
            }
        }
        self.cmds
    }

    /// Apply the active command once. Returns false on truncated input.
    fn apply_command(&mut self) -> bool {
        match self.cmd.to_ascii_uppercase() {
            b'M' => self.move_to(),
            b'L' => self.line_to(),
            b'H' => self.horizontal(),
            b'V' => self.vertical(),
            b'C' => self.curve_to(),
            // Unsupported curve shorthands: consume the right operand count and
            // line to the endpoint (never produced by vtracer; see PathCmd).
            b'S' | b'Q' => self.line_to_endpoint(4, 2, 3),
            b'T' => self.line_to_endpoint(2, 0, 1),
            b'A' => self.line_to_endpoint(7, 5, 6),
            b'Z' => {
                self.close();
                true
            }
            _ => {
                // Unknown command letter: skip any operands that follow it.
                self.cmd = 0;
                true
            }
        }
    }

    /// Read `n` numeric operands, advancing only on success. None = truncated.
    fn take(&mut self, n: usize) -> Option<Vec<f64>> {
        let mut vals = Vec::with_capacity(n);
        for k in 0..n {
            let t = self.tokens.get(self.i + k)?;
            if is_command(t) {
                return None;
            }
            vals.push(t.parse::<f64>().unwrap_or(0.0));
        }
        self.i += n;
        Some(vals)
    }

    /// Resolve an operand against `base` when the active command is relative.
    fn abs(&self, v: f64, base: f64) -> f64 {
        if self.cmd.is_ascii_lowercase() {
            base + v
        } else {
            v
        }
    }

    fn move_to(&mut self) -> bool {
        let Some(v) = self.take(2) else { return false };
        self.cx = self.abs(v[0], self.cx);
        self.cy = self.abs(v[1], self.cy);
        self.sx = self.cx;
        self.sy = self.cy;
        self.cmds.push(PathCmd::Move {
            x: self.cx,
            y: self.cy,
        });
        // Per SVG: coordinates following a moveto are implicit linetos.
        self.cmd = if self.cmd.is_ascii_lowercase() {
            b'l'
        } else {
            b'L'
        };
        true
    }

    fn line_to(&mut self) -> bool {
        let Some(v) = self.take(2) else { return false };
        self.cx = self.abs(v[0], self.cx);
        self.cy = self.abs(v[1], self.cy);
        self.cmds.push(PathCmd::Line {
            x: self.cx,
            y: self.cy,
        });
        true
    }

    fn horizontal(&mut self) -> bool {
        let Some(v) = self.take(1) else { return false };
        self.cx = self.abs(v[0], self.cx);
        self.cmds.push(PathCmd::Line {
            x: self.cx,
            y: self.cy,
        });
        true
    }

    fn vertical(&mut self) -> bool {
        let Some(v) = self.take(1) else { return false };
        self.cy = self.abs(v[0], self.cy);
        self.cmds.push(PathCmd::Line {
            x: self.cx,
            y: self.cy,
        });
        true
    }

    fn curve_to(&mut self) -> bool {
        let Some(v) = self.take(6) else { return false };
        // All six offsets resolve against the point *before* this command.
        let (x1, y1) = (self.abs(v[0], self.cx), self.abs(v[1], self.cy));
        let (x2, y2) = (self.abs(v[2], self.cx), self.abs(v[3], self.cy));
        let (x, y) = (self.abs(v[4], self.cx), self.abs(v[5], self.cy));
        self.cmds.push(PathCmd::Curve {
            x1,
            y1,
            x2,
            y2,
            x,
            y,
        });
        self.cx = x;
        self.cy = y;
        true
    }

    /// Consume `n` operands and line to the endpoint at indices (`xi`, `yi`).
    fn line_to_endpoint(&mut self, n: usize, xi: usize, yi: usize) -> bool {
        let Some(v) = self.take(n) else { return false };
        self.cx = self.abs(v[xi], self.cx);
        self.cy = self.abs(v[yi], self.cy);
        self.cmds.push(PathCmd::Line {
            x: self.cx,
            y: self.cy,
        });
        true
    }

    fn close(&mut self) {
        self.cx = self.sx;
        self.cy = self.sy;
        self.cmds.push(PathCmd::Close);
        self.cmd = 0; // Z takes no operands; require a new command next.
    }
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
