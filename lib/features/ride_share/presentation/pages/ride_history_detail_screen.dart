import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';

enum RideHistoryPerspective { passenger, driver }

class RideHistoryDetailScreen extends StatelessWidget {
  final Ride ride;
  final RideHistoryPerspective perspective;

  const RideHistoryDetailScreen({
    super.key,
    required this.ride,
    required this.perspective,
  });

  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0', 'en');
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm');
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

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      appBar: AppBar(
        title: Text(isDriver ? 'Trip Earnings' : 'Trip Receipt'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E6EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _brandOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.local_taxi_rounded,
                        color: _brandOrange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ride #${ride.id}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: _brandNavy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateFmt.format(when),
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                    _statusChip(ride.status),
                  ],
                ),
                const SizedBox(height: 16),
                _detailRow(
                  'Route',
                  ride.routeLabel,
                  icon: Icons.route_rounded,
                ),
                const SizedBox(height: 10),
                _detailRow(
                  isDriver ? 'Passenger' : 'Driver',
                  summary?.counterpartyName ??
                      (isDriver
                          ? (ride.passengerName ?? 'Passenger')
                          : (ride.driver?.fullName ?? 'Driver')),
                  icon: Icons.person_outline_rounded,
                ),
                if ((summary?.vehiclePlate ?? ride.taxi?.licensePlate)
                        ?.isNotEmpty ==
                    true) ...[
                  const SizedBox(height: 10),
                  _detailRow(
                    'Vehicle',
                    '${summary?.vehiclePlate ?? ride.taxi?.licensePlate}'
                    '${summary?.vehicleClass != null ? ' • ${summary!.vehicleClass}' : ''}',
                    icon: Icons.directions_car_outlined,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E6EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trip Summary',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: _brandNavy,
                  ),
                ),
                const SizedBox(height: 14),
                _metricRow('Distance', '${distance.toStringAsFixed(1)} km'),
                _metricRow('Duration', duration > 0 ? '$duration mins' : '—'),
                _metricRow(
                  'Pickup',
                  summary?.pickup ?? ride.pickupAddress ?? '—',
                ),
                _metricRow(
                  'Dropoff',
                  summary?.dropoff ?? ride.dropoffAddress ?? '—',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E6EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDriver ? 'Earnings Breakdown' : 'Fare Breakdown',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: _brandNavy,
                  ),
                ),
                const SizedBox(height: 14),
                _metricRow('Trip fare', 'MK ${money.format(fare)}'),
                if (isDriver) ...[
                  _metricRow(
                    'Platform fee',
                    'MK ${money.format(platformFee)}',
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'You earned',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: _brandNavy,
                        ),
                      ),
                      Text(
                        'MK ${money.format(driverEarnings)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: _brandOrange,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total paid',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: _brandNavy,
                        ),
                      ),
                      Text(
                        'MK ${money.format(fare)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: _brandOrange,
                        ),
                      ),
                    ],
                  ),
                ],
                if ((summary?.paymentStatus ?? ride.paymentStatus) != null) ...[
                  const SizedBox(height: 12),
                  _metricRow(
                    'Payment',
                    _paymentLabel(
                      summary?.paymentStatus ?? ride.paymentStatus ?? 'pending',
                    ),
                  ),
                  if (ride.paidAt != null)
                    _metricRow(
                      'Paid on',
                      dateFmt.format(ride.paidAt!),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case RideStatus.completed:
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        label = 'Completed';
        break;
      case RideStatus.cancelled:
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
        label = 'Cancelled';
        break;
      default:
        bg = const Color(0xFFFFF3E0);
        fg = _brandOrange;
        label = status.replaceAll('_', ' ');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  String _paymentLabel(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return 'Paid';
      case 'failed':
        return 'Failed';
      default:
        return 'Pending';
    }
  }

  Widget _detailRow(String label, String value, {required IconData icon}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _brandNavy,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: _brandNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
