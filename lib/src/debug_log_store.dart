import 'dart:async';

import 'layer_classifier.dart';

/// Log severity levels for the debug console.
enum LogLevel { trace, debug, info, warning, error, fatal, http, bloc }

/// Device and app context attached to exported log reports.
///
/// Set once at app startup via [DebugLogStore.setDeviceContext] so that
/// every exported log file includes the environment information testers
/// and developers need.
///
/// ```dart
/// DebugLogStore.instance.setDeviceContext(
///   DeviceContext(
///     appName: 'MyApp',
///     appVersion: '2.3.1',
///     buildNumber: '47',
///     deviceModel: 'iPhone 14 Pro',
///     osVersion: 'iOS 17.4',
///   ),
/// );
/// ```
class DeviceContext {
  final String? appName;
  final String? appVersion;
  final String? buildNumber;
  final String? packageName;
  final String? environment;
  final String? deviceModel;
  final String? osVersion;
  final String? manufacturer;
  final String? brand;
  final String? locale;
  final String? timezone;
  final String? screenSize;
  final String? pixelRatio;
  final String? dartVersion;
  final String? flutterVersion;
  final String? flutterMode;
  final Map<String, String>? custom;

  const DeviceContext({
    this.appName,
    this.appVersion,
    this.buildNumber,
    this.packageName,
    this.environment,
    this.deviceModel,
    this.osVersion,
    this.manufacturer,
    this.brand,
    this.locale,
    this.timezone,
    this.screenSize,
    this.pixelRatio,
    this.dartVersion,
    this.flutterVersion,
    this.flutterMode,
    this.custom,
  });

  /// Returns a structured map of all device/app info for display.
  ///
  /// Splits into two sections: 'App Info' and 'Device Info'.
  Map<String, Map<String, String>> toDisplaySections() {
    final appInfo = <String, String>{};
    if (appName != null) appInfo['App Name'] = appName!;
    if (appVersion != null) appInfo['Version'] = appVersion!;
    if (buildNumber != null) appInfo['Build Number'] = buildNumber!;
    if (packageName != null) appInfo['Package Name'] = packageName!;
    if (environment != null) appInfo['Environment'] = environment!;
    if (flutterMode != null) appInfo['Build Mode'] = flutterMode!;
    if (flutterVersion != null) appInfo['Flutter Version'] = flutterVersion!;
    if (dartVersion != null) appInfo['Dart Version'] = dartVersion!;

    final deviceInfo = <String, String>{};
    if (deviceModel != null) deviceInfo['Device Model'] = deviceModel!;
    if (manufacturer != null) deviceInfo['Manufacturer'] = manufacturer!;
    if (brand != null) deviceInfo['Brand'] = brand!;
    if (osVersion != null) deviceInfo['OS Version'] = osVersion!;
    if (locale != null) deviceInfo['Locale'] = locale!;
    if (timezone != null) deviceInfo['Timezone'] = timezone!;
    if (screenSize != null) deviceInfo['Screen Size'] = screenSize!;
    if (pixelRatio != null) deviceInfo['Pixel Ratio'] = pixelRatio!;

    final result = <String, Map<String, String>>{};
    if (appInfo.isNotEmpty) result['App Info'] = appInfo;
    if (deviceInfo.isNotEmpty) result['Device Info'] = deviceInfo;
    if (custom != null && custom!.isNotEmpty) result['Custom'] = custom!;
    return result;
  }

