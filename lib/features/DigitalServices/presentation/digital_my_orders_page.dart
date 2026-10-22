import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/features/DigitalServices/digital_product.dart';
import 'package:vero360_app/features/DigitalServices/presentation/digital_service_order_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/user_facing_error.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

const Color _veroOrange = Color(0xFFFF8A00);
const Color _ink = Color(0xFF1A1109);
const Color _pageBg = Color(0xFFF7F8FA);

final DateFormat _dateFmt = DateFormat('EEE, d MMM yyyy · HH:mm');

class DigitalMyOrdersPage extends StatelessWidget {
  const DigitalMyOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final signedIn = FirebaseAuth.instance.currentUser != null;

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
      builder: (_) => _DigitalOrderDetailSheet(order: order),
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
  const _DigitalOrderDetailSheet({required this.order});

  final DigitalServiceOrder order;

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
          _copyRow(
            context,
            'Order ID',
            order.id,
          ),
          if (order.txRef.isNotEmpty)
            _copyRow(context, 'Payment ref', order.txRef),
          const SizedBox(height: 14),
          Text(
            order.isPaid
                ? 'Payment received. Vero is delivering this code or subscription. Keep this page for your records.'
                : 'This order is waiting for payment. Complete checkout to start delivery.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
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
            child: Text(
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
            child: InkWell(
              onTap: () => _copy(context, label, value),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: _veroOrange,
                      ),
                    ),
                  ),
                  const Icon(Icons.copy_rounded, size: 16, color: _veroOrange),
                ],
              ),
            ),
          ),
        ],
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
