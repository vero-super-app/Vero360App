import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/GeneralPages/Toreceive.dart';
import 'package:vero360_app/GeneralPages/ToRefund.dart';
import 'package:vero360_app/GeneralPages/Toship.dart';
import 'package:vero360_app/GernalServices/order_escrow_service.dart';
import 'package:vero360_app/GernalServices/order_party_notification_service.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/accomodation_mainpage.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart'
    as market;
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace.service.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/Marketplace_detailsPage.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/main_marketPlace.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/food_my_orders_page.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/verocourier.dart';
import 'package:vero360_app/wallet/merchant_wallet_page.dart';
import 'package:vero360_app/utils/app_update_checker.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  marketplaceListing,
  merchantListings,
  refunds,
  accommodation,
  courier,
  wallet,
  appUpdate,
  none,
}

class _VeroTeamChatPageState extends State<VeroTeamChatPage> {
  static const _brandOrange = Color(0xFFFF8A00);
  static const _ink = Color(0xFF101010);
  static const _bg = Color(0xFFECE5DD);
  static const _broadcastsCollection = 'vero_team_broadcasts';
  static const _clearedBroadcastsKey = 'vero_team_broadcasts_cleared_at_ms';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _personalSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _broadcastSub;
  List<_TeamMessage> _personal = const [];
  List<_TeamMessage> _broadcasts = const [];
  List<_TeamMessage> _messages = const [];
  bool _loading = true;
  bool _markedRead = false;
  bool _clearing = false;
  int _clearedBroadcastsBeforeMs = 0;
  final Set<String> _hidingBuyerShipNudges = {};

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _personalSub?.cancel();
    _broadcastSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _clearedBroadcastsBeforeMs =
          prefs.getInt(_clearedBroadcastsKey) ?? 0;
    } catch (_) {}
    _listen();
  }

  void _recompute() {
    final items = <_TeamMessage>[..._personal, ..._broadcasts];
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
    if (!_markedRead) {
      final unread = items.where((m) => !m.read && !m.isBroadcast).toList();
      if (unread.isNotEmpty) {
        _markedRead = true;
        unawaited(_markAllRead(unread.map((m) => m.id)));
      }
    }
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

    _personalSub?.cancel();
    _broadcastSub?.cancel();

    _personalSub = FirebaseFirestore.instance
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
      _personal = items;
      _recompute();
      unawaited(_hideShipNudgesAddressedToBuyer(items));
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });

    _broadcastSub = FirebaseFirestore.instance
        .collection(_broadcastsCollection)
        .limit(50)
        .snapshots()
        .listen((snap) {
      final items = <_TeamMessage>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final title = (data['title'] ?? '').toString().trim();
        final body = (data['body'] ?? '').toString().trim();
        if (body.isEmpty && title.isEmpty) continue;

        DateTime? at;
        final rawAt = data['createdAt'];
        if (rawAt is Timestamp) at = rawAt.toDate();
        if (at != null &&
            at.millisecondsSinceEpoch <= _clearedBroadcastsBeforeMs) {
          continue;
        }

        final kind = (data['kind'] ?? 'general').toString().trim().toLowerCase();
        items.add(
          _TeamMessage(
            id: 'bcast_${doc.id}',
            title: title.isEmpty ? VeroTeamChatPage.displayName : title,
            body: body,
            createdAt: at,
            read: true,
            isBroadcast: true,
            payload: {
              'type': 'vero_team',
              'kind': kind,
              'broadcastId': doc.id,
            },
          ),
        );
      }
      _broadcasts = items;
      _recompute();
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _markAllRead(Iterable<String> ids) async {
    await _batchUpdate(ids, {'read': true, 'consumed': true});
  }

  bool _isMerchantShipNudge(_TeamMessage m) {
    final type = (m.payload?['type'] ?? '').toString().toLowerCase();
    final text = '${m.title} ${m.body}'.toLowerCase();
    if (type == 'ship_reminder') return true;
    return text.contains('please ship') || text.contains('reminded you to ship');
  }

  /// Older builds wrote "please ship" onto the buyer's uid. Drop those.
  Future<void> _hideShipNudgesAddressedToBuyer(List<_TeamMessage> items) async {
    final me = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (me.isEmpty) return;
    final suspects = items.where((m) {
      if (m.isBroadcast || _hidingBuyerShipNudges.contains(m.id)) return false;
      return _isMerchantShipNudge(m);
    }).toList();
    if (suspects.isEmpty) return;

    final hideIds = <String>[];
    for (final m in suspects) {
      final orderId = (m.payload?['orderId'] ?? '').toString().trim();
      if (orderId.isEmpty) continue;
      _hidingBuyerShipNudges.add(m.id);
      try {
        final esc = await OrderEscrowService.fetchEscrow(orderId);
        if (esc == null) continue;
        final buyer = esc.buyerUid.trim();
        final seller = esc.merchantUid.trim();
        if (buyer == me && seller != me) hideIds.add(m.id);
      } catch (_) {}
    }
    if (hideIds.isEmpty || !mounted) return;
    final hide = hideIds.toSet();
    _personal = _personal.where((m) => !hide.contains(m.id)).toList();
    _recompute();
    await _batchUpdate(hideIds, {
      'cleared': true,
      'read': true,
      'consumed': true,
    });
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
    final personalIds =
        _messages.where((m) => !m.isBroadcast).map((m) => m.id).toList();
    if (personalIds.isNotEmpty) {
      await _batchUpdate(personalIds, {
        'cleared': true,
        'read': true,
        'consumed': true,
      });
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_clearedBroadcastsKey, nowMs);
      _clearedBroadcastsBeforeMs = nowMs;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _personal = const [];
        _broadcasts = const [];
        _messages = const [];
        _clearing = false;
      });
    }
  }

  /// Resolve destination from payload + message text (never default to My Orders).
  _TeamAction _actionFor(_TeamMessage msg) {
    final payload = msg.payload ?? const <String, dynamic>{};
    final kind = (payload['kind'] ?? '').toString().trim().toLowerCase();
    final typeEarly = (payload['type'] ?? '').toString().trim().toLowerCase();
    if (msg.isBroadcast || typeEarly == 'vero_team') {
      if (kind == 'app_update') return _TeamAction.appUpdate;
      return _TeamAction.none;
    }

    final actionHint =
        (payload['action'] ?? '').toString().trim().toLowerCase();
    if (actionHint == 'send_parcel' || actionHint == 'send') {
      return _TeamAction.sendParcel;
    }
    if (actionHint == 'received_parcel' || actionHint == 'received') {
      return _TeamAction.receivedParcel;
    }
    if (actionHint == 'view_listing' ||
        actionHint == 'marketplace' ||
        actionHint == 'open_listing') {
      return _TeamAction.marketplaceListing;
    }
    if (actionHint == 'manage_shelf' || actionHint == 'shelf') {
      return _TeamAction.shelf;
    }

    final route = (payload[NotificationStore.kPayloadBadgeRoute] ??
            payload['badgeRoute'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    final type = typeEarly;
    final status = (payload['status'] ?? '').toString().trim().toLowerCase();
    final text = '${msg.title} ${msg.body}'.toLowerCase();

    // Marketplace listing approved / rejected (Cloud Function notifyMerchant).
    if (type == 'marketplace_moderation' ||
        type == 'marketplace_digest' ||
        type == 'marketplace' ||
        type == 'new_product') {
      if (status == 'rejected' ||
          text.contains('not approved') ||
          text.contains('rejected')) {
        return _TeamAction.merchantListings;
      }
      return _TeamAction.marketplaceListing;
    }

    // Text fallback when payload type is missing but copy is clearly listing-live.
    if (text.contains('listing is live') ||
        text.contains('is now visible to buyers') ||
        text.contains('has been approved') ||
        text.contains('approved and is now') ||
        text.contains('just listed') ||
        text.contains('vero marketplace')) {
      return _TeamAction.marketplaceListing;
    }

    if (type == 'out_of_stock_shelf' ||
        route == NotificationStore.kBadgePostArrival ||
        text.contains('remove it from your shelf') ||
        text.contains('out of stock') ||
        text.contains('sold out')) {
      return _TeamAction.shelf;
    }

    if (type == 'food_order' ||
        type == 'food_order_placed' ||
        type == 'new_food_order' ||
        text.contains('food order') ||
        text.contains('has ordered')) {
      return _TeamAction.foodOrders;
    }

    if (type == 'refund_request' ||
        type == 'refund_update' ||
        route == NotificationStore.kBadgeRefund ||
        text.contains('refund')) {
      return _TeamAction.refunds;
    }

    if (type == 'accommodation_booking' ||
        text.contains('stay booking') ||
        text.contains('new booking')) {
      return _TeamAction.accommodation;
    }

    if (type == 'courier_status' ||
        text.contains('vero courier') ||
        text.contains('tracking') ||
        text.contains('parcel accepted') ||
        text.contains('courier is coming')) {
      return _TeamAction.courier;
    }

    if (type == 'order_escrow_released' ||
        text.contains('funds have been transferred') ||
        text.contains('escrow funds released') ||
        text.contains('buyer confirmed receipt')) {
      return _TeamAction.wallet;
    }

    // Explicit send / ship routes (do not use role alone — too broad).
    if (route == NotificationStore.kBadgeShipped ||
        type == 'ship_reminder' ||
        text.contains('send parcel') ||
        text.contains('to ship') ||
        text.contains('upload courier') ||
        text.contains('pack and ship') ||
        text.contains('reminded you to ship') ||
        text.contains('please ship') ||
        text.contains('open send parcel')) {
      return _TeamAction.sendParcel;
    }

    // Explicit received routes.
    if (route == NotificationStore.kBadgeReceived ||
        type == 'order_update' ||
        type == 'order_completed' ||
        (type == 'order_team_tip' &&
            (payload['role']?.toString().toLowerCase() == 'buyer')) ||
        text.contains('received parcel') ||
        text.contains('confirm receipt') ||
        text.contains('has been shipped') ||
        text.contains('confirm when') ||
        text.contains('open received parcel')) {
      return _TeamAction.receivedParcel;
    }

    if (type == 'order_team_tip' &&
        (payload['role']?.toString().toLowerCase() == 'merchant')) {
      return _TeamAction.sendParcel;
    }

    // Unknown tips: stay on received track only for buyer-ish order copy.
    if (text.contains('order') || text.contains('parcel')) {
      return _TeamAction.receivedParcel;
    }

    // Last resort for merchant ops tips without clear copy.
    return _TeamAction.merchantListings;
  }

  String? _ctaLabel(_TeamAction action) {
    switch (action) {
      case _TeamAction.sendParcel:
        return 'Open Send Parcel';
      case _TeamAction.receivedParcel:
        return 'Open Received Parcel';
      case _TeamAction.foodOrders:
        return 'Open Food Orders';
      case _TeamAction.shelf:
        return 'Manage shelf';
      case _TeamAction.marketplaceListing:
        return 'View listing';
      case _TeamAction.merchantListings:
        return 'Open my listings';
      case _TeamAction.refunds:
        return 'Open refunds';
      case _TeamAction.accommodation:
        return 'Open stay bookings';
      case _TeamAction.courier:
        return 'Open Vero Courier';
      case _TeamAction.wallet:
        return 'Open wallet';
      case _TeamAction.appUpdate:
        return 'Update app';
      case _TeamAction.none:
        return null;
    }
  }

  Future<void> _openAction(_TeamMessage msg) async {
    final action = _actionFor(msg);
    if (action == _TeamAction.none) return;
    if (action == _TeamAction.appUpdate) {
      await AppUpdateChecker.openStoreForThisPlatform();
      return;
    }
    final payload = msg.payload ?? const <String, dynamic>{};

    // Clear this tip after the user follows it.
    if (!msg.isBroadcast) {
      unawaited(_batchUpdate([msg.id], {
        'cleared': true,
        'read': true,
        'consumed': true,
      }));
    }

    if (!mounted) return;

    switch (action) {
      case _TeamAction.none:
      case _TeamAction.appUpdate:
        return;
      case _TeamAction.sendParcel:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ToShipPage()),
        );
        return;
      case _TeamAction.receivedParcel:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DeliveredOrdersPage()),
        );
        return;
      case _TeamAction.foodOrders:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FoodMyOrdersPage()),
        );
        return;
      case _TeamAction.shelf:
        final sqlRaw = payload['listingSqlId'] ??
            payload['sqlItemId'] ??
            payload['itemId'];
        final sql = sqlRaw is num
            ? sqlRaw.toInt()
            : int.tryParse('${sqlRaw ?? ''}');
        final itemName = (payload['itemName'] ?? payload['name'] ?? '')
            .toString()
            .trim();
        final firestoreId = (payload['marketplaceItemId'] ??
                payload['firestoreId'] ??
                '')
            .toString()
            .trim();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _TeamShelfItemPage(
              listingSqlId: (sql != null && sql > 0) ? sql : null,
              itemName: itemName,
              firestoreId: firestoreId,
            ),
          ),
        );
        return;
      case _TeamAction.merchantListings:
        final email =
            (FirebaseAuth.instance.currentUser?.email ?? '').trim();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MarketplaceMerchantDashboard(
              email: email,
              merchantUid: FirebaseAuth.instance.currentUser?.uid,
              onBackToHomeTab: () {},
            ),
          ),
        );
        return;
      case _TeamAction.marketplaceListing:
        final itemId = (payload['marketplaceItemId'] ??
                payload['itemId'] ??
                payload['id'] ??
                '')
            .toString()
            .trim();
        // If this tip was a rejection (or listing is no longer public), send
        // the poster to manage listings instead of the public product page.
        final status =
            (payload['status'] ?? '').toString().trim().toLowerCase();
        final text = '${msg.title} ${msg.body}'.toLowerCase();
        if (status == 'rejected' ||
            text.contains('not approved') ||
            text.contains('rejected')) {
          final email =
              (FirebaseAuth.instance.currentUser?.email ?? '').trim();
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MarketplaceMerchantDashboard(
                email: email,
                merchantUid: FirebaseAuth.instance.currentUser?.uid,
                onBackToHomeTab: () {},
              ),
            ),
          );
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _TeamMarketplaceListingPage(itemId: itemId),
          ),
        );
        return;
      case _TeamAction.refunds:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ToRefundPage()),
        );
        return;
      case _TeamAction.accommodation:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AccommodationMainPage(initialTabIndex: 1),
          ),
        );
        return;
      case _TeamAction.courier:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const VerocourierPage()),
        );
        return;
      case _TeamAction.wallet:
        final user = FirebaseAuth.instance.currentUser;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MerchantWalletPage(
              merchantId: user?.uid ?? '',
              merchantName: (user?.displayName ?? user?.email ?? 'Merchant')
                  .trim(),
            ),
          ),
        );
        return;
    }
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
                    'Tips · orders, listings & more',
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
                      'Vero360 Team will message you here about updates, '
                      'shipping, receiving parcels, and order tips.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                )
              : _VeroTeamMessageList(
                  messages: _messages,
                  actionFor: _actionFor,
                  ctaLabel: _ctaLabel,
                  onCta: _openAction,
                ),
    );
  }
}

