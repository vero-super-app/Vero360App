// lib/Home/notifications_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const Color _brandOrange = Color(0xFFFF8A00);

  @override
  void initState() {
    super.initState();
    NotificationStore.instance.markAllAsRead();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        actions: [
          if (NotificationStore.instance.items.isNotEmpty)
            TextButton(
              onPressed: () async {
                await NotificationStore.instance.clearAll();
                if (mounted) setState(() {});
              },
              child: const Text('Clear all', style: TextStyle(color: Colors.white70)),
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
