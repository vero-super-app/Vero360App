import 'dart:async';
import 'package:vero360_app/GeneralModels/messaging_models.dart';
import 'package:vero360_app/GernalServices/local_message_database.dart';
import 'package:vero360_app/GernalServices/offline_message_queue.dart';
import 'package:vero360_app/GernalServices/websocket_messaging_service.dart';

/// Message sync service to handle offline/online sync
class MessageSyncService {
  final WebSocketMessagingService? _webSocket;
  final LocalMessageDatabase _database;
  final OfflineMessageQueue _queue;

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();

  bool _isSyncing = false;
  DateTime? _lastSyncTime;

  MessageSyncService({
    required LocalMessageDatabase database,
    required OfflineMessageQueue queue,
    required WebSocketMessagingService? webSocket,
  })  : _database = database,
        _queue = queue,
        _webSocket = webSocket;

  /// Stream of sync status updates
  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// Current sync status
  SyncStatus get currentStatus => SyncStatus(
        isSyncing: _isSyncing,
        lastSyncTime: _lastSyncTime,
        pendingCount: _queue.queueSize,
      );

  /// Initialize sync service
  Future<void> initialize() async {
    try {
      // Set sync callback on queue
      _queue.setSyncCallback(_executeSyncOperation);

      // Setup WebSocket reconnection listener
      if (_webSocket != null) {
        _webSocket!.connectionStatusStream.listen((status) {
          if (status == 'connected') {
            _onWebSocketConnected();
          }
        });
      }

      print('[MessageSyncService] Initialized');
    } catch (e) {
      print('[MessageSyncService] Error initializing: $e');
      rethrow;
    }
  }

  /// Called when WebSocket connects
  Future<void> _onWebSocketConnected() async {
    print('[MessageSyncService] WebSocket connected, syncing pending operations');
    await syncPendingOperations();
  }

  /// Sync all pending operations
  Future<void> syncPendingOperations() async {
    if (_isSyncing) {
      print('[MessageSyncService] Already syncing, skipping');
      return;
    }

    _isSyncing = true;
    _statusController.add(currentStatus);

    try {
      final pendingOps = _queue.getQueue();
      if (pendingOps.isEmpty) {
        print('[MessageSyncService] No pending operations to sync');
        _isSyncing = false;
        _statusController.add(currentStatus);
        return;
      }

      print('[MessageSyncService] Syncing ${pendingOps.length} pending operations');

      // Process queue (it will handle retries internally)
      await _queue.processPendingQueue();

      _lastSyncTime = DateTime.now();
      print('[MessageSyncService] Sync completed');
    } catch (e) {
      print('[MessageSyncService] Error syncing: $e');
    } finally {
      _isSyncing = false;
      _statusController.add(currentStatus);
    }
  }

  /// Execute sync operation (callback for queue)
  Future<bool> _executeSyncOperation(QueuedMessageOperation operation) async {
    try {
      switch (operation.type) {
        case 'send':
          return await _syncSendMessage(operation);
        case 'edit':
          return await _syncEditMessage(operation);
        case 'delete':
          return await _syncDeleteMessage(operation);
        case 'read':
          return await _syncReadReceipt(operation);
        default:
          print('[MessageSyncService] Unknown operation type: ${operation.type}');
          return false;
      }
    } catch (e) {
      print('[MessageSyncService] Error executing sync operation: $e');
      return false;
    }
  }

  /// Sync send message
  Future<bool> _syncSendMessage(QueuedMessageOperation operation) async {
    try {
      if (_webSocket == null || !_webSocket!.isConnected) {
        print('[MessageSyncService] WebSocket not connected for send sync');
        return false;
      }

      final message = operation.message;
      if (message == null) return false;

      await _webSocket!.sendMessage(
        chatId: message.chatId,
        recipientId: message.recipientId,
        content: message.content,
      );

      // Save as synced
      final syncedMsg = Message(
        id: message.id,
        chatId: message.chatId,
        senderId: message.senderId,
        recipientId: message.recipientId,
        content: message.content,
        createdAt: message.createdAt,
        editedAt: message.editedAt,
        status: MessageStatus.delivered,
        isEdited: message.isEdited,
        isDeleted: message.isDeleted,
        attachmentUrls: message.attachmentUrls,
      );
      await _database.saveMessage(syncedMsg);

      print('[MessageSyncService] Successfully synced send for ${message.id}');
      return true;
    } catch (e) {
      print('[MessageSyncService] Error syncing send: $e');
      return false;
    }
  }

