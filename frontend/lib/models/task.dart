/// Task model representing a single task
class Task {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final String? parentId;
  final String category; // work, personal, health, learning, projects
  final String status; // active, completed, archived
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final String? audioFileUri;
  final String transcription;
  final Map<String, dynamic>? aiPlacementJson;

  Task({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.parentId,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.dueDate,
    this.completedAt,
    this.audioFileUri,
    required this.transcription,
    this.aiPlacementJson,
  });

  /// Create Task from JSON
  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      parentId: json['parent_id'] as String?,
      category: json['category'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      dueDate:
          json['due_date'] != null ? DateTime.parse(json['due_date']) : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      audioFileUri: json['audio_file_uri'] as String?,
      transcription: json['transcription'] as String,
      aiPlacementJson: json['ai_placement_json'] as Map<String, dynamic>?,
    );
  }

  /// Convert Task to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'description': description,
      'parent_id': parentId,
      'category': category,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'audio_file_uri': audioFileUri,
      'transcription': transcription,
      'ai_placement_json': aiPlacementJson,
    };
  }

  /// Create a copy with updated fields
  Task copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    String? parentId,
    String? category,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? dueDate,
    DateTime? completedAt,
    String? audioFileUri,
    String? transcription,
    Map<String, dynamic>? aiPlacementJson,
  }) {
    return Task(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      parentId: parentId ?? this.parentId,
      category: category ?? this.category,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dueDate: dueDate ?? this.dueDate,
      completedAt: completedAt ?? this.completedAt,
      audioFileUri: audioFileUri ?? this.audioFileUri,
      transcription: transcription ?? this.transcription,
      aiPlacementJson: aiPlacementJson ?? this.aiPlacementJson,
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isActive => status == 'active';
  bool get isArchived => status == 'archived';
}
