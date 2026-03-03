import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../models/task.dart';

/// A compact task row used in subtask lists and domain root views.
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

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Opacity(
          opacity: isCompleted ? 0.5 : 1.0,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  domain.surface.withValues(alpha: 0.85),
                  domain.surface.withValues(alpha: 0.55),
                ],
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(
                color: domain.primary.withValues(alpha: 0.05),
                width: 0.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 6,
            ),
            child: Row(
              children: [
                Container(
                  width: AppSpacing.leftAccentBar,
                  height: 20,
                  decoration: BoxDecoration(
                    color: domain.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    task.title,
                    style: AppTypography.metadataText(color: domain.primary)
                        .copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                      decorationColor: domain.primary.withValues(alpha: 0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Metadata hints
                if (task.priority != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    task.priority![0].toUpperCase(),
                    style: AppTypography.metadataText(
                      color: domain.primary.withValues(alpha: 0.6),
                    ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
                if (task.dueDate != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('MMM d, yyyy').format(task.dueDate!),
                    style: AppTypography.metadataText(
                      color: domain.primary.withValues(alpha: 0.6),
                    ).copyWith(fontSize: 11),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: domain.primary.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
