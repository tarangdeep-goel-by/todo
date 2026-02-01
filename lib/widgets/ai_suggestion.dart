import 'package:flutter/material.dart';
import 'package:todo/services/gemini_service.dart';
import 'package:todo/utils/constants.dart';

/// AI suggestion widget
class AISuggestion extends StatelessWidget {
  final AICategorizationResponse categorization;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final String? suggestedParentTitle;

  const AISuggestion({
    super.key,
    required this.categorization,
    this.onAccept,
    this.onReject,
    this.suggestedParentTitle,
  });

  Color _getConfidenceColor(BuildContext context, double confidence) {
    final theme = Theme.of(context);
    if (confidence >= Constants.highConfidenceThreshold) {
      return Colors.green;
    } else if (confidence >= Constants.mediumConfidenceThreshold) {
      return Colors.orange;
    } else {
      return theme.colorScheme.error;
    }
  }

  String _getConfidenceLabel(double confidence) {
    if (confidence >= Constants.highConfidenceThreshold) {
      return 'High';
    } else if (confidence >= Constants.mediumConfidenceThreshold) {
      return 'Medium';
    } else {
      return 'Low';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confidenceColor = _getConfidenceColor(context, categorization.confidence);
    final confidenceLabel = _getConfidenceLabel(categorization.confidence);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI Suggestion',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Category
            Row(
              children: [
                Text(
                  'Category: ',
                  style: theme.textTheme.bodyMedium,
                ),
                Chip(
                  label: Text(categorization.category.toUpperCase()),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Parent task
            if (suggestedParentTitle != null) ...[
              Text(
                'Place under: ',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                suggestedParentTitle!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
            ] else ...[
              Text(
                'New top-level task',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Confidence
            Row(
              children: [
                Text(
                  'Confidence: ',
                  style: theme.textTheme.bodyMedium,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: confidenceColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$confidenceLabel (${(categorization.confidence * 100).toStringAsFixed(0)}%)',
                    style: TextStyle(
                      color: confidenceColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Reasoning
            Text(
              'Reasoning:',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              categorization.reasoning,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onReject,
                  child: const Text('Choose Different'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
