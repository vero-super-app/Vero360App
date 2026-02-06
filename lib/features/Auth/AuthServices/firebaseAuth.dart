import 'package:firebase_auth/firebase_auth.dart'; 

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<User?> signupWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user; // This returns a User? type
    } catch (e) {
      print("Error while creating a user: $e"); // Log the actual error
    }
    return null;
  }

  Future<User?> signinWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user; // This returns a User? type
    } catch (e) {
      print("Error while authenticating the user: $e"); // Log the actual error
    }
    return null;
  }
}