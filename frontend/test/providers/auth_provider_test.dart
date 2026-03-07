import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/auth_provider.dart';

/// Tests for mapFirebaseErrorCode — the production error mapper.
void main() {
  group('Firebase error mapping', () {
    test('user-not-found maps to account not found message', () {
      expect(mapFirebaseErrorCode('user-not-found', null),
          'No account found with this email.');
    });

    test('wrong-password maps to incorrect credentials message', () {
      expect(mapFirebaseErrorCode('wrong-password', null),
          'Incorrect email or password.');
    });

    test('invalid-credential maps to incorrect credentials message', () {
      expect(mapFirebaseErrorCode('invalid-credential', null),
          'Incorrect email or password.');
    });

    test('email-already-in-use maps to existing account message', () {
      expect(mapFirebaseErrorCode('email-already-in-use', null),
          'An account already exists with this email.');
    });

    test('weak-password maps to password length message', () {
      expect(mapFirebaseErrorCode('weak-password', null),
          'Password must be at least 6 characters.');
    });

    test('invalid-email maps to valid email message', () {
      expect(mapFirebaseErrorCode('invalid-email', null),
          'Please enter a valid email address.');
    });

    test('user-disabled maps to disabled account message', () {
      expect(mapFirebaseErrorCode('user-disabled', null),
          'This account has been disabled.');
    });

    test('too-many-requests maps to rate limit message', () {
      expect(mapFirebaseErrorCode('too-many-requests', null),
          'Too many attempts. Please try again later.');
    });

    test('network-request-failed maps to network error message', () {
      expect(mapFirebaseErrorCode('network-request-failed', null),
          'Network error. Check your connection.');
    });

    test('operation-not-allowed maps to method not enabled message', () {
      expect(mapFirebaseErrorCode('operation-not-allowed', null),
          'This sign-in method is not enabled.');
    });

    test('account-exists-with-different-credential maps correctly', () {
      expect(
          mapFirebaseErrorCode(
              'account-exists-with-different-credential', null),
          'An account already exists with this email using a different sign-in method.');
    });

    test('unknown error code with message uses that message', () {
      expect(mapFirebaseErrorCode('some-unknown-code', 'Custom error'),
          'Custom error');
    });

    test('unknown error code without message uses default', () {
      expect(mapFirebaseErrorCode('some-unknown-code', null),
          'Something went wrong. Please try again.');
    });
  });
}
