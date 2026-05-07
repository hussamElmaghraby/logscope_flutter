import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'debug_log_interceptor.dart';
import 'debug_log_store.dart';
import 'layer_classifier.dart';
import 'logs_fab.dart';

/// One-stop entry point for the debug console.
///
/// Designed for **zero-config integration** — most apps need just two lines:
///
/// ```dart
/// void main() {
///   Logscope.init();            // ← auto-detects everything
///   runApp(Logscope.wrap(MyApp()));  // ← adds the draggable FAB
/// }
/// ```
///
/// App name, version, build number, package name, environment, build mode,
/// Dart version, OS, locale, and timezone are all **auto-detected**.
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
  /// All parameters are optional — the package auto-detects:
  /// - **appName**, **appVersion**, **buildNumber**, **packageName** — via `package_info_plus`.
  /// - **environment** — inferred from build mode (Debug → Development, Profile → Staging, Release → Production).
  /// - **osVersion**, **locale**, **timezone**, **dartVersion**, **flutterMode** — from the platform.
  ///
  /// Pass explicit values only to override the auto-detected defaults.
  static void init({
    bool? enabled,
    bool captureFlutterErrors = true,
    bool showErrorToasts = true,
    String? appName,
    String? appVersion,
    String? buildNumber,
    String? packageName,
    String? environment,
    String? flutterVersion,
    String? deviceModel,
    String? osVersion,
    String? manufacturer,
    String? brand,
    int bufferSize = 1000,
  }) {
    if (_initialized) return;
    _initialized = true;

    _enabled = enabled ?? true;
    _captureFlutterErrors = captureFlutterErrors;
    _showErrorToasts = showErrorToasts;

    if (!_enabled) return;

    // Auto-detect build mode
    String buildMode = 'Release';
    assert(() {
      buildMode = 'Debug';
      return true;
    }());
    if (kProfileMode) buildMode = 'Profile';

    // Auto-infer environment from build mode if not provided
    final autoEnvironment = environment ??
        (buildMode == 'Debug'
            ? 'Development'
            : buildMode == 'Profile'
                ? 'Staging'
                : 'Production');

    // Auto-detect platform info
    final autoOsVersion = osVersion ?? '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    final autoLocale = PlatformDispatcher.instance.locale.toString();
    final autoTimezone = DateTime.now().timeZoneName;

    // Set initial context with whatever we know synchronously
    DebugLogStore.instance.setDeviceContext(
      DeviceContext(
        appName: appName,
        appVersion: appVersion,
        buildNumber: buildNumber,
        packageName: packageName,
        environment: autoEnvironment,
        deviceModel: deviceModel,
        osVersion: autoOsVersion,
        manufacturer: manufacturer,
        brand: brand,
        locale: autoLocale,
        timezone: autoTimezone,
        dartVersion: Platform.version.split(' ').first,
        flutterVersion: flutterVersion,
        flutterMode: buildMode,
      ),
    );

    // Async: fetch package info and merge into context
    // User-provided values always take priority over auto-detected.
    _fetchAndMergePackageInfo(
      userAppName: appName,
      userAppVersion: appVersion,
      userBuildNumber: buildNumber,
      userPackageName: packageName,
      autoEnvironment: autoEnvironment,
      deviceModel: deviceModel,
      autoOsVersion: autoOsVersion,
      manufacturer: manufacturer,
      brand: brand,
      autoLocale: autoLocale,
      autoTimezone: autoTimezone,
      flutterVersion: flutterVersion,
      buildMode: buildMode,
    );
  }

  static Future<void> _fetchAndMergePackageInfo({
    required String? userAppName,
    required String? userAppVersion,
    required String? userBuildNumber,
    required String? userPackageName,
    required String autoEnvironment,
    required String? deviceModel,
    required String autoOsVersion,
    required String? manufacturer,
    required String? brand,
    required String autoLocale,
    required String autoTimezone,
    required String? flutterVersion,
    required String buildMode,
  }) async {
    try {
      final info = await PackageInfo.fromPlatform();
      DebugLogStore.instance.setDeviceContext(
        DeviceContext(
          appName: userAppName ?? info.appName,
          appVersion: userAppVersion ?? info.version,
          buildNumber: userBuildNumber ?? info.buildNumber,
          packageName: userPackageName ?? info.packageName,
          environment: autoEnvironment,
          deviceModel: deviceModel,
          osVersion: autoOsVersion,
          manufacturer: manufacturer,
          brand: brand,
          locale: autoLocale,
          timezone: autoTimezone,
          dartVersion: Platform.version.split(' ').first,
          flutterVersion: flutterVersion,
          flutterMode: buildMode,
        ),
      );
    } catch (_) {
      // Silently fail — package_info_plus may not work on all platforms
    }
  }

  static bool _enabled = true;
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
  /// Returns [child] unchanged if [init] was called with `enabled: false`.
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
    String? packageName,
    String? environment,
    String? flutterVersion,
    String? deviceModel,
    String? osVersion,
    String? manufacturer,
    String? brand,
    Map<String, String>? custom,
  }) {
    DebugLogStore.instance.setDeviceContext(
      DeviceContext(
        appName: appName,
        appVersion: appVersion,
        buildNumber: buildNumber,
        packageName: packageName,
        environment: environment,
        deviceModel: deviceModel,
        osVersion: osVersion,
        manufacturer: manufacturer,
        brand: brand,
        flutterVersion: flutterVersion,
        custom: custom,
      ),
    );
  }
}
