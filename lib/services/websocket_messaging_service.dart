import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vero360_app/models/messaging_models.dart';

class WebSocketMessagingService {
  late IO.Socket _socket;
  final String _wsUrl;
  final String _token;
  final String _userId;

  final StreamController<Message> _messageController =
      StreamController<Message>.broadcast();
  final StreamController<TypingIndicator> _typingController =
      StreamController<TypingIndicator>.broadcast();
  final StreamController<UserStatus> _userStatusController =
      StreamController<UserStatus>.broadcast();
  final StreamController<MessageReadReceipt> _readReceiptController =
      StreamController<MessageReadReceipt>.broadcast();
  final StreamController<String> _connectionStatusController =
      StreamController<String>.broadcast();

  // Active chats and typing users
  final Set<String> _activeChats = {};
  final Map<String, Set<String>> _typingUsers = {};
  final Map<String, bool> _onlineUsers = {};

  bool _isConnected = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 2);

  WebSocketMessagingService({
    required String wsUrl,
    required String token,
    required String userId,
  })  : _wsUrl = wsUrl,
        _token = token,
        _userId = userId;

  // Getters for streams
  Stream<Message> get messageStream => _messageController.stream;
  Stream<TypingIndicator> get typingStream => _typingController.stream;
  Stream<UserStatus> get userStatusStream => _userStatusController.stream;
  Stream<MessageReadReceipt> get readReceiptStream => _readReceiptController.stream;
  Stream<String> get connectionStatusStream => _connectionStatusController.stream;

  // Getters for state
  bool get isConnected => _isConnected;
  Set<String> get activeChats => _activeChats;
  Map<String, Set<String>> get typingUsers => _typingUsers;
  Map<String, bool> get onlineUsers => _onlineUsers;

  /// Initialize WebSocket connection
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      _socket = IO.io(
        _wsUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .setAuth({'token': _token, 'userId': _userId})
            .build(),
      );

      _setupEventListeners();
      _socket.connect();

      // Wait for connection with timeout
      await Future.delayed(const Duration(seconds: 1));
      if (!_socket.connected) {
        throw Exception('WebSocket connection failed');
      }

      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionStatusController.add('connected');
    } catch (e) {
      _handleConnectionError(e);
    }
  }

  /// Setup WebSocket event listeners
  void _setupEventListeners() {
    _socket.on('connect', (_) {
      print('[WebSocket] Connected to messaging server');
      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionStatusController.add('connected');
    });

    _socket.on('message:received', (data) {
      try {
        final message = Message.fromJson(data as Map<String, dynamic>);
        _messageController.add(message);
      } catch (e) {
        print('[WebSocket] Error parsing message: $e');
      }
    });

    _socket.on('typing:indicator', (data) {
      try {
        final typing = TypingIndicator.fromJson(data as Map<String, dynamic>);
        _handleTypingIndicator(typing);
        _typingController.add(typing);
      } catch (e) {
        print('[WebSocket] Error parsing typing indicator: $e');
      }
    });

    _socket.on('user:status', (data) {
      try {
        final status = UserStatus.fromJson(data as Map<String, dynamic>);
        _onlineUsers[status.userId] = status.isOnline;
        _userStatusController.add(status);
      } catch (e) {
        print('[WebSocket] Error parsing user status: $e');
      }
    });

    _socket.on('message:read-receipt', (data) {
      try {
        final receipt = MessageReadReceipt.fromJson(data as Map<String, dynamic>);
        _readReceiptController.add(receipt);
      } catch (e) {
        print('[WebSocket] Error parsing read receipt: $e');
      }
    });

    _socket.on('disconnect', (_) {
      print('[WebSocket] Disconnected from messaging server');
      _isConnected = false;
      _connectionStatusController.add('disconnected');
      _attemptReconnect();
    });

    _socket.on('error', (error) {
      print('[WebSocket] Error: $error');
      _isConnected = false;
      _connectionStatusController.add('error');
    });
  }

  /// Handle typing indicator updates
  void _handleTypingIndicator(TypingIndicator typing) {
    if (!_typingUsers.containsKey(typing.chatId)) {
      _typingUsers[typing.chatId] = {};
    }

    if (typing.isTyping) {
      _typingUsers[typing.chatId]!.add(typing.userId);
    } else {
      _typingUsers[typing.chatId]!.remove(typing.userId);
    }
  }

  /// Attempt to reconnect with exponential backoff
  Future<void> _attemptReconnect() async {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('[WebSocket] Max reconnection attempts reached');
      _connectionStatusController.add('failed');
      return;
    }

    _reconnectAttempts++;
    final delay = _reconnectDelay * _reconnectAttempts;
    print('[WebSocket] Attempting reconnect in ${delay.inSeconds}s (attempt $_reconnectAttempts)');

    await Future.delayed(delay);
    await connect();
  }

  /// Handle connection errors
  void _handleConnectionError(Object error) {
    print('[WebSocket] Connection error: $error');
    _isConnected = false;
    _connectionStatusController.add('error');
    _attemptReconnect();
  }

  // =============== CLIENT EVENTS ===============

  /// Join a chat room
  Future<void> joinChat(String chatId) async {
    if (!_isConnected) {
      throw Exception('WebSocket not connected');
    }
    _activeChats.add(chatId);
    _socket.emit('chat:join', {'chatId': chatId});
  }

  /// Leave a chat room
  Future<void> leaveChat(String chatId) async {
    if (!_isConnected) {
      throw Exception('WebSocket not connected');
    }
    _activeChats.remove(chatId);
    _socket.emit('chat:leave', {'chatId': chatId});
  }

  /// Send a message
  Future<void> sendMessage({
    required String chatId,
    required String recipientId,
    required String content,
  }) async {
    if (!_isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket.emit('message:send', {
      'chatId': chatId,
      'recipientId': recipientId,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Edit a message
  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String newContent,
  }) async {
    if (!_isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket.emit('message:edit', {
      'chatId': chatId,
      'messageId': messageId,
      'newContent': newContent,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Delete a message
  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    if (!_isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket.emit('message:delete', {
      'chatId': chatId,
      'messageId': messageId,
    });
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead({
    required String chatId,
    required List<String> messageIds,
  }) async {
    if (!_isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket.emit('message:read', {
      'chatId': chatId,
      'messageIds': messageIds,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Start typing indicator
  Future<void> startTyping(String chatId) async {
    if (!_isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket.emit('typing:start', {'chatId': chatId});
  }

  /// Stop typing indicator
  Future<void> stopTyping(String chatId) async {
    if (!_isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket.emit('typing:stop', {'chatId': chatId});
  }

  /// Update user status
  Future<void> updateUserStatus(String status) async {
    if (!_isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket.emit('user:status', {
      'status': status, // 'online', 'away', 'offline'
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Subscribe to typing indicators in a chat
  void subscribeToTypingIndicators(String chatId) {
    if (!_isConnected) {
      print('[WebSocket] Not connected, cannot subscribe to typing indicators');
      return;
    }
    _socket.emit('typing:subscribe', {'chatId': chatId});
  }

  /// Unsubscribe from typing indicators in a chat
  void unsubscribeFromTypingIndicators(String chatId) {
    if (!_isConnected) {
      return;
    }
    _socket.emit('typing:unsubscribe', {'chatId': chatId});
  }

  // =============== CLEANUP ===============

  /// Disconnect and cleanup
  Future<void> disconnect() async {
    _activeChats.clear();
    _typingUsers.clear();
    _onlineUsers.clear();

    if (_socket.connected) {
      _socket.disconnect();
    }

    _isConnected = false;
    _connectionStatusController.add('disconnected');
  }

  /// Dispose all streams
  Future<void> dispose() async {
    await disconnect();
    await _messageController.close();
    await _typingController.close();
    await _userStatusController.close();
    await _readReceiptController.close();
    await _connectionStatusController.close();
  }
}
