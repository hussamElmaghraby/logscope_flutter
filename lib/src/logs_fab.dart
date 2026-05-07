import 'dart:async';
import 'dart:convert';
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
/// - Works in all build modes (debug, profile, and release)
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

/// InheritedWidget that provides a "copied" toast trigger to descendants.
class _CopiedToastScope extends InheritedWidget {
  final VoidCallback showToast;

  const _CopiedToastScope({
    required this.showToast,
    required super.child,
  });

  static VoidCallback? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_CopiedToastScope>()
        ?.showToast;
  }

  @override
  bool updateShouldNotify(_CopiedToastScope oldWidget) => false;
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
  LogEntry? _selectedHttpEntry;

  // ── Toast state ──
  bool _showToast = false;
  Timer? _toastTimer;

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
    _toastTimer?.cancel();
    super.dispose();
  }

  void _showCopiedToast() {
    _toastTimer?.cancel();
    setState(() => _showToast = true);
    _toastTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showToast = false);
    });
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
    if (mounted) _showCopiedToast();
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

    return _CopiedToastScope(
      showToast: _showCopiedToast,
      child: Stack(
        children: [
          // ── Main console UI ──
          ClipRect(
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
                                    return _HttpLogCard(
                                      entry: entry,
                                      onTap: () => setState(() => _selectedHttpEntry = entry),
                                    );
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
          ),

          if (_selectedHttpEntry != null)
            Positioned.fill(
              child: _HttpDetailsOverlay(
                entry: _selectedHttpEntry!,
                onClose: () => setState(() => _selectedHttpEntry = null),
              ),
            ),

          // ── Copied toast ──
          if (_showToast)
            Positioned(
              bottom: mq.padding.bottom + 70,
              left: 0,
              right: 0,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 200),
                  builder: (_, opacity, child) =>
                      Opacity(opacity: opacity, child: child),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
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
            ),
        ],
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
    // Pre-compute per-category counts from entries narrowed by the search
    // query (but not the active category). This makes the badges answer the
    // useful question: "if I switch to this filter, how many will I see?"
    final entries = DebugLogStore.instance.entries;
    final scoped = _searchQuery.isEmpty
        ? entries
        : entries.where((e) {
            final lower = _searchQuery.toLowerCase();
            return e.message.toLowerCase().contains(lower) ||
                (e.tag?.toLowerCase().contains(lower) ?? false);
          }).toList();

    var networkCount = 0;
    var errorCount = 0;
    var warningCount = 0;
    var infoCount = 0;
    for (final e in scoped) {
      switch (e.level) {
        case LogLevel.http:
          networkCount++;
        case LogLevel.error:
        case LogLevel.fatal:
          errorCount++;
        case LogLevel.warning:
          warningCount++;
        case LogLevel.info:
          infoCount++;
        default:
          break;
      }
    }

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        physics: const BouncingScrollPhysics(),
        children: [
          _buildFilterItem(
            label: 'All',
            icon: Icons.dehaze_rounded,
            category: _FilterCategory.all,
            color: Colors.white,
          ),
          _buildFilterItem(
            label: 'Network',
            icon: Icons.cloud_outlined,
            category: _FilterCategory.network,
            color: const Color(0xFF00BCD4),
            count: networkCount,
          ),
          _buildFilterItem(
            label: 'Errors',
            icon: Icons.error_outline_rounded,
            category: _FilterCategory.errors,
            color: const Color(0xFFF44336),
            count: errorCount,
          ),
          _buildFilterItem(
            label: 'Warnings',
            icon: Icons.warning_amber_rounded,
            category: _FilterCategory.warnings,
            color: const Color(0xFFFF9800),
            count: warningCount,
          ),
          _buildFilterItem(
            label: 'Info',
            icon: Icons.info_outline_rounded,
            category: _FilterCategory.info,
            color: const Color(0xFF4CAF50),
            count: infoCount,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterItem({
    required String label,
    required IconData icon,
    required _FilterCategory category,
    required Color color,
    int? count,
  }) {
    final selected = _activeFilter == category;
    final fg = selected ? color : const Color(0xCCFFFFFF);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => _onFilterChanged(category),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.32),
                      color.withValues(alpha: 0.16),
                    ],
                  )
                : null,
            color: selected ? null : const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.9)
                  : const Color(0x1FFFFFFF),
              width: selected ? 1.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: -2,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0.1,
                  decoration: TextDecoration.none,
                ),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.95)
                        : color.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? Colors.white : color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ],
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
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, child) {
                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        if (value.text.isEmpty)
                          Text(
                            'Search logs...',
                            style: TextStyle(
                              color: const Color(0x4DFFFFFF),
                              fontSize: 14,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        child!,
                      ],
                    );
                  },
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
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                  ),
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


