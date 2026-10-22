import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/GeneralModels/chat_product_context.dart';
import 'package:vero360_app/GernalServices/backend_messaging_cache.dart';
import 'package:vero360_app/GernalServices/notification_service.dart';
import 'package:vero360_app/GernalServices/chat_receipt_service.dart';
import 'package:vero360_app/utils/chat_offplatform_detector.dart';

/// Backend `@IsUUID('4')` rejects anything else (v5, `order-shipping-…`, etc.).
final _uuidV4Re = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String? _apiClientMessageId(String? id) {
  final s = (id ?? '').trim();
  if (s.isEmpty) return null;
  if (_uuidV4Re.hasMatch(s)) return s;
  return null;
}

int _jsonInt(dynamic raw, [int fallback = 0]) {
  if (raw == null) return fallback;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString()) ?? fallback;
}

bool _chatNameLooksLikeEmailLocal(String name, String email) {
  final n = name.trim().toLowerCase();
  final e = email.trim().toLowerCase();
  if (n.isEmpty || !e.contains('@')) return false;
  return n == e.split('@').first;
}

bool _isPlaceholderChatName(String name) {
  final n = name.trim().toLowerCase();
  return n.isEmpty ||
      n == 'user' ||
      n == 'unknown' ||
      n == 'contact' ||
      n == 'someone' ||
      n == 'chat' ||
      n == 'chats' ||
      n == 'new message' ||
      n == 'vero360' ||
      n == 'merchant' ||
      n == 'you' ||
      n == 'my status';
}

String? _businessNameFromProfileMap(Map<dynamic, dynamic> src) {
  for (final key in [
    'businessName',
    'merchantName',
    'shopName',
    'companyName',
    'storeName',
  ]) {
    final raw = src[key]?.toString().trim() ?? '';
    if (raw.isEmpty || _isPlaceholderChatName(raw) || raw.contains('@')) {
      continue;
    }
    if (_chatNameLooksLikeEmailLocal(raw, src['email']?.toString() ?? '')) {
      continue;
    }
    return raw;
  }
  return null;
}

String _chatDisplayNameFromProfileMap(Map<dynamic, dynamic> src, String email) {
  final biz = _businessNameFromProfileMap(src);
  if (biz != null) return biz;
  for (final key in ['name', 'fullName', 'displayName']) {
    final raw = src[key]?.toString().trim() ?? '';
    if (raw.isEmpty || _isPlaceholderChatName(raw)) continue;
    if (_chatNameLooksLikeEmailLocal(raw, email)) continue;
    if (raw.contains('@')) continue;
    return raw;
  }
  final first = (src['firstName'] ?? src['firstname'] ?? '').toString().trim();
  final last = (src['lastName'] ?? src['lastname'] ?? '').toString().trim();
  final combined = '$first $last'.trim();
  if (combined.isNotEmpty &&
      !_isPlaceholderChatName(combined) &&
      !_chatNameLooksLikeEmailLocal(combined, email)) {
    return combined;
  }
  return 'Contact';
}

String? _usableProfileDisplayName(Map<dynamic, dynamic> src) {
  final email = src['email']?.toString() ?? '';
  final n = _chatDisplayNameFromProfileMap(src, email);
  if (n.isEmpty || _isPlaceholderChatName(n)) return null;
  return n;
}

class BackendChatThread {
  final String id;
  final String type; // 'direct' or 'group'
  final String? name;
  final String? description;
  final String? avatarUrl;
  final bool isArchived;
  final int participantCount;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatParticipant> participants;
  final String? lastMessagePreview;
  final ChatProductContext? lastProductTag;

  /// A thread only belongs in the inbox after someone has actually sent a message.
  bool get hasConversation {
    final preview = (lastMessagePreview ?? '').trim();
    if (preview.isNotEmpty) return true;
    if (unreadCount > 0) return true;
    if (lastProductTag != null) return true;
    return false;
  }

  BackendChatThread({
    required this.id,
    required this.type,
    this.name,
    this.description,
    this.avatarUrl,
    this.isArchived = false,
    required this.participantCount,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.lastProductTag,
    required this.unreadCount,
    required this.createdAt,
    required this.updatedAt,
    required this.participants,
  });

  String otherId(String me) {
    if (participants.isEmpty) return me;
    final others = participants.where((p) => p.id.toString() != me).toList();
    return others.isNotEmpty ? others.first.id.toString() : me;
  }

  /// Peer for a direct chat — never returns the current user.
  ChatParticipant? otherParticipant(
    int myUserId, {
    String? myEmail,
    String? myName,
  }) {
    if (participants.isEmpty) return null;

    final myEmailNorm = (myEmail ?? '').trim().toLowerCase();

    bool isMe(ChatParticipant p) {
      if (myUserId > 0 && p.id > 0 && p.id == myUserId) return true;
      final email = p.email.trim().toLowerCase();
      if (myEmailNorm.isNotEmpty && email.isNotEmpty && email == myEmailNorm) {
        return true;
      }
      // Do NOT match by display name — merchants/customers can share names and
      // that falsely made calls report "you can't call yourself".
      return false;
    }

    final others = participants.where((p) => !isMe(p)).toList();
    if (others.isEmpty) return null;

    // Prefer a participant with a real business / display name.
    for (final p in others) {
      if (!p.needsBusinessNameLookup) return p;
    }
    return others.first;
  }

  factory BackendChatThread.fromJson(Map<String, dynamic> json) {
    return BackendChatThread(
      id: json['id']?.toString() ?? '',
      type: json['type'] ?? 'direct',
      name: json['name'],
      description: json['description'],
      avatarUrl: json['avatarUrl'],
      isArchived: json['isArchived'] ?? false,
      participantCount: json['participantCount'] != null
          ? _jsonInt(json['participantCount'])
          : (json['participants'] as List?)?.length ?? 0,
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.parse(json['lastMessageAt'].toString())
          : (json['updatedAt'] != null
              ? DateTime.parse(json['updatedAt'].toString())
              : null),
      unreadCount: _jsonInt(json['unreadCount']),
      lastMessagePreview: json['lastMessagePreview']?.toString(),
      lastProductTag: json['lastProductTag'] is Map
          ? ChatProductContext.fromTagMap(
              Map<String, dynamic>.from(json['lastProductTag'] as Map),
            )
          : null,
      createdAt: DateTime.parse(
          json['createdAt']?.toString() ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(
          json['updatedAt']?.toString() ?? DateTime.now().toIso8601String()),
      participants: (json['participants'] as List?)
              ?.map((p) => ChatParticipant.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'description': description,
      'avatarUrl': avatarUrl,
      'isArchived': isArchived,
      'participantCount': participantCount,
      'lastMessageAt': lastMessageAt?.toIso8601String(),
      'lastMessagePreview': lastMessagePreview,
      'lastProductTag': lastProductTag?.toMessageTag(),
      'unreadCount': unreadCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'participants': participants.map((p) => p.toJson()).toList(),
    };
  }

  BackendChatThread copyWith({
    String? id,
    String? type,
    String? name,
    String? description,
    String? avatarUrl,
    bool? isArchived,
    int? participantCount,
    DateTime? lastMessageAt,
    int? unreadCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatParticipant>? participants,
    String? lastMessagePreview,
    ChatProductContext? lastProductTag,
  }) {
    return BackendChatThread(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isArchived: isArchived ?? this.isArchived,
      participantCount: participantCount ?? this.participantCount,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      participants: participants ?? this.participants,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastProductTag: lastProductTag ?? this.lastProductTag,
    );
  }
}

/// Result of [BackendChatService.startMerchantChat] — chat thread + resolved seller id.
class MerchantChatResult {
  final BackendChatThread chat;
  final int sellerId;

  const MerchantChatResult({
    required this.chat,
    required this.sellerId,
  });
}

class BackendChatMessage {
  final String id;
  final String chatId;
  final int senderId;
  final String? content;
  final String type; // 'text', 'image', 'video', 'audio', etc.
  final String status; // 'sent', 'delivered', 'read', 'failed'
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? deliveredAt;
  final List<Map<String, dynamic>>? attachments;
  final List<Map<String, dynamic>>? tags;
  final Map<String, dynamic>? sender;
  final String? clientMessageId;
  final Map<String, dynamic>? metadata;

  BackendChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.content,
    required this.type,
    required this.status,
    required this.createdAt,
    this.readAt,
    this.deliveredAt,
    this.attachments,
    this.tags,
    this.sender,
    this.clientMessageId,
    this.metadata,
  });

  bool isMine(int myUserId) => senderId == myUserId;

  Map<String, dynamic>? get replyTo {
    final raw = metadata?['replyTo'] ?? metadata?['reply_to'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  factory BackendChatMessage.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? meta;
    final rawMeta = json['metadata'] ?? json['meta'];
    if (rawMeta is Map) {
      meta = Map<String, dynamic>.from(rawMeta);
    }

    DateTime? parseDt(dynamic raw) {
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      return DateTime.tryParse(raw.toString());
    }

    String normalizeStatus(dynamic raw) {
      final s = (raw ?? 'sent').toString().trim().toLowerCase();
      if (s == 'seen' || s == 'viewed') return 'read';
      if (s == 'received') return 'delivered';
      if (s == 'pending' || s == 'queued') return 'sent';
      return s.isEmpty ? 'sent' : s;
    }

    return BackendChatMessage(
      id: json['id']?.toString() ?? '',
      chatId: json['chatId']?.toString() ?? '',
      senderId: (json['senderId'] is int)
          ? json['senderId']
          : int.tryParse(json['senderId'].toString()) ?? 0,
      content: json['content'],
      type: json['type'] ?? 'text',
      status: normalizeStatus(json['status']),
      createdAt: parseDt(json['createdAt']) ?? DateTime.now(),
      readAt: parseDt(json['readAt'] ?? json['seenAt']),
      deliveredAt: parseDt(json['deliveredAt'] ?? json['receivedAt']),
      attachments: json['attachments'] != null
          ? List<Map<String, dynamic>>.from(json['attachments'] as List)
          : json['attachmentUrls'] is List
              ? (json['attachmentUrls'] as List)
                  .map(
                    (u) => {
                      'url': u.toString(),
                      'type': json['type']?.toString() ?? 'image',
                    },
                  )
                  .toList()
              : null,
      tags: json['tags'] != null
          ? List<Map<String, dynamic>>.from(json['tags'] as List)
          : null,
      sender: json['sender'] is Map
          ? Map<String, dynamic>.from(json['sender'] as Map)
          : null,
      clientMessageId: json['clientMessageId']?.toString(),
      metadata: meta,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chatId': chatId,
      'senderId': senderId,
      'content': content,
      'type': type,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'readAt': readAt?.toIso8601String(),
      'deliveredAt': deliveredAt?.toIso8601String(),
      'attachments': attachments,
      'tags': tags,
      'sender': sender,
      'clientMessageId': clientMessageId,
      if (metadata != null) 'metadata': metadata,
    };
  }

  BackendChatMessage copyWith({
    String? id,
    String? chatId,
    int? senderId,
    String? content,
    String? type,
    String? status,
    DateTime? createdAt,
    DateTime? readAt,
    DateTime? deliveredAt,
    List<Map<String, dynamic>>? attachments,
    List<Map<String, dynamic>>? tags,
    Map<String, dynamic>? sender,
    String? clientMessageId,
    Map<String, dynamic>? metadata,
  }) {
    return BackendChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      attachments: attachments ?? this.attachments,
      tags: tags ?? this.tags,
      sender: sender ?? this.sender,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      metadata: metadata ?? this.metadata,
    );
  }
}

class ChatParticipant {
  final int id;
  final String name;
  final String email;
  final String? profilePicture;
  final String? businessName;
  final String? firebaseUid;

  ChatParticipant({
    required this.id,
    required this.name,
    required this.email,
    this.profilePicture,
    this.businessName,
    this.firebaseUid,
  });

  String get displayLookupKey {
    final e = email.trim().toLowerCase();
    if (e.contains('@') && !e.startsWith('+firebase_')) return 'e:$e';
    if (id > 0) return 'i:$id';
    final uid = (firebaseUid ?? '').trim();
    if (uid.isNotEmpty) return 'u:$uid';
    return 'n:${name.trim().toLowerCase()}';
  }

  bool get needsBusinessNameLookup {
    final biz = (businessName ?? '').trim();
    if (biz.isNotEmpty) return false;
    return isPlaceholderName(name) ||
        looksLikeEmailLocalName(name, email) ||
        name.contains('@');
  }

  String get preferredDisplayName {
    final biz = (businessName ?? '').trim();
    if (biz.isNotEmpty) return biz;
    if (!isPlaceholderName(name) &&
        !looksLikeEmailLocalName(name, email) &&
        !name.contains('@')) {
      return name;
    }
    final e = email.trim();
    if (e.contains('@') && !e.toLowerCase().startsWith('+firebase_')) {
      final local = e.split('@').first.trim();
      if (local.length > 1 && !isPlaceholderName(local)) {
        return local[0].toUpperCase() + local.substring(1);
      }
    }
    // Avoid generic "Contact" in chat lists / forward picker.
    return 'Chat';
  }

  static bool isPlaceholderName(String name) => _isPlaceholderChatName(name);

  static bool looksLikeEmailLocalName(String name, String email) =>
      _chatNameLooksLikeEmailLocal(name, email);

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    // Some payloads nest the user under `user` / `profile`.
    final nested = json['user'] is Map
        ? Map<String, dynamic>.from(json['user'] as Map)
        : (json['profile'] is Map
            ? Map<String, dynamic>.from(json['profile'] as Map)
            : null);

    // Prefer explicit userId. On many backends `id` is the membership row PK,
    // not the user id — using it makes "other participant" resolve to yourself.
    final int id;
    if (nested != null) {
      id = _jsonInt(
        nested['userId'] ??
            nested['id'] ??
            json['userId'] ??
            json['participantUserId'],
      );
    } else {
      id = _jsonInt(
        json['userId'] ??
            json['participantUserId'] ??
            json['uid'] ??
            json['id'],
      );
    }

    final src = nested ?? json;
    final email = (src['email'] ?? json['email'] ?? '').toString().trim();
    final picture = (src['profilePicture'] ??
            src['profilepicture'] ??
            json['profilePicture'] ??
            json['profilepicture'])
        ?.toString();

    final merged = <String, dynamic>{...json, ...src};
    final businessName = _businessNameFromProfileMap(merged);
    final name = _chatDisplayNameFromProfileMap(merged, email);
    final firebaseUid = (src['firebaseUid'] ??
            src['firebase_uid'] ??
            src['uid'] ??
            json['firebaseUid'] ??
            json['firebase_uid'])
        ?.toString()
        .trim();

    var participant = ChatParticipant(
      id: id,
      name: name,
      email: email,
      profilePicture: picture != null && picture.isNotEmpty ? picture : null,
      businessName: businessName,
      firebaseUid: firebaseUid != null && firebaseUid.isNotEmpty
          ? firebaseUid
          : null,
    );
    final memo = BackendChatService.peekCachedBusinessName(
      participant.displayLookupKey,
    );
    if (memo != null && memo.isNotEmpty) {
      participant = participant.copyWith(name: memo, businessName: memo);
    }
    return participant;
  }

  ChatParticipant copyWith({
    int? id,
    String? name,
    String? email,
    String? profilePicture,
    String? businessName,
    String? firebaseUid,
  }) {
    return ChatParticipant(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      profilePicture: profilePicture ?? this.profilePicture,
      businessName: businessName ?? this.businessName,
      firebaseUid: firebaseUid ?? this.firebaseUid,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': id,
      'name': name,
      'email': email,
      'profilepicture': profilePicture,
      if (businessName != null && businessName!.isNotEmpty)
        'businessName': businessName,
      if (firebaseUid != null && firebaseUid!.isNotEmpty)
        'firebaseUid': firebaseUid,
    };
  }
}

