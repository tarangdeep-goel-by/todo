import 'package:drift/drift.dart';

/// Tasks table definition
@DataClassName('TaskData')
class Tasks extends Table {
  /// Primary key - task ID
  TextColumn get id => text()();

  /// User ID
  TextColumn get userId => text()();

  /// Task title
  TextColumn get title => text()();

  /// Optional description
  TextColumn get description => text().nullable()();

  /// Parent task ID (self-referencing foreign key)
  TextColumn get parentId => text().nullable().references(Tasks, #id)();

  /// Task category (work or personal)
  TextColumn get category => text()();

  /// Task status (active, completed, archived)
  TextColumn get status => text().withDefault(const Constant('active'))();

  /// Creation timestamp
  DateTimeColumn get createdAt => dateTime()();

  /// Last updated timestamp
  DateTimeColumn get updatedAt => dateTime()();

  /// Optional due date
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Completion timestamp
  DateTimeColumn get completedAt => dateTime().nullable()();

  /// Audio file URI
  TextColumn get audioFileUri => text().nullable()();

  /// Transcription text
  TextColumn get transcription => text()();

  /// AI placement metadata (JSON string)
  TextColumn get aiPlacementJson => text()();

  @override
  Set<Column> get primaryKey => {id};
}
