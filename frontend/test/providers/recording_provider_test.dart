import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/providers/recording_provider.dart';

void main() {
  group('RecordingState enum', () {
    test('has 4 values', () {
      expect(RecordingState.values, hasLength(4));
    });

    test('contains idle, listening, processing, typing', () {
      expect(RecordingState.values, contains(RecordingState.idle));
      expect(RecordingState.values, contains(RecordingState.listening));
      expect(RecordingState.values, contains(RecordingState.processing));
      expect(RecordingState.values, contains(RecordingState.typing));
    });
  });

  group('recordingStateProvider', () {
    test('defaults to idle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(recordingStateProvider), RecordingState.idle);
    });

    test('can be set to listening', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(recordingStateProvider.notifier).state =
          RecordingState.listening;
      expect(container.read(recordingStateProvider), RecordingState.listening);
    });

    test('can be set to processing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(recordingStateProvider.notifier).state =
          RecordingState.processing;
      expect(container.read(recordingStateProvider), RecordingState.processing);
    });

    test('can be set to typing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(recordingStateProvider.notifier).state =
          RecordingState.typing;
      expect(container.read(recordingStateProvider), RecordingState.typing);
    });
  });

  group('recordingPathProvider', () {
    test('defaults to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(recordingPathProvider), isNull);
    });
  });

  group('waveformDataProvider', () {
    test('defaults to empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(waveformDataProvider), isEmpty);
    });
  });

  group('transcriptionTextProvider', () {
    test('defaults to empty string', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(transcriptionTextProvider), '');
    });
  });
}
