import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

/// Callback-based wrapper around SpeechToText for on-device recognition
class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  /// Called with (text, isFinal) on each recognition result
  void Function(String text, bool isFinal)? onResult;

  /// Called with normalized sound level (0-1)
  void Function(double level)? onSoundLevelChange;

  /// Called with status string changes
  void Function(String status)? onStatus;

  /// Called on recognition error
  void Function(String error)? onError;

  /// Idempotent initialization — handles permission prompt internally.
  /// Returns true if speech recognition is available.
  Future<bool> initialize() async {
    if (_initialized) return true;

    _initialized = await _speech.initialize(
      onStatus: (status) => onStatus?.call(status),
      onError: (error) => _handleError(error),
    );

    if (!_initialized) {
      throw Exception('Speech recognition not available');
    }

    return true;
  }

  /// Start listening with dictation mode and partial results
  Future<void> startListening() async {
    await _speech.listen(
      onResult: _handleResult,
      onSoundLevelChange: _handleSoundLevel,
      listenFor: const Duration(seconds: 60),
      localeId: 'en_US',
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
      ),
    );
  }

  /// Stop listening — finalizes recognition
  Future<void> stopListening() async {
    await _speech.stop();
  }

  /// Cancel recognition without result
  Future<void> cancel() async {
    await _speech.cancel();
  }

  bool get isListening => _speech.isListening;

  void _handleResult(SpeechRecognitionResult result) {
    onResult?.call(result.recognizedWords, result.finalResult);
  }

  void _handleSoundLevel(double level) {
    // Normalize dB level to 0-1 range (typical range is -2 to 10)
    final normalized = ((level + 2) / 12).clamp(0.0, 1.0);
    onSoundLevelChange?.call(normalized);
  }

  void _handleError(SpeechRecognitionError error) {
    onError?.call(error.errorMsg);
  }

  void dispose() {
    _speech.stop();
    onResult = null;
    onSoundLevelChange = null;
    onStatus = null;
    onError = null;
  }
}
