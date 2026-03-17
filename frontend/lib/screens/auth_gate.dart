import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/environment.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_lifecycle_observer.dart';
import 'home_screen.dart';
import '../widgets/skeleton_loaders.dart';
import 'login_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // In test mode, skip Firebase Auth entirely
    if (Environment.isTestMode) {
      return const HomeScreen();
    }

    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user != null) {
          // Wrap HomeScreen with lifecycle observer only when authenticated
          return const AppLifecycleObserver(
            child: HomeScreen(),
          );
        }
        return const LoginScreen();
      },
      loading: () => const Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
          child: SkeletonAppShell(),
        ),
      ),
      error: (e, _) => const LoginScreen(),
    );
  }
}
