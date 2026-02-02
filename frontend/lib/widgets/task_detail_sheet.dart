import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../models/task.dart';

/// Task detail bottom sheet showing all fields
class TaskDetailSheet extends StatelessWidget {
  final Task task;

  const TaskDetailSheet({
    super.key,
    required this.task,
  });

  @override
  Widget build(BuildContext context) {
    final domain = DomainColors.getDomain(task.category, true);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.darkText.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  task.title,
                  style: AppTypography.domainTitle(
                    context,
                    color: domain.primary,
                  ).copyWith(fontSize: 28),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Fields
                _buildField('ID', task.id, domain.primary),
                _buildField('Category', task.category, domain.primary),
                _buildField('Status', task.status, domain.primary),

                if (task.description != null)
                  _buildField('Description', task.description!, domain.primary),

                if (task.parentId != null)
                  _buildField('Parent ID', task.parentId!, domain.primary),

                _buildField(
                  'Created',
                  _formatDateTime(task.createdAt),
                  domain.primary,
                ),

                _buildField(
                  'Updated',
                  _formatDateTime(task.updatedAt),
                  domain.primary,
                ),

                if (task.dueDate != null)
                  _buildField(
                    'Due Date',
                    _formatDateTime(task.dueDate!),
                    domain.primary,
                  ),

                if (task.completedAt != null)
                  _buildField(
                    'Completed',
                    _formatDateTime(task.completedAt!),
                    domain.primary,
                  ),

                if (task.audioFileUri != null)
                  _buildField('Audio File', task.audioFileUri!, domain.primary),

                _buildField('Transcription', task.transcription, domain.primary),

                if (task.aiPlacementJson != null)
                  _buildField(
                    'AI Placement',
                    task.aiPlacementJson.toString(),
                    domain.primary,
                  ),

                const SizedBox(height: AppSpacing.md),

                // Close button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: domain.primary,
                      foregroundColor: domain.textOnPrimary,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: AppTypography.ctaLabelText(
                        color: domain.textOnPrimary,
                      ).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.metadataText(
              color: AppColors.darkText.withValues(alpha: 0.6),
            ).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.metadataText(
              color: color,
            ).copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('MMM d, yyyy h:mm a').format(dateTime);
  }
}