class _VeroTeamMessageList extends StatefulWidget {
  const _VeroTeamMessageList({
    required this.messages,
    required this.actionFor,
    required this.ctaLabel,
    required this.onCta,
  });

  final List<_TeamMessage> messages;
  final _TeamAction Function(_TeamMessage) actionFor;
  final String? Function(_TeamAction) ctaLabel;
  final void Function(_TeamMessage) onCta;

  @override
  State<_VeroTeamMessageList> createState() => _VeroTeamMessageListState();
}

class _VeroTeamMessageListState extends State<_VeroTeamMessageList> {
  final _scroll = ScrollController();
  bool _didInitialJump = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());
  }

  @override
  void didUpdateWidget(covariant _VeroTeamMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_didInitialJump && widget.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());
    }
  }

  void _jumpBottom() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max > 0) {
      _scroll.jumpTo(max);
      _didInitialJump = true;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
      itemCount: widget.messages.length,
      itemBuilder: (_, i) {
        final msg = widget.messages[i];
        final action = widget.actionFor(msg);
        return _TeamBubble(
          message: msg,
          ctaLabel: widget.ctaLabel(action),
          onCta: () => widget.onCta(msg),
        );
      },
    );
  }
}

class _TeamMessage {
  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool read;
  final bool isBroadcast;
  final Map<String, dynamic>? payload;

