import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/string_extensions.dart';

void main() {
  group('capitalize', () {
    test('empty string returns empty', () {
      expect(''.capitalize, '');
    });

    test('single char returns uppercase', () {
      expect('a'.capitalize, 'A');
    });

    test('already capitalized is idempotent', () {
      expect('Hello'.capitalize, 'Hello');
    });

    test('lowercase word is capitalized', () {
      expect('work'.capitalize, 'Work');
    });
  });
}
