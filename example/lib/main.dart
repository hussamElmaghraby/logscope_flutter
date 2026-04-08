import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:logscope_flutter/logscope_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // ──────────────────────────────────────────────────────
  // 1. Initialize Logscope (call once in main)
  // ──────────────────────────────────────────────────────
  Logscope.init(
    appName: 'Logscope Example',
    appVersion: '1.0.0',
    buildNumber: '1',
    captureFlutterErrors: true,
    showErrorToasts: true,
    bufferSize: 500,
  );

  // ──────────────────────────────────────────────────────
  // 2. Register a custom classification rule
  // ──────────────────────────────────────────────────────
  Logscope.classifier.addRule(({
    required message,
    required levelName,
    tag,
    metadata,
  }) {
    if (message.toLowerCase().contains('firebase')) return IssueLayer.server;
    if (message.toLowerCase().contains('stripe')) return IssueLayer.server;
    return null; // let built-in rules decide
  });

  // ──────────────────────────────────────────────────────
  // 3. Wrap your root widget — adds the draggable FAB
  // ──────────────────────────────────────────────────────
  runApp(Logscope.wrap(const LogscopeExampleApp()));
}

class LogscopeExampleApp extends StatelessWidget {
  const LogscopeExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Logscope Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Dio _dio;

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    // ── Attach Logscope Dio interceptor ──
    _dio.interceptors.add(Logscope.dioInterceptor());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          '🔍 Logscope Demo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // ═══════════════════════════════════════════════
            // Section: Basic Logging
            // ═══════════════════════════════════════════════
            _SectionHeader(
              icon: Icons.edit_note_rounded,
              title: 'Basic Logging',
              subtitle: 'Tap to generate logs at different severity levels',
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.bug_report_outlined,
              title: 'Debug Log',
              subtitle: 'General debugging information',
              color: const Color(0xFF74B9FF),
              onTap: () {
                Logscope.d('User tapped the debug button', tag: 'UI');
                _showSnack(context, '📘 Debug log added');
              },
            ),
            _ActionCard(
              icon: Icons.info_outline_rounded,
              title: 'Info Log',
              subtitle: 'Informational status messages',
              color: const Color(0xFF55EFC4),
              onTap: () {
                Logscope.i('App initialized successfully', tag: 'App');
                _showSnack(context, '📗 Info log added');
              },
            ),
            _ActionCard(
              icon: Icons.warning_amber_rounded,
              title: 'Warning Log',
              subtitle: 'Potential issues worth attention',
              color: const Color(0xFFFDCB6E),
              onTap: () {
                Logscope.w(
                  'Cache is 90% full — consider clearing',
                  tag: 'Cache',
                );
                _showSnack(context, '📙 Warning log added');
              },
            ),
            _ActionCard(
              icon: Icons.error_outline_rounded,
              title: 'Error Log',
              subtitle: 'Triggers error toast overlay',
              color: const Color(0xFFFF7675),
              onTap: () {
                try {
                  throw FormatException(
                    'Invalid JSON at position 42',
                  );
                } catch (e, s) {
                  Logscope.e(
                    'Failed to parse server response',
                    tag: 'Parser',
                    error: e,
                    stackTrace: s,
                  );
                }
                _showSnack(context, '📕 Error log added — check error toast!');
              },
            ),

            const SizedBox(height: 28),

            // ═══════════════════════════════════════════════
            // Section: Domain-Specific Logging
            // ═══════════════════════════════════════════════
            _SectionHeader(
              icon: Icons.category_rounded,
              title: 'Domain Logging',
              subtitle: 'Specialized log types for common concerns',
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.navigation_rounded,
              title: 'Navigation Log',
              subtitle: 'Log route pushes, pops, and transitions',
              color: const Color(0xFFA29BFE),
              onTap: () {
                Logscope.nav('Pushed /settings → SettingsScreen');
                _showSnack(context, '🧭 Navigation log added');
              },
            ),
            _ActionCard(
              icon: Icons.account_tree_rounded,
              title: 'BLoC / State Log',
              subtitle: 'Log state management events',
              color: const Color(0xFFE17055),
              onTap: () {
                Logscope.bloc(
                  'CounterCubit → CounterState(count: 42, loading: false)',
                );
                _showSnack(context, '🧊 BLoC state log added');
              },
            ),
            _ActionCard(
              icon: Icons.security_rounded,
              title: 'Security / Auth Log',
              subtitle: 'Log auth events with data redaction',
              color: const Color(0xFFFF6348),
              onTap: () {
                final token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6';
                AppLogger.security(
                  'Token refreshed: ${AppLogger.redact(token)}',
                  tag: 'Auth',
                );
                _showSnack(context, '🔐 Security log added (redacted)');
              },
            ),

            const SizedBox(height: 28),

