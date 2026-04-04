import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'debug_log_store.dart';
import 'layer_classifier.dart';

/// A draggable floating debug FAB widget.
///
/// Place this wrapping `MaterialApp` so it sits on top of every screen.
///
/// Features:
/// - Only visible in debug/profile mode (hidden in release builds)
/// - Draggable with snap-to-nearest-edge on release
/// - Respects platform-specific safe areas
/// - Red badge showing unread error count
/// - Tapping opens a fullscreen log console as an in-place overlay
/// - **Layer badges** — auto-classified SERVER/NETWORK/MOBILE/AUTH badges
/// - **Error toasts** — brief notification when errors occur
/// - **Auto-capture** — hooks Flutter error handlers automatically
///
/// Set [enabled] from app config when you want to hide the FAB without
/// removing the widget (e.g. production-like debug builds).
class LogsFab extends StatefulWidget {
  final Widget child;

  /// When false, only [child] is built (no overlay or FAB).
  final bool enabled;

  /// When true, shows a brief toast overlay when an error-level log is captured.
  final bool showErrorToasts;

  /// When true, automatically captures unhandled Flutter framework errors
  /// and platform dispatcher errors into [DebugLogStore].
  final bool captureFlutterErrors;

  const LogsFab({
    super.key,
    required this.child,
    this.enabled = true,
    this.showErrorToasts = false,
    this.captureFlutterErrors = false,
  });

  @override
  State<LogsFab> createState() => _LogsFabState();
}

class _LogsFabState extends State<LogsFab> with SingleTickerProviderStateMixin {
  static const double _fabSize = 48.0;
  static const double _edgePadding = 8.0;

  double _left = double.nan;
  double _top = double.nan;
  bool _initialized = false;

  late AnimationController _snapController;
  CurvedAnimation? _snapAnimation;
  double _snapFrom = 0;
  double _snapTo = 0;

  int _errorCount = 0;
  bool _consoleOpen = false;
  StreamSubscription<LogEntry>? _logSubscription;

  // ── Error toast state ──
  String? _toastMessage;
  Timer? _toastTimer;

  // ── Flutter error capture ──
  void Function(FlutterErrorDetails)? _previousFlutterErrorHandler;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _snapController.addListener(_onSnapTick);

    _logSubscription = DebugLogStore.instance.onNewLog.listen((entry) {
      if (!mounted) return;
      if (entry.level == LogLevel.error || entry.level == LogLevel.fatal) {
        setState(() {
          _errorCount = DebugLogStore.instance.errorCount;
        });

        // Show error toast
        if (widget.showErrorToasts && !_consoleOpen) {
          _showErrorToast(entry);
        }
      }
    });

