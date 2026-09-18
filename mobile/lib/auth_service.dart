import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';

// Google Sign-In only, per PROJECT.md's tech stack decision - no
// email/password. Requires the Android app's SHA-1 registered in the
// Firebase console before this will actually complete on-device.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final firebase_auth.FirebaseAuth _firebaseAuth = firebase_auth.FirebaseAuth.instance;
  bool _googleSignInInitialized = false;

  Stream<firebase_auth.User?> get authStateChanges => _firebaseAuth.authStateChanges();

  firebase_auth.User? get currentUser => _firebaseAuth.currentUser;

  Future<String> currentIdToken() async {
    final token = await _firebaseAuth.currentUser?.getIdToken();
    if (token == null) {
      throw StateError('No signed-in user');
    }
    return token;
  }

  Future<void> signInWithGoogle() async {
    if (!_googleSignInInitialized) {
      await GoogleSignIn.instance.initialize();
      _googleSignInInitialized = true;
    }

    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError(
        'Google did not return an ID token - check that the Android app\'s '
        'SHA-1 is registered in the Firebase console and google-services.json '
        'is up to date.',
      );
    }

    final credential = firebase_auth.GoogleAuthProvider.credential(idToken: idToken);
    await _firebaseAuth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _firebaseAuth.signOut();
  }
}
