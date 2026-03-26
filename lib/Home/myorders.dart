import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/delivery_proof_service.dart';
import 'package:vero360_app/GernalServices/order_escrow_service.dart';
import 'package:vero360_app/GernalServices/merchant_phone_resolver.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace.service.dart';
import 'package:vero360_app/utils/app_wallet_pin.dart';
import 'package:vero360_app/utils/merchant_contact_display.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:path_provider/path_provider.dart';

class OrdersPage extends StatefulWidget {
  final String? initialOrderId;
  final String? initialOrderNumber;
  final String? initialStatus;

  const OrdersPage({
    super.key,
    this.initialOrderId,
    this.initialOrderNumber,
    this.initialStatus,
  });

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _TrackingWebViewPage extends StatefulWidget {
  final String url;
  final String title;
  const _TrackingWebViewPage({required this.url, required this.title});

  @override
  State<_TrackingWebViewPage> createState() => _TrackingWebViewPageState();
}

class _TrackingWebViewPageState extends State<_TrackingWebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onWebResourceError: (_) => setState(() => _loading = false),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFFFF8A00),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

class _ProofViewerPage extends StatelessWidget {
  /// Local file path or `https://` image URL from Firebase Storage.
  final String pathOrUrl;
  const _ProofViewerPage({required this.pathOrUrl});

  @override
  Widget build(BuildContext context) {
    final net = pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Proof'),
        backgroundColor: const Color(0xFFFF8A00),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: net
              ? Image.network(
                  pathOrUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    );
                  },
                  errorBuilder: (_, __, ___) =>
                      const Text('Could not load proof image'),
                )
              : Image.file(
                  File(pathOrUrl),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Text('Could not load proof image'),
                ),
        ),
      ),
    );
  }
}

class _OrdersPageState extends State<OrdersPage> with SingleTickerProviderStateMixin {
  final _svc = OrderService();
  final Color _brand = const Color(0xFFFF8A00);
  final _money = NumberFormat.currency(symbol: 'MK ', decimalDigits: 0);
  final _date = DateFormat('dd MMM yyyy, HH:mm');
  final _dateSearch = DateFormat('dd MMM yyyy');
  final _dateSearchAlt = DateFormat('yyyy-MM-dd');

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late TabController _tab;
  // Must match the visual tab order (Confirmed, Pending, Delivered, Cancelled)
  final List<OrderStatus> _statuses = const [
    OrderStatus.confirmed,
    OrderStatus.pending,
    OrderStatus.delivered,
    OrderStatus.cancelled,
  ];

  /// Single future: fetch all orders once; filter by status in each tab.
  /// Backend may not support ?status=, so we filter client-side.
  late Future<List<OrderItem>> _ordersFuture;

  // Backup path: when we see confirmed + paid marketplace orders that expose
  // itemSqlId, mark those listings as sold so they disappear from shelves.
  final MarketplaceService _marketplaceService = MarketplaceService();
  final Set<String> _syncedSoldOrders = <String>{};
  String? _focusOrderId;
  String? _focusOrderNumber;
  final Map<String, String> _shippingByOrderId = {};
  final Map<String, Map<String, String>> _deliveryMetaByOrderId = {};
  /// Firestore `order_escrow` snapshot per order (marketplace payout hold).
  final Map<String, OrderEscrowSnapshot?> _escrowByOrderId = {};
  /// Merchant phones from dashboard source (SharedPreferences + Firestore), keyed by order id.
  final Map<String, String> _merchantPhoneByOrderId = {};

