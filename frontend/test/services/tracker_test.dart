import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/tracker/tracker.dart';
import 'package:frontend/services/tracker/tracker_event.dart';
import 'package:frontend/services/tracker/tracker_adapter.dart';
import 'package:frontend/services/tracker/test_adapter.dart';

/// Simple adapter that captures calls for assertions.
class _SpyAdapter implements TrackerAdapter {
  final List<TrackerEvent> events = [];
  String? lastUserId;
  Map<String, String>? lastUserProperties;

  @override
  void trackEvent(TrackerEvent event) => events.add(event);

  @override
  void setUserId(String userId) => lastUserId = userId;

  @override
  void setUserProperties(Map<String, String> properties) =>
      lastUserProperties = properties;
}

void main() {
  late _SpyAdapter spy;

  setUp(() {
    spy = _SpyAdapter();
    Tracker.instance.init([spy]);
  });

  group('Tracker', () {
    test('screenView dispatches to adapter', () {
      Tracker.instance.screenView(screen: 'home', source: 'app_launch');

      expect(spy.events, hasLength(1));
      final event = spy.events.first;
      expect(event.type, TrackerEventType.screenView);
      expect(event.typeName, 'screen_view');
      expect(event.properties['screen'], 'home');
      expect(event.properties['source'], 'app_launch');
    });

    test('tap dispatches to adapter', () {
      Tracker.instance.tap(element: 'home_tab', screen: 'home', target: 'node');

      expect(spy.events, hasLength(1));
      final event = spy.events.first;
      expect(event.type, TrackerEventType.tap);
      expect(event.typeName, 'tap');
      expect(event.properties['element'], 'home_tab');
      expect(event.properties['screen'], 'home');
      expect(event.properties['target'], 'node');
    });

    test('impression dispatches to adapter', () {
      Tracker.instance.impression(
        component: 'proposal_cards',
        screen: 'ramble',
        itemCount: 3,
      );

      expect(spy.events, hasLength(1));
      final event = spy.events.first;
      expect(event.type, TrackerEventType.impression);
      expect(event.typeName, 'impression');
      expect(event.properties['component'], 'proposal_cards');
      expect(event.properties['item_count'], 3);
    });

    test('outcome dispatches to adapter', () {
      Tracker.instance.outcome(
        type: 'task_completed',
        method: 'toggle',
        category: 'career',
      );

      expect(spy.events, hasLength(1));
      final event = spy.events.first;
      expect(event.type, TrackerEventType.outcome);
      expect(event.typeName, 'outcome');
      expect(event.properties['type'], 'task_completed');
      expect(event.properties['method'], 'toggle');
      expect(event.properties['category'], 'career');
    });

    test('null optional properties are omitted', () {
      Tracker.instance.screenView(screen: 'home');

      final event = spy.events.first;
      expect(event.properties.containsKey('source'), isFalse);
      expect(event.properties.containsKey('view_mode'), isFalse);
    });

    test('dispatches to multiple adapters', () {
      final spy2 = _SpyAdapter();
      Tracker.instance.init([spy, spy2]);

      Tracker.instance.tap(element: 'flat_tab');

      expect(spy.events, hasLength(1));
      expect(spy2.events, hasLength(1));
    });

    test('setUserId dispatches to all adapters', () {
      final spy2 = _SpyAdapter();
      Tracker.instance.init([spy, spy2]);

      Tracker.instance.setUserId('user-123');

      expect(spy.lastUserId, 'user-123');
      expect(spy2.lastUserId, 'user-123');
    });

    test('setUserProperties dispatches to all adapters', () {
      Tracker.instance.setUserProperties({'task_count': '5'});

      expect(spy.lastUserProperties, {'task_count': '5'});
    });

    test('init replaces adapters', () {
      final spy2 = _SpyAdapter();
      Tracker.instance.init([spy2]);

      Tracker.instance.tap(element: 'test');

      expect(spy.events, isEmpty); // old adapter no longer receives
      expect(spy2.events, hasLength(1));
    });
  });

  group('TestAdapter', () {
    test('captures events and supports ofType', () {
      final adapter = TestAdapter.instance;
      adapter.clear();

      Tracker.instance.init([adapter]);
      Tracker.instance.screenView(screen: 'home');
      Tracker.instance.tap(element: 'btn');
      Tracker.instance.tap(element: 'btn2');

      expect(adapter.events, hasLength(3));
      expect(adapter.ofType(TrackerEventType.screenView), hasLength(1));
      expect(adapter.ofType(TrackerEventType.tap), hasLength(2));
    });

    test('since returns events from index', () {
      final adapter = TestAdapter.instance;
      adapter.clear();

      Tracker.instance.init([adapter]);
      Tracker.instance.screenView(screen: 'a');
      final mark = adapter.events.length;
      Tracker.instance.tap(element: 'b');

      final recent = adapter.since(mark);
      expect(recent, hasLength(1));
      expect(recent.first.properties['element'], 'b');
    });

    test('clear removes all events', () {
      final adapter = TestAdapter.instance;
      Tracker.instance.init([adapter]);
      Tracker.instance.tap(element: 'x');
      adapter.clear();
      expect(adapter.events, isEmpty);
    });
  });

  group('TrackerEvent', () {
    test('toString includes type and properties', () {
      final event = TrackerEvent(
        type: TrackerEventType.tap,
        properties: {'element': 'btn'},
      );
      expect(event.toString(), contains('tap'));
      expect(event.toString(), contains('element'));
    });

    test('timestamp is auto-set', () {
      final before = DateTime.now();
      final event = TrackerEvent(
        type: TrackerEventType.screenView,
        properties: {'screen': 'test'},
      );
      expect(event.timestamp.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
    });
  });
}
