// address.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/delivery_proof_service.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace.service.dart';
import 'package:vero360_app/utils/merchant_contact_display.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// Simple enum for how the merchant will ship the order.
enum ShippingMethod { cts, speed, ankolo, smart, pickup }

const String _ankoloTrackingUrl = 'https://ankolo.com/track-parcel';
const String _smartTrackingUrl = 'https://tracking.smartdeliveriesmw.com/';
const String _shippingPrefsKey = 'order_shipping_method_v1';
const String _deliveryMetaPrefsKey = 'order_delivery_meta_v1';

class ToShipPage extends StatefulWidget {
  const ToShipPage({super.key});

  @override
  State<ToShipPage> createState() => _ToShipPageState();
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
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

class _ToShipPageState extends State<ToShipPage> {
  final _svc = OrderService();
  final _marketplaceService = MarketplaceService();
  final _money = NumberFormat.currency(symbol: 'MK ', decimalDigits: 0);
  final _date = DateFormat('dd MMM yyyy, HH:mm');
  final Color _brand = const Color(0xFFFF8A00);

  late Future<List<OrderItem>> _ordersFuture;
  final Map<String, ShippingMethod> _shippingForOrder = {};
  final Map<String, Map<String, String>> _deliveryMetaByOrder = {};
  final Map<String, TextEditingController> _trackingCtrl = {};
  final Map<String, XFile?> _proofImage = {};

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadShippingPrefs();
    _loadDeliveryMetaPrefs();
    _ordersFuture = _svc.getMyOrders();
  }

