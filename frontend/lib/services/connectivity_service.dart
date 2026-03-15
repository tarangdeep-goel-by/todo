import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'app_logger.dart';

/// Wraps connectivity_plus with actual backend reachability checks.
///
/// [isOnline] is true only when both the network interface is up AND
/// the backend has been recently reachable. API callers report
/// reachability via [reportSuccess] / [reportFailure].
class ConnectivityService {
  final Connectivity _connectivity;
  final String _healthUrl;
  final _controller = StreamController<bool>.broadcast();
  final _logger = AppLogger.instance;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _recheckTimer;

  bool _hasInterface = true;
  bool _isReachable = true;
  bool _disposed = false;

  ConnectivityService({
    Connectivity? connectivity,
    required String healthUrl,
  })  : _connectivity = connectivity ?? Connectivity(),
        _healthUrl = healthUrl;

  bool get isOnline => _hasInterface && _isReachable;
  Stream<bool> get onStatusChange => _controller.stream;

  /// Start listening. Call once on app start.
  Future<void> initialize() async {
    final results = await _connectivity.checkConnectivity();
    _hasInterface = _hasConnection(results);
    // Don't block startup — check reachability in background
    if (_hasInterface) {
      _pingHealth();
    } else {
      _updateOnline();
    }

    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final hadInterface = _hasInterface;
      _hasInterface = _hasConnection(results);

      if (!_hasInterface) {
        // Interface gone — immediately offline
        _isReachable = false;
        _recheckTimer?.cancel();
        _updateOnline();
      } else if (!hadInterface && _hasInterface) {
        // Interface came back — verify reachability before declaring online
        _pingHealth();
      }
    });
  }

  /// Called by SyncService / API layer on successful backend communication.
  void reportSuccess() {
    _recheckTimer?.cancel();
    if (!_isReachable) {
      _isReachable = true;
      _updateOnline();
    }
  }

  /// Called by SyncService / API layer on network/timeout errors.
  void reportFailure() {
    if (_isReachable) {
      _isReachable = false;
      _updateOnline();
    }
    _scheduleRecheck();
  }

  /// Ping the backend health endpoint.
  Future<void> _pingHealth() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(Uri.parse(_healthUrl));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();

      if (_disposed) return;
      if (response.statusCode >= 200 && response.statusCode < 500) {
        if (!_isReachable) {
          _isReachable = true;
          _updateOnline();
        }
        _recheckTimer?.cancel();
      } else {
        _onPingFailed();
      }
    } catch (_) {
      if (!_disposed) _onPingFailed();
    } finally {
      client.close(force: true);
    }
  }

  void _onPingFailed() {
    if (_isReachable) {
      _isReachable = false;
      _updateOnline();
    }
    _scheduleRecheck();
  }

  /// Periodically retry health checks when unreachable (30s interval).
  void _scheduleRecheck() {
    _recheckTimer?.cancel();
    _recheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (_hasInterface) {
          _pingHealth();
        }
      },
    );
  }

  void _updateOnline() {
    final online = isOnline;
    _logger.debug('connectivity.state', logger: 'Connectivity', data: {
      'hasInterface': _hasInterface,
      'isReachable': _isReachable,
      'isOnline': online,
    });
    _controller.add(online);
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _recheckTimer?.cancel();
    _controller.close();
  }
}
