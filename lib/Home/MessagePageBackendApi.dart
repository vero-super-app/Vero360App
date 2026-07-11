import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/GernalServices/chat_notification_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/GeneralModels/chat_product_context.dart';
import 'package:vero360_app/widgets/modern_confirm_dialog.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';
import 'package:vero360_app/widgets/messaging_skeleton_loaders.dart';
import 'package:vero360_app/widgets/voice_note_bubble.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/GeneralPages/checkout_page.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart'
    as core;
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';

class MessagePageBackendApi extends StatefulWidget {
  /// Chat ID from backend. Empty when chat is resolved after open (marketplace).
  final String peerId;
  final String peerName;
  final String? peerAvatarUrl;
  final ChatProductContext? productContext;
  final String? peerMerchantId;
  final int? peerUserId;

  /// When true, sends the marketplace enquiry once (product page only).
  final bool sendProductEnquiry;

  /// Optional marketplace resolve args when [peerId] is empty.
  final int? resolveSqlItemId;
  final int? resolveOwnerId;
  final String? resolveSellerUserId;
  final String? resolveServiceProviderId;
  final String? resolveMerchantId;
  final String? resolveFirestoreItemDocId;

  /// In-flight marketplace resolve started before navigation (shared request).
  final Future<MerchantChatResult>? pendingMerchantChat;

  const MessagePageBackendApi({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerAvatarUrl,
    this.productContext,
    this.peerMerchantId,
    this.peerUserId,
    this.sendProductEnquiry = false,
    this.resolveSqlItemId,
    this.resolveOwnerId,
    this.resolveSellerUserId,
    this.resolveServiceProviderId,
    this.resolveMerchantId,
    this.resolveFirestoreItemDocId,
    this.pendingMerchantChat,
  });

  @override
  State<MessagePageBackendApi> createState() => _MessagePageBackendApiState();
}

class _MessagePageBackendApiState extends State<MessagePageBackendApi> {
  String? _me;
  int? _myUserId;
  late String _chatId;
  int? _peerUserId;

  final _input = TextEditingController();
  final _scroll = ScrollController();

  bool _sending = false;
  bool _loading = true;
  bool _bootComplete = false;
  bool _resolvingChat = false;
  bool _wsConnected = false;
  bool _productTagAttached = false;
  String? _loadError;
  List<BackendChatMessage> _messages = [];
  Timer? _fallbackPollTimer;
  Timer? _readStatusPollTimer;
  StreamSubscription<BackendChatMessage>? _wsMessageSub;
  StreamSubscription<bool>? _wsConnectionSub;

  final _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  _PendingImage? _pendingImage;
  bool _uploadingImage = false;
  bool _uploadingAudio = false;
  bool _recording = false;
  int _recordMs = 0;
  Timer? _recordTimer;
  final Map<String, Uint8List> _localImageBytes = {};
  final Map<String, String> _localVoicePaths = {};
  final Map<String, int> _localVoiceDurations = {};

  static const _imgPrefix = 'img::';
  static const _audPrefix = 'aud::';
  static const _minVoiceMs = 800;
  static const _maxVoiceMs = 180000;
  static const _brandOrange = Color(0xFFFF8A00);
  static const _bg = Color(0xFFF3F4F7);
  static const _fallbackPollInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _chatId = widget.peerId.trim();
    _peerUserId = widget.peerUserId;
    _resolvingChat = _chatId.isEmpty;
    // Show seller chat chrome immediately (messages may still be loading).
    _bootComplete = widget.peerName.trim().isNotEmpty;

    if (_chatId.isNotEmpty) {
      BackendChatService.setActiveChatId(_chatId);
      BackendChatService.clearThreadUnread(_chatId);

      final cached = BackendChatService.peekCachedMessages(_chatId);
      if (cached.isNotEmpty) {
        _messages = cached;
        _loading = false;
        _bootComplete = true;
        if (_hasProductTagInMessages(_messages)) {
          _productTagAttached = true;
        }
      }
    }

    _boot();

