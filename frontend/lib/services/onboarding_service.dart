import 'package:shared_preferences/shared_preferences.dart';

/// Tracks first-use onboarding milestones via SharedPreferences.
class OnboardingService {
  static const _welcomeKey = 'onboarding_welcome_seen';

  static Future<bool> hasSeenWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_welcomeKey) ?? false;
  }

  static Future<void> markWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_welcomeKey, true);
  }
}
