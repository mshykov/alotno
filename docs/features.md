# Conversion features & settings

Alotno's settings are modeled on a full-featured vectorizer panel. Some of that
panel is the reference tool's proprietary engine, which our engine (`vtracer`)
can't reproduce. Rather than ship dead checkboxes, we implement what's real and
**omit** what isn't. This page is the honest map.

All options live in [`core/src/options.rs`](../core/src/options.rs) as
`SvgOptions`; post-processing is in
[`core/src/vector/svg_postprocess.rs`](../core/src/vector/svg_postprocess.rs).

## Supported

| Setting | Values | Where |
|---|---|---|
| **File Format** | SVG, PDF, EPS, DXF (lines-only), WebP | `vector/*`, `raster/webp.rs` |
| **SVG Version** | 1.0, 1.1, Tiny 1.2 | post-process |
| **SVG Options** | Fixed Size, Adobe Compatibility Mode | post-process |
| **Draw Style** | Fill, Stroke, Fill + Stroke | post-process |
| **Shape Stacking** | Cutouts, Stacked | vtracer `Hierarchical` |
| **Group By** | None, Color | post-process |
| **Line Fit Tolerance** | Coarse, Medium, Fine, Super Fine | vtracer presets |
| **Allowed Curve Types** | Lines, Cubic Bézier | vtracer `Polygon`/`Spline` |
| **Color Mode** | Mono (B/W), Posterized | vtracer |
| **Stroke Style** | Override color, width, Non-Scaling Stroke | post-process |
| **Gap Filler** | Clip Overflow, Non-Scaling Stroke | post-process |

## Intentionally NOT supported (and why)

| Setting | Why omitted |
|---|---|
| **Curve types: Quadratic Bézier** | vtracer emits cubic only; a cubic→quad down-convert is lossy and pointless |
| **Curve types: Circular / Elliptical Arcs** | vtracer never emits arcs — needs an arc-fitting stage we don't have |
| **DXF: Lines & Arcs / Lines, Arcs & Splines** | same arc-fitting gap; only lines-only DXF is honest today |
| **Gap Filler: Fill Gaps** | requires shape-dilation geometry; vtracer has no equivalent |
| **Group By: Parent / Layer** | needs shape containment hierarchy we don't compute |
| **Draw Style: Stroke shared edges once** | needs shared-edge dedup geometry |

These all trace back to two missing capabilities: **arc fitting** and
**polygon offset/dedup geometry**. If we ever build those (a real geometry
research effort), the omitted settings light up — see the roadmap. Until then,
they don't appear in the UI at all.
