import 'dart:async';
import 'package:vero360_app/GernalServices/chat_service.dart';
import 'package:vero360_app/GernalServices/hybrid_chat_service.dart';
import 'package:vero360_app/GernalServices/websocket_manager.dart';

/// Wrapper that automatically uses HybridChatService when WebSocket is available
class ChatServiceWrapper {
  static HybridChatService? _hybrid;

  /// Get hybrid service (uses WebSocket if available, falls back to Firebase)
  static HybridChatService getService() {
    _hybrid ??= HybridChatService(
      webSocketService: WebSocketManager.instance,
    );
    return _hybrid!;
  }

  /// Send message (auto WebSocket or Firebase)
  static Future<void> sendMessage({
    required String myAppId,
    required String peerAppId,
    required String text,
  }) async {
    return getService().sendMessage(
      myAppId: myAppId,
      peerAppId: peerAppId,
      text: text,
    );
  }

  /// Mark messages as read
  static Future<void> markMessagesAsRead({
    required String chatId,
    required List<String> messageIds,
    required String myAppId,
  }) async {
    return getService().markMessagesAsRead(
      chatId: chatId,
      messageIds: messageIds,
      myAppId: myAppId,
    );
  }

  /// Delete message
  static Future<void> deleteMessage({
    required String threadId,
    required String messageId,
    required String myAppId,
  }) async {
    return getService().deleteMessage(
      threadId: threadId,
      messageId: messageId,
      myAppId: myAppId,
    );
  }

  /// Edit message
  static Future<void> editMessage({
    required String threadId,
    required String messageId,
    required String newContent,
    required String myAppId,
  }) async {
    return getService().editMessage(
      threadId: threadId,
      messageId: messageId,
      myAppId: myAppId,
      newText: '',
    );
  }

  /// Get messages stream (Firebase fallback)
  static Stream<List<ChatMessage>> messagesStream(String threadId) {
    return ChatService.messagesStream(threadId);
  }

  /// Get threads stream (Firebase fallback)
  static Stream<List<ChatThread>> threadsStream(String userId) {
    return ChatService.threadsStream(userId);
  }

  /// Get current user ID
  static Future<String> myAppUserId() {
    return ChatService.myAppUserId();
  }

  /// Ensure thread exists
  static Future<void> ensureThread({
    required String myAppId,
    required String peerAppId,
    String? peerName,
    String? peerAvatar,
  }) {
    return ChatService.ensureThread(
      myAppId: myAppId,
      peerAppId: peerAppId,
      peerName: peerName,
      peerAvatar: peerAvatar,
    );
  }

  /// Mark thread as read
  static Future<void> markThreadRead({
    required String myAppId,
    required String peerAppId,
  }) {
    return ChatService.markThreadRead(
      myAppId: myAppId,
      peerAppId: peerAppId,
    );
  }

  /// Ensure Firebase auth
  static Future<void> ensureFirebaseAuth() {
    return ChatService.ensureFirebaseAuth();
  }

  /// Get thread ID
  static String threadIdForApp(String myAppId, String peerAppId) {
    return ChatService.threadIdForApp(myAppId, peerAppId);
  }
}
