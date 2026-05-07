## 0.4.1

- **Updated Description** — improved `pubspec.yaml` description to better reflect zero-config initialization and the new Device Info tab.
- **Refreshed Screenshots** — captured new screenshots for the pub.dev documentation to accurately reflect the muted/glassmorphic UI redesign implemented in v0.4.0.

## 0.4.0

- **New Device Info Tab** — added a dedicated tab in the log console to view app, device, platform, and session information (with live duration/date/time).
- **Zero-Config Initialization** — `Logscope.init()` now automatically detects your app name, app version, build number, package name (via `package_info_plus`), and environment (via build mode). No manual parameters needed!
- **UI Refresh** — updated the log console with a muted, calm, and modern color palette for improved readability.

## 0.3.9

- **Shortened package description** — fits within pub.dev's 60–180 character guideline for search-engine-friendly display.
- **Upgraded `share_plus`** — bumped from `^11.0.0` to `^13.0.0` to satisfy pub.dev's up-to-date dependency requirements.

## 0.3.8

- **Fixed search bar crash** — reverted from `TextField` to `EditableText` to avoid `Material`, `MaterialLocalizations`, and `Overlay` ancestor requirements (the overlay sits outside `MaterialApp`).
- **Fixed "Copied" toast** — replaced `Overlay`-dependent toast with a self-contained `Stack`-based toast that works without a `Scaffold` or `Overlay` ancestor.
- **Added search hint text** — shows "Search logs..." placeholder via `ValueListenableBuilder`.
- **Added example app** — full working example demonstrating all Logscope features.

## 0.3.7

- **Release-mode support** — Logscope now works in all build modes (debug, profile, and release). The FAB overlay, log capture, and interceptor are no longer restricted to debug-only. Pass `enabled: false` to `Logscope.init()` to disable in production if needed.

## 0.3.6

- **Updated README** — corrected the installation version from `^0.1.0` to `^0.3.5` to reflect the current release.

## 0.3.5

- **Removed body size limits** — full HTTP request and response bodies are now always shown, eliminating the `skipped, exceeds limit` truncation behavior.

## 0.3.4

- **Fixed search bar input** — resolved an issue where text entered into the log search bar would immediately clear during state rebuilds.

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
