import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/top_bar.dart';
import 'package:frontend/config/spacing.dart';
import 'package:frontend/providers/connectivity_provider.dart';
import 'package:frontend/services/connectivity_service.dart';

import '../helpers/test_helpers.dart';

/// Stub that avoids platform channel calls.
class _StubConnectivityService extends ConnectivityService {
  @override
  bool get isOnline => true;
  @override
  Future<void> initialize() async {}
  @override
  Stream<bool> get onStatusChange => const Stream.empty();
  @override
  void dispose() {}
}

void main() {
  group('TopBar', () {
    late ({dynamic service, dynamic override}) localData;

    setUp(() {
      localData = createTestLocalData();
    });

    List<Override> overrides() => [
      localData.override,
      connectivityServiceProvider.overrideWithValue(_StubConnectivityService()),
    ];

    testWidgets('finds text Amble', (tester) async {
      await tester.pumpWidget(buildTestApp(const TopBar(), overrides: overrides()));
      await tester.pumpAndSettle();
      expect(find.text('Amble'), findsOneWidget);
    });

    testWidgets('has correct height container', (tester) async {
      await tester.pumpWidget(buildTestApp(const TopBar(), overrides: overrides()));
      await tester.pumpAndSettle();

      final box = tester.renderObject<RenderBox>(find.byType(Container).first);
      expect(box.size.height, AppSpacing.topBarHeight);
    });

    testWidgets('no logout icon in top bar', (tester) async {
      await tester.pumpWidget(buildTestApp(const TopBar(), overrides: overrides()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.logout_rounded), findsNothing);
    });
  });
}
