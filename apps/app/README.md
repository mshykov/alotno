# `apps/app` — the cross-platform Flutter app

One Dart codebase → macOS, Windows, Linux, iOS, Android. Calls the Rust core
through the FFI bridge, and styles itself from the generated design tokens, so it
matches the web app pixel-for-pixel.

> Not scaffolded yet — the Flutter SDK isn't installed. Follow the steps below
> once it is. This folder currently holds only this guide.

## Scaffold (Phase 2)

```sh
# from repo root
flutter create --org app.alotno --project-name alotno \
  --platforms=macos,windows,linux,ios,android apps/app
```

## Wire the Rust core (flutter_rust_bridge)

```sh
cargo install flutter_rust_bridge_codegen   # once
flutter_rust_bridge_codegen generate \
  --rust-input bindings/ffi/src/api.rs \
  --dart-output apps/app/lib/src/rust
```

Then in Dart:

```dart
import 'src/rust/api.dart';
final svg = await tracePngToSvg(pngBytes: bytes, options: TraceOptions(preset: "high"));
```

## Wire the design tokens

```sh
pnpm --filter @alotno/design build
cp design/dist/tokens.dart apps/app/lib/design/tokens.dart
```

Use `Tokens.colorBrand500`, `Tokens.space4`, etc. — never hardcode values.
(Optionally add this `cp` to a pre-build hook so it can't go stale.)

## Release notes

- **macOS:** sign with a Developer ID Application cert + notarize (the flow from
  `legacy/electron-mac/RELEASE.md` still applies; Flutter builds the `.app`,
  `codesign`/`notarytool` do the rest).
- **iOS/Android:** standard store signing when Phase 3 arrives.
