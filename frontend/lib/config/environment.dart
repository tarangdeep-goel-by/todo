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
    assert(
      _isLocalUrl(url) || url.startsWith('https://'),
      'Production API URL must use HTTPS: $url',
    );
    return url;
  }

  /// Returns true for localhost / emulator / LAN development URLs.
  static bool _isLocalUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host;
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '10.0.2.2' ||
        host.startsWith('192.168.') ||
        host.startsWith('10.');
  }
}
