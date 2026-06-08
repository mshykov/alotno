//! Regression + property tests for the hand-written SVG-path parsers behind
//! `svg_to_eps` / `svg_to_dxf`.
//!
//! These parsers must be **total** — every input, including truncated or
//! malformed `d` strings, must return a value and never panic, because the core
//! is built with `panic = "abort"` and any panic aborts the whole WASM module /
//! FFI host process. The property tests below previously reproduced two
//! out-of-bounds panics (audit findings C1/C2).

use alotno_core::{svg_to_dxf, svg_to_eps};
use proptest::prelude::*;

fn svg_with_path(d: &str) -> String {
    format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><path d="{d}" fill="#000000"/></svg>"##
    )
}

// --- Regression: truncated / malformed paths must not abort (C1, C2) ---

#[test]
fn truncated_moveto_does_not_panic() {
    // A bare "M" with no operands used to index tokens[i+1] out of bounds.
    assert!(svg_to_eps(&svg_with_path("M")).is_ok());
    assert!(svg_to_dxf(&svg_with_path("M")).is_ok());
}

#[test]
fn truncated_curveto_does_not_panic() {
    // "C" needs 6 operands; supplying fewer must stop cleanly, not abort.
    assert!(svg_to_eps(&svg_with_path("M0 0 C 1 2 3")).is_ok());
    assert!(svg_to_dxf(&svg_with_path("M0 0 C 1 2 3")).is_ok());
}

#[test]
fn trailing_command_letters_do_not_panic() {
    for d in [
        "M 0 0 L 1 1 Z M",
        "L",
        "C",
        "M0 0L",
        "z",
        "M 1 1 H",
        "M 1 1 V",
    ] {
        assert!(svg_to_eps(&svg_with_path(d)).is_ok(), "eps failed on {d:?}");
        assert!(svg_to_dxf(&svg_with_path(d)).is_ok(), "dxf failed on {d:?}");
    }
}

// --- Regression: correctness of the shared parser ---

#[test]
fn implicit_repeated_lineto_is_honored() {
    // After a moveto, extra coordinate pairs are implicit linetos (H3).
    let eps = svg_to_eps(&svg_with_path("M 0 0 10 0 10 10")).unwrap();
    assert_eq!(
        eps.matches("lineto").count(),
        2,
        "expected two implicit linetos"
    );
    assert!(eps.contains("moveto"));
}

#[test]
fn h_and_v_become_lines() {
    let eps = svg_to_eps(&svg_with_path("M 0 0 H 10 V 10")).unwrap();
    assert_eq!(eps.matches("lineto").count(), 2);
}

#[test]
fn known_path_emits_expected_eps() {
    let eps = svg_to_eps(&svg_with_path("M0 0 L10 0 C10 5 5 10 0 10 Z")).unwrap();
    assert!(eps.starts_with("%!PS-Adobe-3.0 EPSF-3.0"));
    assert!(eps.contains("%%BoundingBox: 0 0 100 100"));
    assert!(eps.contains("moveto"));
    assert!(eps.contains("lineto"));
    assert!(eps.contains("curveto"));
    assert!(eps.contains("closepath"));
}

#[test]
fn known_path_emits_dxf_polyline() {
    let dxf = svg_to_dxf(&svg_with_path("M0 0 L10 0 L10 10 Z")).unwrap();
    assert!(dxf.contains("LWPOLYLINE"));
    assert!(dxf.contains("ENDSEC"));
}

#[test]
fn fill_none_path_is_skipped_in_eps() {
    let svg = r#"<svg width="10" height="10"><path d="M0 0 L5 5" fill="none"/></svg>"#;
    let eps = svg_to_eps(svg).unwrap();
    // No paint requested → no fill/stroke operator emitted.
    assert!(!eps.contains("fill"));
    assert!(!eps.contains("stroke\n"));
}

// --- Property tests: no input may panic ---

proptest! {
    #![proptest_config(ProptestConfig::with_cases(2000))]

    // Random tokens drawn from the SVG path alphabet plus junk.
    #[test]
    fn eps_never_panics(d in r"[MmLlHhVvCcSsQqTtAaZz0-9 .,+\-eE]{0,80}") {
        let _ = svg_to_eps(&svg_with_path(&d));
    }

    #[test]
    fn dxf_never_panics(d in r"[MmLlHhVvCcSsQqTtAaZz0-9 .,+\-eE]{0,80}") {
        let _ = svg_to_dxf(&svg_with_path(&d));
    }

    // Fully arbitrary bytes inside the d attribute must also be safe.
    #[test]
    fn arbitrary_d_never_panics(d in r".{0,60}") {
        let _ = svg_to_eps(&svg_with_path(&d));
        let _ = svg_to_dxf(&svg_with_path(&d));
    }
}
