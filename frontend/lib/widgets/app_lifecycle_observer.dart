import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sync_provider.dart';
import '../services/app_logger.dart';

/// Handles app lifecycle events: cleanup on pause/detach, reconnect on resume.
class AppLifecycleObserver extends ConsumerStatefulWidget {
  final Widget child;
  const AppLifecycleObserver({super.key, required this.child});

  @override
  ConsumerState<AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends ConsumerState<AppLifecycleObserver>
    with WidgetsBindingObserver {
  final _logger = AppLogger.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.info('app.lifecycle', logger: 'AppLifecycleObserver', data: {'state': state.name});

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _onBackground();
        break;
      case AppLifecycleState.resumed:
        _onForeground();
        break;
      default:
        break;
    }
  }

  void _onBackground() {
    ref.read(syncServiceProvider).stopPeriodicSync();
  }

  void _onForeground() {
    ref.read(syncServiceProvider)
      ..startPeriodicSync()
      ..sync();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
