## 0.3.2

- **Added Warnings and Info tabs** — filter bar now features 5 tabs: All, Network, Errors, Warnings, and Info.
- **Added "Copied" toast** — visual confirmation appears when copying logs, requests, or specific HTTP card sections.

## 0.3.1

- Removed **Server** filter — server errors already appear in both Errors and Network tabs.
- Simplified to **3 tabs**: All, Network, Errors.

## 0.3.0

- **Simplified filter categories** — reduced to 4 clear filters: All, Network, Errors, Server.
  - Removed Auth filter.
  - **Network** now shows all HTTP requests (GET, POST, PUT, DELETE, etc.).
  - Network tab is now the second tab after All.
- **Detailed HTTP cards** — each request card now shows full details when expanded:
  - Method, Full URL, Status, Request Headers, Request Body, Response Headers, Response Body.
  - **Each section has its own copy button** for individual copying.
- **Interceptor captures more data** — now logs request headers, response headers, and full URL.

## 0.2.0

- **Redesigned filter categories** — replaced 10 scrollable chips with 6 unified, non-scrolling categories:
  - **All** — show everything
  - **Errors** — all error + fatal level logs
  - **Requests** — all HTTP traffic
  - **Server** — server layer issues (5xx, database, backend)
  - **Network** — network layer issues (timeout, DNS, socket)
  - **Auth** — auth layer issues (401/403, token, permissions)
- All filters now fit on screen without scrolling.
- Removed confusing separation between "log levels" and "issue layers".

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
