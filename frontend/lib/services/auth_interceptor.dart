import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_logger.dart';

/// Dio interceptor that adds Firebase ID token, trace headers,
/// and structured request/response logging.
class AuthInterceptor extends Interceptor {
  final _logger = AppLogger.instance;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Generate trace ID and attach headers
    final traceId = _logger.generateTraceId();
    options.headers['X-Request-ID'] = traceId;
    options.headers['X-Session-ID'] = _logger.sessionId;
    // Stash trace ID for response/error logging
    options.extra['trace_id'] = traceId;

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
    if (err.response?.statusCode == 401) {
      _logger.warning('auth.token_expired', logger: 'AuthInterceptor', traceId: traceId);
      await FirebaseAuth.instance.signOut();
    }
    handler.next(err);
  }
}
