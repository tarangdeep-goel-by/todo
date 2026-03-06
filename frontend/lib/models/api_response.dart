import 'task.dart';

/// A single search result: task + relevance score
class TaskSearchResult {
  final Task task;
  final double score;

  TaskSearchResult({required this.task, required this.score});

  factory TaskSearchResult.fromJson(Map<String, dynamic> json) {
    return TaskSearchResult(
      task: Task.fromJson(json['task'] as Map<String, dynamic>),
      score: (json['score'] as num).toDouble(),
    );
  }
}

/// Response from /api/tasks/search
class TaskSearchResponse {
  final List<TaskSearchResult> results;
  final String query;
  final int totalCount;

  TaskSearchResponse({
    required this.results,
    required this.query,
    required this.totalCount,
  });

  factory TaskSearchResponse.fromJson(Map<String, dynamic> json) {
    return TaskSearchResponse(
      results: (json['results'] as List)
          .map((r) => TaskSearchResult.fromJson(r as Map<String, dynamic>))
          .toList(),
      query: json['query'] as String,
      totalCount: json['total_count'] as int,
    );
  }
}

/// A proposed task from brain dump (not yet created)
class BrainDumpTaskProposal {
  String id;
  String action; // "add", "complete", "edit", "delete", or "breakdown"
  String content;
  String? description;
  String category;
  DateTime? dueDate;
  String? priority;
  String? parentId;
  List<String> labels;
  Map<String, dynamic>? changes; // For edit actions (e.g. {"priority": "low", "parent_id": "..."})
  String? matchedTaskId; // Resolved existing task ID for complete/edit/delete
  double? confidence; // Gemini's confidence in this proposal
  List<String>? tags;
  double? estimatedHours;
  List<Map<String, dynamic>>? alternateMatches; // [{id, title, category}, ...]
  String? matchExplanation; // AI transparency: "Matched 'X' (similarity: 87%)"

  BrainDumpTaskProposal({
    required this.id,
    this.action = 'add',
    required this.content,
    this.description,
    required this.category,
    this.dueDate,
    this.priority,
    this.parentId,
    this.labels = const [],
    this.changes,
    this.matchedTaskId,
    this.confidence,
    this.tags,
    this.estimatedHours,
    this.alternateMatches,
    this.matchExplanation,
  });

