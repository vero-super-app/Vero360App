import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/delivery_proof_service.dart';
import 'package:vero360_app/GernalServices/order_escrow_service.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/utils/app_wallet_pin.dart';
import 'package:vero360_app/utils/merchant_contact_display.dart';
import 'package:vero360_app/utils/toasthelper.dart';

const String _ankoloTrackingUrl = 'https://ankolo.com/track-parcel';
const String _smartTrackingUrl = 'https://tracking.smartdeliveriesmw.com/';

class _DeliveredPayload {
  final List<OrderItem> orders;
  final Map<String, Map<String, String>> deliveryMeta;
  final Map<String, OrderEscrowSnapshot?> escrowByOrderId;

  const _DeliveredPayload({
    required this.orders,
    required this.deliveryMeta,
    required this.escrowByOrderId,
  });
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

/// Buyer: track courier, view shipment proof, confirm receipt with biometric / PIN to release escrow.
/// Merchant: see tracking & proof on sales; payout releases when the buyer confirms.
class DeliveredOrdersPage extends StatefulWidget {
  const DeliveredOrdersPage({super.key});

  @override
  State<DeliveredOrdersPage> createState() => _DeliveredOrdersPageState();
}

class _DeliveredOrdersPageState extends State<DeliveredOrdersPage> {
  final _svc = OrderService();
  final Color _brand = const Color(0xFFFF8A00);
  final _money = NumberFormat.currency(symbol: 'MK ', decimalDigits: 0);
  final _date = DateFormat('dd MMM yyyy, HH:mm');

  late Future<_DeliveredPayload> _future;
  String? _releasingOrderId;

  @override
  void initState() {
    super.initState();
    _future = _loadPayload();
  }

