import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/tracker/tracker_event.dart';
import 'package:frontend/services/tracker/test_adapter.dart';

/// Assert a screen_view event was fired with the given screen name.
void expectScreenView(String screen) {
  final events = TestAdapter.instance.ofType(TrackerEventType.screenView);
  expect(
    events.any((e) => e.properties['screen'] == screen),
    isTrue,
    reason: 'Expected screen_view for "$screen" but got: ${events.map((e) => e.properties)}',
  );
}

/// Assert a tap event was fired with the given element name.
void expectTap(String element) {
  final events = TestAdapter.instance.ofType(TrackerEventType.tap);
  expect(
    events.any((e) => e.properties['element'] == element),
    isTrue,
    reason: 'Expected tap for "$element" but got: ${events.map((e) => e.properties)}',
  );
}

/// Assert an outcome event was fired with the given type.
void expectOutcome(String type) {
  final events = TestAdapter.instance.ofType(TrackerEventType.outcome);
  expect(
    events.any((e) => e.properties['type'] == type),
    isTrue,
    reason: 'Expected outcome "$type" but got: ${events.map((e) => e.properties)}',
  );
}

/// Get events since a given index mark.
List<TrackerEvent> eventsSince(int mark) => TestAdapter.instance.since(mark);

/// Current event count (use as mark for eventsSince).
int eventMark() => TestAdapter.instance.events.length;
