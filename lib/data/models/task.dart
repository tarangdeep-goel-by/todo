import 'package:todo/data/models/ai_placement.dart';

/// Task categories
enum TaskCategory {
  work,
  personal;

  /// Convert from string
  static TaskCategory fromString(String value) {
    return TaskCategory.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => TaskCategory.personal,
    );
  }
}

/// Task status
enum TaskStatus {
  active,
  completed,
  archived;

  /// Convert from string
  static TaskStatus fromString(String value) {
    return TaskStatus.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => TaskStatus.active,
    );
  }
}

/// Task model
class Task {
  /// Unique task ID
  final String id;

  /// User ID (default-user for MVP)
  final String userId;

  /// Task title
  final String title;

  /// Optional description
  final String? description;

  /// Parent task ID (null for root)
  final String? parentId;

  /// Task category
  final TaskCategory category;

  /// Task status
  final TaskStatus status;

  /// Creation timestamp
  final DateTime createdAt;

  /// Last updated timestamp
  final DateTime updatedAt;

  /// Optional due date
  final DateTime? dueDate;

  /// Completion timestamp
  final DateTime? completedAt;

  /// Audio file URI
  final String? audioFileUri;

  /// Transcription text
  final String transcription;

  /// AI placement suggestion
  final AIPlacement aiPlacement;

  const Task({
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
    required this.aiPlacement,
  });

  /// Copy with modified fields
  Task copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    String? parentId,
    TaskCategory? category,
    TaskStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? dueDate,
    DateTime? completedAt,
    String? audioFileUri,
    String? transcription,
    AIPlacement? aiPlacement,
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
      aiPlacement: aiPlacement ?? this.aiPlacement,
    );
  }

  @override
  String toString() {
    return 'Task(id: $id, title: $title, category: $category, status: $status)';
  }
}
