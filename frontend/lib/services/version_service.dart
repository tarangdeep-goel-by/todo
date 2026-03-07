import 'package:dio/dio.dart';
import 'app_logger.dart';

/// Checks client version compatibility with the backend.
class VersionService {
  static const _currentVersion = '1.0.0';

  /// Check if this client version is supported by the backend.
  /// Returns true if supported, false if force-update needed.
  /// Never blocks app startup on failure.
  static Future<bool> checkCompatibility(Dio dio) async {
    try {
      final response = await dio.get('/version');
      final minVersion = response.data['min_client_version'] as String?;
      if (minVersion == null) return true;

      return !_isOlderThan(_currentVersion, minVersion);
    } catch (e) {
      AppLogger.instance.warning(
        'version.check_failed',
        logger: 'VersionService',
        data: {'error': e.toString()},
      );
      // Don't block app on version check failure
      return true;
    }
  }

  /// Compare semver strings. Returns true if a < b.
  static bool _isOlderThan(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList();
    final bParts = b.split('.').map(int.parse).toList();
    for (int i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av < bv) return true;
      if (av > bv) return false;
    }
    return false;
  }
}
