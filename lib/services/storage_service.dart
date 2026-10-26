import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload a fluorescence image and return its download URL.
  /// [uid] — user's Firebase UID
  /// [imageBytes] — raw image bytes (e.g. from camera capture)
  /// Returns the public download URL on success.
  Future<String> uploadFluorescenceImage(
      String uid, Uint8List imageBytes) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child('screenings/$uid/$timestamp.jpg');

      final uploadTask = await ref.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      return await uploadTask.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      throw StorageException('Image upload failed: ${e.message}');
    }
  }

  /// Delete a fluorescence image by its storage path.
  Future<void> deleteImage(String storageUrl) async {
    try {
      final ref = _storage.refFromURL(storageUrl);
      await ref.delete();
    } on FirebaseException catch (e) {
      // Non-fatal — log and continue
      // ignore: avoid_print
      print('StorageService: failed to delete image: ${e.message}');
    }
  }
}

class StorageException implements Exception {
  final String message;
  const StorageException(this.message);
  @override
  String toString() => message;
}
