import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/GeneralModels/order_list_helpers.dart';
import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/buyer_phone_resolver.dart';
import 'package:vero360_app/GernalServices/merchant_phone_resolver.dart';
import 'package:vero360_app/GernalServices/order_refund_service.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/GernalServices/paychangu_service.dart';
import 'package:vero360_app/utils/merchant_contact_display.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/order_message_buyer_button.dart';

/// Shows paid / confirmed orders that may qualify for a refund.
///
/// Refund types:
/// 1) Cancel order and refund (before delivery)
/// 2) Return goods and refund (after delivery)
///
/// Refunds are processed via the payments API and settle within 3 days.
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late Future<List<OrderItem>> _future;
  final Map<String, String> _buyerPhoneByOrder = {};
  final Map<String, String> _merchantPhoneByOrder = {};

  @override
  void initState() {
    super.initState();
    _future = _loadOrdersWithMerchantPhones();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<OrderItem>> _loadOrdersWithMerchantPhones() async {
    final list = await _svc.getMyOrders();
    OrderListHelpers.sortNewestFirst(list);
    // Paint list first; resolve phones in the background.
    unawaited(() async {
      try {
        final results = await Future.wait([
          BuyerPhoneResolver.resolveForOrders(list),
          MerchantPhoneResolver.resolveForOrders(list),
        ]);
        if (!mounted) return;
        setState(() {
          _buyerPhoneByOrder
            ..clear()
            ..addAll(results[0]);
          _merchantPhoneByOrder
            ..clear()
            ..addAll(results[1]);
        });
      } catch (_) {}
    }());
    return list;
  }

  String _displayMerchantPhone(OrderItem o) {
    final resolved = _merchantPhoneByOrder[o.id];
    if (resolved != null && resolved.trim().isNotEmpty) return resolved;
    return safeMerchantPhone(o.merchantPhone);
  }

  String _displayBuyerPhone(OrderItem o) {
    final resolved = _buyerPhoneByOrder[o.id];
    if (resolved != null && resolved.trim().isNotEmpty) return resolved;
    return safeMerchantPhone(o.customerPhone);
  }

  /// You are the **seller** on this line only when your Firebase UID matches
  /// the order’s merchant UID. Merchants who **bought** from someone else
  /// are treated as buyers here.
  bool _isSellerForOrder(OrderItem o) {
    final myUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final sellerUid = (o.merchantUid ?? '').trim();
    if (myUid.isEmpty || sellerUid.isEmpty) return false;
    return myUid == sellerUid;
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _future = _loadOrdersWithMerchantPhones();
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

  /// Shown when the same account has both sales and purchases eligible for refund.
  Widget _mixedRefundRolesHint() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F4FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFFBBDEFB)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: Color(0xFF1976D2)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Items you sold show “Refund this order”. Items you bought show '
              '“Apply for refund” — even if your account is a merchant.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF1565C0),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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

  Widget _refundTypeTile({
    required PaymentRefundType type,
    required bool selected,
    required bool enabled,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final borderColor = selected
        ? _brand
        : enabled
            ? Colors.black12
            : Colors.black12;
    return Material(
      color: selected ? _brand.withValues(alpha: 0.08) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: enabled ? _brand : Colors.black26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: enabled
                            ? const Color(0xFF222222)
                            : Colors.black38,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled
                            ? const Color(0xFF6B778C)
                            : Colors.redAccent.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRefundSheet(OrderItem o) async {
    if (!mounted) return;
    if (o.status == OrderStatus.cancelled) return;

    final reasonCtrl = TextEditingController();
    final selling = _isSellerForOrder(o);
    final delivered = o.status == OrderStatus.delivered;
    final sheetTitle = selling ? 'Refund this order' : 'Apply for refund';
    final submitLabel = selling ? 'Submit refund' : 'Submit refund request';

    PaymentRefundType? selectedType =
        delivered ? PaymentRefundType.returnGoods : PaymentRefundType.cancelOrder;

    try {
      // Nested sheets from dashboards assert — always use the root navigator.
      final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setSheet) {
              final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
              return Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 18 + bottomInset),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        sheetTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Order ${o.orderNumber} • ${o.itemName}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _money.format(o.total),
                        style: TextStyle(
                          color: _brand,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4E5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFE0B2)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 20,
                              color: Color(0xFFE65100),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Refunds are processed within 3 days after approval.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE65100),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Select refund type',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      _refundTypeTile(
                        type: PaymentRefundType.cancelOrder,
                        selected: selectedType == PaymentRefundType.cancelOrder,
                        enabled: !delivered,
                        subtitle: delivered
                            ? 'Not available — this order was already delivered'
                            : 'Cancel before delivery and refund payment',
                        onTap: delivered
                            ? null
                            : () => setSheet(
                                  () => selectedType =
                                      PaymentRefundType.cancelOrder,
                                ),
                      ),
                      const SizedBox(height: 8),
                      _refundTypeTile(
                        type: PaymentRefundType.returnGoods,
                        selected: selectedType == PaymentRefundType.returnGoods,
                        enabled: delivered,
                        subtitle: delivered
                            ? 'Return the goods and refund payment'
                            : 'Available after the order is delivered',
                        onTap: !delivered
                            ? null
                            : () => setSheet(
                                  () => selectedType =
                                      PaymentRefundType.returnGoods,
                                ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Reason for refund',
                          border: OutlineInputBorder(),
                          hintText:
                              'Example: item not as described, damaged, never arrived…',
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
                        onPressed: () {
                          final type = selectedType;
                          final reason = reasonCtrl.text.trim();
                          if (type == null) {
                            ToastHelper.showCustomToast(
                              ctx,
                              'Select a refund type',
                              isSuccess: false,
                              errorMessage: '',
                            );
                            return;
                          }
                          if (reason.isEmpty) {
                            ToastHelper.showCustomToast(
                              ctx,
                              'Please enter a reason for the refund',
                              isSuccess: false,
                              errorMessage: '',
                            );
                            return;
                          }
                          Navigator.of(ctx).pop(<String, dynamic>{
                            'type': type,
                            'reason': reason,
                          });
                        },
                        child: Text(
                          submitLabel,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      if (result != null && mounted) {
        final type = result['type'] as PaymentRefundType;
        final reason = (result['reason'] as String?)?.trim() ?? '';
        await _submitRefundRequest(o, type, reason);
      }
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not open refund form',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        reasonCtrl.dispose();
      });
    }
  }

  Future<void> _submitRefundRequest(
    OrderItem o,
    PaymentRefundType type,
    String reason,
  ) async {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF8A00)),
      ),
    );

    try {
      final res = await OrderRefundService.submit(
        order: o,
        refundType: type,
        reason: reason,
        initiatedBySeller: _isSellerForOrder(o),
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final days = res.processingDays > 0 ? res.processingDays : 3;
      ToastHelper.showCustomToast(
        context,
        'Refund applied and order cancelled. '
        'Funds are processed within $days days.',
        isSuccess: true,
        errorMessage: '',
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ToastHelper.showCustomToast(
        context,
        'Refund failed',
        isSuccess: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Widget _card(OrderItem o) {
    final qty = o.quantity;
    final unitPrice = o.price;
    final total = unitPrice * qty;
    final orderDate = o.orderDate;
    final isReceived = o.status == OrderStatus.delivered;
    final refundLabel =
        _isSellerForOrder(o) ? 'Refund this order' : 'Apply for refund';

    final addressCity = o.addressCity ?? '';
    final addressDesc = o.addressDescription ?? '';
    final addressTxt =
        [addressCity, addressDesc].where((s) => s.trim().isNotEmpty).join(' • ');
    final buyerName = (o.customerName ?? '').trim();

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
              OrderThumbWithBuyerChat(
                order: o,
                size: 82,
                brand: _brand,
              ),
              const SizedBox(width: 12),
              Expanded(
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
                            _chip(
                              _statusColor(o.status),
                              _statusLabel(o.status),
                            ),
                            const SizedBox(height: 6),
                            _chip(
                              _paymentColor(o.paymentStatus),
                              _paymentLabel(o.paymentStatus),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (orderDate != null)
            _infoRow(Icons.schedule_outlined, _date.format(orderDate.toLocal())),
          const SizedBox(height: 6),
          Text(
            'Buyer',
            style: TextStyle(
              color: _brand.withValues(alpha: 0.95),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          _infoRow(
            Icons.person_outline,
            buyerName.isEmpty ? 'Name: —' : 'Name: $buyerName',
          ),
          const SizedBox(height: 6),
          _infoRow(
            Icons.phone_outlined,
            _displayBuyerPhone(o) == 'No phone number'
                ? 'Phone: —'
                : 'Phone: ${_displayBuyerPhone(o)}',
          ),
          const SizedBox(height: 8),
          Text(
            'Delivery',
            style: TextStyle(
              color: _brand.withValues(alpha: 0.95),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          _infoRow(Icons.place_outlined, addressTxt),
          const SizedBox(height: 8),
          Text(
            'Seller',
            style: TextStyle(
              color: _brand.withValues(alpha: 0.95),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          _infoRow(Icons.storefront_outlined, (o.merchantName ?? '').toString()),
          const SizedBox(height: 6),
          _infoRow(Icons.phone_outlined, _displayMerchantPhone(o)),
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
          if (isReceived)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Delivered — you can request “Return goods and refund”.',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
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
              label: Text(refundLabel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _processingBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: Color(0xFFE65100)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Refunds are processed within 3 days. Choose cancel order '
              '(before delivery) or return goods (after delivery).',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE65100),
                height: 1.35,
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
        title: const Text('To Refund'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              textInputAction: TextInputAction.search,
              decoration: OrderListHelpers.searchDecoration(
                hint: 'Search by order number…',
                hasQuery: _searchQuery.isNotEmpty,
                onClear: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
            ),
          ),
          _processingBanner(),
          Expanded(
            child: RefreshIndicator(
              color: _brand,
              onRefresh: _reload,
              child: FutureBuilder<List<OrderItem>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFFF8A00),
                          ),
                        ),
                      ],
                    );
                  }
                  if (snap.hasError) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
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

                  // Eligible: paid/confirmed, not already cancelled.
                  final eligible = all.where((o) {
                    if (o.status == OrderStatus.cancelled) return false;
                    final isConfirmed = o.status == OrderStatus.confirmed;
                    final isDelivered = o.status == OrderStatus.delivered;
                    final isPaid = o.paymentStatus == PaymentStatus.paid;
                    if (!(isConfirmed || isDelivered || isPaid)) return false;
                    return OrderListHelpers.matchesSearch(o, _searchQuery);
                  }).toList();
                  OrderListHelpers.sortNewestFirst(eligible);

                  if (eligible.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 90),
                        Center(
                          child: Text(
                            _searchQuery.trim().isEmpty
                                ? 'No orders available for refund right now'
                                : 'No orders match your search',
                            style: const TextStyle(color: Colors.redAccent),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    );
                  }

                  final showMixedRoleHint =
                      eligible.any(_isSellerForOrder) &&
                          eligible.any((o) => !_isSellerForOrder(o));

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: eligible.length + (showMixedRoleHint ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (showMixedRoleHint && i == 0) {
                        return _mixedRefundRolesHint();
                      }
                      final o = eligible[showMixedRoleHint ? i - 1 : i];
                      return _card(o);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
