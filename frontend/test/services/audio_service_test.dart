import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/audio_service.dart';

void main() {
  group('AudioService.normalizeAmplitude', () {
    test('-60dB normalizes to 0.0', () {
      expect(AudioService.normalizeAmplitude(-60.0), 0.0);
    });

    test('0dB normalizes to 1.0', () {
      expect(AudioService.normalizeAmplitude(0.0), 1.0);
    });

    test('-30dB normalizes to 0.5', () {
      expect(AudioService.normalizeAmplitude(-30.0), 0.5);
    });

    test('clamps below -60dB to 0.0', () {
      expect(AudioService.normalizeAmplitude(-100.0), 0.0);
    });

    test('clamps above 0dB to 1.0', () {
      expect(AudioService.normalizeAmplitude(10.0), 1.0);
    });
  });
}
