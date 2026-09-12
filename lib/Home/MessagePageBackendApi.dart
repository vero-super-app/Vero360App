import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:vero360_app/GeneralModels/call_model.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/GernalServices/call_service_impl.dart';
import 'package:vero360_app/GernalServices/chat_outbox.dart';
import 'package:vero360_app/GernalServices/chat_notification_service.dart';
import 'package:vero360_app/GernalServices/chat_receipt_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/GeneralModels/chat_product_context.dart';
import 'package:vero360_app/widgets/modern_confirm_dialog.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';
import 'package:vero360_app/utils/user_facing_error.dart';
import 'package:vero360_app/widgets/messaging_skeleton_loaders.dart';
import 'package:vero360_app/widgets/voice_note_bubble.dart';
import 'package:vero360_app/utils/chat_offplatform_detector.dart';
import 'package:vero360_app/widgets/chat_offplatform_warning.dart';
import 'package:vero360_app/GeneralPages/checkout_page.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart'
    as core;
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:vero360_app/features/Marketplace/presentation/widgets/merchant_review_prompt.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_id_resolver.dart';

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

  /// When set, send this text once after the chat opens (order shipping request).
  final String? autoSendMessage;
  final String? autoSendClientMessageId;

  const MessagePageBackendApi({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerAvatarUrl,
    this.productContext,
    this.peerMerchantId,
    this.peerUserId,
    this.sendProductEnquiry = false,
    this.autoSendMessage,
    this.autoSendClientMessageId,
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
  StreamSubscription<ChatPeerReceipt?>? _peerReceiptSub;
  ChatPeerReceipt? _peerReceipt;

  /// Stay pinned to newest only when the user is already near the bottom.
  bool _stickToBottom = true;
  int _messagePage = 1;
  bool _loadingOlder = false;
  bool _hasMoreOlder = true;
  bool _exportingChat = false;
  static const _pageSize = 50;
  static const _nearBottomPx = 140.0;

  final _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  _PendingImage? _pendingImage;
  bool _recording = false;
  int _recordMs = 0;
  Timer? _recordTimer;
  final Map<String, Uint8List> _localImageBytes = {};
  final Map<String, String> _localVoicePaths = {};
  final Map<String, int> _localVoiceDurations = {};
  BackendChatMessage? _replyingTo;
  final Set<String> _outboxFlushing = {};

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
        // Warm media + land on newest (reverse list starts at latest).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _prefetchThreadVoiceNotes();
          _prefetchChatImages();
          _scheduleScrollToLatest();
        });
      }
    }

    _boot();
    unawaited(_prefetchShopMerchantId());

    _input.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    _scroll.addListener(_onScrollPositionChanged);

    _startRealtime();
  }

  Future<void> _prefetchShopMerchantId() async {
    final known = _resolvedMerchantId()?.trim();
    if (known != null && known.isNotEmpty) {
      _cachedShopMerchantId = known;
    }
    final peerUserId = widget.peerUserId ?? _peerUserId;
    if ((known == null || known.isEmpty) &&
        peerUserId != null &&
        peerUserId > 0) {
      try {
        final uid =
            (await BackendChatService.getFirebaseUidByUserId(peerUserId))
                ?.trim();
        if (uid != null && uid.isNotEmpty && mounted) {
          _cachedShopMerchantId = uid;
        }
      } catch (_) {}
    }

    // Warm Nest merchant id for post-chat ratings (avoids "Merchant not found").
    final ref = _merchantRefForRating();
    final backendHint = _merchantBackendIdForRating();
    if ((ref.isNotEmpty || (backendHint != null && backendHint > 0)) &&
        !_iAmTheMerchantForRating()) {
      try {
        await MerchantReviewIdResolver.resolveMerchantId(
          merchantRef: ref.isNotEmpty ? ref : '${backendHint ?? ''}',
          serviceProviderId: widget.resolveServiceProviderId,
          sellerUserId: widget.resolveSellerUserId ?? ref,
          preResolvedBackendId: backendHint,
        );
      } catch (_) {}
    }
  }

  void _onScrollPositionChanged() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // reverse:true — pixels ≈ 0 is the newest messages.
    _stickToBottom = pos.pixels <= _nearBottomPx;
    // Load older history when the user scrolls toward the oldest end.
    if (pos.maxScrollExtent > 0 &&
        pos.pixels >= pos.maxScrollExtent - 80) {
      unawaited(_loadOlderMessages());
    }
  }

  void _startRealtime() {
    _wsMessageSub = BackendMessagingSocket.messageStream.listen((msg) {
      if (!mounted || _chatId.isEmpty || msg.chatId != _chatId) return;
      final myId = _myUserId;
      final mine = myId != null && msg.isMine(myId);
      setState(() {
        _upsertMessage(msg);
        if (_hasProductTagInMessages(_messages)) {
          _productTagAttached = true;
        }
      });
      final audio = _messageAudio(msg);
      final url = audio?.url.trim() ?? '';
      if (url.isNotEmpty) unawaited(VoiceNoteBubble.warmUrl(url));
      // Peer received our message on their device → treat as delivered locally
      // when we are the recipient of an incoming message.
      if (!mine) {
        unawaited(_publishMyReceipts(asRead: true));
      }
      // Don't yank the user back down while they read history.
      _scrollToBottom(force: mine);
    });

    _wsConnectionSub =
        BackendMessagingSocket.connectionStream.listen((connected) {
      if (!mounted) return;
      setState(() => _wsConnected = connected);
      if (connected) {
        _fallbackPollTimer?.cancel();
        _fallbackPollTimer = null;
        unawaited(_flushOutbox());
      } else {
        _startFallbackPoll();
      }
    });

    _startFallbackPoll();
    _readStatusPollTimer?.cancel();
    _readStatusPollTimer = Timer.periodic(const Duration(seconds: 18), (_) {
      if (mounted && _chatId.isNotEmpty) {
        _loadMessages(silent: true);
      }
    });
  }

  void _startFallbackPoll() {
    _fallbackPollTimer?.cancel();
    if (BackendMessagingSocket.isConnected) return;
    _fallbackPollTimer = Timer.periodic(_fallbackPollInterval, (_) {
      if (mounted &&
          _chatId.isNotEmpty &&
          !BackendMessagingSocket.isConnected) {
        _loadMessages(silent: true);
        unawaited(_flushOutbox());
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
    _peerReceiptSub?.cancel();
    if (_chatId.isNotEmpty) {
      unawaited(BackendMessagingSocket.leaveChat(_chatId));
    }
    _input.dispose();
    _scroll.removeListener(_onScrollPositionChanged);
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
      final msg = UserFacingError.from(e, fallback: 'Could not open chat');
      setState(() {
        _resolvingChat = false;
        _loading = false;
        _loadError = msg;
        _bootComplete = false;
      });
      _toast(msg);
      return false;
    }
  }

  Future<void> _boot() async {
    try {
      unawaited(BackendMessagingSocket.connect().catchError((_) {}));

      // Warm local user id without blocking resolve.
      final prefsFuture = SharedPreferences.getInstance();
      unawaited(prefsFuture.then((prefs) async {
        final cachedUserId = prefs.getInt('userId') ?? prefs.getInt('user_id');
        if (cachedUserId != null && cachedUserId > 0 && mounted) {
          setState(() {
            _myUserId = cachedUserId;
            _me = cachedUserId.toString();
            if (_chatId.isNotEmpty) _bootComplete = true;
          });
          await _hydrateOutbox();
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

      unawaited(() async {
        await _loadMessages(silent: cached.isNotEmpty);
        if (mounted) await _maybeSendAutoMessage(userId);
      }());
      unawaited(_maybeSendProductEnquiry(userId));
      unawaited(_markUnreadAsRead(userId));

      if (!mounted) return;
      setState(() {
        _myUserId = userId;
        _me = userId.toString();
        _bootComplete = true;
      });
      _bindPeerReceiptListener(userId);
      unawaited(_publishMyReceipts(asRead: true));
      await _hydrateOutbox();
      unawaited(_flushOutbox());
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

  String _enquiryClientMessageId(String productId) => const Uuid().v4();

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
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(force: true));
    } catch (_) {
      // Buyer can still attach the product on their first manual message.
    }
  }

  Future<void> _maybeSendAutoMessage(int myUserId) async {
    final text = widget.autoSendMessage?.trim();
    if (text == null || text.isEmpty || _chatId.isEmpty) return;

    final rawClientId = (widget.autoSendClientMessageId ?? '').trim();
    if (rawClientId.isNotEmpty &&
        _messages.any((m) => (m.clientMessageId ?? '') == rawClientId)) {
      return;
    }

    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    for (final msg in _messages) {
      if (!msg.isMine(myUserId)) continue;
      final existing = (msg.content ?? '')
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();
      if (existing == normalized) return;
      if (existing.contains('please arrange shipping') &&
          existing.contains('order:')) {
        return;
      }
    }

    try {
      final product = widget.productContext;
      final saved = await BackendChatService.sendMessage(
        chatId: _chatId,
        content: text,
        type: 'text',
        tags: product == null ? null : [product.toMessageTag()],
        clientMessageId: const Uuid().v4(),
        metadata: {
          'source': 'orders',
          'autoOrderShipping': true,
          if (rawClientId.isNotEmpty) 'orderClientKey': rawClientId,
          if (product != null) 'productId': product.productId,
        },
      );
      if (!mounted) return;
      setState(() {
        _upsertMessage(saved);
        if (product != null) _productTagAttached = true;
      });
      BackendChatService.refreshThreads();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(force: true));
    } catch (_) {
      if (!mounted) return;
      if (_input.text.trim().isEmpty) {
        _input.text = text;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        setState(() {});
      }
    }
  }

  String _friendlyError(Object e) {
    return UserFacingError.from(
      e,
      fallback: 'Could not load messages. Pull to retry.',
    );
  }

  Future<void> _loadMessages({bool silent = false}) async {
    try {
      final messages = await BackendChatService.getMessages(
        _chatId,
        page: 1,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      // Keep already-loaded older pages when a silent refresh only returns page 1.
      var mergedServer = messages;
      if (silent && _messagePage > 1 && _messages.isNotEmpty && messages.isNotEmpty) {
        final cutoff = messages.first.createdAt;
        final older = _messages
            .where((m) => m.createdAt.isBefore(cutoff))
            .toList();
        if (older.isNotEmpty) {
          final byId = <String, BackendChatMessage>{};
          for (final m in [...older, ...messages]) {
            final key = m.id.isNotEmpty
                ? m.id
                : (m.clientMessageId ?? '${m.createdAt.millisecondsSinceEpoch}');
            byId[key] = m;
          }
          mergedServer = byId.values.toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        }
      }

      final wasEmpty = _messages.isEmpty;
      final stick = !silent || _stickToBottom || wasEmpty;

      setState(() {
        _messages = _mergeWithPending(mergedServer);
        _loading = false;
        _loadError = null;
        if (!silent) {
          _messagePage = 1;
          _hasMoreOlder = messages.length >= _pageSize;
        } else if (messages.length < _pageSize && _messagePage <= 1) {
          _hasMoreOlder = false;
        }
        if (_hasProductTagInMessages(_messages)) {
          _productTagAttached = true;
        }
      });
      _ensurePeerUserIdFromMessages();
      _prefetchThreadVoiceNotes();
      _prefetchChatImages();
      // Opening/refreshing the chat means we've delivered + read incoming msgs.
      unawaited(_publishMyReceipts(asRead: true));

      if (stick) {
        _scheduleScrollToLatest();
      }
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

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || !_hasMoreOlder || _chatId.isEmpty || _loading) return;
    setState(() => _loadingOlder = true);
    final nextPage = _messagePage + 1;
    try {
      final older = await BackendChatService.getMessages(
        _chatId,
        page: nextPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      if (older.isEmpty) {
        setState(() {
          _hasMoreOlder = false;
          _loadingOlder = false;
        });
        return;
      }

      older.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final existingIds = _messages.map((m) => m.id).where((id) => id.isNotEmpty).toSet();
      final fresh = older.where((m) => m.id.isEmpty || !existingIds.contains(m.id)).toList();
      if (fresh.isEmpty) {
        setState(() {
          _hasMoreOlder = older.length >= _pageSize;
          _messagePage = nextPage;
          _loadingOlder = false;
        });
        return;
      }

      final prevMax =
          _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
      final prevPixels = _scroll.hasClients ? _scroll.position.pixels : 0.0;

      setState(() {
        _messages = [...fresh, ..._messages]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _messagePage = nextPage;
        _hasMoreOlder = older.length >= _pageSize;
        _loadingOlder = false;
        _stickToBottom = false;
      });
      _prefetchThreadVoiceNotes();
      _prefetchChatImages();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final newMax = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(prevPixels + (newMax - prevMax));
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _markUnreadAsRead(int myUserId) async {
    final unreadIds = _messages
        .where((m) => !m.isMine(myUserId) && !_isUnsent(m))
        .map((m) => m.id)
        .where((id) => id.isNotEmpty)
        .toList();
    // Always publish read receipts for ticks (even if Nest has nothing new).
    unawaited(_publishMyReceipts(asRead: true));
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

  void _bindPeerReceiptListener(int myUserId) {
    _peerReceiptSub?.cancel();
    _peerReceiptSub = null;
    final peerId = _peerUserId ?? widget.peerUserId;
    if (_chatId.isEmpty || peerId == null || peerId <= 0) return;

    _peerReceiptSub = ChatReceiptService.watchUserReceipt(
      chatId: _chatId,
      userId: peerId,
    ).listen((receipt) {
      if (!mounted) return;
      setState(() => _peerReceipt = receipt);
    });
  }

  void _ensurePeerUserIdFromMessages() {
    if ((_peerUserId ?? 0) > 0) {
      final myId = _myUserId;
      if (myId != null) _bindPeerReceiptListener(myId);
      return;
    }
    final myId = _myUserId;
    if (myId == null) return;
    for (final m in _messages) {
      if (!m.isMine(myId) && m.senderId > 0) {
        _peerUserId = m.senderId;
        _bindPeerReceiptListener(myId);
        return;
      }
    }
    // Fallback: thread cache participants.
    final thread = BackendChatService.findCachedThreadById(_chatId);
    final other = thread?.otherParticipant(myId);
    if (other != null && other.id > 0) {
      _peerUserId = other.id;
      _bindPeerReceiptListener(myId);
    }
  }

  /// Tell the peer how far we've delivered/read their messages (for their ticks).
  Future<void> _publishMyReceipts({required bool asRead}) async {
    final myId = _myUserId;
    if (myId == null || _chatId.isEmpty) return;

    DateTime? latestIncoming;
    for (final m in _messages) {
      if (m.isMine(myId) || _isUnsent(m)) continue;
      if (latestIncoming == null || m.createdAt.isAfter(latestIncoming)) {
        latestIncoming = m.createdAt;
      }
    }
    if (latestIncoming == null) return;

    await ChatReceiptService.publish(
      chatId: _chatId,
      userId: myId,
      deliveredUpTo: latestIncoming,
      readUpTo: asRead ? latestIncoming : null,
    );
  }

  List<BackendChatMessage> _mergeWithPending(List<BackendChatMessage> server) {
    final myId = _myUserId;
    if (myId == null) return server;

    final pending = _messages.where(_isUnsent).toList();
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

  bool _isUnsent(BackendChatMessage m) =>
      m.status == 'pending' || m.status == 'failed';

  void _startReply(BackendChatMessage msg) {
    if (_isUnsent(msg)) return;
    HapticFeedback.selectionClick();
    setState(() => _replyingTo = msg);
  }

  void _clearReply() {
    if (_replyingTo == null) return;
    setState(() => _replyingTo = null);
  }

  String _replyPreviewFor(BackendChatMessage msg) {
    final audio = _messageAudio(msg);
    if (audio != null || _localVoicePathFor(msg) != null) return 'Voice note';
    if (_messageImageUrl(msg) != null || _localImageFor(msg) != null) {
      final cap = _visibleCaption(msg, _messageImageUrl(msg));
      if (cap != null && cap.trim().isNotEmpty) return cap.trim();
      return 'Photo';
    }
    final text = (msg.content ?? '').trim();
    if (text.isEmpty) {
      if (_productTagsFor(msg).isNotEmpty) return 'Shared a product';
      return 'Message';
    }
    if (text.startsWith(_audPrefix)) return 'Voice note';
    if (text.startsWith(_imgPrefix)) return 'Photo';
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  Map<String, dynamic>? _replyMetadataPayload() {
    final reply = _replyingTo;
    if (reply == null) return null;
    return {
      'replyTo': {
        'messageId': reply.id,
        if (reply.clientMessageId != null)
          'clientMessageId': reply.clientMessageId,
        'senderId': reply.senderId,
        'type': reply.type,
        'preview': _replyPreviewFor(reply),
      },
    };
  }

  String _replyAuthorLabel(BackendChatMessage msg) {
    final myId = _myUserId;
    if (myId != null && msg.isMine(myId)) return 'You';
    final name = widget.peerName.trim();
    return name.isNotEmpty ? name : 'Reply';
  }

  bool _isStoryReply(BackendChatMessage m) {
    final source = (m.metadata?['source'] ?? '').toString().trim().toLowerCase();
    return source == 'story_reply';
  }

  String? _storyMediaUrl(BackendChatMessage m) {
    final raw = (m.metadata?['storyMediaUrl'] ??
            m.metadata?['storyImageUrl'] ??
            m.metadata?['mediaUrl'] ??
            '')
        .toString()
        .trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return null;
  }

  String? _storyCaptionMeta(BackendChatMessage m) {
    final c = (m.metadata?['storyCaption'] ?? '').toString().trim();
    return c.isEmpty ? null : c;
  }

  /// User-facing reply text without the "↩️ Story reply" header.
  String? _storyReplyBody(BackendChatMessage m) {
    final content = (m.content ?? '').trim();
    if (content.isEmpty) return null;
    final lines = content.split('\n');
    if (lines.isEmpty) return content;
    if (!lines.first.contains('Story reply')) return content;
    var i = 1;
    // Skip optional quoted caption block.
    if (i < lines.length && lines[i].trim().startsWith('"')) {
      while (i < lines.length) {
        final done = lines[i].trim().endsWith('"') || lines[i].trim().isEmpty;
        i++;
        if (done) break;
      }
    }
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
    final body = lines.skip(i).join('\n').trim();
    return body.isEmpty ? null : body;
  }

  Widget _buildStoryReplyChip(
    BackendChatMessage msg, {
    required bool isMine,
  }) {
    final mediaUrl = _storyMediaUrl(msg);
    final caption = _storyCaptionMeta(msg);
    final bg = isMine
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFFF8A00).withValues(alpha: 0.10);
    final fg = isMine ? Colors.white : Colors.black87;
    final accent = isMine ? Colors.white : _brandOrange;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 68,
              child: mediaUrl != null
                  ? ResilientCachedNetworkImage(
                      url: mediaUrl,
                      fit: BoxFit.cover,
                      width: 52,
                      height: 68,
                    )
                  : ColoredBox(
                      color: isMine
                          ? Colors.white24
                          : const Color(0xFFFFE8CC),
                      child: Icon(
                        Icons.auto_stories_rounded,
                        color: accent,
                        size: 22,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Story',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption ?? 'Replying to a story',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.9),
                    fontSize: 12.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyQuoteChip(
    Map<String, dynamic> reply, {
    required bool isMine,
  }) {
    final preview = (reply['preview'] ?? 'Message').toString();
    final senderId = reply['senderId'];
    final myId = _myUserId;
    final isOwnQuote =
        myId != null && senderId != null && senderId.toString() == myId.toString();
    final author = isOwnQuote
        ? 'You'
        : (widget.peerName.trim().isNotEmpty ? widget.peerName.trim() : 'Reply');
    final bg = isMine
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFFF8A00).withValues(alpha: 0.10);
    final fg = isMine ? Colors.white : Colors.black87;
    final accent = isMine ? Colors.white : _brandOrange;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            author,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg.withValues(alpha: 0.9),
              fontSize: 12.5,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerReplyBar() {
    final reply = _replyingTo;
    if (reply == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _brandOrange.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, color: _brandOrange, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${_replyAuthorLabel(reply)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: _brandOrange,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyPreviewFor(reply),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _clearReply,
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'Cancel reply',
          ),
        ],
      ),
    );
  }

  void _upsertMessage(BackendChatMessage msg) {
    final idx = _messages.indexWhere(
      (m) =>
          m.id == msg.id ||
          (msg.clientMessageId != null &&
              m.clientMessageId == msg.clientMessageId) ||
          (_isUnsent(m) &&
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
      final myUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

      // peerMerchantId is often the *product merchant* (self when merchant replies).
      // Prefer a real peer Firebase UID resolved from Nest / chat participants.
      var hint = (widget.peerMerchantId ??
              widget.resolveMerchantId ??
              _cachedShopMerchantId ??
              '')
          .trim();
      if (hint == myUid) hint = '';

      final peerUserId = widget.peerUserId ?? _peerUserId;
      await ChatNotificationService.notifyRecipientOfMessage(
        chatId: _chatId,
        senderName: senderName,
        body: body,
        recipientFirebaseUid: hint.isEmpty ? null : hint,
        recipientUserId: peerUserId,
      );
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    if (_recording) return;

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
    final replyMeta = _replyMetadataPayload();
    final productMeta = attachProductTag
        ? {'source': 'marketplace', 'productId': product.productId}
        : null;
    final metadata = <String, dynamic>{
      if (productMeta != null) ...productMeta,
      if (replyMeta != null) ...replyMeta,
    };
    final now = DateTime.now();
    final pending = BackendChatMessage(
      id: clientMessageId,
      chatId: _chatId,
      senderId: myId,
      content: content,
      type: 'text',
      status: 'pending',
      createdAt: now,
      tags: tags,
      clientMessageId: clientMessageId,
      metadata: metadata.isEmpty ? null : metadata,
    );

    // Paint bubble + clear input immediately (WhatsApp-style), persist in background.
    _input.clear();
    setState(() {
      _messages = [..._messages, pending];
      _replyingTo = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(force: true));

    final entry = ChatOutboxEntry(
      clientMessageId: clientMessageId,
      chatId: _chatId,
      senderId: myId,
      type: 'text',
      content: content,
      status: 'pending',
      createdAt: now,
      tags: tags,
      metadata: metadata.isEmpty ? null : metadata,
    );
    unawaited(() async {
      try {
        await ChatOutbox.upsert(entry);
      } catch (_) {}
      await _deliverOutboxEntry(entry, notifyPeerOnSuccess: true);
    }());
  }

  Future<void> _sendImageMessage(
    _PendingImage image, {
    String caption = '',
  }) async {
    final myId = _myUserId;
    if (myId == null) return;

    final clientMessageId = const Uuid().v4();
    final replyMeta = _replyMetadataPayload();
    final pending = BackendChatMessage(
      id: clientMessageId,
      chatId: _chatId,
      senderId: myId,
      content: caption,
      type: 'image',
      status: 'pending',
      createdAt: DateTime.now(),
      clientMessageId: clientMessageId,
      metadata: replyMeta,
    );

    String? localImagePath;
    try {
      final ext = image.filename.contains('.')
          ? image.filename.split('.').last
          : 'jpg';
      localImagePath = await ChatOutbox.persistImageBytes(
        bytes: image.bytes,
        clientMessageId: clientMessageId,
        ext: ext,
      );
    } catch (_) {}

    final entry = ChatOutboxEntry(
      clientMessageId: clientMessageId,
      chatId: _chatId,
      senderId: myId,
      type: 'image',
      content: caption,
      status: 'pending',
      createdAt: pending.createdAt,
      localImagePath: localImagePath,
      imageMime: image.mime,
      imageFilename: image.filename,
      metadata: replyMeta,
    );
    await ChatOutbox.upsert(entry);

    setState(() {
      _localImageBytes[clientMessageId] = image.bytes;
      _messages = [..._messages, pending];
      _pendingImage = null;
      _replyingTo = null;
    });
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(force: true));
    unawaited(_deliverOutboxEntry(entry, notifyPeerOnSuccess: true));
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

  Future<String> _uploadAudioFile(String path, String uid) async {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) {
      throw StateError(' sign-in required to send voice notes');
    }
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('Voice note file is missing on this device');
    }

    final objectName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final ref = FirebaseStorage.instance
        .ref()
        .child('voice_notes/$safeUid/$objectName');

    try {
      await ref.putFile(
        file,
        SettableMetadata(contentType: 'audio/mp4'),
      );
      return ref.getDownloadURL();
    } catch (_) {
      // Fallback for platforms where putFile fails.
      final bytes = await file.readAsBytes();
      return _uploadAudioBytes(bytes, uid);
    }
  }

  String _formatRecordMs(int ms) {
    final s = (ms / 1000).floor();
    final m = (s / 60).floor();
    final r = s % 60;
    return '${m.toString().padLeft(1, '0')}:${r.toString().padLeft(2, '0')}';
  }

  Future<void> _startVoiceRecording() async {
    if (_myUserId == null) return;
    if (_recording) return;
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
          bitRate: 64000,
          sampleRate: 32000,
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
    final replyMeta = _replyMetadataPayload();
    final now = DateTime.now();
    final pending = BackendChatMessage(
      id: clientMessageId,
      chatId: _chatId,
      senderId: myId,
      content: 'Voice note',
      type: 'audio',
      status: 'pending',
      createdAt: now,
      clientMessageId: clientMessageId,
      metadata: replyMeta,
    );

    // Show bubble instantly with the temp recording path, then harden + upload.
    setState(() {
      _localVoicePaths[clientMessageId] = filePath;
      _localVoiceDurations[clientMessageId] = durationMs;
      _messages = [..._messages, pending];
      _replyingTo = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(force: true));

    unawaited(() async {
      String durablePath = filePath;
      try {
        durablePath = await ChatOutbox.persistVoiceFile(
          sourcePath: filePath,
          clientMessageId: clientMessageId,
        );
        if (mounted && durablePath != filePath) {
          setState(() => _localVoicePaths[clientMessageId] = durablePath);
        }
      } catch (_) {}

      final entry = ChatOutboxEntry(
        clientMessageId: clientMessageId,
        chatId: _chatId,
        senderId: myId,
        type: 'audio',
        content: 'Voice note',
        status: 'pending',
        createdAt: now,
        localVoicePath: durablePath,
        voiceDurationMs: durationMs,
        metadata: replyMeta,
      );
      try {
        await ChatOutbox.upsert(entry);
      } catch (_) {}
      await _deliverOutboxEntry(entry, notifyPeerOnSuccess: true);
    }());
  }

  Future<void> _hydrateOutbox() async {
    final myId = _myUserId;
    if (myId == null || _chatId.isEmpty) return;
    final entries = await ChatOutbox.forChat(userId: myId, chatId: _chatId);
    if (entries.isEmpty || !mounted) return;

    for (final e in entries) {
      if (e.localVoicePath != null &&
          e.localVoicePath!.isNotEmpty &&
          File(e.localVoicePath!).existsSync()) {
        _localVoicePaths[e.clientMessageId] = e.localVoicePath!;
        if (e.voiceDurationMs != null) {
          _localVoiceDurations[e.clientMessageId] = e.voiceDurationMs!;
        }
      }
      if (e.localImagePath != null &&
          e.localImagePath!.isNotEmpty &&
          File(e.localImagePath!).existsSync()) {
        try {
          _localImageBytes[e.clientMessageId] =
              await File(e.localImagePath!).readAsBytes();
        } catch (_) {}
      }
      _upsertMessage(e.toMessage());
    }
    if (mounted) setState(() {});
  }

  Future<void> _flushOutbox() async {
    final myId = _myUserId;
    if (myId == null || _chatId.isEmpty) return;
    final entries = await ChatOutbox.forChat(userId: myId, chatId: _chatId);
    for (final e in entries) {
      if (!mounted) return;
      if (e.isAudio &&
          (e.localVoicePath == null ||
              e.localVoicePath!.isEmpty ||
              !File(e.localVoicePath!).existsSync())) {
        continue;
      }
      if (e.isImage &&
          _localImageBytes[e.clientMessageId] == null &&
          (e.localImagePath == null ||
              e.localImagePath!.isEmpty ||
              !File(e.localImagePath!).existsSync())) {
        continue;
      }
      await _deliverOutboxEntry(e, notifyPeerOnSuccess: true);
    }
  }

  Future<void> _retryUnsent(BackendChatMessage msg) async {
    final myId = _myUserId;
    final id = msg.clientMessageId ?? msg.id;
    if (myId == null || id.isEmpty) return;
    final entry = await ChatOutbox.get(myId, id);
    if (entry == null) return;
    await _deliverOutboxEntry(entry, notifyPeerOnSuccess: true, userInitiated: true);
  }

  Future<void> _deliverOutboxEntry(
    ChatOutboxEntry entry, {
    bool notifyPeerOnSuccess = false,
    bool userInitiated = false,
  }) async {
    final id = entry.clientMessageId;
    if (id.isEmpty || _outboxFlushing.contains(id)) return;
    _outboxFlushing.add(id);

    _setUnsentStatus(id, 'pending');
    unawaited(
      ChatOutbox.markStatus(
        userId: entry.senderId,
        clientMessageId: id,
        status: 'pending',
      ),
    );

    try {
      BackendChatMessage saved;
      if (entry.isAudio) {
        final path = entry.localVoicePath;
        if (path == null || path.isEmpty || !File(path).existsSync()) {
          throw StateError('Voice note file is missing on this device');
        }
        final firebaseUser = await _requireFirebaseUserForStorage();
        final url = await _uploadAudioFile(path, firebaseUser.uid);
        saved = await BackendChatService.sendAudioMessage(
          chatId: entry.chatId,
          audioUrl: url,
          durationMs: entry.voiceDurationMs ?? 0,
          clientMessageId: id,
          mimeType: 'audio/mp4',
          metadata: entry.metadata,
        );
        _localVoicePaths[saved.id] = path;
        _localVoiceDurations[saved.id] = entry.voiceDurationMs ?? 0;
        if (saved.clientMessageId != null) {
          _localVoicePaths[saved.clientMessageId!] = path;
          _localVoiceDurations[saved.clientMessageId!] =
              entry.voiceDurationMs ?? 0;
        }
      } else if (entry.isImage) {
        Uint8List? bytes = _localImageBytes[id];
        if (bytes == null &&
            entry.localImagePath != null &&
            File(entry.localImagePath!).existsSync()) {
          bytes = await File(entry.localImagePath!).readAsBytes();
          _localImageBytes[id] = bytes;
        }
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Photo is missing on this device');
        }
        final image = _PendingImage(
          bytes: bytes,
          filename: entry.imageFilename ?? 'photo.jpg',
          mime: entry.imageMime ?? 'image/jpeg',
        );
        final url = await _uploadImageBytes(image);
        saved = await BackendChatService.sendImageMessage(
          chatId: entry.chatId,
          imageUrl: url,
          caption: entry.content ?? '',
          clientMessageId: id,
          mimeType: image.mime,
          metadata: entry.metadata,
        );
      } else {
        saved = await BackendChatService.sendMessage(
          chatId: entry.chatId,
          content: entry.content ?? '',
          type: 'text',
          tags: entry.tags,
          clientMessageId: id,
          metadata: entry.metadata,
        );
        if (entry.tags != null && entry.tags!.isNotEmpty) {
          _productTagAttached = true;
        }
      }

      await ChatOutbox.remove(entry.senderId, id);
      if (!mounted) return;
      setState(() => _upsertMessage(saved));
      BackendChatService.refreshThreads();
      if (notifyPeerOnSuccess) {
        final body = entry.isAudio
            ? '🎤 Voice message'
            : entry.isImage
                ? ((entry.content ?? '').trim().isNotEmpty
                    ? entry.content!.trim()
                    : '📷 Photo')
                : (entry.content ?? '').trim();
        if (body.isNotEmpty) unawaited(_pushNotifyPeer(body: body));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(force: true));
    } catch (e) {
      await ChatOutbox.markStatus(
        userId: entry.senderId,
        clientMessageId: id,
        status: 'failed',
      );
      _setUnsentStatus(id, 'failed');
      if (kDebugMode) debugPrint('[ChatOutbox] deliver failed $id: $e');
      if (mounted && userInitiated) {
        _toast(UserFacingError.from(
          e,
          fallback: 'Still offline. We\'ll keep this message here.',
        ));
      }
    } finally {
      _outboxFlushing.remove(id);
    }
  }

  void _setUnsentStatus(String clientMessageId, String status) {
    if (!mounted) return;
    final idx = _messages.indexWhere(
      (m) => m.clientMessageId == clientMessageId || m.id == clientMessageId,
    );
    if (idx < 0) return;
    setState(() {
      _messages[idx] = _messages[idx].copyWith(status: status);
    });
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    // reverse:true — 0 is the latest message.
    _scroll.jumpTo(0);
    _stickToBottom = true;
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_stickToBottom) return;
    if (!_scroll.hasClients) return;
    _stickToBottom = true;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// Retry across frames so late image/layout growth still ends on newest.
  void _scheduleScrollToLatest({int attempts = 10}) {
    void attempt(int left) {
      if (!mounted || left <= 0) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _jumpToBottom();
        if (!_scroll.hasClients) {
          if (left > 1) attempt(left - 1);
          return;
        }
        // Content may still be measuring (images); keep pinning briefly.
        if (_stickToBottom && left > 1) {
          Future<void>.delayed(const Duration(milliseconds: 50), () {
            if (!mounted || !_stickToBottom) return;
            if (_scroll.hasClients && _scroll.position.pixels > 2) {
              _jumpToBottom();
            }
            attempt(left - 1);
          });
        }
      });
    }

    attempt(attempts);
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
      if (url.startsWith('http')) return _preferHttps(url);
    }
    if (m.type == 'image') {
      if (content.startsWith('http://') || content.startsWith('https://')) {
        return _preferHttps(content);
      }
    }
    final atts = m.attachments;
    if (atts != null && atts.isNotEmpty) {
      for (final att in atts) {
        final url = att['url']?.toString().trim();
        if (url != null && url.isNotEmpty && url.startsWith('http')) {
          return _preferHttps(url);
        }
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
    if (_isStoryReply(m)) return _storyReplyBody(m);
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

  void _prefetchThreadVoiceNotes() {
    final urls = <String>[];
    for (final m in _messages) {
      if (_localVoicePathFor(m) != null) continue;
      final audio = _messageAudio(m);
      final url = audio?.url.trim() ?? '';
      if (url.isNotEmpty) urls.add(url);
    }
    if (urls.isNotEmpty) VoiceNoteBubble.warmUrls(urls);
  }

  /// Warm disk/memory cache for chat photos so open / full-screen is instant.
  void _prefetchChatImages() {
    if (!mounted) return;
    final seen = <String>{};
    for (final m in _messages.reversed.take(40)) {
      if (_localImageFor(m) != null) continue;
      final url = _messageImageUrl(m);
      if (url == null || url.isEmpty || !seen.add(url)) continue;
      unawaited(
        precacheImage(
          CachedNetworkImageProvider(url),
          context,
          onError: (_, __) {},
        ),
      );
    }
  }

  String _preferHttps(String url) {
    final u = url.trim();
    if (u.startsWith('http://')) return 'https://${u.substring(7)}';
    return u;
  }

  Future<void> _showUnsentActions(BackendChatMessage m) async {
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
            ListTile(
              leading: const Icon(Icons.refresh_rounded, color: _brandOrange),
              title: const Text('Retry send'),
              subtitle: const Text('Keep this message and try again'),
              onTap: () {
                Navigator.pop(context);
                unawaited(_retryUnsent(m));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
              title: const Text(
                'Delete unsent message',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _deleteUnsent(m);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUnsent(BackendChatMessage m) async {
    final myId = _myUserId;
    final id = m.clientMessageId ?? m.id;
    if (myId != null && id.isNotEmpty) {
      await ChatOutbox.remove(myId, id);
    }
    if (!mounted) return;
    setState(() {
      _messages = _messages
          .where((x) => (x.clientMessageId ?? x.id) != id)
          .toList();
      _localVoicePaths.remove(id);
      _localVoiceDurations.remove(id);
      _localImageBytes.remove(id);
    });
  }

  Future<void> _showMsgActions(BackendChatMessage m) async {
    final myId = _myUserId;
    if (myId == null || !m.isMine(myId) || !_within5Min(m)) return;
    if (_isUnsent(m)) return;

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
              leading: const Icon(Icons.reply_rounded, color: _brandOrange),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                _startReply(m);
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
      _toast(UserFacingError.from(e, fallback: 'Could not delete message'));
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
      _toast(UserFacingError.from(e, fallback: 'Could not edit message'));
    }
  }

  void _viewImage(String url) {
    final warmUrl = _preferHttps(url);
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.6,
              maxScale: 4,
              child: Center(
                child: ResilientCachedNetworkImage(
                  url: warmUrl,
                  fit: BoxFit.contain,
                  showSpinner: true,
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
      final myId = _myUserId;
      if (myId != null) {
        final entries =
            await ChatOutbox.forChat(userId: myId, chatId: _chatId);
        for (final e in entries) {
          await ChatOutbox.remove(myId, e.clientMessageId);
        }
      }
      if (!mounted) return;
      setState(() {
        _messages = [];
        _pendingImage = null;
        _localVoicePaths.clear();
        _localVoiceDurations.clear();
        _localImageBytes.clear();
        _messagePage = 1;
        _hasMoreOlder = true;
      });
      BackendChatService.refreshThreads();
      _toast('Chat cleared');
    } catch (e) {
      _toast(UserFacingError.from(e, fallback: 'Could not clear chat'));
    }
  }

  String _exportLineForMessage(BackendChatMessage m) {
    final myId = _myUserId;
    final who = (myId != null && m.isMine(myId)) ? 'You' : widget.peerName;
    final time = DateFormat('yyyy-MM-dd HH:mm').format(m.createdAt.toLocal());
    final content = (m.content ?? '').trim();
    String body;
    if (m.type == 'audio' || content.startsWith(_audPrefix)) {
      body = '[Voice note]';
    } else if (m.type == 'image' || content.startsWith(_imgPrefix)) {
      final caption = content.startsWith(_imgPrefix)
          ? content.split('\n').skip(1).join('\n').trim()
          : content;
      body = caption.isEmpty ? '[Photo]' : '[Photo] $caption';
    } else if (content.isEmpty) {
      body = '[Message]';
    } else {
      body = content;
    }
    return '[$time] $who: $body';
  }

  Future<void> _downloadChat() async {
    if (_exportingChat) return;
    if (_messages.isEmpty) {
      _toast('No messages to download yet.');
      return;
    }
    setState(() => _exportingChat = true);
    try {
      // Pull remaining older pages so the export is complete.
      while (_hasMoreOlder && _messagePage < 40) {
        final before = _messagePage;
        await _loadOlderMessages();
        if (_messagePage == before) break;
      }
      if (!mounted) return;

      final buf = StringBuffer()
        ..writeln('Vero360 chat with ${widget.peerName}')
        ..writeln(
          'Exported ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
        )
        ..writeln('---');
      for (final m in _messages) {
        buf.writeln(_exportLineForMessage(m));
      }

      final text = buf.toString();
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        final safeName = widget.peerName
            .replaceAll(RegExp(r'[^\w\s-]'), '')
            .trim()
            .replaceAll(RegExp(r'\s+'), '_');
        final file = File(
          '${dir.path}/vero360_chat_${safeName.isEmpty ? 'export' : safeName}_'
          '${DateTime.now().millisecondsSinceEpoch}.txt',
        );
        await file.writeAsString(text);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            subject: 'Chat with ${widget.peerName}',
            text: 'Vero360 chat export',
          ),
        );
      } else {
        await SharePlus.instance.share(
          ShareParams(
            text: text,
            subject: 'Chat with ${widget.peerName}',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _toast(UserFacingError.from(e, fallback: 'Could not download chat'));
      }
    } finally {
      if (mounted) setState(() => _exportingChat = false);
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

  String? _cachedShopMerchantId;

  Future<void> _openMerchantProfile() async {
    // Prefer already-known ids so the shop opens on the same frame as the tap.
    var merchantId =
        (_cachedShopMerchantId ?? _resolvedMerchantId() ?? '').trim();

    if (merchantId.isEmpty) {
      final peerUserId = widget.peerUserId ?? _peerUserId;
      if (peerUserId != null && peerUserId > 0) {
        // Resolve without blocking the first paint when we already have a hint.
        merchantId = (await BackendChatService.getFirebaseUidByUserId(
              peerUserId,
            ))
                ?.trim() ??
            '';
      }
    }

    if (merchantId.isEmpty) {
      _toast('Profile is not available for this chat.');
      return;
    }
    _cachedShopMerchantId = merchantId;
    if (!mounted) return;

    // Instant shop navigation (no driver Firestore round-trip before push).
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MerchantProductsPage(
          merchantId: merchantId,
          merchantName: widget.peerName,
        ),
      ),
    );
  }

  Future<void> _startInAppCall({required bool video}) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      _toast('Sign in to start a call.');
      return;
    }

    var recipientId = _resolvedMerchantId();
    if (recipientId == null || recipientId.isEmpty) {
      final peerUserId = widget.peerUserId ?? _peerUserId;
      if (peerUserId != null && peerUserId > 0) {
        recipientId =
            await BackendChatService.getFirebaseUidByUserId(peerUserId);
      }
    }
    if (recipientId == null || recipientId.isEmpty) {
      _toast('Calling isn’t available for this chat yet.');
      return;
    }
    final peerUid = recipientId;
    if (peerUid == me.uid) {
      _toast('You can’t call yourself.');
      return;
    }

    // Mic/camera permission before opening the call UI.
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _toast('Microphone permission is required for calls.');
      return;
    }
    if (video) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        _toast('Camera permission is required for video calls.');
        return;
      }
    }

    try {
      final call = await CallServiceImpl().initiateCall(
        initiatorId: me.uid,
        recipientId: peerUid,
        callType: video ? CallType.video : CallType.voice,
        initiatorName: me.displayName ?? me.email ?? 'Vero360 user',
        initiatorAvatar: me.photoURL,
        recipientName: widget.peerName,
        recipientAvatar: widget.peerAvatarUrl,
      );

      // Leave a WhatsApp-style call marker in the thread (best effort).
      if (_myUserId != null && _chatId.isNotEmpty) {
        unawaited(
          BackendChatService.sendMessage(
            chatId: _chatId,
            content: video ? '📹 Video call' : '📞 Voice call',
            type: 'text',
            metadata: {
              'source': 'in_app_call',
              'callId': call.id,
              'callType': video ? 'video' : 'voice',
            },
          ),
        );
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _ChatCallScreen(
            call: call,
            peerName: widget.peerName,
            peerAvatarUrl: widget.peerAvatarUrl,
            peerUid: peerUid,
            video: video,
          ),
        ),
      );
    } catch (e) {
      _toast(UserFacingError.from(e, fallback: 'Could not start the call.'));
    }
  }

  int? _lastOutgoingMessageIndex() {
    final myId = _myUserId;
    if (myId == null) return null;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.isMine(myId) && !_isUnsent(m)) return i;
    }
    return null;
  }

  bool _isMessageRead(BackendChatMessage m) {
    final status = m.status.trim().toLowerCase();
    if (status == 'read' || status == 'seen' || m.readAt != null) return true;
    final receipt = _peerReceipt;
    if (receipt != null && receipt.coversRead(m.createdAt)) return true;
    return false;
  }

  bool _isMessageDelivered(BackendChatMessage m) {
    if (_isMessageRead(m)) return true;
    final status = m.status.trim().toLowerCase();
    if (status == 'delivered' || m.deliveredAt != null) return true;
    final receipt = _peerReceipt;
    if (receipt != null && receipt.coversDelivered(m.createdAt)) return true;
    return false;
  }

  Widget _buildMessageReceipt(BackendChatMessage msg, bool isLastOutgoing) {
    final read = _isMessageRead(msg);
    final delivered = _isMessageDelivered(msg);
    // ✓ sent · ✓✓ delivered (grey) · ✓✓ seen (blue)
    final tickColor =
        read ? const Color(0xFF53BDEB) : const Color(0xFF9CA3AF);

    return Icon(
      (delivered || read) ? Icons.done_all_rounded : Icons.check_rounded,
      size: 16,
      color: tickColor,
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
          onPressed: _me == null ? null : () => _startInAppCall(video: false),
          icon: const Icon(Icons.call_outlined, color: ink),
        ),
        IconButton(
          tooltip: 'Video call',
          onPressed: _me == null ? null : () => _startInAppCall(video: true),
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
            if (value == 'download') unawaited(_downloadChat());
            if (value == 'clear') _confirmClearChat();
            if (value == 'rate') unawaited(_promptRateSeller(force: true));
          },
          itemBuilder: (_) => [
            if (!_iAmTheMerchantForRating())
              const PopupMenuItem(
                value: 'rate',
                child: Row(
                  children: [
                    Icon(Icons.star_outline_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('Rate seller'),
                  ],
                ),
              ),
            PopupMenuItem(
              value: 'download',
              enabled: !_exportingChat && _messages.isNotEmpty,
              child: Row(
                children: [
                  Icon(
                    _exportingChat
                        ? Icons.hourglass_top_rounded
                        : Icons.download_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(_exportingChat ? 'Downloading…' : 'Download chat'),
                ],
              ),
            ),
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

  bool _leaving = false;

  /// True when the signed-in user owns this shop / is the merchant in the thread.
  bool _iAmTheMerchantForRating() {
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final merchantRef = (widget.peerMerchantId ??
            widget.resolveMerchantId ??
            widget.productContext?.merchantId ??
            '')
        .trim();
    if (myUid.isNotEmpty && merchantRef.isNotEmpty && myUid == merchantRef) {
      return true;
    }
    // Merchant reading a customer enquiry about their listing.
    if (_isMerchantViewingEnquiry) return true;
    return false;
  }

  String _merchantRefForRating() {
    return (widget.peerMerchantId ??
            widget.resolveMerchantId ??
            widget.productContext?.merchantId ??
            _cachedShopMerchantId ??
            '')
        .trim();
  }

  int? _merchantBackendIdForRating() {
    // Buyer chat: peer is the merchant. Prefer owner id from marketplace start.
    final owner = widget.resolveOwnerId;
    if (owner != null && owner > 0) return owner;
    final peer = widget.peerUserId ?? _peerUserId;
    if (peer != null && peer > 0) return peer;
    return null;
  }

  String _chatRatingContextKey() {
    final backendId = _merchantBackendIdForRating();
    final merchantRef = _merchantRefForRating();
    return _chatId.isNotEmpty
        ? 'chat:$_chatId'
        : 'chat_peer:${backendId ?? merchantRef}';
  }

  /// Facebook-style: only prompt after a real two-way conversation.
  /// Only buyers rate merchants — never the reverse.
  bool _eligibleForChatRating() {
    if (_iAmTheMerchantForRating()) return false;

    final myId = _myUserId;
    if (myId == null) return false;

    final merchantRef = _merchantRefForRating();
    final backendId = _merchantBackendIdForRating();
    if (merchantRef.isEmpty && (backendId == null || backendId <= 0)) {
      return false;
    }

    var mine = 0;
    var theirs = 0;
    for (final m in _messages) {
      if (m.isMine(myId)) {
        mine++;
      } else {
        theirs++;
      }
    }
    // Need both sides to have talked (not a one-sided enquiry).
    return mine >= 1 && theirs >= 1;
  }

  Future<void> _promptRateSeller({required bool force}) async {
    if (_iAmTheMerchantForRating()) {
      _toast('You can’t rate your own shop.');
      return;
    }
    if (!_eligibleForChatRating() && !force) return;

    final merchantRef = _merchantRefForRating();
    final backendId = _merchantBackendIdForRating();
    if (merchantRef.isEmpty && (backendId == null || backendId <= 0)) {
      _toast('Seller info is not available for rating yet.');
      return;
    }

    await MerchantReviewPrompt.maybeShow(
      context,
      merchantName: widget.peerName,
      reason: MerchantReviewReason.afterChat,
      contextKey: _chatRatingContextKey(),
      merchantRef: merchantRef.isEmpty ? null : merchantRef,
      serviceProviderId: widget.resolveServiceProviderId,
      sellerUserId: widget.resolveSellerUserId ?? merchantRef,
      // Buyer thread: peer/owner Nest id is the merchant.
      merchantBackendId: backendId,
      force: force,
    );
  }

  Future<void> _maybePromptChatRatingThenPop() async {
    if (_leaving) return;
    _leaving = true;
    try {
      if (_eligibleForChatRating() && mounted) {
        await _promptRateSeller(force: false);
      }
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
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
        !_recording;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_maybePromptChatRatingThenPop());
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: _buildModernAppBar(title: title, activeProduct: activeProduct),
        body: Column(
          children: [
            Expanded(child: _buildMessagesPane(activeProduct)),
            if (activeProduct != null) _buildDiscussedProductBar(activeProduct),
            _buildInputArea(canSend: canSend),
          ],
        ),
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
                  : Stack(
                      children: [
                        SlidableAutoCloseBehavior(
                          child: ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              // reverse:true shows index 0 at the bottom → newest first.
                              final index = _messages.length - 1 - i;
                              return _buildMessageTile(_messages[index], index);
                            },
                          ),
                        ),
                        if (_loadingOlder)
                          const Positioned(
                            top: 8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              ),
                            ),
                          ),
                      ],
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
    final isFailed = msg.status == 'failed';
    final isUnsent = isPending || isFailed;
    final showDateSeparator = _isDifferentDay(msg, prevMsg);
    final localBytes = _localImageFor(msg);
    final imageUrl = localBytes == null ? _messageImageUrl(msg) : null;
    final caption = _visibleCaption(msg, imageUrl);
    final audio = _messageAudio(msg);
    final localVoicePath = _localVoicePathFor(msg);
    final voiceDuration = _voiceDurationFor(msg, audio);
    final canAct = isMine && _within5Min(msg) && !isUnsent;
    final isLastOutgoing = isMine && index == _lastOutgoingMessageIndex();
    final scanText = [
      caption,
      msg.content,
    ].whereType<String>().join('\n');
    final showOffPlatformWarning =
        ChatOffPlatformDetector.containsSensitiveDetails(scanText);

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
                  opacity: isPending ? 0.72 : (isFailed ? 0.92 : 1),
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
                        if (_isStoryReply(msg))
                          _buildStoryReplyChip(msg, isMine: isMine),
                        if (msg.replyTo != null && !_isStoryReply(msg))
                          _buildReplyQuoteChip(msg.replyTo!, isMine: isMine),
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
                                memCacheWidth: 440,
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
                    if (isFailed) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Tap to retry',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (isMine && !isUnsent) ...[
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
          onTap: isFailed ? () => unawaited(_retryUnsent(msg)) : null,
          onLongPress: () {
            if (isUnsent) {
              _showUnsentActions(msg);
            } else if (canAct) {
              _showMsgActions(msg);
            } else {
              _startReply(msg);
            }
          },
          child: Slidable(
            key: ValueKey('msg_${msg.clientMessageId ?? msg.id}'),
            groupTag: 'chat_messages',
            startActionPane: isUnsent
                ? null
                : ActionPane(
                    motion: const StretchMotion(),
                    extentRatio: 0.18,
                    children: [
                      CustomSlidableAction(
                        onPressed: (_) => _startReply(msg),
                        backgroundColor: Colors.transparent,
                        foregroundColor: _brandOrange,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.reply_rounded, color: _brandOrange),
                            SizedBox(height: 4),
                            Text(
                              'Reply',
                              style: TextStyle(
                                color: _brandOrange,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
            child: bubble,
          ),
        ),
        if (showOffPlatformWarning) const ChatOffPlatformWarning(),
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
            if (_replyingTo != null) _buildComposerReplyBar(),
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
            if (_outboxFlushing.isNotEmpty)
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
                      onTap: _recording ? null : _showAttachSheet,
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
                  if (canSend)
                    AnimatedScale(
                      scale: 1,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
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
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _sendMessage,
                            borderRadius: BorderRadius.circular(24),
                            child: const Center(
                              child: Icon(
                                Icons.arrow_upward_rounded,
                                color: Colors.white,
                                size: 22,
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
            onPressed: _cancelVoiceRecording,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: _stopVoiceRecordingAndSend,
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

/// In-app voice/video call UI (Firestore signaling + live call chrome).
class _ChatCallScreen extends StatefulWidget {
  const _ChatCallScreen({
    required this.call,
    required this.peerName,
    required this.peerUid,
    required this.video,
    this.peerAvatarUrl,
  });

  final CallSession call;
  final String peerName;
  final String peerUid;
  final String? peerAvatarUrl;
  final bool video;

  @override
  State<_ChatCallScreen> createState() => _ChatCallScreenState();
}

enum _CallPhase { calling, ringing, connected }

class _ChatCallScreenState extends State<_ChatCallScreen> {
  static const _orange = Color(0xFFFF8A00);
  final _calls = CallServiceImpl();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  Timer? _presenceTimer;
  Timer? _durationTimer;
  int _seconds = 0;
  bool _micOn = true;
  bool _camOn = true;
  bool _ending = false;
  bool _peerOnline = false;
  _CallPhase _phase = _CallPhase.calling;

  @override
  void initState() {
    super.initState();
    _phase = _CallPhase.calling;
    unawaited(_refreshPeerPresence(initial: true));
    _presenceTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_phase == _CallPhase.connected) return;
      unawaited(_refreshPeerPresence());
    });
    _callSub = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.call.id)
        .snapshots()
        .listen(_onCallDoc, onError: (_) {});
  }

  Future<void> _refreshPeerPresence({bool initial = false}) async {
    final online = await _isPeerOnline(widget.peerUid);
    if (!mounted || _phase == _CallPhase.connected) return;
    setState(() {
      _peerOnline = online;
      // Offline → Calling. Online (not yet answered) → Ringing.
      _phase = online ? _CallPhase.ringing : _CallPhase.calling;
    });
  }

  Future<bool> _isPeerOnline(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return false;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(id).get();
      final data = doc.data() ?? const <String, dynamic>{};
      if (data['isOnline'] == true ||
          data['online'] == true ||
          data['presence'] == 'online') {
        return true;
      }
      final raw = data['lastSeen'] ??
          data['lastActiveAt'] ??
          data['lastActive'] ??
          data['updatedAt'];
      DateTime? at;
      if (raw is Timestamp) {
        at = raw.toDate();
      } else if (raw is String) {
        at = DateTime.tryParse(raw);
      } else if (raw is int) {
        at = DateTime.fromMillisecondsSinceEpoch(
          raw > 20000000000 ? raw : raw * 1000,
        );
      }
      if (at != null &&
          DateTime.now().difference(at) <= const Duration(minutes: 2)) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _onCallDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!mounted || !snap.exists) return;
    final data = snap.data() ?? const <String, dynamic>{};
    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    final answered = data['answeredAt'] != null;
    final connected = answered ||
        status == 'active' ||
        status == CallStatus.active.name;

    if (connected && _phase != _CallPhase.connected) {
      _enterConnected();
      return;
    }

    if (status == 'ended' ||
        status == 'declined' ||
        status == 'missed' ||
        status == 'failed') {
      if (!_ending) unawaited(_end(pop: true));
    }
  }

  void _enterConnected() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    setState(() {
      _phase = _CallPhase.connected;
      _seconds = 0;
    });
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _presenceTimer?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  String get _statusLabel {
    switch (_phase) {
      case _CallPhase.calling:
        return 'Calling…';
      case _CallPhase.ringing:
        return 'Ringing…';
      case _CallPhase.connected:
        return _clock;
    }
  }

  String get _clock {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _end({bool pop = true}) async {
    if (_ending) return;
    setState(() => _ending = true);
    _presenceTimer?.cancel();
    _durationTimer?.cancel();
    try {
      final dur = _phase == _CallPhase.connected ? _seconds : 0;
      await _calls.endCall(widget.call.id, dur);
    } catch (_) {}
    if (pop && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = (widget.peerAvatarUrl ?? '').trim();
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 28),
            Text(
              widget.video ? 'Video call' : 'Voice call',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            CircleAvatar(
              radius: 54,
              backgroundColor: _orange.withValues(alpha: 0.25),
              backgroundImage:
                  avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar.isEmpty
                  ? Text(
                      widget.peerName.isNotEmpty
                          ? widget.peerName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              widget.peerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusLabel,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _phase == _CallPhase.connected
                  ? 'Connected'
                  : (_peerOnline ? 'Online' : 'Offline'),
              style: TextStyle(
                color: _phase == _CallPhase.connected || _peerOnline
                    ? const Color(0xFF22C55E)
                    : Colors.white54,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (widget.video) ...[
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white12),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _camOn
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        color: Colors.white70,
                        size: 42,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _camOn ? 'Camera on' : 'Camera off',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else
              const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _roundBtn(
                    icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    label: _micOn ? 'Mute' : 'Unmute',
                    onTap: () => setState(() => _micOn = !_micOn),
                  ),
                  if (widget.video)
                    _roundBtn(
                      icon: _camOn
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      label: _camOn ? 'Camera' : 'Cam off',
                      onTap: () => setState(() => _camOn = !_camOn),
                    ),
                  _roundBtn(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    color: const Color(0xFFEF4444),
                    onTap: _ending ? null : () => _end(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color color = const Color(0xFF2A2F3A),
  }) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
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
