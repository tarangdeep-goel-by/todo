import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../providers/task_store_provider.dart';
import 'task_row_tile.dart';
import '../utils/string_extensions.dart';

/// Domain root view — lists all L1 tasks (parentId == null) for a domain.
class DomainRootView extends ConsumerWidget {
  final String category;
  final bool canPop;
  final VoidCallback onNavigateBack;
  final void Function(String taskId) onTaskTap;
  final VoidCallback onClose;

  const DomainRootView({
    super.key,
    required this.category,
    required this.canPop,
    required this.onNavigateBack,
    required this.onTaskTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final domain = DomainColors.getDomain(category, true, ref.watch(domainPalettesProvider));
    final allTasks = ref.watch(allTasksProvider);
    final l1Tasks = allTasks
        .where((t) => t.parentId == null && t.category.toLowerCase() == category.toLowerCase())
        .toList()
      ..sort((a, b) {
        // Active before completed
        final aRank = a.isCompleted ? 2 : (a.isOverdue ? 0 : 1);
        final bRank = b.isCompleted ? 2 : (b.isOverdue ? 0 : 1);
        if (aRank != bRank) return aRank.compareTo(bRank);
        return b.createdAt.compareTo(a.createdAt);
      });

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onNavigateBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Close button — always dismisses overlay entirely
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    right: AppSpacing.md,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.close, color: domain.primary, size: 28),
                    onPressed: onClose,
                  ),
                ),
              ),

              // Domain title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  category.capitalize,
                  style: AppTypography.domainTitle(context, color: domain.primary)
                      .copyWith(fontSize: 28),
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  '${l1Tasks.where((t) => t.isActive).length} top-level tasks',
                  style: AppTypography.metadataText(
                    color: domain.primary.withValues(alpha: 0.6),
                  ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // L1 task list
              Expanded(
                child: l1Tasks.isEmpty
                    ? Center(
                        child: Text(
                          'No tasks in this domain',
                          style: AppTypography.metadataText(
                            color: domain.primary.withValues(alpha: 0.5),
                          ).copyWith(fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        itemCount: l1Tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (_, i) => TaskRowTile(
                          key: ValueKey(l1Tasks[i].id),
                          domain: domain,
                          task: l1Tasks[i],
                          onTap: () => onTaskTap(l1Tasks[i].id),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
