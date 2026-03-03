import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/services/onboarding_service.dart';

void main() {
  group('OnboardingService', () {
    test('hasSeenWelcome returns false initially', () async {
      SharedPreferences.setMockInitialValues({});
      final result = await OnboardingService.hasSeenWelcome();
      expect(result, isFalse);
    });

    test('markWelcomeSeen then hasSeenWelcome returns true', () async {
      SharedPreferences.setMockInitialValues({});
      await OnboardingService.markWelcomeSeen();
      final result = await OnboardingService.hasSeenWelcome();
      expect(result, isTrue);
    });

    test('hasSeenWelcome returns true when pre-set', () async {
      SharedPreferences.setMockInitialValues({'onboarding_welcome_seen': true});
      final result = await OnboardingService.hasSeenWelcome();
      expect(result, isTrue);
    });
  });
}
