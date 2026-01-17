/// PHASE 4 OFFLINE MESSAGING IMPLEMENTATION USAGE GUIDE
///
/// This file demonstrates how to use the offline messaging system implemented in Phase 4
///
/// ===========================================================================
/// STEP 1: INITIALIZATION (in main.dart or app initialization)
/// ===========================================================================
///
/// ```dart
/// import 'package:vero360_app/services/messaging_initialization_service.dart';
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   
///   // Initialize offline messaging system
///   await MessagingInitializationService.initialize();
///   
///   runApp(const MyApp());
/// }
/// ```
///
/// ===========================================================================
/// STEP 2: SETUP WEBSOCKET INTEGRATION (when WebSocket connects)
/// ===========================================================================
///
/// ```dart
/// // In your messaging provider initialization
/// Future<void> initializeMessaging({
///   required String wsUrl,
///   required String token,
///   required String userId,
/// }) async {
///   final webSocketService = WebSocketMessagingService(
///     wsUrl: wsUrl,
///     token: token,
///     userId: userId,
///   );
///   
///   await webSocketService.connect();
///   
///   // Link WebSocket to offline sync service
///   await MessagingInitializationService.setWebSocketService(webSocketService);
/// }
/// ```
///
/// ===========================================================================
/// STEP 3: USE IN WIDGETS (Riverpod providers)
/// ===========================================================================
///
/// ```dart
/// // Get offline messaging operations
/// final operations = ref.watch(offlineMessagingOperationsProvider);
///
/// // Watch sync status
/// final syncStatus = ref.watch(syncStatusProvider);
/// final queue = ref.watch(queueStatusProvider);
///
/// // Get local messages for a chat
/// final localMessages = ref.watch(localChatMessagesProvider('chatId123'));
///
/// // Get local chat threads
/// final threads = ref.watch(localChatThreadsProvider);
///
/// // Get database stats
/// final stats = ref.watch(databaseStatsProvider);
/// ```
///
/// ===========================================================================
/// STEP 4: SEND MESSAGES WITH OFFLINE SUPPORT
/// ===========================================================================
///
/// ```dart
/// // Create a message
/// final message = Message(
///   id: messageId,
///   chatId: chatId,
///   senderId: userId,
///   recipientId: recipientId,
///   content: 'Hello!',
///   createdAt: DateTime.now(),
///   status: MessageStatus.sent,
/// );
///
/// // Save locally and queue for sync if offline
/// if (isOnline) {
///   // Send via WebSocket
///   await webSocketService.sendMessage(
///     chatId: chatId,
///     recipientId: recipientId,
///     content: 'Hello!',
///   );
/// } else {
///   // Queue for sync when online
///   await operations.queueMessageSend(message);
/// }
///
/// // Always save to local database
/// await operations.saveChatMessages([message]);
/// ```
///
/// ===========================================================================
/// STEP 5: HANDLE OTHER MESSAGE OPERATIONS
/// ===========================================================================
///
/// ```dart
/// // Edit message
/// await operations.queueMessageEdit(
///   messageId: messageId,
///   chatId: chatId,
///   newContent: 'Updated message',
/// );
///
/// // Delete message
/// await operations.queueMessageDelete(
///   messageId: messageId,
///   chatId: chatId,
/// );
///
/// // Mark messages as read
/// await operations.queueReadReceipt(
///   chatId: chatId,
///   messageIds: messageIds,
/// );
/// ```
///
/// ===========================================================================
/// STEP 6: DISPLAY SYNC STATUS IN UI
/// ===========================================================================
///
/// ```dart
/// consumer.watch(syncStatusProvider).whenData((status) {
///   if (status.isSyncing) {
///     return Text('Syncing...');
///   } else if (status.hasPending) {
///     return Text('Pending: ${status.pendingCount} messages');
///   } else {
///     return Text('Last synced: ${status.lastSyncTime}');
///   }
/// })
/// ```
///
/// ===========================================================================
/// STEP 7: LOAD MESSAGES FROM LOCAL STORAGE
/// ===========================================================================
///
/// ```dart
/// // Get messages from local storage first
/// final localMessages = ref.watch(localChatMessagesProvider(chatId));
///
/// // Then fetch from server/Firebase and update local
/// chatMessages.addAll(messagesFromServer);
/// await operations.saveChatMessages(chatMessages);
/// ```
///
/// ===========================================================================
/// STEP 8: CLEANUP (on app exit)
/// ===========================================================================
///
/// ```dart
/// // Call in your app's dispose
/// @override
/// void dispose() {
///   MessagingInitializationService.dispose();
///   super.dispose();
/// }
/// ```
///
/// ===========================================================================
/// KEY COMPONENTS
/// ===========================================================================
///
/// 1. **LocalMessageDatabase**
///    - Stores messages and threads in Hive boxes
///    - Methods: saveMessage, getMessagesForChat, saveChatThread, etc.
///
/// 2. **OfflineMessageQueue**
///    - Queues operations when offline
///    - Auto-syncs when online
///    - Retry logic with exponential backoff
///
/// 3. **MessageSyncService**
///    - Orchestrates sync operations
///    - Handles reconnection
///    - Provides sync status stream
///
/// 4. **MessagingInitializationService**
///    - Single point initialization
///    - Manages lifecycle of all services
///    - Provides static access to services
///
/// 5. **Riverpod Providers** (in offline_messaging_provider.dart)
///    - offlineMessageQueueProvider
///    - messageSyncServiceProvider
///    - syncStatusProvider
///    - queueStatusProvider
///    - localChatMessagesProvider
///    - localChatThreadsProvider
///    - databaseStatsProvider
///    - offlineMessagingOperationsProvider
///
/// ===========================================================================
/// FLOW DIAGRAMS
/// ===========================================================================
///
/// ### Message Send (Offline)
/// User sends message
///   ↓
/// Check if online
///   ↓
/// If offline:
///   ↓
/// Queue message with OfflineMessageQueue
///   ↓
/// Save to LocalMessageDatabase
///   ↓
/// Show "Pending" status in UI
///   ↓
/// When online:
///   ↓
/// Auto-sync via MessageSyncService
///   ↓
/// WebSocket sends to server
///   ↓
/// Update status to "Delivered"
///
/// ### Message Read Receipt (Offline)
/// User views messages
///   ↓
/// Queue read receipt
///   ↓
/// Check WebSocket status
///   ↓
/// If offline: stored in queue
/// If online: sent immediately
///   ↓
/// When online (if was offline):
///   ↓
/// Auto-sync read receipts
///
/// ### Chat Thread Load
/// App opens
///   ↓
/// Load threads from LocalMessageDatabase (instant)
///   ↓
/// Show in UI immediately
///   ↓
/// Fetch from Firebase/Server in background
///   ↓
/// Update local database
///   ↓
/// UI auto-refreshes via Riverpod
///
/// ===========================================================================
/// ERROR HANDLING
/// ===========================================================================
///
/// - Operations throw exceptions on critical errors
/// - Queue has retry logic (max 3 retries with exponential backoff)
/// - Failed operations stay in queue for manual retry
/// - Use try-catch in Riverpod providers
///
/// ===========================================================================
/// DATABASE MANAGEMENT
/// ===========================================================================
///
/// Get stats:
/// ```dart
/// final stats = MessagingInitializationService.getDatabaseStats();
/// // Returns: {'messages': 150, 'threads': 10, 'pendingSyncs': 2}
/// ```
///
/// Clear all data:
/// ```dart
/// await MessagingInitializationService.clearAllData();
/// ```
///
/// ===========================================================================
/// TESTING OFFLINE FUNCTIONALITY
/// ===========================================================================
///
/// 1. Turn off WiFi/Mobile data
/// 2. Send a message
/// 3. Check that it appears in queueStatusProvider
/// 4. Turn internet back on
/// 5. Verify message syncs automatically
///
/// ===========================================================================
