import 'package:firebase_auth/firebase_auth.dart';

class AuthHandler {
  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  /// Get the current Firebase ID token, or null if not logged in.
  static Future<String?> getFirebaseToken() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  static Future<bool> isAuthenticated() async {
    final token = await getFirebaseToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> logout() async {
    await _firebaseAuth.signOut();
  }
}