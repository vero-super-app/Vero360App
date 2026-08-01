// lib/screens/chat_list_page.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GeneralModels/chat_product_context.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_cache.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/Home/MessagePageBackendApi.dart';
import 'package:vero360_app/widgets/modern_confirm_dialog.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';
import 'package:vero360_app/widgets/messaging_skeleton_loaders.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});
  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  static const _brandOrange = Color(0xFFFF8A00);
  static const _bg = Color(0xFFF7F8FA);
  static const _ink = Color(0xFF101010);
  static const _maxPinnedChats = 3;

  int? _myUserId;
  String? _myEmail;
  String? _myName;
  String? _error;
  bool _wsConnected = false;

  final _searchCtrl = TextEditingController();
  StreamSubscription<bool>? _wsConnectionSub;

  final List<String> _pinnedIds = [];
  final Set<String> _hiddenIds = {};
  StreamSubscription<BackendChatMessage>? _messageSub;
  late final Stream<List<BackendChatThread>> _threadsStream;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _threadsStream = BackendChatService.watchThreads();
    _messageSub = BackendMessagingSocket.messageStream.listen((message) async {
      final chatId = message.chatId.trim();
      if (chatId.isEmpty) return;
      // Do not resurrect chats the user deleted.
      if (_hiddenIds.contains(chatId)) return;
      if (mounted) setState(() {});
    });
    _boot();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageSub?.cancel();
    _wsConnectionSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    // Fast path: use cached backend user id so the list can render immediately.
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getInt('userId') ??
          prefs.getInt('user_id') ??
          int.tryParse(
            prefs.getString('userId') ??
                prefs.getString('user_id') ??
                prefs.getString('id') ??
                '',
          );
      if (cached != null && cached > 0 && mounted) {
        await _loadChatListPrefs(cached);
        if (!mounted) return;
        setState(() {
          _myUserId = cached;
          _myEmail = FirebaseAuth.instance.currentUser?.email;
          _myName = FirebaseAuth.instance.currentUser?.displayName;
          _error = null;
        });
      }
    } catch (_) {}

    try {
      await BackendChatService.ensureAuth();
      final userId = await BackendChatService.getUserId();
      final authUser = FirebaseAuth.instance.currentUser;

      unawaited(
        BackendMessagingSocket.connect().catchError((_) {}),
      );

      _wsConnectionSub?.cancel();
      _wsConnectionSub =
          BackendMessagingSocket.connectionStream.listen((connected) {
        if (!mounted) return;
        setState(() => _wsConnected = connected);
      });

      if (!mounted) return;
      await _loadChatListPrefs(userId);
      if (!mounted) return;
      BackendChatService.refreshThreads();
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (!BackendMessagingSocket.isConnected) {
          BackendChatService.refreshThreads();
        }
      });
      setState(() {
        _myUserId = userId;
        _myEmail = authUser?.email ?? _myEmail;
        _myName = authUser?.displayName ?? _myName;
        _error = null;
        _wsConnected = BackendMessagingSocket.isConnected;
      });    } catch (e) {
      if (!mounted) return;
      if (_myUserId != null) return; // keep cached-id UI if auth is slow/fails
      final ui = _friendlyChatError(e);
      setState(() => _error = ui.message);
    }
  }

  String _pinnedPrefsKey(int userId) => 'chat_list_pinned_$userId';
  String _hiddenPrefsKey(int userId) => 'chat_list_hidden_$userId';

  Future<void> _loadChatListPrefs(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pinnedRaw = prefs.getStringList(_pinnedPrefsKey(userId)) ?? [];
      final hiddenRaw = prefs.getStringList(_hiddenPrefsKey(userId)) ?? [];
      if (hiddenRaw.isNotEmpty) {
        await BackendMessagingCache.mergeDeletedThreadIds(userId, hiddenRaw);
      }
      await BackendChatService.applyPersistedDeletedThreads(userId);
      if (!mounted) return;
      setState(() {
        _pinnedIds
          ..clear()
          ..addAll(pinnedRaw.take(_maxPinnedChats));
        _hiddenIds
          ..clear()
          ..addAll(hiddenRaw);
      });
    } catch (_) {}
  }

  Future<void> _persistChatListPrefs() async {
    final userId = _myUserId;
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_pinnedPrefsKey(userId), _pinnedIds);
      await prefs.setStringList(_hiddenPrefsKey(userId), _hiddenIds.toList());
    } catch (_) {}
  }

  List<_ThreadTile> _mapThreads(List<BackendChatThread> raw, int me) {
    final q = _searchCtrl.text.trim().toLowerCase();

    final tiles = raw
        .where((t) => !_hiddenIds.contains(t.id))
        .map(
          (t) => _ThreadTile.fromThread(
            t,
            me,
            myEmail: _myEmail,
            myName: _myName,
            isPinned: _pinnedIds.contains(t.id),
          ),
        )
        .where((tile) => q.isEmpty || tile.searchKey.contains(q))
        .toList();

    final pinned = <_ThreadTile>[];
    final rest = <_ThreadTile>[];
    for (final tile in tiles) {
      if (tile.isPinned) {
        pinned.add(tile);
      } else {
        rest.add(tile);
      }
    }
    pinned.sort(
      (a, b) =>
          _pinnedIds.indexOf(a.threadId).compareTo(_pinnedIds.indexOf(b.threadId)),
    );
    rest.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [...pinned, ...rest];
  }

  Future<void> _togglePin(_ThreadTile tile) async {
    final wasPinned = _pinnedIds.contains(tile.threadId);
    if (wasPinned) {
      _pinnedIds.remove(tile.threadId);
    } else {
      if (_pinnedIds.length >= _maxPinnedChats) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can pin up to 3 chats. Unpin one first.'),
          ),
        );
        return;
      }
      _pinnedIds.add(tile.threadId);
    }
    await _persistChatListPrefs();
    if (mounted) setState(() {});
  }

  Future<void> _confirmDelete(_ThreadTile tile) async {
    final ok = await showModernConfirmDialog(
      context,
      title: 'Delete chat?',
      message:
          'Are you sure you want to delete this chat?',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;

    // Clear from the list immediately — don't wait on the network.
    setState(() {
      _hiddenIds.add(tile.threadId);
      _pinnedIds.remove(tile.threadId);
    });
    unawaited(_persistChatListPrefs());

    try {
      await BackendChatService.deleteChat(tile.threadId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      // Local delete already applied; keep it hidden even if server call fails.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat deleted')),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const _NoBarsScrollBehavior(),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: _appBar(),
        body: _EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Chats unavailable',
          subtitle: _error!,
          onRetry: _boot,
        ),
      );
    }

    final me = _myUserId;
    if (me == null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: _appBar(),
        body: const ChatListSkeleton(),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar(),
      body: Column(
        children: [
          _buildWhatsAppSearch(),
          Expanded(
            child: StreamBuilder<List<BackendChatThread>>(
        stream: _threadsStream,
        builder: (context, snap) {
          if (snap.hasError && (snap.data == null || snap.data!.isEmpty)) {
            final ui = _friendlyChatError(snap.error!);
            return _EmptyState(
              icon: ui.icon,
              title: ui.title,
              subtitle: ui.message,
              onRetry: _boot,
            );
          }

          if (!snap.hasData) {
            return const ChatListSkeleton();
          }

          final tiles = _mapThreads(snap.data ?? const [], me);

          if (tiles.isEmpty) {
            final q = _searchCtrl.text.trim();
            return _EmptyState(
              icon: q.isEmpty
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.search_off_rounded,
              title: q.isEmpty ? 'No chats yet' : 'No results',
              subtitle: q.isEmpty
                  ? 'When you message a seller, the conversation appears here.'
                  : 'Try a different name or message.',
            );
          }

          return SlidableAutoCloseBehavior(
            child: RefreshIndicator(
              color: _brandOrange,
              onRefresh: () async {
                BackendChatService.refreshThreads();
                await Future<void>.delayed(const Duration(milliseconds: 200));
              },
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
                cacheExtent: 480,
                itemCount: tiles.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  indent: 76,
                  endIndent: 16,
                  color: Color(0xFFECEEF2),
                ),
                itemBuilder: (_, i) {
                  final tile = tiles[i];
                  return Slidable(
                    key: ValueKey(tile.threadId),
                    startActionPane: ActionPane(
                      motion: const BehindMotion(),
                      extentRatio: 0.26,
                      children: [
                        SlidableAction(
                          onPressed: (_) => _togglePin(tile),
                          backgroundColor: tile.isPinned
                              ? const Color(0xFF6B7280)
                              : _brandOrange,
                          foregroundColor: Colors.white,
                          icon: tile.isPinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          label: tile.isPinned ? 'Unpin' : 'Pin',
                          borderRadius: BorderRadius.zero,
                        ),
                      ],
                    ),
                    endActionPane: ActionPane(
                      motion: const BehindMotion(),
                      extentRatio: 0.26,
                      children: [
                        SlidableAction(
                          onPressed: (_) => _confirmDelete(tile),
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete',
                          borderRadius: BorderRadius.zero,
                        ),
                      ],
                    ),
                    child: _ChatRow(
                      tile: tile,
                      onTap: () async {
                        BackendChatService.setActiveChatId(tile.threadId);
                        BackendChatService.clearThreadUnread(tile.threadId);
                        unawaited(
                          BackendMessagingSocket.connect().catchError((_) {}),
                        );
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MessagePageBackendApi(
                              peerId: tile.threadId,
                              peerName: tile.peerName,
                              peerAvatarUrl: tile.avatarUrl,
                              productContext: tile.product,
                              peerMerchantId: tile.product?.merchantId,
                              peerUserId: tile.peerUserId,
                            ),
                          ),
                        );
                        BackendChatService.setActiveChatId(null);
                        BackendChatService.refreshThreads();
                      },
                    ),
                  );
                },
              ),
            ),
          );
        },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppSearch() {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F2F5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 15, height: 1.2),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search',
              hintStyle: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 15,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 22,
                color: Colors.grey.shade600,
              ),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: Colors.grey.shade600,
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleSpacing: 16,
      title: const Text(
        'Messages',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 22,
          color: _ink,
          letterSpacing: -0.3,
        ),
      ),
      actions: [
        Tooltip(
          message: _wsConnected ? 'Connected' : 'Reconnecting…',
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              Icons.circle,
              size: 9,
              color: _wsConnected
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFF59E0B),
            ),
          ),
        ),
      ],
    );
  }

  _ChatUiError _friendlyChatError(Object e) {
    final raw = e.toString().toLowerCase();

    if (raw.contains('unauthorized') || raw.contains('401')) {
      return const _ChatUiError(
        icon: Icons.lock_outline,
        title: 'Authentication failed',
        message: 'Please log in again to continue.',
      );
    }

    if (raw.contains('socketexception') ||
        raw.contains('network') ||
        raw.contains('timed out') ||
        raw.contains('timeout') ||
        raw.contains('connection refused')) {
      return const _ChatUiError(
        icon: Icons.wifi_off_rounded,
        title: 'Connection problem',
        message: 'Cannot reach the server. Check your internet and try again.',
      );
    }

    return const _ChatUiError(
      icon: Icons.error_outline_rounded,
      title: 'Chats unavailable',
      message: 'Something went wrong while loading chats. Please tap Retry.',
    );
  }
}