enum ChatLastMessagePreviewKind { text, voice, photo, video }

class ChatLastMessagePreview {
  final String label;
  final ChatLastMessagePreviewKind kind;

  const ChatLastMessagePreview({
    required this.label,
    required this.kind,
  });
}

class BackendChatService {
  /// Legacy Firebase chat image prefix still accepted by some backends.
  static const _legacyImgPrefix = 'img::';
  static const _legacyVidPrefix = 'vid::';
  static const _legacyAudPrefix = 'aud::';

  /// User-facing last-message line for chat lists (WhatsApp-style labels).
  static ChatLastMessagePreview describeLastMessagePreview(
    String? raw, {
    String? messageType,
  }) {
    var t = _stripForwardedPreviewMarker((raw ?? '').trim());
    if (t.isEmpty) {
      return const ChatLastMessagePreview(
        label: '',
        kind: ChatLastMessagePreviewKind.text,
      );
    }

    final type = messageType?.toLowerCase() ?? '';
    if (type == 'audio' ||
        t.startsWith(_legacyAudPrefix) ||
        t.toLowerCase().contains(_legacyAudPrefix) ||
        _looksLikeAudioContent(t)) {
      return ChatLastMessagePreview(
        label: _voicePreviewLabel(t),
        kind: ChatLastMessagePreviewKind.voice,
      );
    }
    if (type == 'image' || t.startsWith(_legacyImgPrefix)) {
      return const ChatLastMessagePreview(
        label: 'Photo',
        kind: ChatLastMessagePreviewKind.photo,
      );
    }
    if (type == 'video' || t.startsWith(_legacyVidPrefix)) {
      return const ChatLastMessagePreview(
        label: 'Video',
        kind: ChatLastMessagePreviewKind.video,
      );
    }
    // Match in-chat masking so phone numbers never leak in the chat list.
    t = ChatOffPlatformDetector.maskPhones(t);
    if (t.length > 80) {
      return ChatLastMessagePreview(
        label: '${t.substring(0, 80)}…',
        kind: ChatLastMessagePreviewKind.text,
      );
    }
    return ChatLastMessagePreview(
      label: t,
      kind: ChatLastMessagePreviewKind.text,
    );
  }

  static String _stripForwardedPreviewMarker(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return t;
    final lower = t.toLowerCase();
    final isForwarded = t.startsWith('↪️') ||
        lower.startsWith('forwarded') ||
        lower.startsWith('fwd:');
    if (!isForwarded) return t;
    final nl = t.indexOf('\n');
    if (nl >= 0) return t.substring(nl + 1).trim();
    // e.g. "↪️ Forwarded: hello"
    final colon = t.indexOf(':');
    if (colon >= 0 && colon < 24) return t.substring(colon + 1).trim();
    return t;
  }

  static String _voicePreviewLabel(String raw) {
    var rest = raw;
    final audIdx = rest.toLowerCase().indexOf(_legacyAudPrefix);
    if (audIdx >= 0) {
      rest = rest.substring(audIdx + _legacyAudPrefix.length);
    }
    final pipeIdx = rest.lastIndexOf('|');
    if (pipeIdx > 0) {
      final durSec = int.tryParse(rest.substring(pipeIdx + 1).trim());
      if (durSec != null && durSec > 0) {
        final m = durSec ~/ 60;
        final s = durSec % 60;
        return '$m:${s.toString().padLeft(2, '0')}';
      }
    }
    return 'Voice note';
  }

  static bool _looksLikeAudioContent(String t) {
    final lower = t.toLowerCase();
    if (lower.contains(_legacyAudPrefix)) return true;
    if (lower.contains('firebasestorage') &&
        (lower.contains('audio') ||
            lower.contains('.m4a') ||
            lower.contains('.mp3') ||
            lower.contains('.aac') ||
            lower.contains('.ogg') ||
            lower.contains('.wav'))) {
      return true;
    }
    if (!t.startsWith('http')) return false;
    return lower.contains('/audio') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg');
  }

  /// Peer title for inbox / forward picker — never the signed-in user's name.
  static String peerDisplayNameForThread(
    BackendChatThread t,
    int myUserId, {
    String? myEmail,
    String? myName,
  }) {
    final otherParticipant = t.otherParticipant(
      myUserId,
      myEmail: myEmail,
      myName: myName,
    );
    final threadTitle = (t.name ?? '').trim();
    final myEmailNorm = (myEmail ?? '').trim().toLowerCase();
    final myNameNorm = (myName ?? '').trim().toLowerCase();
    final myEmailLocal = myEmailNorm.contains('@')
        ? myEmailNorm.split('@').first
        : myEmailNorm;

    bool looksLikeMe(String raw) {
      final n = raw.trim().toLowerCase();
      if (n.isEmpty) return false;
      if (myNameNorm.isNotEmpty && n == myNameNorm) return true;
      if (myEmailNorm.isNotEmpty && n == myEmailNorm) return true;
      if (myEmailLocal.isNotEmpty && n == myEmailLocal) return true;
      return false;
    }

    bool usablePeerName(String raw) {
      final n = raw.trim();
      if (n.isEmpty || looksLikeMe(n) || ChatParticipant.isPlaceholderName(n)) {
        return false;
      }
      if (n.contains('@')) return false;
      final email = (otherParticipant?.email ?? '').trim();
      if (ChatParticipant.looksLikeEmailLocalName(n, email)) return false;
      return true;
    }

    var peerName = (otherParticipant?.preferredDisplayName ?? '').trim();
    if (!usablePeerName(peerName)) {
      peerName = (otherParticipant?.businessName ?? '').trim();
    }
    if (!usablePeerName(peerName)) {
      peerName = (otherParticipant?.name ?? '').trim();
    }
    if (!usablePeerName(peerName)) {
      if (threadTitle.isNotEmpty &&
          threadTitle.toLowerCase() != 'direct' &&
          usablePeerName(threadTitle)) {
        peerName = threadTitle;
      } else {
        for (final p in t.participants) {
          if (myUserId > 0 && p.id > 0 && p.id == myUserId) continue;
          if (looksLikeMe(p.name) || looksLikeMe(p.email)) continue;
          final candidate = (p.businessName ?? p.preferredDisplayName).trim();
          if (usablePeerName(candidate)) {
            peerName = candidate;
            break;
          }
        }
      }
    }
    if (!usablePeerName(peerName) && otherParticipant != null) {
      final memo = peekCachedBusinessName(otherParticipant.displayLookupKey) ??
          (otherParticipant.id > 0
              ? peekCachedBusinessName('i:${otherParticipant.id}')
              : null);
      if (memo != null && usablePeerName(memo)) peerName = memo;
    }
    if (!usablePeerName(peerName)) peerName = 'Chat';
    return peerName;
  }

  static String peerAvatarUrlForThread(
    BackendChatThread t,
    int myUserId, {
    String? myEmail,
    String? myName,
  }) {
    final other = t.otherParticipant(
      myUserId,
      myEmail: myEmail,
      myName: myName,
    );
    final fromPeer = (other?.profilePicture ?? '').trim();
    if (_usableAvatarUrl(fromPeer) && !_avatarBelongsToMe(t, fromPeer, myUserId)) {
      if (other != null) rememberPeerAvatar(other, fromPeer);
      return fromPeer;
    }
    if (other != null) {
      final cached = peekCachedAvatar(other);
      if (_usableAvatarUrl(cached) &&
          !_avatarBelongsToMe(t, cached!, myUserId)) {
        return cached.trim();
      }
    }
    final threadAvatar = (t.avatarUrl ?? '').trim();
    if (!_usableAvatarUrl(threadAvatar)) return '';
    // A shared thread photo is often the person who started the chat.
    // Never show that as the other person when it is actually my photo.
    if (_avatarBelongsToMe(t, threadAvatar, myUserId)) return '';
    return threadAvatar;
  }