  static const String _shippingPrefsKey = 'order_shipping_method_v1';
  static const String _deliveryMetaPrefsKey = 'order_delivery_meta_v1';
  static const String _ankoloTrackingUrl = 'https://ankolo.com/track-parcel';
  static const String _smartTrackingUrl = 'https://tracking.smartdeliveriesmw.com/';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _statuses.length, vsync: this);
    _focusOrderId = widget.initialOrderId?.trim();
    _focusOrderNumber = widget.initialOrderNumber?.trim();
    final s = (widget.initialStatus ?? '').trim().toLowerCase();
    final idx = _statuses.indexWhere((v) => _statusLabel(v).toLowerCase() == s);
    if (idx >= 0) _tab.index = idx;
    _ordersFuture = _svc.getMyOrders();
    unawaited(_bootstrapOrders());
  }

  Future<void> _bootstrapOrders() async {
    await _loadShippingPrefs();
    await _loadDeliveryMetaPrefs();
    if (!mounted) return;
    setState(() {
      _ordersFuture = _fetchOrdersWithProofs();
    });
  }

  Future<List<OrderItem>> _fetchOrdersWithProofs() async {
    final list = await _svc.getMyOrders();
    if (!mounted) return list;
    await _hydrateFirestoreDelivery(list);
    await _hydrateEscrow(list);
    await _hydrateMerchantPhones(list);
    return list;
  }

  /// Loads merchant phones from same source as merchant dashboard:
  /// SharedPreferences 'phone' for current merchant, Firestore users/{uid} for others.
  Future<void> _hydrateMerchantPhones(List<OrderItem> orders) async {
    if (orders.isEmpty) return;
    try {
      final map = await MerchantPhoneResolver.resolveForOrders(orders);
      if (!mounted) return;
      setState(() {
        _merchantPhoneByOrderId
          ..clear()
          ..addAll(map);
      });
    } catch (_) {}
  }

  /// Loads escrow state, repairs delivery timestamps, auto-releases after 5 days.
  Future<void> _hydrateEscrow(List<OrderItem> orders) async {
    if (orders.isEmpty) return;
    try {
      final candidates = orders
          .where((o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus == PaymentStatus.paid)
          .toList();
      if (candidates.isEmpty) return;

      for (final o in candidates) {
        await OrderEscrowService.repairBuyerUidIfNeeded(o);
        await OrderEscrowService.repairDeliveredTimestampIfNeeded(o);
      }

      var map = await OrderEscrowService.fetchEscrowForOrdersResolved(candidates);

      for (final o in candidates) {
        final esc = map[o.id];
        if (esc == null || !esc.isHeld) continue;
        if (esc.deliveredAt == null || esc.releaseDueAt == null) continue;
        if (DateTime.now().isBefore(esc.releaseDueAt!)) continue;
        try {
          await OrderEscrowService.releaseFunds(
            orderId: o.id,
            buyerConfirmed: false,
          );
          map[o.id] = await OrderEscrowService.fetchEscrow(o.id);
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        for (final e in map.entries) {
          _escrowByOrderId[e.key] = e.value;
        }
      });
    } catch (_) {}
  }

  bool _buyerMatchesEscrow(OrderItem o, OrderEscrowSnapshot e, String myUid) {
    if (myUid.isEmpty) return false;
    final bu = e.buyerUid.trim();
    final cust = (o.customerUid ?? '').trim();
    if (bu.isNotEmpty) return bu == myUid;
    return cust.isNotEmpty && cust == myUid;
  }

  bool _merchantMatchesEscrow(OrderItem o, OrderEscrowSnapshot e, String myUid) {
    if (myUid.isEmpty) return false;
    final mu = e.merchantUid.trim();
    final om = (o.merchantUid ?? '').trim();
    if (mu.isNotEmpty) return mu == myUid;
    return om.isNotEmpty && om == myUid;
  }

  Future<void> _confirmParcelReceived(OrderItem o) async {
    await OrderEscrowService.repairBuyerUidIfNeeded(o);
    final esc = await OrderEscrowService.fetchEscrow(o.id);
    if (!mounted) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (esc == null ||
        !esc.isHeld ||
        !_buyerMatchesEscrow(o, esc, myUid)) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Only the buyer can confirm receipt for this order.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    final ok = await AppWalletPin.verifyParcelReceipt(context);
    if (!mounted) return;
    if (!ok) return;
    try {
      await OrderEscrowService.releaseFunds(orderId: o.id, buyerConfirmed: true);
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Payment sent to merchant',
        isSuccess: true,
        errorMessage: '',
      );
      await _reloadCurrent();
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not release payment',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  Widget _parcelEscrowSection(OrderItem o) {
    final esc = _escrowByOrderId[o.id];
    if (esc == null) return const SizedBox.shrink();

    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isBuyer = _buyerMatchesEscrow(o, esc, myUid);
    final isMerchantParty =
        _merchantMatchesEscrow(o, esc, myUid) && !isBuyer;

    if (esc.isReleased) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Payment released to merchant wallet',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ),
              ],
            ),
            if (esc.releasedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 28),
                child: Text(
                  _date.format(esc.releasedAt!.toLocal()),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B778C)),
                ),
              ),
          ],
        ),
      );
    }

    if (!esc.isHeld) return const SizedBox.shrink();

    final waitingMerchant = esc.deliveredAt == null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _brand.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Parcel & payment',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF222222),
            ),
          ),
          const SizedBox(height: 6),
          if (waitingMerchant)
            Text(
              isMerchantParty
                  ? 'Payment is held until you send shipment proof (To ship). The buyer confirms receipt after delivery.'
                  : 'Payment is held until the merchant sends shipment proof. '
                      'Then you can confirm receipt here to release funds to their wallet.',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B778C),
                height: 1.35,
              ),
            )
          else if (isBuyer) ...[
            Text(
              [
                if (esc.releaseDueAt != null)
                  'If you do not confirm, payment is sent to the merchant on '
                      '${_date.format(esc.releaseDueAt!.toLocal())}. ',
                'You’ll confirm with Face ID, fingerprint, or PIN.',
              ].join(),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B778C),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _confirmParcelReceived(o),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('I received this parcel'),
              ),
            ),
          ] else if (isMerchantParty)
            const Text(
              'Waiting for the buyer to confirm receipt so your payout can be released.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B778C),
                height: 1.35,
              ),
            )
          else
            const Text(
              'Payment is held. Sign in as the buyer account that placed this order to see '
              '“I received this parcel”, or pull to refresh.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B778C),
                height: 1.35,
              ),
            ),
        ],
      ),
    );
  }

  /// Merges Firestore delivery proof + courier (works for buyer on any device).
  Future<void> _hydrateFirestoreDelivery(List<OrderItem> orders) async {
    if (orders.isEmpty) return;
    try {
      final ids = orders.map((o) => o.id).toList();
      final remote = await DeliveryProofService.getDeliveryMetadata(ids);
      if (!mounted) return;
      setState(() {
        for (final e in remote.entries) {
          final id = e.key;
          final patch = e.value;
          final prev = Map<String, String>.from(_deliveryMetaByOrderId[id] ?? {});
          for (final pe in patch.entries) {
            if (pe.value.isNotEmpty) prev[pe.key] = pe.value;
          }
          _deliveryMetaByOrderId[id] = prev;
        }
      });
    } catch (_) {}
  }

  Future<void> _loadShippingPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_shippingPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = <String, String>{};
      for (final e in decoded.entries) {
        final k = e.key.toString().trim();
        final v = e.value.toString().trim().toLowerCase();
        if (k.isEmpty || v.isEmpty) continue;
        map[k] = v;
      }
      if (!mounted) return;
      setState(() {
        _shippingByOrderId
          ..clear()
          ..addAll(map);
      });
    } catch (_) {}
  }

  Future<void> _loadDeliveryMetaPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_deliveryMetaPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = <String, Map<String, String>>{};
      for (final e in decoded.entries) {
        final key = e.key.toString().trim();
        if (key.isEmpty || e.value is! Map) continue;
        final valueMap = Map<String, String>.from(
          (e.value as Map).map(
            (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
          ),
        );
        map[key] = valueMap;
      }
      if (!mounted) return;
      setState(() {
        _deliveryMetaByOrderId
          ..clear()
          ..addAll(map);
      });
    } catch (_) {}
  }

  String? _trackingUrlForOrder(OrderItem o) {
    final method = _resolvedCourierMethod(o);
    if (method == 'ankolo') return _ankoloTrackingUrl;
    if (method == 'smart') return _smartTrackingUrl;
    return null;
  }

  String _resolvedCourierMethod(OrderItem o) {
    final fromPrefs = (_deliveryMetaByOrderId[o.id]?['method'] ??
            _shippingByOrderId[o.id] ??
            '')
        .trim()
        .toLowerCase();
    if (fromPrefs.isNotEmpty) return fromPrefs;
    return _shippingFromOrderDescription(o.description);
  }

  String _shippingFromOrderDescription(String description) {
    final d = description.toLowerCase();
    if (d.contains('[delivery: ankolo]') || d.contains('delivery: ankolo')) {
      return 'ankolo';
    }
    if (d.contains('[delivery: smart]') || d.contains('delivery: smart')) {
      return 'smart';
    }
    if (d.contains('[delivery: speed]') || d.contains('delivery: speed')) {
      return 'speed';
    }
    if (d.contains('[delivery: pickup]') || d.contains('delivery: pickup')) {
      return 'pickup';
    }
    return '';
  }

  String? _proofViewerTarget(OrderItem o) {
    final u = (_deliveryMeta(o)['proofUrl'] ?? '').trim();
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    final p = (_deliveryMeta(o)['proofPath'] ?? '').trim();
    if (p.isNotEmpty && File(p).existsSync()) return p;
    return null;
  }

  Map<String, String> _deliveryMeta(OrderItem o) =>
      _deliveryMetaByOrderId[o.id] ?? const <String, String>{};

  /// Phone from dashboard source (SharedPreferences + Firestore), or safe fallback.
  String _displayMerchantPhone(OrderItem o) {
    final resolved = _merchantPhoneByOrderId[o.id];
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return safeMerchantPhone(o.merchantPhone);
  }

  String _courierLabel(OrderItem o) {
    final method = _resolvedCourierMethod(o);
    switch (method) {
      case 'ankolo':
        return 'Ankolo courier';
      case 'smart':
        return 'Smart courier';
      case 'speed':
        return 'Speed courier';
      case 'pickup':
        return 'Shop pickup';
      case 'cts':
        return 'CTS courier';
      default:
        return 'Courier';
    }
  }

  String _trackingTitle(OrderItem o) {
    final method = _resolvedCourierMethod(o);
    return method == 'ankolo' ? 'Ankolo Courier Tracking' : 'Smart Courier Tracking';
  }

  String _trackingButtonLabel(OrderItem o) {
    final method = _resolvedCourierMethod(o);
    return method == 'ankolo' ? 'Track Ankolo' : 'Track Smart';
  }

  Future<void> _openTrackingInApp({
    required String url,
    required String title,
  }) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TrackingWebViewPage(url: url, title: title),
      ),
    );
  }

  Future<void> _reloadCurrent() async {
    await _loadShippingPrefs();
    await _loadDeliveryMetaPrefs();
    if (!mounted) return;
    setState(() {
      _ordersFuture = _fetchOrdersWithProofs();
    });
    try {
      final orders = await _ordersFuture;
      for (final o in orders) {
        if (o.itemSqlId == null) continue;
        if (o.status != OrderStatus.delivered) continue;
        if (o.paymentStatus != PaymentStatus.paid) continue;
        if (_syncedSoldOrders.contains(o.id)) continue;
        _syncedSoldOrders.add(o.id);
        unawaited(_marketplaceService.markItemSold(o.itemSqlId!));
      }
    } catch (_) {
      // Error shown by FutureBuilder
    }
    if (!mounted) return;
    setState(() {});
  }

  Color _statusColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:   return _brand;
      case OrderStatus.confirmed: return Colors.blueAccent;
      case OrderStatus.delivered: return Colors.green;
      case OrderStatus.cancelled: return Colors.redAccent;
    }
  }

  String _statusLabel(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:   return 'Pending';
      case OrderStatus.confirmed: return 'Confirmed';
      case OrderStatus.delivered: return 'Delivered';
      case OrderStatus.cancelled: return 'Cancelled';
    }
  }

  Color _paymentColor(PaymentStatus p) {
    switch (p) {
      case PaymentStatus.paid:    return Colors.green;
      case PaymentStatus.pending: return Colors.orange;
      case PaymentStatus.unpaid:  return Colors.redAccent;
    }
  }

  String _paymentLabel(PaymentStatus p) {
    switch (p) {
      case PaymentStatus.paid:    return 'PAID';
      case PaymentStatus.pending: return 'PENDING';
      case PaymentStatus.unpaid:  return 'UNPAID';
    }
  }

  Widget _chip(Color c, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: .35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: c.withValues(alpha: .95),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _cancel(OrderItem o) async {
    try {
      await _svc.cancelOrMarkCancelled(o.id);
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Order cancelled', isSuccess: true, errorMessage: '');
      await _reloadCurrent();
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Cancel failed', isSuccess: false, errorMessage: e.toString());
    }
  }

  Future<void> _downloadOrder(OrderItem o) async {
    try {
      // Prefer the public Downloads folder on the phone
      final dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final safeOrderNo =
          o.orderNumber.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/order_$safeOrderNo.txt');

      final buf = StringBuffer()
        ..writeln('Order details')
        ..writeln('-----------------------------')
        ..writeln('Order number: ${o.orderNumber}')
        ..writeln('Order ID: ${o.id}')
        ..writeln('Date: ${o.orderDate != null ? _date.format(o.orderDate!.toLocal()) : '-'}')
        ..writeln('Status: ${_statusLabel(o.status)}')
        ..writeln('Payment: ${_paymentLabel(o.paymentStatus)}')
        ..writeln('Item: ${o.itemName}')
        ..writeln('Quantity: ${o.quantity}')
        ..writeln('Price (each): ${_money.format(o.price)}')
        ..writeln('Total: ${_money.format(o.total)}')
        ..writeln('Category: ${o.category.toString().split('.').last}')
        ..writeln()
        ..writeln('Merchant: ${o.merchantName ?? 'Merchant'}')
        ..writeln('Merchant phone: ${_displayMerchantPhone(o)}')
        ..writeln()
        ..writeln('Address city: ${o.addressCity ?? '-'}')
        ..writeln('Address description: ${o.addressDescription ?? '-'}');

      await file.writeAsString(buf.toString());

      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Order saved to ${file.path}',
        isSuccess: true,
        errorMessage: '',
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Failed to save order',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  Widget _infoRow({required IconData icon, required String text, String? trailing}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6B778C)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFF6B778C)),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(trailing, style: const TextStyle(color: Color(0xFF6B778C), fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }

  Widget _orderCard(OrderItem o, {bool highlighted = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: highlighted
            ? Border.all(color: _brand.withValues(alpha: 0.6), width: 1.6)
            : null,
        boxShadow: const [
          BoxShadow(
            blurRadius: 22,
            spreadRadius: -8,
            offset: Offset(0, 14),
            color: Color(0x1A000000),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 82,
              height: 82,
              child: o.itemImage.isEmpty
                  ? Container(
                      color: const Color(0xFFF1F2F6),
                      child: const Icon(Icons.image_outlined, color: Colors.grey),
                    )
                  : Image.network(o.itemImage, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // First line: name + chips
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.itemName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF222222),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Order: ${o.orderNumber}',
                                  style: const TextStyle(
                                    color: Color(0xFF6B778C),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18, color: Color(0xFF6B778C)),
                                tooltip: 'Copy order number',
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: o.orderNumber));
                                  if (!mounted) return;
                                  ToastHelper.showCustomToast(
                                    context,
                                    'Order number copied',
                                    isSuccess: true,
                                    errorMessage: '',
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _chip(_statusColor(o.status), _statusLabel(o.status)),
                        const SizedBox(height: 6),
                        _chip(_paymentColor(o.paymentStatus), _paymentLabel(o.paymentStatus)),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                // Merchant
                _infoRow(
                  icon: Icons.store_mall_directory_outlined,
                  text:
                      '${o.merchantName ?? 'Merchant'}  •  ${_displayMerchantPhone(o)}',
                  trailing: (o.merchantAvgRating != null) ? '⭐ ${o.merchantAvgRating!.toStringAsFixed(1)}' : null,
                ),

                const SizedBox(height: 6),
                // Address
                _infoRow(
                  icon: Icons.location_on_outlined,
                  text: [
                    if ((o.addressCity ?? '').isNotEmpty) o.addressCity,
                    if ((o.addressDescription ?? '').isNotEmpty) o.addressDescription,
                  ].whereType<String>().join(' — ').trim().isEmpty
                      ? 'No address'
                      : [
                          if ((o.addressCity ?? '').isNotEmpty) o.addressCity,
                          if ((o.addressDescription ?? '').isNotEmpty) o.addressDescription,
                        ].whereType<String>().join(' — '),
                ),

                const SizedBox(height: 6),
                if (o.orderDate != null)
                  _infoRow(
                    icon: Icons.schedule_outlined,
                    text: _date.format(o.orderDate!.toLocal()),
                  ),

                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${_money.format(o.price)}  ×  ${o.quantity}',
                      style: const TextStyle(
                        color: Color(0xFF222222),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _money.format(o.total),
                      style: TextStyle(
                        color: _brand,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                // Use Wrap so buttons flow to the next line on small screens,
                // avoiding horizontal overflow while keeping spacing consistent.
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: BorderSide(color: Colors.black12.withValues(alpha: .4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _reloadCurrent(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: BorderSide(color: Colors.black12.withValues(alpha: .4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _downloadOrder(o),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download'),
                    ),
                    if (o.status == OrderStatus.delivered &&
                        _trackingUrlForOrder(o) != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _brand,
                          side: BorderSide(color: _brand.withValues(alpha: .45)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final url = _trackingUrlForOrder(o);
                          if (url == null) return;
                          await _openTrackingInApp(
                            url: url,
                            title: _trackingTitle(o),
                          );
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: Text(_trackingButtonLabel(o)),
                      ),
                    if (o.status == OrderStatus.delivered &&
                        _trackingUrlForOrder(o) == null &&
                        _courierLabel(o) != 'Courier')
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: BorderSide(color: Colors.black12.withValues(alpha: .4)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: null,
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: Text(_courierLabel(o)),
                      ),
                    if (o.status == OrderStatus.delivered &&
                        _proofViewerTarget(o) != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _brand,
                          side: BorderSide(color: _brand.withValues(alpha: .45)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final target = _proofViewerTarget(o);
                          if (target == null || target.isEmpty) return;
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _ProofViewerPage(pathOrUrl: target),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('View proof'),
                      ),
                    if (o.status == OrderStatus.pending)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _brand,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _cancel(o),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel'),
                      ),
                  ],
                ),
                if (o.status == OrderStatus.delivered &&
                    o.paymentStatus == PaymentStatus.paid)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _parcelEscrowSection(o),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBody(OrderStatus s) {
    return RefreshIndicator(
      onRefresh: _reloadCurrent,
      child: FutureBuilder<List<OrderItem>>(
        future: _ordersFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Error: ${snap.error}', textAlign: TextAlign.center),
                  ),
                ),
              ],
            );
          }
          final all = snap.data ?? const <OrderItem>[];
          final byStatus = all.where((o) => o.status == s).toList();
          final items = byStatus
              .where((o) => _orderMatchesSearch(o, _searchQuery))
              .toList();
          final focusId = _focusOrderId;
          final focusNo = _focusOrderNumber;
          if ((focusId != null && focusId.isNotEmpty) ||
              (focusNo != null && focusNo.isNotEmpty)) {
            items.sort((a, b) {
              final aHit = (focusId != null && a.id == focusId) ||
                  (focusNo != null &&
                      focusNo.isNotEmpty &&
                      a.orderNumber == focusNo);
              final bHit = (focusId != null && b.id == focusId) ||
                  (focusNo != null &&
                      focusNo.isNotEmpty &&
                      b.orderNumber == focusNo);
              if (aHit == bHit) return 0;
              return aHit ? -1 : 1;
            });
          }
          if (items.isEmpty) {
            return ListView(
              children: [
                const SizedBox(height: 90),
                Center(
                  child: Text(
                    _searchQuery.trim().isEmpty
                        ? 'No orders in this status'
                        : 'No orders match your search',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final o = items[i];
              final highlighted = (focusId != null && o.id == focusId) ||
                  (focusNo != null &&
                      focusNo.isNotEmpty &&
                      o.orderNumber == focusNo);
              return _orderCard(o, highlighted: highlighted);
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tab.dispose();
    super.dispose();
  }

  bool _orderMatchesSearch(OrderItem o, String q) {
    if (q.trim().isEmpty) return true;
    final lower = q.trim().toLowerCase();
    if (o.orderNumber.toLowerCase().contains(lower)) return true;
    if (o.orderDate != null) {
      final d = o.orderDate!.toLocal();
      if (_dateSearch.format(d).toLowerCase().contains(lower)) return true;
      if (_dateSearchAlt.format(d).contains(lower)) return true;
      if (_date.format(d).toLowerCase().contains(lower)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF222222),
        title: const Text('My Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh orders',
            onPressed: _reloadCurrent,
          ),
        ],
        centerTitle: true,
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: _brand,
          unselectedLabelColor: const Color(0xFF6B778C),
          indicatorColor: _brand,
          tabs: const [
             Tab(text: 'Confirmed'),
            Tab(text: 'Pending'),
            Tab(text: 'Delivered'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search by order number or date...',
                hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF6B778C)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: _statuses.map(_tabBody).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
