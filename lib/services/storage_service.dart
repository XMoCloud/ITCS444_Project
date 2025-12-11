import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  static final _storage = FirebaseStorage.instance;

  static Future<String?> uploadImage(
    XFile file,
    String path, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    try {
      final ref = _storage.ref(path);
      Uint8List bytes = await file.readAsBytes();
      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // Wait for task to complete, with timeout to avoid UI hanging on web when CORS blocks
      await uploadTask.timeout(
        timeout,
        onTimeout: () async {
          try {
            // Try to cancel if possible
            await uploadTask.cancel();
          } catch (_) {}
          throw Exception('Upload timed out');
        },
      );

      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Storage upload error: $e');
      return null;
    }
  }
}
