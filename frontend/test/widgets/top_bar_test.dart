import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/top_bar.dart';
import 'package:frontend/config/spacing.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('TopBar', () {
    testWidgets('finds text Amble', (tester) async {
      await tester.pumpWidget(buildTestApp(const TopBar()));
      expect(find.text('Amble'), findsOneWidget);
    });

    testWidgets('has correct height container', (tester) async {
      await tester.pumpWidget(buildTestApp(const TopBar()));

      final box = tester.renderObject<RenderBox>(find.byType(Container).first);
      expect(box.size.height, AppSpacing.topBarHeight);
    });
  });
}
