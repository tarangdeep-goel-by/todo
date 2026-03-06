import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/constants.dart';
import 'app_logger.dart';
import 'analytics_service.dart';

/// Connection state for ramble WebSocket.
enum RambleConnectionState { disconnected, connecting, connected, reconnecting }

/// WebSocket client for streaming ramble audio to backend (transcription-only).
class RambleWebSocketService {
  final _logger = AppLogger.instance;
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
  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 3;

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

    _logger.info('ws.connect', logger: 'RambleWS', data: {'url': _wsUrl});
    _channel = _channelFactory(Uri.parse(_wsUrl));

    try {
      await _channel!.ready;
      _logger.info('ws.connect', logger: 'RambleWS', data: {'status': 'ready'});
    } catch (e) {
      _logger.error('ws.error', logger: 'RambleWS', data: {'reason': 'connect_failed', 'error': e.toString()});
      _setConnectionState(RambleConnectionState.disconnected);
      _errorController.add('WebSocket connect failed: $e');
      return;
    }

    // Authenticate via first message (token never in URL)
    _send({'type': 'auth', 'token': _token!});
    _logger.debug('ws.message', logger: 'RambleWS', data: {'direction': 'out', 'type': 'auth'});

    // Wait for auth_ok before proceeding
    try {
      final authRaw = await _channel!.stream.first.timeout(
        const Duration(seconds: 5),
      );
      final authMsg = jsonDecode(authRaw as String) as Map<String, dynamic>;
      if (authMsg['type'] == 'auth_error') {
        _logger.error('ws.auth_failed', logger: 'RambleWS', data: {'message': authMsg['message']});
        _setConnectionState(RambleConnectionState.disconnected);
        _errorController.add(authMsg['message'] as String? ?? 'Authentication failed');
        await _channel?.sink.close();
        _channel = null;
        return;
      }
      if (authMsg['type'] != 'auth_ok') {
        _logger.error('ws.auth_failed', logger: 'RambleWS', data: {'unexpected_type': authMsg['type']});
        _setConnectionState(RambleConnectionState.disconnected);
        _errorController.add('Unexpected auth response');
        await _channel?.sink.close();
        _channel = null;
        return;
      }
    } on TimeoutException {
      _logger.error('ws.auth_failed', logger: 'RambleWS', data: {'reason': 'timeout'});
      _setConnectionState(RambleConnectionState.disconnected);
      _errorController.add('Authentication timeout');
      await _channel?.sink.close();
      _channel = null;
      return;
    } catch (e) {
      _logger.error('ws.auth_failed', logger: 'RambleWS', data: {'error': e.toString()});
      _setConnectionState(RambleConnectionState.disconnected);
      _errorController.add('Authentication failed: $e');
      await _channel?.sink.close();
      _channel = null;
      return;
    }

    _listenToChannel();
    _setConnectionState(RambleConnectionState.connected);
    _connectedAt = DateTime.now();
    _reconnectAttempt = 0;

    _send({'type': 'start'});
    AnalyticsService.instance.trackRambleStarted();
    _logger.debug('ws.message', logger: 'RambleWS', data: {'direction': 'out', 'type': 'start'});
  }

  void _listenToChannel() {
    _channel!.stream.listen(
      _handleMessage,
      onError: (error) {
        _logger.error('ws.error', logger: 'RambleWS', data: {'reason': 'stream', 'error': error.toString()});
        _errorController.add(error.toString());
      },
      onDone: () {
        _logger.info('ws.disconnect', logger: 'RambleWS', data: {'intentional': _intentionalClose});
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
          _logger.debug('ws.reconnect', logger: 'RambleWS', data: {'skipped': true, 'reason': 'too_brief'});
        }
      },
    );
  }

  Future<void> _attemptReconnect() async {
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      _logger.warning('ws.reconnect', logger: 'RambleWS', data: {'exhausted': true, 'attempts': _reconnectAttempt});
      _setConnectionState(RambleConnectionState.disconnected);
      _errorController.add('Connection lost after $_reconnectAttempt attempts. Tap to retry or keep what you have.');
      return;
    }

    _reconnectAttempt++;
    _setConnectionState(RambleConnectionState.reconnecting);
    _statusController.add('reconnecting:$_reconnectAttempt/$_maxReconnectAttempts');
    _logger.info('ws.reconnect', logger: 'RambleWS', data: {'attempt': _reconnectAttempt, 'max': _maxReconnectAttempts});

    // Exponential backoff: 1s, 2s, 4s
    final delaySeconds = 1 << (_reconnectAttempt - 1);
    await Future.delayed(Duration(seconds: delaySeconds));

    // Refresh token for reconnect
    _token = await _tokenProvider();
    if (_token == null) {
      _setConnectionState(RambleConnectionState.disconnected);
      _errorController.add('Not authenticated');
      return;
    }

    _channel = _channelFactory(Uri.parse(_wsUrl));
    try {
      await _channel!.ready;

      // Authenticate via first message (token never in URL)
      _send({'type': 'auth', 'token': _token!});
      _logger.debug('ws.message', logger: 'RambleWS', data: {'direction': 'out', 'type': 'auth'});

      // Wait for auth_ok before proceeding
      final authRaw = await _channel!.stream.first.timeout(
        const Duration(seconds: 5),
      );
      final authMsg = jsonDecode(authRaw as String) as Map<String, dynamic>;
      if (authMsg['type'] != 'auth_ok') {
        _logger.error('ws.auth_failed', logger: 'RambleWS', data: {'type': authMsg['type']});
        _setConnectionState(RambleConnectionState.disconnected);
        _errorController.add(authMsg['message'] as String? ?? 'Authentication failed');
        await _channel?.sink.close();
        _channel = null;
        return;
      }

      _listenToChannel();
      _logger.info('ws.reconnect', logger: 'RambleWS', data: {'success': true, 'attempt': _reconnectAttempt});
      _setConnectionState(RambleConnectionState.connected);
      _connectedAt = DateTime.now();
      _reconnectAttempt = 0;
      _send({'type': 'start'});
    } catch (e) {
      _logger.error('ws.error', logger: 'RambleWS', data: {'reason': 'reconnect_failed', 'attempt': _reconnectAttempt, 'error': e.toString()});
      // Recurse to try next attempt
      await _attemptReconnect();
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
    _reconnectAttempt = 0;
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

    final durationSeconds = _connectedAt != null
        ? DateTime.now().difference(_connectedAt!).inSeconds
        : 0;
    AnalyticsService.instance.trackRambleCompleted(
      durationSeconds: durationSeconds,
      transcriptLength: result?.length ?? 0,
    );

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
      _logger.debug('ws.message', logger: 'RambleWS', data: {'direction': 'in', 'type': type});

      switch (type) {
        case 'transcription':
          final text = msg['text'] as String;
          _transcriptionController.add(text);
        case 'final_transcript':
          final text = msg['text'] as String;
          _logger.info('ramble.transcript', logger: 'RambleWS', data: {'length': text.length});
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
          _logger.error('ws.error', logger: 'RambleWS', data: {'reason': 'server', 'message': msg['message']});
          _errorController.add(msg['message'] as String);
      }
    } catch (e) {
      _logger.error('ws.error', logger: 'RambleWS', data: {'reason': 'parse', 'error': e.toString()});
    }
  }
}
