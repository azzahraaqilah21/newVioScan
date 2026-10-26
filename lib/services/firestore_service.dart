import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/screening_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── User CRUD ────────────────────────────────────────────────────────────

  Future<void> createUser(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  Future<UserModel?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.data()!);
  }

  // ─── Screening CRUD ───────────────────────────────────────────────────────

  /// Save a screening result to Firestore.
  Future<String> saveScreening(ScreeningModel screening) async {
    final docRef = _db
        .collection('users')
        .doc(screening.userId)
        .collection('screenings')
        .doc();
    final map = screening.toMap();
    map['id'] = docRef.id;
    await docRef.set(map);
    return docRef.id;
  }

  /// Stream of all screenings for a user, ordered by date (newest first).
  Stream<List<ScreeningModel>> getScreenings(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('screenings')
        .orderBy('screeningDate', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ScreeningModel.fromMap(doc.id, doc.data()))
            .toList());
  }

  /// Get the total number of screenings for a user.
  Future<int> getUserScreeningCount(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('screenings')
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Get the most recent screening for a user.
  Future<ScreeningModel?> getLastScreening(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('screenings')
        .orderBy('screeningDate', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return ScreeningModel.fromMap(doc.id, doc.data());
  }

  /// Delete a screening
  Future<void> deleteScreening(String uid, String screeningId) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('screenings')
        .doc(screeningId)
        .delete();
  }
}
