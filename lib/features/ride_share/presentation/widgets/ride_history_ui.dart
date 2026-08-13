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
  final String? pendingLabel;

  const RideHistoryPaymentChip({
    required this.pending,
    this.pendingLabel,
    super.key,
  });

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
        pending ? (pendingLabel ?? 'Payment Pending') : 'Paid',
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

  String _shortPlace(String? raw, String fallback) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return fallback;
    final first = t.split(',').first.trim();
    return first.isEmpty ? fallback : first;
  }

  String _plainStatus(Ride ride, {required bool pending}) {
    if (ride.isCancelled) return 'Cancelled';
    if (ride.isCashPayment && !ride.isPaid) return 'Cash pending';
    if (pending) return 'Pay now';
    if (ride.isCompleted) return 'Completed';
    final s = ride.status.replaceAll('_', ' ').toLowerCase();
    if (s.isEmpty) return 'Trip';
    return s[0].toUpperCase() + s.substring(1);
  }

  Color _statusColor(Ride ride, {required bool pending}) {
    if (ride.isCancelled) return const Color(0xFFC62828);
    if (ride.isCashPayment && !ride.isPaid) {
      return RideShareColors.primaryDeep;
    }
    if (pending) return RideShareColors.primaryDeep;
    if (ride.isCompleted) return const Color(0xFF2E7D32);
    return RideShareColors.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final summary = ride.tripSummary;
    final amount = isDriver
        ? (summary?.driverEarnings ??
            ride.driverEarnings ??
            ride.resolvedFare)
        : (summary?.fare ?? ride.resolvedFare);
    final when = ride.endTime ?? ride.createdAt;
    final pending = isDriver
        ? ride.isSettlementPending
        : ride.needsPayment;
    final counterpart = rideCounterpartName(ride, isDriver: isDriver);
    final pickup = summary?.pickup ?? ride.pickupAddress ?? 'Pickup';
    final dropoff = summary?.dropoff ?? ride.dropoffAddress ?? 'Dropoff';

    if (!isDriver) {
      return _passengerCard(
        amount: amount,
        when: when,
        pending: pending,
        counterpart: counterpart,
        pickup: pickup,
        dropoff: dropoff,
      );
    }

    return _driverCard(
      amount: amount,
      when: when,
      pending: pending,
      counterpart: counterpart,
      pickup: pickup,
      dropoff: dropoff,
    );
  }

  /// Clear, unique passenger card: From → To, when, fare, one status word.
  Widget _passengerCard({
    required num amount,
    required DateTime when,
    required bool pending,
    required String counterpart,
    required String pickup,
    required String dropoff,
  }) {
    final from = _shortPlace(pickup, 'Pickup');
    final to = _shortPlace(dropoff, 'Drop-off');
    final status = _plainStatus(ride, pending: pending);
    final statusColor = _statusColor(ride, pending: pending);
    final highlight =
        pending || (ride.isCashPayment && !ride.isPaid);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: highlight
                  ? RideShareColors.primary.withValues(alpha: 0.45)
                  : const Color(0xFFE8E4E0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _placeRow(
                          color: RideShareColors.primary,
                          label: 'From',
                          place: from,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 9),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 2,
                              height: 14,
                              color: const Color(0xFFE0DBD6),
                            ),
                          ),
                        ),
                        _placeRow(
                          color: RideShareColors.primaryDeep,
                          label: 'To',
                          place: to,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatRideMoney(amount, money),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: RideShareColors.titleText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 15,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${formatRideWhen(when)} · $counterpart',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (pending) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: onPrimaryAction ?? onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RideShareColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Pay for this ride',
                      style: TextStyle(fontWeight: FontWeight.w800),
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

  Widget _placeRow({
    required Color color,
    required String label,
    required String place,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
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
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                place,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: RideShareColors.titleText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _driverCard({
    required num amount,
    required DateTime when,
    required bool pending,
    required String counterpart,
    required String pickup,
    required String dropoff,
  }) {
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
            border: Border.all(color: RideShareColors.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: RideShareColors.primaryContainer.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                        RideHistoryPaymentChip(
                          pending: true,
                          pendingLabel: ride.isCashPayment
                              ? 'Cash pending'
                              : 'Payment pending',
                        )
                      else
                        RideHistoryStatusChip(
                          status: ride.status,
                          compact: true,
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              RideHistoryRouteTimeline(
                pickup: pickup,
                dropoff: dropoff,
                compact: true,
              ),
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
            RideShareColors.primary,
            RideShareColors.primaryDeep,
            RideShareColors.primaryDark,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: RideShareColors.primary.withValues(alpha: 0.35),
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
