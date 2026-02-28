import 'task.dart';

/// Response from /api/agent/process endpoint
class AgentResponse {
  final bool success;
  final String message;
  final String type; // "confirmation", "question", "error"
  final Map<String, dynamic>? data;

  AgentResponse({
    required this.success,
    required this.message,
    required this.type,
    this.data,
  });

  factory AgentResponse.fromJson(Map<String, dynamic> json) {
    return AgentResponse(
      success: json['success'] as bool,
      message: json['message'] as String,
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>?,
    );
  }
}

/// A proposed task from brain dump (not yet created)
class BrainDumpTaskProposal {
  String id;
  String action; // "add", "complete", "edit", "delete", or "move"
  String content;
  String? description;
  String category;
  DateTime? dueDate;
  String? priority;
  String? parentId;
  List<String> labels;
  Map<String, dynamic>? changes; // For edit actions
  String? matchedTaskId; // Resolved existing task ID for complete/edit/delete/move
  String? targetParentId; // MOVE: resolved destination parent UUID
  String? targetContent; // MOVE: display name of target parent
  double? confidence; // Gemini's confidence in this proposal
  List<String>? tags;
  double? estimatedHours;
  List<Map<String, dynamic>>? alternateMatches; // [{id, title, category}, ...]

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
    this.targetParentId,
    this.targetContent,
    this.confidence,
    this.tags,
    this.estimatedHours,
    this.alternateMatches,
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
      targetParentId: json['target_parent_id'] as String?,
      targetContent: json['target_content'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      tags: (json['tags'] as List?)?.cast<String>(),
      estimatedHours: (json['estimated_hours'] as num?)?.toDouble(),
      alternateMatches: (json['alternate_matches'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
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
      'target_parent_id': targetParentId,
      'target_content': targetContent,
      'confidence': confidence,
      'tags': tags,
      'estimated_hours': estimatedHours,
      'alternate_matches': alternateMatches,
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
  final String userId;
  final String title;
  final String category;
  final String? description;
  final String? parentId;
  final DateTime? dueDate;
  final String transcription;
  final Map<String, dynamic>? aiPlacementJson;

  CreateTaskRequest({
    required this.userId,
    required this.title,
    required this.category,
    this.description,
    this.parentId,
    this.dueDate,
    required this.transcription,
    this.aiPlacementJson,
  });

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'title': title,
      'category': category,
      'description': description,
      'parent_id': parentId,
      'due_date': dueDate?.toIso8601String(),
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
    if (completedAt != null) json['completed_at'] = completedAt!.toIso8601String();
    if (dueDate != null) json['due_date'] = dueDate!.toIso8601String();
    if (estimatedHours != null) json['estimated_hours'] = estimatedHours;
    for (final field in clearFields) {
      if (!json.containsKey(field)) json[field] = null;
    }
    return json;
  }
}
