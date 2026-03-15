import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/environment.dart';
import '../services/connectivity_service.dart';
import 'sync_provider.dart';

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  // Derive health URL from API base (e.g. http://host:port/api → http://host:port/health)
  final apiBase = Environment.apiBaseUrl;
  final uri = Uri.parse(apiBase);
  final healthUrl = uri.replace(path: '/health').toString();

  final service = ConnectivityService(healthUrl: healthUrl);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Reactive provider: true = online, false = offline.
/// Triggers sync on reconnect.
final isOnlineProvider = StateNotifierProvider<IsOnlineNotifier, bool>((ref) {
  return IsOnlineNotifier(ref);
});

class IsOnlineNotifier extends StateNotifier<bool> {
  final Ref _ref;
  StreamSubscription<bool>? _sub;

  IsOnlineNotifier(this._ref) : super(true) {
    _init();
  }

  Future<void> _init() async {
    final connectivity = _ref.read(connectivityServiceProvider);
    await connectivity.initialize();
    state = connectivity.isOnline;

    _sub = connectivity.onStatusChange.listen((online) {
      state = online;
      if (online) {
        // Reconnected — trigger sync with retry (network may be flaky)
        _ref.read(syncServiceProvider).syncWithRetry();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
