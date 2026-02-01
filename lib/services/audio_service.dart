import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:todo/config/env.dart';
import 'package:todo/utils/constants.dart';

/// Service for audio recording
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentRecordingPath;

  /// Check if recording is supported
  Future<bool> isRecordingSupported() async {
    return await _recorder.hasPermission();
  }

  /// Start recording
  Future<void> startRecording() async {
    // Check permission
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception(Constants.permissionDeniedMessage);
    }

    // Create audio directory
    final directory = await getApplicationDocumentsDirectory();
    final audioDir = Directory(p.join(directory.path, Env.audioFolderName));
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }

    // Generate file path
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'recording_$timestamp${Env.audioFileExtension}';
    _currentRecordingPath = p.join(audioDir.path, fileName);

    // Start recording
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _currentRecordingPath!,
    );
  }

  /// Stop recording and return file path
  Future<String?> stopRecording() async {
    final path = await _recorder.stop();
    final recordingPath = _currentRecordingPath;
    _currentRecordingPath = null;
    return recordingPath ?? path;
  }

  /// Cancel recording (stop and delete file)
  Future<void> cancelRecording() async {
    await _recorder.stop();

    if (_currentRecordingPath != null) {
      final file = File(_currentRecordingPath!);
      if (await file.exists()) {
        await file.delete();
      }
      _currentRecordingPath = null;
    }
  }

  /// Check if currently recording
  Future<bool> isRecording() async {
    return await _recorder.isRecording();
  }

  /// Get recording duration
  Stream<Duration> getRecordingDuration() async* {
    final startTime = DateTime.now();
    while (await _recorder.isRecording()) {
      await Future.delayed(const Duration(milliseconds: 100));
      yield DateTime.now().difference(startTime);
    }
  }

  /// Delete audio file
  Future<void> deleteAudioFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Dispose recorder
  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
