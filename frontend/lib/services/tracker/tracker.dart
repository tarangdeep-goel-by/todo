import 'tracker_event.dart';
import 'tracker_adapter.dart';

/// Singleton tracker that fans events to registered adapters.
class Tracker {
  Tracker._();
  static final Tracker instance = Tracker._();

  final List<TrackerAdapter> _adapters = [];

  /// Initialize with adapters. Call once at app startup.
  void init(List<TrackerAdapter> adapters) {
    _adapters.clear();
    _adapters.addAll(adapters);
  }

  void _track(TrackerEvent event) {
    for (final adapter in _adapters) {
      adapter.trackEvent(event);
    }
  }

  void screenView({
    required String screen,
    String? source,
    String? viewMode,
  }) {
    final props = <String, Object>{'screen': screen};
    if (source != null) props['source'] = source;
    if (viewMode != null) props['view_mode'] = viewMode;
    _track(TrackerEvent(type: TrackerEventType.screenView, properties: props));
  }

  void tap({
    required String element,
    String? action,
    String? screen,
    String? target,
  }) {
    final props = <String, Object>{'element': element};
    if (action != null) props['action'] = action;
    if (screen != null) props['screen'] = screen;
    if (target != null) props['target'] = target;
    _track(TrackerEvent(type: TrackerEventType.tap, properties: props));
  }

  void impression({
    required String component,
    String? screen,
    int? itemCount,
    String? content,
  }) {
    final props = <String, Object>{'component': component};
    if (screen != null) props['screen'] = screen;
    if (itemCount != null) props['item_count'] = itemCount;
    if (content != null) props['content'] = content;
    _track(TrackerEvent(type: TrackerEventType.impression, properties: props));
  }

  void outcome({
    required String type,
    bool? success,
    String? method,
    String? category,
    int? count,
    String? detail,
  }) {
    final props = <String, Object>{'type': type};
    if (success != null) props['success'] = success;
    if (method != null) props['method'] = method;
    if (category != null) props['category'] = category;
    if (count != null) props['count'] = count;
    if (detail != null) props['detail'] = detail;
    _track(TrackerEvent(type: TrackerEventType.outcome, properties: props));
  }

  void setUserId(String userId) {
    for (final adapter in _adapters) {
      adapter.setUserId(userId);
    }
  }

  void setUserProperties(Map<String, String> properties) {
    for (final adapter in _adapters) {
      adapter.setUserProperties(properties);
    }
  }
}
