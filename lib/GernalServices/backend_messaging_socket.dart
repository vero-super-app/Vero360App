import 'dart:async';

import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/websocket_messaging_service.dart';
import 'package:vero360_app/GeneralModels/messaging_models.dart' as ws;

/// Shared Socket.IO connection for backend messaging (one per app session).
class BackendMessagingSocket {
  BackendMessagingSocket._();

  static WebSocketMessagingService? _ws;
  static StreamSubscription<ws.Message>? _subscription;
  static bool _connectionListenerAttached = false;
  static final StreamController<BackendChatMessage> _messageController =
      StreamController<BackendChatMessage>.broadcast();
  static final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  static Stream<BackendChatMessage> get messageStream =>
      _messageController.stream;

  static Stream<bool> get connectionStream => _connectionController.stream;

  static bool get isConnected => _ws?.isConnected ?? false;

  /// Underlying Socket.IO client for legacy call sites ([WebSocketManager]).
  static WebSocketMessagingService? get webSocketService =>
      isConnected ? _ws : null;

  static Future<void> connect() async {
    if (_ws?.isConnected == true) return;

    await _subscription?.cancel();
    _subscription = null;
    if (_ws != null) {
      await _ws!.dispose();
      _ws = null;
    }

    final token = await BackendChatService.getAuthToken();
    final userId = await BackendChatService.getUserId();

    _ws = WebSocketMessagingService(
      wsUrl: BackendChatService.messagingWsUrl,
      token: token,
      userId: userId.toString(),
    );

    await _subscription?.cancel();
    _subscription = null;

    await _ws!.connect();

    _subscription = _ws!.messageStream.listen(
      (msg) {
        final backendMsg = _toBackendMessage(msg);
        _messageController.add(backendMsg);
        BackendChatService.notifyRealtimeMessage(backendMsg);
      },
      onError: (_) {},
    );

    if (!_connectionListenerAttached) {
      _connectionListenerAttached = true;
      _ws!.connectionStatusStream.listen((status) {
        final connected = status == 'connected';
        _connectionController.add(connected);
        BackendChatService.notifyWsConnected(connected);
      });
    }
  }

  static Future<void> joinChat(String chatId) async {
    if (_ws == null || !_ws!.isConnected) {
      await connect();
    }
    await _ws!.joinChat(chatId);
  }

  static Future<void> leaveChat(String chatId) async {
    if (_ws == null || !_ws!.isConnected) return;
    await _ws!.leaveChat(chatId);
  }

  static BackendChatMessage _toBackendMessage(ws.Message msg) {
    return BackendChatMessage(
      id: msg.id,
      chatId: msg.chatId,
      senderId: msg.senderId,
      content: msg.content,
      type: 'text',
      status: msg.status.name,
      createdAt: msg.createdAt,
      tags: msg.tags,
      sender: msg.sender,
      clientMessageId: msg.clientMessageId,
    );
  }

  static Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _ws?.dispose();
    _ws = null;
    _connectionController.add(false);
  }
}
