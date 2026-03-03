import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/loading_state.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('LoadingState', () {
    testWidgets('renders a CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoadingState()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('is centered', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoadingState()));
      expect(find.byType(Center), findsWidgets);
    });
  });
}
