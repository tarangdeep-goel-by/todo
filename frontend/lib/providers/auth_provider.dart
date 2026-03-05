import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Stream of Firebase auth state changes
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
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

  Future<UserCredential> signInWithEmail(String email, String password) async {
    debugPrint('[Auth] Sign-in attempt: $email');
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      debugPrint('[Auth] Sign-in success: ${cred.user?.uid}');
      return cred;
    } on FirebaseAuthException catch (e) {
      debugPrint('[Auth] Sign-in failed: ${e.code} — ${e.message}');
      throw _mapFirebaseError(e);
    }
  }

  Future<UserCredential> signUpWithEmail(String email, String password) async {
    debugPrint('[Auth] Sign-up attempt: $email');
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      debugPrint('[Auth] Sign-up success: ${cred.user?.uid}');
      return cred;
    } on FirebaseAuthException catch (e) {
      debugPrint('[Auth] Sign-up failed: ${e.code} — ${e.message}');
      throw _mapFirebaseError(e);
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    debugPrint('[Auth] Google sign-in attempt');
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint('[Auth] Google sign-in cancelled by user');
        return null;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final cred = await _auth.signInWithCredential(credential);
      debugPrint('[Auth] Google sign-in success: ${cred.user?.uid}');
      return cred;
    } on FirebaseAuthException catch (e) {
      debugPrint('[Auth] Google sign-in failed: ${e.code} — ${e.message}');
      throw _mapFirebaseError(e);
    }
  }

  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    debugPrint('[Auth] Sign-out: $uid');
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
    debugPrint('[Auth] Sign-out complete');
  }

  Future<String?> getIdToken() async {
    return await _auth.currentUser?.getIdToken();
  }

  /// Map Firebase error codes to user-friendly messages.
  String _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
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
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
