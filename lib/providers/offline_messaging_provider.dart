import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/services/local_message_database.dart';
import 'package:vero360_app/services/offline_message_queue.dart';
import 'package:vero360_app/services/message_sync_service.dart';
import 'package:vero360_app/models/messaging_models.dart';

/// Local message database provider
final localMessageDatabaseProvider = Provider<LocalMessageDatabase>((ref) {
  return LocalMessageDatabase();
});

/// Offline message queue provider
final offlineMessageQueueProvider = FutureProvider<OfflineMessageQueue>((ref) async {
  final database = ref.watch(localMessageDatabaseProvider);
  final queue = OfflineMessageQueue(database: database);
  await queue.initialize();
  return queue;
});

/// Message sync service provider
final messageSyncServiceProvider = FutureProvider<MessageSyncService>((ref) async {
  final database = ref.watch(localMessageDatabaseProvider);
  final queue = await ref.watch(offlineMessageQueueProvider.future);
  
  // Note: WebSocket service is not available here to avoid circular dependency
  // It should be set up in the main app initialization
  final service = MessageSyncService(
    database: database,
    queue: queue,
    webSocket: null,
  );
  
  await service.initialize();
  return service;
});

/// Sync status stream provider
final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final syncService = await ref.watch(messageSyncServiceProvider.future);
  yield* syncService.statusStream;
});

/// Queue status stream provider
final queueStatusProvider = StreamProvider<List<QueuedMessageOperation>>((ref) async* {
  final queue = await ref.watch(offlineMessageQueueProvider.future);
  yield* queue.queueStream;
});

/// Local messages for a chat provider
final localChatMessagesProvider =
    Provider.family<List<Message>, String>((ref, chatId) {
  final syncService = ref.watch(messageSyncServiceProvider);
  
  return syncService.when(
    data: (service) => service.getLocalChatMessages(chatId),
    loading: () => [],
    error: (err, stack) {
      print('[localChatMessagesProvider] Error: $err');
      return [];
    },
  );
});

/// Local chat threads provider
final localChatThreadsProvider = Provider<List<ChatThread>>((ref) {
  final syncService = ref.watch(messageSyncServiceProvider);
  
  return syncService.when(
    data: (service) => service.getLocalChatThreads(),
    loading: () => [],
    error: (err, stack) {
      print('[localChatThreadsProvider] Error: $err');
      return [];
    },
  );
});

/// Database stats provider
final databaseStatsProvider = Provider<Map<String, int>>((ref) {
  final syncService = ref.watch(messageSyncServiceProvider);
  
  return syncService.when(
    data: (service) => service.getDatabaseStats(),
    loading: () => {'messages': 0, 'threads': 0, 'pendingSyncs': 0},
    error: (err, stack) => {'messages': 0, 'threads': 0, 'pendingSyncs': 0},
  );
});

/// Provider for offline messaging operations
final offlineMessagingOperationsProvider = Provider((ref) {
  return OfflineMessagingOperations(ref: ref);
});

/// Service class for offline messaging operations
class OfflineMessagingOperations {
  final Ref ref;

  OfflineMessagingOperations({required this.ref});

  /// Queue a message send
  Future<void> queueMessageSend(Message message) async {
    try {
      final queue = await ref.read(offlineMessageQueueProvider.future);
      await queue.queueMessageSend(message: message);
    } catch (e) {
      print('[OfflineMessagingOperations] Error queuing message send: $e');
      rethrow;
    }
  }

  /// Queue a message edit
  Future<void> queueMessageEdit({
    required String messageId,
    required String chatId,
    required String newContent,
  }) async {
    try {
      final queue = await ref.read(offlineMessageQueueProvider.future);
      await queue.queueMessageEdit(
        messageId: messageId,
        chatId: chatId,
        newContent: newContent,
      );
    } catch (e) {
      print('[OfflineMessagingOperations] Error queuing message edit: $e');
      rethrow;
    }
  }

  /// Queue a message delete
  Future<void> queueMessageDelete({
    required String messageId,
    required String chatId,
  }) async {
    try {
      final queue = await ref.read(offlineMessageQueueProvider.future);
      await queue.queueMessageDelete(
        messageId: messageId,
        chatId: chatId,
      );
    } catch (e) {
      print('[OfflineMessagingOperations] Error queuing message delete: $e');
      rethrow;
    }
  }

  /// Queue a read receipt
  Future<void> queueReadReceipt({
    required String chatId,
    required List<String> messageIds,
  }) async {
    try {
      final queue = await ref.read(offlineMessageQueueProvider.future);
      await queue.queueReadReceipt(chatId: chatId, messageIds: messageIds);
    } catch (e) {
      print('[OfflineMessagingOperations] Error queuing read receipt: $e');
      rethrow;
    }
  }

  /// Sync pending operations
  Future<void> syncPendingOperations() async {
    try {
      final syncService = await ref.read(messageSyncServiceProvider.future);
      await syncService.syncPendingOperations();
    } catch (e) {
      print('[OfflineMessagingOperations] Error syncing pending: $e');
      rethrow;
    }
  }

  /// Start periodic sync
  Future<void> startPeriodicSync() async {
    try {
      final queue = await ref.read(offlineMessageQueueProvider.future);
      queue.startPeriodicSync();
    } catch (e) {
      print('[OfflineMessagingOperations] Error starting periodic sync: $e');
      rethrow;
    }
  }

  /// Stop periodic sync
  Future<void> stopPeriodicSync() async {
    try {
      final queue = await ref.read(offlineMessageQueueProvider.future);
      queue.stopPeriodicSync();
    } catch (e) {
      print('[OfflineMessagingOperations] Error stopping periodic sync: $e');
      rethrow;
    }
  }

  /// Save chat messages locally
  Future<void> saveChatMessages(List<Message> messages) async {
    try {
      final syncService = await ref.read(messageSyncServiceProvider.future);
      await syncService.saveChatMessages(messages);
    } catch (e) {
      print('[OfflineMessagingOperations] Error saving chat messages: $e');
      rethrow;
    }
  }

  /// Save chat threads locally
  Future<void> saveChatThreads(List<ChatThread> threads) async {
    try {
      final syncService = await ref.read(messageSyncServiceProvider.future);
      await syncService.saveChatThreads(threads);
    } catch (e) {
      print('[OfflineMessagingOperations] Error saving chat threads: $e');
      rethrow;
    }
  }
}
