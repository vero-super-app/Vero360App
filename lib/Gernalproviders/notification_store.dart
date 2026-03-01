// lib/Gernalproviders/notification_store.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Single notification item (in-app + from push).
class AppNotificationItem {
  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  bool read;

  AppNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    this.read = false,
  })  : payload = payload ?? {},
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'read': read,
      };

  static AppNotificationItem? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final id = j['id']?.toString();
    final title = j['title']?.toString();
    if (id == null || title == null) return null;
    return AppNotificationItem(
      id: id,
      title: title,
      body: (j['body'] ?? '').toString(),
      payload: j['payload'] is Map
          ? Map<String, dynamic>.from(j['payload'] as Map)
          : {},
      createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      read: j['read'] == true,
    );
  }
}

/// In-app store for notifications: list, unread count, persist and notify.
class NotificationStore extends ChangeNotifier {
  NotificationStore._();

  static final NotificationStore instance = NotificationStore._();

  static const String _prefsKey = 'vero360_notifications';
  static const int _maxStored = 200;

  final List<AppNotificationItem> _items = [];
  bool _loaded = false;

  List<AppNotificationItem> get items =>
      List.unmodifiable(_items..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  int get unreadCount => _items.where((e) => !e.read).length;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final list = jsonDecode(raw);
      if (list is List) {
        for (final e in list) {
          final item = AppNotificationItem.fromJson(
              e is Map ? Map<String, dynamic>.from(e) : null);
          if (item != null) _items.add(item);
        }
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = items.take(_maxStored).map((e) => e.toJson()).toList();
      await prefs.setString(_prefsKey, jsonEncode(list));
    } catch (_) {}
  }

  /// Add a notification (e.g. from FCM). Notifies listeners.
  Future<void> addNotification({
    required String id,
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    await _load();
    if (_items.any((e) => e.id == id)) return;
    _items.add(AppNotificationItem(
      id: id,
      title: title,
      body: body,
      payload: payload,
    ));
    await _save();
    notifyListeners();
  }

  /// Mark all as read. Call when user opens the notifications page.
  Future<void> markAllAsRead() async {
    await _load();
    bool changed = false;
    for (final item in _items) {
      if (!item.read) {
        item.read = true;
        changed = true;
      }
    }
    if (changed) {
      await _save();
      notifyListeners();
    }
  }

  /// Mark a single notification as read.
  Future<void> markAsRead(String id) async {
    await _load();
    AppNotificationItem? found;
    for (final e in _items) {
      if (e.id == id) {
        found = e;
        break;
      }
    }
    if (found != null && !found.read) {
      found.read = true;
      await _save();
      notifyListeners();
    }
  }

  /// Clear all notifications (optional).
  Future<void> clearAll() async {
    _items.clear();
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
    notifyListeners();
  }
}
