import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Log level enum.
enum LogLevel { debug, info, warning, error }

/// Singleton structured logger for the app.
/// Outputs JSON one-liners via debugPrint for structured log collection.
/// In release mode, buffers entries and ships to backend every 30 seconds.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static LogLevel level = kDebugMode ? LogLevel.debug : LogLevel.info;

  final String sessionId = const Uuid().v4();
  static const _uuid = Uuid();

  // Log shipping (release mode only)
  final List<Map<String, dynamic>> _buffer = [];
  static const int _maxBuffer = 100;
  static const int _flushThreshold = 50;
  Timer? _flushTimer;
  Dio? _shippingDio;

  /// Initialize log shipping with a configured Dio instance.
  /// Call once after app startup with the same base URL as ApiService.
  void initShipping(Dio dio) {
    if (kDebugMode) return;
    _shippingDio = dio;
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
  }

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

    // Buffer for shipping in release mode
    if (!kDebugMode) {
      _buffer.add(entry);
      if (_buffer.length >= _flushThreshold) {
        flush();
      } else if (_buffer.length > _maxBuffer) {
        // Drop oldest to prevent unbounded growth
        _buffer.removeRange(0, _buffer.length - _maxBuffer);
      }
    }
  }

  /// Ship buffered logs to backend. Drops on failure (no retry for logs).
  Future<void> flush() async {
    if (_buffer.isEmpty || _shippingDio == null) return;

    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();

    try {
      await _shippingDio!.post('/logs', data: {
        'entries': batch.map((e) {
          return {
            'level': e['level'],
            'event': e['event'],
            'logger': e['logger'],
            'data': e['data'],
            'ts': e['ts'],
            'trace_id': e['trace_id'],
          };
        }).toList(),
      });
    } catch (_) {
      // Drop logs on failure — don't retry log shipping
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}
