import 'dart:convert';

import 'package:dio/dio.dart';

import 'debug_log_store.dart';

/// A Dio [Interceptor] that captures all HTTP requests, responses, and errors
/// into [DebugLogStore] for the debug console.
///
/// Features:
/// - Logs method, URL, status code, duration, and truncated bodies
/// - Captures request and response headers
/// - Sanitizes sensitive headers (Authorization, API keys)
/// - Sanitizes PII in URLs (long digit sequences)
/// - Size-guarded body logging (skips bodies > 10KB)
/// - Stores structured metadata for rich HTTP card rendering
class DebugLogInterceptor extends Interceptor {
  /// Hard cap — bodies larger than this are skipped entirely.
  static const int _hardCapBytes = 10000;

  /// Max characters to show for request/response bodies.
  static const int _maxBodyLength = 2000;

  /// Keys whose values will be masked in logged headers.
  static const _sensitiveKeys = [
    'authorization',
    'api-key',
    'apikey',
    'token',
    'x-api-key',
  ];

  /// Tracks when each request started (keyed by requestOptions.hashCode).
  final Map<int, DateTime> _startTimes = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _startTimes[options.hashCode] = DateTime.now();

    final sanitizedUrl = _sanitizeUrl(options.uri.toString());
    final sanitizedHeaders = _sanitizeHeaders(options.headers);

    final msg = StringBuffer();
    msg.writeln('→ ${options.method} $sanitizedUrl');
    if (sanitizedHeaders.isNotEmpty) {
      final headerStr = sanitizedHeaders.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      msg.writeln('Headers: {$headerStr}');
    }

    String? requestBody;
    if (options.data != null) {
      requestBody = _safeFormatBody(options.data, _maxBodyLength);
      if (requestBody != null) {
        msg.write('Body: $requestBody');
      }
    }

