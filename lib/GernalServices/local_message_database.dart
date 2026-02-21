import 'package:hive/hive.dart';
import 'package:vero360_app/GeneralModels/messaging_models.dart';

part 'local_message_database.g.dart';

@HiveType(typeId: 10)
class LocalMessage extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String chatId;

  @HiveField(2)
  late String senderId;

  @HiveField(3)
  late String recipientId;

  @HiveField(4)
  late String content;

  @HiveField(5)
  late DateTime createdAt;

  @HiveField(6)
  DateTime? editedAt;

  @HiveField(7)
  late String status; // MessageStatus.value

  @HiveField(8)
  late bool isEdited;

  @HiveField(9)
  late bool isDeleted;

  @HiveField(10)
  List<String>? attachmentUrls;

  @HiveField(11)
  late bool isSynced; // Track if synced with backend

  LocalMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.createdAt,
    this.editedAt,
    required this.status,
    required this.isEdited,
    required this.isDeleted,
    this.attachmentUrls,
    this.isSynced = false,
  });

  /// Convert Message to LocalMessage
  factory LocalMessage.fromMessage(Message msg) {
    return LocalMessage(
      id: msg.id,
      chatId: msg.chatId,
      senderId: msg.senderId,
      recipientId: msg.recipientId,
      content: msg.content,
      createdAt: msg.createdAt,
      editedAt: msg.editedAt,
      status: msg.status.value,
      isEdited: msg.isEdited,
      isDeleted: msg.isDeleted,
      attachmentUrls: msg.attachmentUrls,
      isSynced: true,
    );
  }

  /// Convert LocalMessage to Message
  Message toMessage() {
    return Message(
      id: id,
      chatId: chatId,
      senderId: senderId,
      recipientId: recipientId,
      content: content,
      createdAt: createdAt,
      editedAt: editedAt,
      status: MessageStatusExt.fromString(status),
      isEdited: isEdited,
      isDeleted: isDeleted,
      attachmentUrls: attachmentUrls,
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
      'status': status,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'attachmentUrls': attachmentUrls,
      'isSynced': isSynced,
    };
  }
}

