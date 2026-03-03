import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/category.dart';

void main() {
  group('Category', () {
    test('fromJson parses all fields', () {
      final json = {
        'id': 'cat-1',
        'name': 'career',
        'position': 0,
        'created_at': '2025-01-15T10:00:00.000',
      };
      final cat = Category.fromJson(json);
      expect(cat.id, 'cat-1');
      expect(cat.name, 'career');
      expect(cat.position, 0);
      expect(cat.createdAt, DateTime.parse('2025-01-15T10:00:00.000'));
    });

    test('displayName capitalizes first letter', () {
      final cat = Category(
        id: '1',
        name: 'home',
        position: 1,
        createdAt: DateTime(2025),
      );
      expect(cat.displayName, 'Home');
    });

    test('displayName handles single char', () {
      final cat = Category(
        id: '1',
        name: 'x',
        position: 0,
        createdAt: DateTime(2025),
      );
      expect(cat.displayName, 'X');
    });

    test('fromJson with different positions', () {
      final json = {
        'id': 'cat-5',
        'name': 'recreation',
        'position': 4,
        'created_at': '2025-06-01T00:00:00.000',
      };
      final cat = Category.fromJson(json);
      expect(cat.position, 4);
      expect(cat.name, 'recreation');
    });

    test('displayName for multi-word names', () {
      final cat = Category(
        id: '1',
        name: 'health',
        position: 2,
        createdAt: DateTime(2025),
      );
      expect(cat.displayName, 'Health');
    });
  });
}
