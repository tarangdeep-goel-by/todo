import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  LocalCategoriesCompanion makeCat({
    String id = 'cat-1',
    String name = 'career',
    int position = 0,
  }) =>
      LocalCategoriesCompanion.insert(
        id: id,
        name: name,
        position: position,
        createdAt: DateTime(2026, 1, 1),
      );

  group('CategoryDao', () {
    test('replaceAll inserts categories', () async {
      await db.categoryDao.replaceAll([
        makeCat(id: '1', name: 'career', position: 0),
        makeCat(id: '2', name: 'health', position: 1),
      ]);
      final cats = await db.categoryDao.getAllCategories();
      expect(cats, hasLength(2));
      expect(cats.map((c) => c.name).toSet(), {'career', 'health'});
    });

    test('replaceAll clears old data', () async {
      await db.categoryDao.replaceAll([
        makeCat(id: '1', name: 'career'),
      ]);
      await db.categoryDao.replaceAll([
        makeCat(id: '2', name: 'health'),
      ]);
      final cats = await db.categoryDao.getAllCategories();
      expect(cats, hasLength(1));
      expect(cats.first.name, 'health');
    });

    test('deleteAllCategories empties table', () async {
      await db.categoryDao.replaceAll([
        makeCat(id: '1'),
        makeCat(id: '2', name: 'health'),
      ]);
      await db.categoryDao.deleteAllCategories();
      final cats = await db.categoryDao.getAllCategories();
      expect(cats, isEmpty);
    });
  });
}
