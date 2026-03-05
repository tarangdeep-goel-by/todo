import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Log level enum.
enum LogLevel { debug, info, warning, error }

/// Singleton structured logger for the app.
/// Outputs JSON one-liners via debugPrint for structured log collection.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static LogLevel level = kDebugMode ? LogLevel.debug : LogLevel.info;

  final String sessionId = const Uuid().v4();
  static const _uuid = Uuid();

  /// Generate a unique trace ID for an API request.
  String generateTraceId() => _uuid.v4();

  void debug(String event, {String? logger, Map<String, dynamic>? data, String? traceId}) {
    _log(LogLevel.debug, event, logger: logger, data: data, traceId: traceId);
  }

  void info(String event, {String? logger, Map<String, dynamic>? data, String? traceId}) {
    _log(LogLevel.info, event, logger: logger, data: data, traceId: traceId);
  }

  void warning(String event, {String? logger, Map<String, dynamic>? data, String? traceId}) {
    _log(LogLevel.warning, event, logger: logger, data: data, traceId: traceId);
  }

  void error(String event, {String? logger, Map<String, dynamic>? data, String? traceId}) {
    _log(LogLevel.error, event, logger: logger, data: data, traceId: traceId);
  }

  void _log(LogLevel lvl, String event, {String? logger, Map<String, dynamic>? data, String? traceId}) {
    if (lvl.index < level.index) return;

    final entry = <String, dynamic>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': lvl.name,
      'event': event,
      'session_id': sessionId,
      'source': 'frontend',
    };
    if (logger != null) entry['logger'] = logger;
    if (traceId != null) entry['trace_id'] = traceId;
    if (data != null) entry['data'] = data;

    debugPrint(jsonEncode(entry));
  }
}
