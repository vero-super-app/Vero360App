// Firebase setup (no REST API required):
// 1) Storage rules: allow authenticated users to write under `delivery_proofs/**`
//    and allow public read (or signed URLs via getDownloadURL — default is tokenized URL).
// 2) Firestore rules example for collection [collection]:
//    match /order_delivery_proofs/{orderId} {
//      allow read: if request.auth != null;
//      allow create, update: if request.auth != null;
//    }
// Adjust stricter rules later (e.g. only buyer/merchant on that order).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Uploads delivery proof to Firebase Storage and stores metadata in Firestore
/// so buyers and merchants can load proof on any device (no REST API required).
class DeliveryProofService {
  DeliveryProofService._();

  static const String collection = 'order_delivery_proofs';
  static const String _storageFolder = 'delivery_proofs';

  /// Uploads image bytes to Storage and returns a public download URL.
  ///
  /// Uses [XFile.readAsBytes] (not `dart:io` [File]) so gallery picks work on
  /// Android (content:// URIs) and iOS — `File(path).readAsBytes()` often fails
  /// or yields empty data, which can lead to `object-not-found` on [getDownloadURL].
  static Future<String> uploadProofImage({
    required String orderId,
    required XFile file,
  }) async {
    final pathLower = file.path.toLowerCase();
    final ext = pathLower.contains('.')
        ? pathLower.split('.').last.split('?').first
        : 'jpg';
    final name = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = FirebaseStorage.instance
        .ref()
        .child(_storageFolder)
        .child(orderId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_'))
        .child(name);

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError(
        'Could not read the photo. Please pick the image again or choose another file.',
      );
    }

    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' => 'image/heic',
      'heif' => 'image/heic',
      _ => 'image/jpeg',
    };

    final task = ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    final snapshot = await task;
    // Use the upload task's ref for getDownloadURL to avoid path mismatch.
    // Occasional race: object not yet visible for getDownloadURL right after put.
    return _getDownloadUrlWithRetry(snapshot.ref);
  }

  static Future<String> _getDownloadUrlWithRetry(Reference ref) async {
    const int maxAttempts = 10;
    const int baseMs = 300;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await ref.getDownloadURL();
      } catch (e, st) {
        if (attempt == maxAttempts - 1) {
          Error.throwWithStackTrace(e, st);
        }
        // Exponential backoff: 300, 600, 900, ...
        await Future<void>.delayed(
          Duration(milliseconds: baseMs * (attempt + 1)),
        );
      }
    }
    throw StateError('getDownloadURL failed');
  }

  /// Saves proof URL + courier info for [orderId] (doc id = backend order id).
  static Future<void> saveProofMetadata({
    required String orderId,
    required String proofUrl,
    required String courierMethod,
    String tracking = '',
  }) async {
    await FirebaseFirestore.instance.collection(collection).doc(orderId).set(
      {
        'orderId': orderId,
        'proofUrl': proofUrl,
        'courierMethod': courierMethod.trim().toLowerCase(),
        'tracking': tracking.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'uploadedBy': FirebaseAuth.instance.currentUser?.uid,
      },
      SetOptions(merge: true),
    );
  }

  /// Reads proof URL for an order (null if none).
  static Future<String?> getProofUrl(String orderId) async {
    final snap =
        await FirebaseFirestore.instance.collection(collection).doc(orderId).get();
    final u = snap.data()?['proofUrl']?.toString().trim();
    if (u == null || u.isEmpty) return null;
    return u;
  }

  /// Batch-load proof URLs for many order ids (one read per id).
  static Future<Map<String, String>> getProofUrls(Iterable<String> orderIds) async {
    final out = <String, String>{};
    for (final id in orderIds) {
      final clean = id.trim();
      if (clean.isEmpty) continue;
      final url = await getProofUrl(clean);
      if (url != null && url.isNotEmpty) out[clean] = url;
    }
    return out;
  }

  /// Proof URL + courier + tracking from Firestore (for buyers on any device).
  static Future<Map<String, Map<String, String>>> getDeliveryMetadata(
    Iterable<String> orderIds,
  ) async {
    final out = <String, Map<String, String>>{};
    for (final raw in orderIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      final snap =
          await FirebaseFirestore.instance.collection(collection).doc(id).get();
      if (!snap.exists) continue;
      final d = snap.data();
      if (d == null) continue;
      final proofUrl = d['proofUrl']?.toString().trim() ?? '';
      final courier = d['courierMethod']?.toString().trim().toLowerCase() ?? '';
      final tracking = d['tracking']?.toString().trim() ?? '';
      if (proofUrl.isEmpty && courier.isEmpty && tracking.isEmpty) continue;
      out[id] = {
        if (proofUrl.isNotEmpty) 'proofUrl': proofUrl,
        if (courier.isNotEmpty) 'method': courier,
        if (tracking.isNotEmpty) 'tracking': tracking,
      };
    }
    return out;
  }
}
