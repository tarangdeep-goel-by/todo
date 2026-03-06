import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/models/api_response.dart';
import 'package:frontend/models/category.dart';
import 'package:frontend/widgets/top_bar.dart';
import 'package:frontend/widgets/bottom_nav_bar.dart';
import 'package:frontend/widgets/coaching_hint.dart';
import 'package:frontend/widgets/ptt_input_overlay.dart';
import 'package:frontend/screens/parent_node_view.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;
  late MockSpeechService mockSpeech;

  setUp(() {
    mockApi = MockApiService();
    mockSpeech = MockSpeechService();

    // Bypass the welcome overlay and swipe tutorial
    SharedPreferences.setMockInitialValues({
      'onboarding_welcome_seen': true,
      'onboarding_swipe_tutorial_step': 3,
    });

    // Stub API calls that happen in initState via fetchAll()
    when(() => mockApi.getTasksAdvancedWithRetry(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer((_) async => TaskListResponse(
          tasks: [],
          totalCount: 0,
          limit: 100,
          offset: 0,
          hasMore: false,
        ));
    when(() => mockApi.getCategories())
        .thenAnswer((_) async => <Category>[]);
    when(() => mockSpeech.initialize()).thenAnswer((_) async => true);
  });

  Widget buildHomeScreen() {
    return buildTestApp(
      const HomeScreen(),
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        speechServiceProvider.overrideWithValue(mockSpeech),
      ],
    );
  }

  group('HomeScreen', () {
    testWidgets('renders TopBar with Amble text', (tester) async {
      await tester.pumpWidget(buildHomeScreen());
      await tester.pumpAndSettle();

      expect(find.byType(TopBar), findsOneWidget);
      expect(find.text('Amble'), findsOneWidget);
    });

    testWidgets('renders BottomNavBar', (tester) async {
      await tester.pumpWidget(buildHomeScreen());
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavBar), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('shows CoachingHint when no tasks', (tester) async {
      await tester.pumpWidget(buildHomeScreen());
      await tester.pumpAndSettle();

      expect(find.byType(CoachingHint), findsOneWidget);
    });

    testWidgets('renders PttInputOverlay widget', (tester) async {
      await tester.pumpWidget(buildHomeScreen());
      await tester.pumpAndSettle();

      expect(find.byType(PttInputOverlay), findsOneWidget);
    });

    testWidgets('shows ParentNodeView by default (node view mode)',
        (tester) async {
      await tester.pumpWidget(buildHomeScreen());
      await tester.pumpAndSettle();

      expect(find.byType(ParentNodeView), findsOneWidget);
      // Empty state text from ParentNodeView
      expect(find.text('Your world, organized'), findsOneWidget);
    });
  });
}