class _ThreadTile {
  final String threadId;
  final String title;
  final String peerName;
  final String? peerLabel;
  final String avatarUrl;
  final String? productImageUrl;
  final String preview;
  final ChatLastMessagePreviewKind previewKind;
  final DateTime updatedAt;
  final int unreadCount;
  final ChatProductContext? product;
  final String searchKey;
  final bool isPinned;
  final int? peerUserId;

  const _ThreadTile({
    required this.threadId,
    required this.title,
    required this.peerName,
    required this.peerLabel,
    required this.avatarUrl,
    required this.productImageUrl,
    required this.preview,
    this.previewKind = ChatLastMessagePreviewKind.text,
    required this.updatedAt,
    required this.unreadCount,
    required this.product,
    required this.searchKey,
    this.isPinned = false,
    this.peerUserId,
  });

  factory _ThreadTile.fromThread(
    BackendChatThread t,
    int me, {
    String? myEmail,
    String? myName,
    bool isPinned = false,
  }) {
    // Never fall back to the current user — that made the list show your own name.
    final otherParticipant = t.otherParticipant(
      me,
      myEmail: myEmail,
      myName: myName,
    );
    final threadTitle = (t.name ?? '').trim();
    final myEmailNorm = (myEmail ?? '').trim().toLowerCase();
    final myNameNorm = (myName ?? '').trim().toLowerCase();
    final myEmailLocal = myEmailNorm.contains('@')
        ? myEmailNorm.split('@').first
        : myEmailNorm;

    bool looksLikeMe(String raw) {
      final n = raw.trim().toLowerCase();
      if (n.isEmpty) return false;
      if (myNameNorm.isNotEmpty && n == myNameNorm) return true;
      if (myEmailNorm.isNotEmpty && n == myEmailNorm) return true;
      if (myEmailLocal.isNotEmpty && n == myEmailLocal) return true;
      return false;
    }

    var peerName = (otherParticipant?.name ?? '').trim();
    if (peerName.isEmpty ||
        peerName.toLowerCase() == 'user' ||
        peerName.toLowerCase() == 'unknown' ||
        peerName.toLowerCase() == 'contact' ||
        looksLikeMe(peerName)) {
      final email = (otherParticipant?.email ?? '').trim();
      if (email.contains('@') &&
          !email.startsWith('+firebase_') &&
          email.toLowerCase() != myEmailNorm) {
        peerName = email.split('@').first;
      } else if (threadTitle.isNotEmpty &&
          threadTitle.toLowerCase() != 'direct' &&
          threadTitle.toLowerCase() != 'user' &&
          !looksLikeMe(threadTitle)) {
        peerName = threadTitle;
      } else {
        // Last resort: any other participant we haven't tried.
        for (final p in t.participants) {
          if (me > 0 && p.id > 0 && p.id == me) continue;
          if (looksLikeMe(p.name) || looksLikeMe(p.email)) continue;
          final candidate = p.name.trim();
          if (candidate.isNotEmpty &&
              candidate.toLowerCase() != 'contact' &&
              candidate.toLowerCase() != 'user') {
            peerName = candidate;
            break;
          }
        }
      }
    }
    if (peerName.isEmpty || looksLikeMe(peerName)) peerName = 'Contact';

    final product = t.lastProductTag;
    final display = BackendChatService.describeLastMessagePreview(
      t.lastMessagePreview,
    );
    final preview = display.label.isNotEmpty
        ? display.label
        : (product != null
            ? 'Enquiry about ${product.name}'
            : (t.type == 'direct' ? 'Tap to open chat' : (t.name ?? 'Group chat')));
    final previewKind = display.label.isNotEmpty
        ? display.kind
        : ChatLastMessagePreviewKind.text;

    // Prefer the peer's name for the row title; product name is secondary label.
    final title = peerName;
    final peerLabel = product != null ? product.name : null;
    final avatarUrl = (otherParticipant?.profilePicture ?? t.avatarUrl ?? '')
        .trim();

    return _ThreadTile(
      threadId: t.id,
      title: title,
      peerName: peerName,
      peerLabel: peerLabel,
      avatarUrl: avatarUrl,
      productImageUrl: product?.image,
      preview: preview,
      previewKind: previewKind,
      updatedAt: t.updatedAt,
      unreadCount: t.unreadCount,
      product: product,
      searchKey: [
        title,
        peerName,
        peerLabel ?? '',
        product?.name ?? '',
        preview,
      ].join(' ').toLowerCase(),
      isPinned: isPinned,
      peerUserId: otherParticipant != null && otherParticipant.id > 0
          ? otherParticipant.id
          : null,
    );
  }
}

