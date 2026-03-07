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
    if (_runtimeOverride != null && _runtimeOverride!.isNotEmpty) {
      return _runtimeOverride!;
    }
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8001/api',
    );
  }
}
