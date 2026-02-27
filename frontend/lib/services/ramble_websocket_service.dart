import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/constants.dart';

/// WebSocket client for streaming ramble audio to backend (transcription-only).
class RambleWebSocketService {
  WebSocketChannel? _channel;
  final _transcriptionController = StreamController<String>.broadcast();
  final _finalTranscriptController = StreamController<String>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  /// Completer for the final transcript — set in _handleMessage, awaited in stop().
  Completer<String>? _finalTranscriptCompleter;

  Stream<String> get transcriptionStream => _transcriptionController.stream;
  Stream<String> get finalTranscriptStream => _finalTranscriptController.stream;
  Stream<String> get statusStream => _statusController.stream;
  Stream<String> get errorStream => _errorController.stream;

  /// Connect and send start message.
  Future<void> connect({
    required String userId,
  }) async {
    // Derive WS URL from API base URL
    // e.g. "http://192.168.0.106:8001/api" → "ws://192.168.0.106:8001/ws/ramble"
    final wsBase = AppConstants.apiBaseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://')
        .replaceFirst('/api', '');
    final wsUrl = '$wsBase/ws/ramble';

    debugPrint('[RambleWS] Connecting to $wsUrl');
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    // Wait for WebSocket connection to be established
    try {
      await _channel!.ready;
      debugPrint('[RambleWS] WebSocket ready');
    } catch (e) {
      debugPrint('[RambleWS] WebSocket connect failed: $e');
      _errorController.add('WebSocket connect failed: $e');
      return;
    }

    _channel!.stream.listen(
      _handleMessage,
      onError: (error) {
        debugPrint('[RambleWS] Stream error: $error');
        _errorController.add(error.toString());
      },
      onDone: () {
        debugPrint('[RambleWS] Connection closed');
        _statusController.add('disconnected');
      },
    );

    _send({
      'type': 'start',
      'user_id': userId,
    });
    debugPrint('[RambleWS] Start message sent');
  }

  /// Send base64-encoded PCM audio chunk.
  void sendAudioChunk(String base64Pcm) {
    _send({'type': 'audio', 'data': base64Pcm});
  }

  /// Stop the session. Returns the final transcript (or null on timeout).
  Future<String?> stop() async {
    // Set up completer BEFORE sending stop — _handleMessage will complete it.
    _finalTranscriptCompleter = Completer<String>();

    _send({'type': 'stop'});

    // Wait up to 10s for final_transcript (transliteration can be slow)
    String? result;
    try {
      result = await _finalTranscriptCompleter!.future.timeout(
        const Duration(seconds: 10),
      );
    } on TimeoutException {
      result = null;
    } catch (_) {
      result = null;
    }

    _finalTranscriptCompleter = null;
    await _channel?.sink.close();
    _channel = null;
    return result;
  }

  void dispose() {
    _channel?.sink.close();
    _channel = null;
    _transcriptionController.close();
    _finalTranscriptController.close();
    _statusController.close();
    _errorController.close();
  }

  void _send(Map<String, dynamic> msg) {
    final encoded = jsonEncode(msg);
    _channel?.sink.add(encoded);
  }

  void _handleMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String;
      debugPrint('[RambleWS] ← $type');

      switch (type) {
        case 'transcription':
          final text = msg['text'] as String;
          _transcriptionController.add(text);
        case 'final_transcript':
          final text = msg['text'] as String;
          debugPrint('[RambleWS] Final transcript: ${text.length} chars');
          _finalTranscriptController.add(text);
          if (_finalTranscriptCompleter != null && !_finalTranscriptCompleter!.isCompleted) {
            _finalTranscriptCompleter!.complete(text);
          }
        case 'status':
          _statusController.add(msg['status'] as String);
        case 'error':
          debugPrint('[RambleWS] Error from server: ${msg['message']}');
          _errorController.add(msg['message'] as String);
      }
    } catch (e) {
      debugPrint('[RambleWS] Parse error: $e');
    }
  }
}
