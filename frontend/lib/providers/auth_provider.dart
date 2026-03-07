import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/app_logger.dart';
import '../services/tracker/tracker.dart';
import '../services/notification_service.dart';

/// Stream of Firebase auth state changes
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges().map((user) {
    if (user != null) {
      Tracker.instance.setUserId(user.uid);
    }
    return user;
  });
});

/// Current user's UID (null if not signed in)
final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.whenData((user) => user?.uid).value;
});

/// Auth service for sign-in/sign-up/sign-out
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final _logger = AppLogger.instance;

  Future<UserCredential?> signInWithGoogle() async {
    _logger.info('auth.google_sign_in', logger: 'AuthService');
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _logger.info('auth.google_sign_in', logger: 'AuthService', data: {'cancelled': true});
        return null;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final cred = await _auth.signInWithCredential(credential);
      _logger.info('auth.google_sign_in', logger: 'AuthService', data: {'uid': cred.user?.uid, 'success': true});
      return cred;
    } on FirebaseAuthException catch (e) {
      _logger.warning('auth.google_sign_in', logger: 'AuthService', data: {'error': e.code});
      throw _mapFirebaseError(e);
    }
  }

  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    _logger.info('auth.sign_out', logger: 'AuthService', data: {'uid': uid});
    await NotificationService.instance.unregister();
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
    _logger.info('auth.sign_out', logger: 'AuthService', data: {'success': true});
    Tracker.instance.setUserId('');
  }

  Future<String?> getIdToken() async {
    return await _auth.currentUser?.getIdToken();
  }

  String _mapFirebaseError(FirebaseAuthException e) {
    return mapFirebaseErrorCode(e.code, e.message);
  }
}

/// Map Firebase error codes to user-friendly messages.
String mapFirebaseErrorCode(String code, String? message) {
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

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
