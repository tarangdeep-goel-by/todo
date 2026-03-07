import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/screens/profile_screen.dart';
import 'package:frontend/screens/archive_screen.dart';
import 'package:frontend/services/tracker/tracker_keys.dart';
import '../helpers/test_app.dart';
import '../helpers/api_cleanup.dart';
import '../helpers/tracker_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await cleanupTestUser();
  });

  testWidgets('QA Profile: navigate, verify elements, open archive', (tester) async {
    await pumpApp(tester);

    // --- Navigate to profile tab ---

    await tester.tap(find.byKey(TK.profileTab));
    await settle(tester);
    expectTap('profile_tab');

    // Verify profile screen is shown
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // Verify "Member since" text is present (or at least the profile info area)
    // In test mode, Firebase user may not have creationTime, so check for
    // profile elements that are always present
    final hasMemberSince = find.textContaining('Member since').evaluate().isNotEmpty;
    final hasEmail = find.textContaining('@').evaluate().isNotEmpty;

    // At least the profile screen rendered with some user info
    expect(
      hasMemberSince || hasEmail || find.text('User').evaluate().isNotEmpty,
      isTrue,
      reason: 'Profile should show user info (name, email, or member since)',
    );

    // --- Verify archive link is present ---

    expect(find.byKey(TK.archiveLink), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);

    // --- Verify sign out button is present ---

    expect(find.byKey(TK.signOutButton), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    // --- Tap archive link -> verify archive screen opens ---

    await tester.tap(find.byKey(TK.archiveLink));
    await settle(tester, const Duration(seconds: 3));

    expect(find.byType(ArchiveScreen), findsOneWidget);
    // Archive screen should show title and either tasks or empty state
    expect(find.text('Archive'), findsWidgets);

    // Since we cleaned up test data, expect empty archive state
    expect(find.text('No archived tasks'), findsOneWidget);

    // --- Navigate back to profile ---

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await settle(tester);

    // Should be back on profile screen
    expect(find.byType(ProfileScreen), findsOneWidget);
  });
}
