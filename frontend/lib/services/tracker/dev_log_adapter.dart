import 'package:flutter/foundation.dart';
import 'tracker_event.dart';
import 'tracker_adapter.dart';

/// Prints tracker events to debug console in debug mode.
class DevLogAdapter implements TrackerAdapter {
  @override
  void trackEvent(TrackerEvent event) {
    if (kDebugMode) {
      debugPrint('[Tracker] ${event.typeName}: ${event.properties}');
    }
  }

  @override
  void setUserId(String userId) {
    if (kDebugMode) {
      debugPrint('[Tracker] setUserId: $userId');
    }
  }

  @override
  void setUserProperties(Map<String, String> properties) {
    if (kDebugMode) {
      debugPrint('[Tracker] setUserProperties: $properties');
    }
  }
}
