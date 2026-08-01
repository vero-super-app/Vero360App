// lib/Gernalproviders/notification_store.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/GeneralModels/order_model.dart';

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

  static const String _prefsKeyBase = 'vero360_notifications';
  static const int _maxStored = 200;

  /// Payload key for routing badge counts to quick actions (profile / merchant grid).
  static const String kPayloadBadgeRoute = 'badgeRoute';

  /// Quick-action / grid targets — keep in sync with UI tiles.
  static const String kBadgeMyOrders = 'quick_my_orders';
  static const String kBadgeShipped = 'quick_shipped';
  static const String kBadgeReceived = 'quick_received';
  static const String kBadgeRefund = 'quick_refund';
  static const String kBadgePromotions = 'quick_promotions';
  static const String kBadgePostArrival = 'quick_post_arrival';

  /// Maps order notifications to the correct dashboard tile (merchant vs buyer).
  static String badgeRouteForOrderStatus(
    OrderStatus status, {
    required bool isMerchant,
  }) {
    if (isMerchant) {
      switch (status) {
        case OrderStatus.pending:
          return kBadgeMyOrders;
        case OrderStatus.confirmed:
          return kBadgeShipped;
        case OrderStatus.delivered:
          return kBadgeReceived;
        case OrderStatus.cancelled:
          return kBadgeMyOrders;
      }
    } else {
      switch (status) {
        case OrderStatus.pending:
        case OrderStatus.confirmed:
        case OrderStatus.cancelled:
          return kBadgeMyOrders;
        case OrderStatus.delivered:
          return kBadgeReceived;
      }
    }
  }

  final List<AppNotificationItem> _items = [];
  bool _loaded = false;
  String _loadedKey = '';

  Future<String> _storageKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = (prefs.getString('uid') ?? '').trim();
      if (uid.isNotEmpty) return '${_prefsKeyBase}_$uid';
    } catch (_) {}
    return '${_prefsKeyBase}_guest';
  }

  List<AppNotificationItem> get items =>
      List.unmodifiable(_items..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  int get unreadCount => _items.where((e) => !e.read).length;

  /// Unread notifications for a quick-action tile (FCM / manual must set [kPayloadBadgeRoute] or legacy `order_update`).
  int unreadCountForBadgeRoute(String route) {
    return _items.where((e) => !e.read && _itemMatchesBadgeRoute(e, route)).length;
  }

  bool _itemMatchesBadgeRoute(AppNotificationItem e, String route) {
    final explicit = (e.payload[kPayloadBadgeRoute] ?? e.payload['badgeRoute'])
        ?.toString()
        .trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit == route;
    }
    final type = (e.payload['type'] ?? '').toString().toLowerCase();
    final status = (e.payload['status'] ?? '').toString().toLowerCase();
    if (type == 'refund_update' || type == 'refund_request') {
      return route == kBadgeRefund;
    }
    if (type != 'order_update') return false;
    switch (route) {
      case kBadgeReceived:
        return status == 'delivered';
      case kBadgeShipped:
        return status == 'confirmed';
      case kBadgeMyOrders:
        // Legacy: avoid double-counting with shipped (confirmed → shipped only).
        return status == 'pending' || status == 'cancelled';
      default:
        return false;
    }
  }

  /// Call when user opens the matching screen so the badge clears.
  Future<void> markBadgeRouteAsRead(String route) async {
    await _load();
    var changed = false;
    for (final item in _items) {
      if (!item.read && _itemMatchesBadgeRoute(item, route)) {
        item.read = true;
        changed = true;
      }
    }
    if (changed) {
      await _save();
      notifyListeners();
    }
  }

  /// Loads persisted notifications from disk (call after login / on app start).
  Future<void> ensureLoaded() async {
    await _load();
    notifyListeners();
  }

  Future<void> _load() async {
    final key = await _storageKey();
    if (_loaded && _loadedKey == key) return;
    _loaded = true;
    _loadedKey = key;
    _items.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
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
      final key = await _storageKey();
      final list = items.take(_maxStored).map((e) => e.toJson()).toList();
      await prefs.setString(key, jsonEncode(list));
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
    final key = await _storageKey();
    _items.clear();
    _loaded = true;
    _loadedKey = key;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
    notifyListeners();
  }
}
