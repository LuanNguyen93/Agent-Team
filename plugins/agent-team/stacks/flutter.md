# Stack profile: Flutter

Applies when: `pubspec.yaml` containing a `flutter:` dependency. Pure Dart
projects use the same profile with `dart` in place of `flutter`.

## Gates

| Gate | Typical command | Notes |
|---|---|---|
| format | `dart format --set-exit-if-changed .` | fails on diff, does not rewrite |
| analyze | `flutter analyze` | this is the typecheck **and** the lint |
| test | `flutter test` | widget and unit tests |
| build | `flutter build apk --debug` | slow; opt-in |

`flutter analyze` reads `analysis_options.yaml`. If the project includes
`package:flutter_lints` or `very_good_analysis`, the gate is already strict —
do not add a second linter.

Integration tests (`integration_test/`) run through `flutter test
integration_test` or `flutter drive`, need a device or emulator, and are **not**
part of the blocking chain. They belong to verification — see `app-verify`.

## Conventions to detect and follow

- **State management**: Riverpod, Bloc, Provider, GetX, or `setState`. Read
  which one before writing a widget; introducing a second is a real cost.
- **Navigation**: `go_router`, `auto_route`, or plain `Navigator`. Route
  definitions are the app's URL contract.
- **Code generation**: `build_runner` with freezed / json_serializable. Never
  edit a `*.g.dart` or `*.freezed.dart` by hand — regenerate.
- **Folder layout**: feature-first (`lib/features/<name>/`) or layer-first
  (`lib/models`, `lib/services`). Follow the existing one.
- **Test location**: `test/` mirroring `lib/`, `integration_test/` separately.

## Skills that apply

- `design-intelligence` — tokens, hierarchy, spacing scale, measured contrast.
  Applies to `ThemeData` and `ColorScheme` exactly as it does to CSS.
- `app-verify` — driving the real app, in place of `browser-verify`, which
  assumes a browser and a dev server
- `architecture-discipline` — Preset B maps cleanly: `models → repositories →
  services → widgets`, with no business logic in a widget

## Things to check in review on this stack

- **`BuildContext` used after an `await`.** The widget may be gone. Guard with
  `if (!context.mounted) return;` — this is the single most common real defect
  in Flutter code.
- **A missing `dispose()`** for a controller, `StreamSubscription`,
  `AnimationController`, or `FocusNode`. Every one of these is a leak.
- **Work inside `build()`** — network calls, heavy computation, or creating a
  controller. `build` runs often and at times you do not choose.
- **`setState` after an async gap without a `mounted` check**, or `setState`
  called from outside the widget's own state.
- **Missing `const` constructors.** Not cosmetic: `const` widgets are skipped
  on rebuild, so this is the cheapest performance in the framework.
- **`ListView` with a fixed `children:` for a list that can grow** — use
  `ListView.builder`, or the whole list is built at once.
- **Layout that only works at one size.** Check a narrow phone, a tablet, and a
  large text scale factor. `MediaQuery.textScalerOf` breaks fixed-height rows.
- **Hardcoded colours and spacing** instead of `Theme.of(context)` and the
  spacing scale — the Flutter form of the design-token rule.
- **Missing loading / empty / error states** on anything driven by a `Future` or
  `Stream`. `AsyncValue`, `FutureBuilder`, and `StreamBuilder` all force the
  three cases; a `.data!` skips them.
- **Secrets in the app bundle.** Everything shipped to a device is readable.
  API keys belong on a server, not behind an obfuscation flag.
