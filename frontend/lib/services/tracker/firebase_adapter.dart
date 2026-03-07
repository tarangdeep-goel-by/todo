import 'package:firebase_analytics/firebase_analytics.dart';
import 'tracker_event.dart';
import 'tracker_adapter.dart';

/// Sends tracker events to Firebase Analytics.
class FirebaseAdapter implements TrackerAdapter {
  FirebaseAnalytics? _analyticsInstance;

  FirebaseAnalytics? get _analytics {
    if (_analyticsInstance != null) return _analyticsInstance;
    try {
      _analyticsInstance = FirebaseAnalytics.instance;
      return _analyticsInstance;
    } catch (_) {
      return null; // Firebase not initialized (e.g. tests)
    }
  }

  @override
  void trackEvent(TrackerEvent event) {
    _analytics?.logEvent(
      name: event.typeName,
      parameters: event.properties.map((k, v) {
        // Firebase accepts String, int, double, bool — pass native types
        if (v is String || v is int || v is double || v is bool) {
          return MapEntry(k, v);
        }
        return MapEntry(k, v.toString());
      }),
    );
  }

  @override
  void setUserId(String userId) {
    _analytics?.setUserId(id: userId.isEmpty ? null : userId);
  }

  @override
  void setUserProperties(Map<String, String> properties) {
    for (final entry in properties.entries) {
      _analytics?.setUserProperty(name: entry.key, value: entry.value);
    }
  }
}
