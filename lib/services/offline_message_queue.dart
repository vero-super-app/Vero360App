import 'dart:async';
import 'package:vero360_app/models/messaging_models.dart';
import 'package:vero360_app/services/local_message_database.dart';

/// Queue item for offline message operations
class QueuedMessageOperation {
  final String id;
  final String type; // 'send', 'edit', 'delete', 'read'
  final Message? message;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final int retryCount;

  QueuedMessageOperation({
    required this.id,
    required this.type,
    this.message,
    required this.metadata,
    required this.createdAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'message': message?.toJson(),
      'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
    };
  }

  factory QueuedMessageOperation.fromJson(Map<String, dynamic> json) {
    return QueuedMessageOperation(
      id: json['id'],
      type: json['type'],
      message: json['message'] != null ? Message.fromJson(json['message']) : null,
      metadata: json['metadata'] ?? {},
      createdAt: DateTime.parse(json['createdAt']),
      retryCount: json['retryCount'] ?? 0,
    );
  }
}

/// Callback function for sync operations
typedef SyncCallback = Future<bool> Function(QueuedMessageOperation operation);

/// Offline message queue manager
class OfflineMessageQueue {
  final LocalMessageDatabase _database;
  final StreamController<List<QueuedMessageOperation>> _queueController =
      StreamController<List<QueuedMessageOperation>>.broadcast();

  final Map<String, QueuedMessageOperation> _queue = {};
  SyncCallback? _syncCallback;
  bool _isProcessing = false;
  static const Duration _syncCheckInterval = Duration(seconds: 5);
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  Timer? _syncTimer;

  OfflineMessageQueue({required LocalMessageDatabase database}) : _database = database;

  /// Stream of queue changes
  Stream<List<QueuedMessageOperation>> get queueStream => _queueController.stream;

  /// Set sync callback to handle actual syncing
  void setSyncCallback(SyncCallback callback) {
    _syncCallback = callback;
  }

  /// Initialize queue from persistent storage
  Future<void> initialize() async {
    try {
      final pendingSyncs = _database.getPendingSyncs();
      for (final item in pendingSyncs) {
        final operation = QueuedMessageOperation.fromJson(item);
        _queue[operation.id] = operation;
      }
      print('[OfflineMessageQueue] Initialized with ${_queue.length} pending operations');
      _notifyQueueChanged();
    } catch (e) {
      print('[OfflineMessageQueue] Error initializing: $e');
      rethrow;
    }
  }

  /// Queue a message send operation
  Future<void> queueMessageSend({
    required Message message,
  }) async {
    final operation = QueuedMessageOperation(
      id: 'send_${message.id}',
      type: 'send',
      message: message,
      metadata: {
        'chatId': message.chatId,
        'recipientId': message.recipientId,
      },
      createdAt: DateTime.now(),
    );

    _queue[operation.id] = operation;
    await _database.queueMessageForSync(operation.id, operation.toJson());
    _notifyQueueChanged();
  }

  /// Queue a message edit operation
  Future<void> queueMessageEdit({
    required String messageId,
    required String chatId,
    required String newContent,
  }) async {
    final operation = QueuedMessageOperation(
      id: 'edit_$messageId',
      type: 'edit',
      metadata: {
        'messageId': messageId,
        'chatId': chatId,
        'newContent': newContent,
      },
      createdAt: DateTime.now(),
    );

    _queue[operation.id] = operation;
    await _database.queueMessageForSync(operation.id, operation.toJson());
    _notifyQueueChanged();
  }

  /// Queue a message delete operation
  Future<void> queueMessageDelete({
    required String messageId,
    required String chatId,
  }) async {
    final operation = QueuedMessageOperation(
      id: 'delete_$messageId',
      type: 'delete',
      metadata: {
        'messageId': messageId,
        'chatId': chatId,
      },
      createdAt: DateTime.now(),
    );

    _queue[operation.id] = operation;
    await _database.queueMessageForSync(operation.id, operation.toJson());
    _notifyQueueChanged();
  }

