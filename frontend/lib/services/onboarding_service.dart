import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';

final _log = AppLogger.instance;

/// Tracks first-use onboarding milestones via SharedPreferences.
class OnboardingService {
  static const _welcomeKey = 'onboarding_welcome_seen';

  // Contextual hint keys
  static const voiceHintKey = 'onboarding_voice_hint_seen';
  static const overscrollHintKey = 'onboarding_overscroll_hint_seen';
  static const firstTaskCreatedKey = 'onboarding_first_task_created';

  // Swipe tutorial keys
  static const swipeTutorialStepKey = 'onboarding_swipe_tutorial_step';
  // 0 = show "swipe right to complete"
  // 1 = show "swipe left to restore"
  // 2 = show "swipe left to delete"
  // 3 = tutorial done
  static const flatViewNudgeKey = 'onboarding_flat_view_nudge_seen';

  static Future<bool> hasSeenWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_welcomeKey) ?? false;
    _log.debug('onboard.hasSeenWelcome', logger: 'OnboardingService', data: {'seen': seen});
    return seen;
  }

  static Future<void> markWelcomeSeen() async {
    _log.debug('onboard.markWelcomeSeen', logger: 'OnboardingService');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_welcomeKey, true);
  }

  static Future<bool> hasSeenHint(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(key) ?? false;
    _log.debug('onboard.hasSeenHint', logger: 'OnboardingService', data: {'key': key, 'seen': seen});
    return seen;
  }

  static Future<void> markHintSeen(String key) async {
    _log.debug('onboard.markHintSeen', logger: 'OnboardingService', data: {'key': key});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }

  static Future<int> getSwipeTutorialStep() async {
    final prefs = await SharedPreferences.getInstance();
    final step = prefs.getInt(swipeTutorialStepKey) ?? 0;
    _log.debug('onboard.getSwipeTutorialStep', logger: 'OnboardingService', data: {'step': step});
    return step;
  }

  static Future<void> setSwipeTutorialStep(int step) async {
    _log.debug('onboard.setSwipeTutorialStep', logger: 'OnboardingService', data: {'step': step});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(swipeTutorialStepKey, step);
  }

  static Future<bool> hasCreatedFirstTask() async {
    final prefs = await SharedPreferences.getInstance();
    final created = prefs.getBool(firstTaskCreatedKey) ?? false;
    _log.debug('onboard.hasCreatedFirstTask', logger: 'OnboardingService', data: {'created': created});
    return created;
  }

  static Future<void> markFirstTaskCreated() async {
    _log.debug('onboard.markFirstTaskCreated', logger: 'OnboardingService');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(firstTaskCreatedKey, true);
  }
}