  Future<_DeliveredPayload> _loadPayload() async {
    final orders = await _svc.getMyOrders(status: OrderStatus.delivered);
    for (final o in orders) {
      await OrderEscrowService.repairDeliveredTimestampIfNeeded(o);
    }
    final ids = orders.map((e) => e.id);
    final deliveryMeta = await DeliveryProofService.getDeliveryMetadata(ids);
    final escrowByOrderId =
        await OrderEscrowService.fetchEscrowForOrderIds(ids);
    return _DeliveredPayload(
      orders: orders,
      deliveryMeta: deliveryMeta,
      escrowByOrderId: escrowByOrderId,
    );
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _future = _loadPayload();
    });
    try {
      await _future;
    } catch (_) {
      // Error shown by FutureBuilder
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openTrackingWebView(String url, String title) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _TrackingWebViewPage(url: url, title: title),
      ),
    );
  }

  Future<void> _openProofUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not open proof link',
        isSuccess: false,
        errorMessage: 'Open failed',
      );
    }
  }

  String _courierDisplay(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'ankolo':
        return 'Ankolo';
      case 'smart':
        return 'Smart Deliveries';
      case 'speed':
        return 'Speed';
      case 'cts':
        return 'CTS';
      case 'pickup':
        return 'Pickup';
      default:
        return raw.trim().isEmpty ? 'Courier' : raw.trim();
    }
  }

  Future<void> _confirmReceiptAndRelease(
    OrderItem o,
    OrderEscrowSnapshot? escrow,
  ) async {
    if (_releasingOrderId != null) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (escrow == null || !escrow.isHeld) return;
    if (myUid.isEmpty || escrow.buyerUid != myUid) return;

    setState(() => _releasingOrderId = o.id);
    try {
      final ok = await AppWalletPin.verifyParcelReceipt(context);
      if (!ok || !mounted) return;
      await OrderEscrowService.releaseFunds(
        orderId: o.id,
        buyerConfirmed: true,
      );
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Payment released to the seller. Thank you!',
        isSuccess: true,
        errorMessage: '',
      );
      await _reload();
    } on StateError catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        e.toString(),
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not release payment: $e',
        isSuccess: false,
        errorMessage: '$e',
      );
    } finally {
      if (mounted) setState(() => _releasingOrderId = null);
    }
  }

  Color _paymentColor(String statusUpper) {
    if (statusUpper == 'PAID' ||
        statusUpper == 'SUCCESS' ||
        statusUpper == 'PAID_OUT') {
      return Colors.green;
    }
    if (statusUpper == 'UNPAID' ||
        statusUpper == 'FAILED' ||
        statusUpper == 'PENDING') {
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
        style: TextStyle(
          color: c.withValues(alpha: .95),
          fontWeight: FontWeight.w700,
        ),
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
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  Widget _deliveredNoticeLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.w800)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF444444),
                height: 1.4,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Buyer guidance: verify with courier / waybill before releasing escrow.
  Widget _deliveredOrdersInstructionCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _brand.withValues(alpha: 0.35)),
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
            children: [
              Icon(Icons.verified_user_outlined, color: _brand, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Before you confirm receipt',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF222222),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _deliveredNoticeLine(
            'Confirm authenticity of delivery with the courier when in doubt.',
          ),
          _deliveredNoticeLine(
            'Track the parcel using the waybill or tracking number provided above.',
          ),
          _deliveredNoticeLine(
            'Do not confirm receiving the parcel or release payment unless you have '
            'actually received the goods or verified delivery status with the courier.',
          ),
        ],
      ),
    );
  }

  Widget _card(
    OrderItem o,
    Map<String, String> meta,
    OrderEscrowSnapshot? escrow,
  ) {
    final String imageUrl = o.itemImage.toString();
    final String itemName = o.itemName.toString();
    final String orderNo = o.orderNumber.toString();
    final String paymentStr = o.paymentStatus.toString().toUpperCase();

    final int qty = int.tryParse('${o.quantity}') ?? 1;
    final num unitPrice = num.tryParse('${o.price}') ?? 0;
    final num total = unitPrice * qty;

    final String addressCity = (o.addressCity ?? '').toString();
    final String addressDesc = (o.addressDescription ?? '').toString();
    final String merchantName = (o.merchantName ?? '').toString();
    final String merchantPhone = safeMerchantPhone(o.merchantPhone);

    final orderDate = o.orderDate;
    final addressTxt =
        [addressCity, addressDesc].where((s) => s.trim().isNotEmpty).join(' • ');
    final payColor = _paymentColor(paymentStr);

    final method = (meta['method'] ?? '').trim().toLowerCase();
    final tracking = (meta['tracking'] ?? '').trim();
    final proofUrl = (meta['proofUrl'] ?? '').trim();

    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final canConfirmEscrow = escrow != null &&
        escrow.isHeld &&
        myUid.isNotEmpty &&
        escrow.buyerUid == myUid;
    final orderMerchantUid = (o.merchantUid ?? '').trim();
    final isSellerWaiting = escrow != null &&
        escrow.isHeld &&
        myUid.isNotEmpty &&
        escrow.buyerUid.isNotEmpty &&
        escrow.buyerUid != myUid &&
        (escrow.merchantUid == myUid ||
            (orderMerchantUid.isNotEmpty && orderMerchantUid == myUid));

    final releasing = _releasingOrderId == o.id;

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
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: imageUrl.isEmpty
                  ? Container(
                      color: const Color(0xFFF1F2F6),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.grey,
                      ),
                    )
                  : Image.network(imageUrl, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  _infoRow(
                    Icons.schedule_outlined,
                    _date.format(orderDate.toLocal()),
                  ),
                ],
                const SizedBox(height: 6),
                _infoRow(Icons.place_outlined, addressTxt),
                const SizedBox(height: 6),
                _infoRow(Icons.storefront_outlined, merchantName),
                const SizedBox(height: 6),
                _infoRow(Icons.phone_outlined, merchantPhone),

                if (method.isNotEmpty || tracking.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  if (method.isNotEmpty)
                    _infoRow(
                      Icons.local_shipping_outlined,
                      'Courier: ${_courierDisplay(method)}',
                    ),
                  if (tracking.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _infoRow(Icons.qr_code_2_outlined, 'Tracking: $tracking'),
                  ],
                  if (method == 'ankolo' || method == 'smart') ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final u = method == 'ankolo'
                              ? _ankoloTrackingUrl
                              : _smartTrackingUrl;
                          final title = method == 'ankolo'
                              ? 'Ankolo Tracking'
                              : 'Smart Tracking';
                          _openTrackingWebView(u, title);
                        },
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: Text(
                          method == 'ankolo'
                              ? 'Track on Ankolo'
                              : 'Track on Smart Deliveries',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ],

                if (proofUrl.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => _openProofUrl(proofUrl),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text(
                        'View shipment proof',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],

                if (escrow != null) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  if (escrow.isReleased)
                    _chip(
                      Colors.teal,
                      escrow.status == 'auto_released'
                          ? 'Payment released (auto)'
                          : 'Payment released to seller',
                    )
                  else if (escrow.isHeld) ...[
                    if (escrow.releaseDueAt != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'If you do not confirm, payment may auto-release after '
                          '${OrderEscrowService.escrowAutoReleaseDays} days '
                          '(${_date.format(escrow.releaseDueAt!.toLocal())}).',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B778C),
                            height: 1.35,
                          ),
                        ),
                      ),
                    if (canConfirmEscrow) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.orange.shade200,
                          ),
                        ),
                        child: Text(
                          'Only confirm after you have your parcel or the courier '
                          'confirms delivery — check tracking / waybill first.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: releasing
                            ? null
                            : () => _confirmReceiptAndRelease(o, escrow),
                        style: FilledButton.styleFrom(
                          backgroundColor: _brand,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: releasing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.verified_user_outlined),
                        label: Text(
                          releasing
                              ? 'Confirming…'
                              : 'I received my parcel — release payment',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ] else if (isSellerWaiting)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F2F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Waiting for the buyer to confirm receipt so your payout can be released.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B778C),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ],

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
        title: const Text('Delivered orders'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<_DeliveredPayload>(
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
            final payload = snap.data!;
            final data = payload.orders;
            if (data.isEmpty) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _deliveredOrdersInstructionCard(),
                  const SizedBox(height: 48),
                  const Center(
                    child: Text(
                      'No delivered orders yet',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: data.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) return _deliveredOrdersInstructionCard();
                final o = data[i - 1];
                final meta = payload.deliveryMeta[o.id] ?? const {};
                final escrow = payload.escrowByOrderId[o.id];
                return _card(o, meta, escrow);
              },
            );
          },
        ),
      ),
    );
  }
}
