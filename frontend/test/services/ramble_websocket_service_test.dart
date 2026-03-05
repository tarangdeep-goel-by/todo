import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/services/ramble_websocket_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('RambleConnectionState', () {
    test('has 4 values', () {
      expect(RambleConnectionState.values, hasLength(4));
    });

    test('contains disconnected, connecting, connected, reconnecting', () {
      expect(RambleConnectionState.values, containsAll([
        RambleConnectionState.disconnected,
        RambleConnectionState.connecting,
        RambleConnectionState.connected,
        RambleConnectionState.reconnecting,
      ]));
    });
  });

  group('RambleWebSocketService', () {
    test('initial connectionState is disconnected', () {
      final service = RambleWebSocketService();
      expect(service.connectionState, RambleConnectionState.disconnected);
      service.dispose();
    });

    test('streams are broadcast streams (can listen multiple times)', () {
      final service = RambleWebSocketService();

      // Broadcast streams allow multiple listeners without throwing
      service.transcriptionStream.listen((_) {});
      service.transcriptionStream.listen((_) {});

      service.finalTranscriptStream.listen((_) {});
      service.finalTranscriptStream.listen((_) {});

      service.statusStream.listen((_) {});
      service.statusStream.listen((_) {});

      service.errorStream.listen((_) {});
      service.errorStream.listen((_) {});

      service.timeRemainingStream.listen((_) {});
      service.timeRemainingStream.listen((_) {});

      service.connectionStateStream.listen((_) {});
      service.connectionStateStream.listen((_) {});

      service.dispose();
    });

    test('dispose closes streams', () async {
      final service = RambleWebSocketService();
      service.dispose();

      // After dispose, listening to closed streams should emit done immediately
      final completer = Completer<bool>();
      service.transcriptionStream.listen(
        (_) {},
        onDone: () => completer.complete(true),
      );
      expect(await completer.future, isTrue);
    });
  });

  group('RambleWebSocketService with mock channel', () {
    late MockWebSocketChannel mockChannel;
    late MockWebSocketSink mockSink;
    late StreamController<dynamic> streamController;
    late RambleWebSocketService service;

    setUp(() {
      mockChannel = MockWebSocketChannel();
      mockSink = MockWebSocketSink();
      streamController = StreamController<dynamic>.broadcast();

      when(() => mockChannel.sink).thenReturn(mockSink);
      when(() => mockChannel.stream).thenAnswer((_) => streamController.stream);
      when(() => mockChannel.ready).thenAnswer((_) async {});
      when(() => mockSink.add(any())).thenReturn(null);
      when(() => mockSink.close()).thenAnswer((_) async {});
      when(() => mockSink.close(any(), any())).thenAnswer((_) async {});

      service = RambleWebSocketService(
        channelFactory: (_) => mockChannel,
        tokenProvider: () async => 'test-token',
      );
    });

    tearDown(() {
      service.dispose();
      if (!streamController.isClosed) {
        streamController.close();
      }
    });

    test('connect sends start message', () async {
      await service.connect();

      final captured = verify(() => mockSink.add(captureAny())).captured;
      final startMsg = jsonDecode(captured.first as String) as Map<String, dynamic>;
      expect(startMsg['type'], 'start');
      expect(startMsg.containsKey('user_id'), false);
    });

    test('connect sets state to connected', () async {
      await service.connect();

      // After connect returns, the state should be connected
      expect(service.connectionState, RambleConnectionState.connected);
    });

    test('sendAudioChunk sends audio message', () async {
      await service.connect();
      reset(mockSink);
      when(() => mockSink.add(any())).thenReturn(null);
      when(() => mockSink.close()).thenAnswer((_) async {});
      when(() => mockSink.close(any(), any())).thenAnswer((_) async {});

      service.sendAudioChunk('dGVzdA==');

      final captured = verify(() => mockSink.add(captureAny())).captured;
      final msg = jsonDecode(captured.first as String) as Map<String, dynamic>;
      expect(msg['type'], 'audio');
      expect(msg['data'], 'dGVzdA==');
    });

    test('transcriptionStream emits on transcription message', () async {
      await service.connect();

      final future = service.transcriptionStream.first;
      streamController.add(jsonEncode({
        'type': 'transcription',
        'text': 'hello world',
      }));

      expect(await future, 'hello world');
    });

    test('finalTranscriptStream emits on final_transcript message', () async {
      await service.connect();

      final future = service.finalTranscriptStream.first;
      streamController.add(jsonEncode({
        'type': 'final_transcript',
        'text': 'the full transcript',
      }));

      expect(await future, 'the full transcript');
    });

    test('statusStream emits on status message', () async {
      await service.connect();

      final future = service.statusStream.first;
      streamController.add(jsonEncode({
        'type': 'status',
        'status': 'listening',
      }));

      expect(await future, 'listening');
    });

    test('timeRemainingStream emits seconds on time_remaining status', () async {
      await service.connect();

      final future = service.timeRemainingStream.first;
      streamController.add(jsonEncode({
        'type': 'status',
        'status': 'time_remaining',
        'seconds': 42,
      }));

      expect(await future, 42);
    });

    test('errorStream emits on error message', () async {
      await service.connect();

      final future = service.errorStream.first;
      streamController.add(jsonEncode({
        'type': 'error',
        'message': 'something went wrong',
      }));

      expect(await future, 'something went wrong');
    });

    test('stop sends stop message and waits for final transcript', () async {
      await service.connect();
      reset(mockSink);
      when(() => mockSink.add(any())).thenReturn(null);
      when(() => mockSink.close()).thenAnswer((_) async {});
      when(() => mockSink.close(any(), any())).thenAnswer((_) async {});

      // Schedule a final_transcript response shortly after stop
      final stopFuture = service.stop();
      await Future.delayed(const Duration(milliseconds: 10));
      streamController.add(jsonEncode({
        'type': 'final_transcript',
        'text': 'final text here',
      }));

      final result = await stopFuture;
      expect(result, 'final text here');

      // Verify stop message was sent
      final captured = verify(() => mockSink.add(captureAny())).captured;
      final stopMsg = jsonDecode(captured.first as String) as Map<String, dynamic>;
      expect(stopMsg['type'], 'stop');
    });

    test('connectionStateStream emits connecting then connected during connect', () async {
      final states = <RambleConnectionState>[];
      service.connectionStateStream.listen(states.add);

      await service.connect();
      // Allow any pending microtasks to flush
      await Future<void>.delayed(Duration.zero);

      expect(states, contains(RambleConnectionState.connecting));
      expect(service.connectionState, RambleConnectionState.connected);
    });
  });
}
