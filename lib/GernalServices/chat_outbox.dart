import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';

/// One unsent chat item (text / photo / voice) kept on device until it lands.
class ChatOutboxEntry {
  final String clientMessageId;
  final String chatId;
  final int senderId;
  final String type;
  final String? content;
  final String status; // pending | failed
  final DateTime createdAt;
  final String? localVoicePath;
  final int? voiceDurationMs;
  final String? localImagePath;
  final String? imageMime;
  final String? imageFilename;
  final List<Map<String, dynamic>>? tags;
  final Map<String, dynamic>? metadata;

  const ChatOutboxEntry({
    required this.clientMessageId,
    required this.chatId,
    required this.senderId,
    required this.type,
    this.content,
    required this.status,
    required this.createdAt,
    this.localVoicePath,
    this.voiceDurationMs,
    this.localImagePath,
    this.imageMime,
    this.imageFilename,
    this.tags,
    this.metadata,
  });

  bool get isAudio => type == 'audio';
  bool get isImage => type == 'image';

  ChatOutboxEntry copyWith({String? status}) {
    return ChatOutboxEntry(
      clientMessageId: clientMessageId,
      chatId: chatId,
      senderId: senderId,
      type: type,
      content: content,
      status: status ?? this.status,
      createdAt: createdAt,
      localVoicePath: localVoicePath,
      voiceDurationMs: voiceDurationMs,
      localImagePath: localImagePath,
      imageMime: imageMime,
      imageFilename: imageFilename,
      tags: tags,
      metadata: metadata,
    );
  }

  BackendChatMessage toMessage() {
    return BackendChatMessage(
      id: clientMessageId,
      chatId: chatId,
      senderId: senderId,
      content: content,
      type: type,
      status: status,
      createdAt: createdAt,
      tags: tags,
      clientMessageId: clientMessageId,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'clientMessageId': clientMessageId,
        'chatId': chatId,
        'senderId': senderId,
        'type': type,
        'content': content,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'localVoicePath': localVoicePath,
        'voiceDurationMs': voiceDurationMs,
        'localImagePath': localImagePath,
        'imageMime': imageMime,
        'imageFilename': imageFilename,
        'tags': tags,
        'metadata': metadata,
      };

  factory ChatOutboxEntry.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>>? tags;
    final rawTags = json['tags'];
    if (rawTags is List) {
      tags = rawTags
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    Map<String, dynamic>? metadata;
    final rawMeta = json['metadata'];
    if (rawMeta is Map) {
      metadata = Map<String, dynamic>.from(rawMeta);
    }
    return ChatOutboxEntry(
      clientMessageId: json['clientMessageId']?.toString() ?? '',
      chatId: json['chatId']?.toString() ?? '',
      senderId: json['senderId'] is int
          ? json['senderId'] as int
          : int.tryParse(json['senderId']?.toString() ?? '') ?? 0,
      type: json['type']?.toString() ?? 'text',
      content: json['content']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      localVoicePath: json['localVoicePath']?.toString(),
      voiceDurationMs: json['voiceDurationMs'] is int
          ? json['voiceDurationMs'] as int
          : int.tryParse(json['voiceDurationMs']?.toString() ?? ''),
      localImagePath: json['localImagePath']?.toString(),
      imageMime: json['imageMime']?.toString(),
      imageFilename: json['imageFilename']?.toString(),
      tags: tags,
      metadata: metadata,
    );
  }
}

/// WhatsApp-style outbox: unsent messages survive leaving the chat / going offline.
class ChatOutbox {
  ChatOutbox._();

  static const _boxName = 'chat_outbox_v1';
  static Box<String>? _box;
  static bool _ready = false;

  static Future<void> initialize() async {
    if (_ready) return;
    try {
      await Hive.initFlutter();
      _box = await Hive.openBox<String>(_boxName);
      _ready = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatOutbox] init failed: $e');
    }
  }

  static String _key(int userId, String clientId) => 'u$userId:o:$clientId';

  static Future<Directory> mediaDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/chat_outbox');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> persistVoiceFile({
    required String sourcePath,
    required String clientMessageId,
  }) async {
    final dir = await mediaDir();
    final dest = '${dir.path}/$clientMessageId.m4a';
    if (sourcePath != dest) {
      await File(sourcePath).copy(dest);
    }
    return dest;
  }

  static Future<String> persistImageBytes({
    required List<int> bytes,
    required String clientMessageId,
    String ext = 'jpg',
  }) async {
    final dir = await mediaDir();
    final dest = '${dir.path}/$clientMessageId.$ext';
    await File(dest).writeAsBytes(bytes, flush: true);
    return dest;
  }

  static Future<void> upsert(ChatOutboxEntry entry) async {
    await initialize();
    if (_box == null || entry.clientMessageId.isEmpty) return;
    try {
      await _box!.put(
        _key(entry.senderId, entry.clientMessageId),
        jsonEncode(entry.toJson()),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatOutbox] upsert: $e');
    }
  }

  static Future<void> markStatus({
    required int userId,
    required String clientMessageId,
    required String status,
  }) async {
    final existing = await get(userId, clientMessageId);
    if (existing == null) return;
    await upsert(existing.copyWith(status: status));
  }

  static Future<ChatOutboxEntry?> get(int userId, String clientMessageId) async {
    await initialize();
    if (_box == null) return null;
    final raw = _box!.get(_key(userId, clientMessageId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return ChatOutboxEntry.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<ChatOutboxEntry>> forChat({
    required int userId,
    required String chatId,
  }) async {
    await initialize();
    if (_box == null || chatId.isEmpty) return const [];
    final prefix = 'u$userId:o:';
    final out = <ChatOutboxEntry>[];
    for (final k in _box!.keys) {
      if (!k.toString().startsWith(prefix)) continue;
      final raw = _box!.get(k);
      if (raw == null || raw.isEmpty) continue;
      try {
        final e = ChatOutboxEntry.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (e.chatId == chatId) out.add(e);
      } catch (_) {}
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  static Future<void> remove(int userId, String clientMessageId) async {
    await initialize();
    if (_box == null) return;
    try {
      await _box!.delete(_key(userId, clientMessageId));
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatOutbox] remove: $e');
    }
  }

  /// Drop outbox rows + durable media (logout / account delete).
  static Future<void> clearAll() async {
    await initialize();
    try {
      await _box?.clear();
    } catch (_) {}
    try {
      final dir = await mediaDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
