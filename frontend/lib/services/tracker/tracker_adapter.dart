import 'tracker_event.dart';

/// Interface for tracker backends (Firebase, test capture, debug log).
abstract class TrackerAdapter {
  void trackEvent(TrackerEvent event);
  void setUserId(String userId);
  void setUserProperties(Map<String, String> properties);
}
