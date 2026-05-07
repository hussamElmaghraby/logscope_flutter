# logscope_flutter

[![pub package](https://img.shields.io/pub/v/logscope_flutter.svg)](https://pub.dev/packages/logscope_flutter)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)

**In-app debug console with automatic issue-layer classification for Flutter.**

Logscope helps testers and developers instantly identify _where_ a problem originates — **Server**, **Network**, **Mobile**, or **Auth** — without reading raw logs. Drop it into any Flutter app with just 2 lines of code.

---

## 📸 Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/hussamElmaghraby/logscope_flutter/main/screenshots/fab_overlay.png" width="230" alt="Debug FAB & Error Toast" />
  &nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/hussamElmaghraby/logscope_flutter/main/screenshots/log_console.png" width="230" alt="Log Console" />
  &nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/hussamElmaghraby/logscope_flutter/main/screenshots/device_info_tab.png" width="230" alt="Device Info Tab" />
  &nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/hussamElmaghraby/logscope_flutter/main/screenshots/http_cards.png" width="230" alt="HTTP Structured Cards" />
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/hussamElmaghraby/logscope_flutter/main/screenshots/layer_classification.png" width="600" alt="Layer Classification System" />
</p>

|  |  |  |  |
|:---:|:---:|:---:|:---:|
| **Draggable FAB** | **Log Console** | **Device Info** | **HTTP Cards** |

---

## ✨ Features

| Feature | Description |
|---|---|
| 📱 **Device Info Tab** | Real-time console tab showing app info, device specs, platform OS, and live session duration/time. |
| 🏷️ **Layer classification** | Every log is auto-tagged as `SERVER`, `NETWORK`, `MOBILE`, or `AUTH` based on HTTP status codes, exception patterns, and custom rules. |
| 🔄 **Ring-buffer store** | Fixed-size circular buffer (`LogRingBuffer`) — memory-safe, O(1) insert, oldest entries evicted first. |
| 🌐 **Dio interceptor** | One-line setup captures all HTTP traffic with structured request/response cards. |
| 🎯 **Draggable FAB overlay** | Floating debug button with fullscreen log console — filter, search, share, copy, clear. |
| 🔴 **Error toasts** | Brief overlay notification when an error is captured. |
| 🛡️ **Flutter error capture** | Hooks into `FlutterError.onError` and `PlatformDispatcher.onError` to catch unhandled exceptions. |
| 📤 **Export & share** | Export logs as plain text with device context headers — share via the system share sheet. |
| 🏗️ **Custom rules** | Register your own classification rules for domain-specific patterns (Firebase, GraphQL, Stripe, etc.). |

---

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  logscope_flutter: ^0.4.0
```

Then run:

```bash
flutter pub get
```

---

## 🚀 Quick Start

### Zero-config setup (2 lines)

```dart
import 'package:logscope_flutter/logscope_flutter.dart';

void main() {
  Logscope.init(); // ← Auto-detects app info, device, OS, and environment!
  runApp(Logscope.wrap(const MyApp()));
}
```

### Capture HTTP traffic (Dio)

```dart
final dio = Dio();
dio.interceptors.add(Logscope.dioInterceptor());
```

### Log from anywhere

```dart
Logscope.d('Loaded 42 items', tag: 'Repo');
Logscope.i('Cache hit', tag: 'Cache');
Logscope.w('Deprecated API', tag: 'API');
Logscope.e('Save failed', tag: 'DB', error: e, stackTrace: s);
Logscope.http('GET /users → 200');
Logscope.nav('Pushed /settings');
Logscope.bloc('CounterState(42)');
```

---

## 🔧 Configuration

```dart
Logscope.init(
  enabled: true,                    // master switch (defaults to true)
  captureFlutterErrors: true,       // hook FlutterError + PlatformDispatcher
  showErrorToasts: true,            // overlay notification on errors
  bufferSize: 1000,                 // max entries in ring buffer

  // OVERRIDES (Auto-detected by default)
  // appName: 'MyApp',              // Normally fetched via package_info_plus
  // appVersion: '2.3.1',
  // environment: 'Staging',        // Normally inferred from Build Mode
);
```

---

## 🏷️ Layer Classification

Logs are automatically classified into issue layers:

| Layer | Badge | Triggers |
|---|---|---|
| **Server** | 🟥 `SERVER` | HTTP 5xx, database errors, backend/upstream issues |
| **Network** | 🟧 `NETWORK` | Timeouts, socket errors, DNS failures, no connectivity |
| **Mobile** | 🟦 `MOBILE` | Null errors, type cast, format exceptions, widget overflow |
| **Auth** | 🟨 `AUTH` | HTTP 401/403, token expired, permission denied |

### Custom rules

```dart
Logscope.classifier.addRule(({
  required message, required levelName, tag, metadata,
}) {
  if (message.contains('Firestore')) return IssueLayer.server;
  return null; // let built-in rules decide
});
```

---

## 📊 API Reference

### Logscope (facade)

| Method | Description |
|---|---|
| `Logscope.init(...)` | Initialize the debug console (call once in `main()`) |
| `Logscope.wrap(child)` | Wrap root widget to add the debug FAB |
| `Logscope.dioInterceptor()` | Returns a Dio interceptor for HTTP logging |
| `Logscope.d/i/w/e(...)` | Debug / Info / Warning / Error log shortcuts |
| `Logscope.http(...)` | Log HTTP/network messages |
| `Logscope.nav(...)` | Log navigation events |
| `Logscope.bloc(...)` | Log BLoC/state events |
| `Logscope.store` | Access the `DebugLogStore` singleton |
| `Logscope.classifier` | Access the `LayerClassifier` for custom rules |
| `Logscope.setDeviceContext(...)` | Update device/app info for exports |

### AppLogger (lower-level)

| Method | Description |
|---|---|
| `AppLogger.debug/info/warning/error(...)` | Full-name logging methods |
| `AppLogger.network/security/navigation/bloc(...)` | Domain-specific logging |
| `AppLogger.redact(value)` | Mask sensitive data for safe logging |

---

## 🤝 Contributing

Contributions are welcome! Please open an issue or submit a pull request on [GitHub](https://github.com/hussamElmaghraby/logscope_flutter).

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
