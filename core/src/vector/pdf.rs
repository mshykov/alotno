//! SVG → PDF (vector), via `svg2pdf` (Typst team). Pure Rust, WASM-friendly.
//!
//! Alotno's SVGs come from the tracer and are path-only (no text), so font
//! handling is a non-issue and an empty font database is fine.
//!
//! NOTE: `svg2pdf` / `usvg` APIs move between versions. Written against
//! svg2pdf 0.12 / usvg 0.44 — verify on first `cargo build`.

use crate::options::ConvertError;
// Use svg2pdf's own re-exported usvg so the Tree type matches its API exactly
// (avoids a usvg version clash in the dependency graph).
use svg2pdf::usvg;

pub(crate) fn from_svg(svg: &str) -> Result<Vec<u8>, ConvertError> {
    let options = usvg::Options::default();
    let tree = usvg::Tree::from_str(svg, &options)
        .map_err(|e| ConvertError::Encode(format!("parse svg: {e}")))?;

    svg2pdf::to_pdf(
        &tree,
        svg2pdf::ConversionOptions::default(),
        svg2pdf::PageOptions::default(),
    )
    .map_err(|e| ConvertError::Encode(format!("svg2pdf: {e}")))
}
