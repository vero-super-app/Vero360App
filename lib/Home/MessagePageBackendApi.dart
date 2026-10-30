
import 'dart:async';
import 'package:universal_io/io.dart' show File;
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
import 'package:video_player/video_player.dart';

import 'package:vero360_app/GeneralModels/call_model.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/buyer_commission.dart';
import 'package:vero360_app/GernalServices/backend_messaging_cache.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/GernalServices/call_service_impl.dart';
import 'package:vero360_app/GernalServices/live_call_session.dart';
import 'package:vero360_app/GernalServices/chat_outbox.dart';
import 'package:vero360_app/GernalServices/chat_notification_service.dart';
import 'package:vero360_app/GernalServices/chat_receipt_service.dart';
import 'package:vero360_app/GernalServices/hidden_message_store.dart';
import 'package:vero360_app/GernalServices/message_reaction_service.dart';
import 'package:vero360_app/GernalServices/user_presence_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/GeneralModels/chat_product_context.dart';
import 'package:vero360_app/widgets/modern_confirm_dialog.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';
import 'package:vero360_app/utils/user_facing_error.dart';
import 'package:vero360_app/utils/display_name_sync.dart';
import 'package:vero360_app/widgets/linkified_text.dart';
import 'package:vero360_app/widgets/messaging_skeleton_loaders.dart';
import 'package:vero360_app/widgets/voice_note_bubble.dart';
import 'package:vero360_app/utils/chat_offplatform_detector.dart';
import 'package:vero360_app/widgets/chat_offplatform_warning.dart';
import 'package:vero360_app/GeneralPages/checkout_page.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart'
    as core;
import 'package:vero360_app/features/Marketplace/presentation/pages/Marketplace_detailsPage.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:vero360_app/features/Marketplace/presentation/widgets/merchant_review_prompt.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_id_resolver.dart';
import 'package:vero360_app/app_nav_key.dart';

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

