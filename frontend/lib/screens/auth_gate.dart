import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../main.dart' show kTestMode;
import '../providers/auth_provider.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // In test mode, skip Firebase Auth entirely
    if (kTestMode) {
      return const HomeScreen();
    }

    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user != null) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
      loading: () => const Scaffold(
        backgroundColor: AppColors.darkBg,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.darkText,
          ),
        ),
      ),
      error: (e, _) => const LoginScreen(),
    );
  }
}
