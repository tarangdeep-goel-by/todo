/// Event types for the unified tracker.
enum TrackerEventType { screenView, tap, impression, outcome }

/// Immutable event data class.
class TrackerEvent {
  final TrackerEventType type;
  final Map<String, Object> properties;
  final DateTime timestamp;

  TrackerEvent({
    required this.type,
    required this.properties,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convenience: event type as snake_case string for adapters.
  String get typeName => switch (type) {
    TrackerEventType.screenView => 'app_screen_view',
    TrackerEventType.tap => 'tap',
    TrackerEventType.impression => 'impression',
    TrackerEventType.outcome => 'outcome',
  };

  @override
  String toString() => 'TrackerEvent($typeName, $properties)';
}
