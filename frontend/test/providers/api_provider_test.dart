import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/speech_service.dart';
import 'package:frontend/services/ramble_websocket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('apiServiceProvider', () {
    test('returns ApiService instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(apiServiceProvider);
      expect(service, isA<ApiService>());
    });
  });

  // audioServiceProvider skipped — AudioRecorder uses native platform channels
  // that are unavailable in test environment. Covered via MockAudioService in
  // widget tests.

  group('speechServiceProvider', () {
    test('returns SpeechService instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(speechServiceProvider);
      expect(service, isA<SpeechService>());
    });
  });

  group('rambleWebSocketProvider', () {
    test('returns RambleWebSocketService instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(rambleWebSocketProvider);
      expect(service, isA<RambleWebSocketService>());
    });
  });
}
