import 'package:cloud_firestore/cloud_firestore.dart';

// Message Status enum
enum MessageStatus {
  sent,
  delivered,
  read,
  failed,
}

// Message Status extension
extension MessageStatusExt on MessageStatus {
  String get value => name;

  static MessageStatus fromString(String value) {
    return MessageStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MessageStatus.sent,
    );
  }
}

// Core Message Model
class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String recipientId;
  final String content;
  final DateTime createdAt;
  final DateTime? editedAt;
  final MessageStatus status;
  final bool isEdited;
  final bool isDeleted;
  final List<String>? attachmentUrls;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.createdAt,
    this.editedAt,
    this.status = MessageStatus.sent,
    this.isEdited = false,
    this.isDeleted = false,
    this.attachmentUrls,
  });

  bool isMine(String myId) => senderId == myId;

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      chatId: json['chatId'] ?? '',
      senderId: json['senderId'] ?? '',
      recipientId: json['recipientId'] ?? '',
      content: json['content'] ?? '',
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : json['createdAt'] is String
              ? DateTime.parse(json['createdAt'] as String)
              : DateTime.now(),
      editedAt: json['editedAt'] is Timestamp
          ? (json['editedAt'] as Timestamp).toDate()
          : json['editedAt'] is String
              ? DateTime.parse(json['editedAt'] as String)
              : null,
      status: MessageStatusExt.fromString(json['status'] ?? 'sent'),
      isEdited: json['isEdited'] ?? false,
      isDeleted: json['isDeleted'] ?? false,
      attachmentUrls: json['attachmentUrls'] != null
          ? List<String>.from(json['attachmentUrls'] as List)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chatId': chatId,
      'senderId': senderId,
      'recipientId': recipientId,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'status': status.value,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'attachmentUrls': attachmentUrls,
    };
  }
}

// Chat Thread Model
class ChatThread {
  final String id;
  final List<String> participantIds;
  final Map<String, dynamic> participants; // userId -> {name, avatar}
  final String lastMessageContent;
  final DateTime updatedAt;
  final String? lastSenderId;
  final String? lastMessageId;
  final Map<String, int> unreadCounts; // userId -> count

  ChatThread({
    required this.id,
    required this.participantIds,
    required this.participants,
    required this.lastMessageContent,
    required this.updatedAt,
    this.lastSenderId,
    this.lastMessageId,
    this.unreadCounts = const {},
  });

  String getOtherId(String myId) =>
      participantIds.firstWhere((x) => x != myId, orElse: () => myId);

  int getUnreadCount(String userId) => unreadCounts[userId] ?? 0;

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    return ChatThread(
      id: json['id'] ?? '',
      participantIds: List<String>.from(json['participantIds'] ?? []),
      participants: json['participants'] ?? {},
      lastMessageContent: json['lastMessageContent'] ?? '',
      updatedAt: json['updatedAt'] is Timestamp
          ? (json['updatedAt'] as Timestamp).toDate()
          : json['updatedAt'] is String
              ? DateTime.parse(json['updatedAt'] as String)
              : DateTime.now(),
      lastSenderId: json['lastSenderId'],
      lastMessageId: json['lastMessageId'],
      unreadCounts: json['unreadCounts'] != null
          ? Map<String, int>.from(json['unreadCounts'] as Map)
          : {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'participantIds': participantIds,
      'participants': participants,
      'lastMessageContent': lastMessageContent,
      'updatedAt': updatedAt.toIso8601String(),
      'lastSenderId': lastSenderId,
      'lastMessageId': lastMessageId,
      'unreadCounts': unreadCounts,
    };
  }
}

// Socket State for connection management
class SocketState {
  final bool isConnected;
  final String? error;
  final DateTime? lastConnected;
  final bool isReconnecting;

  SocketState({
    this.isConnected = false,
    this.error,
    this.lastConnected,
    this.isReconnecting = false,
  });

  SocketState copyWith({
    bool? isConnected,
    String? error,
    DateTime? lastConnected,
    bool? isReconnecting,
  }) {
    return SocketState(
      isConnected: isConnected ?? this.isConnected,
      error: error ?? this.error,
      lastConnected: lastConnected ?? this.lastConnected,
      isReconnecting: isReconnecting ?? this.isReconnecting,
    );
  }
}

// Messaging Event Models
class TypingIndicator {
  final String chatId;
  final String userId;
  final bool isTyping;

  TypingIndicator({
    required this.chatId,
    required this.userId,
    required this.isTyping,
  });

  factory TypingIndicator.fromJson(Map<String, dynamic> json) {
    return TypingIndicator(
      chatId: json['chatId'] ?? '',
      userId: json['userId'] ?? '',
      isTyping: json['isTyping'] ?? false,
    );
  }
}

class UserStatus {
  final String userId;
  final bool isOnline;
  final DateTime? lastSeen;

  UserStatus({
    required this.userId,
    required this.isOnline,
    this.lastSeen,
  });

  factory UserStatus.fromJson(Map<String, dynamic> json) {
    return UserStatus(
      userId: json['userId'] ?? '',
      isOnline: json['isOnline'] ?? false,
      lastSeen: json['lastSeen'] is Timestamp
          ? (json['lastSeen'] as Timestamp).toDate()
          : json['lastSeen'] is String
              ? DateTime.parse(json['lastSeen'] as String)
              : null,
    );
  }
}

class MessageReadReceipt {
  final String chatId;
  final String userId;
  final List<String> messageIds;
  final DateTime timestamp;

  MessageReadReceipt({
    required this.chatId,
    required this.userId,
    required this.messageIds,
    required this.timestamp,
  });

  factory MessageReadReceipt.fromJson(Map<String, dynamic> json) {
    return MessageReadReceipt(
      chatId: json['chatId'] ?? '',
      userId: json['userId'] ?? '',
      messageIds: List<String>.from(json['messageIds'] ?? []),
      timestamp: json['timestamp'] is Timestamp
          ? (json['timestamp'] as Timestamp).toDate()
          : json['timestamp'] is String
              ? DateTime.parse(json['timestamp'] as String)
              : DateTime.now(),
    );
  }
}
