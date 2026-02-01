import 'package:hive_flutter/hive_flutter.dart';
import 'package:vero360_app/GernalServices/local_message_database.dart';
import 'package:vero360_app/GernalServices/offline_message_queue.dart';
import 'package:vero360_app/GernalServices/message_sync_service.dart';
import 'package:vero360_app/GernalServices/websocket_messaging_service.dart';

/// Initialize all messaging services
/// Call this in main() or app initialization
class MessagingInitializationService {
  static LocalMessageDatabase? _database;
  static OfflineMessageQueue? _queue;
  static MessageSyncService? _syncService;

  static LocalMessageDatabase? get database => _database;
  static OfflineMessageQueue? get queue => _queue;
  static MessageSyncService? get syncService => _syncService;

  /// Initialize all messaging services
  static Future<void> initialize() async {
    try {
      print('[MessagingInitializationService] Starting initialization');

      // 1. Initialize Hive
      await Hive.initFlutter();
      print('[MessagingInitializationService] Hive initialized');

      // 2. Initialize local message database
      _database = LocalMessageDatabase();
      await _database!.initialize();
      print('[MessagingInitializationService] LocalMessageDatabase initialized');

      // 3. Initialize offline message queue
      _queue = OfflineMessageQueue(database: _database!);
      await _queue!.initialize();
      print('[MessagingInitializationService] OfflineMessageQueue initialized');

      // 4. Initialize message sync service (WebSocket set later)
      _syncService = MessageSyncService(
        database: _database!,
        queue: _queue!,
        webSocket: null,
      );
      await _syncService!.initialize();
      print('[MessagingInitializationService] MessageSyncService initialized');

      // 5. Start periodic sync
      _queue!.startPeriodicSync();
      print('[MessagingInitializationService] Periodic sync started');

      print('[MessagingInitializationService] All services initialized successfully');
    } catch (e) {
      print('[MessagingInitializationService] Initialization failed: $e');
      rethrow;
    }
  }

  /// Set WebSocket service for sync
  static Future<void> setWebSocketService(WebSocketMessagingService wsService) async {
    try {
      if (_syncService == null) {
        throw Exception('MessageSyncService not initialized. Call initialize() first');
      }

      // Setup reconnection callback
      wsService.setOnReconnectCallback(() async {
        print('[MessagingInitializationService] WebSocket reconnected, syncing...');
        await _syncService!.syncPendingOperations();
      });

      print('[MessagingInitializationService] WebSocket service configured');
    } catch (e) {
      print('[MessagingInitializationService] Error setting WebSocket: $e');
      rethrow;
    }
  }

  /// Dispose all services
  static Future<void> dispose() async {
    try {
      print('[MessagingInitializationService] Disposing services');

      // Stop periodic sync
      _queue?.stopPeriodicSync();

      // Dispose sync service
      await _syncService?.dispose();

      // Dispose queue
      await _queue?.dispose();

      // Close database
      await _database?.close();

      // Close Hive
      await Hive.close();

      _database = null;
      _queue = null;
      _syncService = null;

      print('[MessagingInitializationService] All services disposed');
    } catch (e) {
      print('[MessagingInitializationService] Error disposing: $e');
      rethrow;
    }
  }

  /// Get sync status
  static SyncStatus? getSyncStatus() => _syncService?.currentStatus;

  /// Get database stats
  static Map<String, int>? getDatabaseStats() => _database?.getStats();

  /// Force sync
  static Future<void> forceSync() async {
    try {
      await _syncService?.syncPendingOperations();
    } catch (e) {
      print('[MessagingInitializationService] Error forcing sync: $e');
      rethrow;
    }
  }

  /// Clear all local data
  static Future<void> clearAllData() async {
    try {
      print('[MessagingInitializationService] Clearing all local data');
      await _database?.clearAll();
      await _queue?.clearQueue();
      print('[MessagingInitializationService] All data cleared');
    } catch (e) {
      print('[MessagingInitializationService] Error clearing data: $e');
      rethrow;
    }
  }
}
