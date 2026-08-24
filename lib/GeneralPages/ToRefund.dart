import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/GeneralModels/order_list_helpers.dart';
import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/buyer_phone_resolver.dart';
import 'package:vero360_app/GernalServices/merchant_phone_resolver.dart';
import 'package:vero360_app/GernalServices/order_escrow_service.dart';
import 'package:vero360_app/GernalServices/order_refund_service.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/GernalServices/paychangu_service.dart';
import 'package:vero360_app/utils/merchant_contact_display.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/order_message_buyer_button.dart';

class _RefundPageData {
  final List<OrderItem> orders;
  final List<RefundRequestRecord> refunds;
  final Map<String, OrderEscrowSnapshot?> escrowByOrderId;

  const _RefundPageData({
    required this.orders,
    required this.refunds,
    required this.escrowByOrderId,
  });
}

/// Shows paid / confirmed orders that may qualify for a refund, plus your
/// submitted refund details.
///
/// Refund types:
/// 1) Cancel order and refund (before delivery)
/// 2) Return goods and refund (after delivery, within return window)
///
/// After [OrderRefundService.returnWindowDays] of receiving the parcel,
/// business is sealed — return refunds are closed.
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
  final _day = DateFormat('dd MMM yyyy');
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late Future<_RefundPageData> _future;
  final Map<String, String> _buyerPhoneByOrder = {};
  final Map<String, String> _merchantPhoneByOrder = {};

  @override
  void initState() {
    super.initState();
    _future = _loadPageData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_RefundPageData> _loadPageData() async {
    final list = await _svc.getMyOrders();
    OrderListHelpers.sortNewestFirst(list);

    final delivered = list
        .where((o) => o.status == OrderStatus.delivered)
        .toList(growable: false);
    final escrowByOrderId = delivered.isEmpty
        ? <String, OrderEscrowSnapshot?>{}
        : await OrderEscrowService.fetchEscrowForOrdersResolved(delivered);

    final refunds = await OrderRefundService.fetchMyRefundRequests();

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

    return _RefundPageData(
      orders: list,
      refunds: refunds,
      escrowByOrderId: escrowByOrderId,
    );
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

  bool _isSealed(OrderItem o, Map<String, OrderEscrowSnapshot?> escrowMap) {
    if (o.status != OrderStatus.delivered) return false;
    final esc = escrowMap[o.id];
    return !OrderRefundService.isReturnWindowOpen(
      receivedAt: esc?.deliveredAt ?? o.orderDate,
      escrow: esc,
    );
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _future = _loadPageData();
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

  Color _refundStatusColor(String label) {
    switch (label) {
      case 'Completed':
        return Colors.green;
      case 'Failed':
        return Colors.redAccent;
      case 'Processing':
        return Colors.blueAccent;
      default:
        return _brand;
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
                fontWeight: FontWeight.w600,
                color: Color(0xFF1565C0),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _refundDetailCard(RefundRequestRecord r) {
    final expected = r.expectedBy;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE0B2)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            spreadRadius: -8,
            offset: Offset(0, 10),
            color: Color(0x14000000),
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
                child: Text(
                  r.itemName.isEmpty ? 'Refund' : r.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF222222),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _chip(_refundStatusColor(r.statusLabel), r.statusLabel),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            r.isStay ? 'Stay · ${r.orderNumber}' : 'Order · ${r.orderNumber}',
            style: const TextStyle(
              color: Color(0xFF6B778C),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            r.typeLabel,
            style: TextStyle(
              color: _brand,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          if (r.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reason: ${r.reason.trim()}',
              style: const TextStyle(
                color: Color(0xFF444444),
                fontWeight: FontWeight.w500,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  r.createdAt == null
                      ? 'Requested —'
                      : 'Requested ${_day.format(r.createdAt!.toLocal())}',
                  style: const TextStyle(
                    color: Color(0xFF6B778C),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                _money.format(r.amount),
                style: TextStyle(
                  color: _brand,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (expected != null) ...[
            const SizedBox(height: 6),
            Text(
              'Funds typically by ${_day.format(expected.toLocal())} '
              '(within ${r.processingDays > 0 ? r.processingDays : OrderRefundService.processingDays} days)',
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
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

  Future<void> _openRefundSheet(
    OrderItem o, {
    OrderEscrowSnapshot? escrow,
  }) async {
    if (!mounted) return;
    if (o.status == OrderStatus.cancelled) return;

    final sealed = o.status == OrderStatus.delivered &&
        !OrderRefundService.isReturnWindowOpen(
          receivedAt: escrow?.deliveredAt ?? o.orderDate,
          escrow: escrow,
        );
    if (sealed) {
      ToastHelper.showCustomToast(
        context,
        OrderRefundService.sealedBusinessMessage(),
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    final reasonCtrl = TextEditingController();
    final selling = _isSellerForOrder(o);
    final delivered = o.status == OrderStatus.delivered;
    final sheetTitle = selling ? 'Refund this order' : 'Apply for refund';
    final submitLabel = selling ? 'Submit refund' : 'Submit refund request';
    final windowDays = OrderRefundService.returnWindowDays;

    PaymentRefundType? selectedType =
        delivered ? PaymentRefundType.returnGoods : PaymentRefundType.cancelOrder;

    try {
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
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        o.itemName,
                        style: const TextStyle(
                          color: Color(0xFF6B778C),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFE082)),
                        ),
                        child: Text(
                          delivered
                              ? 'Return goods is available for $windowDays days after receiving the parcel. After that, business is sealed.'
                              : 'Refunds are processed within 3 days after approval.',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: Color(0xFF5D4037),
                          ),
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
                            : () => setSheet(() {
                                  selectedType =
                                      PaymentRefundType.cancelOrder;
                                }),
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
                            : () => setSheet(() {
                                  selectedType =
                                      PaymentRefundType.returnGoods;
                                }),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: reasonCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Reason for refund',
                          hintText: 'Describe why you need a refund',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          if (selectedType == null) {
                            ToastHelper.showCustomToast(
                              ctx,
                              'Select a refund type',
                              isSuccess: false,
                              errorMessage: '',
                            );
                            return;
                          }
                          final reason = reasonCtrl.text.trim();
                          if (reason.isEmpty) {
                            ToastHelper.showCustomToast(
                              ctx,
                              'Please enter a reason for the refund',
                              isSuccess: false,
                              errorMessage: '',
                            );
                            return;
                          }
                          Navigator.pop(ctx, {
                            'type': selectedType,
                            'reason': reason,
                          });
                        },
                        child: Text(submitLabel),
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
        final reason = result['reason'] as String;
        await _submitRefundRequest(o, type, reason, escrow: escrow);
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
    String reason, {
    OrderEscrowSnapshot? escrow,
  }) async {
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
        escrow: escrow,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final days = res.processingDays > 0 ? res.processingDays : 3;
      ToastHelper.showCustomToast(
        context,
        'Refund applied and order cancelled. '
        'Funds are processed within $days days. '
        'Details are on this page.',
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

  Widget _infoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6B778C)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text.isEmpty ? '—' : text,
            style: const TextStyle(
              color: Color(0xFF444444),
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(
    OrderItem o, {
    required Map<String, OrderEscrowSnapshot?> escrowMap,
  }) {
    final qty = o.quantity;
    final unitPrice = o.price;
    final total = unitPrice * qty;
    final orderDate = o.orderDate;
    final isReceived = o.status == OrderStatus.delivered;
    final sealed = _isSealed(o, escrowMap);
    final escrow = escrowMap[o.id];
    final refundLabel =
        _isSellerForOrder(o) ? 'Refund this order' : 'Apply for refund';

    final addressCity = o.addressCity ?? '';
    final addressDesc = o.addressDescription ?? '';
    final addressTxt =
        [addressCity, addressDesc].where((s) => s.trim().isNotEmpty).join(' • ');
    final buyerName = (o.customerName ?? '').trim();
    final windowDays = OrderRefundService.returnWindowDays;

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
          if (isReceived && !sealed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Delivered — return refunds within $windowDays days of receiving.',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          if (sealed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                OrderRefundService.sealedBusinessMessage(),
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          if (!sealed)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _openRefundSheet(o, escrow: escrow),
                icon: const Icon(Icons.undo),
                label: Text(refundLabel),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade200),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: null,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Business sealed'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _processingBanner() {
    final days = OrderRefundService.returnWindowDays;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: Color(0xFFE65100)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Refunds settle within 3 days. Cancel before delivery, or return '
              'goods within $days days of receiving. After that, business is sealed.',
              style: const TextStyle(
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
              child: FutureBuilder<_RefundPageData>(
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

                  final data = snap.data!;
                  final all = data.orders;
                  final escrowMap = data.escrowByOrderId;
                  final q = _searchQuery.trim().toLowerCase();

                  final refundDetails = data.refunds.where((r) {
                    if (q.isEmpty) return true;
                    return r.orderNumber.toLowerCase().contains(q) ||
                        r.itemName.toLowerCase().contains(q) ||
                        r.reason.toLowerCase().contains(q) ||
                        r.status.toLowerCase().contains(q);
                  }).toList();

                  // Eligible: paid/confirmed/delivered, not cancelled.
                  // Sealed delivered orders still appear (locked) so the rule is clear.
                  final eligible = all.where((o) {
                    if (o.status == OrderStatus.cancelled) return false;
                    final isConfirmed = o.status == OrderStatus.confirmed;
                    final isDelivered = o.status == OrderStatus.delivered;
                    final isPaid = o.paymentStatus == PaymentStatus.paid;
                    if (!(isConfirmed || isDelivered || isPaid)) return false;
                    return OrderListHelpers.matchesSearch(o, _searchQuery);
                  }).toList();
                  OrderListHelpers.sortNewestFirst(eligible);

                  if (eligible.isEmpty && refundDetails.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 90),
                        Center(
                          child: Text(
                            _searchQuery.trim().isEmpty
                                ? 'No orders or refunds to show right now'
                                : 'No orders match your search',
                            style: const TextStyle(color: Colors.redAccent),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    );
                  }

                  final showMixedRoleHint = eligible.isNotEmpty &&
                      eligible.any(_isSellerForOrder) &&
                      eligible.any((o) => !_isSellerForOrder(o));

                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      if (refundDetails.isNotEmpty) ...[
                        const Text(
                          'Your refund details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF222222),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Status and timeline for refunds you submitted.',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...refundDetails.map(_refundDetailCard),
                        if (eligible.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Orders eligible to refund',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF222222),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                      if (showMixedRoleHint) _mixedRefundRolesHint(),
                      ...eligible.map(
                        (o) => _card(o, escrowMap: escrowMap),
                      ),
                    ],
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
