import 'tracker_event.dart';
import 'tracker_adapter.dart';

/// Captures events in-memory for E2E test assertions.
class TestAdapter implements TrackerAdapter {
  TestAdapter._();
  static final TestAdapter instance = TestAdapter._();

  final List<TrackerEvent> events = [];

  @override
  void trackEvent(TrackerEvent event) {
    events.add(event);
  }

  @override
  void setUserId(String userId) {}

  @override
  void setUserProperties(Map<String, String> properties) {}

  /// Clear captured events (call in setUp).
  void clear() => events.clear();

  /// All events of a specific type.
  List<TrackerEvent> ofType(TrackerEventType type) =>
      events.where((e) => e.type == type).toList();

  /// Events captured since a given index.
  List<TrackerEvent> since(int index) =>
      index < events.length ? events.sublist(index) : [];
}
