//! Vector outputs. Everything derives from one trace: RGBA → SVG (styled),
//! then SVG → PDF / EPS / DXF.
pub mod dxf;
pub mod eps;
pub mod pdf;
pub mod trace;

mod path;
mod svg_postprocess;
