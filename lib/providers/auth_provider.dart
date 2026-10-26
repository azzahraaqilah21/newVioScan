import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';

/// Singleton AuthService provider
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Singleton FirestoreService provider
final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());

/// Stream provider for Firebase auth state changes (raw Firebase User)
final authStateProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

/// Provider for the current user's Firestore UserModel (null if not logged in)
final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  if (authState == null) return null;

  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.getUser(authState.uid);
});
