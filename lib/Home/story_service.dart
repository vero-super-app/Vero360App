// Merchant stories — Firestore + Storage (Firebase Spark plan). 24h expiry.
// When Storage fails (e.g. -13040), falls back to storing image as base64 in Firestore.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:vero360_app/Home/merchant_story_model.dart';

const String _collection = 'merchant_stories';
const String _storagePathPrefix = 'merchant_stories';

/// Max image size for Firestore fallback (doc limit 1MB; base64 ~1.33x).
const int _maxFallbackImageBytes = 350000;

class StoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static const Duration storyLifetime = Duration(hours: 24);

  /// Stream of active story groups (non-expired), grouped by merchant.
  /// Firestore index required: collection `merchant_stories`, fields: expiresAt (Ascending).
  Stream<List<MerchantStoryGroup>> getActiveStoriesStream() {
    final now = Timestamp.now();
    return _firestore
        .collection(_collection)
        .where('expiresAt', isGreaterThan: now)
        .orderBy('expiresAt', descending: false)
        .limit(100)
        .snapshots()
        .map((snap) => _groupByMerchant(snap.docs));
  }

  List<MerchantStoryGroup> _groupByMerchant(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final now = DateTime.now();
    final items = docs
        .map((d) => _docToItem(d))
        .where((e) => e.expiresAt.isAfter(now))
        .toList();
    final byMerchant = <String, List<MerchantStoryItem>>{};
    for (final item in items) {
      byMerchant.putIfAbsent(item.merchantId, () => []).add(item);
    }
    for (final list in byMerchant.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    return byMerchant.entries
        .map((e) => MerchantStoryGroup(
              merchantId: e.key,
              merchantName: e.value.first.merchantName,
              merchantImageUrl: e.value.first.merchantImageUrl,
              items: e.value,
            ))
        .toList()
      ..sort((a, b) {
        final aTime = a.items.last.createdAt;
        final bTime = b.items.last.createdAt;
        return bTime.compareTo(aTime);
      });
  }

  MerchantStoryItem _docToItem(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final expiresAt = (d['expiresAt'] as Timestamp?)?.toDate() ?? createdAt.add(storyLifetime);
    return MerchantStoryItem(
      storyId: doc.id,
      merchantId: d['merchantId'] as String? ?? '',
      merchantName: d['merchantName'] as String? ?? 'Merchant',
      merchantImageUrl: d['merchantImageUrl'] as String?,
      mediaUrl: d['mediaUrl'] as String? ?? '',
      imageBase64: d['imageBase64'] as String?,
      mediaType: d['mediaType'] as String? ?? 'image',
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  /// Post a new story (image). Tries Firebase Storage (putFile); on failure saves image in Firestore as base64.
  Future<void> postStory({
    required String merchantId,
    required String merchantName,
    required Uint8List imageBytes,
    String? merchantImageUrl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != merchantId) {
      throw Exception('Only the merchant can post a story');
    }
    final now = DateTime.now();
    final expiresAt = now.add(storyLifetime);

    String? mediaUrl;
    String? imageBase64;

    // 1) Try Firebase Storage. On failure (e.g. -13040 cancelled), use Firestore fallback.
    try {
      mediaUrl = await _uploadToStorage(merchantId, imageBytes);
    } catch (e) {
      // 2) Fallback: store image in Firestore so the story still posts (doc size limit ~1MB).
      if (imageBytes.length <= _maxFallbackImageBytes) {
        imageBase64 = base64Encode(imageBytes);
      } else {
        throw Exception(
          'Upload failed. Try a smaller photo (e.g. from camera roll).\n$e',
        );
      }
    }

    await _firestore.collection(_collection).add({
      'merchantId': merchantId,
      'merchantName': merchantName,
      'merchantImageUrl': merchantImageUrl,
      'mediaUrl': mediaUrl ?? '',
      if (imageBase64 != null) 'imageBase64': imageBase64,
      'mediaType': 'image',
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });
  }

  Future<String> _uploadToStorage(String merchantId, Uint8List imageBytes) async {
    final now = DateTime.now();
    final path = '$_storagePathPrefix/$merchantId/${now.millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child(path);
    await ref.putData(
      imageBytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await ref.getDownloadURL();
  }
}