class _MessagePageBackendApiState extends State<MessagePageBackendApi>
    with WidgetsBindingObserver {
  String? _me;
  int? _myUserId;
  late String _chatId;
  int? _peerUserId;
  late String _peerDisplayName;
  String _peerAvatarUrl = '';

  final _input = TextEditingController();
  final _scroll = ScrollController();

  bool _loading = true;
  bool _bootComplete = false;
  bool _resolvingChat = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _peerPresenceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _memberSub;
  String? _presenceRoomId;
  bool _roomKnown = false;
  bool _roomFlagged = false;
  bool _roomTypingFlag = false;
  bool _roomOnline = false;
  bool _roomTyping = false;
  DateTime? _roomSeen;
  DateTime? _roomTypingAt;
  Timer? _presenceTick;
  String? _watchedPeerUid;
  bool _peerPresenceKnown = false;
  bool _peerPresenceFlagged = false;
  bool _peerOnline = false;
  bool _peerTyping = false;
  DateTime? _peerLastSeen;
  DateTime? _peerTypingUntil;
  bool _productTagAttached = false;
  String? _loadError;
  List<BackendChatMessage> _messages = [];
  Timer? _fallbackPollTimer;
  Timer? _readStatusPollTimer;
  StreamSubscription<BackendChatMessage>? _wsMessageSub;
  StreamSubscription<bool>? _wsConnectionSub;
  StreamSubscription<ChatPeerReceipt?>? _peerReceiptSub;
  ChatPeerReceipt? _peerReceipt;
  int? _boundReceiptPeerId;
  /// Sticky watermarks â€” never move backwards so ticks don't flicker on poll/rebind.
  DateTime? _stickyPeerReadUpTo;
  DateTime? _stickyPeerDeliveredUpTo;

  /// Stay pinned to newest only when the user is already near the bottom.
  bool _stickToBottom = true;
  /// Bumped to cancel in-flight â€œpin to latestâ€ retries when the user scrolls away.
  int _scrollPinToken = 0;
  /// True while a finger is dragging the message list (cancels pin + eases Slidable fight).
  bool _fingerDraggingList = false;
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
  final Set<String> _hiddenMessageIds = {};
  final Map<String, GlobalKey> _messageAnchorKeys = {};
  String? _highlightedMessageKey;
  Timer? _highlightClearTimer;

  static const _reactionEmojis = ['ðŸ‘', 'â¤ï¸', 'ðŸ˜‚', 'ðŸ˜®', 'ðŸ˜¢', 'ðŸ™'];
  static const _imgPrefix = 'img::';
  static const _vidPrefix = 'vid::';
  static const _audPrefix = 'aud::';
  static const _minVoiceMs = 800;
  static const _maxVoiceMs = 180000;
  static const _brandOrange = Color(0xFFFF8A00);
  static const _bg = Color(0xFFF3F4F7);
  static const _fallbackPollInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatId = widget.peerId.trim();
    _peerUserId = widget.peerUserId;
    _peerDisplayName = widget.peerName.trim().isEmpty ? 'Chat' : widget.peerName.trim();
    _peerAvatarUrl = (widget.peerAvatarUrl ?? '').trim();
    if (BackendChatService.isMyPhoto(_peerAvatarUrl)) _peerAvatarUrl = '';
    _resolvingChat = _chatId.isEmpty;
    // Show seller chat chrome immediately (messages may still be loading).
    _bootComplete = _peerDisplayName.isNotEmpty &&
        _peerDisplayName.toLowerCase() != 'chat';

    unawaited(UserPresenceService.goOnline());
    if (_chatId.isNotEmpty) unawaited(_syncPresenceRoom());
    unawaited(_hydratePeerDisplayName());
    unawaited(_hydratePeerAvatar());

    if (_chatId.isNotEmpty) {
      BackendChatService.setActiveChatId(_chatId);
      BackendChatService.clearThreadUnread(_chatId);
      unawaited(_loadHiddenMessages());

      // Instant paint from memory/disk â€” never wait on auth/network for this.
      final warm = BackendChatService.peekCachedMessages(_chatId);
      if (warm.isNotEmpty) {
        _messages = warm;
        _loading = false;
        _bootComplete = true;
        if (_hasProductTagInMessages(_messages)) {
          _productTagAttached = true;
        }
      }

      unawaited(_paintCachedMessages());
    }

    _boot();
    unawaited(_prefetchShopMerchantId());

    _input.addListener(() {
      if (!mounted) return;
      setState(() {});
      final text = _input.text.trim();
      if (text.isEmpty) {
        unawaited(UserPresenceService.clearTyping());
      } else {
        unawaited(UserPresenceService.pulseTyping(_chatId));
      }
    });
    _scroll.addListener(_onScrollPositionChanged);

    _startRealtime();
    unawaited(_bindPeerPresence());
    _presenceTick = Timer.periodic(const Duration(seconds: 5), (_) {
      _recomputePresence();
    });
  }

  /// WhatsApp-style: show local history immediately, then refresh from network.
  Future<void> _paintCachedMessages() async {
    if (_chatId.isEmpty) return;
    final cached = await BackendChatService.loadCachedMessages(_chatId);
    if (!mounted || cached.isEmpty) return;
    final hadLocal = _messages.isNotEmpty;
    setState(() {
      // Prefer richer local list if we already painted memory and disk is equal/smaller.
      if (!hadLocal || cached.length >= _messages.length) {
        _messages = cached;
      }
      _loading = false;
      _bootComplete = true;
      if (_hasProductTagInMessages(_messages)) {
        _productTagAttached = true;
      }
    });
    _prefetchThreadVoiceNotes();
    unawaited(Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (mounted) _prefetchChatImages();
    }));
    if (_stickToBottom) {
      _scheduleScrollToLatest(forceStick: true);
    }
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
    // reverse:true â€” pixels â‰ˆ 0 is the newest messages.
    final atBottom = pos.pixels <= _nearBottomPx;
    if (!atBottom && _stickToBottom) {
      _scrollPinToken++;
    }
    _stickToBottom = atBottom;
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
      // Peer received our message on their device â†’ treat as delivered locally
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final id = _chatId.trim();
    if (state == AppLifecycleState.resumed) {
      unawaited(UserPresenceService.goOnline());
      if (id.isNotEmpty) unawaited(UserPresenceService.enterChat(id));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(UserPresenceService.goOffline());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final chatId = _chatId.trim();
    final myUserId = _myUserId;
    if (chatId.isNotEmpty) {
      BackendChatService.clearThreadUnread(chatId);
      if (myUserId != null) {
        final unreadIds = _messages
            .where((m) => !m.isMine(myUserId) && !_isUnsent(m))
            .map((m) => m.id)
            .where((id) => id.isNotEmpty)
            .toList();
        if (unreadIds.isNotEmpty) {
          unawaited(
            BackendChatService.markRead(
              chatId: chatId,
              messageIds: unreadIds,
            ),
          );
        }
      }
    }
    BackendChatService.setActiveChatId(null);
    unawaited(UserPresenceService.clearTyping());
    if (_presenceRoomId != null && _presenceRoomId!.isNotEmpty) {
      unawaited(UserPresenceService.leaveChat(_presenceRoomId!));
    }
    _presenceTick?.cancel();
    unawaited(_peerPresenceSub?.cancel());
    unawaited(_memberSub?.cancel());
    _fallbackPollTimer?.cancel();
    _readStatusPollTimer?.cancel();
    _recordTimer?.cancel();
    unawaited(_recorder.dispose());
    _wsMessageSub?.cancel();
    _wsConnectionSub?.cancel();
    _peerReceiptSub?.cancel();
    _boundReceiptPeerId = null;
    if (chatId.isNotEmpty) {
      unawaited(BackendMessagingSocket.leaveChat(chatId));
    }
    _input.dispose();
    _scroll.removeListener(_onScrollPositionChanged);
    _scroll.dispose();
    _highlightClearTimer?.cancel();
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
      unawaited(_syncPresenceRoom());
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
          unawaited(_loadHiddenMessages());
          await _hydrateOutbox();
        }
      }).catchError((_) {}));

      // Paint cache before any network await (WhatsApp-style).
      if (_chatId.isNotEmpty && _messages.isEmpty) {
        await _paintCachedMessages();
      }

      // Resolve chat + auth in parallel when needed.
      final resolveFuture = _resolveChatIfNeeded();
      final authFuture = BackendChatService.ensureAuth();

      final resolved = await resolveFuture;
      if (!resolved || !mounted) return;

      BackendChatService.setActiveChatId(_chatId);

      // Chat id may have been resolved just now â€” paint that thread's cache.
      if (_messages.isEmpty) {
        await _paintCachedMessages();
      } else if (mounted) {
        setState(() {
          _loading = false;
          _bootComplete = true;
        });
      }

      // Don't block message fetch on joinChat.
      unawaited(_bindPeerPresence());
      unawaited(BackendMessagingSocket.joinChat(_chatId).catchError((_) {}));

      await authFuture;
      final userId = await BackendChatService.getUserId();

      // Background refresh â€” UI already shows cache when available.
      unawaited(() async {
        await _loadMessages(silent: _messages.isNotEmpty);
        if (!mounted) return;
        await _markUnreadAsRead(userId);
        if (mounted) await _maybeSendAutoMessage(userId);
      }());
      unawaited(_maybeSendProductEnquiry(userId));

      if (!mounted) return;
      setState(() {
        _myUserId = userId;
        _me = userId.toString();
        _bootComplete = true;
        if (_messages.isNotEmpty) _loading = false;
      });
      unawaited(_loadHiddenMessages());
      _bindPeerReceiptListener(userId);
      unawaited(_hydratePeerDisplayName());
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
      if (existing.contains('we have received your order') &&
          existing.contains('please confirm your details')) {
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
        clientMessageId:
            rawClientId.isNotEmpty ? rawClientId : const Uuid().v4(),
        metadata: {
          'source': 'orders',
          'autoOrderReceived': true,
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
      // Never re-force pin after the user has scrolled away â€” that made the
      // first swipe feel sticky / not smooth while messages finished loading.
      final shouldPin = _stickToBottom && !_fingerDraggingList;

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
      if (!_fingerDraggingList) {
        unawaited(Future<void>.delayed(const Duration(milliseconds: 280), () {
          if (mounted && !_fingerDraggingList) _prefetchChatImages();
        }));
      }
      // Opening/refreshing the chat means we've delivered + read incoming msgs.
      unawaited(_publishMyReceipts(asRead: true));
      final myId = _myUserId;
      if (myId != null) {
        unawaited(_markUnreadAsRead(myId));
      }

      if (shouldPin) {
        _scheduleScrollToLatest(forceStick: wasEmpty);
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
      // Persist merged history so reopen doesn't wait on network for older pages.
      final myId = _myUserId ?? BackendChatService.peekUserId();
      if (myId != null && myId > 0) {
        unawaited(
          BackendMessagingCache.saveMessages(myId, _chatId, _messages),
        );
      }
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
    BackendChatService.clearThreadUnread(_chatId);
    if (unreadIds.isEmpty) return;
    try {
      await BackendChatService.markRead(
        chatId: _chatId,
        messageIds: unreadIds,
      );
      // Keep local zero; avoid an immediate refresh that can resurrect a
      // still-stale Nest unreadCount before the bulk/read write settles.
      BackendChatService.clearThreadUnread(_chatId);
    } catch (_) {}
  }

  void _bindPeerReceiptListener(int myUserId) {
    final peerId = _peerUserId ?? widget.peerUserId;
    if (_chatId.isEmpty || peerId == null || peerId <= 0) return;
    // Already listening for this peer â€” don't cancel (kills ticks during polls).
    if (_peerReceiptSub != null && _boundReceiptPeerId == peerId) return;

    _peerReceiptSub?.cancel();
    _boundReceiptPeerId = peerId;
    _peerReceiptSub = ChatReceiptService.watchUserReceipt(
      chatId: _chatId,
      userId: peerId,
    ).listen((receipt) {
      if (!mounted) return;
      setState(() {
        if (receipt != null) {
          _peerReceipt = receipt;
          final read = receipt.readUpTo;
          if (read != null &&
              (_stickyPeerReadUpTo == null ||
                  read.isAfter(_stickyPeerReadUpTo!))) {
            _stickyPeerReadUpTo = read;
          }
          final delivered = receipt.deliveredUpTo;
          if (delivered != null &&
              (_stickyPeerDeliveredUpTo == null ||
                  delivered.isAfter(_stickyPeerDeliveredUpTo!))) {
            _stickyPeerDeliveredUpTo = delivered;
          }
        }
        // Never clear sticky watermarks when stream briefly emits null.
      });
    });
  }

  void _ensurePeerUserIdFromMessages() {
    final myId = _myUserId;
    if (myId == null) return;

    if ((_peerUserId ?? 0) > 0) {
      _bindPeerReceiptListener(myId);
      unawaited(_hydratePeerDisplayName());
      unawaited(_hydratePeerAvatar());
      return;
    }
    for (final m in _messages) {
      if (!m.isMine(myId) && m.senderId > 0) {
        _peerUserId = m.senderId;
        _bindPeerReceiptListener(myId);
        unawaited(_hydratePeerDisplayName());
        unawaited(_hydratePeerAvatar());
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
    unawaited(_hydratePeerDisplayName());
    unawaited(_hydratePeerAvatar());
  }

  bool _isPlaceholderPeerName(String raw) =>
      ChatParticipant.isPlaceholderName(raw);

  /// Story / notification opens often arrive as "Chat" â€” fill the real name.
  Future<void> _hydratePeerDisplayName() async {
    await BackendChatService.ensureBusinessNameCacheLoaded();
    if (!mounted) return;

    String? next;
    if (!_isPlaceholderPeerName(_peerDisplayName)) {
      next = _peerDisplayName;
    }

    if (next == null || _isPlaceholderPeerName(next)) {
      final cached = BackendChatService.cachedPeerLabelForChat(_chatId);
      if (cached != null && !_isPlaceholderPeerName(cached.name)) {
        next = cached.name;
        if ((cached.peerUserId ?? 0) > 0 && (_peerUserId ?? 0) <= 0) {
          _peerUserId = cached.peerUserId;
        }
      }
    }

    if (next == null || _isPlaceholderPeerName(next)) {
      final myId = _myUserId;
      if (myId != null) {
        for (final m in _messages) {
          if (m.isMine(myId)) continue;
          final sender = m.sender;
          if (sender == null) continue;
          for (final key in [
            'businessName',
            'name',
            'displayName',
            'username',
            'fullName',
          ]) {
            final v = (sender[key] ?? '').toString().trim();
            if (v.isNotEmpty &&
                !_isPlaceholderPeerName(v) &&
                !v.contains('@')) {
              next = v;
              break;
            }
          }
          if (next != null && !_isPlaceholderPeerName(next)) break;
        }
      }
    }

    if (next == null || _isPlaceholderPeerName(next)) {
      next = await BackendChatService.resolvePeerTitle(
        chatId: _chatId,
        peerUserId: _peerUserId ?? widget.peerUserId,
      );
    }

    if (next == null || _isPlaceholderPeerName(next)) return;
    if (!mounted) return;
    if (_peerDisplayName == next) return;
    setState(() {
      _peerDisplayName = next!;
      _bootComplete = true;
    });
  }

  String? get _shownPeerAvatar {
    final live = _peerAvatarUrl.trim();
    if (live.startsWith('http') && !_isMyPhoto(live)) return live;
    final passed = (widget.peerAvatarUrl ?? '').trim();
    if (passed.startsWith('http') && !_isMyPhoto(passed)) return passed;
    return null;
  }

  /// Collect my own photo URLs so they are never shown as the other person.
  Future<void> _learnMyPhotos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in ['profilepicture', 'profilePicture', 'photoUrl']) {
        BackendChatService.rememberMyPhoto(prefs.getString(key));
      }
    } catch (_) {}
    final myId = _myUserId;
    if (myId == null) return;
    for (final m in _messages) {
      if (m.isMine(myId)) BackendChatService.rememberMyPhoto(_senderProfileUrl(m));
    }
    final thread = BackendChatService.findCachedThreadById(_chatId);
    for (final p in thread?.participants ?? const <ChatParticipant>[]) {
      if (p.id == myId) BackendChatService.rememberMyPhoto(p.profilePicture);
    }
  }

  bool _isMyPhoto(String url) => BackendChatService.isMyPhoto(url);

  String _senderProfileUrl(BackendChatMessage m) {
    final sender = m.sender;
    if (sender == null) return '';
    for (final key in [
      'profilePicture',
      'profilepicture',
      'avatarUrl',
      'photoUrl',
      'photoURL',
    ]) {
      final v = (sender[key] ?? '').toString().trim();
      if (v.startsWith('http')) return v;
    }
    return '';
  }

  bool _samePhotoUrl(String a, String b) {
    String norm(String raw) {
      final uri = Uri.tryParse(raw.trim());
      if (uri == null) return raw.trim();
      return '${uri.scheme}://${uri.host}${uri.path}';
    }

    return norm(a) == norm(b);
  }

  bool _isSenderProfilePhoto(String url, BackendChatMessage m) {
    final candidates = <String>[
      _senderProfileUrl(m),
      _peerAvatarUrl,
      widget.peerAvatarUrl ?? '',
    ];
    for (final candidate in candidates) {
      if (candidate.trim().isEmpty) continue;
      if (_samePhotoUrl(url, candidate)) return true;
    }
    return false;
  }

  /// Keep the other person's photo on the header and their messages.
  Future<void> _hydratePeerAvatar() async {
    await BackendChatService.ensureAvatarCacheLoaded();
    await _learnMyPhotos();
    if (!mounted) return;

    bool usable(String url) => url.startsWith('http') && !_isMyPhoto(url);

    final myId = _myUserId;
    final peerId = _peerUserId ?? widget.peerUserId ?? 0;
    if (peerId > 0) {
      BackendChatService.forgetPeerAvatarIfMine(
        ChatParticipant(id: peerId, name: _peerDisplayName, email: ''),
      );
    }

    // The other person's own messages are the most trustworthy source.
    String next = '';
    if (myId != null) {
      for (final m in _messages.reversed) {
        if (m.isMine(myId)) continue;
        final photo = _senderProfileUrl(m);
        if (usable(photo)) {
          next = photo;
          break;
        }
      }
    }

    if (!usable(next) && _chatId.isNotEmpty && (myId ?? 0) > 0) {
      final thread = BackendChatService.findCachedThreadById(_chatId);
      if (thread != null) {
        final url = BackendChatService.peerAvatarUrlForThread(thread, myId!);
        if (usable(url)) next = url;
      }
    }

    if (!usable(next)) {
      final live = _peerAvatarUrl.trim();
      final passed = (widget.peerAvatarUrl ?? '').trim();
      if (usable(live)) {
        next = live;
      } else if (usable(passed)) {
        next = passed;
      }
    }

    if (!usable(next)) {
      final cached = BackendChatService.cachedPeerLabelForChat(_chatId);
      final avatar = cached?.avatarUrl.trim() ?? '';
      if (usable(avatar)) next = avatar;
    }

    if (!usable(next)) {
      if (_peerAvatarUrl.isNotEmpty && _isMyPhoto(_peerAvatarUrl) && mounted) {
        setState(() => _peerAvatarUrl = '');
      }
      return;
    }
    if (peerId > 0) {
      BackendChatService.rememberPeerAvatar(
        ChatParticipant(id: peerId, name: _peerDisplayName, email: ''),
        next,
      );
    }
    if (next == _peerAvatarUrl || !mounted) return;
    setState(() => _peerAvatarUrl = next);
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
    final localByKey = <String, BackendChatMessage>{};
    for (final m in _messages) {
      localByKey[_messageKey(m)] = m;
    }

    final merged = <BackendChatMessage>[];
    final usedLocalKeys = <String>{};

    for (final s in server) {
      final key = _messageKey(s);
      BackendChatMessage? local = localByKey[key];
      if (local == null && myId != null) {
        for (final entry in localByKey.entries) {
          if (usedLocalKeys.contains(entry.key)) continue;
          if (_isSameMessage(s, entry.value, myId)) {
            local = entry.value;
            usedLocalKeys.add(entry.key);
            break;
          }
        }
      } else {
        usedLocalKeys.add(key);
      }
      merged.add(_coalesceReceipt(s, local));
    }

    // Keep pending/failed + just-sent bubbles until the server page catches up.
    for (final local in _messages) {
      final key = _messageKey(local);
      if (usedLocalKeys.contains(key)) continue;
      if (myId != null &&
          server.any((s) => _isSameMessage(s, local, myId))) {
        continue;
      }
      if (_isUnsent(local) || _isRecentLocalSent(local, myId)) {
        merged.add(local);
      }
    }

    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  String _messageKey(BackendChatMessage m) {
    if (m.id.isNotEmpty) return 'id:${m.id}';
    final cid = m.clientMessageId?.trim();
    if (cid != null && cid.isNotEmpty) return 'cid:$cid';
    return 't:${m.createdAt.millisecondsSinceEpoch}:${m.senderId}:${m.content}';
  }

  bool _isRecentLocalSent(BackendChatMessage m, int? myId) {
    if (myId == null || !m.isMine(myId)) return false;
    if (_isUnsent(m)) return true;
    return DateTime.now().difference(m.createdAt) <=
        const Duration(minutes: 2);
  }

  int _statusRank(String status) {
    switch (status.trim().toLowerCase()) {
      case 'read':
      case 'seen':
        return 4;
      case 'delivered':
        return 3;
      case 'sent':
        return 2;
      case 'pending':
      case 'queued':
        return 1;
      case 'failed':
        return 0;
      default:
        return 1;
    }
  }

  /// Keep the strongest receipt fields when Nest silently refreshes as `sent`.
  BackendChatMessage _coalesceReceipt(
    BackendChatMessage incoming,
    BackendChatMessage? local,
  ) {
    if (local == null) return _applyStickyReceipt(incoming);

    var status = incoming.status;
    var readAt = incoming.readAt ?? local.readAt;
    var deliveredAt = incoming.deliveredAt ?? local.deliveredAt;

    if (_statusRank(local.status) > _statusRank(incoming.status)) {
      status = local.status;
    }
    if (local.readAt != null &&
        (readAt == null || local.readAt!.isAfter(readAt))) {
      readAt = local.readAt;
    }
    if (local.deliveredAt != null &&
        (deliveredAt == null || local.deliveredAt!.isAfter(deliveredAt))) {
      deliveredAt = local.deliveredAt;
    }

    // Prefer server id / richer payload, but never lose ticks.
    final preferred = incoming.copyWith(
      status: status,
      readAt: readAt,
      deliveredAt: deliveredAt,
      clientMessageId: incoming.clientMessageId ?? local.clientMessageId,
      metadata: incoming.metadata ?? local.metadata,
      attachments: incoming.attachments ?? local.attachments,
      tags: incoming.tags ?? local.tags,
    );
    return _applyStickyReceipt(preferred);
  }

  BackendChatMessage _applyStickyReceipt(BackendChatMessage m) {
    final myId = _myUserId;
    if (myId == null || !m.isMine(myId) || _isUnsent(m)) return m;

    final stickyRead = _stickyPeerReadUpTo;
    final stickyDelivered = _stickyPeerDeliveredUpTo;
    var status = m.status;
    var readAt = m.readAt;
    var deliveredAt = m.deliveredAt;

    if (stickyRead != null &&
        !m.createdAt.isAfter(stickyRead.add(const Duration(seconds: 8)))) {
      status = 'read';
      readAt ??= stickyRead;
    } else if (stickyDelivered != null &&
        !m.createdAt
            .isAfter(stickyDelivered.add(const Duration(seconds: 8)))) {
      if (_statusRank(status) < _statusRank('delivered')) {
        status = 'delivered';
      }
      deliveredAt ??= stickyDelivered;
    }

    if (status == m.status &&
        readAt == m.readAt &&
        deliveredAt == m.deliveredAt) {
      return m;
    }
    return m.copyWith(
      status: status,
      readAt: readAt,
      deliveredAt: deliveredAt,
    );
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

  Widget _buildReactionRow(BackendChatMessage msg, {required bool isMine}) {
    return StreamBuilder<Map<String, String>>(
      stream: MessageReactionService.watch(
        chatId: _chatId,
        messageId: msg.id,
      ),
      builder: (context, snap) {
        final byUid = snap.data ?? const <String, String>{};
        if (byUid.isEmpty) return const SizedBox.shrink();
        final counts = <String, int>{};
        for (final emoji in byUid.values) {
          counts[emoji] = (counts[emoji] ?? 0) + 1;
        }
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        final myEmoji = myUid == null ? null : byUid[myUid];
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: isMine ? WrapAlignment.end : WrapAlignment.start,
            children: [
              for (final entry in counts.entries)
                GestureDetector(
                  onTap: () => unawaited(_reactToMessage(msg, entry.key)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: myEmoji == entry.key
                          ? _brandOrange.withValues(alpha: 0.18)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: myEmoji == entry.key
                            ? _brandOrange
                            : Colors.black12,
                      ),
                    ),
                    child: Text(
                      '${entry.key} ${entry.value}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
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
    if (text.startsWith(_vidPrefix)) return 'Video';
    final masked = ChatOffPlatformDetector.maskPhones(text);
    return masked.length > 120 ? '${masked.substring(0, 120)}â€¦' : masked;
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

  bool _isForwarded(BackendChatMessage m) {
    final meta = m.metadata;
    if (meta != null) {
      final flag =
          meta['forwarded'] ?? meta['isForwarded'] ?? meta['forwardedMessage'];
      if (flag == true ||
          flag == 1 ||
          flag?.toString().toLowerCase() == 'true') {
        return true;
      }
    }
    final content = (m.content ?? '');
    return content.contains('â†ªï¸ Forwarded') ||
        content.startsWith('Forwarded:');
  }

  /// Strip the Forwarded marker line from message body for display/copy.
  String _stripForwardedMarker(String content) {
    final lines = content.split('\n');
    final kept = lines.where((l) {
      final t = l.trim();
      return t != 'â†ªï¸ Forwarded' && t != 'Forwarded:' && t != 'Forwarded';
    }).toList();
    return kept.join('\n').trim();
  }

  Widget _buildForwardedLabel({required bool isMine}) {
    final color = isMine ? Colors.white70 : Colors.black45;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.flip(
            flipX: true,
            child: Icon(Icons.reply_rounded, size: 14, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            'Forwarded',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
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

  /// User-facing reply text without the "â†©ï¸ Story reply" header.
  String? _storyReplyBody(BackendChatMessage m) {
    final content = (m.content ?? '').trim();
    if (content.isEmpty) return null;
    if (content.startsWith(_imgPrefix) || content.startsWith(_vidPrefix)) {
      final parts = content.split('\n');
      if (parts.length < 2) return null;
      final rest = parts.sublist(1).join('\n').trim();
      return rest.isEmpty ? null : rest;
    }
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

  GlobalKey _anchorKeyForMessage(BackendChatMessage m) {
    final key = _messageKey(m);
    return _messageAnchorKeys.putIfAbsent(key, GlobalKey.new);
  }

  BackendChatMessage? _messageMatchingReply(Map<String, dynamic> reply) {
    final targetId =
        (reply['messageId'] ?? reply['id'] ?? '').toString().trim();
    final targetCid = (reply['clientMessageId'] ?? '').toString().trim();
    final preview = (reply['preview'] ?? '').toString().trim();

    for (final m in _visibleMessages) {
      if (targetId.isNotEmpty && m.id == targetId) return m;
      if (targetCid.isNotEmpty &&
          (m.clientMessageId ?? '').trim() == targetCid) {
        return m;
      }
    }
    // Fallback: match preview text when ids were dropped by the backend.
    if (preview.isNotEmpty) {
      for (final m in _visibleMessages.reversed) {
        if (_replyPreviewFor(m) == preview) return m;
      }
    }
    return null;
  }

  Future<void> _jumpToRepliedMessage(Map<String, dynamic> reply) async {
    var target = _messageMatchingReply(reply);
    var attempts = 0;
    while (target == null && _hasMoreOlder && attempts < 10) {
      attempts++;
      final beforeCount = _messages.length;
      await _loadOlderMessages();
      if (!mounted) return;
      target = _messageMatchingReply(reply);
      if (target != null) break;
      if (_messages.length == beforeCount) break;
    }

    if (target == null) {
      _toast('Original message isnâ€™t loaded yet');
      return;
    }

    final msgKey = _messageKey(target);
    final anchor = _anchorKeyForMessage(target);
    _highlightClearTimer?.cancel();
    setState(() {
      _highlightedMessageKey = msgKey;
      _stickToBottom = false;
      _scrollPinToken++;
      _fingerDraggingList = false;
    });

    // Wait a frame so keys exist after older messages were inserted.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = anchor.currentContext;
      if (ctx == null || !mounted) return;
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.25,
      );
    });

    _highlightClearTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      if (_highlightedMessageKey == msgKey) {
        setState(() => _highlightedMessageKey = null);
      }
    });
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => unawaited(_jumpToRepliedMessage(reply)),
        borderRadius: BorderRadius.circular(10),
        child: Container(
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
        ),
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
    final myId = _myUserId;
    var idx = _messages.indexWhere(
      (m) =>
          m.id == msg.id ||
          (msg.clientMessageId != null &&
              m.clientMessageId == msg.clientMessageId) ||
          (_isUnsent(m) &&
              msg.clientMessageId != null &&
              m.id == msg.clientMessageId),
    );
    if (idx < 0 && myId != null) {
      idx = _messages.indexWhere((m) => _isSameMessage(m, msg, myId));
    }

    if (idx >= 0) {
      _messages[idx] = _coalesceReceipt(msg, _messages[idx]);
    } else {
      _messages.add(_applyStickyReceipt(msg));
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
    // Merchants: business name for notifications / contact labels (not personal).
    final acting =
        await DisplayNameSync.resolveActingDisplayName(fallback: '');
    if (acting.trim().isNotEmpty) return acting.trim();

    final fromToken = await AuthStorage.userNameFromToken();
    if (fromToken != null && fromToken.trim().isNotEmpty) {
      final t = fromToken.trim();
      return t.contains('@') ? t.split('@').first : t;
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
        senderUserId: _myUserId,
      );
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    if (_recording) return;

    final rawContent = _input.text.trim();
    final content = ChatOffPlatformDetector.maskPhones(rawContent);
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

    final safeCaption = ChatOffPlatformDetector.maskPhones(caption);

    final clientMessageId = const Uuid().v4();
    final replyMeta = _replyMetadataPayload();
    final now = DateTime.now();
    final pending = BackendChatMessage(
      id: clientMessageId,
      chatId: _chatId,
      senderId: myId,
      content: safeCaption,
      type: 'image',
      status: 'pending',
      createdAt: now,
      clientMessageId: clientMessageId,
      metadata: replyMeta,
    );

    // Paint bubble instantly (same as text / voice), then persist + upload.
    setState(() {
      _localImageBytes[clientMessageId] = image.bytes;
      _messages = [..._messages, pending];
      _pendingImage = null;
      _replyingTo = null;
    });
    _input.clear();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToBottom(force: true));

    unawaited(() async {
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
        content: safeCaption,
        status: 'pending',
        createdAt: now,
        localImagePath: localImagePath,
        imageMime: image.mime,
        imageFilename: image.filename,
        metadata: replyMeta,
      );
      try {
        await ChatOutbox.upsert(entry);
      } catch (_) {}
      await _deliverOutboxEntry(entry, notifyPeerOnSuccess: true);
    }());
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

  Future<String> _uploadImageFile({
    required String path,
    required String filename,
    required String mime,
  }) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('Photo is missing on this device');
    }
    try {
      final ref = FirebaseStorage.instance.ref().child(
            'chat_media/${_chatId}/'
            '${DateTime.now().millisecondsSinceEpoch}_$filename',
          );
      await ref.putFile(file, SettableMetadata(contentType: mime));
      return ref.getDownloadURL();
    } catch (_) {
      final bytes = await file.readAsBytes();
      return _uploadImageBytes(
        _PendingImage(bytes: bytes, filename: filename, mime: mime),
      );
    }
  }

  Future<User> _requireFirebaseUserForStorage() async {
    await BackendChatService.ensureAuth();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
        'Not signed in to Firebase. Sign out and sign in again, then retry.',
      );
    }
    // Cached token only â€” force-refresh was doubling VN/image send latency.
    try {
      await user.getIdToken(false);
    } catch (_) {}
    return user;
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

    // Harden to durable outbox media FIRST so network failure never loses the VN.
    String durablePath = filePath;
    try {
      durablePath = await ChatOutbox.persistVoiceFile(
        sourcePath: filePath,
        clientMessageId: clientMessageId,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatOutbox] persist VN failed: $e');
      // Keep recording path if copy failed â€” retry can still use it while alive.
      if (!File(filePath).existsSync()) {
        _toast('Could not save voice note. Please record again.');
        return;
      }
      durablePath = filePath;
    }

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

    setState(() {
      _localVoicePaths[clientMessageId] = durablePath;
      _localVoiceDurations[clientMessageId] = durationMs;
      _messages = [..._messages, pending];
      _replyingTo = null;
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToBottom(force: true));

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
    unawaited(_deliverOutboxEntry(entry, notifyPeerOnSuccess: true));
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
      var entry = e;
      if (entry.isAudio) {
        final recovered = await _recoverVoicePathForEntry(entry);
        if (recovered == null) continue;
        if (recovered != entry.localVoicePath) {
          entry = entry.copyWith(localVoicePath: recovered);
          try {
            await ChatOutbox.upsert(entry);
          } catch (_) {}
          _localVoicePaths[entry.clientMessageId] = recovered;
        }
      }
      if (entry.isImage &&
          _localImageBytes[entry.clientMessageId] == null &&
          (entry.localImagePath == null ||
              entry.localImagePath!.isEmpty ||
              !File(entry.localImagePath!).existsSync())) {
        continue;
      }
      await _deliverOutboxEntry(entry, notifyPeerOnSuccess: true);
    }
  }

  Future<void> _retryUnsent(BackendChatMessage msg) async {
    final myId = _myUserId;
    final id = msg.clientMessageId ?? msg.id;
    if (myId == null || id.isEmpty) return;
    var entry = await ChatOutbox.get(myId, id);
    if (entry == null) return;

    if (entry.isAudio) {
      final recovered = await _recoverVoicePathForEntry(entry);
      if (recovered == null) {
        _toast('Voice note file is gone. Please record a new one.');
        return;
      }
      if (recovered != entry.localVoicePath) {
        entry = entry.copyWith(localVoicePath: recovered, status: 'pending');
        try {
          await ChatOutbox.upsert(entry);
        } catch (_) {}
        if (mounted) {
          setState(() => _localVoicePaths[id] = recovered);
        }
      }
    }

    await _deliverOutboxEntry(
      entry,
      notifyPeerOnSuccess: true,
      userInitiated: true,
    );
  }

  Future<String?> _recoverVoicePathForEntry(ChatOutboxEntry entry) async {
    final id = entry.clientMessageId;
    final candidates = <String>[
      if ((entry.localVoicePath ?? '').trim().isNotEmpty)
        entry.localVoicePath!.trim(),
      if ((_localVoicePaths[id] ?? '').trim().isNotEmpty)
        _localVoicePaths[id]!.trim(),
    ];
    for (final path in candidates) {
      try {
        final f = File(path);
        if (f.existsSync() && f.lengthSync() > 0) return path;
      } catch (_) {}
    }
    final recovered = await ChatOutbox.recoverVoicePath(id);
    if (recovered != null) return recovered;
    return null;
  }

  Future<void> _deliverOutboxEntry(
    ChatOutboxEntry entry, {
    bool notifyPeerOnSuccess = false,
    bool userInitiated = false,
  }) async {
    final id = entry.clientMessageId;
    if (id.isEmpty || _outboxFlushing.contains(id)) return;
    _outboxFlushing.add(id);

    // Don't demote an already-acked bubble back to pending during flush.
    final existingIdx = _messages.indexWhere(
      (m) => m.clientMessageId == id || m.id == id,
    );
    final existingStatus = existingIdx >= 0
        ? _messages[existingIdx].status.toLowerCase()
        : '';
    if (existingStatus != 'sent' &&
        existingStatus != 'delivered' &&
        existingStatus != 'read' &&
        existingStatus != 'seen') {
      _setUnsentStatus(id, 'pending');
      unawaited(
        ChatOutbox.markStatus(
          userId: entry.senderId,
          clientMessageId: id,
          status: 'pending',
        ),
      );
    }

    try {
      BackendChatMessage saved;
      if (entry.isAudio) {
        var path = await _recoverVoicePathForEntry(entry);
        if (path == null || path.isEmpty || !File(path).existsSync()) {
          throw StateError('Voice note file is missing on this device');
        }
        // Keep durable path in outbox for future retries.
        if (path != entry.localVoicePath) {
          try {
            await ChatOutbox.upsert(entry.copyWith(localVoicePath: path));
          } catch (_) {}
          _localVoicePaths[id] = path;
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
        final filename = entry.imageFilename ?? 'photo.jpg';
        final mime = entry.imageMime ?? 'image/jpeg';
        late final String url;
        if (entry.localImagePath != null &&
            File(entry.localImagePath!).existsSync()) {
          url = await _uploadImageFile(
            path: entry.localImagePath!,
            filename: filename,
            mime: mime,
          );
        } else {
          if (bytes == null || bytes.isEmpty) {
            throw StateError('Photo is missing on this device');
          }
          url = await _uploadImageBytes(
            _PendingImage(bytes: bytes, filename: filename, mime: mime),
          );
        }
        saved = await BackendChatService.sendImageMessage(
          chatId: entry.chatId,
          imageUrl: url,
          caption: entry.content ?? '',
          clientMessageId: id,
          mimeType: mime,
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
            ? 'ðŸŽ¤ Voice message'
            : entry.isImage
                ? ((entry.content ?? '').trim().isNotEmpty
                    ? entry.content!.trim()
                    : 'ðŸ“· Photo')
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
    if (!_scroll.hasClients || _fingerDraggingList) return;
    // reverse:true â€” minScrollExtent is the latest message.
    final target = _scroll.position.minScrollExtent;
    if ((_scroll.position.pixels - target).abs() > 0.5) {
      _scroll.jumpTo(target);
    }
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_stickToBottom) return;
    if (!_scroll.hasClients || _fingerDraggingList) return;
    _stickToBottom = true;
    final target = _scroll.position.minScrollExtent;
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  /// Light pin after open/load. Stops immediately when the user starts dragging.
  void _scheduleScrollToLatest({
    int attempts = 3,
    bool forceStick = false,
  }) {
    if (_fingerDraggingList) return;
    if (!forceStick && !_stickToBottom) return;

    final token = ++_scrollPinToken;
    if (forceStick) _stickToBottom = true;

    void attempt(int left) {
      if (!mounted ||
          left <= 0 ||
          token != _scrollPinToken ||
          !_stickToBottom ||
          _fingerDraggingList) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            token != _scrollPinToken ||
            !_stickToBottom ||
            _fingerDraggingList) {
          return;
        }
        if (!_scroll.hasClients) {
          if (left > 1) attempt(left - 1);
          return;
        }
        _jumpToBottom();
        if (left <= 1) return;
        Future<void>.delayed(const Duration(milliseconds: 64), () {
          if (!mounted ||
              token != _scrollPinToken ||
              !_stickToBottom ||
              _fingerDraggingList) {
            return;
          }
          if (_scroll.hasClients &&
              (_scroll.position.pixels - _scroll.position.minScrollExtent)
                      .abs() >
                  2) {
            _jumpToBottom();
          }
          attempt(left - 1);
        });
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
    if (content.startsWith(_audPrefix) ||
        content.startsWith(_imgPrefix) ||
        content.startsWith(_vidPrefix)) {
      return false;
    }
    return m.type == 'text' && content.isNotEmpty;
  }

  String? _messageVideoUrl(BackendChatMessage m) {
    final content = m.content?.trim() ?? '';
    if (content.startsWith(_vidPrefix)) {
      final url = content.split('\n').first.substring(_vidPrefix.length).trim();
      if (url.startsWith('http')) return _preferHttps(url);
    }
    if (m.type == 'video' &&
        (content.startsWith('http://') || content.startsWith('https://'))) {
      return _preferHttps(content);
    }
    return null;
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
        if (!_isSenderProfilePhoto(content, m)) return _preferHttps(content);
      }
    }
    final atts = m.attachments;
    if (atts != null && atts.isNotEmpty) {
      for (final att in atts) {
        final kind = (att['type'] ?? att['kind'] ?? '').toString().toLowerCase();
        if (kind.contains('avatar') || kind.contains('profile')) continue;
        final url = att['url']?.toString().trim();
        if (url != null &&
            url.isNotEmpty &&
            url.startsWith('http') &&
            !_isSenderProfilePhoto(url, m)) {
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
    if (_isStoryReply(m)) {
      final body = _storyReplyBody(m);
      return body == null ? null : ChatOffPlatformDetector.maskPhones(body);
    }
    if (content.startsWith(_vidPrefix) || content.startsWith(_imgPrefix)) {
      final parts = content.split('\n');
      if (parts.length < 2) return null;
      final caption = _stripForwardedMarker(parts.sublist(1).join('\n'));
      if (caption.isEmpty) return null;
      return ChatOffPlatformDetector.maskPhones(caption);
    }
    if (imageUrl != null && content == imageUrl) return null;
    if (m.type == 'image' && content.startsWith('http')) return null;
    final body = _stripForwardedMarker(content);
    if (body.isEmpty) return null;
    return ChatOffPlatformDetector.maskPhones(body);
  }

  _VoiceNoteInfo? _messageAudio(BackendChatMessage m) {
    final content = m.content?.trim() ?? '';
    if (content.startsWith(_audPrefix)) {
      final body = content.substring(_audPrefix.length).trim();
      final firstLine = body.split('\n').first.trim();
      final parts = firstLine.split('|');
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

  Future<void> _loadHiddenMessages() async {
    final myId = _myUserId ?? BackendChatService.peekUserId();
    if (myId == null || _chatId.isEmpty) return;
    final hidden = await HiddenMessageStore.load(myId, _chatId);
    if (!mounted || hidden.isEmpty) return;
    setState(() => _hiddenMessageIds.addAll(hidden));
  }

  List<BackendChatMessage> get _visibleMessages => _messages
      .where((m) => !_hiddenMessageIds.contains(m.id))
      .toList();

  String? _copyableText(BackendChatMessage m) {
    final caption = _visibleCaption(m, _messageImageUrl(m));
    if (caption != null && caption.trim().isNotEmpty) return caption.trim();
    final content = (m.content ?? '').trim();
    if (content.isEmpty) return null;
    if (content.startsWith(_audPrefix) ||
        content.startsWith(_imgPrefix) ||
        content.startsWith(_vidPrefix)) {
      return null;
    }
    if (m.type == 'audio' || m.type == 'image') return null;
    return content;
  }

  Future<void> _showMsgActions(BackendChatMessage m) async {
    if (_isUnsent(m)) {
      await _showUnsentActions(m);
      return;
    }

    HapticFeedback.mediumImpact();
    final myId = _myUserId;
    final isMine = myId != null && m.isMine(myId);
    final canDeleteEveryone = isMine && _within5Min(m);
    final canEdit = isMine && _within5Min(m) && _isEditableText(m);
    final copyText = _copyableText(m);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, anim, secondary) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Emoji reactions (WhatsApp-style top bar)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final emoji in _reactionEmojis)
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                Navigator.pop(ctx);
                                unawaited(_reactToMessage(m, emoji));
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 26),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _msgActionTile(
                            icon: Icons.reply_rounded,
                            label: 'Reply',
                            color: _brandOrange,
                            onTap: () {
                              Navigator.pop(ctx);
                              _startReply(m);
                            },
                          ),
                          if (copyText != null)
                            _msgActionTile(
                              icon: Icons.copy_rounded,
                              label: 'Copy',
                              onTap: () async {
                                Navigator.pop(ctx);
                                await Clipboard.setData(
                                  ClipboardData(text: copyText),
                                );
                                _toast('Message copied');
                              },
                            ),
                          if (copyText != null)
                            _msgActionTile(
                              icon: Icons.text_fields_rounded,
                              label: 'Select text',
                              onTap: () {
                                Navigator.pop(ctx);
                                _showSelectText(copyText);
                              },
                            ),
                          _msgActionTile(
                            icon: Icons.forward_rounded,
                            label: 'Forward',
                            onTap: () {
                              Navigator.pop(ctx);
                              unawaited(_forwardMessage(m));
                            },
                          ),
                          if (canEdit)
                            _msgActionTile(
                              icon: Icons.edit_outlined,
                              label: 'Edit',
                              onTap: () async {
                                Navigator.pop(ctx);
                                await _editMessage(m);
                              },
                            ),
                          _msgActionTile(
                            icon: Icons.delete_outline,
                            label: canDeleteEveryone
                                ? 'Delete for everyone'
                                : 'Delete for me',
                            color: const Color(0xFFEF4444),
                            onTap: () async {
                              Navigator.pop(ctx);
                              if (canDeleteEveryone) {
                                await _deleteMessage(
                                  m,
                                  forEveryone: true,
                                );
                              } else {
                                await _deleteMessage(
                                  m,
                                  forEveryone: false,
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _msgActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color ?? Colors.black87),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: color ?? Colors.black87,
        ),
      ),
      onTap: onTap,
    );
  }

  Future<void> _reactToMessage(BackendChatMessage m, String emoji) async {
    if (m.id.trim().isEmpty || _chatId.isEmpty) return;
    await MessageReactionService.setReaction(
      chatId: _chatId,
      messageId: m.id,
      emoji: emoji,
    );
  }

  void _showSelectText(String text) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select text'),
        content: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 16, height: 1.35),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _forwardMessage(BackendChatMessage m) async {
    final myId = _myUserId;
    if (myId == null) {
      _toast('Sign in to forward messages.');
      return;
    }

    // Prefer cached chat list; refresh quietly if empty.
    var threads = BackendChatService.peekCachedThreads()
        .where((t) => t.id.trim().isNotEmpty && t.id.trim() != _chatId)
        .toList();
    if (threads.isEmpty) {
      try {
        threads = (await BackendChatService.getThreads())
            .where((t) => t.id.trim().isNotEmpty && t.id.trim() != _chatId)
            .toList();
      } catch (_) {}
    }
    if (!mounted) return;
    if (threads.isEmpty) {
      _toast('No other chats to forward to yet.');
      return;
    }

    final myEmail = (FirebaseAuth.instance.currentUser?.email ?? '').trim();
    final myName = await _currentSenderDisplayName();
    if (!mounted) return;

    final targets = await showModalBottomSheet<List<BackendChatThread>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ForwardChatPickerSheet(
        threads: threads,
        myUserId: myId,
        myEmail: myEmail,
        myName: myName,
      ),
    );

    if (targets == null || targets.isEmpty || !mounted) return;

    final imageUrl = _messageImageUrl(m);
    final audio = _messageAudio(m);
    final text = _copyableText(m);
    final meta = <String, dynamic>{
      'forwarded': true,
      'isForwarded': true,
      'forwardedFromChatId': _chatId,
      if (m.id.isNotEmpty) 'forwardedFromMessageId': m.id,
    };

    var okCount = 0;
    var failCount = 0;
    for (final target in targets) {
      try {
        if (audio != null && (audio.url).trim().isNotEmpty) {
          await BackendChatService.sendAudioMessage(
            chatId: target.id,
            audioUrl: audio.url.trim(),
            durationMs: audio.durationMs,
            mimeType: 'audio/mp4',
            metadata: meta,
          );
        } else if (imageUrl != null && imageUrl.trim().isNotEmpty) {
          await BackendChatService.sendImageMessage(
            chatId: target.id,
            imageUrl: imageUrl.trim(),
            caption: (text ?? '').trim(),
            metadata: meta,
          );
        } else {
          final body = (text ?? '').trim().isNotEmpty
              ? text!.trim()
              : 'Forwarded message';
          await BackendChatService.sendMessage(
            chatId: target.id,
            // Content marker survives backends that drop metadata.
            content: 'â†ªï¸ Forwarded\n$body',
            type: 'text',
            metadata: meta,
          );
        }
        okCount++;
      } catch (_) {
        failCount++;
      }
    }

    if (!mounted) return;
    if (okCount > 0) {
      _toast(
        okCount == 1
            ? 'Forwarded to 1 chat'
            : 'Forwarded to $okCount chats',
      );
      BackendChatService.refreshThreads();
    }
    if (failCount > 0) {
      _toast(
        failCount == targets.length
            ? 'Could not forward'
            : 'Forwarded to $okCount, failed $failCount',
      );
    }
  }

  Future<void> _deleteMessage(
    BackendChatMessage m, {
    required bool forEveryone,
  }) async {
    if (forEveryone) {
      final ok = await showModernConfirmDialog(
        context,
        title: 'Delete for everyone?',
        message:
            'This message will be removed for everyone. You can only do this within 5 minutes of sending.',
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
      return;
    }

    final ok = await showModernConfirmDialog(
      context,
      title: 'Delete for me?',
      message: 'This message will be removed from your chat only.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;

    final myId = _myUserId;
    if (myId != null) {
      await HiddenMessageStore.hide(
        userId: myId,
        chatId: _chatId,
        messageId: m.id,
      );
    }
    if (!mounted) return;
    setState(() => _hiddenMessageIds.add(m.id));
  }

  Future<void> _editMessage(BackendChatMessage m) async {
    final updated = await showModernEditDialog(
      context,
      title: 'Edit message',
      initialText: m.content ?? '',
    );
    if (updated == null || updated.isEmpty || updated == m.content) return;

    final safe = ChatOffPlatformDetector.maskPhones(updated);
    try {
      final saved = await BackendChatService.editMessage(
        chatId: _chatId,
        messageId: m.id,
        newContent: safe,
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
    final screen = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final memW = (screen.width * dpr).round().clamp(480, 1600);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close photo',
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, _, __) {
        return Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: ResilientCachedNetworkImage(
                      url: warmUrl,
                      fit: BoxFit.contain,
                      width: screen.width - 24,
                      showSpinner: true,
                      memCacheWidth: memW,
                      placeholderColor: Colors.black,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.pop(ctx),
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
      },
    );
  }

  void _viewLocalImage(Uint8List bytes) {
    final screen = MediaQuery.sizeOf(context);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close photo',
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, _, __) {
        return Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      width: screen.width - 24,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.pop(ctx),
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
      },
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
        imageQuality: 70,
        maxWidth: 1080,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final image = _PendingImage(
        bytes: bytes,
        filename: file.name.isEmpty ? 'image.jpg' : file.name,
        mime: lookupMimeType(file.name, headerBytes: bytes) ?? 'image/jpeg',
      );
      unawaited(_sendImageMessage(image, caption: _input.text.trim()));
    } catch (_) {
      _toast('Could not pick image');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1080,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final image = _PendingImage(
        bytes: bytes,
        filename: file.name.isEmpty ? 'camera.jpg' : file.name,
        mime: lookupMimeType(file.name, headerBytes: bytes) ?? 'image/jpeg',
      );
      unawaited(_sendImageMessage(image, caption: _input.text.trim()));
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
    final myUid = me.uid.trim();

    // Never hint with our own shop/merchant uid â€” that caused "can't call yourself".
    final rawHint = (_resolvedMerchantId() ?? '').trim();
    final hint = (rawHint.isNotEmpty && rawHint != myUid) ? rawHint : null;

    final peerUid = (await BackendChatService.resolvePeerFirebaseUid(
          chatId: _chatId,
          peerUserId: widget.peerUserId ?? _peerUserId,
          hintFirebaseUid: hint,
        ))
            ?.trim() ??
        '';
    if (peerUid.isEmpty) {
      _toast('Calling isnâ€™t available for this chat yet.');
      return;
    }
    if (peerUid == myUid) {
      _toast('Calling isnâ€™t available for this chat yet.');
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
      unawaited(UserPresenceService.goOnline());
      final actingName = await _currentSenderDisplayName();
      final call = await CallServiceImpl().initiateCall(
        initiatorId: myUid,
        recipientId: peerUid,
        callType: video ? CallType.video : CallType.voice,
        initiatorName: actingName.isNotEmpty
            ? actingName
            : (me.displayName ?? me.email ?? 'Vero360 user'),
        initiatorAvatar: me.photoURL,
        recipientName: widget.peerName,
        recipientAvatar: _shownPeerAvatar,
      );

      // Best-effort push so the peer rings even if the app is backgrounded.
      unawaited(
        ChatNotificationService.notifyRecipientOfMessage(
          chatId: _chatId,
          senderName: actingName.isNotEmpty ? actingName : (me.displayName ?? 'Vero360'),
          body: video ? 'ðŸ“¹ Incoming video call' : 'ðŸ“ž Incoming voice call',
          recipientFirebaseUid: peerUid,
          recipientUserId: widget.peerUserId ?? _peerUserId,
          senderUserId: _myUserId,
        ),
      );

      // Leave a WhatsApp-style call marker in the thread (best effort).
      if (_myUserId != null && _chatId.isNotEmpty) {
        unawaited(
          BackendChatService.sendMessage(
            chatId: _chatId,
            content: video ? 'ðŸ“¹ Video call' : 'ðŸ“ž Voice call',
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
          builder: (_) => ChatCallScreen(
            call: call,
            peerName: widget.peerName,
            peerAvatarUrl: _shownPeerAvatar,
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
    final sticky = _stickyPeerReadUpTo;
    if (sticky != null &&
        !m.createdAt.isAfter(sticky.add(const Duration(seconds: 8)))) {
      return true;
    }
    return false;
  }

  bool _isMessageDelivered(BackendChatMessage m) {
    if (_isMessageRead(m)) return true;
    final status = m.status.trim().toLowerCase();
    if (status == 'delivered' || m.deliveredAt != null) return true;
    final receipt = _peerReceipt;
    if (receipt != null && receipt.coversDelivered(m.createdAt)) return true;
    final sticky = _stickyPeerDeliveredUpTo;
    if (sticky != null &&
        !m.createdAt.isAfter(sticky.add(const Duration(seconds: 8)))) {
      return true;
    }
    return false;
  }

  Widget _buildMessageReceipt(BackendChatMessage msg, bool isLastOutgoing) {
    final read = _isMessageRead(msg);
    final delivered = _isMessageDelivered(msg);
    // âœ“ sent Â· âœ“âœ“ delivered (grey) Â· âœ“âœ“ seen (blue)
    final tickColor =
        read ? const Color(0xFF53BDEB) : const Color(0xFF9CA3AF);

    return Icon(
      (delivered || read) ? Icons.done_all_rounded : Icons.check_rounded,
      size: 16,
      color: tickColor,
    );
  }

  Future<void> _bindPeerPresence() async {
    final chatId = _chatId.trim();
    if (chatId.isEmpty) return;
    final myUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final rawHint = (_resolvedMerchantId() ?? '').trim();
    final hint = (rawHint.isNotEmpty && rawHint != myUid) ? rawHint : null;
    final uid = (await BackendChatService.resolvePeerFirebaseUid(
          chatId: chatId,
          peerUserId: widget.peerUserId ?? _peerUserId,
          hintFirebaseUid: hint,
        ))
            ?.trim() ??
        '';
    if (!mounted || uid.isEmpty || uid == _watchedPeerUid) return;
    await _peerPresenceSub?.cancel();
    _watchedPeerUid = uid;
    _peerPresenceSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data() ?? const <String, dynamic>{};
      final typingChat = (data['typingChatId'] ?? '').toString().trim();
      final typingAt = _readTime(data['typingAt']);
      final typingFresh = typingAt != null &&
          _ageOk(typingAt, const Duration(seconds: 5));
      final typingHere =
          (typingChat.isNotEmpty && typingChat == _chatId.trim()) ||
              typingFresh;
      _peerPresenceKnown = true;
      _peerPresenceFlagged = data['isOnline'] == true ||
          data['online'] == true ||
          data['presence'] == 'online';
      _peerLastSeen = _presenceSeenAt(data);
      _peerTypingUntil = typingHere
          ? DateTime.now().add(const Duration(seconds: 4))
          : null;
      _recomputePresence(force: true);
    }, onError: (_) {});
  }

  void _recomputePresence({bool force = false}) {
    if (!mounted) return;
    if (!_peerPresenceKnown && !_roomKnown) return;
    final seen = _peerLastSeen;
    // Heartbeat is 12s. A stuck isOnline flag must not keep "Online" up.
    final online = _peerPresenceFlagged &&
        seen != null &&
        _ageOk(seen, const Duration(seconds: 25));
    final typing = _peerTypingUntil != null &&
        DateTime.now().isBefore(_peerTypingUntil!);
    final roomOnline = _roomFlagged &&
        _roomSeen != null &&
        _ageOk(_roomSeen!, const Duration(seconds: 20));
    final roomTyping = _roomTypingFlag &&
        _roomTypingAt != null &&
        _ageOk(_roomTypingAt!, const Duration(seconds: 4));
    if (!force &&
        online == _peerOnline &&
        typing == _peerTyping &&
        roomOnline == _roomOnline &&
        roomTyping == _roomTyping) {
      return;
    }
    setState(() {
      _peerOnline = online;
      _peerTyping = typing;
      _roomOnline = roomOnline;
      _roomTyping = roomTyping;
    });
  }

  /// Clock skew can put [seen] slightly in the future. Clamp that so it
  /// starts aging immediately instead of looking online for minutes.
  bool _ageOk(DateTime seen, Duration window) {
    final now = DateTime.now();
    final at = seen.isAfter(now) ? now : seen;
    return now.difference(at) <= window;
  }

  bool get _headerOnline => _roomKnown ? _roomOnline : _peerOnline;
  bool get _headerTyping => _roomKnown ? _roomTyping : _peerTyping;

  Future<void> _syncPresenceRoom() async {
    final id = _chatId.trim();
    if (id.isEmpty) return;
    if (_presenceRoomId != id) {
      final prev = _presenceRoomId;
      _presenceRoomId = id;
      await _memberSub?.cancel();
      _memberSub = null;
      if (prev != null && prev.isNotEmpty) {
        await UserPresenceService.leaveChat(prev);
      }
      _memberSub = FirebaseFirestore.instance
          .collection('chat_presence')
          .doc(id)
          .collection('members')
          .snapshots()
          .listen(_onChatMembers, onError: (_) {});
    }
    await UserPresenceService.enterChat(id);
  }

  void _onChatMembers(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    final myUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    var sawOther = false;
    var flagged = false;
    var typingFlag = false;
    DateTime? seen;
    DateTime? typingAt;
    for (final doc in snap.docs) {
      if (myUid.isNotEmpty && doc.id == myUid) continue;
      sawOther = true;
      final data = doc.data();
      final seenAt = _readTime(data['seenAt']);
      final typedAt = _readTime(data['typingAt']);
      if (seenAt != null && (seen == null || seenAt.isAfter(seen))) {
        seen = seenAt;
      }
      if (data['online'] == true) flagged = true;
      if (data['typing'] == true) {
        typingFlag = true;
        if (typedAt != null &&
            (typingAt == null || typedAt.isAfter(typingAt))) {
          typingAt = typedAt;
        }
      }
    }
    _roomKnown = sawOther;
    _roomFlagged = flagged;
    _roomTypingFlag = typingFlag;
    _roomSeen = seen;
    _roomTypingAt = typingAt;
    _recomputePresence(force: true);
  }

  DateTime? _presenceSeenAt(Map<String, dynamic> data) {
    return _readTime(data['lastSeen']) ?? _readTime(data['lastActiveAt']);
  }

  DateTime? _readTime(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        raw > 20000000000 ? raw : raw * 1000,
      );
    }
    return null;
  }

  String _chatStatusLabel() {
    if (_headerTyping) return 'typingâ€¦';
    if (_roomKnown) {
      if (_roomOnline) return 'Online';
      final seen = _roomSeen;
      if (seen == null) return 'Offline';
      return _lastSeenLabel(seen);
    }
    if (!_peerPresenceKnown) return '';
    if (_peerOnline) return 'Online';
    final seen = _peerLastSeen;
    if (seen == null) return 'Offline';
    return _lastSeenLabel(seen);
  }

  String _lastSeenLabel(DateTime seen) {
    final at = seen.isAfter(DateTime.now()) ? DateTime.now() : seen;
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 60) return 'last seen just now';
    if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'last seen ${diff.inHours}h ago';
    return 'Offline';
  }

  PreferredSizeWidget _buildModernAppBar({
    required String title,
    required ChatProductContext? activeProduct,
  }) {
    const ink = Color(0xFF101010);
    final status = _chatStatusLabel();
    final subtitle = status.isNotEmpty
        ? status
        : (activeProduct != null
            ? 'View shop Â· ${activeProduct.name}'
            : '');

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
                _avatar(_shownPeerAvatar, size: 42),
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
                          if (activeProduct == null || _headerTyping) ...[
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: (_headerOnline || _headerTyping)
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF9CA3AF),
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
                                fontStyle: _headerTyping
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                color: _headerTyping
                                    ? const Color(0xFF16A34A)
                                    : (activeProduct != null
                                        ? _brandOrange
                                        : const Color(0xFF6B7280)),
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
                  Text(_exportingChat ? 'Downloadingâ€¦' : 'Download chat'),
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

  /// Facebook-style: only prompt after a real conversation (â‰¥10 messages).
  /// Only buyers rate merchants â€” never the reverse.
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
    // Need a real back-and-forth, and at least 10 messages in the thread.
    return _messages.length >= 10 && mine >= 1 && theirs >= 1;
  }

  Future<void> _promptRateSeller({required bool force}) async {
    if (_iAmTheMerchantForRating()) {
      _toast('You canâ€™t rate your own shop.');
      return;
    }
    if (!_eligibleForChatRating()) {
      if (force) {
        _toast('Keep chatting â€” ratings unlock after 10 messages.');
      }
      return;
    }

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

  /// Leave chat immediately. Review (if any) is shown on the shell underneath â€”
  /// never await network/Firestore before popping (that was locking the chat).
  Future<void> _maybePromptChatRatingThenPop() async {
    // Second back while a leave is in flight â†’ force pop.
    if (_leaving) {
      if (mounted) {
        final nav = Navigator.of(context);
        if (nav.canPop()) nav.pop();
      }
      return;
    }
    _leaving = true;

    final shouldPrompt = _eligibleForChatRating();
    final merchantName = widget.peerName;
    final contextKey = _chatRatingContextKey();
    final merchantRef = _merchantRefForRating();
    final backendId = _merchantBackendIdForRating();
    final serviceProviderId = widget.resolveServiceProviderId;
    final sellerUserId = widget.resolveSellerUserId ?? merchantRef;

    if (!mounted) return;
    Navigator.of(context).pop();

    if (!shouldPrompt) return;
    if (merchantRef.isEmpty && (backendId == null || backendId <= 0)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(() async {
        final ctx = appNavKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        try {
          await MerchantReviewPrompt.maybeShow(
            ctx,
            merchantName: merchantName,
            reason: MerchantReviewReason.afterChat,
            contextKey: contextKey,
            merchantRef: merchantRef.isEmpty ? null : merchantRef,
            serviceProviderId: serviceProviderId,
            sellerUserId: sellerUserId.isEmpty ? null : sellerUserId,
            merchantBackendId: backendId,
            force: false,
          ).timeout(const Duration(seconds: 8), onTimeout: () => false);
        } catch (_) {}
      }());
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep seller chrome visible while chat/messages resolve (feels much faster).
    if (_messages.isEmpty &&
        _loadError == null &&
        !_bootComplete &&
        _isPlaceholderPeerName(_peerDisplayName)) {
      return const ChatBootLoadingScaffold();
    }

    final activeProduct = _activeProduct;
    final title = _peerDisplayName;
    final hasText = _input.text.trim().isNotEmpty;
    final hasPendingImage = _pendingImage != null;
    final canSend = (hasText || hasPendingImage) &&
        _chatId.isNotEmpty &&
        !_resolvingChat &&
        !_recording;

    return PopScope(
      // Only intercept back when a post-chat rating might be due. Otherwise
      // allow the normal pop so chat never feels locked.
      canPop: !_eligibleForChatRating(),
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
                        'Say hi ðŸ‘‹',
                        style: TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            // Finger-down: kill auto-pin immediately so the first
                            // swipe isn't fighting jumpTo / image layout.
                            if (notification is ScrollStartNotification &&
                                notification.dragDetails != null) {
                              _fingerDraggingList = true;
                              _scrollPinToken++;
                            }
                            if (notification is ScrollUpdateNotification &&
                                notification.dragDetails != null &&
                                _scroll.hasClients &&
                                _scroll.position.pixels > 8) {
                              _stickToBottom = false;
                            }
                            if (notification is ScrollEndNotification) {
                              _fingerDraggingList = false;
                              if (_scroll.hasClients) {
                                _stickToBottom =
                                    _scroll.position.pixels <= _nearBottomPx;
                              }
                            }
                            return false;
                          },
                          child: SlidableAutoCloseBehavior(
                            child: ListView.builder(
                              controller: _scroll,
                              reverse: true,
                              cacheExtent: 900,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              physics: const ClampingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                              itemCount: _visibleMessages.length,
                              itemBuilder: (context, i) {
                                // reverse:true shows index 0 at the bottom â†’ newest first.
                                final visible = _visibleMessages;
                                final index = visible.length - 1 - i;
                                return _buildMessageTile(visible[index], index);
                              },
                            ),
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
    final videoUrl = _messageVideoUrl(msg);
    final imageUrl =
        videoUrl == null && localBytes == null ? _messageImageUrl(msg) : null;
    final caption = _visibleCaption(msg, imageUrl);
    final audio = _messageAudio(msg);
    final localVoicePath = _localVoicePathFor(msg);
    final voiceDuration = _voiceDurationFor(msg, audio);
    final isLastOutgoing = isMine && index == _lastOutgoingMessageIndex();
    final scanText = [
      caption,
      msg.content,
    ].whereType<String>().join('\n');
    final showOffPlatformWarning =
        ChatOffPlatformDetector.containsSensitiveDetails(scanText);
    final msgKey = _messageKey(msg);
    final isHighlighted = _highlightedMessageKey == msgKey;

    final bubble = Padding(
      key: _anchorKeyForMessage(msg),
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine)
            _avatar(_shownPeerAvatar, size: 28)
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
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
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
                      border: isHighlighted
                          ? Border.all(
                              color: isMine
                                  ? Colors.white
                                  : _brandOrange,
                              width: 2.2,
                            )
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: isHighlighted
                              ? _brandOrange.withValues(alpha: 0.35)
                              : Colors.black.withValues(alpha: 0.06),
                          blurRadius: isHighlighted ? 14 : 6,
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
                        if (_isForwarded(msg))
                          _buildForwardedLabel(isMine: isMine),
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
                            child: GestureDetector(
                              onTap: () => _viewLocalImage(localBytes),
                              child: Image.memory(
                                localBytes,
                                width: 220,
                                height: 180,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.low,
                                cacheWidth: 440,
                              ),
                            ),
                          ),
                          if (caption != null) const SizedBox(height: 8),
                        ] else if (videoUrl != null) ...[
                          _ChatVideoTile(url: videoUrl),
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
                                showSpinner: false,
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
                          LinkifiedText(
                            caption,
                            style: TextStyle(
                              color: isMine ? Colors.white : Colors.black87,
                              fontSize: 15,
                              height: 1.35,
                            ),
                            linkColor: isMine
                                ? Colors.white
                                : const Color(0xFF2563EB),
                          ),
                        if (caption == null &&
                            localBytes == null &&
                            imageUrl == null &&
                            videoUrl == null &&
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
                if (!isUnsent && msg.id.isNotEmpty)
                  _buildReactionRow(msg, isMine: isMine),
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
          onLongPress: () => unawaited(_showMsgActions(msg)),
          child: Slidable(
            key: ValueKey('msg_${msg.clientMessageId ?? msg.id}'),
            groupTag: 'chat_messages',
            closeOnScroll: true,
            startActionPane: isUnsent
                ? null
                : ActionPane(
                    motion: const BehindMotion(),
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
    final rawId = product.productId.trim();
    final sqlId = int.tryParse(rawId);
    return core.MarketplaceDetailModel(
      id: _checkoutItemIdFromProduct(product),
      firestoreDocId: (sqlId == null || sqlId <= 0) && rawId.isNotEmpty
          ? rawId
          : null,
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

  void _openProductDetails(ChatProductContext product) {
    if (!mounted) return;
    // Open instantly with chat tag data â€” no network wait before navigation.
    final item = _checkoutItemFromProduct(product);
    final cart = CartService('', apiPrefix: ApiConfig.apiPrefix);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsPage(item: item, cartService: cart),
      ),
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
                onTap: () => _openProductDetails(product),
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
                              _formatPrice(
                                isMerchant
                                    ? product.price!
                                    : BuyerCommission.buyerFacing(
                                        product.price!,
                                      ),
                              ),
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
    final product = ChatProductContext.fromTagMap(tag);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openProductDetails(product),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                isMine ? Colors.white.withOpacity(0.15) : Colors.grey.shade100,
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
        ),
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
            if (_headerTyping) _buildPeerTypingBar(),
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
                              ? 'Add a captionâ€¦'
                              : 'Type a messageâ€¦',
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

  Widget _buildPeerTypingBar() {
    final name = _peerDisplayName.trim().isEmpty ? 'They' : _peerDisplayName.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$name is typingâ€¦',
          style: const TextStyle(
            color: Color(0xFF16A34A),
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
            fontSize: 13,
          ),
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
class ChatCallScreen extends StatefulWidget {
  const ChatCallScreen({
    super.key,
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
  State<ChatCallScreen> createState() => _ChatCallScreenState();
}

enum _CallPhase { calling, ringing, connected }

class _ChatCallScreenState extends State<ChatCallScreen> {
  static const _orange = Color(0xFFFF8A00);
  final _calls = CallServiceImpl();
  late final LiveCallSession _media;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  Timer? _presenceTimer;
  Timer? _durationTimer;
  Timer? _ringingKick;
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
    _media = LiveCallSession(
      callId: widget.call.id,
      isCaller: true,
      video: widget.video,
    );
    _media.addListener(_onMedia);
    unawaited(_media.start());
    unawaited(UserPresenceService.goOnline());
    unawaited(_refreshPeerPresence(initial: true));
    // Always progress to Ringing so presence alone cannot block dial UX.
    _ringingKick = Timer(const Duration(seconds: 1), () {
      if (!mounted || _phase == _CallPhase.connected) return;
      setState(() => _phase = _CallPhase.ringing);
    });
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
      if (_phase == _CallPhase.calling && online) {
        _phase = _CallPhase.ringing;
      }
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
          DateTime.now().difference(at) <= const Duration(minutes: 10)) {
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
    _ringingKick?.cancel();
    _ringingKick = null;
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

  void _onMedia() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _media.removeListener(_onMedia);
    unawaited(_media.hangup());
    _callSub?.cancel();
    _presenceTimer?.cancel();
    _durationTimer?.cancel();
    _ringingKick?.cancel();
    super.dispose();
  }

  String get _statusLabel {
    switch (_phase) {
      case _CallPhase.calling:
        return 'Callingâ€¦';
      case _CallPhase.ringing:
        return 'Ringingâ€¦';
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
    _ringingKick?.cancel();
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
              _media.mediaLive
                  ? 'Live'
                  : (_phase == _CallPhase.connected
                      ? 'Connecting audioâ€¦'
                      : (_peerOnline ? 'Online' : 'Ringing their deviceâ€¦')),
              style: TextStyle(
                color: _media.mediaLive ||
                        _phase == _CallPhase.connected ||
                        _peerOnline
                    ? const Color(0xFF22C55E)
                    : Colors.white54,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if ((_media.error ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _media.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFF87171),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
            if (widget.video) ...[
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: LiveCallVideoPane(session: _media),
                ),
              ),
            ] else ...[
              LiveCallAudioSink(session: _media),
              const Spacer(),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _roundBtn(
                    icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    label: _micOn ? 'Mute' : 'Unmute',
                    onTap: () {
                      final next = !_micOn;
                      setState(() => _micOn = next);
                      unawaited(_media.setMicEnabled(next));
                    },
                  ),
                  _roundBtn(
                    icon: _media.speakerOn
                        ? Icons.volume_up_rounded
                        : Icons.hearing_rounded,
                    label: _media.speakerOn ? 'Speaker' : 'Earpiece',
                    onTap: () => unawaited(_media.setSpeaker(!_media.speakerOn)),
                  ),
                  if (widget.video)
                    _roundBtn(
                      icon: _camOn
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      label: _camOn ? 'Camera' : 'Cam off',
                      onTap: () {
                        final next = !_camOn;
                        setState(() => _camOn = next);
                        unawaited(_media.setCameraEnabled(next));
                      },
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

/// Forward target picker: multi-select chats + search by peer name.
class _ForwardChatPickerSheet extends StatefulWidget {
  final List<BackendChatThread> threads;
  final int myUserId;
  final String myEmail;
  final String myName;

  const _ForwardChatPickerSheet({
    required this.threads,
    required this.myUserId,
    required this.myEmail,
    required this.myName,
  });

  @override
  State<_ForwardChatPickerSheet> createState() => _ForwardChatPickerSheetState();
}

class _ForwardChatPickerSheetState extends State<_ForwardChatPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selectedIds = <String>{};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<BackendChatThread> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.threads;
    return widget.threads.where((t) {
      final title = BackendChatService.peerDisplayNameForThread(
        t,
        widget.myUserId,
        myEmail: widget.myEmail,
        myName: widget.myName,
      ).toLowerCase();
      final preview = BackendChatService.describeLastMessagePreview(
        t.lastMessagePreview,
      ).label.toLowerCase();
      return title.contains(q) || preview.contains(q);
    }).toList();
  }

  void _toggle(BackendChatThread t) {
    final id = t.id.trim();
    if (id.isEmpty) return;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _confirm() {
    if (_selectedIds.isEmpty) return;
    final chosen = widget.threads
        .where((t) => _selectedIds.contains(t.id.trim()))
        .toList(growable: false);
    Navigator.pop(context, chosen);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final selectedCount = _selectedIds.length;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Forward to chats',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  if (selectedCount > 0)
                    Text(
                      '$selectedCount selected',
                      style: const TextStyle(
                        color: Color(0xFFFF8A00),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Tap to select one or more chats',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search name',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: const Color(0xFFF3F4F7),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text(
                        'No chats match that name',
                        style: TextStyle(color: Color(0xFF6B7280)),
                      ),
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) {
                        final t = rows[i];
                        final id = t.id.trim();
                        final selected = _selectedIds.contains(id);
                        final title =
                            BackendChatService.peerDisplayNameForThread(
                          t,
                          widget.myUserId,
                          myEmail: widget.myEmail,
                          myName: widget.myName,
                        );
                        final avatar =
                            BackendChatService.peerAvatarUrlForThread(
                          t,
                          widget.myUserId,
                          myEmail: widget.myEmail,
                          myName: widget.myName,
                        );
                        final preview =
                            BackendChatService.describeLastMessagePreview(
                          t.lastMessagePreview,
                        ).label;
                        return ListTile(
                          selected: selected,
                          selectedTileColor:
                              const Color(0xFFFF8A00).withValues(alpha: 0.08),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFFFE8CC),
                            backgroundImage: avatar.startsWith('http')
                                ? NetworkImage(avatar)
                                : null,
                            child: avatar.startsWith('http')
                                ? null
                                : Text(
                                    title.isNotEmpty
                                        ? title[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFFF8A00),
                                    ),
                                  ),
                          ),
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            preview.trim().isEmpty
                                ? 'Tap to select'
                                : preview.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Checkbox(
                            value: selected,
                            activeColor: const Color(0xFFFF8A00),
                            onChanged: (_) => _toggle(t),
                          ),
                          onTap: () => _toggle(t),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: selectedCount == 0 ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A00),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE5E7EB),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    selectedCount == 0
                        ? 'Select chats'
                        : selectedCount == 1
                            ? 'Forward to 1 chat'
                            : 'Forward to $selectedCount chats',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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

class _ChatVideoTile extends StatelessWidget {
  final String url;

  const _ChatVideoTile({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showDialog<void>(
          context: context,
          barrierColor: Colors.black87,
          builder: (_) => _ChatVideoDialog(url: url),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 220,
          height: 140,
          color: Colors.black,
          alignment: Alignment.center,
          child: const Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.white,
            size: 48,
          ),
        ),
      ),
    );
  }
}

class _ChatVideoDialog extends StatefulWidget {
  final String url;

  const _ChatVideoDialog({required this.url});

  @override
  State<_ChatVideoDialog> createState() => _ChatVideoDialogState();
}

class _ChatVideoDialogState extends State<_ChatVideoDialog> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        _controller.play();
        setState(() => _ready = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _ready
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio == 0
                          ? 9 / 16
                          : _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
