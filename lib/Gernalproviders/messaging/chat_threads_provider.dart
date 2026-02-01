import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/messaging_models.dart'
    as messaging_models;
import 'package:vero360_app/GernalServices/chat_service.dart';

/// Stream of chat threads
final chatThreadsStreamProvider =
    StreamProvider.autoDispose<List<messaging_models.ChatThread>>((ref) async* {
  try {
    final userId = await ChatService.myAppUserId();

    yield* ChatService.threadsStream(userId)
        .map((firebaseThreads) {
          return firebaseThreads.map((ft) {
            return messaging_models.ChatThread(
              id: ft.id,
              participantIds: ft.participantsAppIds,
              participants: ft.participants,
              lastMessageContent: ft.lastText,
              updatedAt: ft.updatedAt,
              lastSenderId: ft.lastSenderAppId,
              lastMessageId: ft.lastMessageId,
              unreadCounts: (ft.unread as Map<String, dynamic>?)
                      ?.map((key, value) => MapEntry(key, value as int)) ??
                  {},
            );
          }).toList();
        });
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
final totalUnreadCountProvider =
    Provider.family<int, String>((ref, userId) {
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
        final otherParticipant = thread.participants.values.first;
        final name =
            (otherParticipant as Map<String, dynamic>?)?['name']?.toString() ??
                '';
        final lastMsg =
            thread.lastMessageContent.toLowerCase();

        return name.toLowerCase().contains(lowerQuery) ||
            lastMsg.contains(lowerQuery);
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Get unread threads
final unreadThreadsProvider =
    FutureProvider<List<messaging_models.ChatThread>>((ref) async {
  final userId = await ChatService.myAppUserId();
  final threads = await ref.watch(chatThreadsStreamProvider.future);

  return threads.where((t) => t.getUnreadCount(userId) > 0).toList();
});
