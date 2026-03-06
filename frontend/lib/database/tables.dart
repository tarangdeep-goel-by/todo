import 'package:drift/drift.dart';

class LocalTasks extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get parentId => text().nullable()();
  TextColumn get category => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  TextColumn get transcription =>
      text().withDefault(const Constant(''))();
  TextColumn get aiPlacementJson => text().nullable()();
  TextColumn get priority => text().nullable()();
  RealColumn get estimatedHours => real().nullable()();
  TextColumn get audioFileUri => text().nullable()();
  BoolColumn get pendingSync =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get position => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get retryCount =>
      integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  BoolColumn get failed =>
      boolean().withDefault(const Constant(false))();
}

class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
