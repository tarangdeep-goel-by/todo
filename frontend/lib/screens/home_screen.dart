import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/view_mode_provider.dart';
import '../widgets/top_bar.dart';
import '../widgets/push_to_talk_button.dart';
import 'parent_node_view.dart';
import 'flat_task_view.dart';

/// Main home screen with view switching
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(viewModeProvider);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Main content (switches between views)
            Column(
              children: [
                const TopBar(),
                Expanded(
                  child: viewMode == ViewMode.node
                      ? const ParentNodeView()
                      : const FlatTaskView(),
                ),
              ],
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
