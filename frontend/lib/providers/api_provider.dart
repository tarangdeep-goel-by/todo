import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';

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
