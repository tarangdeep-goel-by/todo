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
        // Firebase accepts String, int, double only — convert bools to int
        if (v is String || v is int || v is double) {
          return MapEntry(k, v);
        }
        if (v is bool) return MapEntry(k, v ? 1 : 0);
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
