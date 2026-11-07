import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_completion_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_history_ui.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

enum RideHistoryPerspective { passenger, driver }

class RideHistoryDetailScreen extends StatefulWidget {
  final Ride ride;
  final RideHistoryPerspective perspective;

  const RideHistoryDetailScreen({
    super.key,
    required this.ride,
    required this.perspective,
  });

  @override
  State<RideHistoryDetailScreen> createState() =>
      _RideHistoryDetailScreenState();
}

class _RideHistoryDetailScreenState extends State<RideHistoryDetailScreen> {
  late Ride ride;
  bool _submittingDispute = false;

  @override
  void initState() {
    super.initState();
    ride = widget.ride;
  }

  RideHistoryPerspective get perspective => widget.perspective;

  Future<void> _openPayment() async {
    final paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RideCompletionScreen(
          ride: ride,
          onDone: () {},
        ),
      ),
    );
    if (!mounted) return;
    try {
      final fresh = await RideShareHttpService().getRideDetails(ride.id);
      if (!mounted) return;
      setState(() => ride = fresh);
    } catch (_) {
      if (paid == true && mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _reportProblem() async {
    if (ride.hasDispute || _submittingDispute) return;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report a problem'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Briefly describe what went wrong',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.length < 3 || !mounted) return;

    setState(() => _submittingDispute = true);
    try {
      final updated = await RideShareHttpService().reportRideDispute(
        ride.id,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        ride = updated;
        _submittingDispute = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Problem reported. Thanks.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submittingDispute = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.from(e, fallback: 'Could not submit report'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0', 'en');
    final summary = ride.tripSummary;
    final fare = summary?.fare ?? ride.resolvedFare;
    final distance = summary?.distance ?? ride.resolvedDistance;
    final duration = summary?.durationMinutes ??
        (ride.startTime != null && ride.endTime != null
            ? ride.endTime!.difference(ride.startTime!).inMinutes
            : 0);
    final platformFee = summary?.platformFee ?? ride.platformFee ?? 0;
    final driverEarnings =
        summary?.driverEarnings ?? ride.driverEarnings ?? (fare - platformFee);
    final when = ride.endTime ?? ride.createdAt;
    final isDriver = perspective == RideHistoryPerspective.driver;
    final pending = ride.needsPayment;
    final unsettled = ride.isSettlementPending;
    final counterpart = rideCounterpartName(ride, isDriver: isDriver);
    final vehicle = rideVehicleLabel(ride);
    final pickup = summary?.pickup ?? ride.pickupAddress ?? 'Pickup';
    final dropoff = summary?.dropoff ?? ride.dropoffAddress ?? 'Dropoff';

    return Scaffold(
      backgroundColor: RideShareColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    style: IconButton.styleFrom(
                      backgroundColor: RideShareColors.surfaceContainerLow,
                      shape: const CircleBorder(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isDriver ? 'Trip Earnings' : 'Trip Receipt',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: RideShareColors.titleText,
                      ),
                    ),
                  ),
                  RideHistoryStatusChip(status: ride.status),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          RideShareColors.primary,
                          RideShareColors.primaryDeep,
                          RideShareColors.primaryDark,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: RideShareColors.primary
                              .withValues(alpha: 0.28),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatRideWhen(when),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formatRideMoney(
                            isDriver ? driverEarnings : fare,
                            money,
                          ),
                          style: const TextStyle(
                            color: RideShareColors.primary,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          isDriver ? 'You earned' : 'Trip total',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 16),
                        RideHistoryRouteTimeline(
                          pickup: pickup,
                          dropoff: dropoff,
                          dark: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _card(
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor:
                              RideShareColors.primary.withValues(alpha: 0.15),
                          child: Text(
                            counterpart.isNotEmpty
                                ? counterpart[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: RideShareColors.primaryDeep,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                counterpart,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: RideShareColors.titleText,
                                ),
                              ),
                              Text(
                                vehicle,
                                style: const TextStyle(
                                  color: RideShareColors.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (ride.isCompleted)
                          RideHistoryPaymentChip(
                            pending: unsettled,
                            pendingLabel: ride.isCashPayment
                                ? 'Cash pending'
                                : 'Payment pending',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trip Summary',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _kv('Ride ID', '#${ride.id}'),
                        _kv('Distance', '${distance.toStringAsFixed(1)} km'),
                        _kv(
                          'Duration',
                          duration > 0 ? '$duration min' : '—',
                        ),
                        if (ride.fareBasisLabel != null)
                          _kv('Fare basis', ride.fareBasisLabel!),
                        if (ride.paidAt != null)
                          _kv(
                            'Paid on',
                            DateFormat('dd MMM yyyy, HH:mm')
                                .format(ride.paidAt!),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isDriver ? 'Earnings breakdown' : 'Fare breakdown',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _kv('Trip fare', formatRideMoney(fare, money)),
                        if (ride.hasCancellationFee)
                          _kv(
                            'Cancellation fee',
                            formatRideMoney(ride.cancellationFee!, money),
                          ),
                        if (isDriver) ...[
                          _kv(
                            'Platform fee',
                            formatRideMoney(platformFee, money),
                          ),
                          const Divider(height: 22),
                          _kv(
                            'You earned',
                            formatRideMoney(driverEarnings, money),
                            emphasize: true,
                          ),
                        ] else ...[
                          const Divider(height: 22),
                          _kv(
                            unsettled ? 'Amount due' : 'Total paid',
                            formatRideMoney(fare, money),
                            emphasize: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isDriver && ride.isCashPayment && unsettled) ...[
                    const SizedBox(height: 18),
                    _card(
                      child: Text(
                        'Pay the driver in cash. They will confirm when they receive it. You can book another ride now.',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                  if (!isDriver && pending) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _openPayment,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: RideShareColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text(
                          'Pay Now',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if ((ride.isCompleted || ride.isCancelled) &&
                      !ride.hasDispute) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _submittingDispute ? null : _reportProblem,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: RideShareColors.primaryDeep,
                          side: const BorderSide(
                            color: RideShareColors.outlineVariant,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _submittingDispute
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.flag_outlined, size: 18),
                        label: Text(
                          _submittingDispute
                              ? 'Submitting…'
                              : 'Report a problem',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                  if (ride.hasDispute) ...[
                    const SizedBox(height: 14),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Problem reported',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ride.disputeReason ?? 'Submitted',
                            style: const TextStyle(
                              color: RideShareColors.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RideShareColors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: RideShareColors.primaryContainer.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _kv(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: RideShareColors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
              color: emphasize
                  ? RideShareColors.primary
                  : RideShareColors.titleText,
              fontSize: emphasize ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
