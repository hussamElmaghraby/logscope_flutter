import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'debug_log_interceptor.dart';
import 'debug_log_store.dart';
import 'layer_classifier.dart';
import 'logs_fab.dart';

/// One-stop entry point for the debug console.
///
/// Designed for **minimal integration effort** — most apps need just two lines:
///
/// ```dart
/// void main() {
///   Logscope.init();            // ← sets up error capture & device info
///   runApp(Logscope.wrap(MyApp()));  // ← adds the draggable FAB
/// }
/// ```
///
/// To log from anywhere in the app:
///
/// ```dart
/// Logscope.d('Loaded 42 items', tag: 'Repository');
/// Logscope.e('Failed to save', error: e, stackTrace: s);
/// ```
///
/// To capture HTTP traffic (Dio):
///
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(Logscope.dioInterceptor());
/// ```
class Logscope {
  Logscope._();

  static bool _initialized = false;

  // ──────────────────────── Setup ────────────────────────

  /// Initialize the debug console.
  ///
  /// Call this **once** in `main()` before `runApp()`.
  ///
  /// - [enabled] — master switch; when `false`, no logs are captured and
  ///   [wrap] returns the child as-is. Defaults to `kDebugMode`.
  /// - [captureFlutterErrors] — hook into `FlutterError.onError` and
  ///   `PlatformDispatcher.instance.onError` to capture unhandled exceptions.
  /// - [showErrorToasts] — show a brief overlay notification on errors.
  /// - [appName], [appVersion], [buildNumber] — included in exported log reports.
  /// - [deviceModel], [osVersion] — included in exported log reports.
  ///   Pass these values if you already have them (e.g. from `device_info_plus`).
  /// - [bufferSize] — max number of log entries in the ring buffer (default: 1000).
  static void init({
    bool? enabled,
    bool captureFlutterErrors = true,
    bool showErrorToasts = true,
    String? appName,
    String? appVersion,
    String? buildNumber,
    String? deviceModel,
    String? osVersion,
    int bufferSize = 1000,
  }) {
    if (_initialized) return;
    _initialized = true;

    _enabled = enabled ?? kDebugMode;
    _captureFlutterErrors = captureFlutterErrors;
    _showErrorToasts = showErrorToasts;

    if (!_enabled) return;

    // Set device context if any info was provided
    if (appName != null ||
        appVersion != null ||
        deviceModel != null ||
        osVersion != null) {
      DebugLogStore.instance.setDeviceContext(
        DeviceContext(
          appName: appName,
          appVersion: appVersion,
          buildNumber: buildNumber,
          deviceModel: deviceModel,
          osVersion: osVersion,
        ),
      );
    }
  }

  static bool _enabled = kDebugMode;
  static bool _captureFlutterErrors = true;
  static bool _showErrorToasts = true;

  /// Whether the debug console is enabled.
  static bool get isEnabled => _enabled;

  // ──────────────────────── Widget wrapping ────────────────────────

  /// Wrap your root widget to add the draggable debug FAB.
  ///
  /// ```dart
  /// runApp(Logscope.wrap(MyApp()));
  /// ```
  ///
  /// Returns [child] unchanged if [init] was called with `enabled: false`
  /// or if the app is running in release mode and no explicit `enabled`
  /// was passed.
  static Widget wrap(Widget child) {
    if (!_enabled) return child;

    return LogsFab(
      enabled: true,
      showErrorToasts: _showErrorToasts,
      captureFlutterErrors: _captureFlutterErrors,
      child: child,
    );
  }

  // ──────────────────────── Dio ────────────────────────

  /// Returns a Dio interceptor that captures all HTTP traffic.
  ///
  /// ```dart
  /// dio.interceptors.add(Logscope.dioInterceptor());
  /// ```
  static DebugLogInterceptor dioInterceptor() => DebugLogInterceptor();

  // ──────────────────────── Logging shortcuts ────────────────────────

  /// Log a debug message.
  static void d(String message, {String? tag}) {
    if (!_enabled) return;
    if (kDebugMode) debugPrint('${tag != null ? '[$tag] ' : ''}$message');
    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.debug,
        message: message,
        tag: tag,
      ),
    );
  }

  /// Log an info message.
  static void i(String message, {String? tag}) {
    if (!_enabled) return;
    if (kDebugMode) {
      debugPrint('[INFO] ${tag != null ? '[$tag] ' : ''}$message');
    }
    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: message,
        tag: tag,
      ),
    );
  }

  /// Log a warning message.
  static void w(String message, {String? tag}) {
    if (!_enabled) return;
    if (kDebugMode) {
      debugPrint('[WARN] ${tag != null ? '[$tag] ' : ''}$message');
    }
    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.warning,
        message: message,
        tag: tag,
      ),
    );
  }

  /// Log an error message.
  static void e(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    if (!_enabled) return;
    if (kDebugMode) {
      debugPrint('[ERROR] ${tag != null ? '[$tag] ' : ''}$message');
      if (error != null) debugPrint('   Error: $error');
      if (stackTrace != null) debugPrint('   Stack: $stackTrace');
    }
    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.error,
        message: error != null ? '$message | $error' : message,
        tag: tag,
        stackTrace: stackTrace?.toString(),
      ),
    );
  }

  /// Log an HTTP/network message.
  static void http(String message, {String? tag}) {
    if (!_enabled) return;
    if (kDebugMode) {
      debugPrint('[HTTP] ${tag != null ? '[$tag] ' : ''}$message');
    }
    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.http,
        message: message,
        tag: tag ?? 'HTTP',
      ),
    );
  }

  /// Log a navigation event.
  static void nav(String message, {String? tag}) {
    if (!_enabled) return;
    if (kDebugMode) {
      debugPrint('🧭 ${tag != null ? '[$tag] ' : ''}$message');
    }
    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: message,
        tag: tag ?? 'NAV',
      ),
    );
  }

  /// Log a BLoC/state event.
  static void bloc(String message, {String? tag}) {
    if (!_enabled) return;
    if (kDebugMode) {
      debugPrint('[BLOC] ${tag != null ? '[$tag] ' : ''}$message');
    }
    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.bloc,
        message: message,
        tag: tag ?? 'BLOC',
      ),
    );
  }

  // ──────────────────────── Advanced ────────────────────────

  /// Access the underlying [DebugLogStore] singleton.
  static DebugLogStore get store => DebugLogStore.instance;

  /// Access the [LayerClassifier] to register custom rules.
  ///
  /// ```dart
  /// Logscope.classifier.addRule(({
  ///   required message, required levelName, tag, metadata,
  /// }) {
  ///   if (message.contains('Firestore')) return IssueLayer.server;
  ///   return null;
  /// });
  /// ```
  static LayerClassifier get classifier => LayerClassifier.instance;

  /// Set or update the device context for exported log reports.
  static void setDeviceContext({
    String? appName,
    String? appVersion,
    String? buildNumber,
    String? deviceModel,
    String? osVersion,
    Map<String, String>? custom,
  }) {
    DebugLogStore.instance.setDeviceContext(
      DeviceContext(
        appName: appName,
        appVersion: appVersion,
        buildNumber: buildNumber,
        deviceModel: deviceModel,
        osVersion: osVersion,
        custom: custom,
      ),
    );
  }
}
