import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../providers/view_mode_provider.dart';
import '../providers/task_store_provider.dart';
import '../providers/api_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/local_data_provider.dart';
import '../providers/sync_provider.dart';
import '../services/app_logger.dart';
import '../services/onboarding_service.dart';
import '../services/notification_service.dart';
import '../services/version_service.dart';
import '../services/tracker/tracker.dart';
import '../config/environment.dart';
import '../main.dart' show processPendingDeepLink;
import '../widgets/top_bar.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/ptt_input_overlay.dart';
import '../widgets/filter_button.dart';
import '../widgets/active_filter_chips.dart';
import '../widgets/coaching_hint.dart';
import '../widgets/flat_view_nudge.dart';
import '../widgets/widget_nudge.dart';
import '../providers/tutorial_provider.dart';
import 'parent_node_view.dart';
import 'flat_task_view.dart';
import '../widgets/calendar_task_view.dart';
import 'profile_screen.dart';

/// Main home screen with view switching
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _log = AppLogger.instance;
  bool _tutorialActive = false;

  @override
  void initState() {
    super.initState();
    // Process pending deep links ASAP — before the first frame paints.
    // This avoids a visible flash of the home screen when launched via
    // widget/shortcut deep link.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      processPendingDeepLink();
    });
    Future.microtask(() async {
      Tracker.instance.screenView(screen: 'home', source: 'app_launch');
      final store = ref.read(taskStoreProvider.notifier);

      if (!Environment.isTestMode) {
        final localDb = ref.read(localDataServiceProvider);
        final currentUid = ref.read(currentUserIdProvider) ?? '';

        // User-switch guard: clear local DB if a different user logged in
        final lastUid = await localDb.getMeta('last_user_id');
        _log.debug('init.user_guard', logger: 'HomeScreen', data: {
          'hasLastUid': lastUid != null,
          'hasCurrentUid': currentUid.isNotEmpty,
          'switched': lastUid != null && lastUid != currentUid,
        });
        if (lastUid != null && lastUid != currentUid) {
          await localDb.clearAll();
        }
        await localDb.setMeta('last_user_id', currentUid);

        _log.debug('init.loadLocal', logger: 'HomeScreen');
        await store.loadLocal(); // Instant: cached data → UI
        _log.debug('init.sync_start', logger: 'HomeScreen');
        final syncService = ref.read(syncServiceProvider);
        syncService.sync(); // Background: push pending + pull fresh
        _log.debug('init.sync_fired', logger: 'HomeScreen');
        syncService.startPeriodicSync();
        // Initialize connectivity provider
        ref.read(isOnlineProvider);
        // Eagerly initialize speech recognition to avoid delay on first tap
        ref.read(speechServiceProvider).initialize();
        // Initialize push notifications (registers FCM token with backend)
        NotificationService.instance.initialize(ref.read(apiServiceProvider));
        // Check client version compatibility (non-blocking)
        _checkVersion();
      } else {
        // Test mode: fetch directly from API, skip offline infra
        await store.fetchAll();
      }
      _initTutorial();
    });
  }

  void _checkVersion() {
    final dio = ref.read(apiServiceProvider).dio;
    VersionService.checkCompatibility(dio).then((ok) {
      if (!ok && mounted) {
        // Show force-update dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Update Required'),
            content: const Text('Please update the app to continue.'),
            actions: const [],
          ),
        );
      }
    });
  }

  /// Load tutorial state from SharedPreferences into the provider.
  Future<void> _initTutorial() async {
    final step = await OnboardingService.getSwipeTutorialStep();
    final firstTaskCreated = await OnboardingService.hasCreatedFirstTask();
    _log.debug('onboard.init_tutorial', logger: 'HomeScreen', data: {
      'step': step, 'firstTaskCreated': firstTaskCreated,
    });
    if (!mounted) return;
    if (firstTaskCreated && step < OnboardingService.tutorialDoneStep) {
      // Resume tutorial from persisted step
      ref.read(tutorialStepProvider.notifier).state = step;
      setState(() => _tutorialActive = true);
    } else if (!firstTaskCreated) {
      // New user — step -1 (show "add task" nudge)
      ref.read(tutorialStepProvider.notifier).state = -1;
    }
  }

  /// Called when flat view swipe steps (0-1) are done → step 2+ on other screens.
  void _onFlatTutorialComplete() {
    _log.debug('onboard.flat_tutorial_done', logger: 'HomeScreen');
    // Tutorial continues on profile/archive — _tutorialActive stays true
  }

  @override
  Widget build(BuildContext context) {
    final tutorialStep = ref.watch(tutorialStepProvider);
    final viewMode = ref.watch(viewModeProvider);
    final taskCount = ref.watch(allTasksProvider).length;

    // Activate tutorial when first task is created (step advances from -1 to 0)
    ref.listen<int>(tutorialStepProvider, (prev, next) {
      if (prev == -1 && next == 0 && mounted) {
        setState(() => _tutorialActive = true);
      }
      // Tutorial done
      if (next >= OnboardingService.tutorialDoneStep && mounted) {
        setState(() => _tutorialActive = false);
      }
    });

    // Non-blocking: dismiss tutorial if user changes view during flat view steps (0-2)
    ref.listen<ViewMode>(viewModeProvider, (prev, next) {
      if (_tutorialActive && tutorialStep >= 0 && tutorialStep < 3 && next != ViewMode.flat) {
        _log.debug('onboard.dismiss_view_change', logger: 'HomeScreen', data: {
          'from': prev?.name, 'to': next.name, 'step': tutorialStep,
        });
        ref.read(tutorialStepProvider.notifier).state = OnboardingService.tutorialDoneStep;
        OnboardingService.setSwipeTutorialStep(OnboardingService.tutorialDoneStep);
        setState(() => _tutorialActive = false);
      }
    });

    // Show profile nudge: tutorial step 3 = "go to archive"
    final showProfileNudge = _tutorialActive && tutorialStep == 3;

    _log.debug('home.build', logger: 'HomeScreen', data: {
      'viewMode': viewMode.name, 'taskCount': taskCount,
      'tutorialActive': _tutorialActive, 'tutorialStep': tutorialStep,
      'showProfileNudge': showProfileNudge,
      'showCoaching': taskCount == 0 && tutorialStep < 0,
    });

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (viewMode != ViewMode.profile) const TopBar(),
            if (viewMode != ViewMode.profile) const WidgetNudge(),
            // Active filter chips (only in flat view)
            if (viewMode == ViewMode.flat) const ActiveFilterChips(),
            Expanded(
              child: Stack(
                children: [
                  switch (viewMode) {
                    ViewMode.node => const ParentNodeView(),
                    ViewMode.flat => FlatTaskView(
                        tutorialActive: _tutorialActive,
                        onTutorialComplete: _onFlatTutorialComplete,
                      ),
                    ViewMode.calendar => const CalendarTaskView(),
                    ViewMode.profile => const ProfileScreen(),
                  },

                  // Profile nudge — bouncing arrow above "Profile" nav item
                  if (showProfileNudge)
                    Positioned(
                      right: MediaQuery.of(context).size.width * 0.02,
                      width: MediaQuery.of(context).size.width * 0.2,
                      bottom: 4,
                      child: FlatViewNudge(
                        domainColor: DomainColors.palettes.first.primary,
                        label: 'Go to Archive',
                      ),
                    ),

                  // Filter button (only in flat view)
                  if (viewMode == ViewMode.flat) const FilterButton(),

                  // Coaching hint — rotating examples when no tasks exist
                  if (taskCount == 0 && tutorialStep < 0)
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 24,
                      child: CoachingHint(),
                    ),

                  // Typing/processing overlay (sits above nav)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: PttInputOverlay(),
                  ),
                ],
              ),
            ),
            const BottomNavBar(),
          ],
        ),
      ),
    );
  }
}
