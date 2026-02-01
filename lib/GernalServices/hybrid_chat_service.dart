import 'dart:async';

import 'package:vero360_app/GernalServices/chat_service.dart';
import 'package:vero360_app/GernalServices/websocket_messaging_service.dart';
import 'package:vero360_app/GeneralModels/messaging_models.dart' as messaging_models;

/// Hybrid chat service that uses WebSocket when available, falls back to Firebase
class HybridChatService {
  final WebSocketMessagingService? _webSocket;
  final ChatService _firebase = ChatService();

  bool get _wsConnected => _webSocket?.isConnected ?? false;

  HybridChatService({WebSocketMessagingService? webSocketService})
      : _webSocket = webSocketService;

  /// Send a message with automatic fallback
  Future<void> sendMessage({
    required String myAppId,
    required String peerAppId,
    required String text,
  }) async {
    if (_wsConnected) {
      try {
        final threadId = ChatService.threadIdForApp(myAppId, peerAppId);
        await _webSocket!.sendMessage(
          chatId: threadId,
          recipientId: peerAppId,
          content: text,
        );
        return;
      } catch (e) {
        print('[HybridChatService] WebSocket send failed, falling back to Firebase: $e');
      }
    }

    // Fallback to Firebase
    await ChatService.sendMessage(
      myAppId: myAppId,
      peerAppId: peerAppId,
      text: text,
    );
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead({
    required String chatId,
    required List<String> messageIds,
    required String myAppId,
  }) async {
    if (_wsConnected) {
      try {
        await _webSocket!.markMessagesAsRead(
          chatId: chatId,
          messageIds: messageIds,
        );
        return;
      } catch (e) {
        print('[HybridChatService] WebSocket read marker failed: $e');
      }
    }

    // Firebase fallback (update via thread)
    final threadId = chatId;
    final parts = threadId.split('_');
    if (parts.length == 2) {
      final otherId = parts[0] == myAppId ? parts[1] : parts[0];
      await ChatService.markThreadRead(
        myAppId: myAppId,
        peerAppId: otherId,
      );
    }
  }

  /// Delete a message
  Future<void> deleteMessage({
    required String threadId,
    required String messageId,
    required String myAppId,
  }) async {
    if (_wsConnected) {
      try {
        await _webSocket!.deleteMessage(
          chatId: threadId,
          messageId: messageId,
        );
        return;
      } catch (e) {
        print('[HybridChatService] WebSocket delete failed, using Firebase: $e');
      }
    }

    // Fallback to Firebase
    await ChatService.deleteMessage(
      threadId: threadId,
      messageId: messageId,
      myAppId: myAppId,
    );
  }

  /// Edit a message
  Future<void> editMessage({
    required String threadId,
    required String messageId,
    required String myAppId,
    required String newText,
  }) async {
    if (_wsConnected) {
      try {
        await _webSocket!.editMessage(
          chatId: threadId,
          messageId: messageId,
          newContent: newText,
        );
        return;
      } catch (e) {
        print('[HybridChatService] WebSocket edit failed, using Firebase: $e');
      }
    }

    // Fallback to Firebase
    await ChatService.editMessage(
      threadId: threadId,
      messageId: messageId,
      myAppId: myAppId,
      newText: newText,
    );
  }

  /// Send typing indicator
  Future<void> sendTypingIndicator({
    required String chatId,
    bool isTyping = true,
  }) async {
    if (!_wsConnected) return;

    try {
      if (isTyping) {
        await _webSocket!.startTyping(chatId);
      } else {
        await _webSocket!.stopTyping(chatId);
      }
    } catch (e) {
      print('[HybridChatService] Failed to send typing indicator: $e');
    }
  }

  /// Update user online status
  Future<void> updateUserStatus(String status) async {
    if (!_wsConnected) return;

    try {
      await _webSocket!.updateUserStatus(status);
    } catch (e) {
      print('[HybridChatService] Failed to update user status: $e');
    }
  }

  /// Join a chat room
  Future<void> joinChat(String chatId) async {
    if (!_wsConnected) return;

    try {
      await _webSocket!.joinChat(chatId);
    } catch (e) {
      print('[HybridChatService] Failed to join chat: $e');
    }
  }

  /// Leave a chat room
  Future<void> leaveChat(String chatId) async {
    if (!_wsConnected) return;

    try {
      await _webSocket!.leaveChat(chatId);
    } catch (e) {
      print('[HybridChatService] Failed to leave chat: $e');
    }
  }

  /// Get messages stream (Firebase + WebSocket fallback)
  Stream<List<messaging_models.Message>> getMessagesStream(String threadId) {
    return ChatService.messagesStream(threadId).map((chatMessages) {
      return chatMessages.map((cm) {
        return messaging_models.Message(
          id: cm.id,
          chatId: threadId,
          senderId: cm.fromAppId,
          recipientId: cm.toAppId,
          content: cm.text,
          createdAt: cm.ts,
          isEdited: cm.isEdited,
          isDeleted: cm.isDeleted,
          status: cm.isDeleted
               ? messaging_models.MessageStatus.failed
               : cm.isEdited
                   ? messaging_models.MessageStatus.read
                   : messaging_models.MessageStatus.delivered,
        );
      }).toList();
    });
  }

  /// Get threads stream (Firebase)
  Stream<List<messaging_models.ChatThread>> getThreadsStream(String myAppId) {
    return ChatService.threadsStream(myAppId).map((firebaseThreads) {
      return firebaseThreads.map((ft) {
        return messaging_models.ChatThread(
          id: ft.id,
          participantIds: ft.participantsAppIds,
          participants: ft.participants,
          lastMessageContent: ft.lastText,
          updatedAt: ft.updatedAt,
          lastSenderId: ft.lastSenderAppId,
          lastMessageId: ft.lastMessageId,
          unreadCounts: (ft.unread as Map<String, dynamic>?)
                  ?.map((key, value) => MapEntry(key, value as int)) ??
              {},
        );
      }).toList();
    });
  }

  /// Ensure thread exists
  Future<void> ensureThread({
    required String myAppId,
    required String peerAppId,
    String? myName,
    String? myAvatar,
    String? peerName,
    String? peerAvatar,
  }) async {
    await ChatService.ensureThread(
      myAppId: myAppId,
      peerAppId: peerAppId,
      myName: myName,
      myAvatar: myAvatar,
      peerName: peerName,
      peerAvatar: peerAvatar,
    );
  }

  /// Get WebSocket service (if connected)
  WebSocketMessagingService? get webSocketService => _webSocket;

  /// Check if WebSocket is available
  bool get isWebSocketAvailable => _wsConnected;
}
