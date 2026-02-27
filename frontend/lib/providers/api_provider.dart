import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/speech_service.dart';
import '../services/ramble_websocket_service.dart';

/// Provider for API service singleton
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

/// Provider for audio service singleton
final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for speech recognition service
final speechServiceProvider = Provider<SpeechService>((ref) {
  final service = SpeechService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for ramble WebSocket service
final rambleWebSocketProvider = Provider<RambleWebSocketService>((ref) {
  final service = RambleWebSocketService();
  ref.onDispose(() => service.dispose());
  return service;
});
