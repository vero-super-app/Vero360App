import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_price_breakdown.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_status_badge.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/user_facing_error.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

class CarHireCheckoutPage extends ConsumerStatefulWidget {
  const CarHireCheckoutPage({
    super.key,
    required this.car,
    required this.startAt,
    required this.endAt,
  });

  final CarListing car;
  final DateTime startAt;
  final DateTime endAt;

  @override
  ConsumerState<CarHireCheckoutPage> createState() =>
      _CarHireCheckoutPageState();
}

class _CarHireCheckoutPageState extends ConsumerState<CarHireCheckoutPage>
    with WidgetsBindingObserver {
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _driverController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  bool _termsAccepted = false;
  bool _paymentLaunching = false;
  bool _refreshingStatus = false;
  bool _awaitingPaymentReturn = false;
  String? _paymentError;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    Future<void>.microtask(_loadQuote);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _notesController.dispose();
    _driverController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingPaymentReturn) {
      _awaitingPaymentReturn = false;
      _refreshBookingStatus();
    }
  }

  Future<void> _loadQuote() async {
    // A fresh checkout must not inherit a booking from a previous journey.
    ref.read(bookingSubmissionProvider.notifier).reset();
    await ref.read(quoteControllerProvider.notifier).requestQuote(
          carId: widget.car.id,
          startAt: widget.startAt,
          endAt: widget.endAt,
        );
  }

  Future<void> _submitBooking() async {
    final quote = ref.read(quoteControllerProvider).quote;
    if (quote == null || quote.isExpired) return;

    FocusScope.of(context).unfocus();
    final booking = await ref.read(bookingSubmissionProvider.notifier).submit(
          quoteId: quote.quoteId,
          renterNotes: _notesController.text,
          driverName: _driverController.text,
        );
    if (!mounted) return;

    if (booking != null) {
      setState(() => _paymentError = null);
      return;
    }

    final error = ref.read(bookingSubmissionProvider).error;
    if (error != null) {
      _snack(error.message);
    }
  }

  Future<void> _payNow() async {
    final booking = ref.read(bookingSubmissionProvider).booking;
    if (booking == null) return;

    setState(() {
      _paymentLaunching = true;
      _paymentError = null;
    });

    try {
      final initiation = await ref.read(carHireApiProvider).initiatePayment(
            booking.id,
            phoneNumber: _phoneController.text,
          );
      if (initiation.booking != null && mounted) {
        ref
            .read(bookingSubmissionProvider.notifier)
            .updateBooking(initiation.booking!);
      }

      final url = initiation.checkoutUrl?.trim();
      if (url == null || url.isEmpty) {
        if (!mounted) return;
        setState(() {
          _paymentError =
              'The payment provider did not return a checkout link. '
              'Please try again.';
        });
        return;
      }

      final uri = Uri.tryParse(url);
      if (uri == null) {
        if (!mounted) return;
        setState(() {
          _paymentError = 'The payment link was not valid. Please try again.';
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
          _paymentError =
              'We could not open the payment page. Please try again.';
        });
        return;
      }

      setState(() => _awaitingPaymentReturn = true);
    } on CarHireApiException catch (error) {
      if (!mounted) return;
      setState(() => _paymentError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _paymentError = UserFacingError.from(error));
    } finally {
      if (mounted) setState(() => _paymentLaunching = false);
    }
  }

  Future<void> _refreshBookingStatus() async {
    final current = ref.read(bookingSubmissionProvider).booking;
    if (current == null) return;

    setState(() {
      _refreshingStatus = true;
      _paymentError = null;
    });

    try {
      final fresh = await ref.read(carHireApiProvider).getBooking(current.id);
      ref.read(bookingSubmissionProvider.notifier).updateBooking(fresh);
      if (!mounted) return;

      if (fresh.paymentSucceeded) {
        ToastHelper.showToast(
          context,
          'Payment confirmed by Vero360. Booking status: '
          '${fresh.bookingStatus.label}.',
        );
      } else {
        ToastHelper.showToast(
          context,
          'We have not received payment confirmation yet. '
          'Your payment status is still "${fresh.paymentLabel}".',
        );
      }
    } on CarHireApiException catch (error) {
      if (!mounted) return;
      setState(() => _paymentError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _paymentError = UserFacingError.from(error));
    } finally {
      if (mounted) setState(() => _refreshingStatus = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(UserFacingError.sanitize(message)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _countdown(DateTime? expiresAt) {
    if (expiresAt == null) return '—';
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    if (remaining.inHours >= 1) {
      return '${remaining.inHours}h ${remaining.inMinutes % 60}m';
    }
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final quoteState = ref.watch(quoteControllerProvider);
    final submission = ref.watch(bookingSubmissionProvider);
    final booking = submission.booking;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: CarRentalColors.title,
        elevation: 0.4,
        scrolledUnderElevation: 0.4,
        title: Text(
          booking == null ? 'Checkout' : 'Your booking',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (booking != null)
            IconButton(
              tooltip: 'Refresh booking status',
              icon: _refreshingStatus
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              onPressed: _refreshingStatus ? null : _refreshBookingStatus,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            _CarSummaryCard(
              car: widget.car,
              startAt: widget.startAt,
              endAt: widget.endAt,
            ),
            const SizedBox(height: 14),
            if (booking == null)
              _quoteCard(quoteState)
            else
              _bookingCreatedCard(booking),
            if (booking != null) ...[
              const SizedBox(height: 14),
              _paymentCard(booking),
            ],
            if (booking == null) ...[
              const SizedBox(height: 14),
              _detailsCard(),
              const SizedBox(height: 14),
              _termsCard(),
            ],
            const SizedBox(height: 8),
            const Text(
              'Vero360 never treats a browser redirect as proof of payment. '
              'Your booking is updated from the server after the payment '
              'provider confirms it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CarRentalColors.grey,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: booking == null ? _submitBar(quoteState) : null,
    );
  }

  Widget _quoteCard(CarHireQuoteState quoteState) {
    if (quoteState.loading) {
      return const _Panel(
        child: CarHireLoadingState(
          message: 'Preparing your price for these dates…',
          padding: EdgeInsets.symmetric(vertical: 22),
        ),
      );
    }

    final error = quoteState.error;
    if (error != null) {
      return _Panel(
        child: Column(
          children: [
            CarHireErrorState(
              error: error,
              onRetry: _loadQuote,
              retryLabel: 'Try again',
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            if (error.isConflict || error.isQuoteExpired)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Change dates'),
              ),
          ],
        ),
      );
    }

    final quote = quoteState.quote;
    if (quote == null) {
      return _Panel(
        child: Column(
          children: [
            const Text(
              'No quote yet.',
              style: TextStyle(
                color: CarRentalColors.body,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _loadQuote,
              child: const Text('Get a quote'),
            ),
          ],
        ),
      );
    }

    final remaining = quote.remaining;
    final expiringSoon = remaining != null && remaining.inMinutes < 3;
    final expired = quote.isExpired;
    final verification = ref.watch(verificationProvider).asData?.value;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Price breakdown',
                  style: TextStyle(
                    color: CarRentalColors.title,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: expired
                      ? CarRentalColors.errorLight
                      : expiringSoon
                          ? CarRentalColors.warningLight
                          : CarRentalColors.successLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      expired
                          ? Icons.timer_off_rounded
                          : Icons.timer_outlined,
                      size: 13,
                      color: expired
                          ? CarRentalColors.error
                          : expiringSoon
                              ? CarRentalColors.greyDark
                              : CarRentalColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      expired
                          ? 'Quote expired'
                          : 'Expires in ${_countdown(quote.expiresAt)}',
                      style: TextStyle(
                        color: expired
                            ? CarRentalColors.error
                            : expiringSoon
                                ? CarRentalColors.greyDark
                                : CarRentalColors.success,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${quote.days} day${quote.days == 1 ? '' : 's'} at '
            '${quote.dailyRateLabel}. Expires ${quote.expiryLabel}.',
            style: const TextStyle(
              color: CarRentalColors.body,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          CarHirePriceBreakdown.quote(quote),
          if (expired) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: CarRentalColors.errorLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: CarRentalColors.error,
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'This quote has expired and can no longer be booked. '
                      'Get a fresh quote to continue with current pricing and '
                      'availability.',
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
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loadQuote,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Get a new quote'),
            ),
          ],
          if (verification != null && verification.needsAttention) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: CarRentalColors.warningLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 16,
                    color: CarRentalColors.greyDark,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Driver verification: ${verification.statusLabel}.'
                      '${verification.nextAction == null ? '' : ' ${verification.nextAction}'}',
                      style: const TextStyle(
                        color: CarRentalColors.greyDark,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bookingCreatedCard(CarHireBooking booking) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: booking.paymentSucceeded
                      ? CarRentalColors.successLight
                      : CarRentalColors.brandOrangePale,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  booking.paymentSucceeded
                      ? Icons.verified_rounded
                      : Icons.receipt_long_rounded,
                  color: booking.paymentSucceeded
                      ? CarRentalColors.success
                      : CarRentalColors.brandOrange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.paymentSucceeded
                          ? 'Payment confirmed'
                          : 'Booking created',
                      style: const TextStyle(
                        color: CarRentalColors.title,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      booking.bookingNumberLabel,
                      style: const TextStyle(
                        color: CarRentalColors.body,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CarHireStatusBadge.booking(booking.bookingStatus),
              CarHireStatusBadge.payment(booking.paymentStatus),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Dates', value: booking.dateRangeLabel),
          _InfoRow(label: 'Total', value: booking.totalLabel),
          _InfoRow(label: 'Hold', value: booking.holdExpiryLabel),
          if (booking.nextActionLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              booking.nextActionLabel!,
              style: const TextStyle(
                color: CarRentalColors.body,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => CarHireRoutes.openBookingDetail(
              context,
              bookingId: booking.id,
              initialBooking: booking,
              replace: true,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 17),
            label: const Text('View booking'),
          ),
        ],
      ),
    );
  }

  Widget _paymentCard(CarHireBooking booking) {
    if (booking.paymentSucceeded) {
      return _Panel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.verified_rounded,
              color: CarRentalColors.success,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payment received',
                    style: TextStyle(
                      color: CarRentalColors.title,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'The payment provider confirmed this payment with '
                    'Vero360. Booking status: ${booking.bookingStatus.label}.',
                    style: const TextStyle(
                      color: CarRentalColors.body,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Payment',
            style: TextStyle(
              color: CarRentalColors.title,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Status: ${booking.paymentLabel}. Pay with PayChangu to complete '
            'your booking. Payment is confirmed by Vero360, not by returning '
            'to the app.',
            style: const TextStyle(
              color: CarRentalColors.body,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Mobile money number (optional)',
              hintText: '+265…',
              filled: true,
              fillColor: CarRentalColors.greyLight,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _paymentLaunching || !booking.canPay ? null : _payNow,
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
              _paymentLaunching ? 'Opening payment…' : 'Pay now',
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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _refreshingStatus ? null : _refreshBookingStatus,
            icon: _refreshingStatus
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('I have paid — refresh status'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
          if (_paymentError != null) ...[
            const SizedBox(height: 10),
            _InlineError(message: _paymentError!),
          ],
          if (!booking.canPay) ...[
            const SizedBox(height: 8),
            Text(
              booking.bookingStatus.isTerminal
                  ? 'This booking can no longer be paid.'
                  : 'No payment is currently due for this booking.',
              style: const TextStyle(
                color: CarRentalColors.grey,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailsCard() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Driver details',
            style: TextStyle(
              color: CarRentalColors.title,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _driverController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Driver name (optional)',
              filled: true,
              fillColor: CarRentalColors.greyLight,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Notes for the provider (optional)',
              hintText: 'For example: call on arrival',
              alignLabelWithHint: true,
              filled: true,
              fillColor: CarRentalColors.greyLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _termsCard() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Rental and cancellation terms',
            style: TextStyle(
              color: CarRentalColors.title,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'By submitting, you request this vehicle for the selected dates. '
            'A pending booking holds the dates until the hold expiry shown on '
            'the booking; if payment is not completed, the hold may expire. '
            'The deposit shown above (if any) is collected according to the '
            "vehicle's terms. Cancelling a pending booking releases the hold; "
            'confirmed bookings may be subject to the provider\'s cancellation '
            'policy. Payment is only treated as successful after Vero360 '
            'verifies it with the payment provider.',
            style: TextStyle(
              color: CarRentalColors.body,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _termsAccepted,
            onChanged: (value) {
              setState(() => _termsAccepted = value ?? false);
            },
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: CarRentalColors.brandOrange,
            title: const Text(
              'I have read and accept the rental and cancellation terms.',
              style: TextStyle(
                color: CarRentalColors.title,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _submitBar(CarHireQuoteState quoteState) {
    final submission = ref.watch(bookingSubmissionProvider);
    final quote = quoteState.quote;
    final canSubmit = quote != null &&
        !quote.isExpired &&
        _termsAccepted &&
        !submission.submitting &&
        quoteState.error == null;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: Color(0xFFEDE7DF))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total due now',
                    style: TextStyle(
                      color: CarRentalColors.body,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  quote == null
                      ? '—'
                      : CarHireFormatters.formatCurrency(quote.totalDueNow),
                  style: const TextStyle(
                    color: CarRentalColors.title,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: FilledButton(
                onPressed: canSubmit ? _submitBooking : null,
                style: FilledButton.styleFrom(
                  backgroundColor: CarRentalColors.brandOrange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      CarRentalColors.brandOrange.withValues(alpha: 0.4),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: submission.submitting
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 9),
                          Text('Creating booking…'),
                        ],
                      )
                    : const Text('Submit booking request'),
              ),
            ),
            if (quote != null && quote.isExpired)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Get a new quote before submitting.',
                  style: TextStyle(
                    color: CarRentalColors.error,
                    fontSize: 10.5,
                  ),
                ),
              )
            else if (!_termsAccepted)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Accept the rental terms to continue.',
                  style: TextStyle(
                    color: CarRentalColors.grey,
                    fontSize: 10.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CarSummaryCard extends StatelessWidget {
  const _CarSummaryCard({
    required this.car,
    required this.startAt,
    required this.endAt,
  });

  final CarListing car;
  final DateTime startAt;
  final DateTime endAt;

  @override
  Widget build(BuildContext context) {
    final image = car.primaryImage;

    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 84,
              height: 68,
              child: image == null || image.isEmpty
                  ? Container(
                      color: CarRentalColors.chip,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.directions_car_filled_rounded,
                        color: CarRentalColors.grey,
                      ),
                    )
                  : ResilientCachedNetworkImage(
                      url: image,
                      fit: BoxFit.cover,
                      width: 84,
                      height: 68,
                      memCacheWidth: 260,
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
                const SizedBox(height: 3),
                Text(
                  CarHireFormatters.formatDateTime(startAt),
                  style: const TextStyle(
                    color: CarRentalColors.body,
                    fontSize: 11.5,
                  ),
                ),
                Text(
                  'to ${CarHireFormatters.formatDateTime(endAt)}',
                  style: const TextStyle(
                    color: CarRentalColors.body,
                    fontSize: 11.5,
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
            width: 72,
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
