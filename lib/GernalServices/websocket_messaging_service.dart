import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vero360_app/GeneralModels/messaging_models.dart';
import 'package:vero360_app/utils/app_logger.dart';

// Forward declaration to avoid circular dependency
typedef OnReconnectCallback = Future<void> Function();

class WebSocketMessagingService {
  IO.Socket? _socket;
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
  bool _disposed = false;
  bool _connecting = false;
  bool _reconnectScheduled = false;
  bool _manualDisconnect = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  Timer? _reconnectTimer;

  // Callback for handling reconnection sync
  OnReconnectCallback? _onReconnectCallback;

  void _emitStatus(String status) {
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(status);
    }
  }

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
  Stream<MessageReadReceipt> get readReceiptStream =>
      _readReceiptController.stream;
  Stream<String> get connectionStatusStream =>
      _connectionStatusController.stream;

  // Getters for state
  bool get isConnected => _isConnected && (_socket?.connected ?? false);
  Set<String> get activeChats => _activeChats;
  Map<String, Set<String>> get typingUsers => _typingUsers;
  Map<String, bool> get onlineUsers => _onlineUsers;

  /// Initialize WebSocket connection
  Future<void> connect() async {
    if (_disposed) return;
    if (isConnected) return;
    if (_connecting) return;

    _connecting = true;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _reconnectScheduled = false;

    final completer = Completer<void>();
    Timer? timeout;

    try {
      _tearDownSocket(keepStatus: true);

      final socket = IO.io(
        _wsUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .enableForceNew()
            .disableReconnection() // we own reconnect to avoid duplicate loops
            .setAuth({'token': _token, 'userId': _userId})
            .build(),
      );
      _socket = socket;

      void onConnect(_) {
        timeout?.cancel();
        if (!completer.isCompleted) completer.complete();
      }

      void onConnectError(dynamic err) {
        timeout?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            Exception('WebSocket connection failed: $err'),
          );
        }
      }

      socket.on('connect', onConnect);
      socket.on('connect_error', onConnectError);
      _setupEventListeners(socket);
      socket.connect();

      timeout = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('WebSocket connection timeout'));
        }
      });

      await completer.future;
      if (_disposed || _manualDisconnect) return;

      _isConnected = true;
      _reconnectAttempts = 0;
      _emitStatus('connected');
    } catch (e) {
      _isConnected = false;
      _emitStatus('error');
      AppLogger.d('[WebSocket] Connection error', e);
      if (!_disposed && !_manualDisconnect) {
        _scheduleReconnect();
      }
      rethrow;
    } finally {
      timeout?.cancel();
      _connecting = false;
    }
  }

  /// Set callback for handling reconnection sync
  void setOnReconnectCallback(OnReconnectCallback callback) {
    _onReconnectCallback = callback;
  }

  /// Setup WebSocket event listeners
  void _setupEventListeners(IO.Socket socket) {
    socket.on('connect', (_) async {
      if (_disposed) return;
      _isConnected = true;
      _reconnectAttempts = 0;
      _reconnectScheduled = false;
      _emitStatus('connected');

      // Trigger sync on reconnect
      if (_onReconnectCallback != null) {
        try {
          await _onReconnectCallback!();
        } catch (e) {
          AppLogger.d('[WebSocket] Error during reconnect callback', e);
        }
      }
    });

    socket.on('message:received', (data) {
      try {
        final message = Message.fromJson(data as Map<String, dynamic>);
        if (!_messageController.isClosed) _messageController.add(message);
      } catch (e) {
        AppLogger.d('[WebSocket] Error parsing message', e);
      }
    });

    socket.on('typing:indicator', (data) {
      try {
        final typing = TypingIndicator.fromJson(data as Map<String, dynamic>);
        _handleTypingIndicator(typing);
        if (!_typingController.isClosed) _typingController.add(typing);
      } catch (e) {
        AppLogger.d('[WebSocket] Error parsing typing indicator', e);
      }
    });

    socket.on('user:status', (data) {
      try {
        final status = UserStatus.fromJson(data as Map<String, dynamic>);
        _onlineUsers[status.userId] = status.isOnline;
        if (!_userStatusController.isClosed) _userStatusController.add(status);
      } catch (e) {
        AppLogger.d('[WebSocket] Error parsing user status', e);
      }
    });

    socket.on('message:read-receipt', (data) {
      try {
        final receipt =
            MessageReadReceipt.fromJson(data as Map<String, dynamic>);
        if (!_readReceiptController.isClosed) {
          _readReceiptController.add(receipt);
        }
      } catch (e) {
        AppLogger.d('[WebSocket] Error parsing read receipt', e);
      }
    });

    socket.on('disconnect', (_) {
      if (_disposed || _manualDisconnect) return;
      _isConnected = false;
      _emitStatus('disconnected');
      _scheduleReconnect();
    });

    socket.on('error', (_) {
      if (_disposed || _manualDisconnect) return;
      _isConnected = false;
      _emitStatus('error');
      // disconnect usually follows; avoid double-scheduling here
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

  /// Single-flight reconnect with exponential backoff.
  void _scheduleReconnect() {
    if (_disposed || _manualDisconnect || _connecting) return;
    if (_reconnectScheduled) return;

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      AppLogger.d('[WebSocket] Max reconnection attempts reached');
      _emitStatus('failed');
      return;
    }

    _reconnectScheduled = true;
    _reconnectAttempts++;
    final delay = _reconnectDelay * _reconnectAttempts;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      _reconnectScheduled = false;
      if (_disposed || _manualDisconnect || isConnected || _connecting) return;
      try {
        await connect();
      } catch (_) {
        // connect() schedules the next attempt when needed
      }
    });
  }

  void _tearDownSocket({bool keepStatus = false}) {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    try {
      socket.clearListeners();
      if (socket.connected) socket.disconnect();
      socket.dispose();
    } catch (_) {}
    if (!keepStatus) {
      _isConnected = false;
    }
  }

  // =============== CLIENT EVENTS ===============

  /// Join a chat room
  Future<void> joinChat(String chatId) async {
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }
    _activeChats.add(chatId);
    _socket!.emit('chat:join', {'chatId': chatId});
  }

  /// Leave a chat room
  Future<void> leaveChat(String chatId) async {
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }
    _activeChats.remove(chatId);
    _socket!.emit('chat:leave', {'chatId': chatId});
  }

  /// Send a message
  Future<void> sendMessage({
    required String chatId,
    required String recipientId,
    required String content,
  }) async {
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket!.emit('message:send', {
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
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket!.emit('message:edit', {
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
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket!.emit('message:delete', {
      'chatId': chatId,
      'messageId': messageId,
    });
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead({
    required String chatId,
    required List<String> messageIds,
  }) async {
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket!.emit('message:read', {
      'chatId': chatId,
      'messageIds': messageIds,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Start typing indicator
  Future<void> startTyping(String chatId) async {
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket!.emit('typing:start', {'chatId': chatId});
  }

  /// Stop typing indicator
  Future<void> stopTyping(String chatId) async {
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket!.emit('typing:stop', {'chatId': chatId});
  }

  /// Update user status
  Future<void> updateUserStatus(String status) async {
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }

    _socket!.emit('user:status', {
      'status': status, // 'online', 'away', 'offline'
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Subscribe to typing indicators in a chat
  void subscribeToTypingIndicators(String chatId) {
    if (!isConnected) return;
    _socket!.emit('typing:subscribe', {'chatId': chatId});
  }

  /// Unsubscribe from typing indicators
  void unsubscribeFromTypingIndicators(String chatId) {
    if (!isConnected) {
      return;
    }
    _socket!.emit('typing:unsubscribe', {'chatId': chatId});
  }

  // =============== CLEANUP ===============

  /// Disconnect and cleanup
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectScheduled = false;
    _activeChats.clear();
    _typingUsers.clear();
    _onlineUsers.clear();
    _tearDownSocket();
    _emitStatus('disconnected');
  }

  /// Dispose all streams
  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _messageController.close();
    await _typingController.close();
    await _userStatusController.close();
    await _readReceiptController.close();
    await _connectionStatusController.close();
  }
}
