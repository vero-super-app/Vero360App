import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/messaging_models.dart'
    as messaging_models;
import 'package:vero360_app/GernalServices/backend_chat_service.dart';

/// Backend API chat threads (replaces legacy Firebase [ChatService] stream).
final chatThreadsStreamProvider =
    StreamProvider.autoDispose<List<messaging_models.ChatThread>>((ref) async* {
  try {
    final myId = await BackendChatService.getUserId();
    final myIdStr = myId.toString();

    await for (final threads in BackendChatService.watchThreads()) {
      yield threads.map((t) {
        final other = t.participants.where((p) => p.id != myId).toList();
        final peer = other.isNotEmpty ? other.first : null;

        final participants = <String, dynamic>{};
        for (final p in t.participants) {
          participants[p.id.toString()] = {
            'name': p.name,
            'avatar': p.profilePicture ?? '',
            'email': p.email,
          };
        }

        return messaging_models.ChatThread(
          id: t.id,
          participantIds: t.participants.map((p) => p.id.toString()).toList(),
          participants: participants,
          lastMessageContent: t.lastMessagePreview ?? '',
          updatedAt: t.updatedAt,
          lastSenderId: peer?.id.toString(),
          unreadCounts: {myIdStr: t.unreadCount},
        );
      }).toList();
    }
  } catch (e) {
    print('[ChatThreadsProvider] Error: $e');
    yield [];
  }
});

/// Get a specific thread
final chatThreadProvider = FutureProvider.family<messaging_models.ChatThread?,
    String>((ref, threadId) async {
  final threads = await ref.watch(chatThreadsStreamProvider.future);
  return threads.firstWhere(
    (t) => t.id == threadId,
    orElse: () => messaging_models.ChatThread(
      id: threadId,
      participantIds: [],
      participants: {},
      lastMessageContent: '',
      updatedAt: DateTime.now(),
      unreadCounts: {},
    ),
  );
});

/// Count unread messages across all threads
final totalUnreadCountProvider = Provider.family<int, String>((ref, userId) {
  final threadsAsync = ref.watch(chatThreadsStreamProvider);

  return threadsAsync.when(
    data: (threads) {
      int total = 0;
      for (final thread in threads) {
        total += thread.getUnreadCount(userId);
      }
      return total;
    },
    loading: () => 0,
    error: (_, __) => 0,
  );
});

/// Filter threads by search query
final searchThreadsProvider =
    Provider.family<List<messaging_models.ChatThread>, String>((ref, query) {
  final threadsAsync = ref.watch(chatThreadsStreamProvider);

  return threadsAsync.when(
    data: (threads) {
      if (query.isEmpty) return threads;

      final lowerQuery = query.toLowerCase();
      return threads.where((thread) {
        for (final entry in thread.participants.entries) {
          final name = '${entry.value['name'] ?? ''}'.toLowerCase();
          if (name.contains(lowerQuery)) return true;
        }
        return thread.lastMessageContent.toLowerCase().contains(lowerQuery);
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});
