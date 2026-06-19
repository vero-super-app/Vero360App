import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/GeneralModels/chat_product_context.dart';

class MessagePageBackendApi extends StatefulWidget {
  final String peerId; // Chat ID from backend
  final String peerName;
  final String? peerAvatarUrl;
  final ChatProductContext? productContext;

  const MessagePageBackendApi({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerAvatarUrl,
    this.productContext,
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

      try {
        await BackendMessagingSocket.connect();
        await BackendMessagingSocket.joinChat(widget.peerId);
        if (mounted) setState(() => _wsConnected = BackendMessagingSocket.isConnected);
      } catch (_) {
        if (mounted) setState(() => _wsConnected = false);
      }

      await _loadMessages(silent: true);
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

  Future<void> _maybeSendProductEnquiry(int myUserId) async {
    final product = widget.productContext;
    if (product == null) return;
    if (_hasProductTagInMessages(_messages)) {
      _productTagAttached = true;
      return;
    }

    const enquiryText = "Hi, I'm interested in this item.";
    try {
      final saved = await BackendChatService.sendMessage(
        chatId: widget.peerId,
        content: enquiryText,
        type: 'text',
        tags: [product.toMessageTag()],
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

  bool _hasProductTagInMessages(List<BackendChatMessage> messages) {
    final productId = widget.productContext?.productId;
    if (productId == null) return false;
    for (final msg in messages) {
      final tags = msg.tags ?? const [];
      for (final tag in tags) {
        if (tag['tagType'] == 'product' && '${tag['tagId']}' == productId) {
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

    _sending = true;
    _input.clear();
    setState(() {
      _messages = [..._messages, pending];
    });

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
    final activeProduct = _activeProduct;
    final title = widget.peerName;
    final canSend = !_sending && _input.text.trim().isNotEmpty;

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
                  Text(
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
                ],
              ),
            ),
            IconButton(
              onPressed: _me == null ? null : () {},
              icon: const Icon(Icons.call),
            ),
            IconButton(
              onPressed: _me == null ? null : () {},
              icon: const Icon(Icons.videocam),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ],
        ),
      ),
      body: _me == null || _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null && _messages.isEmpty
              ? Center(
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
                )
              : Stack(
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
                              itemBuilder: (context, i) {
                                final msg = _messages[i];
                                final prevMsg = i > 0 ? _messages[i - 1] : null;
                                final isMine = msg.isMine(_myUserId!);
                                final showDateSeparator =
                                    _isDifferentDay(msg, prevMsg);

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
                                            borderRadius:
                                                BorderRadius.circular(12),
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
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Row(
                                        mainAxisAlignment: isMine
                                            ? MainAxisAlignment.end
                                            : MainAxisAlignment.start,
                                        children: [
                                          if (!isMine)
                                            _avatar(widget.peerAvatarUrl,
                                                size: 28)
                                          else
                                            const SizedBox(width: 28),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Column(
                                              crossAxisAlignment: isMine
                                                  ? CrossAxisAlignment.end
                                                  : CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isMine
                                                        ? _brandOrange
                                                        : Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(0.05),
                                                        blurRadius: 2,
                                                        offset:
                                                            const Offset(0, 1),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      ..._productTagsFor(msg)
                                                          .map(
                                                        (tag) => Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  bottom: 6),
                                                          child:
                                                              _productTagChip(
                                                            tag,
                                                            isMine: isMine,
                                                          ),
                                                        ),
                                                      ),
                                                      if ((msg.content ?? '')
                                                          .isNotEmpty)
                                                        Text(
                                                          msg.content!,
                                                          style: TextStyle(
                                                            color: isMine
                                                                ? Colors.white
                                                                : Colors
                                                                    .black87,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                      if ((msg.content ?? '')
                                                              .isEmpty &&
                                                          _productTagsFor(msg)
                                                              .isNotEmpty)
                                                        Text(
                                                          'Shared a product',
                                                          style: TextStyle(
                                                            color: isMine
                                                                ? Colors.white70
                                                                : Colors
                                                                    .black54,
                                                            fontSize: 13,
                                                            fontStyle: FontStyle
                                                                .italic,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _timeLabel(msg),
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.black54,
                                                  ),
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
                              },
                            ),
                    ),
                    if (activeProduct != null)
                      _buildDiscussedProductBar(activeProduct),
                    _buildInputArea(canSend),
                  ],
                ),
              ],
            ),
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
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.shopping_bag_outlined, size: size * 0.5),
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
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !_sending,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Message...',
                hintStyle: const TextStyle(color: Colors.black54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Colors.black12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            onPressed: canSend ? _sendMessage : null,
            backgroundColor: _brandOrange,
            disabledElevation: 0,
            elevation: 2,
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.send),
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
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                ),
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