  factory BrainDumpTaskProposal.fromJson(Map<String, dynamic> json) {
    return BrainDumpTaskProposal(
      id: json['id'] as String,
      action: json['action'] as String? ?? 'add',
      content: json['content'] as String,
      description: json['description'] as String?,
      category: json['category'] as String,
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'] as String)
          : null,
      priority: json['priority'] as String?,
      parentId: json['parent_id'] as String?,
      labels: (json['labels'] as List?)?.cast<String>() ?? [],
      changes: json['changes'] as Map<String, dynamic>?,
      matchedTaskId: json['matched_task_id'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      tags: (json['tags'] as List?)?.cast<String>(),
      estimatedHours: (json['estimated_hours'] as num?)?.toDouble(),
      alternateMatches: (json['alternate_matches'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      matchExplanation: json['match_explanation'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'action': action,
      'content': content,
      'description': description,
      'category': category,
      'due_date': dueDate?.toIso8601String(),
      'priority': priority,
      'parent_id': parentId,
      'labels': labels,
      'changes': changes,
      'matched_task_id': matchedTaskId,
      'confidence': confidence,
      'tags': tags,
      'estimated_hours': estimatedHours,
      'alternate_matches': alternateMatches,
      'match_explanation': matchExplanation,
    };
  }
}

/// Response from /api/agent/braindump
class BrainDumpResponse {
  final bool success;
  final List<BrainDumpTaskProposal> tasks;
  final String transcription;
  final String? message;

  BrainDumpResponse({
    required this.success,
    required this.tasks,
    required this.transcription,
    this.message,
  });

  factory BrainDumpResponse.fromJson(Map<String, dynamic> json) {
    return BrainDumpResponse(
      success: json['success'] as bool,
      tasks: (json['tasks'] as List)
          .map((t) => BrainDumpTaskProposal.fromJson(t as Map<String, dynamic>))
          .toList(),
      transcription: json['transcription'] as String,
      message: json['message'] as String?,
    );
  }
}

/// Response from /api/agent/braindump/submit
class BrainDumpSubmitResponse {
  final bool success;
  final int createdCount;
  final List<String> createdTaskIds;
  final String message;

  BrainDumpSubmitResponse({
    required this.success,
    required this.createdCount,
    required this.createdTaskIds,
    required this.message,
  });

  factory BrainDumpSubmitResponse.fromJson(Map<String, dynamic> json) {
    return BrainDumpSubmitResponse(
      success: json['success'] as bool,
      createdCount: json['created_count'] as int,
      createdTaskIds: (json['created_task_ids'] as List).cast<String>(),
      message: json['message'] as String,
    );
  }
}

/// Request to create a task
class CreateTaskRequest {
  final String? taskId;
  final String title;
  final String category;
  final String? description;
  final String? parentId;
  final DateTime? dueDate;
  final String? priority;
  final String transcription;
  final Map<String, dynamic>? aiPlacementJson;

  CreateTaskRequest({
    this.taskId,
    required this.title,
    required this.category,
    this.description,
    this.parentId,
    this.dueDate,
    this.priority,
    required this.transcription,
    this.aiPlacementJson,
  });

  Map<String, dynamic> toJson() {
    return {
      if (taskId != null) 'task_id': taskId,
      'title': title,
      'category': category,
      'description': description,
      'parent_id': parentId,
      'due_date': dueDate?.toIso8601String(),
      'priority': priority,
      'transcription': transcription,
      'ai_placement_json': aiPlacementJson,
    };
  }
}

/// Response from /api/tasks endpoint (paginated)
class TaskListResponse {
  final List<Task> tasks;
  final int totalCount;
  final int limit;
  final int offset;
  final bool hasMore;

  TaskListResponse({
    required this.tasks,
    required this.totalCount,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  factory TaskListResponse.fromJson(Map<String, dynamic> json) {
    return TaskListResponse(
      tasks: (json['tasks'] as List).map((t) => Task.fromJson(t)).toList(),
      totalCount: json['total_count'] as int,
      limit: json['limit'] as int,
      offset: json['offset'] as int,
      hasMore: json['has_more'] as bool,
    );
  }
}

/// Request to update a task.
/// Use [clearFields] to explicitly send null for fields that should be cleared
/// on the server (e.g. {'completed_at'} when un-completing a task).
class UpdateTaskRequest {
  final String? title;
  final String? description;
  final String? status;
  final String? category;
  final String? priority;
  final String? parentId;
  final DateTime? completedAt;
  final DateTime? dueDate;
  final double? estimatedHours;
  final Set<String> clearFields;

  UpdateTaskRequest({
    this.title,
    this.description,
    this.status,
    this.category,
    this.priority,
    this.parentId,
    this.completedAt,
    this.dueDate,
    this.estimatedHours,
    this.clearFields = const {},
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {};
    if (title != null) json['title'] = title;
    if (description != null) json['description'] = description;
    if (status != null) json['status'] = status;
    if (category != null) json['category'] = category;
    if (priority != null) json['priority'] = priority;
    if (parentId != null) json['parent_id'] = parentId;
    if (completedAt != null) json['completed_at'] = completedAt!.toIso8601String();
    if (dueDate != null) json['due_date'] = dueDate!.toIso8601String();
    if (estimatedHours != null) json['estimated_hours'] = estimatedHours;
    for (final field in clearFields) {
      if (!json.containsKey(field)) json[field] = null;
    }
    return json;
  }
}
