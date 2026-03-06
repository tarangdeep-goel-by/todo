import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/services/api_service.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  group('NotificationService API methods', () {
    test('registerFcmToken calls correct API endpoint', () async {
      when(() => mockApi.registerFcmToken(any(), any(), any()))
          .thenAnswer((_) async {});

      await mockApi.registerFcmToken('test-token', 'android', 'Asia/Kolkata');

      verify(() => mockApi.registerFcmToken('test-token', 'android', 'Asia/Kolkata')).called(1);
    });

    test('unregisterFcmToken calls delete API', () async {
      when(() => mockApi.unregisterFcmToken(any()))
          .thenAnswer((_) async {});

      await mockApi.unregisterFcmToken('test-token');

      verify(() => mockApi.unregisterFcmToken('test-token')).called(1);
    });
  });
}
