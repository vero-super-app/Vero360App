import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';

/// Legacy Hive/Firebase offline messaging bootstrap.
///
/// Messaging now uses [BackendChatService] + [BackendMessagingSocket].
@Deprecated(
  'Use BackendMessagingSocket.connect() after sign-in instead.',
)
class MessagingInitializationService {
  static void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

  /// Connects the backend WebSocket when a user session exists.
  static Future<void> initialize() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
      await BackendMessagingSocket.connect();
      _log('[MessagingInitializationService] Backend messaging socket ready');
    } catch (e) {
      _log('[MessagingInitializationService] Init skipped: $e');
    }
  }

  @Deprecated('Backend socket is configured in connect()')
  static Future<void> setWebSocketService(dynamic wsService) async {}

  static Future<void> dispose() async {
    await BackendMessagingSocket.disconnect();
  }

  static Future<void> forceSync() async {}

  static Future<void> clearAllData() async {}
}
