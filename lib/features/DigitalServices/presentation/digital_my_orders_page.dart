import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/features/DigitalServices/digital_product.dart';
import 'package:vero360_app/features/DigitalServices/presentation/digital_service_order_service.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/user_facing_error.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

const Color _veroOrange = Color(0xFFFF8A00);
const Color _ink = Color(0xFF1A1109);
const Color _pageBg = Color(0xFFF7F8FA);

final DateFormat _dateFmt = DateFormat('EEE, d MMM yyyy · HH:mm');

class DigitalMyOrdersPage extends StatefulWidget {
  const DigitalMyOrdersPage({super.key, this.initialOrderId});

  /// When opened from a notification, jump straight into this order.
  final String? initialOrderId;

  @override
  State<DigitalMyOrdersPage> createState() => _DigitalMyOrdersPageState();
}

class _DigitalMyOrdersPageState extends State<DigitalMyOrdersPage> {
  bool _openedInitial = false;

  @override
  void initState() {
    super.initState();
    NotificationStore.instance
        .markBadgeRouteAsRead(NotificationStore.kBadgeDigitalOrders);
  }

  void _maybeOpenInitial(List<DigitalServiceOrder> orders) {
    if (_openedInitial) return;
    final want = (widget.initialOrderId ?? '').trim();
    if (want.isEmpty) return;
    DigitalServiceOrder? match;
    for (final o in orders) {
      if (o.id == want) {
        match = o;
        break;
      }
    }
    if (match == null) return;
    _openedInitial = true;
    final order = match;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openDetail(context, order);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final signedIn = user != null && !user.isAnonymous;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _veroOrange,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'My Digital Orders',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
      ),
      body: signedIn
          ? StreamBuilder<List<DigitalServiceOrder>>(
              stream: DigitalServiceOrderService.watchMine(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const AppSkeletonListPlaceholder(items: 6);
                }
                if (snap.hasError && (snap.data == null || snap.data!.isEmpty)) {
                  return _MessageState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Could not load orders',
                    body: UserFacingError.from(
                      snap.error,
                      fallback:
                          'Could not load your digital orders. Please try again.',
                    ),
                  );
                }
                final orders = snap.data ?? const <DigitalServiceOrder>[];
                _maybeOpenInitial(orders);
                if (orders.isEmpty) {
                  return const _MessageState(
                    icon: Icons.receipt_long_rounded,
                    title: 'No digital orders yet',
                    body:
                        'Gift cards, streaming, and ChatGPT purchases you pay for will show up here.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final order = orders[i];
                    return _DigitalOrderCard(
                      order: order,
                      onTap: () => _openDetail(context, order),
                    );
                  },
                );
              },
            )
          : const _MessageState(
              icon: Icons.lock_outline_rounded,
              title: 'Sign in to track orders',
              body: 'Sign in to see gift cards and subscriptions you have paid for.',
            ),
    );
  }

  static void _openDetail(BuildContext context, DigitalServiceOrder order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: order.fulfillment.hasContent ? 0.78 : 0.55,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => StreamBuilder<DigitalServiceOrder?>(
          stream: DigitalServiceOrderService.watchById(order.id),
          initialData: order,
          builder: (context, snap) {
            final live = snap.data ?? order;
            return _DigitalOrderDetailSheet(
              order: live,
              scrollController: scroll,
            );
          },
        ),
      ),
    );
  }
}

class _DigitalOrderCard extends StatelessWidget {
  const _DigitalOrderCard({required this.order, required this.onTap});

