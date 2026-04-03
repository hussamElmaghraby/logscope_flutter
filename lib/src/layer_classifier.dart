/// Automatic issue-layer classification for log entries.
///
/// Testers see a colored badge (SERVER, NETWORK, MOBILE, AUTH) instead of
/// needing to interpret raw log data. Developers can register custom rules
/// via [LayerClassifier.addRule].
library;

/// The layer where an issue likely originates.
enum IssueLayer {
  /// HTTP 5xx, server-side error messages.
  server,

  /// Timeouts, socket errors, DNS failures, no connectivity.
  network,

  /// Dart exceptions, null errors, parse/cast failures, UI bugs.
  mobile,

  /// HTTP 401/403, token expiry, permission denied.
  auth,

  /// Cannot be auto-classified.
  unknown,
}

/// A single classification rule tested against a log entry's properties.
typedef LayerRule = IssueLayer? Function({
  required String message,
  required String levelName,
  String? tag,
  Map<String, dynamic>? metadata,
});

/// Classifies [LogEntry] instances into an [IssueLayer].
///
/// Built-in rules cover the most common patterns. Use [addRule] to extend
/// classification for domain-specific cases (e.g. Firebase, GraphQL).
///
/// Rules are evaluated in order; the first non-null result wins.
class LayerClassifier {
  LayerClassifier._();

  static final LayerClassifier _instance = LayerClassifier._();

  /// Singleton accessor.
  static LayerClassifier get instance => _instance;

  final List<LayerRule> _customRules = [];

  // ──────────────────────── Public API ────────────────────────

  /// Register a custom classification rule.
  ///
  /// Custom rules are evaluated **before** built-in rules, so they can
  /// override default behavior.
  ///
  /// ```dart
  /// LayerClassifier.instance.addRule(({
  ///   required message,
  ///   required levelName,
  ///   tag,
  ///   metadata,
  /// }) {
  ///   if (message.contains('Firestore')) return IssueLayer.server;
  ///   return null; // let other rules decide
  /// });
  /// ```
  void addRule(LayerRule rule) => _customRules.add(rule);

  /// Remove all custom rules.
  void clearCustomRules() => _customRules.clear();

  /// Classify a log entry into an [IssueLayer].
  IssueLayer classify({
    required String message,
    required String levelName,
    String? tag,
    Map<String, dynamic>? metadata,
  }) {
    // 1. Custom rules first
    for (final rule in _customRules) {
      final result = rule(
        message: message,
        levelName: levelName,
        tag: tag,
        metadata: metadata,
      );
      if (result != null) return result;
    }

    // 2. Structured HTTP metadata (from DebugLogInterceptor)
    if (metadata != null) {
      final statusCode = metadata['statusCode'] as int?;
      if (statusCode != null) {
        final layer = _classifyHttpStatus(statusCode, message);
        if (layer != null) return layer;
      }

      final errorType = metadata['errorType'] as String?;
      if (errorType != null) {
        final layer = _classifyDioErrorType(errorType);
        if (layer != null) return layer;
      }
    }

    // 3. Pattern matching on message text
    final lower = message.toLowerCase();

    // ── Auth patterns ──
    if (_authPatterns.any((p) => lower.contains(p))) {
      return IssueLayer.auth;
    }

    // ── Network patterns ──
    if (_networkPatterns.any((p) => lower.contains(p))) {
      return IssueLayer.network;
    }

    // ── Server patterns ──
    if (_serverPatterns.any((p) => lower.contains(p))) {
      return IssueLayer.server;
    }

    // ── Mobile patterns ──
    if (_mobilePatterns.any((p) => lower.contains(p))) {
      return IssueLayer.mobile;
    }

    // ── HTTP level with status code in message ──
    if (levelName == 'HTTP' || tag?.toUpperCase() == 'HTTP') {
      final statusMatch = _httpStatusRegex.firstMatch(message);
      if (statusMatch != null) {
        final code = int.tryParse(statusMatch.group(1)!);
        if (code != null) {
          final layer = _classifyHttpStatus(code, message);
          if (layer != null) return layer;
        }
      }
    }

    // ── Error level without specific pattern → mobile by default ──
    if (levelName == 'ERROR' || levelName == 'FATAL') {
      return IssueLayer.mobile;
    }

    return IssueLayer.unknown;
  }

  // ──────────────────────── Internals ────────────────────────

