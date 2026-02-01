import 'package:todo/data/models/agent_intent.dart';
import 'package:todo/data/models/ai_placement.dart';
import 'package:todo/data/models/task.dart';
import 'package:todo/data/repositories/task_repository.dart';
import 'package:todo/services/gemini_service.dart';

/// Service for AI agent voice command processing
class AgentService {
  final GeminiService _geminiService;
  final TaskRepository _taskRepository;

  AgentService({
    required GeminiService geminiService,
    required TaskRepository taskRepository,
  })  : _geminiService = geminiService,
        _taskRepository = taskRepository;

  /// Main entry point - processes voice command from audio file
  Future<AgentResponse> processVoiceCommand(String audioPath) async {
    try {
      // 1. Transcribe audio
      final transcription = await _geminiService.transcribeAudio(audioPath);

      if (transcription.isEmpty) {
        return AgentResponse.error('Could not understand the audio. Please try again.');
      }

      // 2. Detect intent
      final intent = await _detectIntent(transcription);

      // 3. Check confidence threshold
      if (intent.confidence < 0.6) {
        return AgentResponse.error(
          'Not sure what you meant by "$transcription". Please try rephrasing.',
        );
      }

      // 4. Execute based on intent
      switch (intent.intent) {
        case IntentType.add:
          return await _handleAdd(intent);
        case IntentType.complete:
          return await _handleComplete(intent);
        case IntentType.delete:
          return await _handleDelete(intent);
        case IntentType.edit:
          return await _handleEdit(intent);
        case IntentType.query:
          return await _handleQuery(intent);
        case IntentType.unknown:
          return AgentResponse.error(
            'Unclear command. Try saying "Add [task]", "Complete [task]", or "Show my tasks".',
          );
      }
    } catch (e) {
      return AgentResponse.error('Failed to process command: $e');
    }
  }

  /// Detect intent from transcription
  Future<AgentIntent> _detectIntent(String transcription) async {
    final taskTree = await _buildTaskTree();
    return await _geminiService.detectIntent(
      transcription: transcription,
      taskTree: taskTree,
    );
  }

  /// Build task tree for context
  Future<Map<String, List<Task>>> _buildTaskTree() async {
    final workTasks = await _taskRepository.getTasksByCategory(TaskCategory.work);
    final personalTasks = await _taskRepository.getTasksByCategory(TaskCategory.personal);

    final tree = <String, List<Task>>{};

    // Group work tasks
    tree['work'] = workTasks.where((t) => t.parentId == null).toList();
    for (final task in workTasks) {
      final children = workTasks.where((t) => t.parentId == task.id).toList();
      if (children.isNotEmpty) {
        tree[task.id] = children;
      }
    }

    // Group personal tasks
    tree['personal'] = personalTasks.where((t) => t.parentId == null).toList();
    for (final task in personalTasks) {
      final children = personalTasks.where((t) => t.parentId == task.id).toList();
      if (children.isNotEmpty) {
        tree[task.id] = children;
      }
    }

    return tree;
  }

  /// Handle ADD intent
  Future<AgentResponse> _handleAdd(AgentIntent intent) async {
    try {
      final params = intent.parameters;
      final title = params['title'] as String?;
      final categoryStr = params['category'] as String?;
      final suggestedParent = params['suggestedParent'] as String?;

      if (title == null || title.isEmpty) {
        return AgentResponse.error('Could not extract task title from your command.');
      }

      final category = categoryStr != null
          ? TaskCategory.fromString(categoryStr)
          : TaskCategory.personal;

      // Create AI placement
      final aiPlacement = AIPlacement(
        suggestedParent: suggestedParent,
        confidence: intent.confidence,
        reasoning: 'AI agent categorization',
      );

      // Create task
      final taskId = await _taskRepository.createTask(
        title: title,
        category: category,
        transcription: title,
        aiPlacement: aiPlacement,
        parentId: suggestedParent,
      );

      return AgentResponse.success(
        message: 'Created task: $title',
        data: {'taskId': taskId, 'title': title, 'category': category.name},
      );
    } catch (e) {
      return AgentResponse.error('Failed to create task: $e');
    }
  }

