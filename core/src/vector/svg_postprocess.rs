//! Post-processing applied to the traced SVG before it's returned (and before
//! PDF/EPS/DXF derive from it). Each step is a string transform — no extra deps.
//!
//! Implements the buildable parts of the reference settings panel: SVG version,
//! draw style, stroke style, group-by-color, fixed size, Adobe compatibility,
//! and clip-overflow. Arc/elliptical curve types and "fill gaps" are
//! intentionally absent — vtracer can't produce them (see docs/architecture.md).
//!
//! These transforms are **best-effort and coupled to vtracer's output shape**:
//! they locate `<path>`/`<svg>` substrings by scanning, which is sound for the
//! flat, well-formed SVG vtracer emits. On input they don't recognize they
//! return it unchanged rather than erroring — acceptable because the only
//! producer is the tracer in the same crate. If the SVG source ever changes,
//! revisit this (a real XML parser) instead of trusting the scan.

use super::path::{attr_str, path_elements, svg_attr_number};
use crate::options::{DrawStyle, GroupBy, StrokeStyle, SvgOptions, SvgVersion};

pub(crate) fn apply(mut svg: String, o: &SvgOptions) -> String {
    svg = restyle_paths(&svg, o);
    if o.group_by == GroupBy::Color {
        svg = group_by_color(&svg);
    }
    if o.clip_overflow {
        svg = clip_overflow(&svg);
    }
    svg = apply_version(&svg, o.version, o.adobe_compat);
    if !o.fixed_size {
        svg = make_scalable(&svg);
    }
    svg
}

/// Rewrite every `<path>`'s fill/stroke according to the draw + stroke style.
fn restyle_paths(svg: &str, o: &SvgOptions) -> String {
    let StrokeStyle {
        color,
        width,
        non_scaling,
    } = &o.stroke;
    let ve = if *non_scaling {
        " vector-effect=\"non-scaling-stroke\""
    } else {
        ""
    };

    rewrite_paths(svg, |attrs| {
        // `orig_fill` comes from the traced SVG via attr_str, which reads up to
        // the next quote — so it can never contain a `"` and is injection-safe.
        let orig_fill = attr_str(attrs, "fill").unwrap_or_else(|| "#000000".into());
        // `color` is a caller-supplied option: only accept a safe color token,
        // otherwise fall back to the (trusted) traced fill — never interpolate
        // an unvalidated string into the `stroke="…"` attribute (M1).
        let stroke_color = color
            .clone()
            .filter(|c| is_safe_color(c))
            .unwrap_or_else(|| orig_fill.clone());
        // Keep every other attribute (d, transform, opacity, …); only fill/stroke
        // are ours to set.
        let mut kept = strip_attr(attrs, "fill");
        kept = strip_attr(&kept, "stroke");
        kept = strip_attr(&kept, "stroke-width");
        kept = strip_attr(&kept, "vector-effect");
        let kept = kept.trim();
        let paint = match o.draw_style {
            DrawStyle::Fill => format!("fill=\"{orig_fill}\""),
            DrawStyle::Stroke => {
                format!("fill=\"none\" stroke=\"{stroke_color}\" stroke-width=\"{width}\"{ve}")
            }
            DrawStyle::Both => {
                format!(
                    "fill=\"{orig_fill}\" stroke=\"{stroke_color}\" stroke-width=\"{width}\"{ve}"
                )
            }
        };
        format!("{kept} {paint}")
    })
}

/// Wrap paths that share a fill into `<g fill="...">` groups, in first-seen order.
fn group_by_color(svg: &str) -> String {
    let (head, _, tail) = match split_body(svg) {
        Some(parts) => parts,
        None => return svg.to_string(),
    };

    // Preserve order of first appearance.
    let mut order: Vec<String> = Vec::new();
    let mut groups: std::collections::HashMap<String, Vec<String>> =
        std::collections::HashMap::new();
    for attrs in path_elements(svg) {
        let fill = attr_str(&attrs, "fill").unwrap_or_else(|| "none".into());
        // Push straight into the entry's Vec — no second lookup, no `.unwrap()`.
        groups
            .entry(fill.clone())
            .or_insert_with(|| {
                order.push(fill.clone());
                Vec::new()
            })
            .push(format!("<path {} />", attrs.trim()));
    }

    let mut body = String::new();
    for fill in &order {
        body.push_str(&format!("<g fill=\"{fill}\">"));
        if let Some(paths) = groups.get(fill) {
            for p in paths {
                body.push_str(p);
            }
        }
        body.push_str("</g>");
    }
    format!("{head}{body}{tail}")
}

/// Wrap all content in a clip to the canvas bounds.
fn clip_overflow(svg: &str) -> String {
    let (w, h) = (
        svg_attr_number(svg, "width"),
        svg_attr_number(svg, "height"),
    );
    let (w, h) = match (w, h) {
        (Some(w), Some(h)) => (w, h),
        _ => return svg.to_string(),
    };
    let (head, body, tail) = match split_body(svg) {
        Some(parts) => parts,
        None => return svg.to_string(),
    };
    let defs = format!(
        "<defs><clipPath id=\"alotno-clip\"><rect x=\"0\" y=\"0\" width=\"{w}\" height=\"{h}\"/></clipPath></defs>"
    );
    format!("{head}{defs}<g clip-path=\"url(#alotno-clip)\">{body}</g>{tail}")
}

