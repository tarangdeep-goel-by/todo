import 'task.dart';

/// Response from /api/agent/process endpoint
class AgentResponse {
  final String message;
  final Task? task;
  final String intent;
  final String status;

  AgentResponse({
    required this.message,
    this.task,
    required this.intent,
    required this.status,
  });

  factory AgentResponse.fromJson(Map<String, dynamic> json) {
    return AgentResponse(
      message: json['message'] as String,
      task: json['task'] != null ? Task.fromJson(json['task']) : null,
      intent: json['intent'] as String,
      status: json['status'] as String,
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

/// Request to update a task
class UpdateTaskRequest {
  final String? title;
  final String? description;
  final String? status;
  final String? category;
  final String? priority;
  final DateTime? completedAt;
  final DateTime? dueDate;

  UpdateTaskRequest({
    this.title,
    this.description,
    this.status,
    this.category,
    this.priority,
    this.completedAt,
    this.dueDate,
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
    return json;
  }
}