  String toReportHeader(DateTime sessionStart, int totalLogs, int errors,
      int warnings) {
    final buf = StringBuffer();
    buf.writeln('═══ Log Report ═══');
    if (appName != null) {
      buf.write('App: $appName');
      if (appVersion != null) buf.write(' v$appVersion');
      if (buildNumber != null) buf.write(' (build $buildNumber)');
      buf.writeln();
    }
    if (packageName != null) buf.writeln('Package: $packageName');
    if (environment != null) buf.writeln('Environment: $environment');
    if (flutterVersion != null) buf.writeln('Flutter: $flutterVersion');
    if (deviceModel != null || osVersion != null) {
      buf.writeln('Device: ${deviceModel ?? 'Unknown'} — ${osVersion ?? 'Unknown OS'}');
    }
    if (manufacturer != null) buf.writeln('Manufacturer: $manufacturer');
    final now = DateTime.now();
    final duration = now.difference(sessionStart);
    final minutes = duration.inMinutes;
    final sessionStr = minutes > 0 ? '$minutes min' : '${duration.inSeconds}s';
    buf.writeln(
      'Session: ${_formatDateTime(sessionStart)} → ${_formatDateTime(now)} ($sessionStr)',
    );
    buf.writeln('Logs: $totalLogs total, $errors errors, $warnings warnings');
    if (custom != null && custom!.isNotEmpty) {
      for (final entry in custom!.entries) {
        buf.writeln('${entry.key}: ${entry.value}');
      }
    }
    buf.writeln('══════════════════');
    return buf.toString();
  }