/// Rewrite the opening `<svg>` tag for the chosen version / Adobe compatibility.
fn apply_version(svg: &str, version: SvgVersion, adobe: bool) -> String {
    rewrite_svg_tag(svg, |attrs| {
        let mut a = strip_attr(attrs, "version");
        a = strip_attr(&a, "xmlns");
        a = strip_attr(&a, "baseProfile");
        let (ver, profile) = match version {
            SvgVersion::V1_0 => ("1.0", ""),
            SvgVersion::V1_1 => ("1.1", ""),
            SvgVersion::Tiny1_2 => ("1.2", " baseProfile=\"tiny\""),
        };
        let adobe_ns = if adobe {
            " xmlns:i=\"http://ns.adobe.com/AdobeIllustrator/10.0/\""
        } else {
            ""
        };
        format!(
            "{} version=\"{ver}\"{profile} xmlns=\"http://www.w3.org/2000/svg\"{adobe_ns}",
            a.trim()
        )
    })
}

/// Drop explicit width/height, keeping the viewBox so the SVG scales freely.
fn make_scalable(svg: &str) -> String {
    if svg.contains("viewBox") {
        rewrite_svg_tag(svg, |attrs| {
            let a = strip_attr(&strip_attr(attrs, "width"), "height");
            a.trim().to_string()
        })
    } else {
        svg.to_string()
    }
}

/// Whether `s` is a safe color token to interpolate into an SVG attribute.
/// Accepts `#rgb`/`#rgba`/`#rrggbb`/`#rrggbbaa`, `none`, `currentColor`, and
/// plain alphabetic named colors. Anything that could break out of the
/// attribute (quotes, `<`, `>`, `rgb(…)`, etc.) is rejected.
fn is_safe_color(s: &str) -> bool {
    let s = s.trim();
    if s.eq_ignore_ascii_case("none") || s.eq_ignore_ascii_case("currentColor") {
        return true;
    }
    if let Some(hex) = s.strip_prefix('#') {
        return matches!(hex.len(), 3 | 4 | 6 | 8) && hex.bytes().all(|b| b.is_ascii_hexdigit());
    }
    // Named color: letters only, bounded length (e.g. "red", "navy").
    !s.is_empty() && s.len() <= 32 && s.bytes().all(|b| b.is_ascii_alphabetic())
}

// ---------------------------------------------------------------------------
// small string utilities
// ---------------------------------------------------------------------------

/// Apply `f` to each `<path>`'s attribute substring, rebuilding `<path .../>`.
fn rewrite_paths(svg: &str, f: impl Fn(&str) -> String) -> String {
    let mut out = String::new();
    let mut rest = svg;
    while let Some(start) = rest.find("<path") {
        out.push_str(&rest[..start]);
        let after = &rest[start + 5..];
        if let Some(end) = after.find('>') {
            let attrs = after[..end].strip_suffix('/').unwrap_or(&after[..end]);
            out.push_str(&format!("<path {} />", f(attrs).trim()));
            rest = &after[end + 1..];
        } else {
            out.push_str(&rest[start..]);
            return out;
        }
    }
    out.push_str(rest);
    out
}

/// Apply `f` to the opening `<svg ...>` tag's attribute substring.
fn rewrite_svg_tag(svg: &str, f: impl Fn(&str) -> String) -> String {
    let start = match svg.find("<svg") {
        Some(s) => s,
        None => return svg.to_string(),
    };
    let after = &svg[start + 4..];
    let end = match after.find('>') {
        Some(e) => e,
        None => return svg.to_string(),
    };
    format!(
        "{}<svg {}>{}",
        &svg[..start],
        f(&after[..end]).trim(),
        &after[end + 1..]
    )
}

/// Remove a single `name="..."` attribute (and namespaced `name:*`) from a string.
fn strip_attr(attrs: &str, name: &str) -> String {
    let mut out = String::new();
    let mut rest = attrs;
    let key = format!("{name}=\"");
    while let Some(pos) = rest.find(&key) {
        out.push_str(&rest[..pos]);
        let after = &rest[pos + key.len()..];
        if let Some(close) = after.find('"') {
            rest = &after[close + 1..];
        } else {
            return out;
        }
    }
    out.push_str(rest);
    out
}

/// Split into (everything through the opening `<svg>` tag, inner body, `</svg>…`).
fn split_body(svg: &str) -> Option<(&str, &str, &str)> {
    let open_end = svg
        .find("<svg")
        .and_then(|s| svg[s..].find('>').map(|e| s + e + 1))?;
    let close = svg.rfind("</svg")?;
    Some((&svg[..open_end], &svg[open_end..close], &svg[close..]))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::options::{DrawStyle, StrokeStyle, SvgOptions};

    #[test]
    fn safe_colors_accepted() {
        for c in [
            "#000",
            "#0f0f",
            "#abcdef",
            "#abcdef80",
            "none",
            "currentColor",
            "red",
        ] {
            assert!(is_safe_color(c), "{c} should be safe");
        }
    }

    #[test]
    fn unsafe_colors_rejected() {
        for c in [
            "#000\" onload=\"x",
            "red\"><script>",
            "url(#x)",
            "rgb(1,2,3)",
            "#xyz",
            "#12345",
        ] {
            assert!(!is_safe_color(c), "{c} should be rejected");
        }
    }

    #[test]
    fn malicious_stroke_color_does_not_inject_markup() {
        // A caller-supplied stroke color containing a quote must not break out
        // of the attribute; it falls back to the trusted traced fill instead.
        let svg = r##"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10"><path d="M0 0 L1 1" fill="#112233"/></svg>"##;
        let opts = SvgOptions {
            draw_style: DrawStyle::Stroke,
            stroke: StrokeStyle {
                color: Some("#000\" onload=\"alert(1)".into()),
                width: 1.0,
                non_scaling: false,
            },
            ..Default::default()
        };
        let out = apply(svg.to_string(), &opts);
        assert!(
            !out.contains("onload"),
            "injected attribute leaked into output"
        );
        // The fallback (trusted traced fill) is used for the stroke instead.
        assert!(out.contains("stroke=\"#112233\""));
    }
}