  static bool _usableAvatarUrl(String? raw) {
    final v = (raw ?? '').trim();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  static bool _sameAvatarUrl(String a, String b) {
    String norm(String raw) {
      final uri = Uri.tryParse(raw.trim());
      if (uri == null) return raw.trim();
      return '${uri.scheme}://${uri.host}${uri.path}';
    }

    return norm(a) == norm(b);
  }

  static final Set<String> _myPhotoUrls = <String>{};

  /// Record a photo URL known to be the signed-in user's own picture.
  static void rememberMyPhoto(String? url) {
    final v = (url ?? '').trim();
    if (_usableAvatarUrl(v)) _myPhotoUrls.add(v);
  }

  /// True when [url] is the signed-in user's own profile photo.
  static bool isMyPhoto(String? url) {
    final v = (url ?? '').trim();
    if (!_usableAvatarUrl(v)) return false;
    final mine = FirebaseAuth.instance.currentUser?.photoURL?.trim() ?? '';
    if (_usableAvatarUrl(mine) && _sameAvatarUrl(v, mine)) return true;
    for (final m in _myPhotoUrls) {
      if (_sameAvatarUrl(v, m)) return true;
    }
    return false;
  }

  static bool _avatarBelongsToMe(
    BackendChatThread t,
    String url,
    int myUserId,
  ) {
    if (isMyPhoto(url)) return true;
    for (final p in t.participants) {
      if (myUserId <= 0 || p.id != myUserId) continue;
      final pic = (p.profilePicture ?? '').trim();
      if (_usableAvatarUrl(pic) && _sameAvatarUrl(url, pic)) return true;
    }
    return false;
  }

  /// Uses ApiConfig for base URL (supports dart-define, ngrok, etc.)
  /// Builds: {ApiConfig.prod}/vero/api/v1
  static String get _baseUrl => '${ApiConfig.prod}/vero/api/v1';

  static String? _authToken;
  static int? _userId;
  static String? _cachedFirebaseUid;
  static DateTime? _tokenFetchedAt;
  static const Duration _tokenTtl = Duration(minutes: 50);

  // Stream controller for threads refresh
  static final _threadsRefreshController = StreamController<void>.broadcast();
  static Stream<void> get _threadsRefresh => _threadsRefreshController.stream;

  static final _threadsLiveController =
      StreamController<List<BackendChatThread>>.broadcast();
  static List<BackendChatThread> _cachedThreads = [];
  /// Backend user id that [_cachedThreads] belongs to (guards account switches).
  static int? _cachedThreadsOwnerUserId;
  static Set<String> _deletedThreadIds = {};
  static bool _threadsWatchReady = false;
  static StreamSubscription<void>? _threadsRefreshSub;
  static Timer? _threadsFallbackPollTimer;
  static String? _activeChatId;
  static bool _wsConnected = false;
  /// Chats recently marked read locally — keeps server lag from resurrecting badges.
  static final Map<String, DateTime> _markReadGraceUntil = {};

  /// Chat currently open in [MessagePageBackendApi] (suppresses unread bump).
  static String? get activeChatId => _activeChatId;

  static bool _isActiveChat(String? chatId) {
    final active = (_activeChatId ?? '').trim();
    final id = (chatId ?? '').trim();
    return active.isNotEmpty && id.isNotEmpty && active == id;
  }

  static void setActiveChatId(String? chatId) {
    final normalized = chatId?.trim();
    _activeChatId =
        (normalized == null || normalized.isEmpty) ? null : normalized;
    if (_activeChatId != null) {
      unawaited(restoreThreadLocally(_activeChatId!));
    }
  }

  static void _rememberMarkedRead(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return;
    _markReadGraceUntil[id] =
        DateTime.now().add(const Duration(seconds: 20));
  }

  static void _forgetMarkedRead(String chatId) {
    _markReadGraceUntil.remove(chatId.trim());
  }

  static List<BackendChatThread> _applyUnreadOverrides(
    List<BackendChatThread> threads,
  ) {
    final now = DateTime.now();
    _markReadGraceUntil.removeWhere((_, until) => now.isAfter(until));
    if (_activeChatId == null && _markReadGraceUntil.isEmpty) return threads;
    return threads.map((t) {
      final id = t.id.trim();
      if (_isActiveChat(id) || _markReadGraceUntil.containsKey(id)) {
        return t.unreadCount == 0 ? t : t.copyWith(unreadCount: 0);
      }
      return t;
    }).toList();
  }

  /// Server un-archives when a chat is opened; clear local hide state too.
  static Future<void> restoreThreadLocally(String chatId) async {
    final normalizedId = chatId.trim();
    if (normalizedId.isEmpty) return;
    _deletedThreadIds.remove(normalizedId);
    final userId = _userId;
    if (userId != null) {
      await BackendMessagingCache.unmarkThreadDeleted(userId, normalizedId);
    }
  }

  static void notifyWsConnected(bool connected) {
    _wsConnected = connected;
    if (connected) {
      _threadsFallbackPollTimer?.cancel();
      _threadsFallbackPollTimer = null;
      refreshThreads();
    } else {
      _ensureThreadsFallbackPoll();
    }
  }

  /// Apply a real-time message to the in-memory thread list.
  static void notifyRealtimeMessage(BackendChatMessage message) {
    final chatId = message.chatId.trim();
    // Keep intentionally deleted chats out of the inbox (even if messages arrive).
    if (chatId.isNotEmpty && _deletedThreadIds.contains(chatId)) {
      return;
    }

    final myId = _userId;
    if (myId == null) {
      unawaited(
        ensureAuth().then((_) => notifyRealtimeMessage(message)).catchError((_) {
          refreshThreads();
        }),
      );
      return;
    }

    final idx = _cachedThreads.indexWhere((t) => t.id.trim() == chatId);
    if (idx < 0) {
      unawaited(_ingestIncomingMessageForThreadList(message));
      return;
    }

    final preview = (message.content ?? '').trim();
    final display = describeLastMessagePreview(
      preview,
      messageType: message.type,
    );
    final previewText =
        display.label.isEmpty ? null : display.label;

    ChatProductContext? productUpdate;
    final tags = message.tags ?? const [];
    for (final tag in tags) {
      if (tag['tagType'] == 'product') {
        productUpdate = ChatProductContext.fromTagMap(
          Map<String, dynamic>.from(tag),
        );
        break;
      }
    }

    final old = _cachedThreads[idx];
    final bumpUnread =
        !message.isMine(myId) && !_isActiveChat(message.chatId);
    if (bumpUnread) {
      // A real new peer message should outrank a stale mark-read grace window.
      _forgetMarkedRead(chatId);
    }

    var participants = old.participants;
    if (!message.isMine(myId) &&
        message.senderId > 0 &&
        old.otherParticipant(myId) == null) {
      participants = [
        ...old.participants.where((p) => p.id != message.senderId),
        ChatParticipant(
          id: message.senderId,
          name: _senderDisplayNameFromMessage(message),
          email: message.sender?['email']?.toString() ?? '',
          profilePicture: message.sender?['profilePicture'] ??
              message.sender?['profilepicture'],
        ),
      ];
    }

    final updated = old.copyWith(
      lastMessagePreview: previewText ??
          (productUpdate != null
              ? 'Enquiry about ${productUpdate.name}'
              : old.lastMessagePreview),
      lastProductTag: productUpdate ?? old.lastProductTag,
      updatedAt: message.createdAt,
      lastMessageAt: message.createdAt,
      unreadCount: bumpUnread ? old.unreadCount + 1 : old.unreadCount,
      participants: participants,
    );

    _cachedThreads.removeAt(idx);
    _cachedThreads.insert(0, updated);
    _emitCachedThreads();
    unawaited(BackendMessagingCache.upsertMessage(myId, message));
    unawaited(
      BackendMessagingCache.saveThreads(myId, _cachedThreads),
    );
    if (bumpUnread) {
      unawaited(_notifyIncomingMessage(message, updated));
    }
  }

  /// Bump inbox preview immediately after the current user sends a message.
  static void _applyOutgoingMessageToThreadList(BackendChatMessage message) {
    notifyRealtimeMessage(message);
  }

  static void _mergeThreadIntoCache(BackendChatThread thread) {
    final id = thread.id.trim();
    if (id.isEmpty) return;
    if (_deletedThreadIds.contains(id)) return;
    final existingIdx = _cachedThreads.indexWhere((t) => t.id.trim() == id);
    BackendChatThread toStore = thread;
    if (existingIdx >= 0) {
      // Prefer the richer peer participant list when merging.
      final prior = _cachedThreads[existingIdx];
      if (thread.participants.isEmpty && prior.participants.isNotEmpty) {
        toStore = thread.copyWith(participants: prior.participants);
      } else if (thread.participants.isNotEmpty && prior.participants.isNotEmpty) {
        final byId = <int, ChatParticipant>{};
        for (final p in prior.participants) {
          if (p.id > 0) byId[p.id] = p;
        }
        for (final p in thread.participants) {
          if (p.id <= 0) continue;
          byId[p.id] = _keepKnownProfilePhoto(p, byId[p.id]);
        }
        toStore = thread.copyWith(participants: byId.values.toList());
      }
    }
    if (_isActiveChat(id) || _markReadGraceUntil.containsKey(id)) {
      toStore = toStore.copyWith(unreadCount: 0);
    }
    _cachedThreads.removeWhere((t) => t.id.trim() == id);
    _cachedThreads.insert(0, toStore);
    _threadsWatchReady = true;
    _emitCachedThreads();
  }

  static String _senderDisplayNameFromMessage(BackendChatMessage message) {
    final sender = message.sender;
    if (sender != null) {
      final email = sender['email']?.toString().trim() ?? '';
      final name = _chatDisplayNameFromProfileMap(sender, email);
      if (name.isNotEmpty && name != 'Contact') return name;
    }
    return 'New message';
  }

  static BackendChatThread _minimalThreadFromMessage(
    BackendChatMessage message,
    int myId,
  ) {
    final preview = describeLastMessagePreview(
      message.content,
      messageType: message.type,
    );
    final sender = message.sender;
    final participants = <ChatParticipant>[];
    if (message.senderId > 0 && message.senderId != myId) {
      participants.add(
        ChatParticipant(
          id: message.senderId,
          name: _senderDisplayNameFromMessage(message),
          email: sender?['email']?.toString() ?? '',
          profilePicture:
              sender?['profilePicture'] ?? sender?['profilepicture'],
        ),
      );
    }

    ChatProductContext? productTag;
    for (final tag in message.tags ?? const []) {
      if (tag['tagType'] == 'product') {
        productTag = ChatProductContext.fromTagMap(
          Map<String, dynamic>.from(tag),
        );
        break;
      }
    }

    return BackendChatThread(
      id: message.chatId,
      type: 'direct',
      participantCount: participants.isEmpty ? 1 : participants.length + 1,
      unreadCount:
          (message.isMine(myId) || _isActiveChat(message.chatId)) ? 0 : 1,
      lastMessagePreview: preview.label.isNotEmpty ? preview.label : null,
      lastProductTag: productTag,
      createdAt: message.createdAt,
      updatedAt: message.createdAt,
      participants: participants,
    );
  }

  static Future<void> _ingestIncomingMessageForThreadList(
    BackendChatMessage message,
  ) async {
    try {
      await ensureAuth();
      final myId = _userId;
      if (myId == null) {
        refreshThreads();
        return;
      }

      final chatId = message.chatId.trim();
      if (chatId.isEmpty || _deletedThreadIds.contains(chatId)) return;

      if (_cachedThreads.indexWhere((t) => t.id.trim() == chatId) < 0) {
        _mergeThreadIntoCache(_minimalThreadFromMessage(message, myId));
      }

      unawaited(BackendMessagingCache.upsertMessage(myId, message));

      try {
        final fresh = await getChat(chatId);
        _mergeThreadIntoCache(fresh);
        unawaited(BackendMessagingCache.saveThreads(myId, _cachedThreads));
      } catch (e) {
        if (kDebugMode) {
          print('[BackendChatService] getChat after WS message failed: $e');
        }
        unawaited(BackendMessagingCache.saveThreads(myId, _cachedThreads));
      }

      if (!message.isMine(myId)) {
        // Device received the message → delivered tick for the sender.
        // If this chat is open, the page also publishes read.
        final asRead = _isActiveChat(message.chatId);
        unawaited(ChatReceiptService.publish(
          chatId: message.chatId,
          userId: myId,
          deliveredUpTo: message.createdAt,
          readUpTo: asRead ? message.createdAt : null,
        ));
      }

      if (!message.isMine(myId) && !_isActiveChat(message.chatId)) {
        final thread = _cachedThreads.firstWhere(
          (t) => t.id.trim() == chatId,
          orElse: () => _minimalThreadFromMessage(message, myId),
        );
        unawaited(_notifyIncomingMessage(message, thread));
      }
    } catch (_) {
      refreshThreads();
    }
  }

  static Future<void> _notifyIncomingMessage(
    BackendChatMessage message,
    BackendChatThread thread,
  ) async {
    try {
      final myId = _userId;
      if (myId == null) return;
      if (message.isMine(myId)) return;
      if (_isActiveChat(message.chatId)) return;

      final sender = thread.participants.firstWhere(
        (p) => p.id != myId,
        orElse: () => thread.participants.isNotEmpty
            ? thread.participants.first
            : ChatParticipant(id: 0, name: 'Someone', email: ''),
      );
      var senderName = _senderDisplayNameFromMessage(message);
      if (_isPlaceholderChatName(senderName) || senderName == 'New message') {
        senderName = sender.preferredDisplayName;
        if (_isPlaceholderChatName(senderName) ||
            _chatNameLooksLikeEmailLocal(senderName, sender.email)) {
          final memo = peekCachedBusinessName(sender.displayLookupKey);
          senderName = (memo != null && !_isPlaceholderChatName(memo))
              ? memo
              : senderName;
        }
      }

      final raw = (message.content ?? '').trim();
      String body;
      if (raw.isEmpty) {
        body = 'Sent you a message';
      } else if (message.type == 'audio' || raw.startsWith(_legacyAudPrefix)) {
        body = '🎤 Voice message';
      } else if (message.type == 'image' || raw.startsWith(_legacyImgPrefix)) {
        body = '📷 Photo';
      } else if (message.type == 'video' || raw.startsWith(_legacyVidPrefix)) {
        body = '🎬 Video';
      } else {
        body = raw.length > 100 ? '${raw.substring(0, 100)}…' : raw;
      }

      await NotificationService.instance.showNewChatMessageNotification(
        senderName: senderName,
        body: body,
        chatId: message.chatId,
        peerUserId: sender.id > 0 ? sender.id : message.senderId,
      );
    } catch (_) {}
  }

  /// Total unread messages across all chat threads.
  static int get totalUnreadMessageCount => _cachedThreads.fold<int>(
        0,
        (sum, t) => sum + (t.hasConversation ? t.unreadCount : 0),
      );

  /// Emits whenever thread unread totals change.
  static Stream<int> watchTotalUnreadCount() async* {
    if (FirebaseAuth.instance.currentUser == null) {
      yield 0;
      return;
    }
    try {
      await _ensureThreadsWatchInitialized();
      yield totalUnreadMessageCount;
      yield* _threadsLiveController.stream.map((_) => totalUnreadMessageCount);
    } catch (_) {
      yield 0;
    }
  }

  static void clearThreadUnread(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return;
    _rememberMarkedRead(id);
    final idx = _cachedThreads.indexWhere((t) => t.id.trim() == id);
    if (idx < 0) {
      _emitCachedThreads();
      return;
    }
    if (_cachedThreads[idx].unreadCount == 0) return;
    _cachedThreads[idx] = _cachedThreads[idx].copyWith(unreadCount: 0);
    _emitCachedThreads();
  }

  static void _emitCachedThreads() {
    if (!_threadsLiveController.isClosed) {
      _threadsLiveController.add(
        _filterDeletedThreads(_cachedThreads),
      );
    }
  }

  static Future<void> _loadDeletedThreadIds(int userId) async {
    await BackendMessagingCache.initialize();
    _deletedThreadIds = BackendMessagingCache.peekDeletedThreadIds(userId);
  }

  static List<BackendChatThread> _filterDeletedThreads(
    List<BackendChatThread> threads,
  ) {
    if (_deletedThreadIds.isEmpty) return threads;
    return threads
        .where((t) => !_deletedThreadIds.contains(t.id.trim()))
        .toList();
  }

  /// Reload deleted-thread ids from disk and re-emit the thread list.
  /// Call after login or when chat-list prefs are restored.
  static Future<void> applyPersistedDeletedThreads(int userId) async {
    await _loadDeletedThreadIds(userId);
    if (_cachedThreads.isNotEmpty) {
      _cachedThreads = _filterDeletedThreads(_cachedThreads);
    }
    if (_threadsWatchReady) {
      _emitCachedThreads();
    }
  }

  static List<dynamic> _extractThreadListFromJson(dynamic json) {
    if (json is List) return json;
    if (json is! Map) return const [];
    final data = json['data'];
    if (data is List) return data;
    if (data is Map) {
      for (final key in ['items', 'chats', 'threads', 'results']) {
        final raw = data[key];
        if (raw is List) return raw;
      }
    }
    for (final key in ['items', 'chats', 'threads', 'results']) {
      final raw = json[key];
      if (raw is List) return raw;
    }
    return const [];
  }

  static Future<void> _reloadThreadCache() async {
    await BackendMessagingCache.initialize();
    await ensureBusinessNameCacheLoaded();
    try {
      await ensureAuth();
    } catch (_) {}
    final userId = _userId;

    // Never carry another account's in-memory threads into this session.
    if (userId != null &&
        _cachedThreadsOwnerUserId != null &&
        _cachedThreadsOwnerUserId != userId) {
      _cachedThreads = [];
      _deletedThreadIds = {};
    }
    if (userId != null) {
      _cachedThreadsOwnerUserId = userId;
    }

    final prior = List<BackendChatThread>.from(_cachedThreads);

    if (userId != null) {
      await _loadDeletedThreadIds(userId);
      final diskThreads = BackendMessagingCache.peekThreads(userId);
      if (diskThreads.isNotEmpty && prior.isEmpty) {
        _cachedThreads = _filterDeletedThreads(diskThreads);
        _applyMemoToCachedThreads();
        _threadsWatchReady = true;
        _emitCachedThreads();
        unawaited(_enrichCachedThreadNames());
      }
    }

    try {
      final fresh = await getThreads();
      final filteredFresh = _filterDeletedThreads(fresh);
      // Don't wipe locally updated threads when the server returns empty (401/offline/lag).
      if (filteredFresh.isEmpty && _cachedThreads.isNotEmpty) {
        _applyMemoToCachedThreads();
        _threadsWatchReady = true;
        _emitCachedThreads();
        if (userId != null) {
          unawaited(BackendMessagingCache.saveThreads(userId, _cachedThreads));
        }
        return;
      }
      if (filteredFresh.isEmpty && prior.isNotEmpty) {
        _cachedThreads = prior;
        _applyMemoToCachedThreads();
        _threadsWatchReady = true;
        _emitCachedThreads();
        if (userId != null) {
          unawaited(BackendMessagingCache.saveThreads(userId, _cachedThreads));
        }
        return;
      }
      // Server list is source of truth, but keep active/recently-read chats at 0
      // so a lagging Nest unreadCount cannot resurrect the badge after open/reply.
      _cachedThreads = _applyUnreadOverrides(filteredFresh);
      _applyMemoToCachedThreads();
      _threadsWatchReady = true;
      _emitCachedThreads();
      unawaited(_enrichCachedThreadNames());
      if (userId != null) {
        await BackendMessagingCache.saveThreads(userId, _cachedThreads);
      }
    } catch (e) {
      if (_cachedThreads.isNotEmpty) {
        _threadsWatchReady = true;
        _emitCachedThreads();
        return;
      }
      if (userId != null || FirebaseAuth.instance.currentUser != null) {
        if (userId != null) {
          final diskThreads = BackendMessagingCache.peekThreads(userId);
          if (diskThreads.isNotEmpty) {
            _cachedThreads = _filterDeletedThreads(diskThreads);
            _applyMemoToCachedThreads();
            _threadsWatchReady = true;
            _emitCachedThreads();
            return;
          }
        }
        // If authenticated but empty/offline, emit empty list so UI is usable
        _cachedThreads = [];
        _threadsWatchReady = true;
        _emitCachedThreads();
        return;
      }
      rethrow;
    }
  }

  static void _ensureThreadsFallbackPoll() {
    if (_threadsFallbackPollTimer != null || _wsConnected) return;
    _threadsFallbackPollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_wsConnected) return;
      unawaited(_reloadThreadCache());
    });
  }

  static Future<void> _ensureThreadsWatchInitialized() async {
    if (!_threadsWatchReady) {
      await _reloadThreadCache();
    }

    _threadsRefreshSub ??= _threadsRefresh.listen((_) {
      unawaited(_reloadThreadCache());
    });
    _ensureThreadsFallbackPoll();
  }

  /// Notify all listeners to refresh threads (called after sending a message)
  static void refreshThreads() {
    _threadsRefreshController.add(null);
  }

  static const _messagingFirebaseUidKey = 'messaging_firebase_uid';

  /// Socket.IO namespace URL for real-time messaging.
  static String get messagingWsUrl {
    final root = ApiConfig.prod.replaceAll(RegExp(r'/+$'), '');
    return '$root/messaging';
  }

  /// Current Firebase ID token (call [ensureAuth] first).
  static Future<String> getAuthToken() async {
    await ensureAuth();
    return _authToken!;
  }

  static const Duration _lookupTimeout = Duration(seconds: 15);

  static int _deterministicUserIdFromUid(String uid) {
    if (uid.isEmpty) return 1;
    final hash = uid.hashCode & 0x7FFFFFFF;
    return hash > 0 ? hash : 1;
  }

  static Future<int?> lookupNumericUserIdFromFirestoreOrPrefs(
    String firebaseUid,
    SharedPreferences sp,
  ) async {
    // 1) SharedPreferences
    final cachedId = sp.getInt('userId') ?? sp.getInt('user_id');
    if (cachedId != null && cachedId > 0) return cachedId;

    final strId = sp.getString('userId') ??
        sp.getString('user_id') ??
        sp.getString('id') ??
        sp.getString('nestUserId') ??
        sp.getString('backendUserId');
    final parsedStr = int.tryParse(strId ?? '');
    if (parsedStr != null && parsedStr > 0) return parsedStr;

    // 2) Firestore marketplace_merchants doc
    try {
      final mDoc = await FirebaseFirestore.instance
          .collection('marketplace_merchants')
          .doc(firebaseUid)
          .get(const GetOptions(source: Source.cache));
      if (mDoc.exists && mDoc.data() != null) {
        final data = mDoc.data()!;
        final raw = data['backendUserId'] ??
            data['userId'] ??
            data['merchantUserId'] ??
            data['ownerId'] ??
            data['nestUserId'] ??
            data['id'];
        final n = _parseNumericId(raw);
        if (n != null && n > 0) return n;
      }
    } catch (_) {}

    try {
      final mDoc = await FirebaseFirestore.instance
          .collection('marketplace_merchants')
          .doc(firebaseUid)
          .get(const GetOptions(source: Source.serverAndCache));
      if (mDoc.exists && mDoc.data() != null) {
        final data = mDoc.data()!;
        final raw = data['backendUserId'] ??
            data['userId'] ??
            data['merchantUserId'] ??
            data['ownerId'] ??
            data['nestUserId'] ??
            data['id'];
        final n = _parseNumericId(raw);
        if (n != null && n > 0) return n;
      }
    } catch (_) {}

    // 3) Firestore users doc
    try {
      final uDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUid)
          .get(const GetOptions(source: Source.cache));
      if (uDoc.exists && uDoc.data() != null) {
        final data = uDoc.data()!;
        final raw = data['backendUserId'] ??
            data['userId'] ??
            data['nestUserId'] ??
            data['id'];
        final n = _parseNumericId(raw);
        if (n != null && n > 0) return n;
      }
    } catch (_) {}

    try {
      final uDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUid)
          .get(const GetOptions(source: Source.serverAndCache));
      if (uDoc.exists && uDoc.data() != null) {
        final data = uDoc.data()!;
        final raw = data['backendUserId'] ??
            data['userId'] ??
            data['nestUserId'] ??
            data['id'];
        final n = _parseNumericId(raw);
        if (n != null && n > 0) return n;
      }
    } catch (_) {}

    // 4) Firestore restaurants doc
    try {
      final rDoc = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(firebaseUid)
          .get(const GetOptions(source: Source.serverAndCache));
      if (rDoc.exists && rDoc.data() != null) {
        final data = rDoc.data()!;
        final raw = data['backendUserId'] ?? data['userId'] ?? data['ownerId'];
        final n = _parseNumericId(raw);
        if (n != null && n > 0) return n;
      }
    } catch (_) {}

    return _deterministicUserIdFromUid(firebaseUid);
  }

  static Future<void> ensureAuth({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    // Fast path for chat send: warm token skips prefs / deleted-id reload.
    final cacheValid = !forceRefresh &&
        _authToken != null &&
        _authToken!.isNotEmpty &&
        _userId != null &&
        _cachedFirebaseUid == user.uid &&
        _tokenFetchedAt != null &&
        DateTime.now().difference(_tokenFetchedAt!) < _tokenTtl;
    if (cacheValid) return;

    await ApiConfig.init();

    final sp = await SharedPreferences.getInstance();
    final storedUid = sp.getString(_messagingFirebaseUidKey);
    if (storedUid != null && storedUid != user.uid) {
      await sp.remove('userId');
      await sp.remove('user_id');
      _userId = null;
      _authToken = null;
      _tokenFetchedAt = null;
      _cachedThreads = [];
      _cachedThreadsOwnerUserId = null;
      _deletedThreadIds = {};
      _threadsWatchReady = false;
      _emitCachedThreads();
    }

    try {
      _authToken = await user.getIdToken(forceRefresh);
    } catch (e) {
      // Keep a previously cached token if Google token refresh is unreachable.
      if (_authToken == null || _authToken!.isEmpty) {
        _authToken = await AuthHandler.getTokenForApi();
      }
      if (_authToken == null || _authToken!.isEmpty) {
        print(
          '[BackendChatService] getIdToken failed and no token found: $e',
        );
      }
    }
    _authToken ??= await AuthHandler.getTokenForApi();

    await sp.setString(_messagingFirebaseUidKey, user.uid);
    _cachedFirebaseUid = user.uid;
    _tokenFetchedAt = DateTime.now();

    // Always resolve numeric id from server or fall back to local storage
    int? userId;
    try {
      userId = await _fetchNumericUserIdFromMe();
    } on _ChatAuthUnauthorized {
      try {
        _authToken = await user.getIdToken(true);
        userId = await _fetchNumericUserIdFromMe();
      } catch (_) {}
    } catch (e) {
      print('[BackendChatService] /users/me attempt error: $e');
    }

    userId ??= await lookupNumericUserIdFromFirestoreOrPrefs(user.uid, sp);
    userId ??= _deterministicUserIdFromUid(user.uid);

    final staleCached = sp.getInt('userId') ?? sp.getInt('user_id');
    if (staleCached != null && staleCached > 0 && staleCached != userId) {
      _cachedThreads = [];
      _cachedThreadsOwnerUserId = null;
      _deletedThreadIds = {};
      _threadsWatchReady = false;
      _emitCachedThreads();
      unawaited(BackendMessagingCache.clearThreadsForUser(userId));
      unawaited(BackendMessagingCache.clearThreadsForUser(staleCached));
    }

    await sp.setInt('userId', userId);
    await sp.setInt('user_id', userId);
    _userId = userId;
    _cachedThreadsOwnerUserId = userId;
    await _loadDeletedThreadIds(userId);
  }

  /// Clear in-memory auth + thread cache (e.g. on sign-out / account switch).
  static void clearAuthCache() {
    _authToken = null;
    _userId = null;
    _cachedFirebaseUid = null;
    _tokenFetchedAt = null;
    _cachedThreads = [];
    _cachedThreadsOwnerUserId = null;
    _deletedThreadIds = {};
    _threadsWatchReady = false;
    _activeChatId = null;
    _wsConnected = false;
    _threadsFallbackPollTimer?.cancel();
    _threadsFallbackPollTimer = null;
    _emitCachedThreads();
  }

  /// Always load numeric DB user id for the current Firebase session.
  static Future<int?> _fetchNumericUserIdFromMe() async {
    if (_authToken == null || _authToken!.isEmpty) return null;
    try {
      final response = await http.get(
        ApiConfig.endpoint('/users/me'),
        headers: {'Authorization': _authHeader},
      ).timeout(_lookupTimeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const _ChatAuthUnauthorized();
      }
      if (response.statusCode != 200) {
        throw Exception(
          'Account lookup failed (${response.statusCode}). Check your connection.',
        );
      }
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;
      final data = json['data'] is Map<String, dynamic>
          ? json['data'] as Map<String, dynamic>
          : json;
      final rawId = data['id'] ?? data['userId'];
      if (rawId == null) return null;
      return rawId is int ? rawId : int.tryParse(rawId.toString());
    } on _ChatAuthUnauthorized {
      rethrow;
    } catch (e) {
      print('[BackendChatService] Failed to fetch users: $e');
      rethrow;
    }
  }

  /// Resolve a marketplace / listing seller to a numeric backend user id.
  static Future<int?> resolvePeerUserId({
    int? ownerId,
    String? sellerUserId,
    String? serviceProviderId,
    String? merchantId,
  }) async {
    await ensureAuth();

    if (ownerId != null && ownerId > 0) return ownerId;

    final candidates = [sellerUserId, serviceProviderId, merchantId];
    for (final candidate in candidates) {
      if (candidate == null || candidate.trim().isEmpty) continue;
      final numeric = int.tryParse(candidate.trim());
      if (numeric != null && numeric > 0) return numeric;
    }

    for (final candidate in candidates) {
      if (candidate == null || candidate.trim().isEmpty) continue;
      final trimmed = candidate.trim();
      if (!_looksLikeFirebaseUid(trimmed)) continue;
      final uid = await getUserIdByFirebaseUid(trimmed);
      if (uid != null && uid > 0) return uid;
    }

    return null;
  }

  static int? _acceptSellerId(int? id, int excludeUserId) {
    if (id == null || id <= 0) return null;
    if (excludeUserId > 0 && id == excludeUserId) return null;
    return id;
  }

  static const _ownListingChatMessage =
      'This is your own listing — you cannot chat with yourself😂😂.';

  /// True when listing merchant/seller ids match the signed-in buyer.
  static bool _isOwnMarketplaceListing({
    required int myBackendId,
    int? ownerId,
    String? sellerUserId,
    String? merchantId,
  }) {
    if (ownerId != null && ownerId > 0 && ownerId == myBackendId) return true;

    final meUid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (meUid != null && meUid.isNotEmpty) {
      for (final raw in [merchantId, sellerUserId]) {
        if (raw != null && raw.trim() == meUid) return true;
      }
    }

    if (sellerUserId != null) {
      final parsed = int.tryParse(sellerUserId.trim());
      if (parsed != null && parsed == myBackendId) return true;
    }

    return false;
  }

  /// Firestore-only fallback when sync own-listing checks miss cached fields.
  static Future<bool> _isOwnMarketplaceListingFromFirestore({
    required int myBackendId,
    String? firestoreItemDocId,
    String? merchantId,
    String? sellerUserId,
  }) async {
    if (firestoreItemDocId != null && firestoreItemDocId.trim().isNotEmpty) {
      final fromDoc = await _sellerIdFromFirestoreItemDoc(
        firestoreItemDocId.trim(),
        quiet: true,
      );
      if (fromDoc == myBackendId) return true;
    }

    final meUid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (meUid == null || meUid.isEmpty) return false;

    for (final raw in [merchantId, sellerUserId]) {
      if (raw == null || raw.trim().isEmpty || !_looksLikeFirebaseUid(raw.trim())) {
        continue;
      }
      if (raw.trim() != meUid) continue;
      final fromMerchant =
          await _sellerIdFromFirestoreMerchant(raw.trim(), quiet: true);
      if (fromMerchant == myBackendId) return true;
    }

    return false;
  }

  static Future<int?> _verifiedSellerId(int? id, int excludeUserId) async {
    final accepted = _acceptSellerId(id, excludeUserId);
    if (accepted == null) return null;
    if (await verifyBackendUserExists(accepted)) return accepted;
    return null;
  }

  static final Map<int, bool> _verifiedBackendUserCache = {};

  /// True when [userId] exists on the Nest/SQL backend (chat API peer).
  static Future<bool> verifyBackendUserExists(
    int userId, {
    bool quiet = true,
  }) async {
    if (userId <= 0) return false;
    final memo = _verifiedBackendUserCache[userId];
    if (memo != null) return memo;

    await ensureAuth();
    try {
      final response = await http
          .get(
            ApiConfig.endpoint('/users/$userId'),
            headers: {'Authorization': _authHeader},
          )
          .timeout(_lookupTimeout);
      final ok = response.statusCode == 200;
      _verifiedBackendUserCache[userId] = ok;
      return ok;
    } catch (e) {
      if (!quiet) {
        print('[BackendChatService] verifyBackendUserExists($userId): $e');
      }
      _verifiedBackendUserCache[userId] = false;
      return false;
    }
  }

  static void _forgetSellerCache(String cacheKey) {
    if (cacheKey.isEmpty) return;
    _marketplaceSellerCache.remove(cacheKey);
  }

  /// Resolve marketplace listing seller → numeric backend user id.
  static Future<int?> resolveMarketplaceSeller({
    int? sqlItemId,
    int? ownerId,
    String? sellerUserId,
    String? serviceProviderId,
    String? merchantId,
    String? firestoreItemDocId,
    int excludeUserId = 0,
    bool skipEnsureAuth = false,
    bool skipOwnerId = false,
    bool skipNumericParse = false,
  }) async {
    if (!skipEnsureAuth) await ensureAuth();

    final cacheKey = _marketplaceSellerCacheKey(
      firestoreItemDocId: firestoreItemDocId,
      merchantId: merchantId,
      sellerUserId: sellerUserId,
      sqlItemId: sqlItemId,
    );
    if (cacheKey.isNotEmpty) {
      final cached = await _verifiedSellerId(
        _marketplaceSellerCache[cacheKey],
        excludeUserId,
      );
      if (cached != null) return cached;
      _forgetSellerCache(cacheKey);
    }

    if (!skipOwnerId) {
      final accepted = await _verifiedSellerId(ownerId, excludeUserId);
      if (accepted != null) {
        _rememberMarketplaceSeller(cacheKey, accepted);
        return accepted;
      }
    }

    if (firestoreItemDocId != null && firestoreItemDocId.trim().isNotEmpty) {
      final fromDoc = await _verifiedSellerId(
        await _sellerIdFromFirestoreItemDoc(
          firestoreItemDocId.trim(),
          quiet: true,
        ),
        excludeUserId,
      );
      if (fromDoc != null) {
        _rememberMarketplaceSeller(cacheKey, fromDoc);
        return fromDoc;
      }
    }

    if (!skipNumericParse) {
      for (final raw in [sellerUserId, merchantId, serviceProviderId]) {
        if (raw == null || raw.trim().isEmpty) continue;
        if (_looksLikeFirebaseUid(raw.trim())) continue;
        final numeric = int.tryParse(raw.trim());
        final id = await _verifiedSellerId(numeric, excludeUserId);
        if (id != null) {
          _rememberMarketplaceSeller(cacheKey, id);
          return id;
        }
      }
    }

    // Firestore + API lookups in parallel (first match wins).
    final uidCandidates = <String>{};
    for (final raw in [merchantId, sellerUserId]) {
      if (raw == null || raw.trim().isEmpty) continue;
      final trimmed = raw.trim();
      if (_looksLikeFirebaseUid(trimmed)) uidCandidates.add(trimmed);
    }

    if (uidCandidates.isNotEmpty) {
      final parallelLookups = <Future<int?>>[];
      for (final trimmed in uidCandidates) {
        parallelLookups.add(
          _sellerIdFromFirestoreMerchant(trimmed, quiet: true)
              .then((id) => _verifiedSellerId(id, excludeUserId)),
        );
        parallelLookups.add(
          _sellerIdFromFirestoreItems(trimmed, quiet: true)
              .then((id) => _verifiedSellerId(id, excludeUserId)),
        );
        parallelLookups.add(
          _sellerIdFromFirestoreUser(trimmed, quiet: true)
              .then((id) => _verifiedSellerId(id, excludeUserId)),
        );
        parallelLookups.add(
          _sellerIdFromUsersQuery(trimmed, quiet: true)
              .then((id) => _verifiedSellerId(id, excludeUserId)),
        );
        parallelLookups.add(
          getUserIdByFirebaseUidValidated(
            trimmed,
            excludeUserId: excludeUserId,
            quiet: true,
          ).then((id) => _verifiedSellerId(id, excludeUserId)),
        );
      }
      final fromParallel = await _firstSuccessfulId(parallelLookups);
      if (fromParallel != null) {
        _rememberMarketplaceSeller(cacheKey, fromParallel);
        return fromParallel;
      }
    }

    final lookups = <Future<int?>>[];

    if (sqlItemId != null && sqlItemId > 0) {
      lookups.add(
        _ownerIdFromMarketplaceItem(sqlItemId, quiet: true)
            .then((id) => _verifiedSellerId(id, excludeUserId)),
      );
    }

    if (serviceProviderId != null && serviceProviderId.trim().isNotEmpty) {
      lookups.add(
        _userIdFromServiceProvider(serviceProviderId.trim(), quiet: true)
            .then((id) => _verifiedSellerId(id, excludeUserId)),
      );
    }

    for (final raw in [sellerUserId, merchantId]) {
      if (raw == null || raw.trim().isEmpty) continue;
      final trimmed = raw.trim();
      if (_looksLikeFirebaseUid(trimmed)) {
        lookups.add(
          getUserIdByFirebaseUidValidated(
            trimmed,
            excludeUserId: excludeUserId,
            quiet: true,
          ).then((id) => _verifiedSellerId(id, excludeUserId)),
        );
      }
    }

    if (lookups.isEmpty) return null;

    final resolved = await _firstSuccessfulId(lookups);
    final acceptedResolved = await _verifiedSellerId(resolved, excludeUserId);
    if (acceptedResolved != null) {
      _rememberMarketplaceSeller(cacheKey, acceptedResolved);
    }
    return acceptedResolved;
  }

  /// Returns the first positive id from [futures], without waiting for slower ones.
  static Future<int?> _firstSuccessfulId(List<Future<int?>> futures) {
    if (futures.isEmpty) return Future.value(null);
    final completer = Completer<int?>();
    var remaining = futures.length;
    for (final future in futures) {
      future
          .then((id) {
            if (!completer.isCompleted && id != null && id > 0) {
              completer.complete(id);
            }
          })
          .catchError((_) {})
          .whenComplete(() {
            remaining--;
            if (remaining == 0 && !completer.isCompleted) {
              completer.complete(null);
            }
          });
    }
    return completer.future;
  }

  /// In-memory backend user id when auth is already warm (sync, may be null).
  static int? peekUserId() => _userId;

  /// Sync own-listing check for marketplace chat (no network).
  static bool isOwnMarketplaceListingSync({
    required int myBackendId,
    int? ownerId,
    String? sellerUserId,
    String? merchantId,
  }) {
    return _isOwnMarketplaceListing(
      myBackendId: myBackendId,
      ownerId: ownerId,
      sellerUserId: sellerUserId,
      merchantId: merchantId,
    );
  }

  static final Map<String, Future<MerchantChatResult>> _merchantChatInFlight =
      {};
  static final Map<int, Future<BackendChatThread>> _ensureChatInFlight = {};

  /// Resolve seller and create/open a direct chat (bounded time).
  /// Concurrent callers with the same listing key share one in-flight request.
  static Future<MerchantChatResult> startMerchantChat({
    int? sqlItemId,
    int? ownerId,
    String? sellerUserId,
    String? serviceProviderId,
    String? merchantId,
    String? firestoreItemDocId,
    int? myUserId,
  }) async {
    final cacheKey = _marketplaceSellerCacheKey(
      firestoreItemDocId: firestoreItemDocId,
      merchantId: merchantId,
      sellerUserId: sellerUserId,
      sqlItemId: sqlItemId,
    );
    final inflightKey = cacheKey.isNotEmpty
        ? cacheKey
        : 'owner:${ownerId ?? 0}|su:${sellerUserId ?? ''}|sp:${serviceProviderId ?? ''}';

    final existing = _merchantChatInFlight[inflightKey];
    if (existing != null) return existing;

    final future = _startMerchantChatBody(
      sqlItemId: sqlItemId,
      ownerId: ownerId,
      sellerUserId: sellerUserId,
      serviceProviderId: serviceProviderId,
      merchantId: merchantId,
      firestoreItemDocId: firestoreItemDocId,
      myUserId: myUserId,
      cacheKey: cacheKey,
    );
    _merchantChatInFlight[inflightKey] = future;
    try {
      return await future;
    } finally {
      _merchantChatInFlight.remove(inflightKey);
    }
  }

  static Future<MerchantChatResult> _startMerchantChatBody({
    int? sqlItemId,
    int? ownerId,
    String? sellerUserId,
    String? serviceProviderId,
    String? merchantId,
    String? firestoreItemDocId,
    int? myUserId,
    required String cacheKey,
  }) async {
    await ensureAuth();
    final myId = myUserId ?? _userId!;

    if (_isOwnMarketplaceListing(
      myBackendId: myId,
      ownerId: ownerId,
      sellerUserId: sellerUserId,
      merchantId: merchantId,
    )) {
      throw Exception(_ownListingChatMessage);
    }

    // Memory seller id from a previous open of this listing.
    final remembered = cacheKey.isNotEmpty ? _marketplaceSellerCache[cacheKey] : null;
    if (remembered != null && remembered > 0 && remembered != myId) {
      final cachedThread = findCachedDirectChatWithPeer(remembered);
      if (cachedThread != null) {
        return MerchantChatResult(chat: cachedThread, sellerId: remembered);
      }
    }

    // Fast path: listing already has owner id + we have a cached thread.
    final ownerAccepted = _acceptSellerId(ownerId ?? remembered, myId);
    if (ownerAccepted != null) {
      final cachedForOwner = findCachedDirectChatWithPeer(ownerAccepted);
      if (cachedForOwner != null) {
        _rememberMarketplaceSeller(cacheKey, ownerAccepted);
        return MerchantChatResult(chat: cachedForOwner, sellerId: ownerAccepted);
      }
    }

    // Prefer known owner id → create/open chat directly (skip extra /users lookup).
    int? sellerId = ownerAccepted;
    if (sellerId != null) {
      try {
        final chat = await ensureChat(peerUserId: sellerId).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw Exception(
            'Chat server is not responding. Check your connection and try again.',
          ),
        );
        _rememberMarketplaceSeller(cacheKey, sellerId);
        _cachedThreads.removeWhere((t) => t.id == chat.id);
        _cachedThreads.insert(0, chat);
        return MerchantChatResult(chat: chat, sellerId: sellerId);
      } catch (e) {
        // Fall through to full seller resolution when owner id is stale/wrong.
        if (kDebugMode) {
          print('[BackendChatService] ensureChat(ownerId=$sellerId) failed: $e');
        }
        sellerId = null;
      }
    }

    sellerId ??= await resolveMarketplaceSeller(
      sqlItemId: sqlItemId,
      ownerId: ownerId,
      sellerUserId: sellerUserId,
      serviceProviderId: serviceProviderId,
      merchantId: merchantId,
      firestoreItemDocId: firestoreItemDocId,
      excludeUserId: myId,
      skipEnsureAuth: true,
      skipOwnerId: ownerId != null,
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );

    if (sellerId == null || sellerId <= 0) {
      sellerId = await resolveMarketplaceSeller(
        sqlItemId: sqlItemId,
        sellerUserId: sellerUserId,
        serviceProviderId: serviceProviderId,
        merchantId: merchantId,
        firestoreItemDocId: firestoreItemDocId,
        excludeUserId: myId,
        skipEnsureAuth: true,
        skipOwnerId: true,
        skipNumericParse: true,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    }

    if (sellerId == null || sellerId <= 0) {
      if (_isOwnMarketplaceListing(
            myBackendId: myId,
            ownerId: ownerId,
            sellerUserId: sellerUserId,
            merchantId: merchantId,
          ) ||
          await _isOwnMarketplaceListingFromFirestore(
            myBackendId: myId,
            firestoreItemDocId: firestoreItemDocId,
            merchantId: merchantId,
            sellerUserId: sellerUserId,
          )) {
        throw Exception(_ownListingChatMessage);
      }
      throw Exception(
        'Seller chat is unavailable — we could not find this seller\'s account. Try again later.',
      );
    }
    if (sellerId == myId) {
      throw Exception(_ownListingChatMessage);
    }

    final cached = findCachedDirectChatWithPeer(sellerId);
    if (cached != null) {
      _rememberMarketplaceSeller(cacheKey, sellerId);
      return MerchantChatResult(chat: cached, sellerId: sellerId);
    }

    try {
      final chat = await ensureChat(peerUserId: sellerId).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception(
          'Chat server is not responding. Check your connection and try again.',
        ),
      );
      _rememberMarketplaceSeller(cacheKey, sellerId);
      return MerchantChatResult(chat: chat, sellerId: sellerId);
    } catch (e) {
      _forgetSellerCache(cacheKey);
      _verifiedBackendUserCache[sellerId] = false;
      final msg = e.toString();
      if (msg.contains('404') || msg.contains('not found')) {
        throw Exception(
          'Seller chat is unavailable — this seller\'s account is not linked on the server yet. Ask them to open the merchant dashboard once while logged in.',
        );
      }
      rethrow;
    }
  }

  static final Map<String, int> _marketplaceSellerCache = {};

  static String _marketplaceSellerCacheKey({
    String? firestoreItemDocId,
    String? merchantId,
    String? sellerUserId,
    int? sqlItemId,
  }) {
    if (firestoreItemDocId != null && firestoreItemDocId.trim().isNotEmpty) {
      return 'doc:${firestoreItemDocId.trim()}';
    }
    for (final raw in [merchantId, sellerUserId]) {
      if (raw != null && raw.trim().isNotEmpty) return 'uid:${raw.trim()}';
    }
    if (sqlItemId != null && sqlItemId > 0) return 'sql:$sqlItemId';
    return '';
  }

  static void _rememberMarketplaceSeller(String cacheKey, int sellerId) {
    if (cacheKey.isEmpty || sellerId <= 0) return;
    _marketplaceSellerCache[cacheKey] = sellerId;
  }

  /// Warm auth + disk thread cache so marketplace chat opens faster.
  static Future<void> warmForMarketplaceChat() async {
    try {
      await ensureAuth();
      await BackendMessagingCache.initialize();
      final userId = _userId;
      if (userId == null) return;
      await _loadDeletedThreadIds(userId);
      if (_cachedThreads.isEmpty) {
        final diskThreads = BackendMessagingCache.peekThreads(userId);
        if (diskThreads.isNotEmpty) {
          _cachedThreads = _filterDeletedThreads(diskThreads);
        }
      }
    } catch (_) {}
  }

  /// Create or cache a direct chat in the background (product details prefetch).
  static Future<void> prefetchDirectChat(int peerUserId) async {
    if (peerUserId <= 0) return;
    try {
      await warmForMarketplaceChat();
      final myId = _userId;
      if (myId == null || myId == peerUserId) return;
      if (!(await verifyBackendUserExists(peerUserId))) return;
      if (findCachedDirectChatWithPeer(peerUserId) != null) return;

      final chat = await ensureChat(peerUserId: peerUserId);
      _cachedThreads.removeWhere((t) => t.id == chat.id);
      _cachedThreads.insert(0, chat);
      unawaited(BackendMessagingCache.saveThreads(myId, _cachedThreads));
    } catch (_) {}
  }

  static BackendChatThread? findCachedDirectChatWithPeer(int peerUserId) {
    if (peerUserId <= 0) return null;
    for (final thread in _cachedThreads) {
      if (thread.type != 'direct') continue;
      for (final participant in thread.participants) {
        if (participant.id == peerUserId) return thread;
      }
    }
    return null;
  }

  static BackendChatThread? findCachedThreadById(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return null;
    for (final thread in _cachedThreads) {
      if (thread.id.trim() == id) return thread;
    }
    return null;
  }

  /// Peer label/avatar for opening a chat from a notification payload.
  static ({String name, String avatarUrl, int? peerUserId})?
      cachedPeerLabelForChat(String chatId) {
    final thread = findCachedThreadById(chatId);
    if (thread == null) return null;
    final myId = _userId ?? 0;
    final name = peerDisplayNameForThread(thread, myId);
    final avatar = peerAvatarUrlForThread(thread, myId);
    final peer = thread.otherParticipant(myId);
    return (
      name: name,
      avatarUrl: avatar,
      peerUserId: (peer?.id ?? 0) > 0 ? peer!.id : null,
    );
  }

  /// Real name for the other person in a direct chat. Never returns "Chat".
  static Future<String?> resolvePeerTitle({
    String? chatId,
    int? peerUserId,
  }) async {
    await ensureBusinessNameCacheLoaded();
    final id = (chatId ?? '').trim();
    if (id.isNotEmpty) {
      final cached = cachedPeerLabelForChat(id);
      if (cached != null && !_isPlaceholderChatName(cached.name)) {
        return cached.name;
      }
    }

    BackendChatThread? thread;
    if (id.isNotEmpty) {
      try {
        thread = await getChat(id);
      } catch (_) {}
    }
    var myId = peekUserId() ?? 0;
    if (myId <= 0) {
      try {
        myId = await getUserId();
      } catch (_) {}
    }
    if (thread != null) {
      final fromThread = peerDisplayNameForThread(thread, myId);
      if (!_isPlaceholderChatName(fromThread)) return fromThread;
    }

    ChatParticipant? peer = thread?.otherParticipant(myId);
    if (peer == null && (peerUserId ?? 0) > 0) {
      peer = ChatParticipant(id: peerUserId!, name: '', email: '');
    }
    if (peer == null) return null;
    final found = await resolveBusinessNames([peer]);
    final hit = found[peer.displayLookupKey];
    if (hit != null && !_isPlaceholderChatName(hit)) return hit;
    return null;
  }

  /// Best-effort Firebase UID for the other person in a direct chat.
  static Future<String?> resolvePeerFirebaseUid({
    String? chatId,
    int? peerUserId,
    String? hintFirebaseUid,
  }) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    bool usable(String? uid) {
      final v = (uid ?? '').trim();
      if (!_looksLikeFirebaseUid(v)) return false;
      // Never treat "me" as the peer — callers used to hit this with shop ids.
      if (myUid.isNotEmpty && v == myUid) return false;
      return true;
    }

    final hint = (hintFirebaseUid ?? '').trim();
    if (usable(hint)) return hint;

    final myId = peekUserId() ?? 0;
    final threadId = (chatId ?? '').trim();
    if (threadId.isNotEmpty && myId > 0) {
      final thread = findCachedThreadById(threadId);
      if (thread != null) {
        final other = thread.otherParticipant(myId);
        if (usable(other?.firebaseUid)) return other!.firebaseUid!.trim();

        // Fallback: first participant that is not me by Nest id / firebase uid.
        for (final p in thread.participants) {
          if (myId > 0 && p.id == myId) continue;
          if (usable(p.firebaseUid)) return p.firebaseUid!.trim();
          if (p.id > 0 && p.id != myId) {
            final uid = await getFirebaseUidByUserId(p.id, quiet: true);
            if (usable(uid)) return uid!.trim();
          }
        }
      }
    }

    final peerId = peerUserId ?? 0;
    if (peerId > 0 && (myId <= 0 || peerId != myId)) {
      final uid = await getFirebaseUidByUserId(peerId, quiet: true);
      if (usable(uid)) return uid!.trim();

      // Firestore fallback when Nest profile omits firebaseUid.
      try {
        for (final field in ['userId', 'id', 'backendUserId', 'nestUserId']) {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .where(field, isEqualTo: peerId)
              .limit(1)
              .get();
          if (snap.docs.isEmpty) continue;
          final docUid = snap.docs.first.id.trim();
          if (usable(docUid)) return docUid;
        }
      } catch (_) {}
    }

    return null;
  }

  static bool _looksLikeFirebaseUid(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(value);
  }

  static int? _parseNumericId(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw > 0 ? raw : null;
    return int.tryParse(raw.toString());
  }

  static Future<int?> _sellerIdFromFirestoreItemDoc(
    String docId, {
    bool quiet = false,
  }) async {
    if (docId.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('marketplace_items')
          .doc(docId)
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;

      for (final key in [
        'merchantBackendId',
        'backendUserId',
        'ownerId',
        'userId',
      ]) {
        final parsed = _parseNumericId(data[key]);
        if (parsed != null) return parsed;
      }

      final sellerRaw = data['sellerUserId'];
      if (sellerRaw != null &&
          !_looksLikeFirebaseUid(sellerRaw.toString().trim())) {
        final parsed = _parseNumericId(sellerRaw);
        if (parsed != null) return parsed;
      }

      final merchantUid = data['merchantId']?.toString().trim() ?? '';
      if (_looksLikeFirebaseUid(merchantUid)) {
        return _sellerIdFromFirestoreMerchant(merchantUid, quiet: quiet);
      }
    } catch (e) {
      if (!quiet) {
        print('[BackendChatService] Firestore item doc lookup failed: $e');
      }
    }
    return null;
  }

  static Future<int?> _sellerIdFromUsersQuery(
    String firebaseUid, {
    bool quiet = false,
  }) async {
    if (firebaseUid.isEmpty) return null;
    const fields = ['firebaseUid', 'uid', 'firebase_uid'];
    for (final field in fields) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(field, isEqualTo: firebaseUid)
            .limit(1)
            .get();
        if (snap.docs.isEmpty) continue;
        final data = snap.docs.first.data();
        for (final key in ['backendUserId', 'userId', 'nestUserId', 'id']) {
          final parsed = _parseNumericId(data[key]);
          if (parsed != null) return parsed;
        }
      } catch (e) {
        if (!quiet) {
          print('[BackendChatService] users query ($field) failed: $e');
        }
      }
    }
    return null;
  }

  static Future<int?> _sellerIdFromFirestoreMerchant(
    String firebaseUid, {
    bool quiet = false,
  }) async {
    if (firebaseUid.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('marketplace_merchants')
          .doc(firebaseUid)
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;

      for (final key in [
        'backendUserId',
        'userId',
        'merchantUserId',
        'ownerId',
      ]) {
        final parsed = _parseNumericId(data[key]);
        if (parsed != null) return parsed;
      }
    } catch (e) {
      if (!quiet) {
        print('[BackendChatService] Firestore merchant lookup failed: $e');
      }
    }
    return null;
  }

  static Future<int?> _sellerIdFromFirestoreItems(
    String firebaseUid, {
    bool quiet = false,
  }) async {
    if (firebaseUid.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('marketplace_items')
          .where('merchantId', isEqualTo: firebaseUid)
          .limit(5)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        for (final key in [
          'merchantBackendId',
          'backendUserId',
          'ownerId',
          'userId',
        ]) {
          final parsed = _parseNumericId(data[key]);
          if (parsed != null) return parsed;
        }
        final sellerRaw = data['sellerUserId'];
        if (sellerRaw != null &&
            !_looksLikeFirebaseUid(sellerRaw.toString().trim())) {
          final parsed = _parseNumericId(sellerRaw);
          if (parsed != null) return parsed;
        }
      }
    } catch (e) {
      if (!quiet) {
        print('[BackendChatService] Firestore items lookup failed: $e');
      }
    }
    return null;
  }

  static Future<int?> _sellerIdFromFirestoreUser(
    String firebaseUid, {
    bool quiet = false,
  }) async {
    if (firebaseUid.isEmpty) return null;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(firebaseUid).get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;

      for (final key in ['backendUserId', 'userId', 'nestUserId', 'id']) {
        final parsed = _parseNumericId(data[key]);
        if (parsed != null) return parsed;
      }
    } catch (e) {
      if (!quiet) {
        print('[BackendChatService] Firestore user lookup failed: $e');
      }
    }
    return null;
  }

  static Future<int?> _ownerIdFromMarketplaceItem(int itemId, {bool quiet = false}) async {
    try {
      final response = await http.get(
        ApiConfig.endpoint('/marketplace/$itemId'),
        headers: {'Authorization': _authHeader, 'Accept': 'application/json'},
      ).timeout(_lookupTimeout);

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map) return null;
      final data = json['data'] is Map ? json['data'] as Map : json;
      return _parseNumericId(data['ownerId']);
    } catch (e) {
      if (!quiet) {
        print('[BackendChatService] marketplace owner lookup failed: $e');
      }
      return null;
    }
  }

  static Future<int?> _userIdFromServiceProvider(
    String serviceProviderId, {
    bool quiet = false,
  }) async {
    try {
      final response = await http.get(
        ApiConfig.endpoint('/serviceprovider/search/$serviceProviderId'),
        headers: {'Authorization': _authHeader, 'Accept': 'application/json'},
      ).timeout(_lookupTimeout);

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map) return null;

      final data = json['data'] is Map ? json['data'] as Map : json;
      final user = data['user'];
      if (user is Map) {
        return _parseNumericId(user['id']);
      }
      return _parseNumericId(data['userID'] ?? data['userId']);
    } catch (e) {
      if (!quiet) {
        print('[BackendChatService] service provider lookup failed: $e');
      }
      return null;
    }
  }

  static Future<int> getUserId() async {
    await ensureAuth();
    return _userId!;
  }

  /// Like [getUserIdByFirebaseUid] but rejects ids that map to a different Firebase UID.
  static Future<int?> getUserIdByFirebaseUidValidated(
    String firebaseUid, {
    int excludeUserId = 0,
    bool quiet = false,
  }) async {
    final id = await getUserIdByFirebaseUid(firebaseUid, quiet: quiet);
    if (id == null || id <= 0) return null;
    if (excludeUserId > 0 && id == excludeUserId) return null;

    final resolvedUid = await getFirebaseUidByUserId(id, quiet: true);
    if (resolvedUid != null &&
        resolvedUid.isNotEmpty &&
        resolvedUid != firebaseUid) {
      return null;
    }
    return id;
  }

  /// Get numeric user ID by Firebase UID (for looking up seller/merchant IDs)
  static Future<int?> getUserIdByFirebaseUid(
    String firebaseUid, {
    bool quiet = false,
  }) async {
    if (firebaseUid.isEmpty) return null;
    await ensureAuth();

    final attempts = <Uri>[
      ApiConfig.endpoint('/users').replace(
        queryParameters: {'firebaseUid': firebaseUid},
      ),
      ApiConfig.endpoint('/users').replace(
        queryParameters: {'uid': firebaseUid},
      ),
    ];

    for (final url in attempts) {
      try {
        final response = await http.get(
          url,
          headers: {'Authorization': _authHeader, 'Accept': 'application/json'},
        ).timeout(_lookupTimeout);

        if (response.statusCode != 200) continue;
        final json = jsonDecode(response.body);
        if (json is! Map) continue;

        final data = json['data'];
        if (data is List && data.isNotEmpty) {
          for (final user in data) {
            if (user is! Map) continue;
            final uid = (user['firebaseUid'] ?? user['uid'] ?? user['firebase_uid'])
                ?.toString()
                .trim();
            if ((uid ?? '').isNotEmpty && uid != firebaseUid) continue;
            final id = _parseNumericId(user['id'] ?? user['userId']);
            if (id != null) return id;
          }
        }
        if (data is Map) {
          final uid = (data['firebaseUid'] ?? data['uid'] ?? data['firebase_uid'])
              ?.toString()
              .trim();
          if ((uid ?? '').isEmpty || uid == firebaseUid) {
            final id = _parseNumericId(data['id'] ?? data['userId']);
            if (id != null) return id;
          }
        }

        final topLevel = _parseNumericId(json['id'] ?? json['userId']);
        if (topLevel != null) return topLevel;
      } catch (e) {
        if (!quiet) {
          print('[BackendChatService] Error fetching user by Firebase UID: $e');
        }
      }
    }
    return null;
  }

  static ChatParticipant _keepKnownProfilePhoto(
    ChatParticipant incoming,
    ChatParticipant? prior,
  ) {
    final nextPic = (incoming.profilePicture ?? '').trim();
    if (_usableAvatarUrl(nextPic)) {
      rememberPeerAvatar(incoming, nextPic);
      return incoming;
    }
    final oldPic = (prior?.profilePicture ?? '').trim();
    if (_usableAvatarUrl(oldPic)) {
      return incoming.copyWith(profilePicture: oldPic);
    }
    final cached = peekCachedAvatar(incoming);
    if (_usableAvatarUrl(cached)) {
      return incoming.copyWith(profilePicture: cached);
    }
    return incoming;
  }

  static final Map<String, String> _avatarMemo = {};
  static bool _avatarMemoLoaded = false;
  static const _kAvatarPrefs = 'chat_peer_avatars_v1';

  static Future<void> ensureAvatarCacheLoaded() async {
    if (_avatarMemoLoaded) return;
    _avatarMemoLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in ['profilepicture', 'profilePicture', 'photoUrl']) {
        rememberMyPhoto(prefs.getString(key));
      }
      final raw = prefs.getString(_kAvatarPrefs);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        final k = key.toString().trim();
        final url = value.toString().trim();
        if (k.isEmpty || !_usableAvatarUrl(url)) return;
        _avatarMemo.putIfAbsent(k, () => url);
      });
    } catch (_) {}
  }

  static void rememberPeerAvatar(ChatParticipant peer, String url) {
    final photo = url.trim();
    if (!_usableAvatarUrl(photo)) return;
    if (isMyPhoto(photo)) {
      forgetPeerAvatarIfMine(peer);
      return;
    }
    final before = peekCachedAvatar(peer);
    _rememberAvatar(peer, photo);
    if (before != photo) _persistAvatarMemo();
  }

  /// Drop cached photos for [peer] that are actually the signed-in user's.
  static void forgetPeerAvatarIfMine(ChatParticipant peer) {
    final keys = <String>[
      peer.displayLookupKey,
      if (peer.id > 0) 'i:${peer.id}',
      if (peer.email.trim().contains('@')) 'e:${peer.email.trim().toLowerCase()}',
      if ((peer.firebaseUid ?? '').trim().isNotEmpty) 'u:${peer.firebaseUid!.trim()}',
    ];
    var changed = false;
    for (final key in keys) {
      final v = _avatarMemo[key.trim()];
      if (v != null && isMyPhoto(v)) {
        _avatarMemo.remove(key.trim());
        changed = true;
      }
    }
    if (changed) _persistAvatarMemo();
  }

  static String? peekCachedAvatar(ChatParticipant peer) {
    final keys = <String>[
      peer.displayLookupKey,
      if (peer.id > 0) 'i:${peer.id}',
      if (peer.email.trim().contains('@')) 'e:${peer.email.trim().toLowerCase()}',
      if ((peer.firebaseUid ?? '').trim().isNotEmpty) 'u:${peer.firebaseUid!.trim()}',
    ];
    for (final key in keys) {
      final v = _avatarMemo[key.trim()];
      if (_usableAvatarUrl(v) && !isMyPhoto(v)) return v!.trim();
    }
    return null;
  }

  static void _rememberAvatar(ChatParticipant p, String url) {
    void put(String key) {
      if (key.trim().isEmpty) return;
      _avatarMemo[key] = url;
    }

    put(p.displayLookupKey);
    if (p.id > 0) put('i:${p.id}');
    final email = p.email.trim().toLowerCase();
    if (email.contains('@') && !email.startsWith('+firebase_')) {
      put('e:$email');
    }
    final uid = (p.firebaseUid ?? '').trim();
    if (uid.isNotEmpty) put('u:$uid');
  }

  static void _persistAvatarMemo() {
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAvatarPrefs, jsonEncode(_avatarMemo));
      } catch (_) {}
    }());
  }

  static final Map<String, String> _businessNameMemo = {};
  static bool _businessNameMemoLoaded = false;
  static bool _enrichingThreadNames = false;
  static const _kBusinessNamePrefs = 'chat_peer_business_names_v2';
  /// Peers already checked this session that have no business profile.
  static final Set<String> _noBusinessNameKeys = <String>{};
  static const Duration _nameLookupTimeout = Duration(seconds: 2);

  static String peerDisplayLookupKey(ChatParticipant p) => p.displayLookupKey;

  /// Keep a known business name so the inbox does not fall back offline.
  /// Only pass a business / store name here, never a personal name.
  static void rememberPeerDisplayName(ChatParticipant peer, String name) {
    final n = name.trim();
    if (n.isEmpty || _isPlaceholderChatName(n) || n.toLowerCase() == 'chat') {
      return;
    }
    final before = peekCachedBusinessName(peer.displayLookupKey);
    _rememberBusinessName(peer, n);
    if (before != n) _persistBusinessNameMemo();
  }

  static String? peekCachedBusinessName(String key) {
    final k = key.trim();
    if (k.isEmpty) return null;
    final v = _businessNameMemo[k];
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  static Future<void> ensureBusinessNameCacheLoaded() async {
    unawaited(ensureAvatarCacheLoaded());
    if (_businessNameMemoLoaded) return;
    _businessNameMemoLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kBusinessNamePrefs);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        final k = key.toString().trim();
        final n = value.toString().trim();
        if (k.isEmpty || n.isEmpty || _isPlaceholderChatName(n)) return;
        _businessNameMemo.putIfAbsent(k, () => n);
      });
    } catch (_) {}
  }

  static void _rememberBusinessName(ChatParticipant p, String name) {
    final n = name.trim();
    if (n.isEmpty || _isPlaceholderChatName(n)) return;
    void put(String key) {
      if (key.trim().isEmpty) return;
      _businessNameMemo[key] = n;
    }

    put(p.displayLookupKey);
    if (p.id > 0) put('i:${p.id}');
    final email = p.email.trim().toLowerCase();
    if (email.contains('@') && !email.startsWith('+firebase_')) {
      put('e:$email');
    }
    final uid = (p.firebaseUid ?? '').trim();
    if (uid.isNotEmpty) put('u:$uid');
  }

  static void _persistBusinessNameMemo() {
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kBusinessNamePrefs, jsonEncode(_businessNameMemo));
      } catch (_) {}
    }());
  }

  static bool _applyMemoToCachedThreads() {
    var changed = false;
    for (var i = 0; i < _cachedThreads.length; i++) {
      final t = _cachedThreads[i];
      var threadChanged = false;
      final next = <ChatParticipant>[];
      for (final p in t.participants) {
        final memo = peekCachedBusinessName(p.displayLookupKey) ??
            (p.id > 0 ? peekCachedBusinessName('i:${p.id}') : null);
        if (memo == null ||
            ((p.businessName ?? '').trim() == memo && p.name.trim() == memo)) {
          next.add(p);
          continue;
        }
        threadChanged = true;
        next.add(p.copyWith(name: memo, businessName: memo));
      }
      if (threadChanged) {
        changed = true;
        _cachedThreads[i] = t.copyWith(participants: next);
      }
    }
    return changed;
  }

  static Future<void> _enrichCachedThreadNames() async {
    if (_enrichingThreadNames || _cachedThreads.isEmpty) return;
    _enrichingThreadNames = true;
    try {
      await ensureBusinessNameCacheLoaded();
      if (_applyMemoToCachedThreads()) _emitCachedThreads();

      final myId = _userId ?? 0;
      final peers = <ChatParticipant>[];
      for (final t in _cachedThreads) {
        final other = t.otherParticipant(myId);
        if (other != null) peers.add(other);
      }
      if (peers.isEmpty) return;

      await resolveBusinessNames(
        peers,
        onResolved: (_, __) {
          if (_applyMemoToCachedThreads()) _emitCachedThreads();
        },
      );
      if (_applyMemoToCachedThreads()) {
        _emitCachedThreads();
        final userId = _userId;
        if (userId != null) {
          unawaited(BackendMessagingCache.saveThreads(userId, _cachedThreads));
        }
      }
    } catch (_) {
    } finally {
      _enrichingThreadNames = false;
    }
  }

  /// Resolve store / business names for chat list rows (never email local-part).
  static Future<Map<String, String>> resolveBusinessNames(
    List<ChatParticipant> peers, {
    void Function(String key, String name)? onResolved,
  }) async {
    await ensureBusinessNameCacheLoaded();
    final out = <String, String>{};
    final pending = <ChatParticipant>[];
    for (final p in peers) {
      final key = p.displayLookupKey;
      final memo = peekCachedBusinessName(key) ??
          (p.id > 0 ? peekCachedBusinessName('i:${p.id}') : null);
      if (memo != null) {
        _rememberBusinessName(p, memo);
        out[key] = memo;
        onResolved?.call(key, memo);
        continue;
      }
      final known = (p.businessName ?? '').trim();
      if (known.isNotEmpty && !_isPlaceholderChatName(known)) {
        _rememberBusinessName(p, known);
        out[key] = known;
        onResolved?.call(key, known);
        continue;
      }
      if (_noBusinessNameKeys.contains(key)) continue;
      pending.add(p);
    }

    if (pending.isEmpty) {
      if (out.isNotEmpty) _persistBusinessNameMemo();
      return out;
    }

    await Future.wait(pending.map((p) async {
      final key = p.displayLookupKey;
      final found = await _lookupBusinessNameForPeer(p);
      if (found == null || found.isEmpty) {
        _noBusinessNameKeys.add(key);
        return;
      }
      _rememberBusinessName(p, found);
      out[key] = found;
      onResolved?.call(key, found);
    }));
    _persistBusinessNameMemo();
    return out;
  }

  static Future<String?> _firstNonEmpty(List<Future<String?>> jobs) {
    if (jobs.isEmpty) return Future<String?>.value(null);
    final done = Completer<String?>();
    var remaining = jobs.length;
    for (final job in jobs) {
      job.then((value) {
        if (done.isCompleted) return;
        final n = (value ?? '').trim();
        if (n.isNotEmpty && !_isPlaceholderChatName(n)) {
          done.complete(n);
          return;
        }
        remaining--;
        if (remaining == 0) done.complete(null);
      }).catchError((_) {
        if (done.isCompleted) return;
        remaining--;
        if (remaining == 0) done.complete(null);
      });
    }
    return done.future;
  }

  static Future<String?> _nameFromQuery(
    String collection,
    String field,
    String value,
  ) async {
    final q = FirebaseFirestore.instance
        .collection(collection)
        .where(field, isEqualTo: value)
        .limit(1);
    try {
      final cached = await q.get(const GetOptions(source: Source.cache));
      final fromCache = _usableProfileDisplayName(
        cached.docs.isEmpty ? const {} : cached.docs.first.data(),
      );
      if (fromCache != null) return fromCache;
    } catch (_) {}
    try {
      final snap = await q.get(const GetOptions(source: Source.serverAndCache));
      return _usableProfileDisplayName(
        snap.docs.isEmpty ? const {} : snap.docs.first.data(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _nameFromDoc(String collection, String id) async {
    if (id.isEmpty) return null;
    final ref = FirebaseFirestore.instance.collection(collection).doc(id);
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      final fromCache = _usableProfileDisplayName(cached.data() ?? const {});
      if (fromCache != null) return fromCache;
    } catch (_) {}
    try {
      final doc = await ref.get(const GetOptions(source: Source.serverAndCache));
      return _usableProfileDisplayName(doc.data() ?? const {});
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _nameFromApiUser(int userId) async {
    if (userId <= 0) return null;
    try {
      final response = await http
          .get(
            ApiConfig.endpoint('/users/$userId'),
            headers: {
              'Authorization': _authHeader,
              'Accept': 'application/json',
            },
          )
          .timeout(_nameLookupTimeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      final data = json is Map
          ? (json['data'] is Map ? json['data'] as Map : json)
          : null;
      if (data is! Map) return null;
      return _usableProfileDisplayName(data);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _lookupBusinessNameForPeer(ChatParticipant p) async {
    try {
      final email = p.email.trim();
      final uid = (p.firebaseUid ?? '').trim();
      final firstWave = <Future<String?>>[];
      if (email.contains('@') && !email.startsWith('+firebase_')) {
        firstWave.add(_nameFromQuery('users', 'email', email));
        firstWave.add(_nameFromQuery('marketplace_merchants', 'email', email));
      }
      if (uid.isNotEmpty) {
        firstWave.add(_nameFromDoc('users', uid));
        firstWave.add(_nameFromDoc('marketplace_merchants', uid));
      }
      if (p.id > 0) {
        firstWave.add(_nameFromApiUser(p.id));
      }
      final hit = await _firstNonEmpty(firstWave);
      if (hit != null) return hit;

      final secondWave = <Future<String?>>[];
      if (email.contains('@') && !email.startsWith('+firebase_')) {
        secondWave.add(_nameFromQuery('users', 'userEmail', email));
        secondWave.add(
          _nameFromQuery('accommodation_merchants', 'email', email),
        );
      }
      if (uid.isNotEmpty) {
        secondWave.add(_nameFromDoc('accommodation_merchants', uid));
      }
      return _firstNonEmpty(secondWave);
    } catch (_) {
      return null;
    }
  }

  /// Resolve a backend user's Firebase UID (used for merchant shop pages).
  static Future<String?> getFirebaseUidByUserId(
    int userId, {
    bool quiet = false,
  }) async {
    if (userId <= 0) return null;
    await ensureAuth();

    try {
      final response = await http
          .get(
            ApiConfig.endpoint('/users/$userId'),
            headers: {'Authorization': _authHeader},
          )
          .timeout(_lookupTimeout);

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      final data = json is Map<String, dynamic>
          ? (json['data'] is Map<String, dynamic>
              ? json['data'] as Map<String, dynamic>
              : json)
          : null;
      if (data == null) return null;

      for (final key in ['firebaseUid', 'firebase_uid', 'uid']) {
        final raw = data[key]?.toString().trim();
        if (raw != null && raw.isNotEmpty && _looksLikeFirebaseUid(raw)) {
          return raw;
        }
      }
    } catch (e) {
      if (!quiet) {
        print('[BackendChatService] Error fetching Firebase UID for user $userId: $e');
      }
    }
    return null;
  }

  static String get _authHeader => 'Bearer $_authToken';

  /// Get user's chat threads
  static Future<List<BackendChatThread>> getThreads({
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      await ensureAuth();
    } catch (_) {}

    try {
      var response = await http.get(
        Uri.parse('$_baseUrl/chats?page=$page&pageSize=$pageSize'),
        headers: {'Authorization': _authHeader},
      ).timeout(_lookupTimeout);

      if (response.statusCode == 401) {
        // Token expired on server — force refresh once and retry
        try {
          final refreshed = await AuthHandler.refreshTokenAfterUnauthorized();
          if (refreshed != null && refreshed.isNotEmpty) {
            _authToken = refreshed;
          } else {
            await ensureAuth(forceRefresh: true);
          }
          response = await http.get(
            Uri.parse('$_baseUrl/chats?page=$page&pageSize=$pageSize'),
            headers: {'Authorization': _authHeader},
          ).timeout(_lookupTimeout);
        } catch (_) {}
      }

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = _extractThreadListFromJson(json);
        return data
            .whereType<Map>()
            .map((t) => BackendChatThread.fromJson(
                  Map<String, dynamic>.from(t),
                ))
            .toList();
      } else if (response.statusCode == 401) {
        throw Exception(
          FirebaseAuth.instance.currentUser != null
              ? 'Could not verify your session with the server. Check your connection and try again.'
              : 'Unauthorized - please log in again',
        );
      } else {
        throw Exception('Failed to fetch chats: ${response.statusCode}');
      }
    } catch (e) {
      if (page == 1 && _userId != null) {
        final cached = BackendMessagingCache.peekThreads(_userId!);
        if (cached.isNotEmpty) return cached;
      }
      if (FirebaseAuth.instance.currentUser != null) {
        if (_userId != null) {
          final cached = BackendMessagingCache.peekThreads(_userId!);
          return cached;
        }
        return const <BackendChatThread>[];
      }
      print('[BackendChatService] Error fetching threads: $e');
      rethrow;
    }
  }

  /// Live thread list: initial REST load, WebSocket patches, manual refresh.
  /// Broadcast — safe for multiple listeners (chat list, providers, badges).
  static Stream<List<BackendChatThread>> watchThreads() {
    return Stream.multi((multi) async {
      // WhatsApp-style: emit disk/memory cache immediately before network.
      try {
        final seeded = await loadCachedThreads();
        if (!multi.isClosed) {
          multi.add(seeded);
        }
      } catch (_) {
        if (!multi.isClosed && _cachedThreads.isNotEmpty) {
          multi.add(_filterDeletedThreads(_cachedThreads));
        }
      }

      try {
        await _ensureThreadsWatchInitialized();
        if (!multi.isClosed) {
          multi.add(_filterDeletedThreads(_cachedThreads));
        }
      } catch (e, st) {
        if (!multi.isClosed) {
          if (FirebaseAuth.instance.currentUser != null) {
            multi.add(_filterDeletedThreads(_cachedThreads));
          } else {
            multi.addError(e, st);
            return;
          }
        }
      }

      final sub = _threadsLiveController.stream.listen(
        multi.add,
        onError: (err, st) {
          if (FirebaseAuth.instance.currentUser != null) {
            multi.add(_filterDeletedThreads(_cachedThreads));
          } else {
            multi.addError(err, st);
          }
        },
      );
      multi.onCancel = () => sub.cancel();
    });
  }

  /// @deprecated Use [watchThreads] — kept for older call sites.
  static Stream<List<BackendChatThread>> threadsStream({
    Duration pollInterval = const Duration(seconds: 60),
  }) =>
      watchThreads();

  /// Get a specific chat
  static Future<BackendChatThread> getChat(String chatId) async {
    await ensureAuth();

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/chats/$chatId'),
        headers: {'Authorization': _authHeader},
      ).timeout(_lookupTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final chatData = body is Map<String, dynamic>
            ? (body['data'] is Map
                ? Map<String, dynamic>.from(body['data'] as Map)
                : body)
            : body;
        return BackendChatThread.fromJson(
          Map<String, dynamic>.from(chatData as Map),
        );
      } else {
        throw Exception('Failed to fetch chat: ${response.statusCode}');
      }
    } catch (e) {
      print('[BackendChatService] Error fetching chat: $e');
      rethrow;
    }
  }

  /// Cached messages for instant UI (memory + disk). Works even before Nest user id.
  static List<BackendChatMessage> peekCachedMessages(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return const [];
    return BackendMessagingCache.peekMessages(_userId, id);
  }

  /// In-memory threads for pickers (forward target list, etc.).
  static List<BackendChatThread> peekCachedThreads() {
    return List<BackendChatThread>.from(
      _filterDeletedThreads(_cachedThreads),
    );
  }

  /// Like [peekCachedMessages] but warms Hive + prefs user id first (WhatsApp-style open).
  static Future<List<BackendChatMessage>> loadCachedMessages(String chatId) async {
    await BackendMessagingCache.initialize();
    var uid = _userId;
    if (uid == null) {
      try {
        final sp = await SharedPreferences.getInstance();
        uid = sp.getInt('userId') ?? sp.getInt('user_id');
        if (uid != null && uid > 0) {
          _userId = uid;
        }
      } catch (_) {}
    }
    // Peek works without uid (memory + any disk key for this chat).
    return BackendMessagingCache.peekMessages(uid, chatId);
  }

  /// Instant thread list from memory/disk (no network).
  static Future<List<BackendChatThread>> loadCachedThreads() async {
    await BackendMessagingCache.initialize();
    if (_cachedThreads.isNotEmpty) {
      return _filterDeletedThreads(_cachedThreads);
    }
    var uid = _userId;
    if (uid == null) {
      try {
        final sp = await SharedPreferences.getInstance();
        uid = sp.getInt('userId') ?? sp.getInt('user_id');
        if (uid != null && uid > 0) _userId = uid;
      } catch (_) {}
    }
    if (uid == null) return const [];
    await _loadDeletedThreadIds(uid);
    final disk = BackendMessagingCache.peekThreads(uid);
    if (disk.isEmpty) return const [];
    _cachedThreads = _filterDeletedThreads(disk);
    _cachedThreadsOwnerUserId = uid;
    _applyMemoToCachedThreads();
    return List<BackendChatThread>.from(_cachedThreads);
  }

  /// Get messages in a chat (network fetch + disk cache).
  static Future<List<BackendChatMessage>> getMessages(
    String chatId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    await ensureAuth();
    await BackendMessagingCache.initialize();

    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/chats/$chatId/messages?page=$page&pageSize=$pageSize'),
        headers: {'Authorization': _authHeader},
      ).timeout(_lookupTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = json['data'] as List? ?? [];
        final messages = data
            .map((m) => BackendChatMessage.fromJson(m as Map<String, dynamic>))
            .toList();
        final visible = BackendMessagingCache.filterAfterClear(
          _userId,
          chatId,
          messages,
        );
        if (_userId != null) {
          if (page == 1) {
            // Keep any older pages already cached locally.
            final prior = BackendMessagingCache.peekMessages(_userId, chatId);
            if (prior.isNotEmpty && visible.isNotEmpty) {
              final cutoff = visible.first.createdAt;
              final older = prior
                  .where((m) => m.createdAt.isBefore(cutoff))
                  .toList();
              if (older.isNotEmpty) {
                final byId = <String, BackendChatMessage>{};
                for (final m in [...older, ...visible]) {
                  final key = m.id.isNotEmpty
                      ? m.id
                      : (m.clientMessageId ??
                          '${m.createdAt.millisecondsSinceEpoch}');
                  byId[key] = m;
                }
                final merged = byId.values.toList()
                  ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                await BackendMessagingCache.saveMessages(
                  _userId!,
                  chatId,
                  merged,
                );
                return visible;
              }
            }
            await BackendMessagingCache.saveMessages(
              _userId!,
              chatId,
              visible,
            );
          } else if (visible.isNotEmpty) {
            final prior = BackendMessagingCache.peekMessages(_userId, chatId);
            final byId = <String, BackendChatMessage>{};
            for (final m in [...visible, ...prior]) {
              final key = m.id.isNotEmpty
                  ? m.id
                  : (m.clientMessageId ??
                      '${m.createdAt.millisecondsSinceEpoch}');
              byId[key] = m;
            }
            final merged = byId.values.toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
            await BackendMessagingCache.saveMessages(
              _userId!,
              chatId,
              merged,
            );
          }
        }
        return visible;
      } else {
        throw Exception('Failed to fetch messages: ${response.statusCode}');
      }
    } catch (e) {
      if (page == 1) {
        final cached = peekCachedMessages(chatId);
        if (cached.isNotEmpty) return cached;
      }
      print('[BackendChatService] Error fetching messages: $e');
      rethrow;
    }
  }

  /// Send a message
  static Future<BackendChatMessage> sendMessage({
    required String chatId,
    required String content,
    String type = 'text',
    List<Map<String, dynamic>>? tags,
    List<Map<String, dynamic>>? attachments,
    Map<String, dynamic>? metadata,
    String? clientMessageId,
  }) async {
    await ensureAuth();

    try {
      final payload = <String, dynamic>{
        'content': content,
        'type': type,
      };
      if (tags != null && tags.isNotEmpty) payload['tags'] = tags;
      if (attachments != null && attachments.isNotEmpty) {
        payload['attachments'] = attachments;
      }
      if (metadata != null && metadata.isNotEmpty) payload['metadata'] = metadata;
      final apiClientId = _apiClientMessageId(clientMessageId);
      if (apiClientId != null) {
        payload['clientMessageId'] = apiClientId;
      }

      final response = await http
          .post(
            Uri.parse('$_baseUrl/chats/$chatId/messages'),
            headers: {
              'Authorization': _authHeader,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
            .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        final msg = BackendChatMessage.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
        if (_userId != null) {
          unawaited(BackendMessagingCache.upsertMessage(_userId!, msg));
        }
        _applyOutgoingMessageToThreadList(msg);
        refreshThreads();
        return msg;
      } else {
        if (kDebugMode) {
          print(
            '[BackendChatService] sendMessage ${response.statusCode}: ${response.body}',
          );
        }
        throw Exception(
          'Failed to send message: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      print('[BackendChatService] Error sending message: $e');
      rethrow;
    }
  }

  /// Upload a chat image/file to the backend CDN.
  static Future<String> uploadChatAttachment({
    required Uint8List bytes,
    required String filename,
    String? mimeType,
  }) async {
    await ensureAuth();
    final uri = ApiConfig.endpoint('/uploads');
    final detectedMime =
        mimeType ?? lookupMimeType(filename, headerBytes: bytes) ?? 'image/jpeg';
    final parts = detectedMime.split('/');
    final contentType = parts.length == 2
        ? MediaType(parts[0], parts[1])
        : MediaType('image', 'jpeg');

    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = _authHeader
      ..headers['Accept'] = 'application/json'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename.isNotEmpty ? filename : 'chat.jpg',
          contentType: contentType,
        ),
      );

    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (kDebugMode) {
        print(
          '[BackendChatService] upload failed ${resp.statusCode}: ${resp.body}',
        );
      }
      throw Exception('Upload failed (${resp.statusCode})');
    }
    final body = jsonDecode(resp.body);
    final rawUrl = _extractUploadUrl(body);
    if (rawUrl.isEmpty) {
      throw Exception('Upload succeeded but no URL was returned');
    }
    return _normalizeMediaUrl(rawUrl);
  }

  static String _extractUploadUrl(dynamic body) {
    if (body is! Map) return '';
    final direct = body['url']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final data = body['data'];
    if (data is Map) {
      final nested = data['url']?.toString().trim();
      if (nested != null && nested.isNotEmpty) return nested;
    }
    return '';
  }

  static String _normalizeMediaUrl(String url) {
    var trimmed = url.trim();
    if (trimmed.startsWith('http://')) {
      // Prefer HTTPS so the first image request succeeds (avoids http→https retry lag).
      trimmed = 'https://${trimmed.substring(7)}';
    }
    if (trimmed.startsWith('https://')) {
      return trimmed;
    }
    final root = ApiConfig.prod.replaceAll(RegExp(r'/+$'), '');
    if (trimmed.startsWith('/')) return '$root$trimmed';
    return '$root/$trimmed';
  }

  /// Send an image message, trying common backend payload shapes.
  static Future<BackendChatMessage> sendImageMessage({
    required String chatId,
    required String imageUrl,
    String caption = '',
    String? clientMessageId,
    String? mimeType,
    Map<String, dynamic>? metadata,
  }) async {
    await ensureAuth();

    final trimmedCaption = caption.trim();
    final forwarded = metadata != null &&
        (metadata['forwarded'] == true || metadata['isForwarded'] == true);

    // Legacy text prefix is the known-good path; keep one modern fallback.
    String legacyContent;
    if (forwarded) {
      legacyContent = trimmedCaption.isNotEmpty
          ? '$_legacyImgPrefix$imageUrl\n↪️ Forwarded\n$trimmedCaption'
          : '$_legacyImgPrefix$imageUrl\n↪️ Forwarded';
    } else {
      legacyContent = trimmedCaption.isNotEmpty
          ? '$_legacyImgPrefix$imageUrl\n$trimmedCaption'
          : '$_legacyImgPrefix$imageUrl';
    }
    final attempts = <Map<String, dynamic>>[
      {
        'content': legacyContent,
        'type': 'text',
      },
      {
        'content': trimmedCaption.isNotEmpty ? trimmedCaption : imageUrl,
        'type': 'image',
        'attachmentUrls': [imageUrl],
      },
    ];

    Object? lastError;
    for (final attempt in attempts) {
      try {
        final payload = Map<String, dynamic>.from(attempt);
        final apiClientId = _apiClientMessageId(clientMessageId);
        if (apiClientId != null) {
          payload['clientMessageId'] = apiClientId;
        }
        if (metadata != null && metadata.isNotEmpty) {
          final existing = payload['metadata'];
          payload['metadata'] = {
            if (existing is Map) ...Map<String, dynamic>.from(existing),
            ...metadata,
          };
        }

        final response = await http
            .post(
              Uri.parse('$_baseUrl/chats/$chatId/messages'),
              headers: {
                'Authorization': _authHeader,
                'Content-Type': 'application/json',
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 201) {
          final body = jsonDecode(response.body);
          final raw = body is Map<String, dynamic>
              ? body
              : (body is Map && body['data'] is Map)
                  ? Map<String, dynamic>.from(body['data'] as Map)
                  : body;
          final msg = BackendChatMessage.fromJson(
            Map<String, dynamic>.from(raw as Map),
          );
          if (_userId != null) {
            unawaited(BackendMessagingCache.upsertMessage(_userId!, msg));
          }
          _applyOutgoingMessageToThreadList(msg);
          refreshThreads();
          return msg;
        }

        // Auth errors won't be fixed by a different payload shape.
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }

        if (kDebugMode) {
          print(
            '[BackendChatService] sendImage attempt ${response.statusCode}: ${response.body}',
          );
        }
        lastError = 'HTTP ${response.statusCode}: ${response.body}';
      } catch (e) {
        lastError = e;
        if (e is Exception && e.toString().contains('HTTP 401')) rethrow;
        if (e is Exception && e.toString().contains('HTTP 403')) rethrow;
      }
    }

    throw Exception('Failed to send image: $lastError');
  }

  /// Send a video message. One payload so the reply is not sent twice.
  static Future<BackendChatMessage> sendVideoMessage({
    required String chatId,
    required String videoUrl,
    String caption = '',
    String? clientMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    await ensureAuth();
    final trimmedCaption = caption.trim();
    final content = trimmedCaption.isNotEmpty
        ? '$_legacyVidPrefix$videoUrl\n$trimmedCaption'
        : '$_legacyVidPrefix$videoUrl';
    return sendMessage(
      chatId: chatId,
      content: content,
      type: 'text',
      clientMessageId: clientMessageId,
      metadata: metadata,
    );
  }

  /// Send a voice note message, trying common backend payload shapes.
  static Future<BackendChatMessage> sendAudioMessage({
    required String chatId,
    required String audioUrl,
    required int durationMs,
    String? clientMessageId,
    String? mimeType,
    Map<String, dynamic>? metadata,
  }) async {
    await ensureAuth();

    final duration = durationMs.clamp(0, 600000);
    final mergedMeta = <String, dynamic>{
      'durationMs': duration,
      if (metadata != null) ...metadata,
    };

    // Legacy prefix first (known-good), then one modern fallback.
    final forwarded = mergedMeta['forwarded'] == true ||
        mergedMeta['isForwarded'] == true;
    final audContent = forwarded
        ? '$_legacyAudPrefix$audioUrl|$duration\n↪️ Forwarded'
        : '$_legacyAudPrefix$audioUrl|$duration';
    final attempts = <Map<String, dynamic>>[
      {
        'content': audContent,
        'type': 'text',
        'metadata': mergedMeta,
      },
      {
        'content': audioUrl,
        'type': 'audio',
        'attachmentUrls': [audioUrl],
        'metadata': mergedMeta,
      },
    ];

    Object? lastError;
    for (final attempt in attempts) {
      try {
        final payload = Map<String, dynamic>.from(attempt);
        final apiClientId = _apiClientMessageId(clientMessageId);
        if (apiClientId != null) {
          payload['clientMessageId'] = apiClientId;
        }

        final response = await http
            .post(
              Uri.parse('$_baseUrl/chats/$chatId/messages'),
              headers: {
                'Authorization': _authHeader,
                'Content-Type': 'application/json',
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 201) {
          final body = jsonDecode(response.body);
          final raw = body is Map<String, dynamic>
              ? body
              : (body is Map && body['data'] is Map)
                  ? Map<String, dynamic>.from(body['data'] as Map)
                  : body;
          final msg = BackendChatMessage.fromJson(
            Map<String, dynamic>.from(raw as Map),
          );
          if (_userId != null) {
            unawaited(BackendMessagingCache.upsertMessage(_userId!, msg));
          }
          _applyOutgoingMessageToThreadList(msg);
          refreshThreads();
          return msg;
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }

        if (kDebugMode) {
          print(
            '[BackendChatService] sendAudio attempt ${response.statusCode}: ${response.body}',
          );
        }
        lastError = 'HTTP ${response.statusCode}: ${response.body}';
      } catch (e) {
        lastError = e;
        if (e is Exception && e.toString().contains('HTTP 401')) rethrow;
        if (e is Exception && e.toString().contains('HTTP 403')) rethrow;
      }
    }

    throw Exception('Failed to send voice note: $lastError');
  }

  /// Edit a message
  static Future<BackendChatMessage> editMessage({
    required String chatId,
    required String messageId,
    required String newContent,
  }) async {
    await ensureAuth();

    try {
      final response = await http
          .put(
            Uri.parse('$_baseUrl/chats/$chatId/messages/$messageId'),
            headers: {
              'Authorization': _authHeader,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'content': newContent}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final msg = BackendChatMessage.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
        if (_userId != null) {
          unawaited(BackendMessagingCache.upsertMessage(_userId!, msg));
        }
        return msg;
      } else {
        throw Exception('Failed to edit message: ${response.statusCode}');
      }
    } catch (e) {
      print('[BackendChatService] Error editing message: $e');
      rethrow;
    }
  }

  /// Clear all messages in a chat (server attempt + local cache).
  static Future<void> clearChatHistory(String chatId) async {
    await ensureAuth();
    final userId = _userId;

    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/chats/$chatId/messages'),
        headers: {'Authorization': _authHeader},
      ).timeout(const Duration(seconds: 15));
      if (kDebugMode &&
          response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 404) {
        print(
          '[BackendChatService] clearChatHistory: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('[BackendChatService] clearChatHistory network: $e');
      }
    }

    if (userId != null) {
      await BackendMessagingCache.markChatCleared(userId, chatId);
    }

    final idx = _cachedThreads.indexWhere((t) => t.id == chatId);
    if (idx >= 0) {
      _cachedThreads[idx] = _cachedThreads[idx].copyWith(
        lastMessagePreview: null,
        unreadCount: 0,
      );
      _emitCachedThreads();
    }
  }

  /// Archive/remove a chat from the current user's inbox (local first, then server).
  static Future<void> deleteChat(String chatId) async {
    await ensureAuth();
    final userId = _userId;
    if (userId == null) {
      throw Exception('Not signed in');
    }

    final normalizedId = chatId.trim();
    if (normalizedId.isEmpty) return;

    // Instant local removal so the list clears immediately.
    _deletedThreadIds.add(normalizedId);
    removeThreadLocally(normalizedId);
    await BackendMessagingCache.markThreadDeleted(userId, normalizedId);
    await BackendMessagingCache.deleteMessagesForChat(userId, normalizedId);

    // Best-effort server archive/delete — do not block the UI on network.
    unawaited(() async {
      final archived = await _archiveChatOnServer(normalizedId);
      if (!archived && kDebugMode) {
        print(
          '[BackendChatService] Server archive failed for $normalizedId '
          '(kept deleted locally)',
        );
      }
    }());
  }

  static bool _isArchiveResponseSuccess(http.Response response) {
    if (response.statusCode == 200 || response.statusCode == 204) {
      return true;
    }
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['success'] == true) return true;
      if (body is Map && body['archived'] == true) return true;
    } catch (_) {}
    return false;
  }

  /// DELETE /chats/{id}, then PATCH /chats/{id}/archive as fallback.
  static Future<bool> _archiveChatOnServer(String chatId) async {
    Object? deleteError;

    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/chats/$chatId'),
        headers: {
          'Authorization': _authHeader,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (_isArchiveResponseSuccess(response)) return true;

      if (kDebugMode) {
        print(
          '[BackendChatService] DELETE chat $chatId: '
          '${response.statusCode} ${response.body}',
        );
      }
      deleteError = 'HTTP ${response.statusCode}';
    } catch (e) {
      deleteError = e;
      if (kDebugMode) print('[BackendChatService] DELETE chat network: $e');
    }

    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/chats/$chatId/archive'),
        headers: {
          'Authorization': _authHeader,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (_isArchiveResponseSuccess(response)) return true;

      if (kDebugMode) {
        print(
          '[BackendChatService] PATCH archive $chatId: '
          '${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      if (kDebugMode) print('[BackendChatService] PATCH archive network: $e');
    }

    if (kDebugMode) {
      print('[BackendChatService] archive failed after DELETE: $deleteError');
    }
    return false;
  }

  /// Drop a thread from memory and disk cache without calling the API.
  static void removeThreadLocally(String chatId) {
    final normalizedId = chatId.trim();
    if (normalizedId.isEmpty) return;

    _cachedThreads.removeWhere((t) => t.id.trim() == normalizedId);
    _emitCachedThreads();
    final userId = _userId;
    if (userId == null) return;
    final threads = List<BackendChatThread>.from(
      BackendMessagingCache.peekThreads(userId),
    )..removeWhere((t) => t.id.trim() == normalizedId);
    unawaited(BackendMessagingCache.saveThreads(userId, threads));
  }

  /// Delete a message
  static Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    await ensureAuth();

    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/chats/$chatId/messages/$messageId'),
        headers: {'Authorization': _authHeader},
      ).timeout(_lookupTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to delete message: ${response.statusCode}');
      }
      final userId = _userId;
      if (userId != null) {
        unawaited(
          BackendMessagingCache.removeMessageFromCache(
            userId,
            chatId,
            messageId,
          ),
        );
      }
    } catch (e) {
      print('[BackendChatService] Error deleting message: $e');
      rethrow;
    }
  }

  /// Create or get direct chat with a user.
  /// Concurrent callers for the same peer share one in-flight POST.
  static Future<BackendChatThread> ensureChat({
    required int peerUserId,
    String? peerName,
    String? peerAvatar,
  }) async {
    final existing = _ensureChatInFlight[peerUserId];
    if (existing != null) return existing;

    final future = _ensureChatBody(
      peerUserId: peerUserId,
      peerName: peerName,
      peerAvatar: peerAvatar,
    );
    _ensureChatInFlight[peerUserId] = future;
    try {
      return await future;
    } finally {
      _ensureChatInFlight.remove(peerUserId);
    }
  }

  static Future<BackendChatThread> _ensureChatBody({
    required int peerUserId,
    String? peerName,
    String? peerAvatar,
  }) async {
    await ensureAuth();

    if (peerUserId == _userId) {
      throw Exception('Cannot create a chat with yourself');
    }

    final cached = findCachedDirectChatWithPeer(peerUserId);
    if (cached != null) return cached;

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/chats'),
            headers: {
              'Authorization': _authHeader,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'type': 'direct',
              // Backend pairs authenticated user with this peer id
              'participantIds': [peerUserId],
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 201 || response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final chatData = body is Map<String, dynamic>
            ? (body['data'] is Map
                ? Map<String, dynamic>.from(body['data'] as Map)
                : body)
            : body;
        final thread = BackendChatThread.fromJson(
          Map<String, dynamic>.from(chatData as Map),
        );
        _mergeThreadIntoCache(thread);
        final userId = _userId;
        if (userId != null) {
          unawaited(BackendMessagingCache.saveThreads(userId, _cachedThreads));
        }
        return thread;
      } else {
        print('[BackendChatService] Create chat error: ${response.statusCode}');
        print('[BackendChatService] Response body: ${response.body}');
        throw Exception('Failed to create chat: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('[BackendChatService] Error ensuring chat: $e');
      rethrow;
    }
  }

  /// Mark messages as read
  static Future<void> markRead({
    required String chatId,
    required List<String> messageIds,
  }) async {
    await ensureAuth();
    clearThreadUnread(chatId);

    try {
      await http
          .patch(
            Uri.parse('$_baseUrl/chats/$chatId/messages/bulk/read'),
            headers: {
              'Authorization': _authHeader,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'messageIds': messageIds}),
          )
          .timeout(const Duration(seconds: 10));
      clearThreadUnread(chatId);
    } catch (e) {
      print('[BackendChatService] Error marking as read: $e');
      rethrow;
    }
  }

  /// Send test message to all users (TEST ONLY, debug builds)
  static Future<int> sendTestMessageToAllUsers({
    required String testMessage,
  }) async {
    if (!kDebugMode) {
      throw StateError('sendTestMessageToAllUsers is only available in debug builds');
    }

    await ensureAuth();
    final myId = _userId!;

    try {
      // Fetch all users from /vero/users (users controller is at root, not /api/v1)
      final usersUrl = ApiConfig.endpoint('/users');
      final usersResponse = await http.get(
        usersUrl,
        headers: {'Authorization': _authHeader},
      ).timeout(_lookupTimeout);

      if (usersResponse.statusCode != 200) {
        throw Exception('Failed to fetch users: ${usersResponse.statusCode}');
      }

      final usersJson = jsonDecode(usersResponse.body);
      final users = usersJson['data'] as List? ?? [];
      int successCount = 0;

      for (final userJson in users) {
        final userId = userJson['id'] as int?;
        if (userId == null || userId == myId) continue;

        try {
          // Create or get chat with user
          final chat = await ensureChat(peerUserId: userId);

          // Send message
          await sendMessage(
            chatId: chat.id,
            content: testMessage,
            type: 'text',
          );

          successCount++;
          print('[BackendChatService] Sent test message to user $userId');
        } catch (e) {
          print('[BackendChatService] Failed to send to user $userId: $e');
          // Continue with next user on failure
        }
      }

      print(
          '[BackendChatService] Test messages sent to $successCount users');
      return successCount;
    } catch (e) {
      print('[BackendChatService] Error sending test messages: $e');
      rethrow;
    }
  }
}

/// Thrown when `/users/me` rejects the Firebase token (real auth failure).
class _ChatAuthUnauthorized implements Exception {
  const _ChatAuthUnauthorized();

  @override
  String toString() => 'Unauthorized';
}
