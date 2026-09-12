import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Per-chat delivery/read watermarks so senders can show WhatsApp-style ticks
/// even when the Nest message `status` field stays on `sent`.
///
/// Doc: `chat_receipts/{chatId}`
/// Fields: `{ "<nestUserId>": { deliveredUpTo, readUpTo, updatedAt } }`
class ChatReceiptService {
  ChatReceiptService._();

  static const String collectionName = 'chat_receipts';

  static DocumentReference<Map<String, dynamic>> _doc(String chatId) {
    return FirebaseFirestore.instance
        .collection(collectionName)
        .doc(chatId.trim());
  }

  static DateTime? _parseTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }

  /// Latest times the [userId] has delivered / read messages in [chatId].
  static Stream<ChatPeerReceipt?> watchUserReceipt({
    required String chatId,
    required int userId,
  }) {
    final id = chatId.trim();
    if (id.isEmpty || userId <= 0) {
      return Stream<ChatPeerReceipt?>.value(null);
    }
    final key = userId.toString();
    return _doc(id).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      final raw = data[key];
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      return ChatPeerReceipt(
        userId: userId,
        deliveredUpTo: _parseTime(map['deliveredUpTo']),
        readUpTo: _parseTime(map['readUpTo']),
      );
    });
  }

  /// Raise this user's delivery (and optionally read) watermark.
  static Future<void> publish({
    required String chatId,
    required int userId,
    DateTime? deliveredUpTo,
    DateTime? readUpTo,
  }) async {
    final id = chatId.trim();
    if (id.isEmpty || userId <= 0) return;
    if (deliveredUpTo == null && readUpTo == null) return;

    try {
      final key = userId.toString();
      final ref = _doc(id);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final existing = snap.data()?[key];
        DateTime? prevDelivered;
        DateTime? prevRead;
        if (existing is Map) {
          prevDelivered = _parseTime(existing['deliveredUpTo']);
          prevRead = _parseTime(existing['readUpTo']);
        }

        DateTime? nextDelivered = prevDelivered;
        if (deliveredUpTo != null &&
            (nextDelivered == null || deliveredUpTo.isAfter(nextDelivered))) {
          nextDelivered = deliveredUpTo;
        }

        DateTime? nextRead = prevRead;
        if (readUpTo != null &&
            (nextRead == null || readUpTo.isAfter(nextRead))) {
          nextRead = readUpTo;
        }
        // Reading implies delivered at least that far.
        if (nextRead != null &&
            (nextDelivered == null || nextRead.isAfter(nextDelivered))) {
          nextDelivered = nextRead;
        }

        if (nextDelivered == prevDelivered && nextRead == prevRead) return;

        tx.set(
          ref,
          {
            key: {
              if (nextDelivered != null)
                'deliveredUpTo': nextDelivered.toIso8601String(),
              if (nextRead != null) 'readUpTo': nextRead.toIso8601String(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
          },
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatReceiptService] publish failed: $e');
      }
    }
  }
}

class ChatPeerReceipt {
  final int userId;
  final DateTime? deliveredUpTo;
  final DateTime? readUpTo;

  const ChatPeerReceipt({
    required this.userId,
    this.deliveredUpTo,
    this.readUpTo,
  });

  bool coversDelivered(DateTime messageCreatedAt) {
    final t = deliveredUpTo;
    if (t == null) return false;
    return !messageCreatedAt.isAfter(t.add(const Duration(seconds: 2)));
  }

  bool coversRead(DateTime messageCreatedAt) {
    final t = readUpTo;
    if (t == null) return false;
    return !messageCreatedAt.isAfter(t.add(const Duration(seconds: 2)));
  }
}
