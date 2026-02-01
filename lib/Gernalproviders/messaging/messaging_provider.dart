import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:vero360_app/GeneralModels/messaging_models.dart'
    as messaging_models;
import 'package:vero360_app/GernalServices/websocket_messaging_service.dart';
import 'package:vero360_app/GernalServices/chat_service.dart';

// =============== WEBSOCKET SERVICE PROVIDER ===============

/// WebSocket messaging service instance
final webSocketMessagingServiceProvider =
    Provider.family<WebSocketMessagingService?, String>((ref, userId) {
  // This would be initialized elsewhere when needed
  return null;
});

/// Socket connection state
final socketConnectionStateProvider =
    StateProvider<messaging_models.SocketState>((ref) {
  return messaging_models.SocketState();
});

// =============== MESSAGING STATE PROVIDERS ===============

/// Active chats user is currently in
final activeChatsProvider = StateProvider<Set<String>>((ref) => {});

/// Typing users per chat: {chatId: {userId1, userId2, ...}}
final typingUsersProvider =
    StateProvider<Map<String, Set<String>>>((ref) => {});

/// Online status per user: {userId: isOnline}
final onlineUsersProvider = StateProvider<Map<String, bool>>((ref) => {});

/// Message status per message: {messageId: MessageStatus}
final messageStatusProvider = StateProvider<Map<String, messaging_models.MessageStatus>>(
    (ref) => {});

// =============== STREAM PROVIDERS ===============

/// Stream of incoming messages
final messageStreamProvider =
    StreamProvider.autoDispose<messaging_models.Message>((ref) {
  // WebSocket message stream would be connected here
  throw UnimplementedError('WebSocket not initialized');
});

/// Stream of typing indicators
final typingStreamProvider =
    StreamProvider.autoDispose<messaging_models.TypingIndicator>((ref) {
  // WebSocket typing stream
  throw UnimplementedError('WebSocket not initialized');
});

/// Stream of user status updates
final userStatusStreamProvider =
    StreamProvider.autoDispose<messaging_models.UserStatus>((ref) {
  // WebSocket user status stream
  throw UnimplementedError('WebSocket not initialized');
});

/// Stream of read receipts
final readReceiptStreamProvider = StreamProvider.autoDispose<
    messaging_models.MessageReadReceipt>((ref) {
  // WebSocket read receipt stream
  throw UnimplementedError('WebSocket not initialized');
});

/// Stream of connection status
final connectionStatusStreamProvider =
    StreamProvider.autoDispose<String>((ref) {
  return Stream.value('disconnected');
});

// =============== CHAT MESSAGES STREAM PROVIDER ===============

/// Get messages for a specific chat with fallback to Firebase
final chatMessagesStreamProvider = StreamProvider.family.autoDispose<
    List<messaging_models.Message>,
    String>((ref, chatId) async* {
  // Get messages via Firebase (fallback)
  yield* _getMessagesFromFirebase(chatId);
});

