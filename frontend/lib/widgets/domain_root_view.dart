import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../models/task.dart';
import '../providers/task_store_provider.dart';
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
                        itemBuilder: (_, i) => _buildTaskRow(
                          l1Tasks[i],
                          domain,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskRow(Task task, DomainPalette domain) {
    final isOverdue = task.isOverdue;
    final isCompleted = task.isCompleted;

    // Date formatting
    String? dateText;
    if (task.dueDate != null) {
      dateText = DateFormat('d MMM').format(task.dueDate!);
    }

    // Priority letter + color
    String? priorityLetter;
    Color? priorityColor;
    if (task.priority != null) {
      switch (task.priority!) {
        case 'high':
          priorityLetter = 'H';
          priorityColor = const Color(0xFFFF6B6B);
        case 'medium':
          priorityLetter = 'M';
          priorityColor = const Color(0xFFFFA726);
        case 'low':
          priorityLetter = 'L';
          priorityColor = const Color(0xFF66BB6A);
      }
    }

    // Background color
    final bgColor = isOverdue
        ? const Color(0x0DFF6B6B)
        : domain.primary.withValues(alpha: 0.04);

    Widget row = GestureDetector(
      onTap: () => onTaskTap(task.id),
      child: Container(
        key: ValueKey(task.id),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Overdue red dot
            if (isOverdue) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6B6B),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],

            // 3px accent bar
            Container(
              width: 3,
              height: 28,
              decoration: BoxDecoration(
                color: domain.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),

            // Title
            Expanded(
              child: Text(
                task.sentenceTitle,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: domain.primary,
                  decoration:
                      isCompleted ? TextDecoration.lineThrough : null,
                  decorationColor: domain.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Date
            if (dateText != null) ...[
              const SizedBox(width: 8),
              Text(
                dateText,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: isOverdue
                      ? const Color(0xFFFF6B6B)
                      : domain.primary.withValues(alpha: 0.6),
                ),
              ),
            ],

            // Priority letter
            if (priorityLetter != null) ...[
              const SizedBox(width: 8),
              Text(
                priorityLetter,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: priorityColor,
                ),
              ),
            ],

            // Trailing icon
            const SizedBox(width: 8),
            Icon(
              isCompleted ? Icons.check_circle : Icons.chevron_right,
              size: 16,
              color: domain.primary.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );

    // Completed rows: 0.5 opacity
    if (isCompleted) {
      row = Opacity(opacity: 0.5, child: row);
    }

    return row;
  }
}
