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
const String _viewersSubcollection = 'viewers';

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

  MerchantStoryItem _docToItem(QueryDocumentSnapshot<Map<String, dynamic>> doc, {int viewerCount = 0}) {
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
      caption: d['caption'] as String?,
      musicTrackId: d['musicTrackId'] as String?,
      musicTrackName: d['musicTrackName'] as String?,
      createdAt: createdAt,
      expiresAt: expiresAt,
      viewerCount: viewerCount,
    );
  }

  /// Fetch active (non-expired) stories for a specific merchant, newest first.
  Future<List<MerchantStoryItem>> getMerchantStories(String merchantId) async {
    final snap = await _firestore
        .collection(_collection)
        .where('merchantId', isEqualTo: merchantId)
        .get();

    final now = DateTime.now();
    final items = snap.docs
        .map(_docToItem)
        .where((e) => e.expiresAt.isAfter(now))
        .toList();

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// Delete a single story document by its id.
  Future<void> deleteStory(String storyId) async {
    await _firestore.collection(_collection).doc(storyId).delete();
  }

  /// Post a new story (image or video). Tries Firebase Storage; on failure (image only) saves as base64.
  Future<void> postStory({
    required String merchantId,
    required String merchantName,
    required Uint8List imageBytes,
    String? merchantImageUrl,
    String? caption,
    String? musicTrackId,
    String? musicTrackName,
    String mediaType = 'image',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != merchantId) {
      throw Exception('Only the merchant can post a story');
    }
    final now = DateTime.now();
    final expiresAt = now.add(storyLifetime);

    String? mediaUrl;
    String? imageBase64;

    if (mediaType == 'video') {
      mediaUrl = await _uploadVideoToStorage(merchantId, imageBytes);
    } else {
      try {
        mediaUrl = await _uploadToStorage(merchantId, imageBytes);
      } catch (e) {
        if (imageBytes.length <= _maxFallbackImageBytes) {
          imageBase64 = base64Encode(imageBytes);
        } else {
          throw Exception(
            'Upload failed. Try a smaller photo (e.g. from camera roll).\n$e',
          );
        }
      }
    }

    await _firestore.collection(_collection).add({
      'merchantId': merchantId,
      'merchantName': merchantName,
      'merchantImageUrl': merchantImageUrl,
      'mediaUrl': mediaUrl ?? '',
      if (imageBase64 != null) 'imageBase64': imageBase64,
      'mediaType': mediaType,
      if (caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
      if (musicTrackId != null && musicTrackId.trim().isNotEmpty) 'musicTrackId': musicTrackId.trim(),
      if (musicTrackName != null && musicTrackName.trim().isNotEmpty) 'musicTrackName': musicTrackName.trim(),
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });
  }

  /// Post multiple stories in one batch (e.g. multiple slides with captions).
  Future<void> postStoryBatch({
    required String merchantId,
    required String merchantName,
    String? merchantImageUrl,
    required List<StorySlideInput> slides,
  }) async {
    for (final slide in slides) {
      await postStory(
        merchantId: merchantId,
        merchantName: merchantName,
        imageBytes: slide.bytes,
        merchantImageUrl: merchantImageUrl,
        caption: slide.caption,
        musicTrackId: slide.musicTrackId,
        musicTrackName: slide.musicTrackName,
        mediaType: slide.mediaType,
      );
    }
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

  Future<String> _uploadVideoToStorage(String merchantId, Uint8List videoBytes) async {
    final now = DateTime.now();
    final path = '$_storagePathPrefix/$merchantId/${now.millisecondsSinceEpoch}.mp4';
    final ref = _storage.ref().child(path);
    await ref.putData(
      videoBytes,
      SettableMetadata(contentType: 'video/mp4'),
    );
    return await ref.getDownloadURL();
  }

  /// Record that a viewer saw this story (call when opening/viewing a story).
  Future<void> recordView({
    required String storyId,
    required String viewerId,
    required String viewerName,
    String? viewerProfileImageUrl,
  }) async {
    await _firestore
        .collection(_collection)
        .doc(storyId)
        .collection(_viewersSubcollection)
        .doc(viewerId)
        .set({
      'viewerId': viewerId,
      'viewerName': viewerName,
      'viewedAt': FieldValue.serverTimestamp(),
      if (viewerProfileImageUrl != null && viewerProfileImageUrl.isNotEmpty)
        'viewerProfileImageUrl': viewerProfileImageUrl,
    }, SetOptions(merge: true));
  }

  /// Get list of viewers who saw this story (for merchant insights).
  Future<List<StoryViewerInfo>> getStoryViewers(String storyId) async {
    final snap = await _firestore
        .collection(_collection)
        .doc(storyId)
        .collection(_viewersSubcollection)
        .orderBy('viewedAt', descending: true)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      final viewedAt = (data['viewedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      final profileUrl = data['viewerProfileImageUrl'] as String?;
      return StoryViewerInfo(
        viewerId: data['viewerId'] as String? ?? '',
        viewerName: data['viewerName'] as String? ?? 'Unknown',
        viewedAt: viewedAt,
        viewerProfileImageUrl: profileUrl != null && profileUrl.isNotEmpty ? profileUrl : null,
      );
    }).toList();
  }

  /// Get viewer count for a story.
  Future<int> getStoryViewerCount(String storyId) async {
    final snap = await _firestore
        .collection(_collection)
        .doc(storyId)
        .collection(_viewersSubcollection)
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Get viewer counts for multiple story IDs (batch).
  Future<Map<String, int>> getStoryViewerCounts(List<String> storyIds) async {
    final Map<String, int> out = {};
    for (final id in storyIds) {
      out[id] = await getStoryViewerCount(id);
    }
    return out;
  }
}

/// Input for one slide when posting a story batch.
class StorySlideInput {
  final Uint8List bytes;
  final String mediaType; // 'image' or 'video'
  final String? caption;
  final String? musicTrackId;
  final String? musicTrackName;

  const StorySlideInput({
    required this.bytes,
    this.mediaType = 'image',
    this.caption,
    this.musicTrackId,
    this.musicTrackName,
  });
}
