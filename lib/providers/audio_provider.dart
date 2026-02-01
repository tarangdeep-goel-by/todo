import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo/services/audio_service.dart';
import 'package:todo/services/permission_service.dart';

/// Audio service provider
final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Permission service provider
final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});

/// Recording state provider
enum RecordingState {
  idle,
  recording,
  processing,
}

/// Recording state notifier
class RecordingStateNotifier extends StateNotifier<RecordingState> {
  RecordingStateNotifier() : super(RecordingState.idle);

  void setIdle() => state = RecordingState.idle;
  void setRecording() => state = RecordingState.recording;
  void setProcessing() => state = RecordingState.processing;
}

/// Recording state provider
final recordingStateProvider =
    StateNotifierProvider<RecordingStateNotifier, RecordingState>((ref) {
  return RecordingStateNotifier();
});

/// Current recording path provider
final currentRecordingPathProvider = StateProvider<String?>((ref) => null);

/// Home screen recording states
enum HomeRecordingState {
  idle,
  recording,
  processing,
  confirming,
  executing,
  complete,
}

/// Home screen recording state notifier
class HomeRecordingStateNotifier extends StateNotifier<HomeRecordingState> {
  HomeRecordingStateNotifier() : super(HomeRecordingState.idle);

  void startRecording() => state = HomeRecordingState.recording;
  void setProcessing() => state = HomeRecordingState.processing;
  void setConfirming() => state = HomeRecordingState.confirming;
  void setExecuting() => state = HomeRecordingState.executing;
  void setComplete() => state = HomeRecordingState.complete;
  void reset() => state = HomeRecordingState.idle;
}

/// Home screen recording state provider
final homeRecordingStateProvider =
    StateNotifierProvider<HomeRecordingStateNotifier, HomeRecordingState>((ref) {
  return HomeRecordingStateNotifier();
});
