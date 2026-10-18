import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_price_breakdown.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_status_badge.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/user_facing_error.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

class CarHireBookingDetailPage extends ConsumerStatefulWidget {
  const CarHireBookingDetailPage({
    super.key,
    required this.bookingId,
    this.initialBooking,
  });

  final int bookingId;
  final CarHireBooking? initialBooking;

  @override
  ConsumerState<CarHireBookingDetailPage> createState() =>
      _CarHireBookingDetailPageState();
}

class _CarHireBookingDetailPageState
    extends ConsumerState<CarHireBookingDetailPage>
    with WidgetsBindingObserver {
  CarHireBooking? _localBooking;
  bool _cancelling = false;
  bool _paymentLaunching = false;
  bool _refreshing = false;
  bool _awaitingPaymentReturn = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingPaymentReturn) {
      _awaitingPaymentReturn = false;
      _refreshStatus();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _actionError = null;
    });
    ref.invalidate(carHireBookingDetailProvider(widget.bookingId));
    try {
      final fresh = await ref.read(
        carHireBookingDetailProvider(widget.bookingId).future,
      );
      if (!mounted) return;
      setState(() => _localBooking = fresh);
    } on CarHireApiException catch (error) {
      if (!mounted) return;
      setState(() => _actionError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionError = UserFacingError.from(error));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _refreshStatus() async {
    final current = _localBooking ??
        ref.read(carHireBookingDetailProvider(widget.bookingId)).asData?.value ??
        widget.initialBooking;
    if (current == null) return;

    setState(() {
      _refreshing = true;
      _actionError = null;
    });

    try {
      final fresh =
          await ref.read(carHireApiProvider).getBooking(current.id);
      if (!mounted) return;
      setState(() => _localBooking = fresh);
      ref.invalidate(myCarHireBookingsProvider);
      ref.invalidate(carHireBookingDetailProvider(widget.bookingId));

      if (fresh.paymentSucceeded) {
        ToastHelper.showToast(
          context,
          'Payment confirmed by Vero360. Booking status: '
          '${fresh.bookingStatus.label}.',
        );
      } else {
        ToastHelper.showToast(
          context,
          'Payment status from Vero360: "${fresh.paymentLabel}".',
        );
      }
    } on CarHireApiException catch (error) {
      if (!mounted) return;
      setState(() => _actionError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionError = UserFacingError.from(error));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _cancelBooking(CarHireBooking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel this booking?'),
          content: const Text(
            'This releases the dates and cannot be undone. Any refund is '
            'handled according to the rental terms and the payment status '
            'shown on this booking.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep booking'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: CarRentalColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cancel booking'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _cancelling = true;
      _actionError = null;
    });

    try {
      final updated =
          await ref.read(carHireApiProvider).cancelBooking(booking.id);
      if (!mounted) return;
      setState(() => _localBooking = updated);
      ref.invalidate(myCarHireBookingsProvider);
      ref.invalidate(carHireBookingDetailProvider(widget.bookingId));
      ToastHelper.showToast(context, 'Booking cancelled.');
    } on CarHireApiException catch (error) {
      if (!mounted) return;
      setState(() => _actionError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionError = UserFacingError.from(error));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _startPayment(CarHireBooking booking) async {
    final phone = await showDialog<String>(
      context: context,
      builder: (_) => const _PaymentPhoneDialog(),
    );
    if (phone == null || !mounted) return;

    setState(() {
      _paymentLaunching = true;
      _actionError = null;
    });

    try {
      final initiation = await ref.read(carHireApiProvider).initiatePayment(
            booking.id,
            phoneNumber: phone,
          );
      if (initiation.booking != null && mounted) {
        setState(() => _localBooking = initiation.booking);
      }

      final rawUrl = initiation.checkoutUrl?.trim();
      if (rawUrl == null || rawUrl.isEmpty) {
        if (!mounted) return;
        setState(() {
          _actionError = 'The payment provider did not return a checkout link. '
              'Please try again.';
        });
        return;
      }

      final uri = Uri.tryParse(rawUrl);
      if (uri == null) {
        if (!mounted) return;
        setState(() {
          _actionError = 'The payment link was not valid. Please try again.';
        });
        return;
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;

      if (!launched) {
        setState(() {
          _actionError =
              'We could not open the payment page. Please try again.';
        });
        return;
      }

      setState(() => _awaitingPaymentReturn = true);
    } on CarHireApiException catch (error) {
      if (!mounted) return;
      setState(() => _actionError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionError = UserFacingError.from(error));
    } finally {
      if (mounted) setState(() => _paymentLaunching = false);
    }
  }

  void _showSupportPlaceholder(CarHireBooking booking) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Car hire support'),
          content: Text(
            'In-app car hire support is not available yet. Please open the '
            'Support tile on the home screen to reach Vero Assist and quote '
            'your booking number (${booking.bookingNumberLabel}).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(carHireBookingDetailProvider(widget.bookingId));
    final booking = _localBooking ??
        async.asData?.value ??
        widget.initialBooking;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: CarRentalColors.title,
        elevation: 0.4,
        scrolledUnderElevation: 0.4,
        title: const Text(
          'Booking details',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
      ),
      body: booking == null
          ? async.when(
              loading: () => const CarHireLoadingState(
                message: 'Loading booking details…',
              ),
              error: (error, _) => CarHireErrorState(
                error: error,
                onRetry: _refresh,
              ),
              data: (_) => CarHireErrorState(
                message: 'We could not find this booking.',
                onRetry: _refresh,
              ),
            )
          : RefreshIndicator(
              color: CarRentalColors.brandOrange,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  if (async.isLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: CarRentalColors.brandOrange,
                        backgroundColor: CarRentalColors.brandOrangePale,
                      ),
                    ),
                  _statusCard(booking),
                  if (_actionError != null) ...[
                    const SizedBox(height: 12),
                    _InlineError(message: _actionError!),
                  ],
                  const SizedBox(height: 12),
                  _carCard(booking),
                  const SizedBox(height: 12),
                  _datesCard(booking),
                  const SizedBox(height: 12),
                  _priceCard(booking),
                  const SizedBox(height: 12),
                  _paymentCard(booking),
                  const SizedBox(height: 12),
                  _cancellationCard(booking),
                  const SizedBox(height: 12),
                  _supportCard(booking),
                ],
              ),
            ),
    );
  }

  Widget _statusCard(CarHireBooking booking) {
    final holdExpired =
        booking.bookingStatus == BookingStatus.pending && booking.isHoldExpired;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.bookingNumberLabel,
                      style: const TextStyle(
                        color: CarRentalColors.title,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      booking.car?.title ?? 'Vehicle rental',
                      style: const TextStyle(
                        color: CarRentalColors.body,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: CarHireStatusBadge.booking(booking.bookingStatus),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CarHireStatusBadge.payment(booking.paymentStatus),
            ],
          ),
          if (booking.nextActionLabel != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CarRentalColors.brandOrangePale,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: CarRentalColors.brandOrange,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      booking.nextActionLabel!,
                      style: const TextStyle(
                        color: CarRentalColors.body,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (holdExpired) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CarRentalColors.errorLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.timer_off_outlined,
                    size: 16,
                    color: CarRentalColors.error,
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'The hold on these dates has expired. Refresh the '
                      'booking or start a new search for current availability.',
                      style: TextStyle(
                        color: CarRentalColors.error,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          _InfoRow(label: 'Hold', value: booking.holdExpiryLabel),
          if (booking.driverName != null)
            _InfoRow(label: 'Driver', value: booking.driverName!),
          if (booking.renterNotes != null)
            _InfoRow(label: 'Notes', value: booking.renterNotes!),
        ],
      ),
    );
  }

  Widget _carCard(CarHireBooking booking) {
    final car = booking.car;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Vehicle'),
          const SizedBox(height: 10),
          if (car == null)
            const Text(
              'Vehicle details are not available for this booking. '
              'Contact support if you need them.',
              style: TextStyle(
                color: CarRentalColors.body,
                fontSize: 12,
                height: 1.4,
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 86,
                    height: 70,
                    child: car.primaryImage == null
                        ? Container(
                            color: CarRentalColors.chip,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.directions_car_filled_rounded,
                              color: CarRentalColors.grey,
                            ),
                          )
                        : ResilientCachedNetworkImage(
                            url: car.primaryImage!,
                            fit: BoxFit.cover,
                            width: 86,
                            height: 70,
                            memCacheWidth: 280,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        car.title,
                        style: const TextStyle(
                          color: CarRentalColors.title,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (car.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          car.subtitle,
                          style: const TextStyle(
                            color: CarRentalColors.body,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        '${car.seatsLabel} · ${car.transmissionLabel} · '
                        '${car.fuelLabel}',
                        style: const TextStyle(
                          color: CarRentalColors.body,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        car.pickupAreaLabel,
                        style: const TextStyle(
                          color: CarRentalColors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _datesCard(CarHireBooking booking) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Rental period'),
          const SizedBox(height: 10),
          _InfoRow(
            label: 'Pick-up',
            value: booking.startAt == null
                ? 'Not provided'
                : CarHireFormatters.formatDateTime(booking.startAt!),
          ),
          _InfoRow(
            label: 'Return',
            value: booking.endAt == null
                ? 'Not provided'
                : CarHireFormatters.formatDateTime(booking.endAt!),
          ),
        ],
      ),
    );
  }

  Widget _priceCard(CarHireBooking booking) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Price breakdown'),
          const SizedBox(height: 10),
          CarHirePriceBreakdown.booking(booking),
          const SizedBox(height: 4),
          const Text(
            'Amounts come from the server quote and booking record. Vero360 '
            'does not calculate the total on this screen.',
            style: TextStyle(
              color: CarRentalColors.grey,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentCard(CarHireBooking booking) {
    final paid = booking.paymentSucceeded;
    final pending = booking.paymentStatus == PaymentStatus.pending;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Payment'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.paymentLabel,
                  style: TextStyle(
                    color: paid
                        ? CarRentalColors.success
                        : pending
                            ? CarRentalColors.brandOrange
                            : CarRentalColors.title,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: CarHireStatusBadge.payment(booking.paymentStatus),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'Amount', value: booking.totalLabel),
          if (booking.paymentReference != null)
            _InfoRow(
              label: 'Reference',
              value: booking.paymentReference!,
            ),
          if (paid) ...[
            const SizedBox(height: 8),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: CarRentalColors.success,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Vero360 has confirmed this payment with the payment '
                    'provider.',
                    style: TextStyle(
                      color: CarRentalColors.body,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (pending) ...[
            const SizedBox(height: 8),
            const Text(
              'The payment provider has not confirmed this payment yet. '
              'Refresh the booking in a moment.',
              style: TextStyle(
                color: CarRentalColors.body,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
          if (booking.canPay) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _paymentLaunching || _refreshing
                  ? null
                  : () => _startPayment(booking),
              icon: _paymentLaunching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.payments_rounded, size: 18),
              label: Text(
                _paymentLaunching ? 'Opening payment…' : 'Complete payment',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: CarRentalColors.brandOrange,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _refreshing ? null : _refreshStatus,
            icon: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh payment status'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cancellationCard(CarHireBooking booking) {
    final cancelled = booking.bookingStatus == BookingStatus.cancelled;
    final canCancel = booking.canCancel;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Cancellation'),
          const SizedBox(height: 8),
          if (cancelled || booking.cancelledAt != null) ...[
            Text(
              booking.cancelledAt == null
                  ? 'This booking is cancelled.'
                  : 'Cancelled ${CarHireFormatters.formatDateTime(booking.cancelledAt!)}.',
              style: const TextStyle(
                color: CarRentalColors.body,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            if (booking.cancellationReason != null) ...[
              const SizedBox(height: 4),
              Text(
                'Reason: ${booking.cancellationReason}',
                style: const TextStyle(
                  color: CarRentalColors.body,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ] else if (canCancel) ...[
            const Text(
              'You can cancel a pending or confirmed booking before pick-up. '
              'This releases the dates; any refund follows the rental terms.',
              style: TextStyle(
                color: CarRentalColors.body,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _cancelling
                  ? null
                  : () => _cancelBooking(booking),
              icon: _cancelling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cancel_outlined, size: 18),
              label: Text(
                _cancelling ? 'Cancelling…' : 'Cancel booking',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: CarRentalColors.error,
                side: const BorderSide(color: CarRentalColors.error),
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ] else
            const Text(
              'This booking can no longer be cancelled from the app.',
              style: TextStyle(
                color: CarRentalColors.body,
                fontSize: 12,
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }

  Widget _supportCard(CarHireBooking booking) {
    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.support_agent_rounded,
            color: CarRentalColors.brandOrange,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Need help with this rental?',
                  style: TextStyle(
                    color: CarRentalColors.title,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Keep your booking number handy when contacting support.',
                  style: TextStyle(
                    color: CarRentalColors.body,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => _showSupportPlaceholder(booking),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: CarRentalColors.brandOrange,
                  ),
                  child: const Text('Contact support'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentPhoneDialog extends StatefulWidget {
  const _PaymentPhoneDialog();

  @override
  State<_PaymentPhoneDialog> createState() => _PaymentPhoneDialogState();
}

class _PaymentPhoneDialogState extends State<_PaymentPhoneDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Continue to payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter a mobile money number if your payment provider requires '
            'one. You can leave it blank.',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Mobile money number (optional)',
              hintText: '+265…',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE7DF)),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: CarRentalColors.title,
        fontSize: 14.5,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                color: CarRentalColors.grey,
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: CarRentalColors.title,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CarRentalColors.errorLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: CarRentalColors.error,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              UserFacingError.sanitize(message),
              style: const TextStyle(
                color: CarRentalColors.error,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
