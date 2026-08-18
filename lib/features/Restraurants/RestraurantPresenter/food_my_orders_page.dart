import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_time.dart';
import 'package:vero360_app/features/Restraurants/Models/food_order_model.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_review_service.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/food_order_tracking_page.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

const Color _veroOrange = Color(0xFFFF8A00);
const Color _ink = Color(0xFF1A1109);
const Color _pageBg = Color(0xFFF7F8FA);

final NumberFormat _mwk0Fmt =
    NumberFormat.currency(locale: 'en_US', symbol: 'MWK ', decimalDigits: 0);
String _mwk0(num v) => _mwk0Fmt.format(v);

/// TODO: extract with merchant dashboard [_getStatusColor] into a shared util.
Color _getStatusColor(String? status) {
  switch (status?.toLowerCase()) {
    case 'completed':
    case 'delivered':
      return Colors.green.shade100;
    case 'preparing':
      return Colors.blue.shade100;
    case 'pending':
      return Colors.orange.shade100;
    case 'cancelled':
      return Colors.red.shade100;
    default:
      return Colors.grey.shade100;
  }
}

class FoodMyOrdersPage extends StatefulWidget {
  const FoodMyOrdersPage({super.key});

  @override
  State<FoodMyOrdersPage> createState() => _FoodMyOrdersPageState();
}

