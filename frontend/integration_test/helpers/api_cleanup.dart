import 'package:dio/dio.dart';
import 'package:frontend/config/environment.dart';

/// Wipes all data for the test user via the backend reset endpoint.
/// Call this in setUp() before each test.
Future<void> cleanupTestUser() async {
  final dio = Dio(BaseOptions(
    baseUrl: Environment.apiBaseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  try {
    await dio.delete(
      '/test/reset',
      options: Options(
        headers: {'Authorization': 'Bearer test-token-e2e'},
      ),
    );
  } catch (e) {
    // Ignore errors during cleanup — test user may not have data yet
  }
}
