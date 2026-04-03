# `logscope_flutter` — handoff notes

> **Renamed:** This package was previously `debug_console_logger`. It has been
> renamed to `logscope_flutter` for pub.dev publishing.

This file is for humans and agents continuing work on this package (e.g. pub.dev publishing, refactors).

## What this package is

Flutter-focused debug logging with **automatic issue-layer classification** for testers:

- **`Logscope`** — one-stop facade: `Logscope.init()` + `Logscope.wrap(child)` for 2-line integration.
- **`LayerClassifier`** — auto-classifies logs as SERVER / NETWORK / MOBILE / AUTH based on HTTP status codes, exception patterns, and custom rules.
- **`DebugLogStore`** — singleton ring buffer (`LogRingBuffer`) of `LogEntry`, broadcast stream `onNewLog`, filter/export helpers with `DeviceContext` report headers.
- **`AppLogger`** — static methods (`debug`, `info`, `warning`, `error`, `network`, `security`, `navigation`, `bloc`, …) that print via `debugPrint` in `kDebugMode` and append to `DebugLogStore`.
- **`DebugLogInterceptor`** — Dio `Interceptor` writing sanitized HTTP logs with structured metadata into `DebugLogStore`.
- **`LogsFab`** — draggable debug FAB + fullscreen in-app log console with layer badges, structured HTTP cards, error toasts, share/copy/clear.

Public API entry: `package:logscope_flutter/logscope_flutter.dart`.

## Quick integration

```dart
// main.dart — 2 lines
void main() {
  Logscope.init(appName: 'MyApp', appVersion: '1.0.0');
  runApp(Logscope.wrap(MyApp()));
}

// Dio — 1 line
dio.interceptors.add(Logscope.dioInterceptor());

// Log from anywhere
Logscope.d('Loaded items', tag: 'Repo');
Logscope.e('Save failed', error: e, stackTrace: s);
```

## Already done (SwissFiat monorepo)

1. **Package** at `packages/logscope_flutter/`.
2. **`core`** depends on `logscope_flutter` via path `../logscope_flutter` and **re-exports** the package from `packages/core/lib/core.dart`, so code that only imports `package:core/core.dart` still sees all public APIs.
3. **`sentry_bloc_observer`** imports `package:logscope_flutter/logscope_flutter.dart` directly.
4. **`LogsFab` decoupled from `AppConfig`**: `lib/app/app.dart` passes `enabled: AppConfig.showDebugFab`.
5. **Removed** from `core`: `lib/src/utils/app_logger.dart`, `lib/src/services/console_loggers/*`.
6. **`data`** unchanged: still uses `DebugLogInterceptor` through `package:core/core.dart`.

## Monorepo migration checklist

After renaming the package, update these files in the monorepo:

- [ ] Rename folder `packages/debug_console_logger/` → `packages/logscope_flutter/`
- [ ] `packages/core/pubspec.yaml` — dependency name `debug_console_logger` → `logscope_flutter`, path `../debug_console_logger` → `../logscope_flutter`
- [ ] `packages/core/lib/core.dart` — `export 'package:debug_console_logger/debug_console_logger.dart'` → `export 'package:logscope_flutter/logscope_flutter.dart'`
- [ ] `packages/sentry_bloc_observer/pubspec.yaml` — dependency name + path
- [ ] `packages/sentry_bloc_observer/lib/...` — any direct imports of the old package
- [ ] Run `fvm flutter pub get` in all affected packages
- [ ] Run `fvm dart analyze` from the repo root

## Integration cheat sheet

| Consumer              | How it gets the API                                      |
|-----------------------|----------------------------------------------------------|
| App / most packages   | `import 'package:core/core.dart';` (re-export)           |
| Direct (optional)     | `import 'package:logscope_flutter/logscope_flutter.dart';`|

## Pub.dev — not done yet

`pubspec.yaml` has `publish_to: none` for the monorepo.

Before publishing:

- Remove or override `publish_to`.
- Add **`LICENSE`**, **`repository`** (and ideally **`homepage`** / **`issue_tracker`**).
- Run `dart pub publish --dry-run` from `packages/logscope_flutter`.
- Consider a stable **version** and **changelog** (`CHANGELOG.md`) per semver.

## Related paths

- Package: `packages/logscope_flutter/`
- Core re-export: `packages/core/lib/core.dart` (`export 'package:logscope_flutter/logscope_flutter.dart';`)
- FAB + config: `lib/app/app.dart`
- Dio interceptor registration: `packages/data/lib/src/providers/api_provider_core.dart`
