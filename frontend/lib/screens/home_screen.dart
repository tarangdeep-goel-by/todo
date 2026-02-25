import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/view_mode_provider.dart';
import '../providers/task_store_provider.dart';
import '../providers/api_provider.dart';
import '../services/onboarding_service.dart';
import '../widgets/top_bar.dart';
import '../widgets/push_to_talk_button.dart';
import '../widgets/filter_button.dart';
import '../widgets/active_filter_chips.dart';
import '../widgets/coaching_hint.dart';
import '../widgets/welcome_overlay.dart';
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
  bool _showWelcome = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(taskStoreProvider.notifier).fetchAll();
      // Eagerly initialize speech recognition to avoid delay on first tap
      ref.read(speechServiceProvider).initialize();
      _checkWelcome();
    });
  }

  Future<void> _checkWelcome() async {
    final seen = await OnboardingService.hasSeenWelcome();
    if (!seen && mounted) {
      setState(() => _showWelcome = true);
    }
  }

  Future<void> _dismissWelcome() async {
    await OnboardingService.markWelcomeSeen();
    if (mounted) {
      setState(() => _showWelcome = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show welcome overlay on first launch (data loads behind it)
    if (_showWelcome) {
      return WelcomeOverlay(onDismiss: _dismissWelcome);
    }

    final viewMode = ref.watch(viewModeProvider);
    final taskCount = ref.watch(allTasksProvider).length;

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
                    ViewMode.flat => const FlatTaskView(),
                    ViewMode.calendar => const CalendarTaskView(),
                  },
                ),
              ],
            ),

            // Filter button (only in flat view)
            if (viewMode == ViewMode.flat) const FilterButton(),

            // Coaching hint — rotating examples when no tasks exist
            if (taskCount == 0)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 100,
                child: CoachingHint(),
              ),

            // Push-to-talk CTA button (always visible)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: PushToTalkButton(),
            ),
          ],
        ),
      ),
    );
  }
}