            // ═══════════════════════════════════════════════
            // Section: HTTP Traffic (Dio)
            // ═══════════════════════════════════════════════
            _SectionHeader(
              icon: Icons.cloud_rounded,
              title: 'HTTP Traffic',
              subtitle: 'Real Dio requests captured as structured cards',
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.cloud_download_rounded,
              title: 'GET — Success (200)',
              subtitle: 'Fetch users from JSONPlaceholder',
              color: const Color(0xFF00B894),
              onTap: () => _makeRequest(
                context,
                () => _dio.get(
                  'https://jsonplaceholder.typicode.com/users',
                  queryParameters: {'_limit': 3},
                ),
                '✅ GET /users succeeded',
              ),
            ),
            _ActionCard(
              icon: Icons.cloud_upload_rounded,
              title: 'POST — Create Resource',
              subtitle: 'POST a new todo item',
              color: const Color(0xFF0984E3),
              onTap: () => _makeRequest(
                context,
                () => _dio.post(
                  'https://jsonplaceholder.typicode.com/todos',
                  data: {
                    'title': 'Test todo from Logscope',
                    'completed': false,
                    'userId': 1,
                  },
                ),
                '✅ POST /todos succeeded',
              ),
            ),
            _ActionCard(
              icon: Icons.cloud_off_rounded,
              title: 'GET — Server Error (500)',
              subtitle: 'Simulate a 500 response',
              color: const Color(0xFFD63031),
              onTap: () => _makeRequest(
                context,
                () => _dio.get('https://httpstat.us/500'),
                '❌ Got 500 — see SERVER layer badge',
              ),
            ),
            _ActionCard(
              icon: Icons.lock_outline_rounded,
              title: 'GET — Auth Error (401)',
              subtitle: 'Simulate an unauthorized response',
              color: const Color(0xFFE17055),
              onTap: () => _makeRequest(
                context,
                () => _dio.get('https://httpstat.us/401'),
                '🔒 Got 401 — see AUTH layer badge',
              ),
            ),
            _ActionCard(
              icon: Icons.timer_off_rounded,
              title: 'GET — Timeout',
              subtitle: 'Request to a slow endpoint',
              color: const Color(0xFFFF9F43),
              onTap: () => _makeRequest(
                context,
                () => _dio.get(
                  'https://httpstat.us/200?sleep=30000',
                  options: Options(
                    receiveTimeout: const Duration(seconds: 2),
                  ),
                ),
                '⏱️ Timeout — see NETWORK layer badge',
              ),
            ),
            _ActionCard(
              icon: Icons.wifi_off_rounded,
              title: 'GET — DNS Failure',
              subtitle: 'Request to non-existent host',
              color: const Color(0xFF636E72),
              onTap: () => _makeRequest(
                context,
                () => _dio.get('https://this-host-definitely-does-not-exist-xyz.com/api'),
                '🌐 DNS failure — see NETWORK layer badge',
              ),
            ),

            const SizedBox(height: 28),

            // ═══════════════════════════════════════════════
            // Section: Layer Classification Demo
            // ═══════════════════════════════════════════════
            _SectionHeader(
              icon: Icons.layers_rounded,
              title: 'Layer Classification',
              subtitle: 'Auto-tagged issue layers based on content',
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.dns_rounded,
              title: '🟥 Server Layer',
              subtitle: 'Logs with server-side error patterns',
              color: const Color(0xFFF44336),
              onTap: () {
                Logscope.e('Internal server error on /api/orders', tag: 'API');
                Logscope.e('Database connection pool exhausted', tag: 'DB');
                Logscope.e('Upstream service returned 502 Bad Gateway',
                    tag: 'Gateway');
                _showSnack(context, '🟥 3 SERVER layer logs added');
              },
            ),
            _ActionCard(
              icon: Icons.signal_wifi_off_rounded,
              title: '🟧 Network Layer',
              subtitle: 'Logs with connectivity/timeout patterns',
              color: const Color(0xFFFF9800),
              onTap: () {
                Logscope.e(
                  'SocketException: Connection refused (errno = 7)',
                  tag: 'Net',
                );
                Logscope.e(
                  'Connection timed out after 30s',
                  tag: 'Net',
                );
                Logscope.e('DNS lookup failed for api.example.com', tag: 'Net');
                _showSnack(context, '🟧 3 NETWORK layer logs added');
              },
            ),
            _ActionCard(
              icon: Icons.phone_android_rounded,
              title: '🟦 Mobile Layer',
              subtitle: 'Logs with client-side error patterns',
              color: const Color(0xFF2196F3),
              onTap: () {
                Logscope.e(
                  'Null check operator used on a null value',
                  tag: 'Widget',
                );
                Logscope.e(
                  'RenderFlex children have non-zero flex but overflow',
                  tag: 'Layout',
                );
                Logscope.e(
                  'FormatException: Unexpected character at position 0',
                  tag: 'Parser',
                );
                _showSnack(context, '🟦 3 MOBILE layer logs added');
              },
            ),
            _ActionCard(
              icon: Icons.vpn_key_rounded,
              title: '🟨 Auth Layer',
              subtitle: 'Logs with authentication/permission patterns',
              color: const Color(0xFFFF5722),
              onTap: () {
                Logscope.e('Token expired — refresh required', tag: 'Auth');
                Logscope.e('Permission denied for resource /admin', tag: 'Auth');
                Logscope.e('Session expired — please login again', tag: 'Auth');
                _showSnack(context, '🟨 3 AUTH layer logs added');
              },
            ),

