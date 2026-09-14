import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';

/// Disk cache for backend chat threads and messages (per user).
class BackendMessagingCache {
  static const _boxName = 'backend_messaging_v1';
  static Box<String>? _box;
  static bool _ready = false;
  static final Set<String> _warmedUrls = <String>{};
  /// Instant open without waiting for Nest user id / Hive.
  static final Map<String, List<BackendChatMessage>> _memMessagesByChat = {};

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

  /// Survives logout — not under the [clearUser] `u$userId:` prefix.
  static String _deletedThreadsKey(int userId) => 'deleted_threads_$userId';

  static List<BackendChatMessage> _decodeMessages(String raw) {
    if (raw.isEmpty) return [];
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
      return messages;
    } catch (_) {
      return [];
    }
  }

  static List<BackendChatMessage> _readDiskMessagesForChat(
    String chatId, {
    int? preferUserId,
  }) {
    if (!_ready || _box == null) return [];
    final id = chatId.trim();
    if (id.isEmpty) return [];

    if (preferUserId != null && preferUserId > 0) {
      final raw = _box!.get(_messagesKey(preferUserId, id));
      if (raw != null && raw.isNotEmpty) {
        final decoded = _decodeMessages(raw);
        if (decoded.isNotEmpty) return decoded;
      }
    }

    // Nest user id can change across sessions — find any cached copy for this chat.
    final suffix = ':msgs:$id';
    List<BackendChatMessage> best = const [];
    for (final key in _box!.keys) {
      final ks = key.toString();
      if (!ks.endsWith(suffix)) continue;
      final raw = _box!.get(key);
      if (raw == null || raw.isEmpty) continue;
      final decoded = _decodeMessages(raw);
      if (decoded.length > best.length) best = decoded;
    }
    return best;
  }

  static void _putMem(String chatId, List<BackendChatMessage> messages) {
    final id = chatId.trim();
    if (id.isEmpty) return;
    final sorted = [...messages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _memMessagesByChat[id] = sorted;
  }

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

  static Set<String> peekDeletedThreadIds(int? userId) {
    if (!_ready || userId == null || _box == null) return {};
    final raw = _box!.get(_deletedThreadsKey(userId));
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => e.toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> unmarkThreadDeleted(int userId, String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    await initialize();
    if (_box == null) return;
    try {
      final existing = peekDeletedThreadIds(userId);
      if (!existing.remove(id)) return;
      if (existing.isEmpty) {
        await _box!.delete(_deletedThreadsKey(userId));
      } else {
        await _box!.put(
          _deletedThreadsKey(userId),
          jsonEncode(existing.toList()),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackendMessagingCache] unmarkThreadDeleted: $e');
      }
    }
  }

  static Future<void> clearDeletedThreadIds(int userId) async {
    await initialize();
    if (_box == null) return;
    try {
      await _box!.delete(_deletedThreadsKey(userId));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackendMessagingCache] clearDeletedThreadIds: $e');
      }
    }
  }

  static Future<void> markThreadDeleted(int userId, String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    await initialize();
    if (_box == null) return;
    try {
      final existing = peekDeletedThreadIds(userId);
      if (existing.contains(id)) return;
      existing.add(id);
      await _box!.put(
        _deletedThreadsKey(userId),
        jsonEncode(existing.toList()),
      );
      await deleteMessagesForChat(userId, id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackendMessagingCache] markThreadDeleted: $e');
      }
    }
  }

  static Future<void> mergeDeletedThreadIds(
    int userId,
    Iterable<String> chatIds,
  ) async {
    await initialize();
    if (_box == null) return;
    final merged = peekDeletedThreadIds(userId);
    var changed = false;
    for (final raw in chatIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      if (merged.add(id)) changed = true;
    }
    if (!changed) return;
    try {
      await _box!.put(
        _deletedThreadsKey(userId),
        jsonEncode(merged.toList()),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackendMessagingCache] mergeDeletedThreadIds: $e');
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
    final id = chatId.trim();
    if (id.isEmpty) return [];

    final mem = _memMessagesByChat[id];
    if (mem != null && mem.isNotEmpty) {
      return filterAfterClear(userId, id, List<BackendChatMessage>.from(mem));
    }

    if (!_ready || _box == null) return [];
    final disk = _readDiskMessagesForChat(id, preferUserId: userId);
    if (disk.isEmpty) return [];
    _putMem(id, disk);
    return filterAfterClear(userId, id, List<BackendChatMessage>.from(disk));
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
    final id = chatId.trim();
    if (id.isEmpty) return;
    final sorted = [...messages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _putMem(id, sorted);

    await initialize();
    if (_box == null || userId <= 0) return;
    try {
      await _box!.put(
        _messagesKey(userId, id),
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
    final id = chatId.trim();
    _memMessagesByChat.remove(id);
    await initialize();
    if (_box == null) return;
    try {
      await _box!.delete(_messagesKey(userId, id));
      // Also drop any leftover copies keyed under a previous Nest user id.
      final suffix = ':msgs:$id';
      final stale = _box!.keys
          .where((k) => k.toString().endsWith(suffix))
          .toList();
      if (stale.isNotEmpty) await _box!.deleteAll(stale);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackendMessagingCache] deleteMessagesForChat: $e');
      }
    }
  }

  /// Clear threads that no longer belong to [userId] after an account switch.
  /// Keeps deleted-thread markers so same-user re-login still hides deletes.
  static Future<void> clearThreadsForUser(int userId) async {
    await initialize();
    if (_box == null) return;
    try {
      await _box!.delete(_threadsKey(userId));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackendMessagingCache] clearThreadsForUser: $e');
      }
    }
  }

  static Future<void> clearUser(int userId) async {
    await initialize();
    // Drop in-memory copies for this account's chats.
    final prefix = 'u$userId:msgs:';
    if (_box != null) {
      for (final key in _box!.keys) {
        final ks = key.toString();
        if (ks.startsWith(prefix)) {
          final chatId = ks.substring(prefix.length);
          _memMessagesByChat.remove(chatId);
        }
      }
    }
    if (_box == null) return;
    final userPrefix = 'u$userId:';
    final keys = _box!.keys
        .where((k) => k.toString().startsWith(userPrefix))
        .toList();
    await _box!.deleteAll(keys);
  }

  /// Drop cached threads/messages for every account. Keeps deleted-thread
  /// markers so the same user can log back in without resurrecting hidden chats.
  static Future<void> clearSessionThreads() async {
    await initialize();
    _memMessagesByChat.clear();
    if (_box == null) return;
    try {
      final keys = _box!.keys
          .where((k) => !k.toString().startsWith('deleted_threads_'))
          .toList();
      await _box!.deleteAll(keys);
      _warmedUrls.clear();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackendMessagingCache] clearSessionThreads: $e');
      }
    }
  }

  /// Full wipe including deleted-thread markers. Use on account deletion.
  static Future<void> clearAll() async {
    await initialize();
    _memMessagesByChat.clear();
    _warmedUrls.clear();
    if (_box == null) return;
    try {
      await _box!.clear();
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendMessagingCache] clearAll: $e');
    }
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
