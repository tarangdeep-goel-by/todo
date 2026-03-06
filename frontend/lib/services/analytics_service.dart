import 'package:firebase_analytics/firebase_analytics.dart';

/// Singleton analytics service wrapping Firebase Analytics.
/// Type-safe event methods — no raw string event names outside this file.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

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

  void setUserId(String uid) {
    _analytics?.setUserId(id: uid);
  }

  void setUserProperties({int? taskCount, int? categoryCount}) {
    if (taskCount != null) {
      _analytics?.setUserProperty(name: 'task_count', value: taskCount.toString());
    }
    if (categoryCount != null) {
      _analytics?.setUserProperty(name: 'category_count', value: categoryCount.toString());
    }
  }

  void trackTaskCreated({required String source, String? category, bool hasDueDate = false}) {
    final params = <String, Object>{
      'source': source,
      'has_due_date': hasDueDate.toString(),
    };
    if (category != null) params['category'] = category;
    _analytics?.logEvent(name: 'task_created', parameters: params);
  }

  void trackTaskCompleted({required String source, int? daysToComplete}) {
    final params = <String, Object>{
      'source': source,
    };
    if (daysToComplete != null) params['days_to_complete'] = daysToComplete;
    _analytics?.logEvent(name: 'task_completed', parameters: params);
  }

  void trackBrainDumpSubmitted({required int proposalCount, required List<String> actionTypes}) {
    _analytics?.logEvent(name: 'brain_dump_submitted', parameters: {
      'proposal_count': proposalCount,
      'action_types': actionTypes.join(','),
    });
  }

  void trackRambleStarted() {
    _analytics?.logEvent(name: 'ramble_started');
  }

  void trackRambleCompleted({required int durationSeconds, required int transcriptLength}) {
    _analytics?.logEvent(name: 'ramble_completed', parameters: {
      'duration_seconds': durationSeconds,
      'transcript_length': transcriptLength,
    });
  }

  void trackViewSwitched({required String from, required String to}) {
    _analytics?.logEvent(name: 'view_switched', parameters: {
      'from': from,
      'to': to,
    });
  }

  void trackSearchPerformed({required int queryLength, required int resultCount}) {
    _analytics?.logEvent(name: 'search_performed', parameters: {
      'query_length': queryLength,
      'result_count': resultCount,
    });
  }

  void trackFilterApplied({String? category, String? priority, String? status}) {
    final params = <String, Object>{};
    if (category != null) params['category'] = category;
    if (priority != null) params['priority'] = priority;
    if (status != null) params['status'] = status;
    _analytics?.logEvent(name: 'filter_applied', parameters: params);
  }
}