    // Format headers for display
    final requestHeadersStr = _formatHeaders(sanitizedHeaders);

    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.http,
        message: msg.toString().trimRight(),
        tag: 'HTTP',
        metadata: {
          'type': 'request',
          'method': options.method,
          'url': sanitizedUrl,
          'fullUrl': options.uri.toString(),
          'requestHeaders': ?requestHeadersStr,
          'requestBody': ?requestBody,
        },
      ),
    );

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final start = _startTimes.remove(response.requestOptions.hashCode);
    final duration = start != null
        ? DateTime.now().difference(start)
        : Duration.zero;

    final sanitizedUrl = _sanitizeUrl(response.requestOptions.uri.toString());
    final statusCode = response.statusCode ?? 0;
    final isError = statusCode >= 400;

    final msg = StringBuffer();
    msg.writeln(
      '← ${response.requestOptions.method} $sanitizedUrl → $statusCode '
      '(${_formatDuration(duration)})',
    );

    // Capture request data from the original request
    final reqHeaders = _sanitizeHeaders(response.requestOptions.headers);
    final requestHeadersStr = _formatHeaders(reqHeaders);

    String? requestBody;
    if (response.requestOptions.data != null) {
      requestBody = _safeFormatBody(
          response.requestOptions.data, _maxBodyLength);
    }

    // Capture response headers
    final resHeaders = _formatResponseHeaders(response.headers);

    String? responseBody;
    if (response.data != null) {
      responseBody = _safeFormatBody(response.data, _maxBodyLength);
      if (responseBody != null) {
        msg.write('Response: $responseBody');
      }
    }

    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: isError ? LogLevel.error : LogLevel.http,
        message: msg.toString().trimRight(),
        tag: 'HTTP',
        metadata: {
          'type': 'response',
          'method': response.requestOptions.method,
          'url': sanitizedUrl,
          'fullUrl': response.requestOptions.uri.toString(),
          'statusCode': statusCode,
          'durationMs': duration.inMilliseconds,
          'requestHeaders': ?requestHeadersStr,
          'requestBody': ?requestBody,
          'responseHeaders': ?resHeaders,
          'responseBody': ?responseBody,
        },
      ),
    );

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final start = _startTimes.remove(err.requestOptions.hashCode);
    final duration = start != null
        ? DateTime.now().difference(start)
        : Duration.zero;

    final sanitizedUrl = _sanitizeUrl(err.requestOptions.uri.toString());
    final statusCode = err.response?.statusCode;

    final msg = StringBuffer();
    msg.writeln(
      '✗ ${err.requestOptions.method} $sanitizedUrl '
      '→ ${statusCode ?? 'FAILED'} (${_formatDuration(duration)})',
    );
    msg.writeln('Error: ${err.message ?? err.type.name}');

    // Capture request data from the original request
    final reqHeaders = _sanitizeHeaders(err.requestOptions.headers);
    final requestHeadersStr = _formatHeaders(reqHeaders);

    String? requestBody;
    if (err.requestOptions.data != null) {
      requestBody = _safeFormatBody(
          err.requestOptions.data, _maxBodyLength);
    }

    // Capture response headers and body
    String? resHeaders;
    if (err.response != null) {
      resHeaders = _formatResponseHeaders(err.response!.headers);
    }

    String? responseBody;
    if (err.response?.data != null) {
      responseBody = _safeFormatBody(err.response!.data, _maxBodyLength);
      if (responseBody != null) {
        msg.write('Response: $responseBody');
      }
    }

    DebugLogStore.instance.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.error,
        message: msg.toString().trimRight(),
        tag: 'HTTP',
        metadata: {
          'type': 'error',
          'method': err.requestOptions.method,
          'url': sanitizedUrl,
          'fullUrl': err.requestOptions.uri.toString(),
          'statusCode': statusCode,
          'durationMs': duration.inMilliseconds,
          'errorType': err.type.name,
          'errorMessage': err.message ?? err.type.name,
          'requestHeaders': ?requestHeadersStr,
          'requestBody': ?requestBody,
          'responseHeaders': ?resHeaders,
          'responseBody': ?responseBody,
        },
        stackTrace: err.stackTrace.toString(),
      ),
    );

    handler.next(err);
  }

  // ───────────────────────── Helpers ─────────────────────────

  /// Format duration for display.
  static String _formatDuration(Duration duration) {
    return duration.inSeconds > 0
        ? '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s'
        : '${duration.inMilliseconds}ms';
  }

  /// Sanitize URL to hide long digit sequences (potential PII).
  static String _sanitizeUrl(String url) {
    return url.replaceAllMapped(RegExp(r'/(\d{10,})'), (m) {
      final id = m.group(1)!;
      return '/${id.substring(0, 3)}***${id.substring(id.length - 3)}';
    });
  }

  /// Sanitize headers to hide sensitive values.
  static Map<String, String> _sanitizeHeaders(Map<String, dynamic> headers) {
    final sanitized = <String, String>{};
    headers.forEach((key, value) {
      final lowerKey = key.toLowerCase();
      if (_sensitiveKeys.any((k) => lowerKey.contains(k))) {
        sanitized[key] = '***';
      } else {
        sanitized[key] = value.toString();
      }
    });
    return sanitized;
  }

  /// Format sanitized headers map into a readable multi-line string.
  static String? _formatHeaders(Map<String, String> headers) {
    if (headers.isEmpty) return null;
    return headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }

  /// Format Dio response headers into a readable multi-line string.
  static String? _formatResponseHeaders(Headers headers) {
    final map = headers.map;
    if (map.isEmpty) return null;
    return map.entries
        .map((e) => '${e.key}: ${e.value.join(', ')}')
        .join('\n');
  }

  /// Safely format body data with size guards.
  static String? _safeFormatBody(dynamic data, int maxLength) {
    if (data == null) return null;

    String raw;
    if (data is String) {
      if (data.trim().isEmpty) return null;
      raw = data;
    } else if (data is Map || data is List) {
      try {
        raw = jsonEncode(data);
      } catch (_) {
        raw = data.toString();
      }
    } else {
      raw = data.toString();
    }

    if (raw.length > _hardCapBytes) {
      return '(${raw.length} chars — skipped, exceeds $_hardCapBytes char limit)';
    }

    // Try to pretty-print JSON
    String formatted;
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      formatted = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      formatted = raw;
    }

    if (formatted.length <= maxLength) {
      return formatted;
    }

    return '${formatted.substring(0, maxLength)}... (${raw.length} chars total)';
  }
}
