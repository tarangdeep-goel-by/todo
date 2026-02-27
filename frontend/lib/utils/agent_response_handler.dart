import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/constants.dart';
import '../models/api_response.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../widgets/question_bottom_sheet.dart';
import '../widgets/subtask_selection_sheet.dart';
import '../widgets/styled_snackbar.dart';

/// Process a text command through the unified agent pipeline and handle the response.
///
/// Used by both PushToTalkButton and RambleSheet for consistent behavior.
/// Returns true if processing succeeded (regardless of response type).
Future<bool> processAndHandleAgentResponse({
  required BuildContext context,
  required WidgetRef ref,
  required String text,
}) async {
  try {
    final apiService = ref.read(apiServiceProvider);
    final response = await apiService.processVoiceCommand(
      text,
      AppConstants.defaultUserId,
    );

    await ref.read(taskStoreProvider.notifier).fetchAll();

    if (!context.mounted) return true;

    _handleAgentResponse(context: context, response: response);
    return true;
  } catch (e) {
    if (context.mounted) {
      showStyledSnackbar(context,
        message: 'Failed to process: $e',
        style: SnackbarStyle.error,
      );
    }
    return false;
  }
}

/// Handle an AgentResponse — show question sheet, subtask selection, or success snackbar.
void _handleAgentResponse({
  required BuildContext context,
  required AgentResponse response,
}) {
  if (response.type == 'question' && response.data != null) {
    final action = response.data!['action'] as String?;
    if (action == 'select_subtasks') {
      final parentTask = response.data!['parent_task'] as Map<String, dynamic>;
      final suggestions = (response.data!['suggestions'] as List).cast<String>();
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SubtaskSelectionSheet(
          parentTask: parentTask,
          suggestions: suggestions,
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => QuestionBottomSheet(response: response),
      );
    }
  } else {
    showStyledSnackbar(context,
      message: response.message,
      style: response.success ? SnackbarStyle.success : SnackbarStyle.error,
    );
  }
}