  static String _formatDateTime(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

/// A single log entry captured from [AppLogger] or [DebugLogInterceptor].
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? tag;
  final String? stackTrace;
  final Map<String, dynamic>? metadata;

  /// The classified issue layer (auto-populated by [DebugLogStore]).
  final IssueLayer layer;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.tag,
    this.stackTrace,
    this.metadata,
    this.layer = IssueLayer.unknown,
  });

  /// Creates a copy with the given layer.
  LogEntry withLayer(IssueLayer layer) => LogEntry(
    timestamp: timestamp,
    level: level,
    message: message,
    tag: tag,
    stackTrace: stackTrace,
    metadata: metadata,
    layer: layer,
  );

  String get formattedTimestamp {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  String get levelLabel => level.name.toUpperCase();

  String toPlainText() {
    final tagStr = tag != null ? '[$tag] ' : '';
    final stackStr = stackTrace != null ? '\n$stackTrace' : '';
    final layerStr = layer != IssueLayer.unknown
        ? ' ${layer.emoji} ${layer.label}'
        : '';
    return '$formattedTimestamp [$levelLabel]$layerStr $tagStr$message$stackStr';
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'message': message,
    'layer': layer.name,
    if (tag != null) 'tag': tag,
    if (stackTrace != null) 'stackTrace': stackTrace,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Fixed-size circular buffer with O(1) add.
///
/// When the buffer reaches [capacity], the oldest entry is overwritten.
/// Iteration via [entries] returns items oldest-first.
class LogRingBuffer<T> {
  final int capacity;
  final List<T?> _buffer;
  int _head = 0;
  int _count = 0;

  LogRingBuffer({this.capacity = 1000})
    : _buffer = List<T?>.filled(capacity, null);

  int get length => _count;
  bool get isEmpty => _count == 0;

  void add(T item) {
    _buffer[_head] = item;
    _head = (_head + 1) % capacity;
    if (_count < capacity) _count++;
  }

  void clear() {
    for (var i = 0; i < capacity; i++) {
      _buffer[i] = null;
    }
    _head = 0;
    _count = 0;
  }

  /// Returns entries oldest-first.
  List<T> get entries {
    if (_count == 0) return [];
    final result = <T>[];
    final start = _count < capacity ? 0 : _head;
    for (var i = 0; i < _count; i++) {
      result.add(_buffer[(start + i) % capacity] as T);
    }
    return result;
  }
}

/// Singleton store for debug log entries.
///
/// Captures logs from [AppLogger] and [DebugLogInterceptor] into a ring buffer
/// and broadcasts new entries via a stream. Features automatic layer
/// classification via [LayerClassifier] and optional device context for
/// rich log exports.
class DebugLogStore {
  DebugLogStore._internal();

  static final DebugLogStore _instance = DebugLogStore._internal();
  static DebugLogStore get instance => _instance;

  final LogRingBuffer<LogEntry> _buffer = LogRingBuffer<LogEntry>(
    capacity: 1000,
  );
  final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();

  int _errorCount = 0;
  int _warningCount = 0;

  /// Session start timestamp — set when the first log is added.
  DateTime? _sessionStart;

  /// Optional device/app context for export headers.
  DeviceContext? _deviceContext;

  /// The current device context, if set.
  DeviceContext? get deviceContext => _deviceContext;

  /// Whether to auto-classify the issue layer on each log entry.
  bool autoClassifyLayer = true;

  /// When the current session started (first log entry).
  DateTime get sessionStart => _sessionStart ?? DateTime.now();

  /// Number of error-level entries since last clear.
  int get errorCount => _errorCount;

  /// Number of warning-level entries since last clear.
  int get warningCount => _warningCount;

  /// Total number of entries in the buffer.
  int get totalCount => _buffer.length;

  /// Stream of new log entries (broadcast — safe for multiple listeners).
  Stream<LogEntry> get onNewLog => _controller.stream;

  /// All entries in the buffer, oldest first.
  List<LogEntry> get entries => _buffer.entries;

  /// Set device context for log report exports.
  ///
  /// Call this once during app initialization:
  /// ```dart
  /// DebugLogStore.instance.setDeviceContext(
  ///   DeviceContext(
  ///     appName: 'MyApp',
  ///     appVersion: '2.3.1',
  ///     buildNumber: '47',
  ///     deviceModel: 'iPhone 14 Pro',
  ///     osVersion: 'iOS 17.4',
  ///   ),
  /// );
  /// ```
  void setDeviceContext(DeviceContext context) {
    _deviceContext = context;
  }

  /// Add a log entry.
  ///
  /// If [autoClassifyLayer] is true and the entry's layer is [IssueLayer.unknown],
  /// the [LayerClassifier] will attempt to auto-detect the layer.
  void add(LogEntry entry) {
    _sessionStart ??= DateTime.now();

    // Auto-classify layer if not already set
    LogEntry classified = entry;
    if (autoClassifyLayer && entry.layer == IssueLayer.unknown) {
      final layer = LayerClassifier.instance.classify(
        message: entry.message,
        levelName: entry.levelLabel,
        tag: entry.tag,
        metadata: entry.metadata,
      );
      if (layer != IssueLayer.unknown) {
        classified = entry.withLayer(layer);
      }
    }

    _buffer.add(classified);
    if (classified.level == LogLevel.error ||
        classified.level == LogLevel.fatal) {
      _errorCount++;
    } else if (classified.level == LogLevel.warning) {
      _warningCount++;
    }
    if (_controller.hasListener) {
      _controller.add(classified);
    }
  }

  /// Reset the error badge count without clearing logs.
  void resetErrorCount() => _errorCount = 0;

  /// Clear all entries and reset counters.
  void clear() {
    _buffer.clear();
    _errorCount = 0;
    _warningCount = 0;
  }

  /// Filter logs by level, layer, and/or search query.
  List<LogEntry> filteredLogs({
    LogLevel? level,
    IssueLayer? layer,
    String? query,
  }) {
    var result = _buffer.entries;
    if (level != null) {
      result = result.where((e) => e.level == level).toList();
    }
    if (layer != null) {
      result = result.where((e) => e.layer == layer).toList();
    }
    if (query != null && query.isNotEmpty) {
      final lower = query.toLowerCase();
      result = result.where((e) {
        return e.message.toLowerCase().contains(lower) ||
            (e.tag?.toLowerCase().contains(lower) ?? false);
      }).toList();
    }
    return result;
  }

  /// Export all logs as plain text with optional device context header.
  String toPlainText({LogLevel? level, IssueLayer? layer, String? query}) {
    final entries = filteredLogs(level: level, layer: layer, query: query);
    final logLines = entries.map((e) => e.toPlainText()).join('\n');

    if (_deviceContext != null) {
      final header = _deviceContext!.toReportHeader(
        sessionStart,
        totalCount,
        _errorCount,
        _warningCount,
      );
      return '$header\n$logLines';
    }

    return logLines;
  }

  /// Export all logs as JSON string.
  String toJsonString({LogLevel? level, IssueLayer? layer, String? query}) {
    final entries = filteredLogs(level: level, layer: layer, query: query);
    final list = entries.map((e) => e.toJson()).toList();
    return list.toString();
  }
}
