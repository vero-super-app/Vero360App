import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:vero360_app/config/api_config.dart';

/// Same Firestore collection as the website Help Center / admin VeroChat inbox.
class HelpCenterChatService {
  HelpCenterChatService._();

  static const collectionName = 'verochat_sessions';
  static const _prefsSessionKey = 'verochat_app_session_id';

  static CollectionReference<Map<String, dynamic>> get _sessions =>
      FirebaseFirestore.instance.collection(collectionName);

  static CollectionReference<Map<String, dynamic>> _messages(String sessionId) =>
      _sessions.doc(sessionId).collection('messages');

  /// Stable session per signed-in user; guests get a persisted UUID.
  static Future<String> resolveSessionId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isNotEmpty) return 'app_$uid';

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsSessionKey)?.trim() ?? '';
    if (id.isEmpty || !RegExp(r'^[a-zA-Z0-9_-]{8,128}$').hasMatch(id)) {
      id = 'guest_${const Uuid().v4().replaceAll('-', '')}';
      await prefs.setString(_prefsSessionKey, id);
    }
    return id;
  }

  static Future<void> ensureSession({
    required String sessionId,
    required String visitorName,
    required String visitorEmail,
  }) async {
    final ref = _sessions.doc(sessionId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.set({
        'visitorName': visitorName.trim().isEmpty ? 'App user' : visitorName.trim(),
        'visitorEmail': visitorEmail.trim(),
        'status': 'open',
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'app',
        'type': 'help_center',
        if (FirebaseAuth.instance.currentUser?.uid != null)
          'visitorUid': FirebaseAuth.instance.currentUser!.uid,
      }, SetOptions(merge: true));
      return;
    }

    await ref.set({
      'visitorName': visitorName.trim().isEmpty ? 'App user' : visitorName.trim(),
      'visitorEmail': visitorEmail.trim().isEmpty
          ? 'app-user@vero.local'
          : visitorEmail.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'unreadForAgent': 0,
      'source': 'app',
      'type': 'help_center',
      if (FirebaseAuth.instance.currentUser?.uid != null)
        'visitorUid': FirebaseAuth.instance.currentUser!.uid,
    });

    await _messages(sessionId).add({
      'text':
          'Hello! This is Vero360 Help Center. How can we help you today?',
      'sender': 'agent',
      'agentName': 'Vero360 Help Center',
      'kind': 'text',
      'createdAt': FieldValue.serverTimestamp(),
    });

    unawaitedNotify(
      type: 'new_chat',
      sessionId: sessionId,
      visitorName: visitorName,
      visitorEmail: visitorEmail,
    );
  }

  static Stream<List<HelpCenterMessage>> watchMessages(String sessionId) {
    return _messages(sessionId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(HelpCenterMessage.fromDoc).toList());
  }

  static Future<void> sendText({
    required String sessionId,
    required String text,
    required String visitorName,
    required String visitorEmail,
    HelpCenterReplyTo? replyTo,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await ensureSession(
      sessionId: sessionId,
      visitorName: visitorName,
      visitorEmail: visitorEmail,
    );

    final payload = <String, dynamic>{
      'text': trimmed,
      'sender': 'visitor',
      'kind': 'text',
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (replyTo != null) payload['replyTo'] = replyTo.toMap();

    await _messages(sessionId).add(payload);
    await _sessions.doc(sessionId).update({
      'lastMessage': trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadForAgent': FieldValue.increment(1),
      'status': 'open',
    });

    unawaitedNotify(
      type: 'new_message',
      sessionId: sessionId,
      visitorName: visitorName,
      visitorEmail: visitorEmail,
      message: trimmed,
    );
  }

  static Future<void> sendImage({
    required String sessionId,
    required List<int> bytes,
    required String filename,
    required String contentType,
    required String visitorName,
    required String visitorEmail,
    String? caption,
    HelpCenterReplyTo? replyTo,
  }) async {
    await ensureSession(
      sessionId: sessionId,
      visitorName: visitorName,
      visitorEmail: visitorEmail,
    );

    final imageUrl = await uploadImage(
      sessionId: sessionId,
      bytes: bytes,
      filename: filename,
      contentType: contentType,
    );

    final text = (caption ?? '').trim();
    final payload = <String, dynamic>{
      'text': text,
      'sender': 'visitor',
      'kind': 'image',
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (replyTo != null) payload['replyTo'] = replyTo.toMap();

    await _messages(sessionId).add(payload);
    final preview = text.isEmpty ? '📷 Photo' : text;
    await _sessions.doc(sessionId).update({
      'lastMessage': preview,
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadForAgent': FieldValue.increment(1),
      'status': 'open',
    });

    unawaitedNotify(
      type: 'new_message',
      sessionId: sessionId,
      visitorName: visitorName,
      visitorEmail: visitorEmail,
      message: preview,
    );
  }

  static Future<String> uploadImage({
    required String sessionId,
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    final uri = ApiConfig.siteEndpoint('/api/verochat/upload');
    final req = http.MultipartRequest('POST', uri)
      ..fields['sessionId'] = sessionId
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: MediaType.parse(
            contentType.startsWith('image/') ? contentType : 'image/jpeg',
          ),
        ),
      );

    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    final data = jsonDecode(body.isEmpty ? '{}' : body) as Map<String, dynamic>;
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception(data['error']?.toString() ?? 'Upload failed');
    }
    final url = data['url']?.toString().trim() ?? '';
    if (url.isEmpty) throw Exception('Upload failed');
    return url;
  }

  static void unawaitedNotify({
    required String type,
    required String sessionId,
    required String visitorName,
    required String visitorEmail,
    String? message,
  }) {
    // Fire-and-forget email alert for Help Center admins.
    Future(() async {
      try {
        final uri = ApiConfig.siteEndpoint('/api/verochat/notify');
        await http
            .post(
              uri,
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'type': type,
                'sessionId': sessionId,
                'visitorName': visitorName.trim().isEmpty
                    ? 'App user'
                    : visitorName.trim(),
                'visitorEmail': visitorEmail.trim().isEmpty
                    ? 'app-user@vero.local'
                    : visitorEmail.trim(),
                if ((message ?? '').trim().isNotEmpty) 'message': message!.trim(),
                'source': 'app',
              }),
            )
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[HelpCenterChat] notify failed: $e');
        }
      }
    });
  }
}

