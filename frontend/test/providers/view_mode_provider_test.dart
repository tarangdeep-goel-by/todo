import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/providers/view_mode_provider.dart';

void main() {
  group('ViewMode enum', () {
    test('has 4 values', () {
      expect(ViewMode.values.length, 4);
    });

    test('values contains all modes', () {
      expect(ViewMode.values, contains(ViewMode.node));
      expect(ViewMode.values, contains(ViewMode.flat));
      expect(ViewMode.values, contains(ViewMode.calendar));
      expect(ViewMode.values, contains(ViewMode.profile));
    });
  });

  group('viewModeProvider', () {
    test('defaults to ViewMode.node', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(viewModeProvider), ViewMode.node);
    });

    test('can switch to flat', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(viewModeProvider.notifier).state = ViewMode.flat;
      expect(container.read(viewModeProvider), ViewMode.flat);
    });

    test('can switch to calendar', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(viewModeProvider.notifier).state = ViewMode.calendar;
      expect(container.read(viewModeProvider), ViewMode.calendar);
    });
  });
}
