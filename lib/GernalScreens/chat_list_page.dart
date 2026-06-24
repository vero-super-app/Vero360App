// lib/screens/chat_list_page.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/Home/MessagePageBackendApi.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';
import 'package:vero360_app/widgets/messaging_skeleton_loaders.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});
  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  static const _brandOrange = Color(0xFFFF8A00);
  static const _bg = Color(0xFFF6F6F6);

  int? _myUserId;
  String? _error;
  bool _wsConnected = false;

  bool _searching = false;
  final _searchCtrl = TextEditingController();
  StreamSubscription<bool>? _wsConnectionSub;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _wsConnectionSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await BackendChatService.ensureAuth();
      final userId = await BackendChatService.getUserId();

      try {
        await BackendMessagingSocket.connect();
      } catch (_) {}

      _wsConnectionSub?.cancel();
      _wsConnectionSub =
          BackendMessagingSocket.connectionStream.listen((connected) {
        if (!mounted) return;
        setState(() => _wsConnected = connected);
      });

      if (!mounted) return;
      setState(() {
        _myUserId = userId;
        _error = null;
        _wsConnected = BackendMessagingSocket.isConnected;
      });
    } catch (e) {
      if (!mounted) return;
      final ui = _friendlyChatError(e);
      setState(() => _error = ui.message);
    }
  }

  void _showTestMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Test Actions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _sendTestMessage(context),
                icon: const Icon(Icons.send),
                label: const Text('Send Test Message to All Users'),
                style: FilledButton.styleFrom(
                  backgroundColor: _brandOrange,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendTestMessage(BuildContext context) async {
    Navigator.pop(context);

    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      const SnackBar(content: Text('Sending test messages...')),
    );

    try {
      final count = await BackendChatService.sendTestMessageToAllUsers(
        testMessage: '✅ Test message from ${DateTime.now()}',
      );

      if (!mounted) return;
      final msg = count == 0
          ? 'No active users found'
          : 'Test messages sent to $count users!';
      scaffold.showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: count > 0 ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      scaffold.showSnackBar(
        SnackBar(
          content: Text('Error: ${_friendlyChatError(e).message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ removes scrollbars + glow "bars"
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
      body: StreamBuilder<List<BackendChatThread>>(
        stream: BackendChatService.watchThreads(),
        builder: (context, snap) {
          if (snap.hasError) {
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

          var items = snap.data ?? <BackendChatThread>[];
          items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

          // Search filter (name + chat type)
          final q = _searchCtrl.text.trim().toLowerCase();
          if (q.isNotEmpty) {
            items = items.where((t) {
              final otherParticipant = t.participants.firstWhere(
                (p) => p.id != me,
                orElse: () => t.participants.isNotEmpty
                    ? t.participants.first
                    : ChatParticipant(id: 0, name: 'Contact', email: ''),
              );
              var pName = otherParticipant.name.toLowerCase();
              if (pName.isEmpty || pName == 'user') {
                pName = otherParticipant.email.split('@').first.toLowerCase();
              }
              final chatName = (t.name ?? '').toLowerCase();
              final productName = (t.lastProductTag?.name ?? '').toLowerCase();
              return pName.contains(q) ||
                  chatName.contains(q) ||
                  productName.contains(q);
            }).toList();
          }

          if (items.isEmpty) {
            return const _EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'No chats yet',
              subtitle: 'Start a conversation and it will appear here.',
            );
          }

          return RefreshIndicator(
            color: _brandOrange,
            onRefresh: () async {
              BackendChatService.refreshThreads();
              await Future<void>.delayed(const Duration(milliseconds: 250));
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final t = items[i];
                final otherParticipant = t.participants.firstWhere(
                  (p) => p.id != me,
                  orElse: () => t.participants.isNotEmpty
                      ? t.participants.first
                      : ChatParticipant(id: 0, name: 'Contact', email: ''),
                );

                // Use participant name, but fall back to email prefix
                // if name is empty or a generic placeholder like "user"
                var name = otherParticipant.name.trim();
                if (name.isEmpty || name.toLowerCase() == 'user') {
                  final email = otherParticipant.email.trim();
                  if (email.contains('@') && !email.startsWith('+firebase_')) {
                    name = email.split('@').first;
                  } else if (t.name != null && t.name!.trim().isNotEmpty) {
                    name = t.name!.trim();
                  }
                }
                final avatarUrl = otherParticipant.profilePicture ?? '';
                final product = t.lastProductTag;

                final preview = (t.lastMessagePreview ?? '').trim();
                final subtitle = preview.isNotEmpty
                    ? preview
                    : (product != null
                        ? 'Enquiry about ${product.name}'
                        : (t.type == 'direct'
                            ? 'Tap to chat'
                            : (t.name ?? 'Group chat')));

                final rowTitle = product?.name ??
                    (name.isEmpty ? 'Contact' : name);
                final rowPeerLabel = product != null
                    ? (name.isEmpty ? 'Seller' : name)
                    : null;

                return _ChatRow(
                  name: rowTitle,
                  peerLabel: rowPeerLabel,
                  avatarUrls: avatarUrl.isNotEmpty ? [avatarUrl] : [],
                  productImageUrl: product?.image,
                  lastText: subtitle,
                  updatedAt: t.updatedAt,
                  unreadCount: t.unreadCount,
                  onTap: () async {
                    BackendChatService.setActiveChatId(t.id);
                    BackendChatService.clearThreadUnread(t.id);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MessagePageBackendApi(
                          peerId: t.id,
                          peerName: name.isEmpty ? 'Contact' : name,
                          peerAvatarUrl: avatarUrl,
                          productContext: product,
                        ),
                      ),
                    );
                    BackendChatService.setActiveChatId(null);
                    BackendChatService.refreshThreads();
                  },
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: kDebugMode
          ? FloatingActionButton(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
              onPressed: () => _showTestMenu(context),
              child: const Icon(Icons.chat_rounded),
            )
          : null,
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.6,
      titleSpacing: 16,
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _searching
            ? Container(
                key: const ValueKey('search'),
                height: 40,
                alignment: Alignment.center,
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search chats',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF3F3F3),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
              )
            : const Text(
                'Messages',
                key: ValueKey('title'),
                style:
                    TextStyle(fontWeight: FontWeight.w900, color: Colors.black),
              ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            Icons.circle,
            size: 10,
            color: _wsConnected ? const Color(0xFF39C16C) : Colors.orange,
          ),
        ),
        IconButton(
          tooltip: _searching ? 'Close' : 'Search',
          onPressed: () {
            setState(() {
              _searching = !_searching;
              if (!_searching) _searchCtrl.clear();
            });
          },
          icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded,
              color: Colors.black87),
        ),
        const SizedBox(width: 6),
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

    if (raw.contains('failed') || raw.contains('error')) {
      return const _ChatUiError(
        icon: Icons.error_outline_rounded,
        title: 'Chats unavailable',
        message: 'Something went wrong while loading chats. Please tap Retry.',
      );
    }

    return const _ChatUiError(
      icon: Icons.error_outline_rounded,
      title: 'Chats unavailable',
      message: 'Something went wrong. Please tap Retry.',
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
  return '${dt.month}/${dt.day}/${dt.year % 100}';
}

class _AvatarCarousel extends StatefulWidget {
  const _AvatarCarousel({required this.urls, required this.name});
  final List<String> urls;
  final String name;

  @override
  State<_AvatarCarousel> createState() => _AvatarCarouselState();
}

class _AvatarCarouselState extends State<_AvatarCarousel> {
  late final PageController _pc;
  Timer? _timer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _pc = PageController();

    // ✅ auto-slide only when > 1 image
    if (widget.urls.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        _i = (_i + 1) % widget.urls.length;
        _pc.animateToPage(
          _i,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant _AvatarCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // restart timer if urls count changes
    if (oldWidget.urls.length != widget.urls.length) {
      _timer?.cancel();
      _i = 0;
      if (widget.urls.length > 1) {
        _timer = Timer.periodic(const Duration(seconds: 3), (_) {
          if (!mounted) return;
          _i = (_i + 1) % widget.urls.length;
          _pc.animateToPage(
            _i,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOut,
          );
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initials(widget.name);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 48,
        height: 48,
        color: Colors.grey.shade200,
        child: widget.urls.isEmpty
            ? _fallback(initials)
            : PageView.builder(
                controller: _pc,
                itemCount: widget.urls.length,
                physics: const NeverScrollableScrollPhysics(), // auto only
                itemBuilder: (_, idx) {
                  final url = widget.urls[idx];
                  return ResilientCachedNetworkImage(
                    url: url,
                    fit: BoxFit.cover,
                    width: 48,
                    height: 48,
                  );
                },
              ),
      ),
    );
  }

  Widget _fallback(String initials) => Center(
        child: Text(
          initials,
          style: const TextStyle(
              fontWeight: FontWeight.w900, color: Colors.black87),
        ),
      );

  String _initials(String n) {
    final parts =
        n.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _UnreadPill extends StatelessWidget {
  static const _brandOrange = Color(0xFFFF8A00);

  const _UnreadPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _brandOrange,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
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
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.black54),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandOrange,
                  foregroundColor: Colors.white,
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

/// ✅ Removes scrollbar + glow bars
class _NoBarsScrollBehavior extends MaterialScrollBehavior {
  const _NoBarsScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class _ChatUiError {
  final IconData icon;
  final String title;
  final String message;
  const _ChatUiError(
      {required this.icon, required this.title, required this.message});
}

// ─────────────────────────────────────────────────────────────

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.name,
    required this.avatarUrls,
    required this.lastText,
    required this.updatedAt,
    required this.unreadCount,
    required this.onTap,
    this.peerLabel,
    this.productImageUrl,
  });

  final String name;
  final String? peerLabel;
  final List<String> avatarUrls;
  final String? productImageUrl;
  final String lastText;
  final DateTime updatedAt;
  final int unreadCount;
  final VoidCallback onTap;

  static const _brandOrange = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context) {
    final time = _fmtTime(updatedAt);
    final hasProductImage =
        productImageUrl != null && productImageUrl!.trim().isNotEmpty;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _AvatarCarousel(urls: avatarUrls, name: peerLabel ?? name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (peerLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        peerLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lastText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: unreadCount > 0
                                  ? Colors.black87
                                  : Colors.grey.shade700,
                              fontWeight: unreadCount > 0
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (unreadCount > 0 && !hasProductImage) ...[
                          const SizedBox(width: 10),
                          _UnreadPill(count: unreadCount),
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
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 52,
                        height: 52,
                        color: Colors.grey.shade200,
                        child: ResilientCachedNetworkImage(
                          url: productImageUrl!,
                          fit: BoxFit.cover,
                          width: 52,
                          height: 52,
                        ),
                      ),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: _UnreadPill(count: unreadCount),
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
