import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/GeneralPages/Toreceive.dart';
import 'package:vero360_app/GeneralPages/Toship.dart';
import 'package:vero360_app/GernalServices/order_party_notification_service.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/food_my_orders_page.dart';

/// In-app chat thread for Vero360 Team tips (order ship / receive / shelf).
/// Content lives in Firestore [order_party_alerts]; the notification tray only
/// increments badge counts.
class VeroTeamChatPage extends StatefulWidget {
  const VeroTeamChatPage({super.key});

  static const threadId = 'vero360_team';
  static const displayName = 'Vero360 Team';

  @override
  State<VeroTeamChatPage> createState() => _VeroTeamChatPageState();
}

enum _TeamAction {
  sendParcel,
  receivedParcel,
  foodOrders,
  shelf,
}

class _VeroTeamChatPageState extends State<VeroTeamChatPage> {
  static const _brandOrange = Color(0xFFFF8A00);
  static const _ink = Color(0xFF101010);
  static const _bg = Color(0xFFECE5DD);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<_TeamMessage> _messages = const [];
  bool _loading = true;
  bool _markedRead = false;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listen() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      setState(() {
        _messages = const [];
        _loading = false;
      });
      return;
    }

    _sub = FirebaseFirestore.instance
        .collection(OrderPartyNotificationService.collectionName)
        .where('toUid', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      final items = <_TeamMessage>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['cleared'] == true) continue;

        final title = (data['title'] ?? '').toString().trim();
        final body = (data['body'] ?? '').toString().trim();
        if (body.isEmpty && title.isEmpty) continue;

        DateTime? at;
        final rawAt = data['createdAt'];
        if (rawAt is Timestamp) at = rawAt.toDate();

        Map<String, dynamic>? payload;
        final rawPayload = data['payload'];
        if (rawPayload is Map) {
          payload = Map<String, dynamic>.from(
            rawPayload.map((k, v) => MapEntry(k.toString(), v)),
          );
        }

        final read = data['read'] == true || data['consumed'] == true;

        items.add(
          _TeamMessage(
            id: doc.id,
            title: title.isEmpty ? VeroTeamChatPage.displayName : title,
            body: body,
            createdAt: at,
            read: read,
            payload: payload,
          ),
        );
      }
      items.sort((a, b) {
        final aa = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aa.compareTo(bb);
      });
      if (!mounted) return;
      setState(() {
        _messages = items;
        _loading = false;
      });
      if (!_markedRead && items.any((m) => !m.read)) {
        _markedRead = true;
        unawaited(_markAllRead(items.where((m) => !m.read).map((m) => m.id)));
      }
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _markAllRead(Iterable<String> ids) async {
    await _batchUpdate(ids, {'read': true, 'consumed': true});
  }

  Future<void> _batchUpdate(
    Iterable<String> ids,
    Map<String, dynamic> data,
  ) async {
    final list = ids.toList();
    for (var i = 0; i < list.length; i += 400) {
      final chunk = list.sublist(i, i + 400 > list.length ? list.length : i + 400);
      final batch = FirebaseFirestore.instance.batch();
      for (final id in chunk) {
        batch.set(
          FirebaseFirestore.instance
              .collection(OrderPartyNotificationService.collectionName)
              .doc(id),
          data,
          SetOptions(merge: true),
        );
      }
      try {
        await batch.commit();
      } catch (_) {}
    }
  }

  Future<void> _clearChat() async {
    if (_clearing || _messages.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
          'This removes all Vero360 Team messages from this chat.',
        ),
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
    if (ok != true || !mounted) return;

    setState(() => _clearing = true);
    final ids = _messages.map((m) => m.id).toList();
    await _batchUpdate(ids, {
      'cleared': true,
      'read': true,
      'consumed': true,
    });
    if (mounted) {
      setState(() {
        _messages = const [];
        _clearing = false;
      });
    }
  }

  /// Resolve destination from payload + message text (never default to My Orders).
  _TeamAction _actionFor(_TeamMessage msg) {
    final payload = msg.payload ?? const <String, dynamic>{};
    final actionHint =
        (payload['action'] ?? '').toString().trim().toLowerCase();
    if (actionHint == 'send_parcel' || actionHint == 'send') {
      return _TeamAction.sendParcel;
    }
    if (actionHint == 'received_parcel' || actionHint == 'received') {
      return _TeamAction.receivedParcel;
    }

    final route = (payload[NotificationStore.kPayloadBadgeRoute] ??
            payload['badgeRoute'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    final type = (payload['type'] ?? '').toString().trim().toLowerCase();
    final role = (payload['role'] ?? '').toString().trim().toLowerCase();
    final text = '${msg.title} ${msg.body}'.toLowerCase();

    if (type == 'out_of_stock_shelf' ||
        route == NotificationStore.kBadgePostArrival) {
      return _TeamAction.shelf;
    }
    if (type == 'food_order' || type == 'food_order_placed') {
      return _TeamAction.foodOrders;
    }

    // Explicit send / ship routes.
    if (route == NotificationStore.kBadgeShipped ||
        type == 'ship_reminder' ||
        role == 'merchant' ||
        text.contains('send parcel') ||
        text.contains('to ship') ||
        text.contains('upload courier') ||
        text.contains('pack and ship') ||
        text.contains('reminded you to ship') ||
        text.contains('please ship')) {
      return _TeamAction.sendParcel;
    }

    // Explicit received routes.
    if (route == NotificationStore.kBadgeReceived ||
        type == 'order_completed' ||
        type == 'order_escrow_released' ||
        type == 'order_update' ||
        role == 'buyer' ||
        text.contains('received parcel') ||
        text.contains('confirm receipt') ||
        text.contains('has been shipped') ||
        text.contains('confirm when')) {
      return _TeamAction.receivedParcel;
    }

    // Safe default for remaining team tips: Received section (buyer track).
    return _TeamAction.receivedParcel;
  }

  String _ctaLabel(_TeamAction action) {
    switch (action) {
      case _TeamAction.sendParcel:
        return 'Open Send Parcel';
      case _TeamAction.receivedParcel:
        return 'Open Received Parcel';
      case _TeamAction.foodOrders:
        return 'Open Food Orders';
      case _TeamAction.shelf:
        return 'Manage shelf';
    }
  }

  Future<void> _openAction(_TeamMessage msg) async {
    final action = _actionFor(msg);
    final Widget page;
    switch (action) {
      case _TeamAction.sendParcel:
        page = const ToShipPage();
        break;
      case _TeamAction.receivedParcel:
        page = const DeliveredOrdersPage();
        break;
      case _TeamAction.foodOrders:
        page = const FoodMyOrdersPage();
        break;
      case _TeamAction.shelf:
        final email =
            (FirebaseAuth.instance.currentUser?.email ?? '').trim();
        page = MarketplaceMerchantDashboard(
          email: email,
          merchantUid: FirebaseAuth.instance.currentUser?.uid,
          onBackToHomeTab: () {},
        );
        break;
    }

    // Clear this tip after the user follows it.
    unawaited(_batchUpdate([msg.id], {
      'cleared': true,
      'read': true,
      'consumed': true,
    }));

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0E0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _brandOrange.withValues(alpha: 0.35),
                ),
              ),
              alignment: Alignment.center,
              child: Image.asset(
                'assets/logo_mark.png',
                width: 24,
                height: 24,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.support_agent_rounded,
                  color: _brandOrange,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    VeroTeamChatPage.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: _ink,
                    ),
                  ),
                  Text(
                    'Tips · Send & Received parcels',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'Clear chat',
              onPressed: _clearing ? null : _clearChat,
              icon: _clearing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brandOrange))
          : _messages.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'Vero360 Team will message you here about shipping, '
                      'receiving parcels, and order tips.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final msg = _messages[i];
                    final action = _actionFor(msg);
                    return _TeamBubble(
                      message: msg,
                      ctaLabel: _ctaLabel(action),
                      onCta: () => _openAction(msg),
                    );
                  },
                ),
    );
  }
}

class _TeamMessage {
  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool read;
  final Map<String, dynamic>? payload;

  const _TeamMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.payload,
  });
}

class _TeamBubble extends StatelessWidget {
  final _TeamMessage message;
  final String ctaLabel;
  final VoidCallback onCta;

  const _TeamBubble({
    required this.message,
    required this.ctaLabel,
    required this.onCta,
  });

  static const _brandOrange = Color(0xFFFF8A00);

  String _timeLabel(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    return DateFormat('HH:mm').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final showTitle = message.title.trim().isNotEmpty &&
        message.title.trim().toLowerCase() != 'vero360 team';

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showTitle) ...[
                Text(
                  message.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: _brandOrange,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                message.body,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.35,
                  color: Color(0xFF1F2937),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onCta,
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    ctaLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _timeLabel(message.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