@HiveType(typeId: 11)
class LocalChatThread extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late List<String> participantIds;

  @HiveField(2)
  late Map<String, dynamic> participants;

  @HiveField(3)
  late String lastMessageContent;

  @HiveField(4)
  late DateTime updatedAt;

  @HiveField(5)
  String? lastSenderId;

  @HiveField(6)
  String? lastMessageId;

  @HiveField(7)
  late Map<String, int> unreadCounts;

  LocalChatThread({
    required this.id,
    required this.participantIds,
    required this.participants,
    required this.lastMessageContent,
    required this.updatedAt,
    this.lastSenderId,
    this.lastMessageId,
    this.unreadCounts = const {},
  });

  /// Convert ChatThread to LocalChatThread
  factory LocalChatThread.fromChatThread(ChatThread ct) {
    return LocalChatThread(
      id: ct.id,
      participantIds: ct.participantIds,
      participants: ct.participants,
      lastMessageContent: ct.lastMessageContent,
      updatedAt: ct.updatedAt,
      lastSenderId: ct.lastSenderId,
      lastMessageId: ct.lastMessageId,
      unreadCounts: ct.unreadCounts,
    );
  }

  /// Convert LocalChatThread to ChatThread
  ChatThread toChatThread() {
    return ChatThread(
      id: id,
      participantIds: participantIds,
      participants: participants,
      lastMessageContent: lastMessageContent,
      updatedAt: updatedAt,
      lastSenderId: lastSenderId,
      lastMessageId: lastMessageId,
      unreadCounts: unreadCounts,
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

/// Local database service using Hive for offline message persistence
class LocalMessageDatabase {
  static const String _messagesBoxName = 'messages';
  static const String _threadsBoxName = 'chat_threads';
  static const String _queueBoxName = 'message_queue';
  static const String _configBoxName = 'messaging_config';

  late Box<LocalMessage> _messagesBox;
  late Box<LocalChatThread> _threadsBox;
  late Box _queueBox;
  late Box<Map> _configBox;

  bool _isInitialized = false;

  /// Initialize Hive and open boxes
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Register adapters
      if (!Hive.isAdapterRegistered(10)) {
        Hive.registerAdapter(LocalMessageAdapter());
      }
      if (!Hive.isAdapterRegistered(11)) {
        Hive.registerAdapter(LocalChatThreadAdapter());
      }

      // Open boxes
      _messagesBox = await Hive.openBox<LocalMessage>(_messagesBoxName);
      _threadsBox = await Hive.openBox<LocalChatThread>(_threadsBoxName);
      _queueBox = await Hive.openBox(_queueBoxName);
      _configBox = await Hive.openBox<Map>(_configBoxName);

      _isInitialized = true;
      print('[LocalMessageDatabase] Initialized successfully');
    } catch (e) {
      print('[LocalMessageDatabase] Initialization error: $e');
      rethrow;
    }
  }

  /// Save a message locally
  Future<void> saveMessage(Message message) async {
    try {
      final localMsg = LocalMessage.fromMessage(message);
      await _messagesBox.put(message.id, localMsg);
    } catch (e) {
      print('[LocalMessageDatabase] Error saving message: $e');
      rethrow;
    }
  }

  /// Save multiple messages
  Future<void> saveMessages(List<Message> messages) async {
    try {
      final Map<String, LocalMessage> batch = {};
      for (final msg in messages) {
        batch[msg.id] = LocalMessage.fromMessage(msg);
      }
      await _messagesBox.putAll(batch);
    } catch (e) {
      print('[LocalMessageDatabase] Error saving messages: $e');
      rethrow;
    }
  }

  /// Get all messages for a chat
  List<Message> getMessagesForChat(String chatId) {
    try {
      return _messagesBox.values
          .where((msg) => msg.chatId == chatId)
          .map((msg) => msg.toMessage())
          .toList();
    } catch (e) {
      print('[LocalMessageDatabase] Error getting messages for chat: $e');
      return [];
    }
  }

  /// Get message by ID
  Message? getMessageById(String messageId) {
    try {
      final localMsg = _messagesBox.get(messageId);
      return localMsg?.toMessage();
    } catch (e) {
      print('[LocalMessageDatabase] Error getting message: $e');
      return null;
    }
  }

  /// Delete a message
  Future<void> deleteMessage(String messageId) async {
    try {
      await _messagesBox.delete(messageId);
    } catch (e) {
      print('[LocalMessageDatabase] Error deleting message: $e');
      rethrow;
    }
  }

  /// Clear all messages for a chat
  Future<void> clearChatMessages(String chatId) async {
    try {
      final keysToDelete = _messagesBox.values
          .where((msg) => msg.chatId == chatId)
          .map((msg) => msg.key)
          .toList();
      await _messagesBox.deleteAll(keysToDelete);
    } catch (e) {
      print('[LocalMessageDatabase] Error clearing chat messages: $e');
      rethrow;
    }
  }

  /// Save a chat thread locally
  Future<void> saveChatThread(ChatThread thread) async {
    try {
      final localThread = LocalChatThread.fromChatThread(thread);
      await _threadsBox.put(thread.id, localThread);
    } catch (e) {
      print('[LocalMessageDatabase] Error saving chat thread: $e');
      rethrow;
    }
  }

  /// Save multiple chat threads
  Future<void> saveChatThreads(List<ChatThread> threads) async {
    try {
      final Map<String, LocalChatThread> batch = {};
      for (final thread in threads) {
        batch[thread.id] = LocalChatThread.fromChatThread(thread);
      }
      await _threadsBox.putAll(batch);
    } catch (e) {
      print('[LocalMessageDatabase] Error saving chat threads: $e');
      rethrow;
    }
  }

  /// Get all chat threads
  List<ChatThread> getAllChatThreads() {
    try {
      return _threadsBox.values
          .map((thread) => thread.toChatThread())
          .toList();
    } catch (e) {
      print('[LocalMessageDatabase] Error getting chat threads: $e');
      return [];
    }
  }

  /// Get chat thread by ID
  ChatThread? getChatThreadById(String threadId) {
    try {
      final localThread = _threadsBox.get(threadId);
      return localThread?.toChatThread();
    } catch (e) {
      print('[LocalMessageDatabase] Error getting chat thread: $e');
      return null;
    }
  }

  /// Delete a chat thread
  Future<void> deleteChatThread(String threadId) async {
    try {
      await _threadsBox.delete(threadId);
    } catch (e) {
      print('[LocalMessageDatabase] Error deleting chat thread: $e');
      rethrow;
    }
  }

  /// Add message to sync queue
  Future<void> queueMessageForSync(String messageId, Map<String, dynamic> messageData) async {
    try {
      final queue = await _queueBox.get('pending_syncs', defaultValue: []);
      final List<dynamic> pendingList = List.from(queue ?? []);
      pendingList.add({
        'messageId': messageId,
        'data': messageData,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await _queueBox.put('pending_syncs', pendingList);
    } catch (e) {
      print('[LocalMessageDatabase] Error queuing message for sync: $e');
      rethrow;
    }
  }

  /// Get all pending syncs
  List<Map<String, dynamic>> getPendingSyncs() {
    try {
      final queue = _queueBox.get('pending_syncs', defaultValue: []);
      if (queue == null) return [];
      return List<Map<String, dynamic>>.from(queue);
    } catch (e) {
      print('[LocalMessageDatabase] Error getting pending syncs: $e');
      return [];
    }
  }

  /// Remove message from sync queue
  Future<void> removePendingSync(String messageId) async {
    try {
      final queue = await _queueBox.get('pending_syncs', defaultValue: []);
      final List<dynamic> pendingList = List.from(queue ?? []);
      pendingList.removeWhere((item) => item['messageId'] == messageId);
      await _queueBox.put('pending_syncs', pendingList);
    } catch (e) {
      print('[LocalMessageDatabase] Error removing pending sync: $e');
      rethrow;
    }
  }

  /// Clear all pending syncs
  Future<void> clearPendingSyncs() async {
    try {
      await _queueBox.delete('pending_syncs');
    } catch (e) {
      print('[LocalMessageDatabase] Error clearing pending syncs: $e');
      rethrow;
    }
  }

  /// Store sync metadata
  Future<void> setSyncMetadata(String key, dynamic value) async {
    try {
      final metadata = (_configBox.get('sync_metadata') ?? {});
      metadata[key] = value;
      await _configBox.put('sync_metadata', metadata);
        } catch (e) {
      print('[LocalMessageDatabase] Error setting sync metadata: $e');
      rethrow;
    }
  }

  /// Get sync metadata
  dynamic getSyncMetadata(String key) {
    try {
      final metadata = (_configBox.get('sync_metadata') ?? {});
      return metadata[key];
          return null;
    } catch (e) {
      print('[LocalMessageDatabase] Error getting sync metadata: $e');
      return null;
    }
  }

  /// Clear all local data
  Future<void> clearAll() async {
    try {
      await _messagesBox.clear();
      await _threadsBox.clear();
      await _queueBox.clear();
      await _configBox.clear();
      print('[LocalMessageDatabase] All data cleared');
    } catch (e) {
      print('[LocalMessageDatabase] Error clearing all data: $e');
      rethrow;
    }
  }

  /// Close all boxes
  Future<void> close() async {
    try {
      if (!_isInitialized) return;
      
      if (_messagesBox.isOpen) await _messagesBox.close();
      if (_threadsBox.isOpen) await _threadsBox.close();
      if (_queueBox.isOpen) await _queueBox.close();
      if (_configBox.isOpen) await _configBox.close();
      _isInitialized = false;
      print('[LocalMessageDatabase] Closed successfully');
    } catch (e) {
      print('[LocalMessageDatabase] Error closing: $e');
      rethrow;
    }
  }

  /// Get database stats
  Map<String, int> getStats() {
    return {
      'messages': _messagesBox.length,
      'threads': _threadsBox.length,
      'pendingSyncs': (getPendingSyncs()).length,
    };
  }
}
