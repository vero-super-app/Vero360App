import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/services/websocket_messaging_service.dart';
import 'package:vero360_app/services/messaging_initialization_service.dart';
import 'package:vero360_app/services/chat_service.dart';

/// Global WebSocket manager - handles initialization and lifecycle
class WebSocketManager {
  static WebSocketMessagingService? _instance;

  static WebSocketMessagingService? get instance => _instance;

  /// Initialize WebSocket connection
  static Future<WebSocketMessagingService?> initialize() async {
    try {
      // Get current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print(
            '[WebSocketManager] No authenticated user, skipping WebSocket init');
        return null;
      }

      // Get app user ID from chat service
      final appUserId = await ChatService.myAppUserId();

      if (appUserId.isEmpty) {
        print('[WebSocketManager] No app user ID, skipping WebSocket init');
        return null;
      }

      // Get auth token
      final idToken = await user.getIdToken();

      // Configure WebSocket URL (change to your backend)
      const wsUrl = 'ws://localhost:3000'; // ← Change to your backend

      print('[WebSocketManager] Initializing WebSocket at $wsUrl');

      _instance = WebSocketMessagingService(
        wsUrl: wsUrl,
        token: idToken!,
        userId: appUserId,
      );

      // Connect
      await _instance!.connect();
      print('[WebSocketManager] WebSocket connected ✅');

      // Link to sync service
      await MessagingInitializationService.setWebSocketService(_instance!);

      return _instance;
    } catch (e) {
      print('[WebSocketManager] Failed to initialize: $e');
      return null;
    }
  }

  /// Reconnect if disconnected
  static Future<void> ensureConnected() async {
    if (_instance != null && _instance!.isConnected) {
      return;
    }
    await initialize();
  }

  /// Disconnect WebSocket
  static Future<void> disconnect() async {
    try {
      await _instance?.disconnect();
      print('[WebSocketManager] WebSocket disconnected');
    } catch (e) {
      print('[WebSocketManager] Error disconnecting: $e');
    }
  }

  /// Dispose
  static Future<void> dispose() async {
    await disconnect();
    _instance = null;
  }
}
