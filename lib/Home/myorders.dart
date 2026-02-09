import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({Key? key}) : super(key: key);

  @override
  State<OrdersPage> createState() => _OrdersPageState();
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
  final List<OrderStatus> _statuses = const [
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.delivered,
    OrderStatus.cancelled,
  ];

  /// Single future: fetch all orders once; filter by status in each tab.
  /// Backend may not support ?status=, so we filter client-side.
  late Future<List<OrderItem>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _statuses.length, vsync: this);
    _ordersFuture = _svc.getMyOrders();
  }

  Future<void> _reloadCurrent() async {
    if (!mounted) return;
    setState(() => _ordersFuture = _svc.getMyOrders());
    try {
      await _ordersFuture;
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

  Widget _orderCard(OrderItem o) {
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
                  text: '${o.merchantName ?? 'Merchant'}  •  ${o.merchantPhone ?? '—'}',
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
                Row(
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
                    const SizedBox(width: 10),
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
          if (items.isEmpty) {
            return ListView(
              children: [
                const SizedBox(height: 90),
                Center(
                  child: Text(
                    _searchQuery.trim().isEmpty
                        ? 'No orders in this status'
                        : 'No orders match your search',
                    style: const TextStyle(color: Color(0xFF6B778C)),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: items.length,
            itemBuilder: (_, i) => _orderCard(items[i]),
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
        centerTitle: true,
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: _brand,
          unselectedLabelColor: const Color(0xFF6B778C),
          indicatorColor: _brand,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Confirmed'),
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
