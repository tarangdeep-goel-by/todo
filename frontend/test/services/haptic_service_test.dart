import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/haptic_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HapticService', () {
    test('light does not throw', () {
      expect(() => HapticService.light(), returnsNormally);
    });

    test('medium does not throw', () {
      expect(() => HapticService.medium(), returnsNormally);
    });

    test('selection does not throw', () {
      expect(() => HapticService.selection(), returnsNormally);
    });
  });
}
