import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/constants.dart';

/// Connection state for ramble WebSocket.
enum RambleConnectionState { disconnected, connecting, connected, reconnecting }

/// WebSocket client for streaming ramble audio to backend (transcription-only).
class RambleWebSocketService {
  final WebSocketChannel Function(Uri) _channelFactory;
  final Future<String?> Function() _tokenProvider;
  WebSocketChannel? _channel;

  RambleWebSocketService({
    WebSocketChannel Function(Uri)? channelFactory,
    Future<String?> Function()? tokenProvider,
  })  : _channelFactory = channelFactory ?? WebSocketChannel.connect,
        _tokenProvider = tokenProvider ??
            (() async => FirebaseAuth.instance.currentUser?.getIdToken());
  final _transcriptionController = StreamController<String>.broadcast();
  final _finalTranscriptController = StreamController<String>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _timeRemainingController = StreamController<int>.broadcast();
  final _connectionStateController =
      StreamController<RambleConnectionState>.broadcast();

  RambleConnectionState _connectionState = RambleConnectionState.disconnected;
  String? _token;
  bool _intentionalClose = false;
  DateTime? _connectedAt;

  /// Completer for the final transcript — set in _handleMessage, awaited in stop().
  Completer<String>? _finalTranscriptCompleter;

  Stream<String> get transcriptionStream => _transcriptionController.stream;
  Stream<String> get finalTranscriptStream => _finalTranscriptController.stream;
  Stream<String> get statusStream => _statusController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<int> get timeRemainingStream => _timeRemainingController.stream;
  Stream<RambleConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  RambleConnectionState get connectionState => _connectionState;

  void _setConnectionState(RambleConnectionState state) {
    _connectionState = state;
    _connectionStateController.add(state);
  }

  String get _wsUrl {
    final wsBase = AppConstants.apiBaseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://')
        .replaceFirst('/api', '');
    return '$wsBase/ws/ramble';
  }

  /// Connect and send start message.
  Future<void> connect() async {
    _intentionalClose = false;
    _connectedAt = null;
    _setConnectionState(RambleConnectionState.connecting);

    // Get fresh auth token
    _token = await _tokenProvider();
    if (_token == null) {
      _setConnectionState(RambleConnectionState.disconnected);
      _errorController.add('Not authenticated');
      return;
    }

    final url = '$_wsUrl?token=$_token';
    debugPrint('[RambleWS] Connecting to $_wsUrl');
    _channel = _channelFactory(Uri.parse(url));

    try {
      await _channel!.ready;
      debugPrint('[RambleWS] WebSocket ready');
    } catch (e) {
      debugPrint('[RambleWS] WebSocket connect failed: $e');
      _setConnectionState(RambleConnectionState.disconnected);
      _errorController.add('WebSocket connect failed: $e');
      return;
    }

    _listenToChannel();
    _setConnectionState(RambleConnectionState.connected);
    _connectedAt = DateTime.now();

    _send({'type': 'start'});
    debugPrint('[RambleWS] Start message sent');
  }

  void _listenToChannel() {
    _channel!.stream.listen(
      _handleMessage,
      onError: (error) {
        debugPrint('[RambleWS] Stream error: $error');
        _errorController.add(error.toString());
      },
      onDone: () {
        debugPrint('[RambleWS] Connection closed (intentional=$_intentionalClose)');
        if (_intentionalClose) return;

        final wasConnected =
            _connectionState == RambleConnectionState.connected;
        _setConnectionState(RambleConnectionState.disconnected);
        _statusController.add('disconnected');

        // Only auto-reconnect if connected for >3s (not a setup hiccup)
        final connectedLongEnough = _connectedAt != null &&
            DateTime.now().difference(_connectedAt!).inSeconds >= 3;

        if (wasConnected && _token != null && connectedLongEnough) {
          _attemptReconnect();
        } else if (wasConnected) {
          debugPrint('[RambleWS] Skipping reconnect — connection too brief');
        }
      },
    );
  }

  Future<void> _attemptReconnect() async {
    _setConnectionState(RambleConnectionState.reconnecting);
    debugPrint('[RambleWS] Attempting reconnect in 2s...');
    await Future.delayed(const Duration(seconds: 2));

    // Refresh token for reconnect
    _token = await _tokenProvider();
    if (_token == null) {
      _setConnectionState(RambleConnectionState.disconnected);
      _errorController.add('Not authenticated');
      return;
    }

    final url = '$_wsUrl?token=$_token';
    _channel = _channelFactory(Uri.parse(url));
    try {
      await _channel!.ready;
      debugPrint('[RambleWS] Reconnected');
      _listenToChannel();
      _setConnectionState(RambleConnectionState.connected);
      _connectedAt = DateTime.now();
      _send({'type': 'start'});
    } catch (e) {
      debugPrint('[RambleWS] Reconnect failed: $e');
      _setConnectionState(RambleConnectionState.disconnected);
      _errorController.add('Reconnect failed — editing with current transcript');
    }
  }

  /// Manually reconnect after a disconnection.
  /// Re-establishes the WebSocket and sends a new start message.
  Future<void> manualReconnect() async {
    if (_connectionState == RambleConnectionState.connecting ||
        _connectionState == RambleConnectionState.reconnecting) {
      return; // Already attempting connection
    }
    _intentionalClose = false;
    await _attemptReconnect();
  }

  /// Send base64-encoded PCM audio chunk.
  void sendAudioChunk(String base64Pcm) {
    _send({'type': 'audio', 'data': base64Pcm});
  }

  /// Stop the session. Returns the final transcript (or null on timeout).
  Future<String?> stop() async {
    _intentionalClose = true;
    _finalTranscriptCompleter = Completer<String>();

    _send({'type': 'stop'});

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
    _setConnectionState(RambleConnectionState.disconnected);
    return result;
  }

  void dispose() {
    _intentionalClose = true;
    _channel?.sink.close();
    _channel = null;
    _setConnectionState(RambleConnectionState.disconnected);
    _transcriptionController.close();
    _finalTranscriptController.close();
    _statusController.close();
    _errorController.close();
    _timeRemainingController.close();
    _connectionStateController.close();
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
          if (_finalTranscriptCompleter != null &&
              !_finalTranscriptCompleter!.isCompleted) {
            _finalTranscriptCompleter!.complete(text);
          }
        case 'status':
          final status = msg['status'] as String;
          if (status == 'time_remaining') {
            final seconds = msg['seconds'] as int;
            _timeRemainingController.add(seconds);
          } else {
            _statusController.add(status);
          }
        case 'error':
          debugPrint('[RambleWS] Error from server: ${msg['message']}');
          _errorController.add(msg['message'] as String);
      }
    } catch (e) {
      debugPrint('[RambleWS] Parse error: $e');
    }
  }
}
