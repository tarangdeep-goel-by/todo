import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';
import '../models/category.dart';

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

  // Demo task/category IDs
  static const demoTaskId = 'onboarding-demo-task';
  static const demoCategoryName = 'user';

  static Future<bool> hasSeenWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_welcomeKey) ?? false;
  }

  static Future<void> markWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_welcomeKey, true);
  }

  static Future<bool> hasSeenHint(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<void> markHintSeen(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }

  static Future<int> getSwipeTutorialStep() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(swipeTutorialStepKey) ?? 0;
  }

  static Future<void> setSwipeTutorialStep(int step) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(swipeTutorialStepKey, step);
  }

  static Task createDemoTask() => Task(
        id: demoTaskId,
        userId: 'default-user',
        title: 'hello world',
        category: demoCategoryName,
        status: 'active',
        priority: 'high',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transcription: '',
      );

  static Category createDemoCategory() => Category(
        id: 'onboarding-demo-category',
        name: demoCategoryName,
        position: 0,
        createdAt: DateTime.now(),
      );
}
