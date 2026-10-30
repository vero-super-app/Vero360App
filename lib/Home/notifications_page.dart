// lib/Home/notifications_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';
import 'package:vero360_app/GernalServices/notification_service.dart';
import 'package:vero360_app/utils/description_contact_mask.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _pageBg = Color(0xFFF4F5F7);
  static const Color _ink = Color(0xFF111827);

  bool _showUnreadOnly = false;
  bool _handlingNotificationTap = false;

  @override
  void initState() {
    super.initState();
    unawaited(NotificationStore.instance.ensureLoaded());
  }

  String _sectionLabel(DateTime dt) {
    final now = DateTime.now();
    final d = DateTime(dt.year, dt.month, dt.day);
    final t = DateTime(now.year, now.month, now.day);
    final diff = t.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(dt);
    return DateFormat('MMM d, y').format(dt);
  }

  IconData _iconFor(Map<String, dynamic> payload) {
    final type = (payload['type'] ?? '').toString().toLowerCase();
    if (type.contains('refund')) return Icons.replay_circle_filled_outlined;
    if (type.contains('escrow')) return Icons.account_balance_wallet_outlined;
    if (type.contains('food')) return Icons.restaurant_outlined;
    if (type.contains('digital')) return Icons.workspace_premium_outlined;
    if (type.contains('courier')) return Icons.local_shipping_outlined;
    if (type.contains('booking') || type.contains('stay')) {
      return Icons.hotel_outlined;
    }
    if (type.contains('order')) return Icons.shopping_bag_outlined;
    if (type.contains('chat') || type.contains('message')) {
      return Icons.chat_bubble_outline;
    }
    return Icons.notifications_rounded;
  }

  String? _mediaFrom(Map<String, dynamic> payload) {
    final candidates = [
      payload['itemImage'],
      payload['imageUrl'],
      payload['mediaUrl'],
      payload['thumbnail'],
      payload['photoUrl'],
    ];
    for (final c in candidates) {
      final s = (c ?? '').toString().trim();
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
    }
    return null;
  }

  Future<void> _onNotificationTap(AppNotificationItem n) async {
    if (_handlingNotificationTap) return;
    _handlingNotificationTap = true;

    final payload = Map<String, dynamic>.from(n.payload);
    payload.putIfAbsent('title', () => n.title);
    payload.putIfAbsent('body', () => n.body);
    final type = (payload['type'] ?? '').toString().toLowerCase();
    if (type == 'new_message') {
      final existing = (payload['senderName'] ??
              payload['peerName'] ??
              payload['title'] ??
              '')
          .toString()
          .trim();
      final title = n.title.trim();
      if (existing.isEmpty && title.isNotEmpty) {
        payload['senderName'] = title;
        payload['title'] = title;
      }
    }
    final badgeRoute = (payload[NotificationStore.kPayloadBadgeRoute] ??
            payload['badgeRoute'])
        ?.toString()
        .trim();

    if (mounted) {
      NotificationService.navigateFromPayload(context, payload);
    }

    unawaited(NotificationStore.instance.markAsRead(n.id));
    if (badgeRoute != null && badgeRoute.isNotEmpty) {
      unawaited(NotificationStore.instance.markBadgeRouteAsRead(badgeRoute));
    }

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) _handlingNotificationTap = false;
  }

  Future<void> _clearAll() async {
    final store = NotificationStore.instance;
    if (store.items.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear notifications?'),
        content: const Text('This removes the list from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.clearAll();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          ListenableBuilder(
            listenable: NotificationStore.instance,
            builder: (context, _) {
              if (NotificationStore.instance.items.isEmpty) {
                return const SizedBox.shrink();
              }
              return TextButton(
                onPressed: () => unawaited(_clearAll()),
                child: const Text(
                  'Clear',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: NotificationStore.instance,
        builder: (context, _) {
          final store = NotificationStore.instance;
          final items = _showUnreadOnly
              ? store.items.where((e) => !e.read).toList()
              : store.items;
          return Column(
            children: [
              Material(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: !_showUnreadOnly,
                        onSelected: (_) =>
                            setState(() => _showUnreadOnly = false),
                        selectedColor: _brandOrange.withValues(alpha: 0.18),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text('Unread (${store.unreadCount})'),
                        selected: _showUnreadOnly,
                        onSelected: (_) =>
                            setState(() => _showUnreadOnly = true),
                        selectedColor: _brandOrange.withValues(alpha: 0.18),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_none_rounded,
                                size: 64,
                                color: Color(0xFF9CA3AF),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No notifications yet',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: _ink,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'When an order comes in, it will show here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
                        itemCount: _grouped(items).length,
                        itemBuilder: (context, i) {
                          final row = _grouped(items)[i];
                          if (row.header != null) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
                              child: Text(
                                row.header!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            );
                          }
                          return _NotificationTile(
                            item: row.item!,
                            icon: _iconFor(row.item!.payload),
                            mediaUrl: _mediaFrom(row.item!.payload),
                            onTap: () => _onNotificationTap(row.item!),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<_ListRow> _grouped(List<AppNotificationItem> items) {
    final out = <_ListRow>[];
    String? last;
    for (final n in items) {
      final key = _sectionLabel(n.createdAt);
      if (key != last) {
        out.add(_ListRow.header(key));
        last = key;
      }
      out.add(_ListRow.item(n));
    }
    return out;
  }
}

class _ListRow {
  final String? header;
  final AppNotificationItem? item;
  const _ListRow.header(this.header) : item = null;
  const _ListRow.item(this.item) : header = null;
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.icon,
    required this.onTap,
    this.mediaUrl,
  });

  final AppNotificationItem item;
  final IconData icon;
  final String? mediaUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: item.read
                    ? const Color(0xFFE5E7EB)
                    : const Color(0xFFFF8A00).withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      const Color(0xFFFF8A00).withValues(alpha: 0.14),
                  child: Icon(icon, color: const Color(0xFFFF8A00), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DescriptionContactMask.mask(item.title),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                          height: 1.25,
                        ),
                      ),
                      if (item.body.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          DescriptionContactMask.mask(item.body),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF4B5563),
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            DateFormat('HH:mm').format(item.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9CA3AF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!item.read) ...[
                            const SizedBox(width: 8),
                            const Text(
                              'New',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFF8A00),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (mediaUrl != null)
                  Container(
                    width: 54,
                    height: 54,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.grey.shade100,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.network(
                      mediaUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