  /// Handle COMPLETE intent
  Future<AgentResponse> _handleComplete(AgentIntent intent) async {
    try {
      final params = intent.parameters;
      final taskQuery = params['taskQuery'] as String?;

      if (taskQuery == null || taskQuery.isEmpty) {
        return AgentResponse.error('Could not identify which task to complete.');
      }

      // Search for matching tasks
      final matches = await _searchTasks(taskQuery);

      if (matches.isEmpty) {
        return AgentResponse.error('Could not find task matching "$taskQuery".');
      }

      if (matches.length > 1) {
        // Multiple matches - ask user to clarify
        return AgentResponse.question(
          message: 'Found ${matches.length} tasks matching "$taskQuery". Which one?',
          data: {
            'matches': matches.map((t) => {'id': t.id, 'title': t.title}).toList(),
            'action': 'complete',
          },
        );
      }

      // Single match - mark as complete
      final task = matches.first;
      await _taskRepository.markTaskDone(task.id);

      return AgentResponse.success(
        message: 'Completed task: ${task.title}',
        data: {'taskId': task.id, 'title': task.title},
      );
    } catch (e) {
      return AgentResponse.error('Failed to complete task: $e');
    }
  }

  /// Handle DELETE intent
  Future<AgentResponse> _handleDelete(AgentIntent intent) async {
    try {
      final params = intent.parameters;
      final taskQuery = params['taskQuery'] as String?;

      if (taskQuery == null || taskQuery.isEmpty) {
        return AgentResponse.error('Could not identify which task to delete.');
      }

      // Search for matching tasks
      final matches = await _searchTasks(taskQuery);

      if (matches.isEmpty) {
        return AgentResponse.error('Could not find task matching "$taskQuery".');
      }

      if (matches.length > 1) {
        // Multiple matches - ask user to clarify
        return AgentResponse.question(
          message: 'Found ${matches.length} tasks matching "$taskQuery". Which one?',
          data: {
            'matches': matches.map((t) => {'id': t.id, 'title': t.title}).toList(),
            'action': 'delete',
          },
        );
      }

      // Single match - need confirmation for destructive action
      final task = matches.first;
      return AgentResponse.question(
        message: 'Are you sure you want to delete "${task.title}"?',
        data: {
          'taskId': task.id,
          'title': task.title,
          'action': 'delete',
          'requiresConfirmation': true,
        },
      );
    } catch (e) {
      return AgentResponse.error('Failed to delete task: $e');
    }
  }

  /// Handle EDIT intent
  Future<AgentResponse> _handleEdit(AgentIntent intent) async {
    try {
      final params = intent.parameters;
      final taskQuery = params['taskQuery'] as String?;
      final changes = params['changes'] as Map<String, dynamic>?;

      if (taskQuery == null || taskQuery.isEmpty) {
        return AgentResponse.error('Could not identify which task to edit.');
      }

      if (changes == null || changes.isEmpty) {
        return AgentResponse.error('Could not identify what changes to make.');
      }

      // Search for matching tasks
      final matches = await _searchTasks(taskQuery);

      if (matches.isEmpty) {
        return AgentResponse.error('Could not find task matching "$taskQuery".');
      }

      if (matches.length > 1) {
        // Multiple matches - ask user to clarify
        return AgentResponse.question(
          message: 'Found ${matches.length} tasks matching "$taskQuery". Which one?',
          data: {
            'matches': matches.map((t) => {'id': t.id, 'title': t.title}).toList(),
            'action': 'edit',
            'changes': changes,
          },
        );
      }

      // Single match - apply changes
      final task = matches.first;
      await _applyTaskChanges(task.id, changes);

      // Build change summary
      final changeSummary = _buildChangeSummary(changes);

      return AgentResponse.success(
        message: 'Updated "${task.title}": $changeSummary',
        data: {'taskId': task.id, 'title': task.title, 'changes': changes},
      );
    } catch (e) {
      return AgentResponse.error('Failed to edit task: $e');
    }
  }

  /// Handle QUERY intent
  Future<AgentResponse> _handleQuery(AgentIntent intent) async {
    try {
      final params = intent.parameters;
      final filters = params['filters'] as Map<String, dynamic>?;

      // Get tasks based on filters
      List<Task> tasks = [];

      if (filters != null && filters['category'] != null) {
        final category = TaskCategory.fromString(filters['category'] as String);
        tasks = await _taskRepository.getTasksByCategory(category);
      } else {
        // Get all tasks
        final workTasks = await _taskRepository.getTasksByCategory(TaskCategory.work);
        final personalTasks = await _taskRepository.getTasksByCategory(TaskCategory.personal);
        tasks = [...workTasks, ...personalTasks];
      }

      // Filter by status if specified
      if (filters != null && filters['status'] != null) {
        final status = TaskStatus.fromString(filters['status'] as String);
        tasks = tasks.where((t) => t.status == status).toList();
      } else {
        // Default to active tasks only
        tasks = tasks.where((t) => t.status == TaskStatus.active).toList();
      }

      // Build response message
      final message = _buildQueryResponse(tasks, filters);

      return AgentResponse.success(
        message: message,
        data: {
          'tasks': tasks.map((t) => {'id': t.id, 'title': t.title}).toList(),
          'count': tasks.length,
        },
      );
    } catch (e) {
      return AgentResponse.error('Failed to query tasks: $e');
    }
  }