String _shortenUrl(String url) {
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
    case 'GET': return const Color(0xFF4CAF50);
    case 'POST': return const Color(0xFF2196F3);
    case 'PUT':
    case 'PATCH': return const Color(0xFFFF9800);
    case 'DELETE': return const Color(0xFFF44336);
    default: return const Color(0xFF9E9E9E);
  }
}

class _HttpLogCard extends StatelessWidget {
  final LogEntry entry;
  final VoidCallback onTap;
  
  const _HttpLogCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final meta = entry.metadata!;
    final method = meta['method'] as String? ?? '';
    final url = meta['url'] as String? ?? '';
    final statusCode = meta['statusCode'] as int?;
    final durationMs = meta['durationMs'] as int?;
    final errorMessage = meta['errorMessage'] as String?;
    final isError = statusCode != null && statusCode >= 400 || statusCode == null;
    final layer = entry.layer;
    final layerColor = Color(layer.colorValue);

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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isError ? statusColor.withValues(alpha: 0.5) : const Color(0x1AFFFFFF),
            width: isError ? 1.5 : 1.0,
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  if (durationMs != null)
                    Text(
                      durationMs > 1000
                          ? '${(durationMs / 1000).toStringAsFixed(1)}s'
                          : '${durationMs}ms',
                      style: TextStyle(
                        color: durationMs > 3000 ? const Color(0xFFFF9800) : const Color(0x80FFFFFF),
                        fontSize: 11,
                        fontFamily: 'monospace',
                        decoration: TextDecoration.none,
                      ),
                    ),
                  const Spacer(),
                  if (layer != IssueLayer.unknown)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  Text(
                    entry.formattedTimestamp,
                    style: const TextStyle(
                      color: Color(0x4DFFFFFF),
                      fontSize: 9,
                      fontFamily: 'monospace',
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Text(
                _shortenUrl(url),
                style: const TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 11,
                  fontFamily: 'monospace',
                  decoration: TextDecoration.none,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: Text(
                  errorMessage,
                  style: const TextStyle(
                    color: Color(0xCCF44336),
                    fontSize: 11,
                    fontFamily: 'monospace',
                    decoration: TextDecoration.none,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HttpDetailsOverlay extends StatefulWidget {
  final LogEntry entry;
  final VoidCallback onClose;
  const _HttpDetailsOverlay({required this.entry, required this.onClose});

  @override
  State<_HttpDetailsOverlay> createState() => _HttpDetailsOverlayState();
}

class _HttpDetailsOverlayState extends State<_HttpDetailsOverlay> {
  int _tabIndex = 0; // 0: Overview, 1: Request, 2: Response

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: ColoredBox(
          color: const Color(0xEE121212),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                _buildTabBar(),
                Container(height: 1, color: const Color(0x1AFFFFFF)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _buildTabContent(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final meta = widget.entry.metadata!;
    final method = meta['method'] as String? ?? '';
    final url = meta['url'] as String? ?? '';
    
    return Container(
      color: const Color(0x33000000),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onClose,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  method,
                  style: TextStyle(
                    color: _methodColor(method),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    decoration: TextDecoration.none,
                  ),
                ),
                Text(
                  _shortenUrl(url),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    decoration: TextDecoration.none,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.entry.toPlainText()));
              _CopiedToastScope.of(context)?.call();
            },
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.copy, color: Colors.white70, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Row(
      children: [
        _buildTab('Overview', 0),
        _buildTab('Request', 1),
        _buildTab('Response', 2),
      ],
    );
  }

  Widget _buildTab(String title, int index) {
    final selected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? const Color(0xFF00E676) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? const Color(0xFF00E676) : Colors.white54,
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    final meta = widget.entry.metadata!;
    
    if (_tabIndex == 0) {
      final method = meta['method'] as String? ?? '';
      final fullUrl = meta['fullUrl'] as String? ?? '';
      final statusCode = meta['statusCode'] as int?;
      final durationMs = meta['durationMs'] as int?;
      final errorMessage = meta['errorMessage'] as String?;
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCopyableSection('Method', method),
          _buildCopyableSection('URL', fullUrl),
          _buildCopyableSection('Status', statusCode != null ? '$statusCode${durationMs != null ? '  (${durationMs}ms)' : ''}' : 'FAILED${errorMessage != null ? ' — $errorMessage' : ''}'),
        ],
      );
    } else if (_tabIndex == 1) {
      final requestHeaders = meta['requestHeaders'] as String?;
      final requestBody = meta['requestBody'] as String?;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (requestHeaders != null) _buildCopyableSection('Headers', requestHeaders),
          if (requestBody != null) _buildCopyableSection('Body', requestBody),
          if (requestHeaders == null && requestBody == null)
             const Text('No request data', style: TextStyle(color: Colors.white54, fontSize: 12, decoration: TextDecoration.none)),
        ],
      );
    } else {
      final responseHeaders = meta['responseHeaders'] as String?;
      final responseBody = meta['responseBody'] as String?;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (responseHeaders != null) _buildCopyableSection('Headers', responseHeaders),
          if (responseBody != null) _buildCopyableSection('Body', responseBody),
          if (responseHeaders == null && responseBody == null)
             const Text('No response data', style: TextStyle(color: Colors.white54, fontSize: 12, decoration: TextDecoration.none)),
        ],
      );
    }
  }