  const _TeamMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.isBroadcast = false,
    this.payload,
  });
}

class _TeamBubble extends StatelessWidget {
  final _TeamMessage message;
  final String? ctaLabel;
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
              if ((ctaLabel ?? '').trim().isNotEmpty) ...[
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
                      ctaLabel!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              ],
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

/// Resolves a marketplace listing from a Cloud Function / team alert payload.
class _TeamMarketplaceListingPage extends StatelessWidget {
  const _TeamMarketplaceListingPage({required this.itemId});

  final String itemId;

  Future<market.MarketplaceDetailModel?> _resolve() async {
    final id = itemId.trim();
    if (id.isEmpty) return null;

    final sqlId = int.tryParse(id);
    if (sqlId != null && sqlId > 0) {
      try {
        final item = await MarketplaceService().getItemDetails(sqlId);
        if (item != null) return item;
      } catch (_) {}
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('marketplace_items')
          .doc(id)
          .get();
      if (!doc.exists) return null;
      final data = doc.data() ?? const <String, dynamic>{};
      final review =
          (data['reviewStatus'] ?? '').toString().trim().toLowerCase();
      final inactive = data['isActive'] == false;
      if (review == 'pending' || review == 'rejected' || inactive) {
        // Not public — seller should use manage listings CTA, not product page.
        return null;
      }
      int? sql;
      final rawSql = data['sqlItemId'] ?? data['backendId'] ?? data['itemId'];
      if (rawSql is int) {
        sql = rawSql;
      } else if (rawSql != null) {
        sql = int.tryParse(rawSql.toString());
      }
      double price = 0;
      final p = data['price'];
      if (p is num) {
        price = p.toDouble();
      } else if (p != null) {
        price = double.tryParse(p.toString()) ?? 0;
      }
      DateTime? created;
      final createdRaw = data['createdAt'];
      if (createdRaw is Timestamp) created = createdRaw.toDate();
      List<String> gallery = const [];
      final g = data['galleryUrls'] ?? data['gallery'];
      if (g is List) {
        gallery = g
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      return market.MarketplaceDetailModel(
        id: sql ?? doc.id.hashCode.abs(),
        name: (data['name'] ?? data['title'] ?? data['productName'] ?? 'Item')
            .toString(),
        image: (data['imageUrl'] ?? data['image'] ?? data['photo'] ?? '')
            .toString()
            .trim(),
        price: price,
        description: (data['description'] ?? '').toString(),
        location: (data['location'] ?? '').toString(),
        category: (data['category'] ?? '').toString(),
        gallery: gallery,
        merchantId: (data['merchantId'] ?? '').toString(),
        merchantName: (data['merchantName'] ?? '').toString(),
        sellerUserId: (data['sellerUserId'] ?? '').toString(),
        serviceProviderId: (data['serviceProviderId'] ?? '').toString(),
        serviceType: (data['serviceType'] ?? 'marketplace').toString(),
        firestoreDocId: doc.id,
        createdAt: created,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartServiceProvider.getInstance();
    return FutureBuilder<market.MarketplaceDetailModel?>(
      future: _resolve(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Listing')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final item = snap.data;
        if (item != null) {
          return DetailsPage(item: item, cartService: cart);
        }
        return MarketPage(cartService: cart);
      },
    );
  }
}

class _ShelfListing {
  const _ShelfListing({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.sqlId,
    this.stock,
  });

  final String id;
  final String name;
  final String imageUrl;
  final int? sqlId;
  final int? stock;

  static _ShelfListing fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawSql = data['sqlItemId'] ?? data['backendId'] ?? data['itemId'];
    final sql = rawSql is num ? rawSql.toInt() : int.tryParse('$rawSql');
    final rawStock = data['stockQuantity'] ?? data['quantity'] ?? data['stock'];
    final stock =
        rawStock is num ? rawStock.toInt() : int.tryParse('$rawStock');
    return _ShelfListing(
      id: doc.id,
      name: (data['name'] ?? data['title'] ?? 'Listing').toString().trim(),
      imageUrl: (data['imageUrl'] ?? data['image'] ?? data['photo'] ?? '')
          .toString()
          .trim(),
      sqlId: (sql != null && sql > 0) ? sql : null,
      stock: stock,
    );
  }
}

/// Sold-out shelf tip: open that listing and let the merchant take it down.
class _TeamShelfItemPage extends StatefulWidget {
  const _TeamShelfItemPage({
    this.listingSqlId,
    this.itemName = '',
    this.firestoreId = '',
  });

  final int? listingSqlId;
  final String itemName;
  final String firestoreId;

  @override
  State<_TeamShelfItemPage> createState() => _TeamShelfItemPageState();
}

class _TeamShelfItemPageState extends State<_TeamShelfItemPage> {
  static const _brandOrange = Color(0xFFFF8A00);

  late Future<_ShelfListing?> _future;
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ShelfListing?> _load() async {
    final col = FirebaseFirestore.instance.collection('marketplace_items');
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final docId = widget.firestoreId.trim();
    if (docId.isNotEmpty) {
      final snap = await col.doc(docId).get();
      if (snap.exists) return _ShelfListing.fromDoc(snap);
    }

    final sql = widget.listingSqlId;
    if (sql != null && sql > 0) {
      for (final field in ['sqlItemId', 'itemId', 'backendId']) {
        final q = await col.where(field, isEqualTo: sql).limit(5).get();
        final owned = _ownedDoc(q.docs, uid);
        if (owned != null) return _ShelfListing.fromDoc(owned);
      }
    }

    final name = widget.itemName.trim().toLowerCase();
    if (uid.isEmpty || name.isEmpty) return null;
    final mine = await col.where('merchantId', isEqualTo: uid).limit(40).get();
    for (final d in mine.docs) {
      final n = (d.data()['name'] ?? d.data()['title'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (n == name) return _ShelfListing.fromDoc(d);
    }
    return null;
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _ownedDoc(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String uid,
  ) {
    for (final d in docs) {
      final owner = (d.data()['merchantId'] ?? '').toString().trim();
      if (uid.isEmpty || owner.isEmpty || owner == uid) return d;
    }
    return null;
  }

  Future<void> _remove(_ShelfListing item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from shelf'),
        content: Text(
          'Remove "${item.name}"? Buyers will no longer be able to order it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _removing = true);
    try {
      final sql = item.sqlId ?? widget.listingSqlId;
      if (sql != null && sql > 0) {
        try {
          await MarketplaceService().deleteItem(sql);
        } catch (_) {}
      }
      await FirebaseFirestore.instance
          .collection('marketplace_items')
          .doc(item.id)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed "${item.name}" from your shelf')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _removing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove this item. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.itemName.trim().isEmpty ? 'Listing' : widget.itemName.trim();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4EF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF101010),
        elevation: 0,
        title: const Text(
          'Manage shelf',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: FutureBuilder<_ShelfListing?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: _brandOrange),
            );
          }
          final item = snap.data;
          if (item == null) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Could not find "$title" on your shelf.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _brandOrange,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      final email =
                          (FirebaseAuth.instance.currentUser?.email ?? '')
                              .trim();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => MarketplaceMerchantDashboard(
                            email: email,
                            merchantUid: FirebaseAuth.instance.currentUser?.uid,
                            initialInnerTab: 2,
                            onBackToHomeTab: () {},
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Open my listings',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 1.2,
                  child: item.imageUrl.isEmpty
                      ? const ColoredBox(
                          color: Color(0xFFE8E4DE),
                          child: Icon(Icons.inventory_2_outlined, size: 48),
                        )
                      : Image.network(
                          item.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Color(0xFFE8E4DE),
                            child: Icon(Icons.inventory_2_outlined, size: 48),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                item.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: Color(0xFF101010),
                ),
              ),
              if (item.stock != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Quantity left: ${item.stock}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B6B6B),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'This listing looks sold out. Remove it so buyers cannot order it again.',
                style: TextStyle(height: 1.4, color: Color(0xFF101010)),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC62828),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _removing ? null : () => _remove(item),
                child: Text(
                  _removing ? 'Removing…' : 'Remove from shelf',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