/// Helper to get messages from Firebase
Stream<List<messaging_models.Message>> _getMessagesFromFirebase(String threadId) {
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

// =============== CHAT THREADS PROVIDER ===============

/// Get all chat threads for current user - using chat_threads_provider instead
final chatThreadsProvider = StreamProvider.autoDispose<
    List<messaging_models.ChatThread>>((ref) async* {
  try {
    final userId = await ChatService.myAppUserId();

    yield* ChatService.threadsStream(userId).map((firebaseThreads) {
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
  } catch (e) {
    print('[MessagingProvider] Error fetching chat threads: $e');
    yield [];
  }
});

// =============== UTILITY PROVIDERS ===============

/// Get current user ID
final currentUserIdProvider = FutureProvider<String>((ref) async {
  return ChatService.myAppUserId();
});

/// Get typing users for a specific chat
final typingUsersForChatProvider =
    Provider.family<Set<String>, String>((ref, chatId) {
  final typingUsers = ref.watch(typingUsersProvider);
  return typingUsers[chatId] ?? {};
});

/// Get online status for a specific user
final userOnlineStatusProvider = Provider.family<bool, String>((ref, userId) {
  final onlineUsers = ref.watch(onlineUsersProvider);
  return onlineUsers[userId] ?? false;
});

/// Get message status for a specific message
final messageStatusForProvider =
    Provider.family<messaging_models.MessageStatus, String>((ref, messageId) {
  final statuses = ref.watch(messageStatusProvider);
  return statuses[messageId] ?? messaging_models.MessageStatus.sent;
});

/// Check if WebSocket is connected
final isWebSocketConnectedProvider = Provider((ref) {
  final socketState = ref.watch(socketConnectionStateProvider);
  return socketState.isConnected;
});

// =============== MESSAGING ACTIONS SERVICE ===============

/// Provider for messaging service methods
final messagingServiceProvider = Provider((ref) {
  return MessagingService(ref: ref);
});

class MessagingService {
  final Ref ref;

  MessagingService({required this.ref});

  /// Initialize messaging system
  Future<void> initializeMessaging({
    required String wsUrl,
    required String token,
    required String userId,
  }) async {
    try {
      final service = WebSocketMessagingService(
        wsUrl: wsUrl,
        token: token,
        userId: userId,
      );
      await service.connect();

      // Update socket state
      final stateNotifier = ref.read(socketConnectionStateProvider.notifier);
      stateNotifier.state = messaging_models.SocketState(
        isConnected: true,
        lastConnected: DateTime.now(),
      );
    } catch (e) {
      print('[MessagingService] Failed to initialize: $e');
      final stateNotifier = ref.read(socketConnectionStateProvider.notifier);
      stateNotifier.state =
          stateNotifier.state.copyWith(error: e.toString());
      rethrow;
    }
  }

  /// Join a chat
  Future<void> joinChat(String chatId) async {
    try {
      final activeChats = ref.read(activeChatsProvider.notifier);
      final current = ref.read(activeChatsProvider);
      activeChats.state = {...current, chatId};
    } catch (e) {
      print('[MessagingService] Failed to join chat: $e');
      rethrow;
    }
  }

  /// Leave a chat
  Future<void> leaveChat(String chatId) async {
    try {
      final activeChats = ref.read(activeChatsProvider.notifier);
      final current = ref.read(activeChatsProvider);
      final updated = <String>{...current};
      updated.remove(chatId);
      activeChats.state = updated;
    } catch (e) {
      print('[MessagingService] Failed to leave chat: $e');
      rethrow;
    }
  }

  /// Send a message (uses Firebase as fallback)
  Future<void> sendMessage({
    required String myAppId,
    required String peerAppId,
    required String content,
  }) async {
    try {
      await ChatService.sendMessage(
        myAppId: myAppId,
        peerAppId: peerAppId,
        text: content,
      );
    } catch (e) {
      print('[MessagingService] Failed to send message: $e');
      rethrow;
    }
  }

  /// Start typing indicator
  Future<void> startTyping(String chatId) async {
    try {
      // WebSocket would handle this
    } catch (e) {
      print('[MessagingService] Failed to start typing: $e');
    }
  }

  /// Stop typing indicator
  Future<void> stopTyping(String chatId) async {
    try {
      // WebSocket would handle this
    } catch (e) {
      print('[MessagingService] Failed to stop typing: $e');
    }
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead({
    required String chatId,
    required List<String> messageIds,
  }) async {
    try {
      // WebSocket would handle this
    } catch (e) {
      print('[MessagingService] Failed to mark messages as read: $e');
    }
  }

  /// Update user status
  Future<void> updateUserStatus(String status) async {
    try {
      // WebSocket would handle this
    } catch (e) {
      print('[MessagingService] Failed to update user status: $e');
    }
  }
}
