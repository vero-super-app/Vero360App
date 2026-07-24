import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

bool ridePaymentPending(Ride ride) => ride.needsPayment;

String rideCounterpartName(Ride ride, {required bool isDriver}) {
  final summaryName = ride.tripSummary?.counterpartyName?.trim();
  if (summaryName != null && summaryName.isNotEmpty) return summaryName;
  if (isDriver) {
    final name = ride.passengerName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Passenger';
  }
  final driver = ride.driver?.fullName.trim();
  if (driver != null && driver.isNotEmpty) return driver;
  return 'Driver';
}

String rideVehicleLabel(Ride ride) {
  final plate = ride.tripSummary?.vehiclePlate ?? ride.taxi?.licensePlate;
  final cls = ride.tripSummary?.vehicleClass ?? ride.taxi?.vehicleClass;
  final make = ride.taxi?.make;
  final color = ride.taxi?.color;
  final parts = <String>[
    if (make != null && make.isNotEmpty) make,
    if (color != null && color.isNotEmpty) color,
    if ((make == null || make.isEmpty) &&
        cls != null &&
        cls.isNotEmpty)
      cls,
    if (plate != null && plate.isNotEmpty) plate,
  ];
  if (parts.isEmpty) return 'Vero Ride';
  return parts.join(' • ');
}

String formatRideMoney(num amount, NumberFormat money) =>
    'MK ${money.format(amount)}';

String formatRideWhen(DateTime when) {
  final now = DateTime.now();
  final local = when.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final time = DateFormat('hh:mm a').format(local);
  if (day == today) return 'Today, $time';
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Yesterday, $time';
  }
  return DateFormat('MMM d, hh:mm a').format(local);
}

class RideHistoryStatusChip extends StatelessWidget {
  final String status;
  final bool compact;