String _fmtTime(DateTime dt) {
  if (dt.millisecondsSinceEpoch == 0) return '';
  final now = DateTime.now();
  final sameDay =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  if (sameDay) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (dt.year == yesterday.year &&
      dt.month == yesterday.month &&
      dt.day == yesterday.day) {
    return 'Yesterday';
  }
  if (dt.year == now.year) {
    return '${dt.month}/${dt.day}';
  }
  return '${dt.month}/${dt.day}/${dt.year % 100}';
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.name,
    required this.imageUrl,
    this.size = 52,
  });

  final String name;
  final String imageUrl;
  final double size;

  static const _palette = <Color>[
    Color(0xFFFF8A00),
    Color(0xFF2D9CDB),
    Color(0xFF27AE60),
    Color(0xFF9B51E0),
    Color(0xFFEB5757),
    Color(0xFF16284C),
    Color(0xFF00B894),
    Color(0xFF6C5CE7),
  ];

  static Color _colorFor(String seed) {
    var hash = 0;
    for (final c in seed.codeUnits) {
      hash = c + ((hash << 5) - hash);
    }
    return _palette[hash.abs() % _palette.length];
  }

  static String _letter(String n) {
    final trimmed = n.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    final letter = _letter(name);
    final color = _colorFor(name.isEmpty ? 'contact' : name);

    if (url.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipOval(
          child: ResilientCachedNetworkImage(
            url: url,
            fit: BoxFit.cover,
            width: size,
            height: size,
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            color,
            Color.lerp(color, Colors.black, 0.18)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.38,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF8A00),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  static const _brandOrange = Color(0xFFFF8A00);

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 30, color: const Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: Color(0xFF101010),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF6B7280), height: 1.4),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoBarsScrollBehavior extends MaterialScrollBehavior {
  const _NoBarsScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _ChatUiError {
  final IconData icon;
  final String title;
  final String message;
  const _ChatUiError({
    required this.icon,
    required this.title,
    required this.message,
  });
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.tile,
    required this.onTap,
  });

  final _ThreadTile tile;
  final VoidCallback onTap;

  static const _ink = Color(0xFF101010);
  static const _muted = Color(0xFF6B7280);
  static const _brandOrange = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context) {
    final unread = tile.unreadCount > 0;
    final time = _fmtTime(tile.updatedAt);
    final hasProductImage =
        tile.productImageUrl != null && tile.productImageUrl!.trim().isNotEmpty;

    return Material(
      color: unread
          ? const Color(0xFFFFF9F2)
          : (tile.isPinned ? const Color(0xFFFFFBF5) : Colors.white),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ChatAvatar(
                name: tile.peerLabel ?? tile.title,
                imageUrl: tile.avatarUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (tile.isPinned) ...[
                          Icon(
                            Icons.push_pin_rounded,
                            size: 14,
                            color: _brandOrange.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            tile.title,                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: unread ? FontWeight.w800 : FontWeight.w700,
                              fontSize: 16,
                              color: _ink,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 12,
                            color: unread ? _brandOrange : _muted,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (tile.peerLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        tile.peerLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: _ThreadPreviewLine(
                            preview: tile.preview,
                            kind: tile.previewKind,
                            unread: unread,
                          ),
                        ),
                        if (unread && !hasProductImage) ...[
                          const SizedBox(width: 8),
                          _UnreadDot(count: tile.unreadCount),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (hasProductImage) ...[
                const SizedBox(width: 10),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 48,
                        height: 48,
                        color: const Color(0xFFF1F3F6),
                        child: ResilientCachedNetworkImage(
                          url: tile.productImageUrl!,
                          fit: BoxFit.cover,
                          width: 48,
                          height: 48,
                        ),
                      ),
                    ),
                    if (unread)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: _UnreadDot(count: tile.unreadCount),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadPreviewLine extends StatelessWidget {
  const _ThreadPreviewLine({
    required this.preview,
    required this.kind,
    required this.unread,
  });

  final String preview;
  final ChatLastMessagePreviewKind kind;
  final bool unread;

  static const _ink = Color(0xFF101010);
  static const _muted = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final color = unread ? _ink.withValues(alpha: 0.82) : _muted;
    final style = TextStyle(
      fontSize: 14,
      height: 1.2,
      color: color,
      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
    );

    final icon = switch (kind) {
      ChatLastMessagePreviewKind.voice => Icons.mic_rounded,
      ChatLastMessagePreviewKind.photo => Icons.photo_camera_outlined,
      ChatLastMessagePreviewKind.video => Icons.videocam_outlined,
      ChatLastMessagePreviewKind.text => null,
    };

    if (icon == null) {
      return Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
