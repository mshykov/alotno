> Baseline: `MSH/docs/security.md` (org common rules). Below: Alotno-specific rules.

# Security (Alotno)

- `core` is **panic-free by contract**: every public entry point returns
  `Result` and must never panic on any input. Release builds use
  `panic = "abort"`, so a panic poisons the WASM module / aborts the FFI host.
- No `unwrap`/`expect`/unchecked indexing on input-derived data. Validate
  caller-supplied strings before writing them to output.
- Decode dimensions are capped before allocation (`decode::MAX_*`); the
  hand-written parsers are total.