class HelpCenterReplyTo {
  final String messageId;
  final String text;
  final String sender; // visitor | agent

  const HelpCenterReplyTo({
    required this.messageId,
    required this.text,
    required this.sender,
  });

  Map<String, dynamic> toMap() => {
        'messageId': messageId,
        'text': text,
        'sender': sender,
      };
}

class HelpCenterMessage {
  final String id;
  final String text;
  final String sender; // visitor | agent
  final String? agentName;
  final DateTime? createdAt;
  final String kind; // text | image
  final String? imageUrl;
  final HelpCenterReplyTo? replyTo;

  const HelpCenterMessage({
    required this.id,
    required this.text,
    required this.sender,
    this.agentName,
    this.createdAt,
    this.kind = 'text',
    this.imageUrl,
    this.replyTo,
  });

  bool get fromAgent => sender == 'agent';

  factory HelpCenterMessage.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    HelpCenterReplyTo? reply;
    final raw = data['replyTo'];
    if (raw is Map) {
      final id = raw['messageId']?.toString().trim() ?? '';
      if (id.isNotEmpty) {
        reply = HelpCenterReplyTo(
          messageId: id,
          text: raw['text']?.toString() ?? '',
          sender: raw['sender']?.toString() == 'agent' ? 'agent' : 'visitor',
        );
      }
    }

    DateTime? created;
    final ts = data['createdAt'];
    if (ts is Timestamp) created = ts.toDate();

    return HelpCenterMessage(
      id: doc.id,
      text: data['text']?.toString() ?? '',
      sender: data['sender']?.toString() == 'agent' ? 'agent' : 'visitor',
      agentName: data['agentName']?.toString(),
      createdAt: created,
      kind: data['kind']?.toString() == 'image' ? 'image' : 'text',
      imageUrl: data['imageUrl']?.toString(),
      replyTo: reply,
    );
  }
}
