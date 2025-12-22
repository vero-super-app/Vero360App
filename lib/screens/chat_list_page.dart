// lib/screens/chat_list_page.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/services/chat_service.dart';
import 'package:vero360_app/Pages/Home/Messages.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});
  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  static const _brandOrange = Color(0xFFFF8A00);
  static const _bg = Color(0xFFF6F6F6);

  String? _myAppId;
  String? _error;

  bool _searching = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await ChatService.ensureFirebaseAuth();
      final appId = await ChatService.myAppUserId();

      try {
        await ChatService.lockUidMapping(appId);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _myAppId = appId;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final ui = _friendlyChatError(e);
      setState(() => _error = ui.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ removes scrollbars + glow “bars”
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

    final me = _myAppId;
    if (me == null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: _appBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar(),
      body: StreamBuilder<List<ChatThread>>(
        stream: ChatService.threadsStream(me),
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
            return const Center(child: CircularProgressIndicator());
          }

          var items = snap.data ?? <ChatThread>[];
          items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

          // Search filter (name + last message)
          final q = _searchCtrl.text.trim().toLowerCase();
          if (q.isNotEmpty) {
            items = items.where((t) {
              final otherId = t.otherId(me);
              final meta = (t.participants[otherId] as Map?) ?? const {};
              final name = ('${meta['name'] ?? 'Contact'}').toLowerCase();
              final last = (t.lastText).toString().toLowerCase();
              return name.contains(q) || last.contains(q);
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
              await _boot();
              await Future<void>.delayed(const Duration(milliseconds: 250));
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final t = items[i];
                final otherId = t.otherId(me);

                final meta = (t.participants[otherId] as Map?) ?? const {};
                final name = ('${meta['name'] ?? 'Contact'}').trim();

                // ✅ supports:
                // - meta['avatars'] as List
                // - meta['avatar'] as String with "," or "|" separated
                final avatarUrls = _extractAvatarUrls(meta);

                final rawLast = t.lastText.toString().trim();
                final lastSender = t.lastSenderAppId; // now populated by service
                final youPrefix = (lastSender != null && lastSender == me) ? 'You: ' : '';
                final subtitle = rawLast.isEmpty ? 'Tap to chat' : '$youPrefix$rawLast';

                return _ChatRow(
                  name: name.isEmpty ? 'Contact' : name,
                  avatarUrls: avatarUrls,
                  lastText: subtitle,
                  updatedAt: t.updatedAt,
                  unreadCount: _safeUnreadCount(t, me),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MessagePage(
                        peerAppId: otherId,
                        peerName: name.isEmpty ? 'Contact' : name,
                        peerAvatarUrl: avatarUrls.isNotEmpty ? avatarUrls.first : '',
                        peerId: '',
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add “New chat” action here.')),
          );
        },
        child: const Icon(Icons.chat_rounded),
      ),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              )
            : const Text(
                'Messages',
                key: ValueKey('title'),
                style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black),
              ),
      ),
      actions: [
        IconButton(
          tooltip: _searching ? 'Close' : 'Search',
          onPressed: () {
            setState(() {
              _searching = !_searching;
              if (!_searching) _searchCtrl.clear();
            });
          },
          icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded, color: Colors.black87),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  List<String> _extractAvatarUrls(Map meta) {
    try {
      final v = meta['avatars'];
      if (v is List) {
        return v.map((e) => '$e').where((s) => s.trim().isNotEmpty).toList();
      }
    } catch (_) {}

    final raw = ('${meta['avatar'] ?? ''}').trim();
    if (raw.isEmpty) return const [];

    if (raw.contains('|')) {
      return raw.split('|').map((e) => e.trim()).where((s) => s.isNotEmpty).toList();
    }
    if (raw.contains(',')) {
      return raw.split(',').map((e) => e.trim()).where((s) => s.isNotEmpty).toList();
    }
    return [raw];
  }

  int _safeUnreadCount(ChatThread t, String me) {
    try {
      final m = t.unread;
      if (m is Map && m?[me] is int) return m?[me] as int;
      if (m is Map && m?[me] is num) return (m?[me] as num).toInt();
    } catch (_) {}
    return 0;
  }

  _ChatUiError _friendlyChatError(Object e) {
    final raw = e.toString().toLowerCase();
    final isIndexError =
        raw.contains('failed-precondition') && raw.contains('requires an index');

    if (e is FirebaseException) {
      final code = e.code.toLowerCase();
      final msg = (e.message ?? '').toLowerCase();

      if (code == 'failed-precondition' && (msg.contains('requires an index') || isIndexError)) {
        return const _ChatUiError(
          icon: Icons.build_circle_outlined,
          title: 'Chats unavailable',
          message: 'Chats are being set up on our side. Please tap Retry in a moment.',
        );
      }

      if (code == 'permission-denied') {
        return const _ChatUiError(
          icon: Icons.lock_outline,
          title: 'Access denied',
          message: 'You don’t have access to chats. Please log in again.',
        );
      }

      if (code == 'unavailable') {
        return const _ChatUiError(
          icon: Icons.wifi_off_rounded,
          title: 'No connection',
          message: 'We can’t reach the chat service. Check your internet and try again.',
        );
      }
    }

    if (raw.contains('socketexception') ||
        raw.contains('network') ||
        raw.contains('timed out') ||
        raw.contains('timeout')) {
      return const _ChatUiError(
        icon: Icons.wifi_off_rounded,
        title: 'Connection problem',
        message: 'Please check your internet connection and try again.',
      );
    }

    return const _ChatUiError(
      icon: Icons.error_outline_rounded,
      title: 'Chats unavailable',
      message: 'Something went wrong while loading chats. Please tap Retry.',
    );
  }
}

/// ✅ Removes scrollbar + glow bars
class _NoBarsScrollBehavior extends MaterialScrollBehavior {
  const _NoBarsScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class _ChatUiError {
  final IconData icon;
  final String title;
  final String message;
  const _ChatUiError({required this.icon, required this.title, required this.message});
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
  });

  final String name;
  final List<String> avatarUrls;
  final String lastText;
  final DateTime updatedAt;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = _fmtTime(updatedAt);

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
              _AvatarCarousel(urls: avatarUrls, name: name),
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
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: unreadCount > 0 ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
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
                              color: unreadCount > 0 ? Colors.black87 : Colors.grey.shade700,
                              fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 10),
                          _UnreadPill(count: unreadCount),
                        ],
                      ],
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

  String _fmtTime(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return '';
    final now = DateTime.now();
    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ap = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $ap';
    }
    return '${dt.month}/${dt.day}/${dt.year % 100}';
  }
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
                  return Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallback(initials),
                    loadingBuilder: (c, w, p) {
                      if (p == null) return w;
                      return Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  Widget _fallback(String initials) => Center(
        child: Text(
          initials,
          style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black87),
        ),
      );

  String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
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
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
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
