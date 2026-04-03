## 0.1.2

- **Request body** now displayed in HTTP cards (tap to expand shows both Request Body and Response Body).
- Request body is captured from `RequestOptions.data` and passed through to response/error log entries.

## 0.1.1

- Added screenshots to README and pub.dev listing.
- Added `screenshots` section to `pubspec.yaml`.

## 0.1.0

- Initial release of `logscope_flutter`.
- **Logscope** — one-stop facade with 2-line integration (`Logscope.init()` + `Logscope.wrap(child)`).
- **LayerClassifier** — automatic issue-layer classification (SERVER / NETWORK / MOBILE / AUTH) based on HTTP status codes, Dio error types, and message pattern matching.
- **DebugLogStore** — singleton ring-buffer (`LogRingBuffer`) with broadcast stream, filter, and export helpers.
- **AppLogger** — static logging methods (`debug`, `info`, `warning`, `error`, `network`, `security`, `navigation`, `bloc`) with automatic `debugPrint` in debug mode.
- **DebugLogInterceptor** — Dio `Interceptor` that captures sanitized HTTP request/response data with structured metadata.
- **LogsFab** — draggable floating action button with fullscreen in-app log console, layer badges, structured HTTP cards, error toasts, share/copy/clear.
- **DeviceContext** — app and device metadata attached to exported log reports.
- Custom classification rules via `Logscope.classifier.addRule(...)`.