  static IssueLayer? _classifyHttpStatus(int code, String message) {
    if (code == 401 || code == 403) return IssueLayer.auth;
    if (code >= 500) return IssueLayer.server;
    if (code == 408 || code == 504) return IssueLayer.network;
    if (code >= 400) {
      // 4xx could be mobile (bad request) or auth
      final lower = message.toLowerCase();
      if (lower.contains('token') ||
          lower.contains('unauthorized') ||
          lower.contains('forbidden')) {
        return IssueLayer.auth;
      }
      return IssueLayer.mobile;
    }
    return null; // 2xx, 3xx — not an issue
  }

  static IssueLayer? _classifyDioErrorType(String errorType) {
    switch (errorType) {
      case 'connectionTimeout':
      case 'sendTimeout':
      case 'receiveTimeout':
      case 'connectionError':
        return IssueLayer.network;
      case 'badResponse':
        return null; // handled by status code
      case 'cancel':
        return IssueLayer.mobile;
      default:
        return null;
    }
  }

  static final _httpStatusRegex = RegExp(r'→\s*(\d{3})\b');

  static const _authPatterns = [
    'unauthorized',
    '401',
    '403',
    'forbidden',
    'token expired',
    'token invalid',
    'authentication failed',
    'not authenticated',
    'access denied',
    'permission denied',
    'login required',
    'session expired',
    'refresh token',
    'invalid credentials',
  ];

  static const _networkPatterns = [
    'socketexception',
    'socket exception',
    'connection refused',
    'connection reset',
    'connection closed',
    'connection timed out',
    'timeout',
    'timed out',
    'no internet',
    'no connectivity',
    'network unreachable',
    'host lookup',
    'dns',
    'handshake',
    'certificate',
    'ssl',
    'tls',
    'errno = 7',
    'errno = 101',
    'failed host lookup',
    'network is unreachable',
    'no address associated',
    'connection aborted',
  ];

  static const _serverPatterns = [
    'internal server error',
    '500',
    '502',
    '503',
    'bad gateway',
    'service unavailable',
    'server error',
    'server unavailable',
    'database error',
    'db error',
    'query failed',
    'sql error',
    'postgres',
    'mysql',
    'mongodb',
    'redis error',
    'cache miss',
    'upstream',
    'backend',
    'microservice',
    'grpc error',
  ];

  static const _mobilePatterns = [
    'null check',
    'nosuchmethoderror',
    'type \'null\'',
    'type \'string\'',
    'cast',
    'formatexception',
    'format exception',
    'rangeerror',
    'range error',
    'indexerror',
    'index out of',
    'assertion failed',
    'state error',
    'stateerror',
    'json decode',
    'json.decode',
    'jsondecodeerror',
    'unexpected character',
    'unexpected end',
    'missing required',
    'invalid argument',
    'widget',
    'renderflex',
    'overflow',
    'setState() called',
    'build context',
    'navigator',
    'disposed',
    'not mounted',
  ];
}

// ═══════════════════════════════════════════════════════════════════════════
// Layer display helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Extension for UI display properties.
extension IssueLayerDisplay on IssueLayer {
  /// Short label for badge display.
  String get label {
    switch (this) {
      case IssueLayer.server:
        return 'SERVER';
      case IssueLayer.network:
        return 'NETWORK';
      case IssueLayer.mobile:
        return 'MOBILE';
      case IssueLayer.auth:
        return 'AUTH';
      case IssueLayer.unknown:
        return '';
    }
  }

  /// Color value (as int) for badge rendering.
  /// Using int to avoid importing Flutter in this pure-Dart file.
  int get colorValue {
    switch (this) {
      case IssueLayer.server:
        return 0xFFF44336; // Red
      case IssueLayer.network:
        return 0xFFFF9800; // Orange
      case IssueLayer.mobile:
        return 0xFF2196F3; // Blue
      case IssueLayer.auth:
        return 0xFFFF5722; // Deep Orange
      case IssueLayer.unknown:
        return 0xFF9E9E9E; // Grey
    }
  }

  /// Emoji for plain-text exports.
  String get emoji {
    switch (this) {
      case IssueLayer.server:
        return '🟥';
      case IssueLayer.network:
        return '🟧';
      case IssueLayer.mobile:
        return '🟦';
      case IssueLayer.auth:
        return '🟨';
      case IssueLayer.unknown:
        return '⬜';
    }
  }
}
