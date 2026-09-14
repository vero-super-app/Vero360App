import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Per-message emoji reactions shared via Firestore (WhatsApp-style).
class MessageReactionService {
  MessageReactionService._();

  static const _collection = 'message_reactions';

  static String docId(String chatId, String messageId) =>
      '${chatId.trim()}_${messageId.trim()}';

  static Stream<Map<String, String>> watch({
    required String chatId,
    required String messageId,
  }) {
    final id = docId(chatId, messageId);
    if (chatId.trim().isEmpty || messageId.trim().isEmpty) {
      return Stream.value(const {});
    }
    return FirebaseFirestore.instance
        .collection(_collection)
        .doc(id)
        .snapshots()
        .map((snap) {
      final raw = snap.data()?['byUid'];
      if (raw is! Map) return const <String, String>{};
      return raw.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    });
  }

  static Future<void> setReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty || chatId.trim().isEmpty || messageId.trim().isEmpty) {
      return;
    }
    final emojiTrim = emoji.trim();
    if (emojiTrim.isEmpty) return;

    final ref =
        FirebaseFirestore.instance.collection(_collection).doc(docId(chatId, messageId));
    try {
      final snap = await ref.get();
      final existing = Map<String, dynamic>.from(
        (snap.data()?['byUid'] as Map?) ?? const {},
      );
      // Tap same emoji again → remove (toggle).
      if (existing[uid]?.toString() == emojiTrim) {
        existing.remove(uid);
      } else {
        existing[uid] = emojiTrim;
      }
      await ref.set({
        'chatId': chatId.trim(),
        'messageId': messageId.trim(),
        'byUid': existing,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[MessageReaction] set failed: $e');
    }
  }
}
