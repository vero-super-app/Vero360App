import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/utils/description_contact_mask.dart';

/// Cross-device chat alerts via Firestore → Cloud Function → FCM.
/// Critical when the recipient app is backgrounded or killed (WebSocket is offline).
///
/// Single push transport only — do not also call Nest `/notifications/send`
/// (that previously caused duplicate FCM deliveries for every message).
class ChatNotificationService {
  ChatNotificationService._();

  static const String collectionName = 'chat_message_alerts';

  /// Notify the recipient after the sender successfully posts a message.
  static Future<void> notifyRecipientOfMessage({
    required String chatId,
    required String senderName,
    required String body,
    String? recipientFirebaseUid,
    int? recipientUserId,
    int? senderUserId,
  }) async {
    final fromUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (fromUid.isEmpty) return;

    var toUid = await BackendChatService.resolvePeerFirebaseUid(
      chatId: chatId,
      peerUserId: recipientUserId,
      hintFirebaseUid: recipientFirebaseUid,
    );
    toUid = (toUid ?? '').trim();

    // Last-resort legacy lookup (kept for older user docs).
    if (!_looksLikeFirebaseUid(toUid) &&
        recipientUserId != null &&
        recipientUserId > 0) {
      toUid = await _firebaseUidForBackendUser(recipientUserId) ?? '';
    }

    if (!_looksLikeFirebaseUid(toUid)) {
      if (kDebugMode) {
        debugPrint(
          '[ChatNotificationService] skip push — no recipient Firebase UID '
          '(chatId=$chatId peerUserId=$recipientUserId)',
        );
      }
      return;
    }
    if (toUid == fromUid) {
      if (kDebugMode) {
        debugPrint(
          '[ChatNotificationService] skip push — recipient resolved to self',
        );
      }
      return;
    }

    final rawSender = senderName.trim().isEmpty ? 'Someone' : senderName.trim();
    final safeSender = DescriptionContactMask.mask(rawSender);
    final preview = DescriptionContactMask.mask(_previewBody(body));

    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': toUid,
        'fromUid': fromUid,
        'title': safeSender,
        'body': preview,
        'payload': {
          'type': 'new_message',
          'chatId': chatId,
          'badgeRoute': 'messages',
          'senderName': safeSender,
          'title': safeSender,
          if (senderUserId != null && senderUserId > 0)
            'peerUserId': senderUserId,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
      });
      if (kDebugMode) {
        debugPrint(
          '[ChatNotificationService] chat_message_alerts written → $toUid',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatNotificationService] Firestore alert failed: $e');
      }
    }
  }

  static String _previewBody(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Sent you a message';
    if (t.startsWith('img::')) return '📷 Photo';
    if (t.startsWith('aud::')) return '🎤 Voice message';
    return t.length > 120 ? '${t.substring(0, 120)}…' : t;
  }

  static bool _looksLikeFirebaseUid(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(value);
  }

  static Future<String?> _firebaseUidForBackendUser(int userId) async {
    if (userId <= 0) return null;
    try {
      for (final field in ['userId', 'id', 'backendUserId', 'nestUserId']) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(field, isEqualTo: userId)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final id = snap.docs.first.id.trim();
          if (_looksLikeFirebaseUid(id)) return id;
        }
      }
    } catch (_) {}
    return null;
  }
}
