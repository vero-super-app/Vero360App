import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/driver_request_service.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

/// Navy premium ride-request card shared by overlay popup and accept dialog.
class DriverRideRequestSheet extends StatelessWidget {
  final DriverRideRequest request;
  final Animation<double>? timer;
  final double? pickupKm;
  final int? pickupMins;
  final String passengerShort;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final bool accepting;
  final bool declining;

  const DriverRideRequestSheet({
    required this.request,
    required this.passengerShort,
    this.timer,
    this.pickupKm,
    this.pickupMins,
    this.onAccept,
    this.onDecline,
    this.accepting = false,
    this.declining = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final fare = request.estimatedFare > 0
        ? 'MK ${request.estimatedFare.toStringAsFixed(0)}'
        : '—';
    final tripKm = request.estimatedDistance > 0
        ? '${request.estimatedDistance.toStringAsFixed(1)} km'
        : '—';
    final tripMins = request.estimatedTime > 0
        ? '${request.estimatedTime} min'
        : (request.estimatedDistance > 0
            ? '${(request.estimatedDistance * 2.5).ceil()} min'
            : '—');
    final pickupDist =
        pickupKm != null ? '${pickupKm!.toStringAsFixed(1)} km' : 'Near you';
    final pickupEta = pickupMins != null ? '$pickupMins min' : '…';
    final busy = accepting || declining;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            RideShareColors.primaryContainer,
            Color(0xFF0E1A33),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (timer != null)
            AnimatedBuilder(
              animation: timer!,
              builder: (context, _) {
                return LinearProgressIndicator(
                  value: (1.0 - timer!.value).clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  color: RideShareColors.primary,
                );
              },
            )
          else
            Container(height: 5, color: RideShareColors.primary),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'New Ride Request',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: RideShareColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        fare,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.symmetric(
                      horizontal: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _stat(
                          label: 'Pickup',
                          value: pickupDist,
                          sub: pickupEta,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 48,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      Expanded(
                        child: _stat(
                          label: 'Total',
                          value: tripKm,
                          sub: tripMins,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 48,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      Expanded(
                        child: _stat(
                          label: 'Passenger',
                          valueWidget: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: RideShareColors.primary,
                              ),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  passengerShort,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          sub: 'Waiting',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: RideShareColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pickup Address',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            request.pickupAddress.isNotEmpty
                                ? request.pickupAddress
                                : 'Pickup location',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          if (request.dropoffAddress.isNotEmpty &&
                              request.dropoffAddress != 'Destination') ...[
                            const SizedBox(height: 10),
                            Text(
                              'Drop-off',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              request.dropoffAddress,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: busy ? null : onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RideShareColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          RideShareColors.primary.withValues(alpha: 0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: accepting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'ACCEPT REQUEST',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 0.4,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: busy ? null : onDecline,
                  child: declining
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        )
                      : Text(
                          'Decline',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required String label,
    String? value,
    Widget? valueWidget,
    required String sub,
  }) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        valueWidget ??
            Text(
              value ?? '—',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
        const SizedBox(height: 2),
        Text(
          sub,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

String shortPassengerName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed == 'Unknown') return 'Passenger';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length == 1) return parts.first;
  final last = parts.last;
  if (last.isEmpty) return parts.first;
  return '${parts.first} ${last[0]}.';
}
