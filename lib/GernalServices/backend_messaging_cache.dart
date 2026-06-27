import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';

/// Disk cache for backend chat threads and messages (per user).
class BackendMessagingCache {
  static const _boxName = 'backend_messaging_v1';
  static Box<String>? _box;
  static bool _ready = false;
  static final Set<String> _warmedUrls = <String>{};

  static Future<void> initialize() async {
    if (_ready) return;
    try {
      await Hive.initFlutter();
      _box = await Hive.openBox<String>(_boxName);
      _ready = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackendMessagingCache] init failed: $e');
      }
    }
  }

  static String _threadsKey(int userId) => 'u$userId:threads';

  static String _messagesKey(int userId, String chatId) =>
      'u$userId:msgs:$chatId';

  static String _chatClearedKey(int userId, String chatId) =>
      'u$userId:cleared:$chatId';

  static DateTime? peekChatClearedAt(int? userId, String chatId) {
    if (!_ready || userId == null || _box == null) return null;
    final raw = _box!.get(_chatClearedKey(userId, chatId));
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Hide messages at or before [clearedAt] (with a small clock-skew buffer).
  static List<BackendChatMessage> filterAfterClear(
    int? userId,
    String chatId,
    List<BackendChatMessage> messages,
  ) {
    final clearedAt = peekChatClearedAt(userId, chatId);
    if (clearedAt == null) return messages;
    final cutoff = clearedAt.subtract(const Duration(seconds: 2));
    return messages.where((m) => m.createdAt.isAfter(cutoff)).toList();
  }

  static Future<void> markChatCleared(int userId, String chatId) async {
    await initialize();
    if (_box == null) return;
    try {
      await _box!.put(
        _chatClearedKey(userId, chatId),
        DateTime.now().toUtc().toIso8601String(),
      );
      await deleteMessagesForChat(userId, chatId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackendMessagingCache] markChatCleared: $e');
      }
    }
  }

  static Future<void> unmarkChatCleared(int userId, String chatId) async {
    await initialize();
    if (_box == null) return;
    try {
      await _box!.delete(_chatClearedKey(userId, chatId));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackendMessagingCache] unmarkChatCleared: $e');
      }
    }
  }

  static List<BackendChatThread> peekThreads(int? userId) {
    if (!_ready || userId == null || _box == null) return [];
    final raw = _box!.get(_threadsKey(userId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map(
            (e) => BackendChatThread.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static List<BackendChatMessage> peekMessages(int? userId, String chatId) {
    if (!_ready || userId == null || _box == null) return [];
    final raw = _box!.get(_messagesKey(userId, chatId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final messages = list
          .map(
            (e) => BackendChatMessage.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return filterAfterClear(userId, chatId, messages);
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveThreads(
    int userId,
    List<BackendChatThread> threads,
  ) async {
    await initialize();
    if (_box == null) return;
    try {
      await _box!.put(
        _threadsKey(userId),
        jsonEncode(threads.map((t) => t.toJson()).toList()),
      );
      unawaited(_warmImageUrls(_imageUrlsFromThreads(threads)));
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendMessagingCache] saveThreads: $e');
    }
  }

  static Future<void> saveMessages(
    int userId,
    String chatId,
    List<BackendChatMessage> messages,
  ) async {
    await initialize();
    if (_box == null) return;
    try {
      final sorted = [...messages]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _box!.put(
        _messagesKey(userId, chatId),
        jsonEncode(sorted.map((m) => m.toJson()).toList()),
      );
      unawaited(_warmImageUrls(_imageUrlsFromMessages(sorted)));
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendMessagingCache] saveMessages: $e');
    }
  }

  static Future<void> upsertMessage(
    int userId,
    BackendChatMessage message,
  ) async {
    final existing = peekMessages(userId, message.chatId);
    final idx = existing.indexWhere(
      (m) =>
          m.id == message.id ||
          (message.clientMessageId != null &&
              m.clientMessageId == message.clientMessageId),
    );
    if (idx >= 0) {
      existing[idx] = message;
    } else {
      existing.add(message);
    }
    await saveMessages(userId, message.chatId, existing);
  }

  static Future<void> removeMessageFromCache(
    int userId,
    String chatId,
    String messageId,
  ) async {
    final existing = peekMessages(userId, chatId);
    if (existing.isEmpty) return;
    final updated = existing.where((m) => m.id != messageId).toList();
    await saveMessages(userId, chatId, updated);
  }

  static Future<void> deleteMessagesForChat(int userId, String chatId) async {
    await initialize();
    if (_box == null) return;
    try {
      await _box!.delete(_messagesKey(userId, chatId));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackendMessagingCache] deleteMessagesForChat: $e');
      }
    }
  }

  static Future<void> clearUser(int userId) async {
    await initialize();
    if (_box == null) return;
    final prefix = 'u$userId:';
    final keys = _box!.keys
        .where((k) => k.toString().startsWith(prefix))
        .toList();
    await _box!.deleteAll(keys);
  }

  static Iterable<String> _imageUrlsFromThreads(
    List<BackendChatThread> threads,
  ) sync* {
    for (final thread in threads) {
      for (final p in thread.participants) {
        final url = p.profilePicture?.trim();
        if (url != null && url.isNotEmpty) yield url;
      }
      final product = thread.lastProductTag;
      final productImage = product?.image?.trim();
      if (productImage != null && productImage.isNotEmpty) yield productImage;
    }
  }

  static Iterable<String> _imageUrlsFromMessages(
    List<BackendChatMessage> messages,
  ) sync* {
    for (final msg in messages) {
      for (final att in msg.attachments ?? const []) {
        final url = att['url']?.toString().trim();
        if (url != null && url.isNotEmpty) yield url;
        final thumb = att['thumbnailUrl']?.toString().trim();
        if (thumb != null && thumb.isNotEmpty) yield thumb;
      }
      for (final tag in msg.tags ?? const []) {
        if (tag['tagType'] == 'product') {
          final img = tag['tagImage']?.toString().trim();
          if (img != null && img.isNotEmpty) yield img;
        }
      }
    }
  }

  static Future<void> _warmImageUrls(Iterable<String> urls) async {
    final manager = DefaultCacheManager();
    for (final raw in urls) {
      final url = raw.trim();
      if (url.isEmpty || !url.contains('://')) continue;
      if (_warmedUrls.contains(url)) continue;
      _warmedUrls.add(url);
      try {
        await manager.downloadFile(url);
      } catch (_) {
        _warmedUrls.remove(url);
      }
    }
  }
}
