import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';

import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';

/// Cross-device chat alerts via Firestore (recipient app shows local notification).
/// Complements WebSocket real-time delivery when the recipient app is backgrounded.
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
  }) async {
    final fromUid = FirebaseAuth.instance.currentUser?.uid;
    if (fromUid == null || fromUid.isEmpty) return;

    var toUid = (recipientFirebaseUid ?? '').trim();
    if (!_looksLikeFirebaseUid(toUid) && recipientUserId != null) {
      toUid = await _firebaseUidForBackendUser(recipientUserId) ?? '';
    }
    if (!_looksLikeFirebaseUid(toUid)) return;
    if (toUid == fromUid) return;

    final safeSender = senderName.trim().isEmpty ? 'Someone' : senderName.trim();
    final preview = _previewBody(body);

    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': toUid,
        'fromUid': fromUid,
        'title': safeSender,
        'body': preview,
        'payload': {
          'type': 'new_message',
          'chatId': chatId,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatNotificationService] Firestore alert failed: $e');
      }
    }

    unawaited(_requestBackendPush(
      recipientFirebaseUid: toUid,
      title: safeSender,
      body: preview,
      chatId: chatId,
    ));
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
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.id;
    } catch (_) {}

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('id', isEqualTo: userId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.id;
    } catch (_) {}

    return null;
  }

  /// Best-effort server push (no-op if endpoint unavailable).
  static Future<void> _requestBackendPush({
    required String recipientFirebaseUid,
    required String title,
    required String body,
    required String chatId,
  }) async {
    try {
      await BackendChatService.ensureAuth();
      final token = await BackendChatService.getAuthToken();
      final uri = ApiConfig.endpoint('/api/v1/notifications/send');
      final res = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'toFirebaseUid': recipientFirebaseUid,
              'title': title,
              'body': body,
              'data': {
                'type': 'new_message',
                'chatId': chatId,
              },
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (kDebugMode && res.statusCode >= 400) {
        debugPrint(
          '[ChatNotificationService] backend push ${res.statusCode}',
        );
      }
    } catch (_) {}
  }
}