class _FoodMyOrdersPageState extends State<FoodMyOrdersPage> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;
  final _reviewService = FoodReviewService();
  final _reviewedOrderIds = <String>{};

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _stream = null;
      return;
    }
    _stream = FirebaseFirestore.instance
        .collection('food_orders')
        .where('customerUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
    _loadReviewedIds(uid);
  }

  Future<void> _loadReviewedIds(String uid) async {
    final ids = await _reviewService.reviewedOrderIdsForCustomer(uid);
    if (!mounted) return;
    setState(() {
      _reviewedOrderIds
        ..clear()
        ..addAll(ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        centerTitle: true,
        title: const Text(
          'My Food Orders',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _stream == null
          ? _signedOut()
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const AppSkeletonListPlaceholder(items: 6);
                }
                if (snap.hasError) {
                  return _errorState('${snap.error}');
                }
                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) return _empty();

                final orders = docs
                    .map(FoodOrder.fromFirestore)
                    .toList();
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final order = orders[i];
                    return _FoodOrderCard(
                      order: order,
                      canRate: _isDelivered(order) &&
                          !_reviewedOrderIds.contains(order.id),
                      onTap: () => _openDetail(order),
                      onTrack: () => _openTracking(order),
                    );
                  },
                );
              },
            ),
    );
  }

  void _openTracking(FoodOrder order) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FoodOrderTrackingPage(orderId: order.id),
      ),
    );
  }

  void _openDetail(FoodOrder order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _FoodOrderDetailSheet(
          order: order,
          alreadyReviewed: _reviewedOrderIds.contains(order.id),
          onReviewed: () {
            setState(() => _reviewedOrderIds.add(order.id));
          },
          onTrack: () {
            Navigator.pop(context);
            _openTracking(order);
          },
        ),
      ),
    );
  }

  Widget _signedOut() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 48, color: _veroOrange.withValues(alpha: 0.8)),
            const SizedBox(height: 12),
            const Text(
              'Sign in to see your food orders',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: _ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu_rounded,
                size: 56, color: _veroOrange.withValues(alpha: 0.7)),
            const SizedBox(height: 14),
            const Text(
              'No food orders yet',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'When you order from a kitchen, tracking shows up here live.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink.withValues(alpha: 0.55),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not load orders.\n$message',
          textAlign: TextAlign.center,
          style: TextStyle(color: _ink.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}

class _FoodOrderCard extends StatelessWidget {
  const _FoodOrderCard({
    required this.order,
    required this.onTap,
    required this.onTrack,
    this.canRate = false,
  });

  final FoodOrder order;
  final VoidCallback onTap;
  final VoidCallback onTrack;
  final bool canRate;

  @override
  Widget build(BuildContext context) {
    final name = order.restaurantName.trim().isEmpty
        ? 'Kitchen'
        : order.restaurantName.trim();
    final when = order.createdAt == null
        ? ''
        : MarketplaceTime.formatTimeAgo(order.createdAt!, verbose: true);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _veroOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.restaurant_menu_rounded,
                    color: _veroOrange, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: _ink,
                            ),
                          ),
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          label: Text(
                            order.status,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          backgroundColor: _getStatusColor(order.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _lineSummary(order.lineItems),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: _ink.withValues(alpha: 0.62),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.courierTrackingNumber.trim().isEmpty
                          ? 'Vero Courier'
                          : 'Vero Courier · ${order.courierTrackingNumber.trim()}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _ink.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          _mwk0(order.totalMwk),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _veroOrange,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: onTrack,
                          style: TextButton.styleFrom(
                            foregroundColor: _veroOrange,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text(
                            'Track',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (canRate)
                          const Text(
                            'Rate this order',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _veroOrange,
                            ),
                          )
                        else if (when.isNotEmpty)
                          Text(
                            when,
                            style: TextStyle(
                              fontSize: 12,
                              color: _ink.withValues(alpha: 0.45),
                            ),
                          ),
                      ],
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
}

class _FoodOrderDetailSheet extends StatefulWidget {
  const _FoodOrderDetailSheet({
    required this.order,
    required this.alreadyReviewed,
    required this.onReviewed,
    required this.onTrack,
  });

  final FoodOrder order;
  final bool alreadyReviewed;
  final VoidCallback onReviewed;
  final VoidCallback onTrack;

  @override
  State<_FoodOrderDetailSheet> createState() => _FoodOrderDetailSheetState();
}

class _FoodOrderDetailSheetState extends State<_FoodOrderDetailSheet> {
  final _commentCtrl = TextEditingController();
  final _reviewService = FoodReviewService();
  int _rating = 5;
  bool _submitting = false;
  late bool _alreadyReviewed;

  FoodOrder get order => widget.order;

  @override
  void initState() {
    super.initState();
    _alreadyReviewed = widget.alreadyReviewed;
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_submitting) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Sign in to leave a review.',
        isSuccess: false,
        errorMessage: 'Not signed in',
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final name = order.customerName.trim().isNotEmpty
          ? order.customerName.trim()
          : (FirebaseAuth.instance.currentUser?.displayName ?? 'Customer');
      await _reviewService.submitReview(
        orderId: order.id,
        restaurantId: order.restaurantId,
        merchantId: order.merchantId,
        customerUid: uid,
        customerName: name,
        rating: _rating,
        comment: _commentCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _alreadyReviewed = true);
      widget.onReviewed();
      ToastHelper.showCustomToast(
        context,
        'Thanks for rating this order.',
        isSuccess: true,
        errorMessage: '',
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException
          ? e.message
          : 'Could not save your review. Try again.';
      if (e is ApiException &&
          e.message.toLowerCase().contains('already reviewed')) {
        setState(() => _alreadyReviewed = true);
        widget.onReviewed();
      }
      ToastHelper.showCustomToast(
        context,
        msg,
        isSuccess: false,
        errorMessage: msg,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = order.restaurantName.trim().isEmpty
        ? 'Kitchen'
        : order.restaurantName.trim();
    final cancelled = order.status.toLowerCase() == 'cancelled';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scroll) {
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Text(
              name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Order #${order.id.length > 8 ? order.id.substring(0, 8) : order.id}',
              style: TextStyle(color: _ink.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 16),
            if (cancelled)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cancel_outlined, color: Colors.red.shade700),
                    const SizedBox(width: 10),
                    Text(
                      'This order was cancelled',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.red.shade800,
                      ),
                    ),
                  ],
                ),
              )
            else
              _StatusStepper(status: order.status),
            if (_isDelivered(order)) ...[
              const SizedBox(height: 18),
              _buildRateSection(),
            ],
            const SizedBox(height: 22),
            const Text(
              'Items',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            if (order.lineItems.isEmpty)
              Text(
                'No line items on this order.',
                style: TextStyle(color: _ink.withValues(alpha: 0.5)),
              )
            else
              ...order.lineItems.map((line) {
                final title = line.variant == null || line.variant!.isEmpty
                    ? line.name
                    : '${line.name} (${line.variant})';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${line.quantity}×',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _veroOrange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            if (line.notes != null &&
                                line.notes!.trim().isNotEmpty)
                              Text(
                                line.notes!.trim(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _ink.withValues(alpha: 0.5),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        _mwk0(line.lineTotalMwk),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                );
              }),
            const Divider(height: 28),
            _kv('Subtotal', _mwk0(order.subtotalMwk)),
            _kv('Delivery', _mwk0(order.deliveryFeeMwk)),
            _kv('Service fee', _mwk0(order.serviceFeeMwk)),
            const SizedBox(height: 6),
            _kv('Total', _mwk0(order.totalMwk), emphasize: true),
            const SizedBox(height: 18),
            const Text(
              'Delivery',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              order.deliveryAddress.trim().isEmpty
                  ? 'No delivery address on this order.'
                  : order.deliveryAddress.trim(),
              style: TextStyle(
                height: 1.35,
                color: _ink.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              order.courierTrackingNumber.trim().isEmpty
                  ? 'Delivered by Vero Courier'
                  : 'Vero Courier · ${order.courierTrackingNumber.trim()}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: _veroOrange,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.onTrack,
                style: FilledButton.styleFrom(
                  backgroundColor: _veroOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.delivery_dining_rounded),
                label: const Text(
                  'Track on map',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRateSection() {
    if (_alreadyReviewed) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green.shade100),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green.shade700),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Thanks — you rated this order.',
                style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6EC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _veroOrange.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Rate this order',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'How was ${order.restaurantName.trim().isEmpty ? 'the kitchen' : order.restaurantName.trim()}?',
            style: TextStyle(
              fontSize: 12,
              color: _ink.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              final filled = star <= _rating;
              return IconButton(
                onPressed:
                    _submitting ? null : () => setState(() => _rating = star),
                icon: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 34,
                  color: filled ? _veroOrange : Colors.grey.shade400,
                ),
              );
            }),
          ),
          _reviewCommentField(),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _submitting ? null : _submitReview,
            style: FilledButton.styleFrom(
              backgroundColor: _veroOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Submit rating',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _reviewCommentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Comment (optional)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
            color: _ink,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: _commentCtrl,
          enabled: !_submitting,
          maxLines: 3,
          minLines: 2,
          style: const TextStyle(
            fontSize: 14,
            color: _ink,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: _veroOrange,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'e.g. Food was hot and arrived on time…',
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: Color(0xFFEEEEEE), width: 1.2),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: _veroOrange, width: 1.8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            k,
            style: TextStyle(
              color: _ink.withValues(alpha: 0.55),
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            v,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: emphasize ? _veroOrange : _ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStepper extends StatelessWidget {
  const _StatusStepper({required this.status});

  final String status;

  static const stages = ['pending', 'preparing', 'ready', 'delivered'];

  @override
  Widget build(BuildContext context) {
    var idx = stages.indexOf(status.toLowerCase());
    if (status.toLowerCase() == 'completed') idx = 3;
    if (idx < 0) idx = 0;

    return Row(
      children: [
        for (var i = 0; i < stages.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 3,
                color: i <= idx
                    ? _veroOrange
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= idx ? _veroOrange : Colors.white,
                  border: Border.all(
                    color: i <= idx
                        ? _veroOrange
                        : Colors.black.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
                child: i <= idx
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                stages[i],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: i == idx ? FontWeight.w800 : FontWeight.w600,
                  color: i <= idx ? _ink : _ink.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _lineSummary(List<FoodOrderLineItem> items) {
  if (items.isEmpty) return 'Food order';
  final shown = items.take(2).map((e) => '${e.name} x${e.quantity}').join(', ');
  final extra = items.length - 2;
  if (extra > 0) return '$shown, +$extra more';
  return shown;
}

bool _isDelivered(FoodOrder order) {
  final s = order.status.toLowerCase();
  return s == 'delivered' || s == 'completed';
}
