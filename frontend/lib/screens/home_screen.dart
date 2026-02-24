import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/view_mode_provider.dart';
import '../providers/task_store_provider.dart';
import '../providers/api_provider.dart';
import '../widgets/top_bar.dart';
import '../widgets/push_to_talk_button.dart';
import '../widgets/filter_button.dart';
import '../widgets/active_filter_chips.dart';
import 'parent_node_view.dart';
import 'flat_task_view.dart';

/// Main home screen with view switching
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(taskStoreProvider.notifier).fetchAll();
      // Eagerly initialize speech recognition to avoid delay on first tap
      ref.read(speechServiceProvider).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewMode = ref.watch(viewModeProvider);

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
                  child: viewMode == ViewMode.node
                      ? const ParentNodeView()
                      : const FlatTaskView(),
                ),
              ],
            ),

            // Filter button (only in flat view)
            if (viewMode == ViewMode.flat) const FilterButton(),

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
