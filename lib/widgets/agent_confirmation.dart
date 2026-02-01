import 'package:flutter/material.dart';
import 'package:todo/data/models/agent_intent.dart';

/// Widget to show agent confirmation before executing action
class AgentConfirmation extends StatelessWidget {
  final AgentResponse response;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  const AgentConfirmation({
    super.key,
    required this.response,
    this.onConfirm,
    this.onCancel,
  });

  IconData _getIcon() {
    if (!response.success) {
      return Icons.error_outline;
    }

    switch (response.type) {
      case AgentResponseType.confirmation:
        return Icons.check_circle_outline;
      case AgentResponseType.question:
        return Icons.help_outline;
      case AgentResponseType.error:
        return Icons.error_outline;
    }
  }

  Color _getIconColor(BuildContext context) {
    final theme = Theme.of(context);

    if (!response.success) {
      return theme.colorScheme.error;
    }

    switch (response.type) {
      case AgentResponseType.confirmation:
        return Colors.green;
      case AgentResponseType.question:
        return Colors.orange;
      case AgentResponseType.error:
        return theme.colorScheme.error;
    }
  }

  String _getTitle() {
    if (!response.success) {
      return 'Error';
    }

    switch (response.type) {
      case AgentResponseType.confirmation:
        return 'Confirm Action';
      case AgentResponseType.question:
        return 'Need Clarification';
      case AgentResponseType.error:
        return 'Error';
    }
  }

  Widget _buildQuestionOptions(BuildContext context, Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final matches = data['matches'] as List<dynamic>?;

    if (matches == null || matches.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Select task:',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...matches.map((match) {
          final title = match['title'] as String;
          return Card(
            child: ListTile(
              title: Text(title),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                // This would be handled by parent screen
                // For now, just show selection
              },
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _getIcon();
    final iconColor = _getIconColor(context);
    final title = _getTitle();

    // Determine if we should show action buttons
    final showActions = response.success &&
        (response.type == AgentResponseType.confirmation ||
            response.type == AgentResponseType.question);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Message
            Text(
              response.message,
              style: theme.textTheme.bodyLarge,
            ),

            // Additional data (for questions)
            if (response.type == AgentResponseType.question &&
                response.data != null) ...[
              _buildQuestionOptions(context, response.data!),
            ],

            // Task details (for confirmations)
            if (response.type == AgentResponseType.confirmation &&
                response.data != null) ...[
              const SizedBox(height: 12),
              _buildConfirmationDetails(context, response.data!),
            ],

            const SizedBox(height: 16),

            // Actions
            if (showActions)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onCancel != null) ...[
                    TextButton(
                      onPressed: onCancel,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (onConfirm != null)
                    FilledButton(
                      onPressed: onConfirm,
                      child: Text(
                        response.type == AgentResponseType.question
                            ? 'Select'
                            : 'Confirm',
                      ),
                    ),
                ],
              )
            else if (!response.success)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: onCancel ?? () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationDetails(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final theme = Theme.of(context);
    final details = <Widget>[];

    if (data['title'] != null) {
      details.add(
        _buildDetailRow(
          context,
          'Task',
          data['title'] as String,
        ),
      );
    }

    if (data['category'] != null) {
      details.add(
        _buildDetailRow(
          context,
          'Category',
          (data['category'] as String).toUpperCase(),
        ),
      );
    }

    if (data['changes'] != null) {
      final changes = data['changes'] as Map<String, dynamic>;
      if (changes.isNotEmpty) {
        details.add(
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Changes:',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
        changes.forEach((key, value) {
          details.add(
            _buildDetailRow(context, key, value.toString()),
          );
        });
      }
    }

    if (details.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: details,
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
