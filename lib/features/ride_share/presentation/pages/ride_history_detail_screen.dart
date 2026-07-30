import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_completion_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_history_ui.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

enum RideHistoryPerspective { passenger, driver }

class RideHistoryDetailScreen extends StatelessWidget {
  final Ride ride;
  final RideHistoryPerspective perspective;

  const RideHistoryDetailScreen({
    super.key,
    required this.ride,
    required this.perspective,
  });

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
    final pending = ridePaymentPending(ride);
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
                          RideHistoryPaymentChip(pending: pending),
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
                            pending ? 'Amount due' : 'Total paid',
                            formatRideMoney(fare, money),
                            emphasize: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isDriver && pending) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RideCompletionScreen(
                                ride: ride,
                                onDone: () => Navigator.of(context).pop(),
                              ),
                            ),
                          );
                        },
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
