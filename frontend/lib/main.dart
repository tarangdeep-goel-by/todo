import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'config/theme.dart';
import 'screens/auth_gate.dart';
import 'services/auth_interceptor.dart';
import 'widgets/reauth_dialog.dart';

/// Compile-time flag: `flutter test --dart-define=TEST_MODE=true`
const bool kTestMode = bool.fromEnvironment('TEST_MODE', defaultValue: false);

final navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  }

  runApp(
    const ProviderScope(
      child: AmbleApp(),
    ),
  );
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
