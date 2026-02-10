import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// Shows orders that are eligible for a refund (confirmed or paid)
/// and lets the customer apply for a refund.
class ToRefundPage extends StatefulWidget {
  const ToRefundPage({super.key});

  @override
  State<ToRefundPage> createState() => _ToRefundPageState();
}

class _ToRefundPageState extends State<ToRefundPage> {
  final _svc = OrderService();
  final Color _brand = const Color(0xFFFF8A00);
  final _money = NumberFormat.currency(symbol: 'MK ', decimalDigits: 0);
  final _date = DateFormat('dd MMM yyyy, HH:mm');

  late Future<List<OrderItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _svc.getMyOrders();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _future = _svc.getMyOrders();
    });
    try {
      await _future;
    } catch (_) {
      // Error will be shown by FutureBuilder
    }
    if (!mounted) return;
    setState(() {});
  }

  Widget _chip(Color c, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(.10),
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

  Widget _infoRow(IconData icon, String text) {
    final t = text.trim();
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6B778C)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            t.isEmpty ? '—' : t,
            style: const TextStyle(color: Color(0xFF6B778C)),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  Future<void> _openRefundSheet(OrderItem o) async {
    final reasonCtrl = TextEditingController();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            18 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Apply for refund',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'Order ${o.orderNumber} • ${o.itemName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Explain why you want a refund. Your request will be reviewed. '
                  'Actual refund logic will be handled by the payments/PayChangu API.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Reason for refund',
                    border: OutlineInputBorder(),
                    hintText: 'Example: item not as described, never arrived…',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Submit refund request',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == true) {
      await _submitRefundRequest(o, reasonCtrl.text.trim());
    }
  }

  /// Placeholder for actual refund integration.
  /// Here we only show feedback; backend/PayChangu integration can use
  /// the order total and transaction reference to process a refund.
  Future<void> _submitRefundRequest(OrderItem o, String reason) async {
    // TODO: integrate with your backend & PayChangu refund flow.
    // For example:
    // - POST /orders/{id}/refund-requests with {reason}
    // - or call a dedicated /payments/refund endpoint using PaymentsService.

    ToastHelper.showCustomToast(
      context,
      'Refund request sent for order ${o.orderNumber}',
      isSuccess: true,
      errorMessage: '',
    );
  }

  Widget _card(OrderItem o) {
    final qty = o.quantity;
    final unitPrice = o.price;
    final total = unitPrice * qty;
    final orderDate = o.orderDate;

    final addressCity = o.addressCity ?? '';
    final addressDesc = o.addressDescription ?? '';
    final addressTxt =
        [addressCity, addressDesc].where((s) => s.trim().isNotEmpty).join(' • ');

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.itemName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF222222),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Order: ${o.orderNumber}',
                      style: const TextStyle(
                        color: Color(0xFF6B778C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
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
          if (orderDate != null)
            _infoRow(Icons.schedule_outlined, _date.format(orderDate.toLocal())),
          const SizedBox(height: 6),
          _infoRow(Icons.place_outlined, addressTxt),
          const SizedBox(height: 6),
          _infoRow(Icons.storefront_outlined, (o.merchantName ?? '').toString()),
          const SizedBox(height: 6),
          _infoRow(Icons.phone_outlined, (o.merchantPhone ?? '').toString()),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Qty: $qty  •  Unit: ${_money.format(unitPrice)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF222222),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _money.format(total),
                style: TextStyle(
                  color: _brand,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _openRefundSheet(o),
              icon: const Icon(Icons.undo),
              label: const Text('Apply for refund'),
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
        title: const Text('To Refund'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<OrderItem>>(
          future: _future,
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
                      child: Text(
                        'Error: ${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }

            final all = snap.data ?? const <OrderItem>[];

            // Eligible for refund: confirmed or paid (you can tweak rule later)
            final eligible = all.where((o) {
              final isConfirmed = o.status == OrderStatus.confirmed;
              final isPaid = o.paymentStatus == PaymentStatus.paid;
              return isConfirmed || isPaid;
            }).toList();

            if (eligible.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 90),
                  Center(
                    child: Text(
                      'No orders available for refund right now',
                      style: TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: eligible.length,
              itemBuilder: (_, i) => _card(eligible[i]),
            );
          },
        ),
      ),
    );
  }
}
