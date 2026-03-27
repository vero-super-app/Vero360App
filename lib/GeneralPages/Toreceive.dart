import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/buyer_phone_resolver.dart';
import 'package:vero360_app/GernalServices/delivery_proof_service.dart';
import 'package:vero360_app/GernalServices/merchant_phone_resolver.dart';
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
  final Map<String, String> buyerPhonesByOrderId;
  final Map<String, OrderEscrowSnapshot?> escrowByOrderId;
  final Map<String, String> merchantPhonesByOrderId;

  const _DeliveredPayload({
    required this.orders,
    required this.deliveryMeta,
    required this.buyerPhonesByOrderId,
    required this.escrowByOrderId,
    required this.merchantPhonesByOrderId,
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

class _ProofViewerPage extends StatelessWidget {
  final String proofUrl;
  const _ProofViewerPage({required this.proofUrl});

  @override
  Widget build(BuildContext context) {
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
          child: Image.network(
            proofUrl,
            fit: BoxFit.contain,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              );
            },
            errorBuilder: (_, __, ___) =>
                const Text('Could not load proof image'),
          ),
        ),
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
      await OrderEscrowService.repairBuyerUidIfNeeded(o);
      await OrderEscrowService.repairDeliveredTimestampIfNeeded(o);
    }
    final ids = orders.map((e) => e.id);
    final deliveryMeta = await DeliveryProofService.getDeliveryMetadata(ids);
    final buyerPhonesByOrderId =
        await BuyerPhoneResolver.resolveForOrders(orders);
    final escrowByOrderId =
        await OrderEscrowService.fetchEscrowForOrdersResolved(orders);
    final merchantPhonesByOrderId =
        await MerchantPhoneResolver.resolveForOrders(orders);
    return _DeliveredPayload(
      orders: orders,
      deliveryMeta: deliveryMeta,
      buyerPhonesByOrderId: buyerPhonesByOrderId,
      escrowByOrderId: escrowByOrderId,
      merchantPhonesByOrderId: merchantPhonesByOrderId,
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
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProofViewerPage(proofUrl: url),
      ),
    );
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
    await OrderEscrowService.repairBuyerUidIfNeeded(o);
    final refreshed = await OrderEscrowService.fetchEscrow(o.id);
    if (!mounted) return;
    if (refreshed == null || !refreshed.isHeld) return;
    if (!_buyerMatchesEscrow(o, refreshed, myUid)) return;

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

  /// True when this signed-in user is the buyer for escrow (Firestore buyerUid or order customerUid).
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

  Widget _parcelEscrowSection({
    required OrderItem order,
    required OrderEscrowSnapshot? escrow,
    required bool canConfirmEscrow,
    required bool isSellerWaiting,
    required bool releasing,
  }) {
    if (escrow == null && order.paymentStatus == PaymentStatus.paid) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _brand.withValues(alpha: 0.35)),
        ),
        child: const Text(
          'No escrow hold is linked to this order id (often fixed after refresh if the hold '
          'was saved under a different id). Pull to refresh. If it persists, the order may '
          'not have been completed through in-app marketplace checkout.',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF6B778C),
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (escrow == null) return const SizedBox.shrink();

    if (escrow.isReleased) {
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
            if (escrow.releasedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 28),
                child: Text(
                  _date.format(escrow.releasedAt!.toLocal()),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B778C)),
                ),
              ),
          ],
        ),
      );
    }

    if (!escrow.isHeld) return const SizedBox.shrink();
    final waitingMerchant = escrow.deliveredAt == null;

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
            const Text(
              'Payment is held until the merchant marks this order as delivered.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B778C), height: 1.35),
            )
          else if (canConfirmEscrow) ...[
            Text(
              [
                if (escrow.releaseDueAt != null)
                  'If you do not confirm, payment is sent to the merchant on '
                      '${_date.format(escrow.releaseDueAt!.toLocal())}. ',
                'Confirm with Face ID, fingerprint, or PIN.',
              ].join(),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B778C),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: releasing
                  ? null
                  : () => _confirmReceiptAndRelease(order, escrow),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: releasing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.inventory_2_outlined),
              label: Text(releasing ? 'Confirming…' : 'I received this parcel'),
            ),
          ] else if (isSellerWaiting)
            const Text(
              'Waiting for the buyer to confirm receipt so your payout can be released.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B778C), height: 1.35),
            )
          else if (!waitingMerchant)
            const Text(
              'Payment is held for this order. Open this screen while signed in as the '
              'account that bought the item, then confirm receipt to release funds to the seller. '
              'If the button still does not appear, pull to refresh or contact support.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B778C), height: 1.35),
            ),
        ],
      ),
    );
  }

  Widget _card(
    OrderItem o,
    Map<String, String> meta,
    OrderEscrowSnapshot? escrow,
    Map<String, String> buyerPhonesByOrderId,
    Map<String, String> merchantPhonesByOrderId,
  ) {
    final String imageUrl = o.itemImage.toString();
    final String itemName = o.itemName.toString();
    final String orderNo = o.orderNumber.toString();
    final String paymentStr = switch (o.paymentStatus) {
      PaymentStatus.paid => 'PAID',
      PaymentStatus.pending => 'PENDING',
      PaymentStatus.unpaid => 'UNPAID',
    };

    final int qty = int.tryParse('${o.quantity}') ?? 1;
    final num unitPrice = num.tryParse('${o.price}') ?? 0;
    final num total = unitPrice * qty;

    final String addressCity = (o.addressCity ?? '').toString();
    final String addressDesc = (o.addressDescription ?? '').toString();
    final String buyerName = (o.customerName ?? '').toString().trim();
    final String buyerPhone = buyerPhonesByOrderId[o.id]?.trim().isNotEmpty == true
        ? buyerPhonesByOrderId[o.id]!
        : safeMerchantPhone(o.customerPhone);
    final String merchantName = (o.merchantName ?? '').toString();
    final String merchantPhone = merchantPhonesByOrderId[o.id]?.trim().isNotEmpty == true
        ? merchantPhonesByOrderId[o.id]!
        : safeMerchantPhone(o.merchantPhone);

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
        _buyerMatchesEscrow(o, escrow, myUid);
    final isSellerWaiting = escrow != null &&
        escrow.isHeld &&
        myUid.isNotEmpty &&
        _merchantMatchesEscrow(o, escrow, myUid) &&
        !_buyerMatchesEscrow(o, escrow, myUid);

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
                  buyerPhone == 'No phone number'
                      ? 'Phone: —'
                      : 'Phone: $buyerPhone',
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
                    Row(
                      children: [
                        Expanded(
                          child: _infoRow(
                            Icons.qr_code_2_outlined,
                            'Tracking: $tracking',
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy tracking number',
                          icon: const Icon(
                            Icons.copy,
                            size: 18,
                            color: Color(0xFF6B778C),
                          ),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: tracking),
                            );
                            if (!mounted) return;
                            ToastHelper.showCustomToast(
                              context,
                              'Tracking number copied',
                              isSuccess: true,
                              errorMessage: '',
                            );
                          },
                        ),
                      ],
                    ),
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

                const SizedBox(height: 10),
                _parcelEscrowSection(
                  order: o,
                  escrow: escrow,
                  canConfirmEscrow: canConfirmEscrow,
                  isSellerWaiting: isSellerWaiting,
                  releasing: releasing,
                ),

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
                return _card(
                  o,
                  meta,
                  escrow,
                  payload.buyerPhonesByOrderId,
                  payload.merchantPhonesByOrderId,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