  /// Queue a read receipt operation
  Future<void> queueReadReceipt({
    required String chatId,
    required List<String> messageIds,
  }) async {
    final operation = QueuedMessageOperation(
      id: 'read_${chatId}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'read',
      metadata: {
        'chatId': chatId,
        'messageIds': messageIds,
      },
      createdAt: DateTime.now(),
    );

    _queue[operation.id] = operation;
    await _database.queueMessageForSync(operation.id, operation.toJson());
    _notifyQueueChanged();
  }

  /// Get current queue
  List<QueuedMessageOperation> getQueue() {
    return _queue.values.toList();
  }

  /// Get queue size
  int get queueSize => _queue.length;

  /// Start periodic sync check
  void startPeriodicSync() {
    if (_syncTimer != null) return;

    _syncTimer = Timer.periodic(_syncCheckInterval, (_) {
      if (!_isProcessing) {
        processPendingQueue();
      }
    });

    print('[OfflineMessageQueue] Started periodic sync');
  }

  /// Stop periodic sync
  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    print('[OfflineMessageQueue] Stopped periodic sync');
  }

  /// Process all pending queue items
  Future<void> processPendingQueue() async {
    if (_isProcessing || _queue.isEmpty || _syncCallback == null) {
      return;
    }

    _isProcessing = true;
    try {
      print('[OfflineMessageQueue] Processing ${_queue.length} pending operations');

      final operationsToProcess = _queue.values.toList();

      for (final operation in operationsToProcess) {
        await _processOperation(operation);
      }

      print('[OfflineMessageQueue] Finished processing queue');
    } catch (e) {
      print('[OfflineMessageQueue] Error processing queue: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Process a single operation
  Future<void> _processOperation(QueuedMessageOperation operation) async {
    try {
      print('[OfflineMessageQueue] Processing ${operation.type} operation: ${operation.id}');

      bool success = false;
      int attempts = 0;

      while (attempts < _maxRetries && !success) {
        try {
          success = await _syncCallback!(operation);

          if (success) {
            print('[OfflineMessageQueue] Successfully synced ${operation.id}');
            _queue.remove(operation.id);
            await _database.removePendingSync(operation.id);
            _notifyQueueChanged();
            break;
          }
        } catch (e) {
          attempts++;
          print('[OfflineMessageQueue] Attempt $attempts failed for ${operation.id}: $e');

          if (attempts < _maxRetries) {
            await Future.delayed(_retryDelay);
          }
        }
      }

      if (!success && attempts >= _maxRetries) {
        print('[OfflineMessageQueue] Max retries reached for ${operation.id}');
      }
    } catch (e) {
      print('[OfflineMessageQueue] Error processing operation: $e');
    }
  }

  /// Force sync a specific operation
  Future<bool> syncOperation(String operationId) async {
    final operation = _queue[operationId];
    if (operation == null || _syncCallback == null) {
      return false;
    }

    try {
      final success = await _syncCallback!(operation);
      if (success) {
        _queue.remove(operationId);
        await _database.removePendingSync(operationId);
        _notifyQueueChanged();
      }
      return success;
    } catch (e) {
      print('[OfflineMessageQueue] Error syncing operation: $e');
      return false;
    }
  }

  /// Remove operation from queue
  Future<void> removeOperation(String operationId) async {
    try {
      _queue.remove(operationId);
      await _database.removePendingSync(operationId);
      _notifyQueueChanged();
    } catch (e) {
      print('[OfflineMessageQueue] Error removing operation: $e');
    }
  }

  /// Clear all queue items
  Future<void> clearQueue() async {
    try {
      _queue.clear();
      await _database.clearPendingSyncs();
      _notifyQueueChanged();
      print('[OfflineMessageQueue] Queue cleared');
    } catch (e) {
      print('[OfflineMessageQueue] Error clearing queue: $e');
    }
  }

  /// Notify listeners of queue changes
  void _notifyQueueChanged() {
    _queueController.add(getQueue());
  }

  /// Dispose
  Future<void> dispose() async {
    stopPeriodicSync();
    await _queueController.close();
  }
}
