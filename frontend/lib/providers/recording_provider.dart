import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Recording state enum
enum RecordingState {
  idle,
  listening,
  processing,
  typing,
}

/// Provider for recording state
final recordingStateProvider = StateProvider<RecordingState>((ref) => RecordingState.idle);

/// Provider for current recording file path
final recordingPathProvider = StateProvider<String?>((ref) => null);

/// Provider for waveform data
final waveformDataProvider = StateProvider<List<double>>((ref) => []);

/// Provider for partial/final transcription text from speech recognition
final transcriptionTextProvider = StateProvider<String>((ref) => '');
