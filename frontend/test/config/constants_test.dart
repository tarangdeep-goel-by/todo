import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/constants.dart';

void main() {
  group('AppConstants', () {
    test('apiBaseUrl contains http', () {
      expect(AppConstants.apiBaseUrl, contains('http'));
    });

    test('audioFileExtension is .m4a', () {
      expect(AppConstants.audioFileExtension, '.m4a');
    });

    test('statusActive is active', () {
      expect(AppConstants.statusActive, 'active');
    });

    test('statusCompleted is completed', () {
      expect(AppConstants.statusCompleted, 'completed');
    });

    test('audioFolderName is audio_recordings', () {
      expect(AppConstants.audioFolderName, 'audio_recordings');
    });
  });

  group('AppAnimations curves', () {
    test('easeOutQuint is a Cubic instance', () {
      expect(AppAnimations.easeOutQuint, isA<Cubic>());
    });

    test('easeOutCubic is a Cubic instance', () {
      expect(AppAnimations.easeOutCubic, isA<Cubic>());
    });
  });

  group('AppAnimations durations', () {
    test('cardExpand is positive', () {
      expect(AppAnimations.cardExpand.inMilliseconds, greaterThan(0));
    });

    test('cardCollapse is positive', () {
      expect(AppAnimations.cardCollapse.inMilliseconds, greaterThan(0));
    });

    test('waveformUpdate is positive', () {
      expect(AppAnimations.waveformUpdate.inMilliseconds, greaterThan(0));
    });

    test('viewTransition is positive', () {
      expect(AppAnimations.viewTransition.inMilliseconds, greaterThan(0));
    });

    test('staggerDelay is positive', () {
      expect(AppAnimations.staggerDelay.inMilliseconds, greaterThan(0));
    });

    test('ctaExpand is positive', () {
      expect(AppAnimations.ctaExpand.inMilliseconds, greaterThan(0));
    });

    test('ctaContract is positive', () {
      expect(AppAnimations.ctaContract.inMilliseconds, greaterThan(0));
    });

    test('snackbarIn is positive', () {
      expect(AppAnimations.snackbarIn.inMilliseconds, greaterThan(0));
    });

    test('snackbarOut is positive', () {
      expect(AppAnimations.snackbarOut.inMilliseconds, greaterThan(0));
    });
  });
}
