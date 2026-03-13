import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
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
import 'parent_node_view.dart';
import 'flat_task_view.dart';
import '../widgets/calendar_task_view.dart';

/// Bumped by PushToTalkButton after first task creation to trigger tutorial.
final tutorialTriggerProvider = StateProvider<int>((ref) => 0);

/// Main home screen with view switching
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _log = AppLogger.instance;
  bool _tutorialActive = false;
  bool _flatViewNudgeSeen = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      Tracker.instance.screenView(screen: 'home', source: 'app_launch');
      final store = ref.read(taskStoreProvider.notifier);

      if (!Environment.isTestMode) {
        final localDb = ref.read(localDataServiceProvider);
        final currentUid = ref.read(currentUserIdProvider) ?? '';

        // User-switch guard: clear local DB if a different user logged in
        final lastUid = await localDb.getMeta('last_user_id');
        _log.debug('init.user_guard', logger: 'HomeScreen', data: {
          'lastUid': lastUid, 'currentUid': currentUid,
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
      _checkTutorial();
      // Process any deep link that arrived before UI was ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        processPendingDeepLink();
      });
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

  /// Check if swipe tutorial should be active.
  /// Activates when user has created their first task and hasn't finished tutorial.
  Future<void> _checkTutorial() async {
    final step = await OnboardingService.getSwipeTutorialStep();
    final firstTaskCreated = await OnboardingService.hasCreatedFirstTask();
    final hasTasks = ref.read(allTasksProvider).isNotEmpty;
    final nudgeSeen =
        await OnboardingService.hasSeenHint(OnboardingService.flatViewNudgeKey);
    _log.debug('onboard.tutorial_check', logger: 'HomeScreen', data: {
      'step': step, 'firstTaskCreated': firstTaskCreated,
      'hasTasks': hasTasks, 'nudgeSeen': nudgeSeen, 'mounted': mounted,
    });
    // Activate if user has tasks (flag or store) and tutorial isn't done
    if (step < 3 && (firstTaskCreated || hasTasks) && mounted) {
      // Backfill flag if missing (e.g. app data cleared but tasks exist)
      if (!firstTaskCreated && hasTasks) {
        await OnboardingService.markFirstTaskCreated();
      }
      setState(() {
        _tutorialActive = true;
        _flatViewNudgeSeen = nudgeSeen;
      });
    }
  }

  void _onTutorialComplete() {
    _log.debug('onboard.tutorial_complete', logger: 'HomeScreen');
    if (mounted) {
      setState(() => _tutorialActive = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for first task creation to activate tutorial
    ref.listen<int>(tutorialTriggerProvider, (prev, next) => _checkTutorial());

    final viewMode = ref.watch(viewModeProvider);
    final taskCount = ref.watch(allTasksProvider).length;

    // Mark flat view nudge seen when user switches to flat
    if (_tutorialActive && !_flatViewNudgeSeen && viewMode == ViewMode.flat) {
      _flatViewNudgeSeen = true;
      OnboardingService.markHintSeen(OnboardingService.flatViewNudgeKey);
    }

    const navTotalHeight =
        AppSpacing.bottomNavHeight + AppSpacing.bottomNavMarginBottom;

    // Show nudge: tutorial active, on node view, nudge not yet seen
    final showFlatNudge =
        _tutorialActive && !_flatViewNudgeSeen && viewMode == ViewMode.node;

    _log.debug('home.build', logger: 'HomeScreen', data: {
      'viewMode': viewMode.name, 'taskCount': taskCount,
      'tutorialActive': _tutorialActive, 'flatViewNudgeSeen': _flatViewNudgeSeen,
      'showFlatNudge': showFlatNudge, 'showCoaching': taskCount == 0 && !_tutorialActive,
    });

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Main content (switches between views)
            Column(
              children: [
                const TopBar(),
                // Active filter chips (only in flat view)
                if (viewMode == ViewMode.flat) const ActiveFilterChips(),
                Expanded(
                  child: switch (viewMode) {
                    ViewMode.node => const ParentNodeView(),
                    ViewMode.flat => FlatTaskView(
                        tutorialActive: _tutorialActive,
                        onTutorialComplete: _onTutorialComplete,
                      ),
                    ViewMode.calendar => const CalendarTaskView(),
                  },
                ),
              ],
            ),

            // Floating bottom nav bar
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomNavBar(),
            ),

            // Flat view nudge — bouncing arrow above "Flat" nav item
            if (showFlatNudge)
              Positioned(
                // Approximate position above the "Flat" nav item (second item)
                left: MediaQuery.of(context).size.width * 0.2,
                width: MediaQuery.of(context).size.width * 0.2,
                bottom: navTotalHeight + 4,
                child: FlatViewNudge(
                  domainColor: DomainColors.palettes.first.primary,
                ),
              ),

            // Filter button (only in flat view)
            if (viewMode == ViewMode.flat) const FilterButton(),

            // Coaching hint — rotating examples when no tasks exist
            if (taskCount == 0 && !_tutorialActive)
              Positioned(
                left: 0,
                right: 0,
                bottom: navTotalHeight + 24,
                child: const CoachingHint(),
              ),

            // Typing/processing overlay (sits above floating nav)
            Positioned(
              left: 0,
              right: 0,
              bottom: navTotalHeight,
              child: const PttInputOverlay(),
            ),
          ],
        ),
      ),
    );
  }
}
