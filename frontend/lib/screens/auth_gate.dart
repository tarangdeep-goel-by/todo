import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/environment.dart';
import '../config/theme.dart';
import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../services/version_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _versionChecked = false;
  bool _compatible = true;

  void _checkVersion() {
    if (_versionChecked) return;
    _versionChecked = true;
    final dio = ref.read(apiServiceProvider).dio;
    VersionService.checkCompatibility(dio).then((ok) {
      if (!ok && mounted) {
        setState(() => _compatible = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // In test mode, skip Firebase Auth entirely
    if (Environment.isTestMode) {
      return const HomeScreen();
    }

    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user != null) {
          _checkVersion();
          if (!_compatible) {
            return _ForceUpdateScreen();
          }
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

class _ForceUpdateScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.system_update, size: 64, color: AppColors.secondaryText),
              const SizedBox(height: 24),
              Text(
                'Update Required',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Please update the app to continue.',
                style: TextStyle(fontSize: 16, color: AppColors.secondaryText),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
