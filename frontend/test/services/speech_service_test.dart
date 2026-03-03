import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/services/speech_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockSpeechToText mockSpeech;
  late SpeechService service;

  setUp(() {
    mockSpeech = MockSpeechToText();
    service = SpeechService(speech: mockSpeech);
  });

  group('SpeechService', () {
    group('initialize', () {
      test('calls speech.initialize and returns true', () async {
        when(() => mockSpeech.initialize(
              onStatus: any(named: 'onStatus'),
              onError: any(named: 'onError'),
            )).thenAnswer((_) async => true);

        final result = await service.initialize();

        expect(result, isTrue);
        verify(() => mockSpeech.initialize(
              onStatus: any(named: 'onStatus'),
              onError: any(named: 'onError'),
            )).called(1);
      });

      test('is idempotent - second call does not re-initialize', () async {
        when(() => mockSpeech.initialize(
              onStatus: any(named: 'onStatus'),
              onError: any(named: 'onError'),
            )).thenAnswer((_) async => true);

        await service.initialize();
        final result = await service.initialize();

        expect(result, isTrue);
        // initialize should only be called once on the mock
        verify(() => mockSpeech.initialize(
              onStatus: any(named: 'onStatus'),
              onError: any(named: 'onError'),
            )).called(1);
      });

      test('throws when speech not available', () async {
        when(() => mockSpeech.initialize(
              onStatus: any(named: 'onStatus'),
              onError: any(named: 'onError'),
            )).thenAnswer((_) async => false);

        expect(() => service.initialize(), throwsException);
      });
    });

    group('startListening', () {
      test('calls speech.listen', () async {
        when(() => mockSpeech.listen(
              onResult: any(named: 'onResult'),
              onSoundLevelChange: any(named: 'onSoundLevelChange'),
              listenFor: any(named: 'listenFor'),
              localeId: any(named: 'localeId'),
              listenOptions: any(named: 'listenOptions'),
            )).thenAnswer((_) async {});

        await service.startListening();

        verify(() => mockSpeech.listen(
              onResult: any(named: 'onResult'),
              onSoundLevelChange: any(named: 'onSoundLevelChange'),
              listenFor: any(named: 'listenFor'),
              localeId: any(named: 'localeId'),
              listenOptions: any(named: 'listenOptions'),
            )).called(1);
      });
    });

    group('stopListening', () {
      test('calls speech.stop', () async {
        when(() => mockSpeech.stop()).thenAnswer((_) async {});

        await service.stopListening();

        verify(() => mockSpeech.stop()).called(1);
      });
    });

    group('cancel', () {
      test('calls speech.cancel', () async {
        when(() => mockSpeech.cancel()).thenAnswer((_) async {});

        await service.cancel();

        verify(() => mockSpeech.cancel()).called(1);
      });
    });

    group('isListening', () {
      test('delegates to speech.isListening', () {
        when(() => mockSpeech.isListening).thenReturn(true);
        expect(service.isListening, isTrue);

        when(() => mockSpeech.isListening).thenReturn(false);
        expect(service.isListening, isFalse);
      });
    });

    group('sound level normalization', () {
      test('level -2 normalizes to 0.0', () async {
        double? captured;
        service.onSoundLevelChange = (level) => captured = level;

        // Capture the onSoundLevelChange callback passed to speech.listen
        void Function(double)? soundCallback;
        when(() => mockSpeech.listen(
              onResult: any(named: 'onResult'),
              onSoundLevelChange: any(named: 'onSoundLevelChange'),
              listenFor: any(named: 'listenFor'),
              localeId: any(named: 'localeId'),
              listenOptions: any(named: 'listenOptions'),
            )).thenAnswer((invocation) async {
          soundCallback = invocation.namedArguments[#onSoundLevelChange]
              as void Function(double)?;
        });

        await service.startListening();
        soundCallback!(-2.0);

        expect(captured, closeTo(0.0, 0.001));
      });

      test('level 10 normalizes to 1.0', () async {
        double? captured;
        service.onSoundLevelChange = (level) => captured = level;

        void Function(double)? soundCallback;
        when(() => mockSpeech.listen(
              onResult: any(named: 'onResult'),
              onSoundLevelChange: any(named: 'onSoundLevelChange'),
              listenFor: any(named: 'listenFor'),
              localeId: any(named: 'localeId'),
              listenOptions: any(named: 'listenOptions'),
            )).thenAnswer((invocation) async {
          soundCallback = invocation.namedArguments[#onSoundLevelChange]
              as void Function(double)?;
        });

        await service.startListening();
        soundCallback!(10.0);

        expect(captured, closeTo(1.0, 0.001));
      });

      test('level 4 normalizes to 0.5', () async {
        double? captured;
        service.onSoundLevelChange = (level) => captured = level;

        void Function(double)? soundCallback;
        when(() => mockSpeech.listen(
              onResult: any(named: 'onResult'),
              onSoundLevelChange: any(named: 'onSoundLevelChange'),
              listenFor: any(named: 'listenFor'),
              localeId: any(named: 'localeId'),
              listenOptions: any(named: 'listenOptions'),
            )).thenAnswer((invocation) async {
          soundCallback = invocation.namedArguments[#onSoundLevelChange]
              as void Function(double)?;
        });

        await service.startListening();
        soundCallback!(4.0);

        expect(captured, closeTo(0.5, 0.001));
      });
    });

    group('dispose', () {
      test('calls speech.stop', () {
        when(() => mockSpeech.stop()).thenAnswer((_) async {});

        service.dispose();

        verify(() => mockSpeech.stop()).called(1);
      });
    });
  });
}
