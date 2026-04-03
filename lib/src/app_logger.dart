import 'package:flutter/foundation.dart';

import 'debug_log_store.dart';

/// Centralized logging utility that respects kDebugMode.
///
/// All console output is automatically disabled in release builds.
/// Use this instead of debugPrint() or print() throughout the app.
///
/// IMPORTANT: Never log sensitive data like:
/// - Tokens or API keys
/// - Passwords
/// - Personal information
class AppLogger {
  /// Log debug messages (general debugging info)
  static void debug(String message, {String? tag}) {
    if (kDebugMode) {
      debugPrint('${tag != null ? '[$tag] ' : ''}$message');
    }
    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.debug,
        message: message,
        tag: tag,
      ),
    );
  }

  /// Log info messages (general information)
  static void info(String message, {String? tag}) {
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

  /// Log warning messages (potential issues)
  static void warning(String message, {String? tag}) {
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

  /// Log error messages (errors and exceptions)
  static void error(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
  }) {
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

  /// Log success messages (completed operations)
  static void success(String message, {String? tag}) {
    if (kDebugMode) {
      debugPrint('[OK] ${tag != null ? '[$tag] ' : ''}$message');
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

  /// Log network-related messages
  static void network(String message, {String? tag}) {
    if (kDebugMode) {
      debugPrint('[HTTP] ${tag != null ? '[$tag] ' : ''}$message');
    }
    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.http,
        message: message,
        tag: tag,
      ),
    );
  }

  /// Log security-related messages (non-sensitive)
  /// NEVER include actual credentials or tokens in the message
  static void security(String message, {String? tag}) {
    if (kDebugMode) {
      debugPrint('[AUTH] ${tag != null ? '[$tag] ' : ''}$message');
    }
    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: message,
        tag: tag ?? 'AUTH',
      ),
    );
  }

  /// Log navigation events
  static void navigation(String message, {String? tag}) {
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

  /// Log BLoC events and state changes
  static void bloc(String message, {String? tag}) {
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

  /// Redact sensitive data for logging
  /// Returns a masked version of the input (e.g., "123***789")
  static String redact(String? value, {int visibleChars = 3}) {
    if (value == null || value.isEmpty) return '[empty]';
    if (value.length <= visibleChars * 2) return '***';
    return '${value.substring(0, visibleChars)}***${value.substring(value.length - visibleChars)}';
  }

  /// Check if logging is enabled (useful for expensive log preparations)
  static bool get isEnabled => kDebugMode;
}