  @override
  void dispose() {
    for (final c in _trackingCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  ShippingMethod _shippingOf(OrderItem o) =>
      _shippingForOrder[o.id] ?? _shippingFromOrderDescription(o.description);

  ShippingMethod _shippingFromOrderDescription(String description) {
    final d = description.toLowerCase();
    if (d.contains('[delivery: ankolo]') || d.contains('delivery: ankolo')) {
      return ShippingMethod.ankolo;
    }
    if (d.contains('[delivery: smart]') || d.contains('delivery: smart')) {
      return ShippingMethod.smart;
    }
    if (d.contains('[delivery: speed]') || d.contains('delivery: speed')) {
      return ShippingMethod.speed;
    }
    if (d.contains('[delivery: pickup]') || d.contains('delivery: pickup')) {
      return ShippingMethod.pickup;
    }
    return ShippingMethod.cts;
  }

  ShippingMethod _shippingFromString(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'speed':
        return ShippingMethod.speed;
      case 'ankolo':
        return ShippingMethod.ankolo;
      case 'smart':
        return ShippingMethod.smart;
      case 'pickup':
        return ShippingMethod.pickup;
      case 'cts':
      default:
        return ShippingMethod.cts;
    }
  }

  String _shippingToString(ShippingMethod m) {
    switch (m) {
      case ShippingMethod.cts:
        return 'cts';
      case ShippingMethod.speed:
        return 'speed';
      case ShippingMethod.ankolo:
        return 'ankolo';
      case ShippingMethod.smart:
        return 'smart';
      case ShippingMethod.pickup:
        return 'pickup';
    }
  }

  Future<void> _loadShippingPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_shippingPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = <String, ShippingMethod>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty) continue;
        map[key] = _shippingFromString(entry.value.toString());
      }
      if (!mounted) return;
      setState(() => _shippingForOrder.addAll(map));
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  Future<void> _saveShippingPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, String>{};
      _shippingForOrder.forEach((k, v) => map[k] = _shippingToString(v));
      await prefs.setString(_shippingPrefsKey, jsonEncode(map));
    } catch (_) {
      // Ignore persistence errors.
    }
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
      setState(() => _deliveryMetaByOrder.addAll(map));
    } catch (_) {}
  }

  /// Persists delivery metadata locally (Firebase proof URL is already stored in Firestore for other users).
  Future<void> _saveDeliveryMeta({
    required String orderId,
    required ShippingMethod method,
    required String tracking,
    required String proofUrl,
  }) async {
    final next = <String, Map<String, String>>{
      ..._deliveryMetaByOrder,
      orderId: {
        'method': _shippingToString(method),
        'tracking': tracking,
        'proofUrl': proofUrl,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    };
    _deliveryMetaByOrder
      ..clear()
      ..addAll(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deliveryMetaPrefsKey, jsonEncode(next));
  }

  String _shippingLabel(ShippingMethod m) {
    switch (m) {
      case ShippingMethod.cts:
        return 'CTS courier';
      case ShippingMethod.speed:
        return 'Speed courier';
      case ShippingMethod.ankolo:
        return 'Ankolo courier';
      case ShippingMethod.smart:
        return 'Smart courier';
      case ShippingMethod.pickup:
        return 'Shop pickup';
    }
  }

  Color _statusColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:
        return _brand;
      case OrderStatus.confirmed:
        return Colors.blueAccent;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.redAccent;
    }
  }

  String _statusLabel(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color _paymentColor(PaymentStatus p) {
    switch (p) {
      case PaymentStatus.paid:
        return Colors.green;
      case PaymentStatus.pending:
        return Colors.orange;
      case PaymentStatus.unpaid:
        return Colors.redAccent;
    }
  }

  String _paymentLabel(PaymentStatus p) {
    switch (p) {
      case PaymentStatus.paid:
        return 'PAID';
      case PaymentStatus.pending:
        return 'PENDING';
      case PaymentStatus.unpaid:
        return 'UNPAID';
    }
  }

  Widget _chip(Color c, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: c.withOpacity(.95),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _pickProof(OrderItem o) async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;
      final picked = await _picker.pickImage(source: source);
      if (picked != null) {
        setState(() {
          _proofImage[o.id] = picked;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Failed to pick image: $e',
        isSuccess: false,
        errorMessage: 'Image error',
      );
    }
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

  Future<void> _openMap(OrderItem o) async {
    final parts = <String>[];
    if ((o.addressCity ?? '').trim().isNotEmpty) {
      parts.add(o.addressCity!.trim());
    }
    if ((o.addressDescription ?? '').trim().isNotEmpty) {
      parts.add(o.addressDescription!.trim());
    }
    final q = parts.isEmpty ? null : parts.join(', ');
    if (q == null) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'No address available for this order',
        isSuccess: false,
        errorMessage: 'No address',
      );
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not open map',
        isSuccess: false,
        errorMessage: 'Map error',
      );
    }
  }

  Future<void> _markShipped(OrderItem o) async {
    if (o.status == OrderStatus.delivered) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Order already delivered.',
        isSuccess: false,
        errorMessage: 'Already delivered',
      );
      return;
    }

    final proof = _proofImage[o.id];
    if (proof == null) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Please select photo evidence before marking as delivered.',
        isSuccess: false,
        errorMessage: 'Proof required',
      );
      return;
    }

    final method = _shippingOf(o);
    final tracking = _trackingCtrl[o.id]?.text.trim();

    try {
      final proofUrl = await DeliveryProofService.uploadProofImage(
        orderId: o.id,
        file: proof,
      );
      await DeliveryProofService.saveProofMetadata(
        orderId: o.id,
        proofUrl: proofUrl,
        courierMethod: _shippingToString(method),
        tracking: tracking ?? '',
      );

      // For now we map "shipped" → delivered in the existing enum.
      await _svc.updateStatus(o.id, OrderStatus.delivered);
      await _markListingSoldIfDelivered(o);
      await _saveDeliveryMeta(
        orderId: o.id,
        method: method,
        tracking: tracking ?? '',
        proofUrl: proofUrl,
      );

      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Marked as shipped via ${_shippingLabel(method)}'
        '${tracking != null && tracking.isNotEmpty ? ' (tracking: $tracking)' : ''}',
        isSuccess: true,
        errorMessage: '',
      );

      setState(() {
        _ordersFuture = _svc.getMyOrders();
      });
    } on AuthRequiredException catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        e.toString(),
        isSuccess: false,
        errorMessage: 'Auth required',
      );
    } on FriendlyApiException catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        e.message,
        isSuccess: false,
        errorMessage: e.debugMessage ?? 'Order update failed',
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not update order: $e',
        isSuccess: false,
        errorMessage: 'Order update failed',
      );
    }
  }

  int? _listingIdFromOrderDescription(String description) {
    final m = RegExp(r'\[ListingId:\s*(\d+)\]', caseSensitive: false)
        .firstMatch(description.trim());
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  Future<void> _markListingSoldIfDelivered(OrderItem o) async {
    final itemId = o.itemSqlId ?? _listingIdFromOrderDescription(o.description);
    if (itemId == null || itemId <= 0) {
      debugPrint(
        '[ToShip] Skipping markItemSold: no listing id (ItemId / [ListingId: n] in description). '
        'Order ${o.id}',
      );
      return;
    }
    try {
      await _marketplaceService.markItemSold(itemId);
    } catch (e, st) {
      // Listing may already be inactive, wrong id, or API 404 — delivery still succeeded.
      debugPrint('[ToShip] markItemSold failed for listing $itemId: $e\n$st');
    }
  }

  Widget _infoRow({required IconData icon, required String text, Widget? trailing}) {
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
          trailing,
        ],
      ],
    );
  }

  Widget _orderCard(OrderItem o) {
    final savedMeta = _deliveryMetaByOrder[o.id] ?? const <String, String>{};
    final tracking = _trackingCtrl.putIfAbsent(
      o.id,
      () => TextEditingController(),
    );
    if (tracking.text.trim().isEmpty && (savedMeta['tracking'] ?? '').isNotEmpty) {
      tracking.text = savedMeta['tracking']!;
    }
    final method = _shippingOf(o);
    final proof = _proofImage[o.id];
    final savedProofExists = (() {
      final u = (savedMeta['proofUrl'] ?? '').trim();
      if (u.startsWith('http://') || u.startsWith('https://')) return true;
      final p = savedMeta['proofPath'] ?? '';
      if (p.isEmpty) return false;
      return File(p).existsSync();
    })();
    final addressText = [
      if ((o.addressCity ?? '').isNotEmpty) o.addressCity,
      if ((o.addressDescription ?? '').isNotEmpty) o.addressDescription,
    ].whereType<String>().join(' — ');
    final hasAddress = addressText.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            blurRadius: 22,
            spreadRadius: -8,
            offset: Offset(0, 14),
            color: Color(0x1A000000),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: o.itemImage.isEmpty
                      ? Container(
                          color: const Color(0xFFF1F2F6),
                          child: const Icon(Icons.image_outlined, color: Colors.grey),
                        )
                      : Image.network(o.itemImage, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.itemName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF222222),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Order: ${o.orderNumber}',
                      style: const TextStyle(
                        color: Color(0xFF6B778C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _chip(_statusColor(o.status), _statusLabel(o.status)),
                        const SizedBox(width: 6),
                        _chip(_paymentColor(o.paymentStatus), _paymentLabel(o.paymentStatus)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow(
            icon: Icons.store_mall_directory_outlined,
            text:
                '${o.merchantName ?? 'Merchant'}  •  ${safeMerchantPhone(o.merchantPhone)}',
          ),
          const SizedBox(height: 6),
          _infoRow(
            icon: Icons.location_on_outlined,
            text: hasAddress
                ? addressText
                : (o.description.toLowerCase().contains('pickup')
                    ? 'Pickup selected (no delivery address)'
                    : 'No delivery address from checkout'),
            trailing: hasAddress
                ? IconButton(
                    icon: const Icon(Icons.map_outlined, size: 20),
                    onPressed: () => _openMap(o),
                    tooltip: 'View on map',
                  )
                : null,
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
                '${_money.format(o.price)} × ${o.quantity}',
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
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<ShippingMethod>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Shipment method',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ShippingMethod.cts,
                      child: Text('CTS courier'),
                    ),
                    DropdownMenuItem(
                      value: ShippingMethod.speed,
                      child: Text('Speed courier'),
                    ),
                    DropdownMenuItem(
                      value: ShippingMethod.ankolo,
                      child: Text('Ankolo courier'),
                    ),
                    DropdownMenuItem(
                      value: ShippingMethod.smart,
                      child: Text('Smart courier'),
                    ),
                    DropdownMenuItem(
                      value: ShippingMethod.pickup,
                      child: Text('Shop pickup'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _shippingForOrder[o.id] = v;
                    });
                    _saveShippingPrefs();
                  },
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () => _pickProof(o),
                icon: Icon(
                  (proof == null && !savedProofExists)
                      ? Icons.add_a_photo_outlined
                      : Icons.check_circle,
                  color: (proof == null && !savedProofExists)
                      ? Colors.grey[700]
                      : Colors.green,
                ),
                tooltip: (proof == null && !savedProofExists)
                    ? 'Upload proof of shipment'
                    : 'Proof selected',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (method == ShippingMethod.ankolo || method == ShippingMethod.smart) ...[
            InkWell(
              onTap: () async {
                final isAnkolo = method == ShippingMethod.ankolo;
                final uri = Uri.parse(isAnkolo ? _ankoloTrackingUrl : _smartTrackingUrl);
                await _openTrackingInApp(
                  url: uri.toString(),
                  title: isAnkolo ? 'Ankolo Tracking' : 'Smart Tracking',
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _brand.withOpacity(.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _brand.withOpacity(.45)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 18, color: Color(0xFFFF8A00)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        method == ShippingMethod.ankolo
                            ? 'Track with Ankolo Courier'
                            : 'Track with Smart Courier',
                        style: TextStyle(
                          color: Color(0xFFFF8A00),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: tracking,
            decoration: const InputDecoration(
              labelText: 'Tracking / courier reference (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: o.status == OrderStatus.delivered ? null : () => _markShipped(o),
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                disabledBackgroundColor: _brand.withOpacity(.45),
              ),
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(
                o.status == OrderStatus.delivered
                    ? 'Already delivered'
                    : 'Mark as delivered',
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF222222),
        title: const Text('To Ship'),
        centerTitle: true,
      ),
      body: FutureBuilder<List<OrderItem>>(
        future: _ordersFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Could not load orders: ${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final all = snap.data ?? const <OrderItem>[];

          // "To ship" = confirmed orders, prioritising those already paid.
          final toShip = all.where((o) {
            final isConfirmed = o.status == OrderStatus.confirmed;
            final isPaid = o.paymentStatus == PaymentStatus.paid;
            return isConfirmed || isPaid;
          }).toList();

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _ordersFuture = _svc.getMyOrders();
              });
              await _ordersFuture;
            },
            child: toShip.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 90),
                      Center(
                        child: Text(
                          'No confirmed or paid orders to ship yet',
                          style: TextStyle(color: Colors.redAccent),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: toShip.length,
                    itemBuilder: (_, i) => _orderCard(toShip[i]),
                  ),
          );
        },
      ),
    );
  }
}
