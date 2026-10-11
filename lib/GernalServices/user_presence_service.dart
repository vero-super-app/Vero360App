import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Foreground presence and typing for in-app chat.
///
/// App-wide online lives on `users/{uid}`. The open chat also writes
/// `chat_presence/{chatId}/members/{uid}` so the other person can see
/// Online / typing without guessing a stale user flag.
class UserPresenceService {
  UserPresenceService._();

  static Timer? _heartbeat;
  static Timer? _typingClear;
  static bool _online = false;
  static String? _activeChatId;
  static String? _typingChatId;
  static DateTime? _lastTypingWrite;
  static int _typingEpoch = 0;
  static int _writeSeq = 0;

  static String get _uid =>
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  static Future<void> goOnline() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    _online = true;
    await _writeUser(uid, online: true);
    _armHeartbeat();
  }

  static Future<void> goOffline() async {
    _online = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    final uid = _uid;
    final chatId = _activeChatId;
    if (uid.isEmpty) return;
    await _writeUser(uid, online: false);
    if (chatId != null && chatId.isNotEmpty) {
      await _writeMember(chatId, uid, online: false, typing: false);
    }
    await clearTyping();
  }

  /// Mark this user present in [chatId] while the thread is on screen.
  static Future<void> enterChat(String chatId) async {
    final id = chatId.trim();
    final uid = _uid;
    if (id.isEmpty || uid.isEmpty) return;
    if (_activeChatId != null && _activeChatId != id) {
      await leaveChat(_activeChatId!);
    }
    _activeChatId = id;
    _online = true;
    await _writeMember(id, uid, online: true, typing: _typingChatId == id);
    await _writeUser(uid, online: true);
    _armHeartbeat();
  }

  static Future<void> leaveChat(String chatId) async {
    final id = chatId.trim();
    final uid = _uid;
    if (id.isEmpty || uid.isEmpty) return;
    if (_typingChatId == id) {
      _typingChatId = null;
      _typingEpoch++;
      _typingClear?.cancel();
      _typingClear = null;
      _lastTypingWrite = null;
    }
    if (_activeChatId == id) _activeChatId = null;
    await _writeMember(id, uid, online: false, typing: false);
  }

  /// Tell the open chat that this user is typing. Writes at most every 1s.
  static Future<void> pulseTyping(String chatId) async {
    final id = chatId.trim();
    final uid = _uid;
    if (id.isEmpty || uid.isEmpty) return;
    final epoch = ++_typingEpoch;
    _typingChatId = id;
    _typingClear?.cancel();
    _typingClear = Timer(const Duration(seconds: 3), () {
      unawaited(clearTyping());
    });
    final now = DateTime.now();
    if (_lastTypingWrite != null &&
        now.difference(_lastTypingWrite!) < const Duration(seconds: 1)) {
      return;
    }
    _lastTypingWrite = now;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'typingChatId': id,
          'typingAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await _writeMember(id, uid, online: true, typing: true);
      if (epoch != _typingEpoch) {
        await clearTyping();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[UserPresence] typing failed: $e');
    }
  }

  static Future<void> clearTyping() async {
    _typingClear?.cancel();
    _typingClear = null;
    _lastTypingWrite = null;
    final previous = _typingChatId;
    if (previous == null) {
      _typingEpoch++;
      return;
    }
    _typingChatId = null;
    _typingEpoch++;
    final uid = _uid;
    if (uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'typingChatId': FieldValue.delete(),
          'typingAt': FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
      await _writeMember(previous, uid, online: _online && _activeChatId == previous, typing: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[UserPresence] clear typing failed: $e');
    }
  }

  static void _armHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!_online) return;
      final uid = _uid;
      if (uid.isEmpty) return;
      unawaited(_writeUser(uid, online: true));
      final chatId = _activeChatId;
      if (chatId != null && chatId.isNotEmpty) {
        unawaited(_writeMember(
          chatId,
          uid,
          online: true,
          typing: _typingChatId == chatId,
        ));
      }
    });
  }

  static Future<void> _writeUser(String uid, {required bool online}) async {
    final seq = ++_writeSeq;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'isOnline': online,
          'online': online,
          'presence': online ? 'online' : 'offline',
          'lastSeen': FieldValue.serverTimestamp(),
          'lastActiveAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      // A slower "online" write must not undo a later "offline".
      if (seq != _writeSeq || _online != online) {
        if (!_online && online) {
          await FirebaseFirestore.instance.collection('users').doc(uid).set(
            {
              'isOnline': false,
              'online': false,
              'presence': 'offline',
              'lastSeen': FieldValue.serverTimestamp(),
              'lastActiveAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[UserPresence] write failed: $e');
    }
  }

  static Future<void> _writeMember(
    String chatId,
    String uid, {
    required bool online,
    required bool typing,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('chat_presence')
          .doc(chatId)
          .collection('members')
          .doc(uid)
          .set(
        {
          'online': online,
          'typing': typing,
          'seenAt': FieldValue.serverTimestamp(),
          'typingAt': typing
              ? FieldValue.serverTimestamp()
              : FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[UserPresence] member write failed: $e');
    }
  }
}