    _input.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    _startRealtime();
  }

  void _startRealtime() {
    _wsMessageSub = BackendMessagingSocket.messageStream.listen((msg) {
      if (!mounted || _chatId.isEmpty || msg.chatId != _chatId) return;
      setState(() {
        _upsertMessage(msg);
        if (_hasProductTagInMessages(_messages)) {
          _productTagAttached = true;
        }
      });
      _scrollToBottom();
    });

    _wsConnectionSub =
        BackendMessagingSocket.connectionStream.listen((connected) {
      if (!mounted) return;
      setState(() => _wsConnected = connected);
      if (connected) {
        _fallbackPollTimer?.cancel();
        _fallbackPollTimer = null;
      } else {
        _startFallbackPoll();
      }
    });

    _startFallbackPoll();
    _readStatusPollTimer?.cancel();
    _readStatusPollTimer = Timer.periodic(const Duration(seconds: 18), (_) {
      if (mounted && !_sending && _chatId.isNotEmpty) {
        _loadMessages(silent: true);
      }
    });
  }

  void _startFallbackPoll() {
    _fallbackPollTimer?.cancel();
    if (BackendMessagingSocket.isConnected) return;
    _fallbackPollTimer = Timer.periodic(_fallbackPollInterval, (_) {
      if (mounted &&
          !_sending &&
          _chatId.isNotEmpty &&
          !BackendMessagingSocket.isConnected) {
        _loadMessages(silent: true);
      }
    });
  }

  @override
  void dispose() {
    BackendChatService.setActiveChatId(null);
    _fallbackPollTimer?.cancel();
    _readStatusPollTimer?.cancel();
    _recordTimer?.cancel();
    unawaited(_recorder.dispose());
    _wsMessageSub?.cancel();
    _wsConnectionSub?.cancel();
    if (_chatId.isNotEmpty) {
      unawaited(BackendMessagingSocket.leaveChat(_chatId));
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _resolveChatIfNeeded() async {
    if (_chatId.isNotEmpty) return true;

    setState(() {
      _resolvingChat = true;
      _loading = true;
      _loadError = null;
      // Show chat chrome immediately while resolve finishes.
      _bootComplete = true;
    });

    try {
      final result = await (widget.pendingMerchantChat ??
          BackendChatService.startMerchantChat(
            sqlItemId: widget.resolveSqlItemId,
            ownerId: widget.resolveOwnerId ?? widget.peerUserId,
            sellerUserId: widget.resolveSellerUserId,
            serviceProviderId: widget.resolveServiceProviderId,
            merchantId: widget.resolveMerchantId,
            firestoreItemDocId: widget.resolveFirestoreItemDocId,
          ));

      if (!mounted) return false;

      _chatId = result.chat.id;
      _peerUserId = result.sellerId;
      BackendChatService.setActiveChatId(_chatId);
      BackendChatService.clearThreadUnread(_chatId);

      final cached = BackendChatService.peekCachedMessages(_chatId);
      setState(() {
        _resolvingChat = false;
        if (cached.isNotEmpty) {
          _messages = cached;
          _loading = false;
          if (_hasProductTagInMessages(_messages)) {
            _productTagAttached = true;
          }
        }
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      final raw = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() {
        _resolvingChat = false;
        _loading = false;
        _loadError = raw;
        _bootComplete = false;
      });
      _toast(raw);
      return false;
    }
  }

  Future<void> _boot() async {
    try {
      unawaited(BackendMessagingSocket.connect().catchError((_) {}));

      // Warm local user id without blocking resolve.
      final prefsFuture = SharedPreferences.getInstance();
      unawaited(prefsFuture.then((prefs) {
        final cachedUserId = prefs.getInt('userId') ?? prefs.getInt('user_id');
        if (cachedUserId != null && cachedUserId > 0 && mounted) {
          setState(() {
            _myUserId = cachedUserId;
            _me = cachedUserId.toString();
            if (_chatId.isNotEmpty) _bootComplete = true;
          });
        }
      }).catchError((_) {}));

      // Resolve chat + auth in parallel when needed.
      final resolveFuture = _resolveChatIfNeeded();
      final authFuture = BackendChatService.ensureAuth();

      final resolved = await resolveFuture;
      if (!resolved || !mounted) return;

      BackendChatService.setActiveChatId(_chatId);

      final cached = BackendChatService.peekCachedMessages(_chatId);
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _messages = cached;
          _loading = false;
          _bootComplete = true;
          if (_hasProductTagInMessages(_messages)) {
            _productTagAttached = true;
          }
        });
      } else if (mounted) {
        setState(() => _bootComplete = true);
      }

      // Don't block message fetch on joinChat.
      unawaited(BackendMessagingSocket.joinChat(_chatId).then((_) {
        if (mounted) {
          setState(() => _wsConnected = BackendMessagingSocket.isConnected);
        }
      }).catchError((_) {
        if (mounted) setState(() => _wsConnected = false);
      }));

      await authFuture;
      final userId = await BackendChatService.getUserId();

      unawaited(_loadMessages(silent: cached.isNotEmpty));
      unawaited(_maybeSendProductEnquiry(userId));
      unawaited(_markUnreadAsRead(userId));

      if (!mounted) return;
      setState(() {
        _myUserId = userId;
        _me = userId.toString();
        _bootComplete = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _resolvingChat = false;
        _loadError = _friendlyError(e);
        _bootComplete = _messages.isNotEmpty;
      });
      if (_messages.isEmpty) _toast(_loadError!);
    }
  }

  ChatProductContext? get _activeProduct {
    return ChatProductContext.latestFromMessages(_messages) ??
        widget.productContext;
  }

  BackendChatMessage? get _latestProductTaggedMessage {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_productTagsFor(_messages[i]).isNotEmpty) return _messages[i];
    }
    return null;
  }

  bool get _isMerchantViewingEnquiry {
    final myId = _myUserId;
    final tagged = _latestProductTaggedMessage;
    if (myId == null || tagged == null) return false;
    return !tagged.isMine(myId);
  }

  String _enquiryClientMessageId(String productId) =>
      'mp-enquiry-${_chatId}-$productId';

  bool _hasExistingProductEnquiry(int myUserId, String productId) {
    if (_hasProductTagInMessages(_messages, productId: productId)) {
      return true;
    }

    final enquiryClientId = _enquiryClientMessageId(productId);
    for (final msg in _messages) {
      if (msg.clientMessageId == enquiryClientId) return true;
      if (!msg.isMine(myUserId)) continue;
      final text = (msg.content ?? '').trim().toLowerCase();
      if (!text.contains("interested in this item")) continue;
      if (_productTagsFor(msg).any((t) => '${t['tagId']}' == productId)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _maybeSendProductEnquiry(int myUserId) async {
    if (!widget.sendProductEnquiry) return;

    final product = widget.productContext;
    if (product == null) return;

    if (_hasExistingProductEnquiry(myUserId, product.productId)) {
      _productTagAttached = true;
      return;
    }

    const enquiryText = "Hi, I'm interested in this item.";
    final clientMessageId = _enquiryClientMessageId(product.productId);
    try {
      final saved = await BackendChatService.sendMessage(
        chatId: _chatId,
        content: enquiryText,
        type: 'text',
        tags: [product.toMessageTag()],
        clientMessageId: clientMessageId,
        metadata: {
          'source': 'marketplace',
          'productId': product.productId,
          'autoEnquiry': true,
        },
      );
      if (!mounted) return;
      setState(() {
        _upsertMessage(saved);
        _productTagAttached = true;
      });
      BackendChatService.refreshThreads();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      // Buyer can still attach the product on their first manual message.
    }
  }

  String _friendlyError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('401') || raw.contains('unauthorized')) {
      return 'Session expired. Please log in again.';
    }
    if (raw.contains('403') || raw.contains('forbidden') || raw.contains('participant')) {
      return 'You do not have access to this chat.';
    }
    if (raw.contains('socket') || raw.contains('network') || raw.contains('timeout')) {
      return 'Connection problem. Check your internet and try again.';
    }
    return 'Could not load messages. Pull to retry.';
  }

  Future<void> _loadMessages({bool silent = false}) async {
    try {
      final messages = await BackendChatService.getMessages(_chatId);
      if (!mounted) return;
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      setState(() {
        _messages = _mergeWithPending(messages);
        _loading = false;
        _loadError = null;
        if (_hasProductTagInMessages(_messages)) {
          _productTagAttached = true;
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } catch (e) {
      if (!mounted) return;
      final msg = _friendlyError(e);
      setState(() {
        _loading = false;
        if (!silent || _messages.isEmpty) _loadError = msg;
      });
      if (!silent) _toast(msg);
    }
  }

  Future<void> _markUnreadAsRead(int myUserId) async {
    final unreadIds = _messages
        .where((m) => !m.isMine(myUserId))
        .map((m) => m.id)
        .where((id) => id.isNotEmpty)
        .toList();
    if (unreadIds.isEmpty) return;
    try {
      await BackendChatService.markRead(
        chatId: _chatId,
        messageIds: unreadIds,
      );
      BackendChatService.clearThreadUnread(_chatId);
      BackendChatService.refreshThreads();
    } catch (_) {}
  }

  List<BackendChatMessage> _mergeWithPending(List<BackendChatMessage> server) {
    final myId = _myUserId;
    if (myId == null) return server;

    final pending = _messages.where((m) => m.status == 'pending').toList();
    if (pending.isEmpty) return server;

    final merged = List<BackendChatMessage>.from(server);
    for (final p in pending) {
      final alreadySaved = server.any((s) => _isSameMessage(s, p, myId));
      if (!alreadySaved) merged.add(p);
    }
    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  bool _isSameMessage(
    BackendChatMessage a,
    BackendChatMessage b,
    int myId,
  ) {
    if (a.id.isNotEmpty && a.id == b.id) return true;
    if (a.clientMessageId != null &&
        a.clientMessageId == b.clientMessageId) {
      return true;
    }
    return a.isMine(myId) &&
        b.isMine(myId) &&
        a.content == b.content &&
        a.createdAt.difference(b.createdAt).inSeconds.abs() < 30;
  }

  void _upsertMessage(BackendChatMessage msg) {
    final idx = _messages.indexWhere(
      (m) =>
          m.id == msg.id ||
          (msg.clientMessageId != null &&
              m.clientMessageId == msg.clientMessageId) ||
          (m.status == 'pending' &&
              msg.clientMessageId != null &&
              m.id == msg.clientMessageId),
    );

    if (idx >= 0) {
      _messages[idx] = msg;
    } else {
      _messages.add(msg);
    }
    _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  bool _hasProductTagInMessages(
    List<BackendChatMessage> messages, {
    String? productId,
  }) {
    final id = productId ?? widget.productContext?.productId;
    if (id == null) return false;
    for (final msg in messages) {
      final tags = msg.tags ?? const [];
      for (final tag in tags) {
        if (tag['tagType'] == 'product' && '${tag['tagId']}' == id) {
          return true;
        }
      }
    }
    return false;
  }

  Future<String> _currentSenderDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in ['name', 'displayName', 'username']) {
      final raw = prefs.getString(key)?.trim() ?? '';
      if (raw.isNotEmpty) return raw;
    }

    final fromToken = await AuthStorage.userNameFromToken();
    if (fromToken != null && fromToken.trim().isNotEmpty) {
      final t = fromToken.trim();
      return t.contains('@') ? t.split('@').first : t;
    }

    final fb = FirebaseAuth.instance.currentUser?.displayName?.trim();
    if (fb != null && fb.isNotEmpty) return fb;

    final email = prefs.getString('email') ??
        FirebaseAuth.instance.currentUser?.email;
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }

    return 'Someone';
  }

  Future<void> _pushNotifyPeer({required String body}) async {
    try {
      final senderName = await _currentSenderDisplayName();
      await ChatNotificationService.notifyRecipientOfMessage(
        chatId: _chatId,
        senderName: senderName,
        body: body,
        recipientFirebaseUid: widget.peerMerchantId,
        recipientUserId: _peerUserId,
      );
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    if (_sending || _uploadingImage || _uploadingAudio || _recording) return;

    final content = _input.text.trim();
    final pendingImage = _pendingImage;
    if (content.isEmpty && pendingImage == null) return;

    final myId = _myUserId;
    if (myId == null) return;

    if (pendingImage != null) {
      await _sendImageMessage(pendingImage, caption: content);
      return;
    }

    final product = widget.productContext;
    final attachProductTag =
        product != null && !_productTagAttached;
    final tags = attachProductTag ? [product.toMessageTag()] : null;

    final clientMessageId = const Uuid().v4();
    final pending = BackendChatMessage(
      id: clientMessageId,
      chatId: _chatId,
      senderId: myId,
      content: content,
      type: 'text',
      status: 'pending',
      createdAt: DateTime.now(),
      tags: tags,
      clientMessageId: clientMessageId,
    );

    setState(() {
      _sending = true;
      _messages = [..._messages, pending];
    });
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    try {
      final saved = await BackendChatService.sendMessage(
        chatId: _chatId,
        content: content,
        type: 'text',
        tags: tags,
        clientMessageId: clientMessageId,
        metadata: attachProductTag
            ? {'source': 'marketplace', 'productId': product.productId}
            : null,
      );

      if (attachProductTag) _productTagAttached = true;

      if (mounted) {
        setState(() {
          _upsertMessage(saved);
          _sending = false;
        });
        BackendChatService.refreshThreads();
        unawaited(_pushNotifyPeer(body: content));
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _messages =
            _messages.where((m) => m.clientMessageId != clientMessageId).toList();
        _input.text = content;
      });
      _toast('Failed to send message: $e');
    }
  }

  Future<void> _sendImageMessage(
    _PendingImage image, {
    String caption = '',
  }) async {
    final myId = _myUserId;
    if (myId == null) return;

    final clientMessageId = const Uuid().v4();
    final pending = BackendChatMessage(
      id: clientMessageId,
      chatId: _chatId,
      senderId: myId,
      content: caption,
      type: 'image',
      status: 'pending',
      createdAt: DateTime.now(),
      clientMessageId: clientMessageId,
    );

    setState(() {
      _localImageBytes[clientMessageId] = image.bytes;
      _messages = [..._messages, pending];
      _pendingImage = null;
      _uploadingImage = true;
      _sending = true;
    });
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    try {
      final url = await _uploadImageBytes(image);
      final saved = await BackendChatService.sendImageMessage(
        chatId: _chatId,
        imageUrl: url,
        caption: caption,
        clientMessageId: clientMessageId,
        mimeType: image.mime,
      );

      if (!mounted) return;
      setState(() {
        _localImageBytes.remove(clientMessageId);
        _upsertMessage(saved);
        _sending = false;
        _uploadingImage = false;
      });
      BackendChatService.refreshThreads();
      unawaited(_pushNotifyPeer(body: caption.isNotEmpty ? caption : '📷 Photo'));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _localImageBytes.remove(clientMessageId);
        _messages = _messages
            .where((m) => m.clientMessageId != clientMessageId)
            .toList();
        _sending = false;
        _uploadingImage = false;
        _pendingImage = image;
        if (caption.isNotEmpty) _input.text = caption;
      });
      _toast(_friendlyImageError(e));
    }
  }

  String _friendlyImageError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('upload failed')) {
      return 'Could not upload photo. Check your connection.';
    }
    if (raw.contains('400')) {
      return 'Server rejected the image. Trying again may help.';
    }
    return 'Failed to send image. Please try again.';
  }

  Future<String> _uploadImageBytes(_PendingImage image) async {
    try {
      final ref = FirebaseStorage.instance.ref().child(
            'chat_media/${_chatId}/'
            '${DateTime.now().millisecondsSinceEpoch}_${image.filename}',
          );
      await ref.putData(
        image.bytes,
        SettableMetadata(contentType: image.mime),
      );
      return ref.getDownloadURL();
    } catch (_) {
      return BackendChatService.uploadChatAttachment(
        bytes: image.bytes,
        filename: image.filename,
        mimeType: image.mime,
      );
    }
  }

  Future<User> _requireFirebaseUserForStorage() async {
    await BackendChatService.ensureAuth();
    await AuthHandler.refreshFirebaseTokenIfSignedIn();
    return AuthHandler.requireUserForFirestore();
  }

  Future<String> _uploadAudioBytes(Uint8List bytes, String uid) async {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) {
      throw StateError('Firebase sign-in required to send voice notes');
    }

    final objectName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final ref = FirebaseStorage.instance
        .ref()
        .child('voice_notes/$safeUid/$objectName');

    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'audio/mp4'),
    );
    return ref.getDownloadURL();
  }

  String _formatRecordMs(int ms) {
    final s = (ms / 1000).floor();
    final m = (s / 60).floor();
    final r = s % 60;
    return '${m.toString().padLeft(1, '0')}:${r.toString().padLeft(2, '0')}';
  }

  Future<void> _startVoiceRecording() async {
    if (_myUserId == null) return;
    if (_sending || _uploadingImage || _uploadingAudio || _recording) return;
    if (kIsWeb) {
      _toast('Voice notes are not supported on web yet.');
      return;
    }

    try {
      var ok = await _recorder.hasPermission();
      if (!ok) {
        final status = await Permission.microphone.request();
        ok = status.isGranted;
      }
      if (!ok) {
        _toast('Microphone permission is required for voice notes.');
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _recordTimer?.cancel();
      _recordMs = 0;
      setState(() => _recording = true);
      _recordTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        final next = _recordMs + 200;
        if (next >= _maxVoiceMs) {
          unawaited(_stopVoiceRecordingAndSend());
          return;
        }
        setState(() => _recordMs = next);
      });
    } catch (_) {
      _toast('Could not start recording');
    }
  }

  Future<void> _cancelVoiceRecording() async {
    _recordTimer?.cancel();
    try {
      await _recorder.cancel();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordMs = 0;
    });
  }

  Future<void> _stopVoiceRecordingAndSend() async {
    if (_myUserId == null || !_recording) return;

    _recordTimer?.cancel();
    final capturedMs = _recordMs;
    setState(() {
      _recording = false;
      _recordMs = 0;
    });

    if (capturedMs < _minVoiceMs) {
      try {
        await _recorder.cancel();
      } catch (_) {}
      _toast('Hold longer to record a voice note.');
      return;
    }

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      _toast('Recording failed');
      return;
    }

    if (path == null || path.isEmpty) {
      _toast('Recording failed');
      return;
    }

    await _sendVoiceMessage(path, capturedMs);
  }

  Future<void> _sendVoiceMessage(String filePath, int durationMs) async {
    final myId = _myUserId;
    if (myId == null) return;

    final clientMessageId = const Uuid().v4();
    final pending = BackendChatMessage(
      id: clientMessageId,
      chatId: _chatId,
      senderId: myId,
      content: 'Voice note',
      type: 'audio',
      status: 'pending',
      createdAt: DateTime.now(),
      clientMessageId: clientMessageId,
    );

    setState(() {
      _localVoicePaths[clientMessageId] = filePath;
      _localVoiceDurations[clientMessageId] = durationMs;
      _messages = [..._messages, pending];
      _uploadingAudio = true;
      _sending = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    try {
      final firebaseUser = await _requireFirebaseUserForStorage();
      final bytes = await File(filePath).readAsBytes();
      final url = await _uploadAudioBytes(bytes, firebaseUser.uid);
      final saved = await BackendChatService.sendAudioMessage(
        chatId: _chatId,
        audioUrl: url,
        durationMs: durationMs,
        clientMessageId: clientMessageId,
        mimeType: 'audio/mp4',
      );

      if (!mounted) return;
      setState(() {
        _localVoicePaths.remove(clientMessageId);
        _localVoiceDurations.remove(clientMessageId);
        _upsertMessage(saved);
        _sending = false;
        _uploadingAudio = false;
      });
      BackendChatService.refreshThreads();
      unawaited(_pushNotifyPeer(body: '🎤 Voice message'));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _localVoicePaths.remove(clientMessageId);
        _localVoiceDurations.remove(clientMessageId);
        _messages = _messages
            .where((m) => m.clientMessageId != clientMessageId)
            .toList();
        _sending = false;
        _uploadingAudio = false;
      });
      _showVoiceErrorToast(e);
    } finally {
      try {
        await File(filePath).delete();
      } catch (_) {}
    }
  }

  void _showVoiceErrorToast(Object e) {
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint('[VoiceNote] send failed: $e');
    }
    ToastHelper.showCustomToast(
      context,
      "Couldn't send your VN",
      isSuccess: false,
      errorMessage: '',
    );
  }

  void _scrollToBottom() {
    if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _within5Min(BackendChatMessage m) =>
      DateTime.now().difference(m.createdAt) <= const Duration(minutes: 5);

  bool _isEditableText(BackendChatMessage m) {
    final content = (m.content ?? '').trim();
    if (content.startsWith(_audPrefix) || content.startsWith(_imgPrefix)) {
      return false;
    }
    return m.type == 'text' && content.isNotEmpty;
  }

  String? _messageImageUrl(BackendChatMessage m) {
    if (m.type == 'audio') return null;
    final content = m.content?.trim() ?? '';
    if (content.startsWith(_audPrefix)) return null;
    if (content.startsWith(_imgPrefix)) {
      final firstLine = content.split('\n').first.trim();
      final url = firstLine.substring(_imgPrefix.length).trim();
      if (url.startsWith('http')) return url;
    }
    if (m.type == 'image') {
      if (content.startsWith('http://') || content.startsWith('https://')) {
        return content;
      }
    }
    final atts = m.attachments;
    if (atts != null && atts.isNotEmpty) {
      for (final att in atts) {
        final url = att['url']?.toString().trim();
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  Uint8List? _localImageFor(BackendChatMessage m) {
    final key = m.clientMessageId ?? m.id;
    return _localImageBytes[key];
  }

  String? _visibleCaption(BackendChatMessage m, String? imageUrl) {
    final content = m.content?.trim() ?? '';
    if (content.isEmpty) return null;
    if (content.startsWith(_audPrefix)) return null;
    if (m.type == 'audio') return null;
    if (content.startsWith(_imgPrefix)) {
      final parts = content.split('\n');
      if (parts.length < 2) return null;
      final caption = parts.sublist(1).join('\n').trim();
      return caption.isEmpty ? null : caption;
    }
    if (imageUrl != null && content == imageUrl) return null;
    if (m.type == 'image' && content.startsWith('http')) return null;
    return content;
  }

  _VoiceNoteInfo? _messageAudio(BackendChatMessage m) {
    final content = m.content?.trim() ?? '';
    if (content.startsWith(_audPrefix)) {
      final body = content.substring(_audPrefix.length).trim();
      final parts = body.split('|');
      final url = parts.first.trim();
      final ms = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
      if (url.startsWith('http')) {
        return _VoiceNoteInfo(url: url, durationMs: ms);
      }
    }

    if (m.type == 'audio') {
      String? url;
      var durationMs = 0;
      if (content.startsWith('http://') || content.startsWith('https://')) {
        url = content;
      }
      final atts = m.attachments;
      if (atts != null) {
        for (final att in atts) {
          final rawUrl = att['url']?.toString().trim();
          if (rawUrl != null && rawUrl.isNotEmpty) {
            url = rawUrl;
            final rawDur = att['durationMs'];
            if (rawDur is int) {
              durationMs = rawDur;
            } else if (rawDur != null) {
              durationMs = int.tryParse(rawDur.toString()) ?? durationMs;
            }
          }
        }
      }
      if (url != null && url.isNotEmpty) {
        return _VoiceNoteInfo(url: url, durationMs: durationMs);
      }
    }
    return null;
  }

  String? _localVoicePathFor(BackendChatMessage m) {
    final key = m.clientMessageId ?? m.id;
    return _localVoicePaths[key];
  }

  int _voiceDurationFor(BackendChatMessage m, _VoiceNoteInfo? audio) {
    final key = m.clientMessageId ?? m.id;
    return _localVoiceDurations[key] ?? audio?.durationMs ?? 0;
  }

  Future<void> _showMsgActions(BackendChatMessage m) async {
    final myId = _myUserId;
    if (myId == null || !m.isMine(myId) || !_within5Min(m)) return;
    if (m.status == 'pending') return;

    final canEdit = _isEditableText(m);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit message'),
                onTap: () async {
                  Navigator.pop(context);
                  await _editMessage(m);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
              title: const Text(
                'Delete message',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _deleteMessage(m);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMessage(BackendChatMessage m) async {
    final ok = await showModernConfirmDialog(
      context,
      title: 'Delete message?',
      message: 'This message will be removed for everyone. You can only delete within 5 minutes.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;

    try {
      await BackendChatService.deleteMessage(
        chatId: _chatId,
        messageId: m.id,
      );
      if (!mounted) return;
      setState(() {
        _messages = _messages.where((x) => x.id != m.id).toList();
      });
      BackendChatService.refreshThreads();
    } catch (e) {
      _toast('Could not delete message: $e');
    }
  }

  Future<void> _editMessage(BackendChatMessage m) async {
    final updated = await showModernEditDialog(
      context,
      title: 'Edit message',
      initialText: m.content ?? '',
    );
    if (updated == null || updated.isEmpty || updated == m.content) return;

    try {
      final saved = await BackendChatService.editMessage(
        chatId: _chatId,
        messageId: m.id,
        newContent: updated,
      );
      if (!mounted) return;
      setState(() => _upsertMessage(saved));
      BackendChatService.refreshThreads();
    } catch (e) {
      _toast('Could not edit message: $e');
    }
  }

  void _viewImage(String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: ResilientCachedNetworkImage(
                  url: url,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearChat() async {
    final ok = await showModernConfirmDialog(
      context,
      title: 'Clear chat?',
      message:
          'All messages in this conversation will be removed from your device.',
      confirmLabel: 'Clear',
    );
    if (!ok || !mounted) return;

    try {
      await BackendChatService.clearChatHistory(_chatId);
      if (!mounted) return;
      setState(() {
        _messages = [];
        _pendingImage = null;
      });
      BackendChatService.refreshThreads();
      _toast('Chat cleared');
    } catch (e) {
      _toast('Could not clear chat: $e');
    }
  }

  void _showAttachSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _attachTile(
                      icon: Icons.photo_library_rounded,
                      title: 'Gallery',
                      color: const Color(0xFF27AE60),
                      onTap: () {
                        Navigator.pop(context);
                        _pickFromGallery();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _attachTile(
                      icon: Icons.photo_camera_rounded,
                      title: 'Camera',
                      color: const Color(0xFF16284C),
                      onTap: () {
                        Navigator.pop(context);
                        _pickFromCamera();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1280,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final image = _PendingImage(
        bytes: bytes,
        filename: file.name.isEmpty ? 'image.jpg' : file.name,
        mime: lookupMimeType(file.name, headerBytes: bytes) ?? 'image/jpeg',
      );
      await _sendImageMessage(image, caption: _input.text.trim());
    } catch (_) {
      _toast('Could not pick image');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1280,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final image = _PendingImage(
        bytes: bytes,
        filename: file.name.isEmpty ? 'camera.jpg' : file.name,
        mime: lookupMimeType(file.name, headerBytes: bytes) ?? 'image/jpeg',
      );
      await _sendImageMessage(image, caption: _input.text.trim());
    } catch (_) {
      _toast('Camera not available');
    }
  }

  String _timeLabel(BackendChatMessage m) {
    return DateFormat('HH:mm').format(m.createdAt);
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(dt.year, dt.month, dt.day);

    if (msgDate == today) {
      return 'Today';
    } else if (msgDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, yyyy').format(dt);
    }
  }

  bool _isDifferentDay(
      BackendChatMessage current, BackendChatMessage? previous) {
    if (previous == null) return true;
    final curr = DateTime(
        current.createdAt.year, current.createdAt.month, current.createdAt.day);
    final prev = DateTime(previous.createdAt.year, previous.createdAt.month,
        previous.createdAt.day);
    return curr != prev;
  }

  String? _resolvedMerchantId() {
    final direct = widget.peerMerchantId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final fromProduct = widget.productContext?.merchantId?.trim();
    if (fromProduct != null && fromProduct.isNotEmpty) return fromProduct;
    final active = _activeProduct?.merchantId?.trim();
    if (active != null && active.isNotEmpty) return active;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final tags = _messages[i].tags ?? const [];
      for (final tag in tags) {
        if (tag['tagType'] != 'product') continue;
        final meta = tag['metadata'];
        if (meta is Map) {
          final mid = meta['merchantId']?.toString().trim();
          if (mid != null && mid.isNotEmpty) return mid;
          final sp = meta['serviceProviderId']?.toString().trim();
          if (sp != null && sp.isNotEmpty) return sp;
        }
      }
    }
    return null;
  }

  Future<void> _openMerchantProfile() async {
    var merchantId = _resolvedMerchantId();
    if (merchantId == null || merchantId.isEmpty) {
      final peerUserId = _peerUserId;
      if (peerUserId != null && peerUserId > 0) {
        merchantId =
            await BackendChatService.getFirebaseUidByUserId(peerUserId);
      }
    }
    if (merchantId == null || merchantId.isEmpty) {
      _toast('Seller shop is not available for this chat.');
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MerchantProductsPage(
          merchantId: merchantId!,
          merchantName: widget.peerName,
        ),
      ),
    );
  }

  int? _lastOutgoingMessageIndex() {
    final myId = _myUserId;
    if (myId == null) return null;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.isMine(myId) && m.status != 'pending') return i;
    }
    return null;
  }

  bool _isMessageRead(BackendChatMessage m) =>
      m.status == 'read' || m.readAt != null;

  bool _isMessageDelivered(BackendChatMessage m) =>
      _isMessageRead(m) ||
      m.status == 'delivered' ||
      m.deliveredAt != null;

  Widget _buildMessageReceipt(BackendChatMessage msg, bool isLastOutgoing) {
    final read = _isMessageRead(msg);
    final delivered = _isMessageDelivered(msg);
    final tickColor = read
        ? const Color(0xFF53BDEB)
        : (delivered ? const Color(0xFF9CA3AF) : const Color(0xFF9CA3AF));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          delivered ? Icons.done_all_rounded : Icons.check_rounded,
          size: 15,
          color: tickColor,
        ),
        if (isLastOutgoing && read) ...[
          const SizedBox(width: 4),
          Text(
            'Seen',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: tickColor,
            ),
          ),
        ],
      ],
    );
  }

  PreferredSizeWidget _buildModernAppBar({
    required String title,
    required ChatProductContext? activeProduct,
  }) {
    const ink = Color(0xFF101010);
    final subtitle = activeProduct != null
        ? 'View shop · ${activeProduct.name}'
        : (_wsConnected ? 'Online' : 'Connecting…');

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      titleSpacing: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFECEEF2)),
      ),
      title: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openMerchantProfile,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                _avatar(widget.peerAvatarUrl, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (activeProduct == null) ...[
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: _wsConnected
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 6),
                          ] else ...[
                            Icon(
                              Icons.storefront_outlined,
                              size: 13,
                              color: _brandOrange.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: activeProduct != null
                                    ? _brandOrange
                                    : const Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Voice call',
          onPressed: _me == null ? null : () {},
          icon: const Icon(Icons.call_outlined, color: ink),
        ),
        IconButton(
          tooltip: 'Video call',
          onPressed: _me == null ? null : () {},
          icon: const Icon(Icons.videocam_outlined, color: ink),
        ),
        IconButton(
          tooltip: 'View shop',
          onPressed: _openMerchantProfile,
          icon: Icon(
            Icons.storefront_outlined,
            color: _brandOrange.withValues(alpha: 0.95),
          ),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: ink),
          onSelected: (value) {
            if (value == 'clear') _confirmClearChat();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.delete_sweep_outlined, size: 20),
                  SizedBox(width: 10),
                  Text('Clear chat'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep seller chrome visible while chat/messages resolve (feels much faster).
    if (_messages.isEmpty &&
        _loadError == null &&
        !_bootComplete &&
        widget.peerName.trim().isEmpty) {
      return const ChatBootLoadingScaffold();
    }

    final activeProduct = _activeProduct;
    final title = widget.peerName;
    final hasText = _input.text.trim().isNotEmpty;
    final hasPendingImage = _pendingImage != null;
    final canSend = (hasText || hasPendingImage) &&
        _chatId.isNotEmpty &&
        !_resolvingChat &&
        !_sending &&
        !_uploadingImage &&
        !_uploadingAudio &&
        !_recording;

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildModernAppBar(title: title, activeProduct: activeProduct),
      body: Column(
        children: [
          Expanded(child: _buildMessagesPane(activeProduct)),
          if (activeProduct != null) _buildDiscussedProductBar(activeProduct),
          _buildInputArea(canSend: canSend),
        ],
      ),
    );
  }

  Widget _buildMessagesPane(ChatProductContext? activeProduct) {
    if (_loading && _messages.isEmpty && _loadError == null) {
      return const ChatScreenLoadingSkeleton(includeHeaderStrip: false);
    }

    if (_loadError != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Colors.black54),
              const SizedBox(height: 12),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _loadError = null;
                  });
                  if (_chatId.isEmpty) {
                    unawaited(_boot());
                  } else {
                    unawaited(_loadMessages());
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _brandOrange,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _ChatBgPainter())),
        Column(
          children: [
            if (_isMerchantViewingEnquiry && activeProduct != null)
              _buildMerchantEnquiryBanner(activeProduct),
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'Say hi 👋',
                        style: TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) =>
                          _buildMessageTile(_messages[i], i),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessageTile(BackendChatMessage msg, int index) {
    final prevMsg = index > 0 ? _messages[index - 1] : null;
    final myId = _myUserId;
    final isMine = myId != null && msg.isMine(myId);
    final isPending = msg.status == 'pending';
    final showDateSeparator = _isDifferentDay(msg, prevMsg);
    final localBytes = _localImageFor(msg);
    final imageUrl = localBytes == null ? _messageImageUrl(msg) : null;
    final caption = _visibleCaption(msg, imageUrl);
    final audio = _messageAudio(msg);
    final localVoicePath = _localVoicePathFor(msg);
    final voiceDuration = _voiceDurationFor(msg, audio);
    final canAct = isMine && _within5Min(msg) && !isPending;
    final isLastOutgoing = isMine && index == _lastOutgoingMessageIndex();

    final bubble = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine)
            _avatar(widget.peerAvatarUrl, size: 28)
          else
            const SizedBox(width: 28),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isPending ? 0.72 : 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isMine ? _brandOrange : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMine ? 18 : 6),
                        bottomRight: Radius.circular(isMine ? 6 : 18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._productTagsFor(msg).map(
                          (tag) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _productTagChip(
                              tag,
                              isMine: isMine,
                            ),
                          ),
                        ),
                        if (localBytes != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              localBytes,
                              width: 220,
                              height: 180,
                              fit: BoxFit.cover,
                            ),
                          ),
                          if (caption != null) const SizedBox(height: 8),
                        ] else if (imageUrl != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: GestureDetector(
                              onTap: () => _viewImage(imageUrl),
                              child: ResilientCachedNetworkImage(
                                url: imageUrl,
                                width: 220,
                                height: 180,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          if (caption != null) const SizedBox(height: 8),
                        ],
                        if (audio != null || localVoicePath != null) ...[
                          VoiceNoteBubble(
                            messageId: msg.clientMessageId ?? msg.id,
                            url: audio?.url ?? '',
                            localPath: localVoicePath,
                            durationMs: voiceDuration,
                            isMine: isMine,
                          ),
                        ],
                        if (caption != null &&
                            audio == null &&
                            localVoicePath == null)
                          Text(
                            caption,
                            style: TextStyle(
                              color: isMine ? Colors.white : Colors.black87,
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                        if (caption == null &&
                            localBytes == null &&
                            imageUrl == null &&
                            audio == null &&
                            localVoicePath == null &&
                            _productTagsFor(msg).isNotEmpty)
                          Text(
                            'Shared a product',
                            style: TextStyle(
                              color: isMine ? Colors.white70 : Colors.black54,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _timeLabel(msg),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                    if (isPending) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: isMine
                              ? _brandOrange.withValues(alpha: 0.7)
                              : Colors.black38,
                        ),
                      ),
                    ],
                    if (isMine && !isPending) ...[
                      const SizedBox(width: 6),
                      _buildMessageReceipt(msg, isLastOutgoing),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );

    return Column(
      children: [
        if (showDateSeparator) ...[
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _dateLabel(msg.createdAt),
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        GestureDetector(
          onLongPress: canAct ? () => _showMsgActions(msg) : null,
          child: bubble,
        ),
      ],
    );
  }

  Widget _buildMerchantEnquiryBanner(ChatProductContext product) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _brandOrange.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined, color: _brandOrange, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Marketplace enquiry',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.peerName} is asking about "${product.name}".',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _checkoutItemIdFromProduct(ChatProductContext product) {
    final parsed = int.tryParse(product.productId.trim());
    if (parsed != null && parsed > 0) return parsed;
    var hash = 0;
    for (final code in product.productId.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  core.MarketplaceDetailModel _checkoutItemFromProduct(
    ChatProductContext product,
  ) {
    final merchantId = (product.merchantId ?? widget.peerMerchantId ?? '')
        .trim();
    return core.MarketplaceDetailModel(
      id: _checkoutItemIdFromProduct(product),
      name: product.name,
      image: product.image ?? '',
      price: product.price ?? 0,
      description: product.description ?? '',
      location: '',
      merchantId: merchantId.isEmpty ? null : merchantId,
      merchantName: widget.peerName.trim().isEmpty ? null : widget.peerName,
      serviceType: 'marketplace',
    );
  }

  Future<void> _openBuyNowCheckout(ChatProductContext product) async {
    if (_isMerchantViewingEnquiry) return;
    final item = _checkoutItemFromProduct(product);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CheckoutPage(item: item)),
    );
  }

  Widget _buildDiscussedProductBar(ChatProductContext product) {
    final isMerchant = _isMerchantViewingEnquiry;
    return Material(
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.grey.shade200),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _openMerchantProfile,
                child: Row(
                  children: [
                    _productThumb(product.image, size: 54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMerchant
                                ? 'Customer is viewing'
                                : 'You are enquiring about',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          if (product.price != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              _formatPrice(product.price!),
                              style: const TextStyle(
                                color: _brandOrange,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isMerchant)
              Icon(
                Icons.storefront_outlined,
                color: _brandOrange.withOpacity(0.85),
              )
            else
              FilledButton(
                onPressed: () => _openBuyNowCheckout(product),
                style: FilledButton.styleFrom(
                  backgroundColor: _brandOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Buy Now',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _productTagsFor(BackendChatMessage msg) {
    final tags = msg.tags ?? const [];
    return tags
        .where((t) => t['tagType'] == 'product')
        .map((t) => Map<String, dynamic>.from(t))
        .toList();
  }

  Widget _productTagChip(Map<String, dynamic> tag, {required bool isMine}) {
    final name = '${tag['tagName'] ?? 'Product'}';
    final image = tag['tagImage']?.toString();
    final price = tag['metadata'] is Map
        ? (tag['metadata'] as Map)['price']
        : null;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMine ? Colors.white.withOpacity(0.15) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _productThumb(image, size: 40),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isMine ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                if (price != null)
                  Text(
                    _formatPrice((price is num) ? price.toDouble() : 0),
                    style: TextStyle(
                      color: isMine ? Colors.white70 : _brandOrange,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _productThumb(String? url, {required double size}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: Colors.grey.shade200,
        child: url != null && url.isNotEmpty
            ? ResilientCachedNetworkImage(
                url: url,
                fit: BoxFit.cover,
                width: size,
                height: size,
              )
            : Icon(Icons.shopping_bag_outlined, size: size * 0.5),
      ),
    );
  }

  String _formatPrice(double price) {
    return NumberFormat.simpleCurrency(name: 'MWK', decimalDigits: 0)
        .format(price);
  }

  Widget _buildInputArea({required bool canSend}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_recording) _buildRecordingBar(),
            if (_pendingImage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        _pendingImage!.bytes,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Photo ready to send',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _pendingImage = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            if (_uploadingImage || _uploadingAudio)
              const LinearProgressIndicator(
                minHeight: 2,
                color: _brandOrange,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Material(
                    color: const Color(0xFFF3F4F7),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: (_sending ||
                              _uploadingImage ||
                              _uploadingAudio ||
                              _recording)
                          ? null
                          : _showAttachSheet,
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.add_rounded, color: Colors.black54),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F7),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                      child: TextField(
                        controller: _input,
                        maxLines: 5,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: _pendingImage != null
                              ? 'Add a caption…'
                              : 'Type a message…',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: canSend ? (_) => _sendMessage() : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (canSend || _sending || _uploadingImage || _uploadingAudio)
                    AnimatedScale(
                      scale: canSend || _sending || _uploadingImage || _uploadingAudio
                          ? 1
                          : 0.92,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: canSend ||
                                  _sending ||
                                  _uploadingImage ||
                                  _uploadingAudio
                              ? const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFFF9A2E),
                                    Color(0xFFFF8A00),
                                  ],
                                )
                              : null,
                          color: canSend ||
                                  _sending ||
                                  _uploadingImage ||
                                  _uploadingAudio
                              ? null
                              : const Color(0xFFE4E6EB),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: canSend ||
                                  _sending ||
                                  _uploadingImage ||
                                  _uploadingAudio
                              ? [
                                  BoxShadow(
                                    color:
                                        _brandOrange.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: canSend ? _sendMessage : null,
                            borderRadius: BorderRadius.circular(24),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: _sending ||
                                        _uploadingImage ||
                                        _uploadingAudio
                                    ? const SizedBox(
                                        key: ValueKey('sending'),
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        key: const ValueKey('send'),
                                        Icons.arrow_upward_rounded,
                                        color: canSend
                                            ? Colors.white
                                            : Colors.grey.shade500,
                                        size: 22,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: _recording ? null : _startVoiceRecording,
                      onLongPressStart: (_) => _startVoiceRecording(),
                      onLongPressEnd: (_) => _stopVoiceRecordingAndSend(),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFF9A2E),
                              Color(0xFFFF8A00),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: _brandOrange.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.mic_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Recording ${_formatRecordMs(_recordMs)}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFFB91C1C),
              ),
            ),
          ),
          TextButton(
            onPressed: _sending ? null : _cancelVoiceRecording,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: _sending ? null : _stopVoiceRecordingAndSend,
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String? url, {double size = 40}) {
    final initials = _getInitials(widget.peerName);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[300],
      ),
      child: url != null && url.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(size / 2),
              child: ResilientCachedNetworkImage(
                url: url,
                fit: BoxFit.cover,
                width: size,
                height: size,
              ),
            )
          : Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
            ),
    );
  }

  String _getInitials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _PendingImage {
  final Uint8List bytes;
  final String filename;
  final String mime;

  const _PendingImage({
    required this.bytes,
    required this.filename,
    required this.mime,
  });
}

class _VoiceNoteInfo {
  final String url;
  final int durationMs;

  const _VoiceNoteInfo({
    required this.url,
    required this.durationMs,
  });
}

class _ChatBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF3F4F7)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
