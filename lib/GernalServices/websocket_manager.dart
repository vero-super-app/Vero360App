import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/GernalServices/websocket_messaging_service.dart';

/// @deprecated Use [BackendMessagingSocket] instead.
@Deprecated('Use BackendMessagingSocket instead.')
class WebSocketManager {
  static void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

  static WebSocketMessagingService? get instance =>
      BackendMessagingSocket.webSocketService;

  static Future<void> initialize() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
      await BackendChatService.ensureAuth();
      await BackendMessagingSocket.connect();
      _log('[WebSocketManager] Delegated to BackendMessagingSocket');
    } catch (e) {
      _log('[WebSocketManager] Init failed: $e');
    }
  }

  static Future<void> ensureConnected() async {
    if (BackendMessagingSocket.isConnected) return;
    await initialize();
  }

  static Future<void> disconnect() => BackendMessagingSocket.disconnect();

  static Future<void> dispose() => BackendMessagingSocket.disconnect();
}