  const RideHistoryStatusChip({
    required this.status,
    this.compact = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final s = status.toUpperCase();
    Color bg;
    Color fg;
    String label;
    switch (s) {
      case RideStatus.completed:
        bg = RideShareColors.primarySoft;
        fg = RideShareColors.primaryDeep;
        label = 'Completed';
      case RideStatus.cancelled:
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
        label = 'Cancelled';
      case RideStatus.inProgress:
        bg = RideShareColors.primaryContainer.withValues(alpha: 0.12);
        fg = RideShareColors.primaryContainer;
        label = 'In progress';
      default:
        bg = RideShareColors.surfaceContainer;
        fg = RideShareColors.onSurfaceVariant;
        label = s.isEmpty ? 'Unknown' : s.replaceAll('_', ' ').toLowerCase();
        label = label[0].toUpperCase() + label.substring(1);
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class RideHistoryPaymentChip extends StatelessWidget {
  final bool pending;

  const RideHistoryPaymentChip({required this.pending, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: pending
            ? const Color(0xFFFFEBEE)
            : RideShareColors.primarySoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        pending ? 'Payment Pending' : 'Paid',
        style: TextStyle(
          color: pending
              ? const Color(0xFFC62828)
              : RideShareColors.primaryDeep,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class RideHistoryRouteTimeline extends StatelessWidget {
  final String pickup;
  final String dropoff;
  final bool compact;
  final bool dark;

  const RideHistoryRouteTimeline({
    required this.pickup,
    required this.dropoff,
    this.compact = false,
    this.dark = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final muted = dark
        ? Colors.white.withValues(alpha: 0.65)
        : RideShareColors.onSurfaceVariant;
    final strong = dark ? Colors.white : RideShareColors.titleText;

    return Stack(
      children: [
        Positioned(
          left: 9,
          top: 18,
          bottom: 18,
          child: Container(
            width: 2,
            color: dark
                ? Colors.white.withValues(alpha: 0.2)
                : RideShareColors.outlineVariant,
          ),
        ),
        Column(
          children: [
            _stop(
              label: 'Pick-up',
              address: pickup,
              muted: muted,
              strong: strong,
              marker: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: RideShareColors.primaryContainer,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 10 : 14),
            _stop(
              label: 'Drop-off',
              address: dropoff,
              muted: muted,
              strong: strong,
              marker: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: RideShareColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stop({
    required String label,
    required String address,
    required Color muted,
    required Color strong,
    required Widget marker,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        marker,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              Text(
                address,
                style: TextStyle(
                  fontSize: compact ? 13 : 15,
                  fontWeight: FontWeight.w600,
                  color: strong,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Stunning trip card for passenger & driver history lists.
class RideHistoryTripCard extends StatelessWidget {
  final Ride ride;
  final bool isDriver;
  final NumberFormat money;
  final VoidCallback onTap;
  final VoidCallback? onPrimaryAction;

  const RideHistoryTripCard({
    required this.ride,
    required this.isDriver,
    required this.money,
    required this.onTap,
    this.onPrimaryAction,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final summary = ride.tripSummary;
    final amount = isDriver
        ? (summary?.driverEarnings ??
            ride.driverEarnings ??
            ride.resolvedFare)
        : (summary?.fare ?? ride.resolvedFare);
    final when = ride.endTime ?? ride.createdAt;
    final pending = ridePaymentPending(ride);
    final counterpart = rideCounterpartName(ride, isDriver: isDriver);
    final vehicle = rideVehicleLabel(ride);
    final pickup = summary?.pickup ?? ride.pickupAddress ?? 'Pickup';
    final dropoff = summary?.dropoff ?? ride.dropoffAddress ?? 'Dropoff';
    final highlightUnpaid = !isDriver && pending;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: highlightUnpaid
                  ? RideShareColors.primary.withValues(alpha: 0.35)
                  : RideShareColors.outlineVariant,
            ),
            boxShadow: [
              BoxShadow(
                color: RideShareColors.primaryContainer.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          foregroundDecoration: highlightUnpaid
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: const Border(
                    left: BorderSide(
                      color: RideShareColors.primary,
                      width: 4,
                    ),
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isDriver)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          RideShareColors.primary.withValues(alpha: 0.12),
                      child: Text(
                        counterpart.isNotEmpty
                            ? counterpart[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: RideShareColors.primaryDeep,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            counterpart,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: RideShareColors.titleText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            formatRideWhen(when),
                            style: const TextStyle(
                              color: RideShareColors.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatRideMoney(amount, money),
                          style: const TextStyle(
                            color: RideShareColors.titleText,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (ride.isCompleted && pending)
                          const RideHistoryPaymentChip(pending: true)
                        else
                          RideHistoryStatusChip(
                            status: ride.status,
                            compact: true,
                          ),
                      ],
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (highlightUnpaid)
                                const Text(
                                  'ATTENTION REQUIRED',
                                  style: TextStyle(
                                    color: RideShareColors.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              Text(
                                formatRideWhen(when),
                                style: TextStyle(
                                  color: highlightUnpaid
                                      ? RideShareColors.titleText
                                      : RideShareColors.onSurfaceVariant,
                                  fontSize: highlightUnpaid ? 17 : 13,
                                  fontWeight: highlightUnpaid
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                              if (!highlightUnpaid) ...[
                                const SizedBox(height: 2),
                                Text(
                                  vehicle,
                                  style: const TextStyle(
                                    color: RideShareColors.titleText,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          formatRideMoney(amount, money),
                          style: const TextStyle(
                            color: RideShareColors.titleText,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: RideShareColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: highlightUnpaid ? 22 : 18,
                            backgroundColor: RideShareColors.primary
                                .withValues(alpha: 0.15),
                            child: Text(
                              counterpart.isNotEmpty
                                  ? counterpart[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: RideShareColors.primaryDeep,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  counterpart,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: RideShareColors.titleText,
                                  ),
                                ),
                                if (highlightUnpaid)
                                  Text(
                                    vehicle,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: RideShareColors.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (ride.isCompleted && pending)
                            const RideHistoryPaymentChip(pending: true)
                          else
                            RideHistoryStatusChip(
                              status: ride.status,
                              compact: true,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 14),
              RideHistoryRouteTimeline(
                pickup: pickup,
                dropoff: dropoff,
                compact: !highlightUnpaid,
              ),
              if (!isDriver) ...[
                const SizedBox(height: 14),
                if (highlightUnpaid)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: onPrimaryAction ?? onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: RideShareColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text(
                        'Pay Now',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: onPrimaryAction ?? onTap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: RideShareColors.primaryContainer,
                        side: const BorderSide(
                          color: RideShareColors.primaryContainer,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text(
                        'View Receipt',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class RideHistoryEarningsHero extends StatelessWidget {
  final String title;
  final String amountLabel;
  final String tripsLabel;
  final String? trendLabel;
  final VoidCallback? onCashOut;

  const RideHistoryEarningsHero({
    required this.title,
    required this.amountLabel,
    required this.tripsLabel,
    this.trendLabel,
    this.onCashOut,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            RideShareColors.primaryContainer,
            RideShareColors.primaryContainer.withValues(alpha: 0.88),
            const Color(0xFF0E1A33),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: RideShareColors.primaryContainer.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Total",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      amountLabel,
                      style: const TextStyle(
                        color: RideShareColors.primary,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Trips Completed',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    tripsLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
            child: Row(
              children: [
                if (trendLabel != null)
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.trending_up,
                          size: 16,
                          color: RideShareColors.primarySoft,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            trendLabel!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (onCashOut != null)
                  TextButton(
                    onPressed: onCashOut,
                    style: TextButton.styleFrom(
                      backgroundColor: RideShareColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: const Text(
                      'Cash Out',
                      style: TextStyle(fontWeight: FontWeight.w800),
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

class RideHistoryFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const RideHistoryFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: RideShareColors.primary,
        labelStyle: TextStyle(
          color: selected ? Colors.white : RideShareColors.titleText,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected
              ? RideShareColors.primary
              : RideShareColors.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
