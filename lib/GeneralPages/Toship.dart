// address.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// Simple enum for how the merchant will ship the order.
enum ShippingMethod { cts, speed, pickup }

class ToShipPage extends StatefulWidget {
  const ToShipPage({super.key});

  @override
  State<ToShipPage> createState() => _ToShipPageState();
}

class _ToShipPageState extends State<ToShipPage> {
  final _svc = OrderService();
  final _money = NumberFormat.currency(symbol: 'MK ', decimalDigits: 0);
  final _date = DateFormat('dd MMM yyyy, HH:mm');
  final Color _brand = const Color(0xFFFF8A00);

  late Future<List<OrderItem>> _ordersFuture;
  final Map<String, ShippingMethod> _shippingForOrder = {};
  final Map<String, TextEditingController> _trackingCtrl = {};
  final Map<String, XFile?> _proofImage = {};

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
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
      _shippingForOrder[o.id] ?? ShippingMethod.cts;

  String _shippingLabel(ShippingMethod m) {
    switch (m) {
      case ShippingMethod.cts:
        return 'CTS courier';
      case ShippingMethod.speed:
        return 'Speed courier';
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
      final picked = await _picker.pickImage(source: ImageSource.gallery);
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
    final method = _shippingOf(o);
    final tracking = _trackingCtrl[o.id]?.text.trim();

    try {
      // For now we map "shipped" → delivered in the existing enum.
      await _svc.updateStatus(o.id, OrderStatus.delivered);

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
    final tracking = _trackingCtrl.putIfAbsent(
      o.id,
      () => TextEditingController(),
    );
    final method = _shippingOf(o);
    final proof = _proofImage[o.id];

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
            text: '${o.merchantName ?? 'Merchant'}  •  ${o.merchantPhone ?? '—'}',
          ),
          const SizedBox(height: 6),
          _infoRow(
            icon: Icons.location_on_outlined,
            text: [
                  if ((o.addressCity ?? '').isNotEmpty) o.addressCity,
                  if ((o.addressDescription ?? '').isNotEmpty) o.addressDescription,
                ].whereType<String>().join(' — ').isEmpty
                ? 'No delivery address'
                : [
                    if ((o.addressCity ?? '').isNotEmpty) o.addressCity,
                    if ((o.addressDescription ?? '').isNotEmpty) o.addressDescription,
                  ].whereType<String>().join(' — '),
            trailing: IconButton(
              icon: const Icon(Icons.map_outlined, size: 20),
              onPressed: () => _openMap(o),
              tooltip: 'View on map',
            ),
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
                  value: method,
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
                      value: ShippingMethod.pickup,
                      child: Text('Shop pickup'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _shippingForOrder[o.id] = v;
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () => _pickProof(o),
                icon: Icon(
                  proof == null ? Icons.add_a_photo_outlined : Icons.check_circle,
                  color: proof == null ? Colors.grey[700] : Colors.green,
                ),
                tooltip: proof == null ? 'Upload proof of shipment' : 'Proof selected',
              ),
            ],
          ),
          const SizedBox(height: 8),
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
              onPressed: () => _markShipped(o),
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Mark as shipped'),
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
