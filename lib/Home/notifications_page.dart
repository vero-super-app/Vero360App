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

  @override
  void initState() {
    super.initState();
    NotificationStore.instance.markAllAsRead();
    _loadProfilePicture();
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
          final items = NotificationStore.instance.items;
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
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final n = items[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _brandOrange.withOpacity(0.2),
                  child: const Icon(Icons.notifications_rounded, color: _brandOrange),
                ),
                title: Text(
                  n.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (n.body.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          n.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMM d, y • HH:mm').format(n.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}
