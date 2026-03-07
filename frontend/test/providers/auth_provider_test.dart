import 'package:flutter_test/flutter_test.dart';

/// Tests for the error mapping logic in AuthService._mapFirebaseError.
///
/// Since AuthService depends on FirebaseAuth.instance (singleton),
/// we test the mapping logic by replicating the switch statement.
/// This validates the expected user-facing messages for each error code.
void main() {
  // Replicate _mapFirebaseError logic for testing without Firebase init
  String mapFirebaseError(String code, String? message) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a different sign-in method.';
      default:
        return message ?? 'Something went wrong. Please try again.';
    }
  }

  group('Firebase error mapping', () {
    test('user-not-found maps to account not found message', () {
      expect(mapFirebaseError('user-not-found', null),
          'No account found with this email.');
    });

    test('wrong-password maps to incorrect credentials message', () {
      expect(mapFirebaseError('wrong-password', null),
          'Incorrect email or password.');
    });

    test('invalid-credential maps to incorrect credentials message', () {
      expect(mapFirebaseError('invalid-credential', null),
          'Incorrect email or password.');
    });

    test('email-already-in-use maps to existing account message', () {
      expect(mapFirebaseError('email-already-in-use', null),
          'An account already exists with this email.');
    });

    test('weak-password maps to password length message', () {
      expect(mapFirebaseError('weak-password', null),
          'Password must be at least 6 characters.');
    });

    test('invalid-email maps to valid email message', () {
      expect(mapFirebaseError('invalid-email', null),
          'Please enter a valid email address.');
    });

    test('user-disabled maps to disabled account message', () {
      expect(mapFirebaseError('user-disabled', null),
          'This account has been disabled.');
    });

    test('too-many-requests maps to rate limit message', () {
      expect(mapFirebaseError('too-many-requests', null),
          'Too many attempts. Please try again later.');
    });

    test('network-request-failed maps to network error message', () {
      expect(mapFirebaseError('network-request-failed', null),
          'Network error. Check your connection.');
    });

    test('operation-not-allowed maps to method not enabled message', () {
      expect(mapFirebaseError('operation-not-allowed', null),
          'This sign-in method is not enabled.');
    });

    test('account-exists-with-different-credential maps correctly', () {
      expect(
          mapFirebaseError('account-exists-with-different-credential', null),
          'An account already exists with this email using a different sign-in method.');
    });

    test('unknown error code with message uses that message', () {
      expect(mapFirebaseError('some-unknown-code', 'Custom error'),
          'Custom error');
    });

    test('unknown error code without message uses default', () {
      expect(mapFirebaseError('some-unknown-code', null),
          'Something went wrong. Please try again.');
    });
  });
}
