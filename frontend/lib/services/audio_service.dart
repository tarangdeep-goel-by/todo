import 'dart:async';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/constants.dart';

/// Service for native audio recording
class AudioService {
  /// Normalize a dBFS amplitude value to the 0-1 range.
  /// Assumes a floor of -60 dB and a ceiling of 0 dB.
  static double normalizeAmplitude(double current) =>
      ((current + 60) / 60).clamp(0.0, 1.0);

  final AudioRecorder _recorder = AudioRecorder();
  final List<double> _waveformData = [];
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// Request microphone permission
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Start recording audio
  Future<String> startRecording() async {
    final hasPermission = await this.hasPermission();
    if (!hasPermission) {
      final granted = await requestPermission();
      if (!granted) {
        throw Exception('Microphone permission denied');
      }
    }

    final path = await _getFilePath();

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: path,
    );

    // Stream amplitude for waveform visualization
    _amplitudeSubscription = _recorder.onAmplitudeChanged(
      const Duration(milliseconds: 100),
    ).listen((amp) {
      final normalized = normalizeAmplitude(amp.current);
      _waveformData.add(normalized);

      // Keep only last 50 samples
      if (_waveformData.length > 50) {
        _waveformData.removeAt(0);
      }
    });

    return path;
  }

  /// Stop recording and return file path
  Future<String?> stopRecording() async {
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _waveformData.clear();

    final path = await _recorder.stop();
    return path;
  }

  /// Cancel recording and delete file
  Future<void> cancelRecording() async {
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _waveformData.clear();

    await _recorder.stop();
  }

  /// Start streaming raw PCM audio (16kHz, mono, 16-bit).
  /// Returns a Stream of PCM byte chunks for WebSocket streaming.
  Future<Stream<List<int>>> startStream() async {
    final hasPerm = await hasPermission();
    if (!hasPerm) {
      final granted = await requestPermission();
      if (!granted) throw Exception('Microphone permission denied');
    }

    // Monitor amplitude for waveform visualization
    _amplitudeSubscription = _recorder.onAmplitudeChanged(
      const Duration(milliseconds: 100),
    ).listen((amp) {
      final normalized = normalizeAmplitude(amp.current);
      _waveformData.add(normalized);
      if (_waveformData.length > 50) _waveformData.removeAt(0);
    });

    return await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
  }

  /// Stop the audio stream.
  Future<void> stopStream() async {
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _waveformData.clear();
    await _recorder.stop();
  }

  /// Get current waveform data for visualization
  List<double> get waveformData => List.unmodifiable(_waveformData);

  /// Check if currently recording
  Future<bool> isRecording() async {
    return await _recorder.isRecording();
  }

  /// Generate unique file path for recording
  Future<String> _getFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    final audioDir = '${directory.path}/${AppConstants.audioFolderName}';

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$audioDir/recording_$timestamp${AppConstants.audioFileExtension}';
  }

  /// Dispose resources
  void dispose() {
    _amplitudeSubscription?.cancel();
    _recorder.dispose();
  }
}