  Widget _buildCopyableSection(String title, String content) {
    final decoded = _tryDecodeJson(content);
    final isStructured = decoded is Map || decoded is List;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                ),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: content));
                  _CopiedToastScope.of(context)?.call();
                },
                child: const Icon(Icons.copy_rounded, size: 14, color: Color(0x4DFFFFFF)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isStructured)
            _JsonTreeView(value: decoded)
          else
            Text(
              content,
              style: const TextStyle(
                color: Color(0xE6FFFFFF),
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.4,
                decoration: TextDecoration.none,
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// JSON tree view — DevTools-style expandable Map/List inspector
// ═══════════════════════════════════════════════════════════════════════════

dynamic _tryDecodeJson(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final first = trimmed.codeUnitAt(0);
  if (first != 0x7B /* { */ && first != 0x5B /* [ */) return null;
  try {
    return jsonDecode(trimmed);
  } catch (_) {
    return null;
  }
}

class _JsonTreeView extends StatelessWidget {
  final dynamic value;
  const _JsonTreeView({required this.value});

  @override
  Widget build(BuildContext context) {
    return _JsonNode(
      label: null,
      value: value,
      depth: 0,
      initiallyExpanded: true,
    );
  }
}

class _JsonNode extends StatefulWidget {
  final String? label;
  final dynamic value;
  final int depth;
  final bool initiallyExpanded;

  const _JsonNode({
    required this.label,
    required this.value,
    required this.depth,
    this.initiallyExpanded = false,
  });

  @override
  State<_JsonNode> createState() => _JsonNodeState();
}

class _JsonNodeState extends State<_JsonNode> {
  late bool _expanded = widget.initiallyExpanded;

  static const _baseStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    height: 1.45,
    decoration: TextDecoration.none,
  );

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final isMap = value is Map;
    final isList = value is List;
    final isContainer = isMap || isList;
    final indent = widget.depth * 12.0;

    if (!isContainer) {
      return Padding(
        padding: EdgeInsets.only(left: indent + 14, top: 1, bottom: 1),
        child: SelectableText.rich(
          TextSpan(
            style: _baseStyle,
            children: [
              if (widget.label != null)
                TextSpan(
                  text: '${widget.label}: ',
                  style: const TextStyle(color: Color(0xCCFFFFFF)),
                ),
              TextSpan(
                text: _scalarText(value),
                style: TextStyle(color: _scalarColor(value)),
              ),
            ],
          ),
        ),
      );
    }

    final length = isMap ? value.length : (value as List).length;
    final summary = isMap
        ? 'Map (${length == 1 ? '1 item' : '$length items'})'
        : 'List (${length == 1 ? '1 item' : '$length items'})';

    final canExpand = length > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canExpand ? () => setState(() => _expanded = !_expanded) : null,
          child: Padding(
            padding: EdgeInsets.only(left: indent, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 14,
                  child: Icon(
                    canExpand
                        ? (_expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right)
                        : Icons.remove,
                    size: 14,
                    color: const Color(0x99FFFFFF),
                  ),
                ),
                Flexible(
                  child: RichText(
                    text: TextSpan(
                      style: _baseStyle,
                      children: [
                        if (widget.label != null)
                          TextSpan(
                            text: '${widget.label}: ',
                            style: const TextStyle(color: Color(0xCCFFFFFF)),
                          ),
                        TextSpan(
                          text: summary,
                          style: const TextStyle(color: Color(0x99FFFFFF)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ..._buildChildren(value, isMap),
      ],
    );
  }

  List<Widget> _buildChildren(dynamic value, bool isMap) {
    if (isMap) {
      return (value as Map).entries.map<Widget>((e) {
        return _JsonNode(
          label: '${e.key}',
          value: e.value,
          depth: widget.depth + 1,
        );
      }).toList();
    }
    final list = value as List;
    return List.generate(list.length, (i) {
      return _JsonNode(
        label: '[$i]',
        value: list[i],
        depth: widget.depth + 1,
      );
    });
  }

  String _scalarText(dynamic v) {
    if (v == null) return 'null';
    if (v is String) return '"$v"';
    return v.toString();
  }

  Color _scalarColor(dynamic v) {
    if (v == null) return const Color(0x80FFFFFF);
    if (v is String) return const Color(0xFF8BC34A);
    if (v is bool) return const Color(0xFFCE93D8);
    if (v is num) return const Color(0xFF64B5F6);
    return const Color(0xE6FFFFFF);
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
        _CopiedToastScope.of(context)?.call();
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

