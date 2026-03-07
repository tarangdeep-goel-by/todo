import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_logger.dart';

/// Dio interceptor that adds Firebase ID token, trace headers,
/// and structured request/response logging.
class AuthInterceptor extends Interceptor {
  final _logger = AppLogger.instance;
  Dio? _dio;

  // Token refresh synchronization
  bool _isRefreshing = false;
  final List<_PendingRequest> _pendingRequests = [];

  /// Attach the Dio instance for authenticated retries.
  void attachDio(Dio dio) => _dio = dio;

  /// Callback invoked when token refresh fails and re-auth is needed.
  static void Function()? onReauthRequired;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Generate trace ID and attach headers
    final traceId = _logger.generateTraceId();
    options.headers['X-Request-ID'] = traceId;
    options.headers['X-Session-ID'] = _logger.sessionId;
    options.extra['trace_id'] = traceId;

    // In test mode, use a static test token instead of Firebase Auth
    if (const bool.fromEnvironment('TEST_MODE', defaultValue: false)) {
      options.headers['Authorization'] = 'Bearer test-token-e2e';
      _logger.info('api.request', logger: 'AuthInterceptor', traceId: traceId,
          data: {'method': options.method, 'path': options.path, 'auth': 'test-token'});
      handler.next(options);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final token = await user.getIdToken();
        if (token == null) {
          _logger.warning('api.error', logger: 'AuthInterceptor', traceId: traceId,
              data: {'reason': 'getIdToken returned null'});
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.unknown,
              message: 'Failed to obtain authentication token',
            ),
          );
          return;
        }
        options.headers['Authorization'] = 'Bearer $token';
      } catch (e) {
        _logger.error('api.error', logger: 'AuthInterceptor', traceId: traceId,
            data: {'reason': 'token_error', 'error': e.toString()});
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.unknown,
            message: 'Authentication token error: $e',
          ),
        );
        return;
      }
    } else {
      _logger.debug('api.request', logger: 'AuthInterceptor', traceId: traceId,
          data: {'note': 'no_auth'});
    }

    _logger.info('api.request', logger: 'AuthInterceptor', traceId: traceId,
        data: {'method': options.method, 'path': options.path});
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final traceId = response.requestOptions.extra['trace_id'] as String?;
    _logger.info('api.response', logger: 'AuthInterceptor', traceId: traceId,
        data: {
          'method': response.requestOptions.method,
          'path': response.requestOptions.path,
          'status_code': response.statusCode,
        });
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final traceId = err.requestOptions.extra['trace_id'] as String?;
    _logger.error('api.error', logger: 'AuthInterceptor', traceId: traceId,
        data: {
          'method': err.requestOptions.method,
          'path': err.requestOptions.path,
          'status_code': err.response?.statusCode,
          'type': err.type.name,
        });

    if (err.response?.statusCode != 401 ||
        const bool.fromEnvironment('TEST_MODE', defaultValue: false)) {
      handler.next(err);
      return;
    }

    _logger.warning('auth.token_expired', logger: 'AuthInterceptor', traceId: traceId);

    // If already refreshing, queue this request
    if (_isRefreshing) {
      _pendingRequests.add(_PendingRequest(err.requestOptions, handler));
      return;
    }

    _isRefreshing = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final newToken = await user.getIdToken(true);
        if (newToken != null) {
          _logger.info('auth.token_refreshed', logger: 'AuthInterceptor', traceId: traceId);

          // Retry the original request with the SAME Dio instance
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer $newToken';
          final retryDio = _dio ?? Dio();
          final response = await retryDio.fetch(opts);

          // Retry all queued requests with the new token
          _retryPendingRequests(newToken, retryDio);
          _isRefreshing = false;

          handler.resolve(response);
          return;
        }
      } catch (refreshError) {
        _logger.error('auth.refresh_failed', logger: 'AuthInterceptor', traceId: traceId,
            data: {'error': refreshError.toString()});
      }
    }

    // Refresh failed — reject all pending requests
    _rejectPendingRequests();
    _isRefreshing = false;

    if (onReauthRequired != null) {
      onReauthRequired!();
    } else {
      await FirebaseAuth.instance.signOut();
    }

    handler.next(err);
  }

  void _retryPendingRequests(String token, Dio dio) {
    final pending = List<_PendingRequest>.from(_pendingRequests);
    _pendingRequests.clear();
    for (final req in pending) {
      req.options.headers['Authorization'] = 'Bearer $token';
      dio.fetch(req.options).then(
        (response) => req.handler.resolve(response),
        onError: (e) => req.handler.next(
          e is DioException ? e : DioException(requestOptions: req.options),
        ),
      );
    }
  }

  void _rejectPendingRequests() {
    final pending = List<_PendingRequest>.from(_pendingRequests);
    _pendingRequests.clear();
    for (final req in pending) {
      req.handler.next(DioException(
        requestOptions: req.options,
        type: DioExceptionType.unknown,
        message: 'Token refresh failed',
      ));
    }
  }
}

class _PendingRequest {
  final RequestOptions options;
  final ErrorInterceptorHandler handler;
  _PendingRequest(this.options, this.handler);
}
