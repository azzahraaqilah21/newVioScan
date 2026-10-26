import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream of Firebase auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Current Firebase user (nullable)
  User? get currentUser => _auth.currentUser;

  /// Sign in with Google. Creates a Firestore user document on first login.
  Future<UserModel?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // User cancelled

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;
      if (user == null) return null;

  // Check if user document exists in Firestore
      final docRef = _firestore.collection('users').doc(user.uid);
      final docSnap = await docRef.get();

      if (!docSnap.exists) {
        // First login — create user document
        final userModel = UserModel(
          uid: user.uid,
          displayName: user.displayName ?? 'VioScan User',
          email: user.email ?? '',
          photoURL: user.photoURL,
          createdAt: DateTime.now(),
        );
        await docRef.set(userModel.toMap());
        return userModel;
      } else {
        return UserModel.fromMap(docSnap.data()!);
      }
    } on FirebaseAuthException catch (e) {
      throw AuthException('Google Sign-In failed: ${e.message}');
    } catch (e) {
      throw AuthException('Unexpected error: $e');
    }
  }

  /// Register with Email and Password
  Future<UserModel?> registerWithEmail(
      String email, String password, String displayName) async {
    try {
      final UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);
      final User? user = userCredential.user;
      if (user == null) return null;

      // Update Firebase Profile
      await user.updateDisplayName(displayName);

      // Create Firestore User Document
      final userModel = UserModel(
        uid: user.uid,
        displayName: displayName,
        email: email,
        createdAt: DateTime.now(),
      );
      await _firestore.collection('users').doc(user.uid).set(userModel.toMap());

      return userModel;
    } on FirebaseAuthException catch (e) {
      throw AuthException('Pendaftaran gagal: ${e.message}');
    } catch (e) {
      throw AuthException('Terjadi kesalahan: $e');
    }
  }

  /// Sign in with Email and Password
  Future<UserModel?> signInWithEmail(String email, String password) async {
    try {
      final UserCredential userCredential = await _auth
          .signInWithEmailAndPassword(email: email, password: password);
      final User? user = userCredential.user;
      if (user == null) return null;

      final docSnap =
          await _firestore.collection('users').doc(user.uid).get();
      if (docSnap.exists) {
        return UserModel.fromMap(docSnap.data()!);
      }
      return null;
    } on FirebaseAuthException catch (e) {
      throw AuthException('Login gagal: ${e.message}');
    } catch (e) {
      throw AuthException('Terjadi kesalahan: $e');
    }
  }

  /// Send Password Reset Email
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw AuthException('Reset password gagal: ${e.message}');
    } catch (e) {
      throw AuthException('Terjadi kesalahan: $e');
    }
  }

  /// Update User Display Name
  Future<void> updateDisplayName(String displayName) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.updateDisplayName(displayName);
        await _firestore
            .collection('users')
            .doc(user.uid)
            .update({'displayName': displayName});
      }
    } catch (e) {
      throw AuthException('Gagal mengubah profil: $e');
    }
  }

  /// Sign out from Firebase and Google
  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  /// Whether a user is currently signed in
  bool get isLoggedIn => _auth.currentUser != null;
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}
