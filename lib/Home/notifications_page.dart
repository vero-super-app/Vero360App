// lib/Home/notifications_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const Color _brandOrange = Color(0xFFFF8A00);

  String _profilePictureUrl = '';
  bool _showUnreadOnly = false;

  @override
  void initState() {
    super.initState();
    _loadProfilePicture();
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
    if (type.contains('order')) return Icons.shopping_bag_outlined;
    if (type.contains('chat') || type.contains('message')) return Icons.chat_bubble_outline;
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

  Future<void> _loadProfilePicture() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('profilepicture') ?? '';
    if (mounted) setState(() => _profilePictureUrl = url);
  }

  void _showProfilePictureViewer() {
    if (_profilePictureUrl.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _profilePictureUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 64, color: Colors.white70),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: ListenableBuilder(
          listenable: NotificationStore.instance,
          builder: (context, _) {
            final store = NotificationStore.instance;
            final total = store.items.length;
            final unread = store.unreadCount;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _showProfilePictureViewer,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white24,
                    backgroundImage: _profilePictureUrl.isNotEmpty
                        ? NetworkImage(_profilePictureUrl)
                        : null,
                    child: _profilePictureUrl.isEmpty
                        ? const Icon(Icons.person, color: Colors.white70, size: 22)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      unread > 0
                          ? '$unread unread'
                          : '$total ${total == 1 ? 'notification' : 'notifications'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        actions: [
          ListenableBuilder(
            listenable: NotificationStore.instance,
            builder: (context, _) {
              if (NotificationStore.instance.items.isEmpty) return const SizedBox.shrink();
              return TextButton(
                onPressed: () async {
                  await NotificationStore.instance.clearAll();
                  if (mounted) setState(() {});
                },
                child: const Text('Clear all', style: TextStyle(color: Colors.white70)),
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
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          final grouped = <String, List<AppNotificationItem>>{};
          for (final n in items) {
            final key = _sectionLabel(n.createdAt);
            grouped.putIfAbsent(key, () => []).add(n);
          }
          final sections = grouped.entries.toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            children: [
              Row(
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: !_showUnreadOnly,
                    onSelected: (_) => setState(() => _showUnreadOnly = false),
                    selectedColor: _brandOrange.withOpacity(0.18),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text('Unread (${store.unreadCount})'),
                    selected: _showUnreadOnly,
                    onSelected: (_) => setState(() => _showUnreadOnly = true),
                    selectedColor: _brandOrange.withOpacity(0.18),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final sec in sections) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
                  child: Text(
                    sec.key,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                for (final n in sec.value)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => NotificationStore.instance.markAsRead(n.id),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: n.read
                              ? Colors.black12
                              : _brandOrange.withOpacity(0.4),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 14,
                            spreadRadius: -10,
                            offset: Offset(0, 8),
                            color: Color(0x1A000000),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: _brandOrange.withOpacity(0.14),
                            child: Icon(
                              _iconFor(n.payload),
                              color: _brandOrange,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  n.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (n.body.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    n.body,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF4B5563),
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Text(
                                      DateFormat('HH:mm').format(n.createdAt),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF9CA3AF),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (!n.read) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFFF8A00),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (_mediaFrom(n.payload) != null)
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
                                _mediaFrom(n.payload)!,
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
              ],
            ],
          );
        },
      ),
    );
  }
}