    // Auto-capture Flutter framework errors
    if (widget.captureFlutterErrors) {
      _setupErrorCapture();
    }
  }

  void _setupErrorCapture() {
    _previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      DebugLogStore.instance.add(
        LogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.fatal,
          message: 'Flutter Error: ${details.exceptionAsString()}',
          tag: 'FRAMEWORK',
          stackTrace: details.stack?.toString(),
        ),
      );
      // Call the previous handler (e.g. Sentry, Crashlytics)
      _previousFlutterErrorHandler?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      DebugLogStore.instance.add(
        LogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.fatal,
          message: 'Unhandled Error: $error',
          tag: 'PLATFORM',
          stackTrace: stack.toString(),
        ),
      );
      return false; // Let the framework handle it too
    };
  }

  void _showErrorToast(LogEntry entry) {
    _toastTimer?.cancel();
    if (!mounted) return;
    setState(() {
      final layer = entry.layer;
      final layerPrefix = layer != IssueLayer.unknown
          ? '${layer.emoji} ${layer.label}: '
          : '';
      final msg = entry.message.length > 80
          ? entry.message.substring(0, 80)
          : entry.message;
      _toastMessage = '$layerPrefix$msg';
    });
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _toastMessage = null);
      }
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _snapAnimation?.dispose();
    _snapController.dispose();
    _toastTimer?.cancel();
    // Restore previous error handler
    if (widget.captureFlutterErrors && _previousFlutterErrorHandler != null) {
      FlutterError.onError = _previousFlutterErrorHandler;
    }
    super.dispose();
  }

  void _initPosition(BoxConstraints constraints) {
    if (_initialized) return;
    _initialized = true;
    final mq = MediaQuery.of(context);
    final bottomSafe = mq.padding.bottom;
    _left = constraints.maxWidth - _fabSize - _edgePadding;
    _top = constraints.maxHeight - _fabSize - bottomSafe - _edgePadding - 80;
  }

  void _onSnapTick() {
    setState(() {
      _left = _snapFrom + (_snapTo - _snapFrom) * _snapAnimation!.value;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _left += details.delta.dx;
      _top += details.delta.dy;
    });
  }

  void _onPanEnd(DragEndDetails details, BoxConstraints constraints) {
    final mq = MediaQuery.of(context);
    final safeLeft = mq.padding.left + _edgePadding;
    final safeRight =
        constraints.maxWidth - _fabSize - mq.padding.right - _edgePadding;
    final safeTop = mq.padding.top + _edgePadding;
    final safeBottom =
        constraints.maxHeight - _fabSize - mq.padding.bottom - _edgePadding;

    _top = _top.clamp(safeTop, safeBottom);

    final center = _left + _fabSize / 2;
    final screenMidpoint = constraints.maxWidth / 2;
    final targetLeft = center < screenMidpoint ? safeLeft : safeRight;

    _snapFrom = _left;
    _snapTo = targetLeft;
    _snapAnimation?.dispose();
    _snapAnimation = CurvedAnimation(
      parent: _snapController,
      curve: Curves.easeOutBack,
    );
    _snapController.forward(from: 0);
  }

  void _onTap() {
    DebugLogStore.instance.resetErrorCount();
    setState(() {
      _errorCount = 0;
      _consoleOpen = true;
      _toastMessage = null;
    });
  }

  void _closeConsole() {
    setState(() {
      _consoleOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _initPosition(constraints);

          return Stack(
            fit: StackFit.passthrough,
            children: [
              // ── App content ──
              widget.child,

              // ── FAB button ──
              if (!_consoleOpen)
                Positioned(
                  left: _left,
                  top: _top,
                  width: _fabSize,
                  height: _fabSize,
                  child: GestureDetector(
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: (details) => _onPanEnd(details, constraints),
                    onTap: _onTap,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              width: _fabSize,
                              height: _fabSize,
                              decoration: BoxDecoration(
                                color: const Color(0x99000000),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0x4DFFFFFF),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0x66000000),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.track_changes, // A majestic, descriptive scope icon
                                color: Color(0xFF00E676),
                                size: 26,
                              ),
                            ),
                          ),
                        ),
                        if (_errorCount > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 20,
                                minHeight: 20,
                              ),
                              child: Text(
                                _errorCount > 99 ? '99+' : '$_errorCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // ── Error toast ──
              if (_toastMessage != null && !_consoleOpen)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 16,
                  right: 16,
                  child: _ErrorToast(
                    message: _toastMessage!,
                    onTap: _onTap,
                  ),
                ),

              // ── Fullscreen log console overlay ──
              if (_consoleOpen)
                Positioned.fill(
                  child: _LogConsoleOverlay(onClose: _closeConsole),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Error Toast Widget
// ═══════════════════════════════════════════════════════════════════════════

class _ErrorToast extends StatelessWidget {
  final String message;
  final VoidCallback onTap;

  const _ErrorToast({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xDD1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0x33F44336),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFF44336), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      decoration: TextDecoration.none,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'OPEN',
                  style: TextStyle(
                    color: Color(0xFFF44336),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Log level colors and icons
// ═══════════════════════════════════════════════════════════════════════════

class _LogLevelTheme {
  static Color barColor(LogLevel level) {
    switch (level) {
      case LogLevel.trace:
        return const Color(0xFF9E9E9E);
      case LogLevel.debug:
        return const Color(0xFF2196F3);
      case LogLevel.info:
        return const Color(0xFF4CAF50);
      case LogLevel.warning:
        return const Color(0xFFFF9800);
      case LogLevel.error:
        return const Color(0xFFF44336);
      case LogLevel.fatal:
        return const Color(0xFF9C27B0);
      case LogLevel.http:
        return const Color(0xFF00BCD4);
      case LogLevel.bloc:
        return const Color(0xFF3F51B5);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Lightweight "Copied" toast — works without Scaffold/SnackBar
// ═══════════════════════════════════════════════════════════════════════════

void _showCopiedToast(BuildContext context) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CopiedToastWidget(onDismiss: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _CopiedToastWidget extends StatefulWidget {
  final VoidCallback onDismiss;
  const _CopiedToastWidget({required this.onDismiss});

  @override
  State<_CopiedToastWidget> createState() => _CopiedToastWidgetState();
}

class _CopiedToastWidgetState extends State<_CopiedToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);
    _controller.forward().then((_) => widget.onDismiss());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 70,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _opacity,
          builder: (_, child) => Opacity(opacity: _opacity.value, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xDD1A1A1A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 16, color: const Color(0xFF00E676)),
                const SizedBox(width: 6),
                Text(
                  'Copied',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Full-featured log console overlay
// ═══════════════════════════════════════════════════════════════════════════

/// Unified filter categories for the log console.
///
/// Combines log levels and issue layers into a single, tester-friendly
/// set of filters that all fit on screen without scrolling.
enum _FilterCategory {
  all,
  network,
  errors,
  warnings,
  info,
}

class _LogConsoleOverlay extends StatefulWidget {
  final VoidCallback onClose;

  const _LogConsoleOverlay({required this.onClose});

  @override
  State<_LogConsoleOverlay> createState() => _LogConsoleOverlayState();
}

class _LogConsoleOverlayState extends State<_LogConsoleOverlay> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  StreamSubscription<LogEntry>? _sub;
  List<LogEntry> _filteredLogs = [];
  _FilterCategory _activeFilter = _FilterCategory.all;
  String _searchQuery = '';
  bool _autoScroll = true;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _refreshLogs();

    _scrollController.addListener(_onScroll);

    _sub = DebugLogStore.instance.onNewLog.listen((_) {
      _refreshLogs();
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    _autoScroll = (maxScroll - currentScroll) < 50;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  void _refreshLogs() {
    if (!mounted) return;
    setState(() {
      final allEntries = DebugLogStore.instance.entries;
      var result = allEntries;

      // Apply category filter
      switch (_activeFilter) {
        case _FilterCategory.all:
          break;
        case _FilterCategory.network:
          result = result
              .where((e) => e.level == LogLevel.http)
              .toList();
        case _FilterCategory.errors:
          result = result
              .where((e) =>
                  e.level == LogLevel.error || e.level == LogLevel.fatal)
              .toList();
        case _FilterCategory.warnings:
          result = result
              .where((e) => e.level == LogLevel.warning)
              .toList();
        case _FilterCategory.info:
          result = result
              .where((e) => e.level == LogLevel.info)
              .toList();
      }

      // Apply search query
      if (_searchQuery.isNotEmpty) {
        final lower = _searchQuery.toLowerCase();
        result = result.where((e) {
          return e.message.toLowerCase().contains(lower) ||
              (e.tag?.toLowerCase().contains(lower) ?? false);
        }).toList();
      }

      _filteredLogs = result;
    });
  }

  void _onFilterChanged(_FilterCategory category) {
    _activeFilter = _activeFilter == category
        ? _FilterCategory.all
        : category;
    _refreshLogs();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchQuery = query;
      _refreshLogs();
    });
  }

  void _clearLogs() {
    DebugLogStore.instance.clear();
    _refreshLogs();
  }

  Future<void> _copyAll() async {
    final text = _filteredLogs.map((e) => e.toPlainText()).join('\n');
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _showCopiedToast(context);
  }

  Future<void> _shareLogs() async {
    // Build plain text from the currently filtered logs
    final text = _filteredLogs.isEmpty
        ? ''
        : _filteredLogs.map((e) => e.toPlainText()).join('\n');
    if (text.isEmpty) return;

    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/log_report_$timestamp.txt');
      await file.writeAsString(text);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], title: 'Log Report'),
      );
    } catch (_) {
      // Silently fail — share is best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: ColoredBox(
          color: const Color(0xCC121212),
          child: Padding(
            padding: EdgeInsets.only(
              top: mq.padding.top,
              bottom: mq.padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header bar ──
                _buildHeader(),

                // ── Search bar ──
                _buildSearchBar(),

                // ── Filter chips ──
                _buildFilterBar(),

                // ── Stats row ──
                _buildStatsRow(),

                // ── Divider ──
                Container(height: 1, color: const Color(0x1AFFFFFF)),

                // ── Log list ──
                Expanded(
                  child: _filteredLogs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _activeFilter != _FilterCategory.all || _searchQuery.isNotEmpty
                                    ? Icons.filter_alt_off_outlined
                                    : Icons.receipt_long_outlined,
                                size: 48,
                                color: const Color(0x33FFFFFF),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _activeFilter != _FilterCategory.all || _searchQuery.isNotEmpty
                                    ? 'No matching logs'
                                    : 'No logs yet',
                                style: TextStyle(
                                  color: const Color(0x4DFFFFFF),
                                  fontSize: 14,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              if (_activeFilter != _FilterCategory.all || _searchQuery.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () {
                                    _activeFilter = _FilterCategory.all;
                                    _searchQuery = '';
                                    _searchController.clear();
                                    _refreshLogs();
                                  },
                                  child: Text(
                                    'Clear filters',
                                    style: TextStyle(
                                      color: const Color(0xFF00E676),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: _filteredLogs.length,
                          itemBuilder: (_, index) {
                            final entry = _filteredLogs[index];
                            if (_isHttpEntry(entry)) {
                              return _HttpLogCard(entry: entry);
                            }
                            return _LogEntryTile(entry: entry);
                          },
                        ),
                ),

                // ── Bottom action bar ──
                _buildBottomBar(mq),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isHttpEntry(LogEntry entry) {
    return entry.metadata != null &&
        entry.metadata!.containsKey('statusCode') &&
        entry.metadata!['type'] != 'request';
  }

  Widget _buildHeader() {
    return Container(
      color: const Color(0x33000000),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onClose,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Logscope Console',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          GestureDetector(
            onTap: _clearLogs,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0x33F44336),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_outline, color: Color(0xFFF44336), size: 20),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            _buildFilterItem(
              label: 'All',
              category: _FilterCategory.all,
              color: Colors.white,
            ),
            _buildFilterItem(
              label: 'Network',
              category: _FilterCategory.network,
              color: const Color(0xFF00BCD4),
            ),
            _buildFilterItem(
              label: 'Errors',
              category: _FilterCategory.errors,
              color: const Color(0xFFF44336),
            ),
            _buildFilterItem(
              label: 'Warnings',
              category: _FilterCategory.warnings,
              color: const Color(0xFFFF9800),
            ),
            _buildFilterItem(
              label: 'Info',
              category: _FilterCategory.info,
              color: const Color(0xFF4CAF50),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterItem({
    required String label,
    required _FilterCategory category,
    required Color color,
  }) {
    final selected = _activeFilter == category;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onFilterChanged(category),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? color.withValues(alpha: 0.25)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? color : Colors.white24,
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.white54,
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: SizedBox(
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(
                  Icons.search,
                  color: const Color(0x99FFFFFF),
                  size: 20,
                ),
              ),
              Expanded(
                child: EditableText(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                  cursorColor: Colors.white,
                  backgroundCursorColor: Colors.grey,
                  onChanged: _onSearchChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final hasFilter = _activeFilter != _FilterCategory.all || _searchQuery.isNotEmpty;
    final storeTotal = DebugLogStore.instance.totalCount;
    final filteredCount = _filteredLogs.length;

    // Count errors/warnings in the filtered set
    final filteredErrors = _filteredLogs
        .where((e) => e.level == LogLevel.error || e.level == LogLevel.fatal)
        .length;
    final filteredWarnings =
        _filteredLogs.where((e) => e.level == LogLevel.warning).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _statDot(
            const Color(0xFFF44336),
            '$filteredErrors errors',
          ),
          const SizedBox(width: 12),
          _statDot(
            const Color(0xFFFF9800),
            '$filteredWarnings warnings',
          ),
          const Spacer(),
          Text(
            hasFilter
                ? '$filteredCount of $storeTotal'
                : '$storeTotal total',
            style: TextStyle(
              color: const Color(0x66FFFFFF),
              fontSize: 11,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDot(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: const Color(0x80FFFFFF),
            fontSize: 11,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(MediaQueryData mq) {
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        border: Border(top: BorderSide(color: const Color(0x1AFFFFFF))),
      ),
      child: Row(
        children: [
          _bottomAction(icon: Icons.share, label: 'Share', onTap: _shareLogs),
          _bottomAction(
            icon: Icons.copy_all,
            label: 'Copy All',
            onTap: _copyAll,
          ),
          _bottomAction(
            icon: Icons.vertical_align_bottom,
            label: 'Scroll ↓',
            onTap: () {
              _autoScroll = true;
              _scrollToBottom();
            },
          ),
        ],
      ),
    );
  }

  Widget _bottomAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Structured HTTP log card
// ═══════════════════════════════════════════════════════════════════════════

class _HttpLogCard extends StatefulWidget {
  final LogEntry entry;
  const _HttpLogCard({required this.entry});

  @override
  State<_HttpLogCard> createState() => _HttpLogCardState();
}

class _HttpLogCardState extends State<_HttpLogCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final meta = entry.metadata!;
    final method = meta['method'] as String? ?? '';
    final url = meta['url'] as String? ?? '';
    final fullUrl = meta['fullUrl'] as String? ?? url;
    final statusCode = meta['statusCode'] as int?;
    final durationMs = meta['durationMs'] as int?;
    final requestHeaders = meta['requestHeaders'] as String?;
    final requestBody = meta['requestBody'] as String?;
    final responseHeaders = meta['responseHeaders'] as String?;
    final responseBody = meta['responseBody'] as String?;
    final errorMessage = meta['errorMessage'] as String?;
    final isError = statusCode != null && statusCode >= 400 || statusCode == null;
    final layer = entry.layer;
    final layerColor = Color(layer.colorValue);

    // Status color
    Color statusColor;
    if (statusCode == null) {
      statusColor = const Color(0xFFF44336);
    } else if (statusCode >= 500) {
      statusColor = const Color(0xFFF44336);
    } else if (statusCode >= 400) {
      statusColor = const Color(0xFFFF9800);
    } else {
      statusColor = const Color(0xFF4CAF50);
    }

    final hasDetails = requestHeaders != null ||
        requestBody != null ||
        responseHeaders != null ||
        responseBody != null ||
        errorMessage != null;

    return GestureDetector(
      onTap: hasDetails ? () => setState(() => _expanded = !_expanded) : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isError
                ? statusColor.withValues(alpha: 0.5)
                : const Color(0x1AFFFFFF),
            width: isError ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0x33000000),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: method + status + duration + layer + timestamp ──
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Row(
                children: [
                  // Method badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _methodColor(method).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      method,
                      style: TextStyle(
                        color: _methodColor(method),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Status code
                  Text(
                    statusCode?.toString() ?? 'FAIL',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Duration
                  if (durationMs != null)
                    Text(
                      durationMs > 1000
                          ? '${(durationMs / 1000).toStringAsFixed(1)}s'
                          : '${durationMs}ms',
                      style: TextStyle(
                        color: durationMs > 3000
                            ? const Color(0xFFFF9800)
                            : const Color(0x80FFFFFF),
                        fontSize: 11,
                        fontFamily: 'monospace',
                        decoration: TextDecoration.none,
                      ),
                    ),

                  const Spacer(),

                  // Layer badge
                  if (layer != IssueLayer.unknown)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: layerColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        layer.label,
                        style: TextStyle(
                          color: layerColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),

                  const SizedBox(width: 6),

                  // Timestamp
                  Text(
                    entry.formattedTimestamp,
                    style: TextStyle(
                      color: const Color(0x4DFFFFFF),
                      fontSize: 9,
                      fontFamily: 'monospace',
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),

            // ── URL (always visible) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Text(
                _shortenUrl(url),
                style: TextStyle(
                  color: const Color(0xB3FFFFFF),
                  fontSize: 11,
                  fontFamily: 'monospace',
                  decoration: TextDecoration.none,
                ),
                maxLines: _expanded ? 5 : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // ── Error message (always visible if present) ──
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: Text(
                  errorMessage,
                  style: TextStyle(
                    color: const Color(0xCCF44336),
                    fontSize: 11,
                    fontFamily: 'monospace',
                    decoration: TextDecoration.none,
                  ),
                  maxLines: _expanded ? 10 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // ═══ Expanded detail sections ═══
            if (_expanded) ...[
              // ── Method ──
              _buildCopyableSection('Method', method),

              // ── Full URL ──
              _buildCopyableSection('URL', fullUrl),

              // ── Status ──
              _buildCopyableSection(
                'Status',
                statusCode != null
                    ? '$statusCode${durationMs != null ? '  (${durationMs}ms)' : ''}'
                    : 'FAILED${errorMessage != null ? ' — $errorMessage' : ''}',
              ),

              // ── Request Headers ──
              if (requestHeaders != null)
                _buildCopyableSection('Request Headers', requestHeaders),

              // ── Request Body ──
              if (requestBody != null)
                _buildCopyableSection('Request Body', requestBody),

              // ── Response Headers ──
              if (responseHeaders != null)
                _buildCopyableSection('Response Headers', responseHeaders),

              // ── Response Body ──
              if (responseBody != null)
                _buildCopyableSection('Response Body', responseBody),
            ],

            // ── Expand hint ──
            if (!_expanded && hasDetails)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Center(
                  child: Text(
                    '▼ tap for details',
                    style: TextStyle(
                      color: const Color(0x33FFFFFF),
                      fontSize: 9,
                      fontStyle: FontStyle.italic,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),

            // ── Collapse hint ──
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Center(
                  child: Text(
                    '▲ tap to collapse',
                    style: TextStyle(
                      color: const Color(0x33FFFFFF),
                      fontSize: 9,
                      fontStyle: FontStyle.italic,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds a section with a title, content, and a copy icon button.
  Widget _buildCopyableSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: const Color(0x0DFFFFFF)),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: const Color(0x66FFFFFF),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: content));
                      _showCopiedToast(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: const Color(0x4DFFFFFF),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                content,
                style: TextStyle(
                  color: const Color(0xB3FFFFFF),
                  fontSize: 10,
                  fontFamily: 'monospace',
                  height: 1.4,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _shortenUrl(String url) {
    // Remove scheme and host, keep path + query
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final query = uri.query.isNotEmpty ? '?${uri.query}' : '';
      return '$path$query';
    } catch (_) {
      return url;
    }
  }

  Color _methodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return const Color(0xFF4CAF50);
      case 'POST':
        return const Color(0xFF2196F3);
      case 'PUT':
      case 'PATCH':
        return const Color(0xFFFF9800);
      case 'DELETE':
        return const Color(0xFFF44336);
      default:
        return const Color(0xFF9E9E9E);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Individual log entry tile with expand/copy and layer badge
// ═══════════════════════════════════════════════════════════════════════════

class _LogEntryTile extends StatefulWidget {
  final LogEntry entry;
  const _LogEntryTile({required this.entry});

  @override
  State<_LogEntryTile> createState() => _LogEntryTileState();
}

class _LogEntryTileState extends State<_LogEntryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final color = _LogLevelTheme.barColor(entry.level);
    final isLong = entry.message.length > 200;
    final displayMessage = _expanded || !isLong
        ? entry.message
        : '${entry.message.substring(0, 200)}...';
    final layer = entry.layer;
    final layerColor = Color(layer.colorValue);

    return GestureDetector(
      onTap: isLong ? () => setState(() => _expanded = !_expanded) : null,
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: entry.toPlainText()));
        _showCopiedToast(context);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0x12FFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: color, width: 4),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0x1A000000),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: entry.formattedTimestamp,
                    style: TextStyle(color: const Color(0x80FFFFFF)),
                  ),
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: '[${entry.levelLabel}]',
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                  if (entry.tag != null) ...[
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: '[${entry.tag}]',
                      style: TextStyle(color: const Color(0x99FFFFFF)),
                    ),
                  ],
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: displayMessage,
                    style: TextStyle(color: const Color(0xE6FFFFFF)),
                  ),
                  if (entry.stackTrace != null && _expanded) ...[
                    const TextSpan(text: '\n'),
                    TextSpan(
                      text: entry.stackTrace,
                      style: TextStyle(
                        color: const Color(0x66FFFFFF),
                        fontSize: 10,
                      ),
                    ),
                  ],
                  if (isLong && !_expanded)
                    TextSpan(
                      text: ' [tap to expand]',
                      style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            // ── Layer badge ──
            if (layer != IssueLayer.unknown)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: layerColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${layer.emoji} ${layer.label}',
                    style: TextStyle(
                      color: layerColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