            const SizedBox(height: 28),

            // ═══════════════════════════════════════════════
            // Section: Custom Classification Rule
            // ═══════════════════════════════════════════════
            _SectionHeader(
              icon: Icons.tune_rounded,
              title: 'Custom Rules',
              subtitle: 'Domain-specific patterns (Firebase, Stripe)',
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.local_fire_department_rounded,
              title: 'Firebase Error',
              subtitle: 'Custom rule → SERVER layer',
              color: const Color(0xFFFFA502),
              onTap: () {
                Logscope.e(
                  'Firebase Firestore: PERMISSION_DENIED on collection /orders',
                  tag: 'Firebase',
                );
                _showSnack(
                  context,
                  '🔥 Firebase error → custom rule → SERVER',
                );
              },
            ),
            _ActionCard(
              icon: Icons.payment_rounded,
              title: 'Stripe Error',
              subtitle: 'Custom rule → SERVER layer',
              color: const Color(0xFF6C5CE7),
              onTap: () {
                Logscope.e(
                  'Stripe: card_declined — insufficient funds',
                  tag: 'Payment',
                );
                _showSnack(
                  context,
                  '💳 Stripe error → custom rule → SERVER',
                );
              },
            ),

            const SizedBox(height: 28),

            // ═══════════════════════════════════════════════
            // Section: Bulk & Stress Test
            // ═══════════════════════════════════════════════
            _SectionHeader(
              icon: Icons.speed_rounded,
              title: 'Bulk Logging',
              subtitle: 'Test ring buffer performance & overflow',
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.flash_on_rounded,
              title: 'Generate 50 Mixed Logs',
              subtitle: 'Burst of debug, info, warning, error logs',
              color: const Color(0xFFE84393),
              onTap: () {
                for (var i = 1; i <= 50; i++) {
                  switch (i % 4) {
                    case 0:
                      Logscope.d('Debug entry #$i — checking state', tag: 'Bulk');
                    case 1:
                      Logscope.i('Info entry #$i — processing', tag: 'Bulk');
                    case 2:
                      Logscope.w('Warning entry #$i — slow query', tag: 'Bulk');
                    case 3:
                      Logscope.e('Error entry #$i — retry failed', tag: 'Bulk');
                  }
                }
                _showSnack(context, '⚡ 50 logs generated — open console to browse');
              },
            ),

            const SizedBox(height: 28),

            // ═══════════════════════════════════════════════
            // Section: Flutter Error Capture
            // ═══════════════════════════════════════════════
            _SectionHeader(
              icon: Icons.error_rounded,
              title: 'Flutter Error Capture',
              subtitle: 'Unhandled exceptions auto-captured by Logscope',
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.dangerous_rounded,
              title: 'Throw Unhandled Exception',
              subtitle: 'Caught by FlutterError.onError hook',
              color: const Color(0xFFEB2F06),
              onTap: () {
                // This will be caught by Logscope's error hook
                Future.delayed(Duration.zero, () {
                  throw StateError(
                    'Example unhandled error — '
                    'Logscope captures this automatically!',
                  );
                });
                _showSnack(
                  context,
                  '💥 Unhandled exception thrown — check error toast',
                );
              },
            ),

            const SizedBox(height: 28),

            // ═══════════════════════════════════════════════
            // Section: Data Redaction
            // ═══════════════════════════════════════════════
            _SectionHeader(
              icon: Icons.visibility_off_rounded,
              title: 'Data Redaction',
              subtitle: 'AppLogger.redact() masks sensitive values',
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.credit_card_rounded,
              title: 'Redact Sensitive Data',
              subtitle: 'Log masked tokens, emails, card numbers',
              color: const Color(0xFF00CEC9),
              onTap: () {
                final token = 'sk_live_abc123def456ghi789';
                final email = 'user@example.com';
                final card = '4242424242424242';

                AppLogger.info(
                  'Token: ${AppLogger.redact(token)}',
                  tag: 'Redaction',
                );
                AppLogger.info(
                  'Email: ${AppLogger.redact(email)}',
                  tag: 'Redaction',
                );
                AppLogger.info(
                  'Card: ${AppLogger.redact(card, visibleChars: 4)}',
                  tag: 'Redaction',
                );
                _showSnack(context, '🔒 Redacted logs added — check console');
              },
            ),

            const SizedBox(height: 28),

            // ═══════════════════════════════════════════════
            // Hint
            // ═══════════════════════════════════════════════
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    color: theme.colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Tap the floating bug button 🐛 '
                      'to open the full debug console. '
                      'Filter, search, and share your logs!',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _makeRequest(
    BuildContext context,
    Future<Response> Function() request,
    String successMessage,
  ) async {
    try {
      await request();
      if (context.mounted) _showSnack(context, successMessage);
    } on DioException catch (_) {
      if (context.mounted) {
        _showSnack(context, '❌ Request failed — check console for details');
      }
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Reusable widgets
// ═══════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
