> Baseline: `MSH/docs/testing.md` (org common rules). Below: Alotno-specific rules.

# Testing (Alotno)

## Rust core (`core/`)

- **Panic-freedom is property-tested.** The hand-written path/SVG parsers are
  fuzzed (`core/tests/path_parsers.rs`) so any input — truncated, malformed,
  adversarial — yields a command list and never panics. This is load-bearing:
  release builds are `panic = "abort"`, so a panic aborts the WASM module / FFI
  host.
- **End-to-end conversions** are covered in `core/tests/conversions.rs` (every
  output format — SVG/PDF/EPS/DXF/WebP — plus the WebP lossless/lossy/grayscale
  variants and the SVG post-process options).
- **Options surface** (`core/tests/options.rs`, `trace_options.rs`): the `parse`
  helpers every binding relies on, defaults, and the shared `OptionsDto` mapping.
- Run: `cargo test --workspace --all-features`. Manual smoke:
  `cargo run --example trace`.

## Flutter app (`apps/app/`)

- Widget tests cover the extracted converter parts, the desktop sidebar +
  settings sheet, and the mobile intake/queue (`apps/app/test/`). The full
  `MacosWindow` screen needs a native window, so tests target the leaf widgets —
  a deliberate payoff of the widget extraction.
- Headless-test gotcha: async `dart:io` never completes inside the widget-test
  fake-async zone — use sync setup or `tester.runAsync` for real file I/O.
- Run: `flutter analyze` (strict) + `flutter test`.

## Coverage & quality gate

- CI feeds **both** Dart (`flutter test --coverage`) and Rust
  (`cargo llvm-cov --workspace`) lcov into SonarCloud. Overall coverage is
  tracked on the README badge.
- Surfaces that only run inside a real platform process (bindings, the FFI
  crate, the app entrypoint, `converter_screen.dart`) are coverage-excluded in
  `sonar-project.properties` — measured code reflects what tests can reach.
- The Sonar quality gate runs on every PR (CI-based scan; not a required merge
  check). Keep it green.
