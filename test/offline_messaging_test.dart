import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vero360_app/GeneralModels/messaging_models.dart';
import 'package:vero360_app/GernalServices/local_message_database.dart';
import 'package:vero360_app/GernalServices/offline_message_queue.dart';
import 'package:vero360_app/GernalServices/message_sync_service.dart';
import 'dart:io';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return './test_hive_db';
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return './test_hive_db';
  }

  @override
  Future<String?> getTemporaryPath() async {
    return './test_hive_db';
  }
}

void main() {
  setUpAll(() async {
    // Setup fake path provider for tests
    PathProviderPlatform.instance = FakePathProviderPlatform();
    
    // Initialize Hive with test directory
    final testDir = Directory('./test_hive_db');
    if (testDir.existsSync()) {
      testDir.deleteSync(recursive: true);
    }
    testDir.createSync();
    
    Hive.init('./test_hive_db');
  });

  tearDownAll(() async {
    // Cleanup test directory
    final testDir = Directory('./test_hive_db');
    if (testDir.existsSync()) {
      testDir.deleteSync(recursive: true);
    }
  });

  group('Offline Messaging System', () {
    late LocalMessageDatabase database;
    late OfflineMessageQueue queue;
    late MessageSyncService syncService;

    setUp(() async {
      database = LocalMessageDatabase();
      queue = OfflineMessageQueue(database: database);
      syncService = MessageSyncService(
        database: database,
        queue: queue,
        webSocket: null,
      );
    });

    test('LocalMessageDatabase initializes', () async {
      await database.initialize();
      expect(database, isNotNull);
    });

    test('OfflineMessageQueue initializes', () async {
      await database.initialize();
      await queue.initialize();
      expect(queue.queueSize, equals(0));
    });

    test('MessageSyncService initializes', () async {
      await database.initialize();
      await queue.initialize();
      await syncService.initialize();
      expect(syncService.currentStatus.isSyncing, equals(false));
    });

    test('Save and retrieve messages', () async {
      await database.initialize();

      final message = Message(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        recipientId: 'user2',
        content: 'Hello',
        createdAt: DateTime.now(),
        status: MessageStatus.sent,
      );

      await database.saveMessage(message);

      final retrieved = database.getMessageById('msg1');
      expect(retrieved, isNotNull);
      expect(retrieved?.content, equals('Hello'));
      expect(retrieved?.senderId, equals('user1'));
    });

    test('Save and retrieve chat threads', () async {
      await database.initialize();

      final thread = ChatThread(
        id: 'thread1',
        participantIds: ['user1', 'user2'],
        participants: {
          'user1': {'name': 'User 1', 'avatar': ''},
          'user2': {'name': 'User 2', 'avatar': ''},
        },
        lastMessageContent: 'Last message',
        updatedAt: DateTime.now(),
      );

      await database.saveChatThread(thread);

      final retrieved = database.getChatThreadById('thread1');
      expect(retrieved, isNotNull);
      expect(retrieved?.participantIds.length, equals(2));
      expect(retrieved?.lastMessageContent, equals('Last message'));
    });

    test('Queue message send operation', () async {
      await database.initialize();
      await queue.initialize();

      final message = Message(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        recipientId: 'user2',
        content: 'Hello',
        createdAt: DateTime.now(),
        status: MessageStatus.sent,
      );

      await queue.queueMessageSend(message: message);

      expect(queue.queueSize, equals(1));
      final queuedOps = queue.getQueue();
      expect(queuedOps.first.type, equals('send'));
      expect(queuedOps.first.message?.content, equals('Hello'));
    });

    test('Queue message edit operation', () async {
      await database.initialize();
      await queue.initialize();

      await queue.queueMessageEdit(
        messageId: 'msg1',
        chatId: 'chat1',
        newContent: 'Updated',
      );

      expect(queue.queueSize, equals(1));
      final queuedOps = queue.getQueue();
      expect(queuedOps.first.type, equals('edit'));
      expect(queuedOps.first.metadata['newContent'], equals('Updated'));
    });

    test('Queue message delete operation', () async {
      await database.initialize();
      await queue.initialize();

      await queue.queueMessageDelete(
        messageId: 'msg1',
        chatId: 'chat1',
      );

      expect(queue.queueSize, equals(1));
      final queuedOps = queue.getQueue();
      expect(queuedOps.first.type, equals('delete'));
    });

    test('Queue read receipt operation', () async {
      await database.initialize();
      await queue.initialize();

      await queue.queueReadReceipt(
        chatId: 'chat1',
        messageIds: ['msg1', 'msg2', 'msg3'],
      );

      expect(queue.queueSize, equals(1));
      final queuedOps = queue.getQueue();
      expect(queuedOps.first.type, equals('read'));
      expect(queuedOps.first.metadata['messageIds'].length, equals(3));
    });

    test('Get messages for specific chat', () async {
      await database.initialize();

      final msg1 = Message(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        recipientId: 'user2',
        content: 'Message 1',
        createdAt: DateTime.now(),
        status: MessageStatus.sent,
      );

      final msg2 = Message(
        id: 'msg2',
        chatId: 'chat2',
        senderId: 'user1',
        recipientId: 'user3',
        content: 'Message 2',
        createdAt: DateTime.now(),
        status: MessageStatus.sent,
      );

      await database.saveMessages([msg1, msg2]);

      final chat1Messages = database.getMessagesForChat('chat1');
      expect(chat1Messages.length, equals(1));
      expect(chat1Messages.first.chatId, equals('chat1'));

      final chat2Messages = database.getMessagesForChat('chat2');
      expect(chat2Messages.length, equals(1));
      expect(chat2Messages.first.chatId, equals('chat2'));
    });

    test('Clear queue and verify empty', () async {
      await database.initialize();
      await queue.initialize();

      await queue.queueMessageSend(
        message: Message(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          recipientId: 'user2',
          content: 'Hello',
          createdAt: DateTime.now(),
          status: MessageStatus.sent,
        ),
      );

      expect(queue.queueSize, equals(1));

      await queue.clearQueue();
      expect(queue.queueSize, equals(0));
    });

    test('Remove specific operation from queue', () async {
      await database.initialize();
      await queue.initialize();

      await queue.queueMessageSend(
        message: Message(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          recipientId: 'user2',
          content: 'Hello',
          createdAt: DateTime.now(),
          status: MessageStatus.sent,
        ),
      );

      final operationId = queue.getQueue().first.id;
      await queue.removeOperation(operationId);

      expect(queue.queueSize, equals(0));
    });

    test('Database stats return correct counts', () async {
      await database.initialize();
      // Clear any existing data
      await database.clearAll();

      final msg = Message(
        id: 'msg_stats_1',
        chatId: 'chat1',
        senderId: 'user1',
        recipientId: 'user2',
        content: 'Hello',
        createdAt: DateTime.now(),
        status: MessageStatus.sent,
      );

      final thread = ChatThread(
        id: 'thread_stats_1',
        participantIds: ['user1', 'user2'],
        participants: {},
        lastMessageContent: 'Last',
        updatedAt: DateTime.now(),
      );

      await database.saveMessage(msg);
      await database.saveChatThread(thread);

      final stats = database.getStats();
      expect(stats['messages'], equals(1));
      expect(stats['threads'], equals(1));
      expect(stats['pendingSyncs'], equals(0));
    });

    test('Sync status reflects pending count', () async {
      await database.initialize();
      expect(syncService.currentStatus.pendingCount, equals(0));
    });

    test('Multiple messages can be queued and tracked', () async {
      await database.initialize();
      await queue.initialize();

      for (int i = 0; i < 5; i++) {
        await queue.queueMessageSend(
          message: Message(
            id: 'msg$i',
            chatId: 'chat1',
            senderId: 'user1',
            recipientId: 'user2',
            content: 'Message $i',
            createdAt: DateTime.now(),
            status: MessageStatus.sent,
          ),
        );
      }

      expect(queue.queueSize, equals(5));
      final ops = queue.getQueue();
      expect(ops.every((op) => op.type == 'send'), isTrue);
    });

    tearDown(() async {
      await queue.dispose();
      await database.close();
    });
  });
}
