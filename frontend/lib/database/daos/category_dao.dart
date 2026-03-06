import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'category_dao.g.dart';

@DriftAccessor(tables: [LocalCategories])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  Future<List<LocalCategory>> getAllCategories() =>
      select(localCategories).get();

  Future<void> replaceAll(List<LocalCategoriesCompanion> entries) async {
    await transaction(() async {
      await delete(localCategories).go();
      await batch((b) {
        b.insertAll(localCategories, entries);
      });
    });
  }

  Future<int> deleteAllCategories() => delete(localCategories).go();
}
