import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:vero360_app/GernalServices/local_message_database.dart';
import 'package:vero360_app/GernalServices/offline_message_queue.dart';
import 'package:vero360_app/GernalServices/message_sync_service.dart';
import 'package:vero360_app/GernalServices/websocket_messaging_service.dart';

/// Initialize all messaging services
/// Call this in main() or app initialization
class MessagingInitializationService {
  static void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }
  static LocalMessageDatabase? _database;
  static OfflineMessageQueue? _queue;
  static MessageSyncService? _syncService;

  static LocalMessageDatabase? get database => _database;
  static OfflineMessageQueue? get queue => _queue;
  static MessageSyncService? get syncService => _syncService;

  /// Initialize all messaging services
  static Future<void> initialize() async {
    try {
      _log('[MessagingInitializationService] Starting initialization');

      // 1. Initialize Hive
      await Hive.initFlutter();
      _log('[MessagingInitializationService] Hive initialized');

      // 2. Initialize local message database
      _database = LocalMessageDatabase();
      await _database!.initialize();
      _log('[MessagingInitializationService] LocalMessageDatabase initialized');

      // 3. Initialize offline message queue
      _queue = OfflineMessageQueue(database: _database!);
      await _queue!.initialize();
      _log('[MessagingInitializationService] OfflineMessageQueue initialized');

      // 4. Initialize message sync service (WebSocket set later)
      _syncService = MessageSyncService(
        database: _database!,
        queue: _queue!,
        webSocket: null,
      );
      await _syncService!.initialize();
      _log('[MessagingInitializationService] MessageSyncService initialized');

      // 5. Start periodic sync
      _queue!.startPeriodicSync();
      _log('[MessagingInitializationService] Periodic sync started');

      _log('[MessagingInitializationService] All services initialized successfully');
    } catch (e) {
      _log('[MessagingInitializationService] Initialization failed: $e');
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
        _log('[MessagingInitializationService] WebSocket reconnected, syncing...');
        await _syncService!.syncPendingOperations();
      });

      _log('[MessagingInitializationService] WebSocket service configured');
    } catch (e) {
      _log('[MessagingInitializationService] Error setting WebSocket: $e');
      rethrow;
    }
  }

  /// Dispose all services
  static Future<void> dispose() async {
    try {
      _log('[MessagingInitializationService] Disposing services');

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

      _log('[MessagingInitializationService] All services disposed');
    } catch (e) {
      _log('[MessagingInitializationService] Error disposing: $e');
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
      _log('[MessagingInitializationService] Error forcing sync: $e');
      rethrow;
    }
  }

  /// Clear all local data
  static Future<void> clearAllData() async {
    try {
      _log('[MessagingInitializationService] Clearing all local data');
      await _database?.clearAll();
      await _queue?.clearQueue();
      _log('[MessagingInitializationService] All data cleared');
    } catch (e) {
      _log('[MessagingInitializationService] Error clearing data: $e');
      rethrow;
    }
  }
}
