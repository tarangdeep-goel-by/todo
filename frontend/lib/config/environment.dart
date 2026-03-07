/// Centralised environment configuration.
///
/// All compile-time (`--dart-define`) and runtime overrides live here.
/// No other file should call `bool.fromEnvironment` or
/// `String.fromEnvironment` directly.
class Environment {
  // ------------------------------------------------------------------
  // Compile-time flags (--dart-define)
  // ------------------------------------------------------------------

  /// Integration-test mode: skips Firebase Auth, uses static test tokens.
  /// Pass `--dart-define=TEST_MODE=true` to enable.
  static const bool isTestMode =
      bool.fromEnvironment('TEST_MODE', defaultValue: false);

  // ------------------------------------------------------------------
  // API base URL (runtime override > dart-define > default)
  // ------------------------------------------------------------------

  static String? _runtimeOverride;

  /// Set by remote config or local override.
  static void setApiBaseUrl(String url) {
    _runtimeOverride = url;
  }

  static String get apiBaseUrl {
    final url = _runtimeOverride != null && _runtimeOverride!.isNotEmpty
        ? _runtimeOverride!
        : const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://10.0.2.2:8001/api',
          );
    if (!_isSecureOrLocalUrl(url)) {
      throw StateError('Production API URL must use HTTPS: $url');
    }
    return url;
  }

  static bool _isSecureOrLocalUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    return _isLocalHost(uri.host);
  }

  static bool _isLocalHost(String host) {
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return true;
    }

    final parts = host.split('.');
    if (parts.length != 4) return false;

    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null)) return false;

    return octets[0] == 10 ||
        (octets[0] == 192 && octets[1] == 168) ||
        (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31);
  }
}
