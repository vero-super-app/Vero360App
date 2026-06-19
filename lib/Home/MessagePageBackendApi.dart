import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/GeneralModels/chat_product_context.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';
import 'package:vero360_app/widgets/messaging_skeleton_loaders.dart';

class MessagePageBackendApi extends StatefulWidget {
  final String peerId; // Chat ID from backend
  final String peerName;
  final String? peerAvatarUrl;
  final ChatProductContext? productContext;

  /// When true, sends the marketplace enquiry once (product page only).
  final bool sendProductEnquiry;

  const MessagePageBackendApi({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerAvatarUrl,
    this.productContext,
    this.sendProductEnquiry = false,
  });

  @override
  State<MessagePageBackendApi> createState() => _MessagePageBackendApiState();
}

class _MessagePageBackendApiState extends State<MessagePageBackendApi> {
  String? _me;
  int? _myUserId;

  final _input = TextEditingController();
  final _scroll = ScrollController();

  bool _sending = false;
  bool _loading = true;
  bool _bootComplete = false;
  bool _wsConnected = false;
  bool _productTagAttached = false;
  String? _loadError;
  List<BackendChatMessage> _messages = [];
  Timer? _fallbackPollTimer;
  StreamSubscription<BackendChatMessage>? _wsMessageSub;
  StreamSubscription<bool>? _wsConnectionSub;

  static const _brandOrange = Color(0xFFFF8A00);
  static const _bg = Color(0xFFF3F4F7);
  static const _fallbackPollInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _boot();

    _input.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    _startRealtime();
  }

  void _startRealtime() {
    _wsMessageSub = BackendMessagingSocket.messageStream.listen((msg) {
      if (!mounted || msg.chatId != widget.peerId) return;
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
  }

  void _startFallbackPoll() {
    _fallbackPollTimer?.cancel();
    if (BackendMessagingSocket.isConnected) return;
    _fallbackPollTimer = Timer.periodic(_fallbackPollInterval, (_) {
      if (mounted && !_sending && !BackendMessagingSocket.isConnected) {
        _loadMessages(silent: true);
      }
    });
  }

  @override
  void dispose() {
    BackendChatService.setActiveChatId(null);
    _fallbackPollTimer?.cancel();
    _wsMessageSub?.cancel();
    _wsConnectionSub?.cancel();
    unawaited(BackendMessagingSocket.leaveChat(widget.peerId));
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      BackendChatService.setActiveChatId(widget.peerId);

      await BackendChatService.ensureAuth();
      final userId = await BackendChatService.getUserId();

      final cached = BackendChatService.peekCachedMessages(widget.peerId);
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _messages = cached;
          _loading = false;
          _myUserId = userId;
          _me = userId.toString();
          if (_hasProductTagInMessages(_messages)) {
            _productTagAttached = true;
          }
        });
      }

      try {
        await BackendMessagingSocket.connect();
        await BackendMessagingSocket.joinChat(widget.peerId);
        if (mounted) setState(() => _wsConnected = BackendMessagingSocket.isConnected);
      } catch (_) {
        if (mounted) setState(() => _wsConnected = false);
      }

      await _loadMessages(silent: cached.isNotEmpty);
      await _maybeSendProductEnquiry(userId);
      await _markUnreadAsRead(userId);

      if (!mounted) return;
      setState(() {
        _myUserId = userId;
        _me = userId.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _friendlyError(e);
      });
      _toast(_loadError!);
    } finally {
      if (mounted) {
        setState(() => _bootComplete = true);
      }
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
      'mp-enquiry-${widget.peerId}-$productId';

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
        chatId: widget.peerId,
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
      final messages = await BackendChatService.getMessages(widget.peerId);
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
        chatId: widget.peerId,
        messageIds: unreadIds,
      );
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

  Future<void> _sendMessage() async {
    if (_sending) return;

    final content = _input.text.trim();
    if (content.isEmpty) return;

    final myId = _myUserId;
    if (myId == null) return;

    final product = widget.productContext;
    final attachProductTag =
        product != null && !_productTagAttached;
    final tags = attachProductTag ? [product.toMessageTag()] : null;

    final clientMessageId = const Uuid().v4();
    final pending = BackendChatMessage(
      id: clientMessageId,
      chatId: widget.peerId,
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
        chatId: widget.peerId,
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

  @override
  Widget build(BuildContext context) {
    if (!_bootComplete) {
      return const ChatBootLoadingScaffold();
    }

    final activeProduct = _activeProduct;
    final title = widget.peerName;
    final hasText = _input.text.trim().isNotEmpty;
    final canSend = hasText && !_sending;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 6),
            _avatar(widget.peerAvatarUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (activeProduct == null) ...[
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: _wsConnected
                              ? const Color(0xFF39C16C)
                              : Colors.orange,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          activeProduct != null
                              ? activeProduct.name
                              : (_wsConnected ? 'Connected' : 'Reconnecting…'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: activeProduct != null
                                ? _brandOrange
                                : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _me == null ? null : () {},
              icon: const Icon(Icons.call_outlined),
            ),
            IconButton(
              onPressed: _me == null ? null : () {},
              icon: const Icon(Icons.videocam_outlined),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessagesPane(activeProduct)),
          if (activeProduct != null) _buildDiscussedProductBar(activeProduct),
          _buildInputArea(canSend),
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
                  _loadMessages();
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
    final isMine = msg.isMine(_myUserId!);
    final isPending = msg.status == 'pending';
    final showDateSeparator = _isDifferentDay(msg, prevMsg);

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
        Padding(
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
                            if ((msg.content ?? '').isNotEmpty)
                              Text(
                                msg.content!,
                                style: TextStyle(
                                  color: isMine ? Colors.white : Colors.black87,
                                  fontSize: 15,
                                  height: 1.35,
                                ),
                              ),
                            if ((msg.content ?? '').isEmpty &&
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
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
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

  Widget _buildDiscussedProductBar(ChatProductContext product) {
    final isMerchant = _isMerchantViewingEnquiry;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
          _productThumb(product.image, size: 54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMerchant ? 'Customer is viewing' : 'You are enquiring about',
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
          Icon(Icons.shopping_bag_outlined, color: _brandOrange.withOpacity(0.85)),
        ],
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

  Widget _buildInputArea(bool canSend) {
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
                      hintText: 'Type a message…',
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
              AnimatedScale(
                scale: canSend || _sending ? 1 : 0.92,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: canSend || _sending
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFF9A2E),
                              Color(0xFFFF8A00),
                            ],
                          )
                        : null,
                    color: canSend || _sending ? null : const Color(0xFFE4E6EB),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: canSend || _sending
                        ? [
                            BoxShadow(
                              color: _brandOrange.withValues(alpha: 0.35),
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
                          child: _sending
                              ? const SizedBox(
                                  key: ValueKey('sending'),
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Icon(
                                  key: const ValueKey('send'),
                                  Icons.arrow_upward_rounded,
                                  color: canSend ? Colors.white : Colors.grey.shade500,
                                  size: 22,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
