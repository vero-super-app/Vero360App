import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Keeps Firebase `users/{uid}` presence fresh so in-app calls can show Online/Ringing.
class UserPresenceService {
  UserPresenceService._();

  static Timer? _heartbeat;
  static bool _online = false;

  static Future<void> goOnline() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;
    _online = true;
    await _write(uid, online: true);
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_online) return;
      unawaited(_write(uid, online: true));
    });
  }

  static Future<void> goOffline() async {
    _online = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;
    await _write(uid, online: false);
  }

  static Future<void> _write(String uid, {required bool online}) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'isOnline': online,
          'online': online,
          'presence': online ? 'online' : 'offline',
          'lastSeen': FieldValue.serverTimestamp(),
          'lastActiveAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[UserPresence] write failed: $e');
    }
  }
}
