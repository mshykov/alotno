# `apps/app` — the cross-platform Flutter app

One Dart codebase → macOS, Windows, Linux, iOS, Android. Calls the Rust core
(`alotno-core`) through an FFI bridge, and styles itself from the generated
design tokens so it matches the web app.

Scaffolded and bridged. macOS builds and runs today (ad-hoc, no Apple account).

## Layout

- `lib/` — the Flutter UI.
- `rust/` — **`rust_lib_alotno`**, the FFI bridge crate (its own Cargo workspace).
  Depends on `alotno-core` and exposes the conversion API in
  [`rust/src/api/simple.rs`](rust/src/api/simple.rs). `flutter_rust_bridge`
  requires this crate to live inside the app; cargokit builds it per target.
- `lib/src/rust/` — generated Dart bindings (do not edit by hand).
- `rust_builder/` — cargokit (compiles `rust/` during `flutter build`).

## Run / build

```sh
cd apps/app
flutter run   -d macos        # dev (hot reload)
flutter build macos --debug   # → build/macos/Build/Products/Debug/alotno.app
```

(First build needs `~/.netrc` at mode `600` or CocoaPods errors: `chmod 600 ~/.netrc`.)

## Regenerate the bridge (after editing `rust/src/api/`)

```sh
flutter_rust_bridge_codegen generate   # reads flutter_rust_bridge.yaml
```

Calling it from Dart:

```dart
import 'src/rust/api/simple.dart';
final svg = await tracePngToSvg(pngBytes: bytes, options: TraceOptions(preset: "high"));
```

## Design tokens

```sh
pnpm --filter @alotno/design build
cp design/dist/tokens.dart apps/app/lib/design/tokens.dart
```

Use `Tokens.colorBrand500`, `Tokens.space4`, etc. — never hardcode values.

## Release notes

- **macOS:** sign with a **Developer ID Application** cert under the **personal**
  team (`64HRGLZCS4`) + notarize (`APPLE_ID` = personal gmail). Pin
  `DEVELOPMENT_TEAM=64HRGLZCS4`; never the work team. Flutter builds the `.app`;
  `codesign`/`notarytool` do the rest (flow mirrors `legacy/electron-mac/RELEASE.md`).
- **iOS/Android:** standard store signing when Phase 3 arrives.