  final DigitalServiceOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final when = order.createdAt == null
        ? '—'
        : _dateFmt.format(order.createdAt!.toLocal());
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
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
                  child: const Icon(
                    Icons.confirmation_number_outlined,
                    color: _veroOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        when,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatMwk(order.amountMwk),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.green,
                          fontSize: 14,
                        ),
                      ),
                      if (order.fulfillment.hasContent) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Details ready · tap to copy',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _StatusChip(order: order),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.order});

  final DigitalServiceOrder order;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (order.isFailed) {
      bg = Colors.red.shade100;
      fg = Colors.red.shade800;
    } else if (order.isPaid) {
      bg = Colors.green.shade100;
      fg = Colors.green.shade800;
    } else {
      bg = Colors.orange.shade100;
      fg = Colors.orange.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        order.statusLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

class _DigitalOrderDetailSheet extends StatelessWidget {
  const _DigitalOrderDetailSheet({
    required this.order,
    required this.scrollController,
  });

  final DigitalServiceOrder order;
  final ScrollController scrollController;

  Future<void> _copy(BuildContext context, String label, String value) async {
    final v = value.trim();
    if (v.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: v));
    if (!context.mounted) return;
    ToastHelper.showCustomToast(
      context,
      '$label copied',
      isSuccess: true,
      errorMessage: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final when = order.createdAt == null
        ? '—'
        : _dateFmt.format(order.createdAt!.toLocal());
    final paid = order.paidAt == null
        ? '—'
        : _dateFmt.format(order.paidAt!.toLocal());
    final fulfill = order.fulfillment;
    return ListView(
      controller: scrollController,
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
          order.productName,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        _StatusChip(order: order),
        const SizedBox(height: 16),
        _row('Kind', order.kind.isEmpty ? '—' : order.kind.replaceAll('_', ' ')),
        if (order.periodLabel.isNotEmpty) _row('Period', order.periodLabel),
        if (order.brandTag.isNotEmpty) _row('Brand', order.brandTag),
        _row('Amount', formatMwk(order.amountMwk)),
        _row('Placed', when),
        if (order.paidAt != null) _row('Paid', paid),
        const SizedBox(height: 8),
        _copyRow(context, 'Order ID', order.id),
        if (order.txRef.isNotEmpty)
          _copyRow(context, 'Payment ref', order.txRef),
        if (fulfill.hasContent) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Your delivery',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Color(0xFF166534),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _copy(
                        context,
                        'Details',
                        fulfill.copyAllText,
                      ),
                      icon: const Icon(Icons.copy_all_rounded, size: 16),
                      label: const Text('Copy all'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF166534),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (fulfill.cardDetails.isNotEmpty)
                  _copyRow(context, 'Card details', fulfill.cardDetails),
                for (final e in fulfill.extraFields.entries)
                  _copyRow(context, e.key, e.value),
                if (fulfill.joiningLink.isNotEmpty)
                  _copyRow(context, 'Joining link', fulfill.joiningLink),
                if (fulfill.notes.isNotEmpty)
                  _copyRow(context, 'Notes', fulfill.notes),
                if (fulfill.fileUrls.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Files',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF166534),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final url in fulfill.fileUrls)
                        _FulfillmentFile(url: url),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          fulfill.hasContent
              ? 'Tap any orange row (or Copy all) to copy. Keep these details private.'
              : order.isPaid
                  ? 'Payment received. Vero is delivering this code or subscription. It will show here (and in your notifications) when ready.'
                  : 'This order is waiting for payment. Complete checkout to start delivery.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _copyRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Material(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => _copy(context, label, value),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SelectableText(
                          value,
                          onTap: () => _copy(context, label, value),
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: _veroOrange,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.copy_rounded,
                        size: 16,
                        color: _veroOrange,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FulfillmentFile extends StatelessWidget {
  const _FulfillmentFile({required this.url});

  final String url;

  bool get _isPdf => url.toLowerCase().contains('.pdf');

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ToastHelper.showCustomToast(
      context,
      'Link copied',
      isSuccess: true,
      errorMessage: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isPdf) {
      return OutlinedButton.icon(
        onPressed: _open,
        onLongPress: () => _copy(context),
        icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
        label: const Text('Open PDF'),
      );
    }
    return GestureDetector(
      onTap: _open,
      onLongPress: () => _copy(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: 88,
          height: 88,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 88,
            height: 88,
            color: const Color(0xFFDCFCE7),
            child: const Icon(Icons.insert_drive_file_rounded),
          ),
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
