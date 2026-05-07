/// Debug logging toolkit with automatic issue-layer classification.
///
/// - [DebugLogStore] — singleton ring buffer with broadcast stream and export.
/// - [AppLogger] — static methods that print via `debugPrint` in debug mode.
/// - [DebugLogInterceptor] — Dio interceptor with sanitized HTTP logging.
/// - [LogsFab] — draggable debug FAB + fullscreen log console overlay
///   with **Device & App Info** tab (auto-detected platform, session stats).
/// - [LayerClassifier] — auto-classifies logs as SERVER/NETWORK/MOBILE/AUTH.
library;

export 'src/app_logger.dart';
export 'src/debug_log_interceptor.dart';
export 'src/debug_log_store.dart';
export 'src/layer_classifier.dart';
export 'src/logscope.dart';
export 'src/logs_fab.dart';