  /// Search tasks by query string (fuzzy match)
  Future<List<Task>> _searchTasks(String query) async {
    final workTasks = await _taskRepository.getTasksByCategory(TaskCategory.work);
    final personalTasks = await _taskRepository.getTasksByCategory(TaskCategory.personal);
    final allTasks = [...workTasks, ...personalTasks];

    // Filter to active tasks only
    final activeTasks = allTasks.where((t) => t.status == TaskStatus.active).toList();

    // Simple fuzzy search - match if query words appear in title
    final queryWords = query.toLowerCase().split(' ');

    return activeTasks.where((task) {
      final titleLower = task.title.toLowerCase();
      return queryWords.any((word) => titleLower.contains(word));
    }).toList();
  }

  /// Apply changes to task
  Future<void> _applyTaskChanges(String taskId, Map<String, dynamic> changes) async {
    String? title;
    DateTime? dueDate;
    TaskCategory? category;

    if (changes['title'] != null) {
      title = changes['title'] as String;
    }

    if (changes['dueDate'] != null) {
      // Parse ISO date or relative dates
      final dueDateStr = changes['dueDate'] as String;
      dueDate = _parseDate(dueDateStr);
    }

    if (changes['category'] != null) {
      category = TaskCategory.fromString(changes['category'] as String);
    }

    await _taskRepository.updateTask(
      taskId,
      title: title,
      dueDate: dueDate,
      category: category,
    );
  }

  /// Parse date from string (ISO format or relative)
  DateTime? _parseDate(String dateStr) {
    try {
      // Try ISO format first
      return DateTime.parse(dateStr);
    } catch (e) {
      // Handle relative dates
      final now = DateTime.now();
      final lower = dateStr.toLowerCase();

      if (lower.contains('today')) {
        return DateTime(now.year, now.month, now.day);
      } else if (lower.contains('tomorrow')) {
        return DateTime(now.year, now.month, now.day + 1);
      } else if (lower.contains('next week')) {
        return now.add(const Duration(days: 7));
      }

      return null;
    }
  }

  /// Build change summary message
  String _buildChangeSummary(Map<String, dynamic> changes) {
    final parts = <String>[];

    if (changes['title'] != null) {
      parts.add('title changed');
    }
    if (changes['dueDate'] != null) {
      parts.add('due date updated');
    }
    if (changes['category'] != null) {
      parts.add('moved to ${changes['category']}');
    }

    return parts.join(', ');
  }

  /// Build query response message
  String _buildQueryResponse(List<Task> tasks, Map<String, dynamic>? filters) {
    if (tasks.isEmpty) {
      return 'No tasks found.';
    }

    final categoryStr = filters?['category'] as String?;
    final statusStr = filters?['status'] as String?;

    final prefix = <String>[];
    if (statusStr != null) prefix.add(statusStr);
    if (categoryStr != null) prefix.add(categoryStr);

    final descriptor = prefix.isNotEmpty ? '${prefix.join(' ')} ' : '';

    if (tasks.length == 1) {
      return 'You have 1 ${descriptor}task: ${tasks.first.title}';
    } else if (tasks.length <= 5) {
      final titles = tasks.map((t) => t.title).join(', ');
      return 'You have ${tasks.length} ${descriptor}tasks: $titles';
    } else {
      return 'You have ${tasks.length} ${descriptor}tasks.';
    }
  }

  /// Execute confirmed action (for follow-up after user confirmation)
  Future<AgentResponse> executeConfirmedAction({
    required String action,
    required String taskId,
  }) async {
    try {
      final task = await _taskRepository.getTask(taskId);
      if (task == null) {
        return AgentResponse.error('Task not found.');
      }

      switch (action) {
        case 'delete':
          await _taskRepository.archiveTask(taskId);
          return AgentResponse.success(message: 'Deleted task: ${task.title}');
        case 'complete':
          await _taskRepository.markTaskDone(taskId);
          return AgentResponse.success(message: 'Completed task: ${task.title}');
        default:
          return AgentResponse.error('Unknown action: $action');
      }
    } catch (e) {
      return AgentResponse.error('Failed to execute action: $e');
    }
  }
}
