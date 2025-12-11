import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static Future<User?> signIn({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return cred.user;
  }

  static Future<User?> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String nationalId,
    required String preferredContact,
    required String role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = cred.user;
    if (user == null) return null;

    await _db.collection('users').doc(user.uid).set({
      'name': name,
      'email': email,
      'phone': phone,
      'nationalId': nationalId,
      'preferredContact': preferredContact,
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
      'rentalsCount': 0,
      'overdueCount': 0,
      'isTrusted': false,
    });

    return user;
  }

  static Future<void> signOut() => _auth.signOut();
}
