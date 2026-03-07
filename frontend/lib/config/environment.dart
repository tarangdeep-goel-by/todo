/// Runtime API URL configuration with fallback chain.
class Environment {
  static String? _runtimeOverride;

  /// Set by remote config or local override.
  static void setApiBaseUrl(String url) {
    _runtimeOverride = url;
  }

  /// API base URL with fallback chain:
  /// Runtime override > --dart-define > default
  static String get apiBaseUrl {
    if (_runtimeOverride != null && _runtimeOverride!.isNotEmpty) {
      return _runtimeOverride!;
    }
    // Fall back to build-time define or default
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8001/api',
    );
  }
}
