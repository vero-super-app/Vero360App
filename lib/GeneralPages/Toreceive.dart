import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/GeneralModels/order_model.dart';   // OrderItem + OrderStatus
import 'package:vero360_app/GernalServices/order_service.dart';

class DeliveredOrdersPage extends StatefulWidget {
  const DeliveredOrdersPage({super.key});

  @override
  State<DeliveredOrdersPage> createState() => _DeliveredOrdersPageState();
}

class _DeliveredOrdersPageState extends State<DeliveredOrdersPage> {
  final _svc = OrderService();
  final Color _brand = const Color(0xFFFF8A00);
  final _money = NumberFormat.currency(symbol: 'MK ', decimalDigits: 0);
  final _date  = DateFormat('dd MMM yyyy, HH:mm');

  late Future<List<OrderItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _svc.getMyOrders(status: OrderStatus.delivered);
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _future = _svc.getMyOrders(status: OrderStatus.delivered);
    });
    try {
      await _future;
    } catch (_) {
      // Error shown by FutureBuilder
    }
    if (!mounted) return;
    setState(() {});
  }

  Color _paymentColor(String statusUpper) {
    // statusUpper must already be uppercased
    if (statusUpper == 'PAID' || statusUpper == 'SUCCESS' || statusUpper == 'PAID_OUT') {
      return Colors.green;
    }
    if (statusUpper == 'UNPAID' || statusUpper == 'FAILED' || statusUpper == 'PENDING') {
      return Colors.redAccent;
    }
    return Colors.grey;
  }

  Widget _chip(Color c, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: .35)),
      ),
      child: Text(
        text,
        style: TextStyle(color: c.withValues(alpha: .95), fontWeight: FontWeight.w700),
      ),
    );
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

  Widget _card(OrderItem o) {
    // Strings (force to String so we never pass Object to Text/Chip)
    final String imageUrl   = o.itemImage.toString();
    final String itemName   = o.itemName.toString();
    final String orderNo    = o.orderNumber.toString();
    final String paymentStr = o.paymentStatus.toString().toUpperCase();

    // Numbers
    final int qty = int.tryParse('${o.quantity}') ?? 1;
    final num unitPrice = num.tryParse('${o.price}') ?? 0;
    final num total = unitPrice * qty;

    // Address + merchant (flat fields expected on your model)
    final String addressCity   = (o.addressCity ?? '').toString();
    final String addressDesc   = (o.addressDescription ?? '').toString();
    final String merchantName  = (o.merchantName ?? '').toString();
    final String merchantPhone = (o.merchantPhone ?? '').toString();

    final orderDate = o.orderDate; // DateTime? if your model exposes it
    final addressTxt = [addressCity, addressDesc].where((s) => s.trim().isNotEmpty).join(' • ');
    final payColor = _paymentColor(paymentStr);

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: imageUrl.isEmpty
                  ? Container(
                      color: const Color(0xFFF1F2F6),
                      child: const Icon(Icons.inventory_2_outlined, color: Colors.grey),
                    )
                  : Image.network(imageUrl, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 10),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: name + chips (shrink-to-fit to avoid overflow)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        itemName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF222222),
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _chip(Colors.green, 'Delivered'),
                            const SizedBox(height: 6),
                            _chip(_brand, _money.format(total)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                _infoRow(Icons.tag, 'Order #$orderNo'),
                if (orderDate != null) ...[
                  const SizedBox(height: 6),
                  _infoRow(Icons.schedule_outlined, _date.format(orderDate.toLocal())),
                ],
                const SizedBox(height: 6),
                _infoRow(Icons.place_outlined, addressTxt),
                const SizedBox(height: 6),
                _infoRow(Icons.storefront_outlined, merchantName),
                const SizedBox(height: 6),
                _infoRow(Icons.phone_outlined, merchantPhone),

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
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: _chip(
                          payColor,
                          paymentStr.isEmpty ? 'UNKNOWN' : paymentStr,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
        title: const Text('Delivered Orders'),
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
                      child: Text('Error: ${snap.error}', textAlign: TextAlign.center),
                    ),
                  ),
                ],
              );
            }
            final data = (snap.data ?? const <OrderItem>[]);
            if (data.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 90),
                  Center(child: Text('No delivered orders yet', style: TextStyle(color: Colors.red))),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: data.length,
              itemBuilder: (_, i) => _card(data[i]),
            );
          },
        ),
      ),
    );
  }
}
