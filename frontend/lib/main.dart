import 'dart:ui';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'config/environment.dart';
import 'config/theme.dart';
import 'screens/auth_gate.dart';
import 'services/auth_interceptor.dart';
import 'services/audio_service.dart';
import 'services/notification_service.dart';
import 'services/tracker/tracker.dart';
import 'services/tracker/firebase_adapter.dart';
import 'services/tracker/dev_log_adapter.dart';
import 'services/tracker/test_adapter.dart';
import 'widgets/reauth_dialog.dart';
import 'widgets/task_detail_overlay.dart';
import 'providers/local_data_provider.dart';
import 'screens/ramble_screen.dart';

/// Compile-time flag: `flutter test --dart-define=TEST_MODE=true`
/// Canonical source is [Environment.isTestMode]; this alias exists for
/// files that already import `main.dart show kTestMode`.
const bool kTestMode = Environment.isTestMode;

final navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // M8: User-friendly error widget instead of red error screen
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Something went wrong',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Please restart the app',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  };

  if (!kTestMode) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // FCM background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Crashlytics error handlers
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    // Wire reauth dialog to auth interceptor
    AuthInterceptor.onReauthRequired = () {
      final context = navigatorKey.currentContext;
      if (context != null) {
        ReauthDialog.show(context);
      }
    };

    // Initialize local database encryption (key + old-DB cleanup)
    await initDatabaseEncryption();

    // Clean up old audio temp files
    AudioService.cleanupOldRecordings();

    // Initialize tracker with Firebase + DevLog
    Tracker.instance.init([FirebaseAdapter(), DevLogAdapter()]);

    // M2: Deep link handler for amble:// URI scheme
    _initDeepLinks();

    // Wire notification tap → task detail navigation
    NotificationService.instance.onNotificationTap = (taskId) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        showTaskDetailOverlay(context, taskId: taskId);
      }
    };
  } else {
    // Test mode: use TestAdapter for E2E assertions + DevLog for console visibility
    Tracker.instance.init([TestAdapter.instance, DevLogAdapter()]);
  }

  runApp(
    const ProviderScope(
      child: AmbleApp(),
    ),
  );
}

Uri? _pendingDeepLink;
bool _deepLinksReady = false;

/// Whether a deep link is waiting to be processed (used by HomeScreen
/// to show a blank frame instead of flashing home content).
bool get hasPendingDeepLink => _pendingDeepLink != null;

void _initDeepLinks() {
  final appLinks = AppLinks();

  // Handle link when app is already running (or arriving during cold start).
  // During cold start, AuthGate hasn't resolved yet — pushing a route now
  // would be covered when AuthGate rebuilds with HomeScreen. Defer until
  // HomeScreen signals readiness via processPendingDeepLink().
  appLinks.uriLinkStream.listen((Uri uri) {
    if (_deepLinksReady) {
      _handleDeepLink(uri);
    } else {
      _pendingDeepLink = uri;
    }
  });

  // Handle link that launched the app — defer if UI isn't ready yet
  appLinks.getInitialLink().then((Uri? uri) {
    if (uri != null) {
      if (_deepLinksReady) {
        _handleDeepLink(uri);
      } else {
        _pendingDeepLink = uri;
      }
    }
  });
}

void processPendingDeepLink() {
  _deepLinksReady = true;
  final uri = _pendingDeepLink;
  if (uri != null) {
    _pendingDeepLink = null;
    _handleDeepLink(uri);
  }
}

void _handleDeepLink(Uri uri) {
  // Support amble://task/{taskId}
  // Dart Uri.parse treats "amble://task/123" as host="task", path="/123"
  // so we check host == 'task' and extract taskId from pathSegments.
  if (uri.scheme != 'amble') return;
  if (uri.host == 'task' && uri.pathSegments.length == 1) {
    final taskId = uri.pathSegments[0];
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Validate UUID format before showing overlay
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (!uuidRegex.hasMatch(taskId)) return;

    showTaskDetailOverlay(context, taskId: taskId);
  } else if (uri.host == 'ramble') {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    // Double-push guard: don't push if already on RambleScreen
    String? currentRouteName;
    navigator.popUntil((route) {
      currentRouteName = route.settings.name;
      return true;
    });
    if (currentRouteName == '/ramble') return;

    navigator.push(
      MaterialPageRoute(
        builder: (_) => const RambleScreen(),
        settings: const RouteSettings(name: '/ramble'),
      ),
    );
  }
}

class AmbleApp extends ConsumerWidget {
  const AmbleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Amble',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.darkBg,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.dark,
      home: const AuthGate(),
    );
  }
}
