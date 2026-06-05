# `alotno-ffi`

Native binding that exposes the Rust core to the Flutter app via
[`flutter_rust_bridge`](https://cjycode.com/flutter_rust_bridge/).

The API Flutter calls is defined in [`src/api.rs`](src/api.rs):
`trace_png_to_svg(...)` and `convert_png_to_webp(...)`.

## One-time setup

```sh
cargo install flutter_rust_bridge_codegen
```

## Generate the Dart <-> Rust bridge

```sh
# from repo root, after the Flutter app exists (apps/app)
flutter_rust_bridge_codegen generate \
  --rust-input bindings/ffi/src/api.rs \
  --dart-output apps/app/lib/src/rust
```

This generates Dart in `apps/app/lib/src/rust/` and `src/frb_generated.rs` here
(then uncomment the `mod frb_generated;` line in `src/lib.rs`).

The `flutter_rust_bridge` plugin builds this crate automatically for each target
(macOS/Windows/Linux/iOS/Android) during `flutter run` / `flutter build`.

## Why a separate crate from `alotno-wasm`?

Native targets enable the core's `webp` feature (real libwebp encoding); the WASM
binding deliberately does not (the browser encodes WebP via canvas). Same engine,
two thin edges.
