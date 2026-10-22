import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_price_breakdown.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_skeletons.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_status_badge.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
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
    final current =
        _localBooking ??
        ref
            .read(carHireBookingDetailProvider(widget.bookingId))
            .asData
            ?.value ??
        widget.initialBooking;
    if (current == null) return;

    setState(() {
      _refreshing = true;
      _actionError = null;
    });

    try {
      final fresh = await ref.read(carHireApiProvider).getBooking(current.id);
      if (!mounted) return;
      setState(() => _localBooking = fresh);
      ref.invalidate(myCarHireBookingsProvider);
      ref.invalidate(carHireBookingDetailProvider(widget.bookingId));

      ToastHelper.showToast(
        context,
        fresh.paymentSucceeded
            ? 'Payment confirmed.'
            : 'Payment not confirmed yet. Check again in a moment.',
      );
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
            'This releases your dates and cannot be undone. Refunds follow '
            'the rental terms.',
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
      final updated = await ref
          .read(carHireApiProvider)
          .cancelBooking(booking.id);
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
      final initiation = await ref
          .read(carHireApiProvider)
          .initiatePayment(booking.id, phoneNumber: phone);
      if (initiation.booking != null && mounted) {
        setState(() => _localBooking = initiation.booking);
      }

      final rawUrl = initiation.checkoutUrl?.trim();
      if (rawUrl == null || rawUrl.isEmpty) {
        if (!mounted) return;
        setState(() {
          _actionError =
              'The payment provider did not return a checkout link. '
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

  Future<void> _requestExtension(CarHireBooking booking) async {
    final currentEnd = booking.endAt;
    if (currentEnd == null) {
      setState(() {
        _actionError =
            'This booking does not have a return time, so it cannot be '
            'extended from the app. Contact support.';
      });
      return;
    }

    final now = DateTime.now();
    final earliest = currentEnd.isAfter(now) ? currentEnd : now;
    final initialDate = earliest.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(earliest.year, earliest.month, earliest.day),
      lastDate: earliest.add(const Duration(days: 90)),
      helpText: 'Select a new return date',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      helpText: 'Select a new return time',
    );
    if (time == null || !mounted) return;

    final requested = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!requested.isAfter(currentEnd)) {
      setState(() {
        _actionError =
            'Choose a return after ${CarHireFormatters.formatDateTime(currentEnd)}.';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Request an extension?'),
          content: Text(
            'Current return: '
            '${CarHireFormatters.formatDateTime(currentEnd)}.\n'
            'Requested return: '
            '${CarHireFormatters.formatDateTime(requested)}.\n\n'
            'The provider will review it. Any extra cost appears on this '
            'booking.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Send request'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionError = null);
    final extension = await ref
        .read(extensionRequestProvider.notifier)
        .request(bookingId: booking.id, requestedEndAt: requested);
    if (!mounted) return;

    if (extension != null) {
      ToastHelper.showToast(
        context,
        extension.hasAdditionalAmount
            ? 'Extension requested. Additional amount quoted: '
                  '${extension.additionalAmountLabel}.'
            : 'Extension requested. No additional amount was quoted.',
      );
      return;
    }

    final error = ref.read(extensionRequestProvider).error;
    if (error != null) {
      setState(() => _actionError = error.message);
    }
  }

  bool _canRecordInspection(CarHireBooking booking, InspectionType type) {
    switch (type) {
      case InspectionType.pickup:
        return booking.bookingStatus == BookingStatus.confirmed ||
            booking.bookingStatus == BookingStatus.active;
      case InspectionType.returnInspection:
        return booking.bookingStatus == BookingStatus.active;
      case InspectionType.unknown:
        return false;
    }
  }

  HandoverInspection? _latestInspection(
    AsyncValue<List<HandoverInspection>> async,
    InspectionType type,
  ) {
    final items = async.asData?.value;
    if (items == null) return null;
    HandoverInspection? latest;
    for (final inspection in items) {
      if (inspection.type != type) continue;
      if (latest == null) {
        latest = inspection;
        continue;
      }
      final current =
          inspection.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final previous =
          latest.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (current.isAfter(previous)) latest = inspection;
    }
    return latest;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(carHireBookingDetailProvider(widget.bookingId));
    final booking =
        _localBooking ?? async.asData?.value ?? widget.initialBooking;
    final extensions = ref.watch(bookingExtensionsProvider(widget.bookingId));
    final inspections = ref.watch(bookingInspectionsProvider(widget.bookingId));
    final extensionState = ref.watch(extensionRequestProvider);

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: 'Booking details',
        actions: [
          CarHireIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onTap: _refreshing ? () {} : _refresh,
            child: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: CarHirePalette.accent,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: booking == null
          ? async.when(
              skipLoadingOnRefresh: true,
              loading: () => const SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: ExcludeSemantics(child: CarHireCompanyBookingSkeleton()),
              ),
              error: (error, _) =>
                  CarHireErrorState(error: error, onRetry: _refresh),
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
                  _tripCard(booking),
                  const SizedBox(height: 12),
                  _paymentCard(booking),
                  const SizedBox(height: 12),
                  _inspectionsCard(booking, inspections),
                  if (booking.bookingStatus.isOpen ||
                      (extensions.asData?.value.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 12),
                    _extensionsCard(booking, extensions, extensionState),
                  ],
                  const SizedBox(height: 12),
                  _manageCard(booking),
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
          Text(booking.bookingNumberLabel, style: CarHireType.labelSmall),
          const SizedBox(height: 2),
          Text(
            booking.car?.title ?? 'Vehicle rental',
            style: CarHireType.titleLarge,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CarHireStatusBadge.booking(booking.bookingStatus),
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
                      'The hold on these dates has expired.',
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
          if (booking.bookingStatus == BookingStatus.pending &&
              !holdExpired) ...[
            const SizedBox(height: 10),
            _InfoRow(label: 'Hold until', value: booking.holdExpiryLabel),
          ],
          if (booking.cancelledAt != null) ...[
            const SizedBox(height: 10),
            _InfoRow(
              label: 'Cancelled',
              value: CarHireFormatters.formatDateTime(booking.cancelledAt!),
            ),
            if (booking.cancellationReason != null)
              _InfoRow(label: 'Reason', value: booking.cancellationReason!),
          ],
        ],
      ),
    );
  }

  Widget _tripCard(CarHireBooking booking) {
    final car = booking.car;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (car != null) ...[
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
                      if (car.provider != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          car.providerLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CarRentalColors.body,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
            const SizedBox(height: 12),
            const Divider(height: 1, color: CarHirePalette.hairline),
            const SizedBox(height: 10),
          ],
          if (booking.assignedPlate != null)
            _InfoRow(
              label: 'Vehicle',
              value: [
                booking.assignedPlate!,
                if (booking.assignedColor != null) booking.assignedColor!,
              ].join(' · '),
            ),
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
          if (booking.driverName != null)
            _InfoRow(label: 'Driver', value: booking.driverName!),
          if (booking.renterNotes != null)
            _InfoRow(label: 'Note', value: booking.renterNotes!),
        ],
      ),
    );
  }

  Widget _inspectionsCard(
    CarHireBooking booking,
    AsyncValue<List<HandoverInspection>> inspections,
  ) {
    final pickup = _latestInspection(inspections, InspectionType.pickup);
    final returnInspection = _latestInspection(
      inspections,
      InspectionType.returnInspection,
    );
    final canPickup = _canRecordInspection(booking, InspectionType.pickup);
    final canReturn = _canRecordInspection(
      booking,
      InspectionType.returnInspection,
    );
    final items = inspections.asData?.value ?? const <HandoverInspection>[];
    final awaitingDecision = items
        .where((inspection) => inspection.awaitingRenterDecision)
        .length;
    final disputed = items.where((inspection) => inspection.isDisputed).length;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Handover inspections'),
          const SizedBox(height: 10),
          _inspectionSummaryRow('Pick-up', pickup),
          const SizedBox(height: 6),
          _inspectionSummaryRow('Return', returnInspection),
          if (inspections.isLoading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(
              minHeight: 2,
              color: CarRentalColors.brandOrange,
              backgroundColor: CarRentalColors.brandOrangePale,
            ),
          ],
          if (inspections.hasError) ...[
            const SizedBox(height: 10),
            CarHireInlineError(
              message: inspections.error is CarHireApiException
                  ? (inspections.error as CarHireApiException).message
                  : UserFacingError.from(inspections.error!),
              onRetry: () =>
                  ref.invalidate(bookingInspectionsProvider(widget.bookingId)),
            ),
          ],
          if (awaitingDecision > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CarRentalColors.warningLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.pending_actions_rounded,
                    size: 16,
                    color: CarRentalColors.greyDark,
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'The provider recorded an inspection. Open it to accept '
                      'or decline.',
                      style: TextStyle(
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
          if (disputed > 0) ...[
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
                    Icons.report_problem_outlined,
                    size: 16,
                    color: CarRentalColors.error,
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'An inspection is disputed. Support can review it.',
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canPickup
                      ? () => CarHireRoutes.openInspection(
                          context,
                          bookingId: booking.id,
                          type: InspectionType.pickup,
                          booking: booking,
                        )
                      : null,
                  icon: const Icon(Icons.login_rounded, size: 17),
                  label: const Text('Pick-up'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canReturn
                      ? () => CarHireRoutes.openInspection(
                          context,
                          bookingId: booking.id,
                          type: InspectionType.returnInspection,
                          booking: booking,
                        )
                      : null,
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  label: const Text('Return'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
          ),
          if (!canPickup && !canReturn && booking.bookingStatus.isOpen) ...[
            const SizedBox(height: 6),
            const Text(
              'Available once the booking is confirmed.',
              style: TextStyle(
                color: CarRentalColors.grey,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _inspectionSummaryRow(String label, HandoverInspection? inspection) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: const TextStyle(color: CarRentalColors.grey, fontSize: 11.5),
          ),
        ),
        Expanded(
          child: Text(
            inspection == null
                ? 'Not recorded'
                : '${inspection.actorLabel} · ${inspection.createdAtLabel}',
            style: TextStyle(
              color: inspection == null
                  ? CarRentalColors.body
                  : CarRentalColors.title,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
        if (inspection != null) ...[
          const SizedBox(width: 8),
          Flexible(child: CarHireStatusBadge.inspection(inspection.status)),
        ],
      ],
    );
  }

  Widget _extensionsCard(
    CarHireBooking booking,
    AsyncValue<List<BookingExtension>> extensions,
    CarHireMutationState extensionState,
  ) {
    final items = extensions.asData?.value ?? const <BookingExtension>[];

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Need it longer?'),
          const SizedBox(height: 10),
          if (extensions.isLoading)
            const LinearProgressIndicator(
              minHeight: 2,
              color: CarRentalColors.brandOrange,
              backgroundColor: CarRentalColors.brandOrangePale,
            )
          else if (extensions.hasError)
            CarHireInlineError(
              message: extensions.error is CarHireApiException
                  ? (extensions.error as CarHireApiException).message
                  : UserFacingError.from(extensions.error!),
              onRetry: () =>
                  ref.invalidate(bookingExtensionsProvider(widget.bookingId)),
            )
          else if (items.isEmpty)
            const SizedBox.shrink()
          else
            for (final extension in items)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CarRentalColors.greyLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CarHirePalette.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            'Return ${extension.requestedEndLabel}',
                            style: const TextStyle(
                              color: CarRentalColors.title,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: CarHireStatusBadge.extension(extension.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      extension.hasAdditionalAmount
                          ? 'Additional amount quoted: '
                                '${extension.additionalAmountLabel}'
                          : 'No additional amount was quoted.',
                      style: const TextStyle(
                        color: CarRentalColors.body,
                        fontSize: 11.5,
                      ),
                    ),
                    if (extension.decisionReason != null &&
                        extension.decisionReason!.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Reason: ${extension.decisionReason!.trim()}',
                        style: const TextStyle(
                          color: CarRentalColors.error,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          if (extensionState.hasError) ...[
            const SizedBox(height: 8),
            CarHireInlineError(message: extensionState.error!.message),
          ],
          if (booking.bookingStatus.isOpen && booking.endAt != null)
            OutlinedButton.icon(
              onPressed: extensionState.submitting
                  ? null
                  : () => _requestExtension(booking),
              icon: extensionState.submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.more_time_rounded, size: 18),
              label: Text(
                extensionState.submitting
                    ? 'Sending request…'
                    : 'Request extension',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
        ],
      ),
    );
  }

  Widget _paymentCard(CarHireBooking booking) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total', style: CarHireType.labelSmall),
                    const SizedBox(height: 2),
                    Text(booking.totalLabel, style: CarHireType.priceSmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: CarHireStatusBadge.payment(booking.paymentStatus),
              ),
            ],
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              dense: true,
              iconColor: CarRentalColors.title,
              collapsedIconColor: CarRentalColors.grey,
              title: const Text(
                'Price breakdown',
                style: TextStyle(
                  color: CarRentalColors.title,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              children: [
                CarHirePriceBreakdown.booking(booking),
                if (booking.paymentReference != null) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Reference',
                    value: booking.paymentReference!,
                  ),
                ],
              ],
            ),
          ),
          if (booking.canPay) ...[
            const SizedBox(height: 4),
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
              style: carHirePrimaryButton(),
            ),
          ],
          if (!booking.paymentSucceeded &&
              booking.paymentStatus == PaymentStatus.pending) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _refreshing ? null : _refreshStatus,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text("I've paid · Check status"),
              style: TextButton.styleFrom(
                foregroundColor: CarRentalColors.title,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _manageCard(CarHireBooking booking) {
    final canCancel =
        booking.canCancel && booking.bookingStatus != BookingStatus.cancelled;

    return CarHireSurface(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          _ManageTile(
            icon: Icons.report_problem_outlined,
            label: 'Report an issue',
            onTap: () => CarHireRoutes.openReport(
              context,
              bookingId: booking.id,
              initialTab: 0,
              bookingNumber: booking.bookingNumber,
            ),
          ),
          _ManageTile(
            icon: Icons.support_agent_rounded,
            label: 'Get help',
            onTap: () => CarHireRoutes.openReport(
              context,
              bookingId: booking.id,
              initialTab: 1,
              bookingNumber: booking.bookingNumber,
            ),
          ),
          _ManageTile(
            icon: Icons.description_outlined,
            label: 'Rental terms',
            onTap: () => CarHireRoutes.openTerms(context),
          ),
          if (canCancel)
            _ManageTile(
              icon: Icons.cancel_outlined,
              label: _cancelling ? 'Cancelling…' : 'Cancel booking',
              color: CarRentalColors.error,
              onTap: _cancelling ? null : () => _cancelBooking(booking),
            ),
        ],
      ),
    );
  }
}

class _ManageTile extends StatelessWidget {
  const _ManageTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = CarRentalColors.title,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: CarRentalColors.grey,
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
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Mobile money number (optional)',
          hintText: '+265…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
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
    return CarHireSurface(padding: const EdgeInsets.all(16), child: child);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: CarHireType.title);
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