  /// Sync edit message
  Future<bool> _syncEditMessage(QueuedMessageOperation operation) async {
    try {
      if (_webSocket == null || !_webSocket!.isConnected) {
        print('[MessageSyncService] WebSocket not connected for edit sync');
        return false;
      }

      final messageId = operation.metadata['messageId'] as String;
      final chatId = operation.metadata['chatId'] as String;
      final newContent = operation.metadata['newContent'] as String;

      await _webSocket!.editMessage(
        chatId: chatId,
        messageId: messageId,
        newContent: newContent,
      );

      print('[MessageSyncService] Successfully synced edit for $messageId');
      return true;
    } catch (e) {
      print('[MessageSyncService] Error syncing edit: $e');
      return false;
    }
  }

  /// Sync delete message
  Future<bool> _syncDeleteMessage(QueuedMessageOperation operation) async {
    try {
      if (_webSocket == null || !_webSocket!.isConnected) {
        print('[MessageSyncService] WebSocket not connected for delete sync');
        return false;
      }

      final messageId = operation.metadata['messageId'] as String;
      final chatId = operation.metadata['chatId'] as String;

      await _webSocket!.deleteMessage(
        chatId: chatId,
        messageId: messageId,
      );

      print('[MessageSyncService] Successfully synced delete for $messageId');
      return true;
    } catch (e) {
      print('[MessageSyncService] Error syncing delete: $e');
      return false;
    }
  }

  /// Sync read receipt
  Future<bool> _syncReadReceipt(QueuedMessageOperation operation) async {
    try {
      if (_webSocket == null || !_webSocket!.isConnected) {
        print('[MessageSyncService] WebSocket not connected for read sync');
        return false;
      }

      final chatId = operation.metadata['chatId'] as String;
      final messageIds = List<String>.from(operation.metadata['messageIds'] as List);

      await _webSocket!.markMessagesAsRead(
        chatId: chatId,
        messageIds: messageIds,
      );

      print('[MessageSyncService] Successfully synced read for $chatId');
      return true;
    } catch (e) {
      print('[MessageSyncService] Error syncing read: $e');
      return false;
    }
  }

  /// Load messages for chat from local storage
  List<Message> getLocalChatMessages(String chatId) {
    return _database.getMessagesForChat(chatId);
  }

  /// Save messages to local storage
  Future<void> saveChatMessages(List<Message> messages) async {
    await _database.saveMessages(messages);
  }

  /// Load chat threads from local storage
  List<ChatThread> getLocalChatThreads() {
    return _database.getAllChatThreads();
  }

  /// Save chat threads to local storage
  Future<void> saveChatThreads(List<ChatThread> threads) async {
    await _database.saveChatThreads(threads);
  }

  /// Get database statistics
  Map<String, int> getDatabaseStats() {
    return _database.getStats();
  }

  /// Force resync all messages in a chat
  Future<void> resyncChat(String chatId) async {
    try {
      print('[MessageSyncService] Resyncing chat: $chatId');
      await _database.clearChatMessages(chatId);
      // Messages will be reloaded from Firebase fallback
    } catch (e) {
      print('[MessageSyncService] Error resyncing chat: $e');
      rethrow;
    }
  }

  /// Dispose
  Future<void> dispose() async {
    await _statusController.close();
  }
}

/// Sync status model
class SyncStatus {
  final bool isSyncing;
  final DateTime? lastSyncTime;
  final int pendingCount;

  SyncStatus({
    required this.isSyncing,
    this.lastSyncTime,
    this.pendingCount = 0,
  });

  bool get hasPending => pendingCount > 0;

  String get summary => isSyncing
      ? 'Syncing...'
      : hasPending
          ? 'Pending: $pendingCount'
          : lastSyncTime != null
              ? 'Last synced: ${lastSyncTime!.toLocal()}'
              : 'Not synced';
}
