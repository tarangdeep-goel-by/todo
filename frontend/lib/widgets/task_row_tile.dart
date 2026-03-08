import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/task.dart';
import '../utils/string_extensions.dart';

/// A compact task row used in domain root views.
/// Styled to match the subtask items in task detail overlay.
class TaskRowTile extends StatelessWidget {
  final DomainPalette domain;
  final Task task;
  final VoidCallback onTap;

  const TaskRowTile({
    super.key,
    required this.domain,
    required this.task,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.isCompleted;
    final isOverdue = task.isOverdue;

    Widget row = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isOverdue
              ? AppColors.overdue.withValues(alpha: 0.05)
              : domain.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Accent bar
            Container(
              width: 3,
              height: 28,
              decoration: BoxDecoration(
                color: isCompleted
                    ? domain.primary.withValues(alpha: 0.3)
                    : domain.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            // Title + metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.sentenceTitle,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isCompleted
                          ? AppColors.darkText.withValues(alpha: 0.4)
                          : AppColors.darkText.withValues(alpha: 0.8),
                      decoration: isCompleted ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.darkText.withValues(alpha: 0.3),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (task.dueDate != null || task.priority != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (task.dueDate != null) ...[
                          if (isOverdue) ...[
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: AppColors.overdue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            DateFormat('MMM d').format(task.dueDate!),
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              color: isOverdue
                                  ? AppColors.overdue
                                  : domain.primary.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                        if (task.dueDate != null && task.priority != null)
                          const SizedBox(width: 8),
                        if (task.priority != null)
                          Text(
                            task.priority!.capitalize,
                            style: GoogleFonts.dmSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: switch (task.priority!.toLowerCase()) {
                                'high' => AppColors.priorityHigh,
                                'medium' => AppColors.priorityMedium,
                                'low' => AppColors.priorityLow,
                                _ => domain.primary.withValues(alpha: 0.4),
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status indicator
            if (isCompleted)
              Icon(Icons.check_circle, size: 16, color: AppColors.completed.withValues(alpha: 0.6))
            else
              Icon(
                Icons.chevron_right,
                size: 16,
                color: domain.primary.withValues(alpha: 0.3),
              ),
          ],
        ),
      ),
    );

    if (isCompleted) {
      row = Opacity(opacity: 0.6, child: row);
    }

    return row;
  }
}
