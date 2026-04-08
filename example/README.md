# Logscope Flutter — Example App

A fully interactive demo that showcases every feature of the `logscope_flutter` package.

## Getting Started

```bash
cd example
flutter pub get
flutter run
```

## Features Demonstrated

| Feature | What It Shows |
|---|---|
| **Basic Logging** | `Logscope.d()`, `.i()`, `.w()`, `.e()` — all severity levels |
| **Domain Logging** | `.nav()` for navigation, `.bloc()` for state, `AppLogger.security()` for auth |
| **HTTP Traffic** | Real Dio requests captured as structured cards (GET, POST, 500, 401, timeout, DNS failure) |
| **Layer Classification** | Auto-tagged `SERVER`, `NETWORK`, `MOBILE`, `AUTH` badges on logs |
| **Custom Rules** | Domain-specific classifiers (Firebase → SERVER, Stripe → SERVER) |
| **Bulk Logging** | 50-log burst to test ring buffer performance |
| **Flutter Error Capture** | Unhandled exceptions caught by `FlutterError.onError` hook |
| **Data Redaction** | `AppLogger.redact()` masks tokens, emails, card numbers |

## How to Use

1. **Tap any card** to generate logs of that type
2. **Tap the floating bug button** (🐛) to open the debug console
3. **Filter** by log level or issue layer
4. **Search** through logs with the search bar
5. **Share** or export logs via the share button
