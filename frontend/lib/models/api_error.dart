/// Structured API error with type classification for retry/display logic.
enum ApiErrorType { network, timeout, auth, validation, server }

class ApiError implements Exception {
  final String message;
  final ApiErrorType type;
  final int? statusCode;

  const ApiError({
    required this.message,
    required this.type,
    this.statusCode,
  });

  bool get isRetryable =>
      type == ApiErrorType.network ||
      type == ApiErrorType.timeout ||
      type == ApiErrorType.server;

  @override
  String toString() => 'ApiError($type, $statusCode): $message';
}
