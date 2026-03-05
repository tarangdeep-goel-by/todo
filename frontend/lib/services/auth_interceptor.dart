import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Dio interceptor that adds Firebase ID token to every request
/// and signs out on 401 responses.
class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final token = await user.getIdToken();
        if (token == null) {
          debugPrint('[AuthInterceptor] getIdToken returned null — rejecting request');
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
        debugPrint('[AuthInterceptor] Failed to get ID token: $e — rejecting request');
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
      debugPrint('[AuthInterceptor] No current user — request sent without auth');
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      debugPrint('[AuthInterceptor] 401 received — signing out user');
      await FirebaseAuth.instance.signOut();
    }
    handler.next(err);
  }
}
