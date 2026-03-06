import 'dart:math';
import '../models/api_error.dart';

/// Retries [fn] with exponential backoff on retryable [ApiError]s.
/// Base delay doubles each attempt with ±25% jitter.
Future<T> retryWithBackoff<T>(
  Future<T> Function() fn, {
  int maxRetries = 2,
  Duration baseDelay = const Duration(milliseconds: 500),
}) async {
  final random = Random();
  for (int attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } on ApiError catch (e) {
      if (!e.isRetryable || attempt == maxRetries) rethrow;
      final delayMs = baseDelay.inMilliseconds * (1 << attempt);
      final jitter = (delayMs * 0.25 * (random.nextDouble() * 2 - 1)).round();
      await Future.delayed(Duration(milliseconds: delayMs + jitter));
    }
  }
  // Unreachable — loop always returns or rethrows
  throw StateError('retryWithBackoff: unreachable');
}
