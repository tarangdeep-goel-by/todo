import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/theme.dart';
import '../providers/view_mode_provider.dart';
import '../providers/task_store_provider.dart';
import '../providers/api_provider.dart';
import '../services/onboarding_service.dart';
import '../services/notification_service.dart';
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

/// Main home screen with view switching
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _tutorialActive = false;
  bool _flatViewNudgeSeen = false;
  bool _demoInjected = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(taskStoreProvider.notifier).fetchAll();
      // Eagerly initialize speech recognition to avoid delay on first tap
      ref.read(speechServiceProvider).initialize();
      // Initialize push notifications (registers FCM token with backend)
      NotificationService.instance.initialize(ref.read(apiServiceProvider));
      _checkWelcome();
    });
  }

  Future<void> _checkWelcome() async {
    final seen = await OnboardingService.hasSeenWelcome();
    if (!seen) {
      await OnboardingService.markWelcomeSeen();
    }
    await _checkTutorial();
  }

  Future<void> _checkTutorial() async {
    final step = await OnboardingService.getSwipeTutorialStep();
    final nudgeSeen =
        await OnboardingService.hasSeenHint(OnboardingService.flatViewNudgeKey);
    if (step < 3 && mounted) {
      setState(() {
        _tutorialActive = true;
        _flatViewNudgeSeen = nudgeSeen;
      });
      _injectDemoTask();
    }
  }

  void _injectDemoTask() {
    if (_demoInjected) return;
    final store = ref.read(taskStoreProvider.notifier);
    final allTasks = ref.read(allTasksProvider);

    // Only inject if no real tasks exist
    if (allTasks.isEmpty ||
        (allTasks.length == 1 &&
            allTasks.first.id == OnboardingService.demoTaskId)) {
      store.upsertTask(OnboardingService.createDemoTask());

      // Inject demo category if not present
      final cats = ref.read(categoriesProvider);
      final hasDemo = cats.any(
          (c) => c.name.toLowerCase() == OnboardingService.demoCategoryName);
      if (!hasDemo) {
        ref.read(categoriesProvider.notifier).update(
            (s) => [...s, OnboardingService.createDemoCategory()]);
      }
      _demoInjected = true;
    }
  }

  void _onTutorialComplete() {
    if (mounted) {
      setState(() => _tutorialActive = false);
      // Clean up demo category
      ref.read(categoriesProvider.notifier).update(
        (s) => s
            .where((c) =>
                c.name.toLowerCase() != OnboardingService.demoCategoryName ||
                c.id != 'onboarding-demo-category')
            .toList(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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

            // Coaching hint — rotating examples when few tasks exist
            // Hide during tutorial to avoid visual clutter
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
