import 'package:firebase_auth/firebase_auth.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Current user stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Current user
  User? get currentUser => _auth.currentUser;

  // Sign in with email and password
  Future<UserCredential> signInWithEmailAndPassword({required String email, required String password}) async {
    return await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  // Register with email and password
  Future<UserCredential> createUserWithEmailAndPassword({required String email, required String password}) async {
    return await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
