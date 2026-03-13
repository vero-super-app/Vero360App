import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GernalServices/driver_request_service.dart';

class RideNotificationPopup extends StatefulWidget {
  final DriverRideRequest rideRequest;
  final WidgetRef ref;
  final VoidCallback onDismiss;
  final VoidCallback onAccept;

  const RideNotificationPopup({
    super.key,
    required this.rideRequest,
    required this.ref,
    required this.onDismiss,
    required this.onAccept,
  });

  @override
  State<RideNotificationPopup> createState() => _RideNotificationPopupState();
}

class _RideNotificationPopupState extends State<RideNotificationPopup>
    with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFFFF8A00);

  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _scaleAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();

    Future.delayed(const Duration(seconds: 12), () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() {
    _controller.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cardWidth = size.width < 600 ? size.width - 48 : 400.0;

    return Positioned.fill(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            GestureDetector(
              onTap: _dismiss,
              child: Container(color: Colors.black26),
            ),
            Center(
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: cardWidth,
                    child: _buildCard(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard() {
    final req = widget.rideRequest;
    final fareStr = req.estimatedFare > 0
        ? 'MK ${req.estimatedFare.toStringAsFixed(0)}'
        : '---';
    final distStr = req.estimatedDistance > 0
        ? '${req.estimatedDistance.toStringAsFixed(1)} km'
        : '---';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF8A00), Color(0xFFFF6B00)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_taxi, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New Ride Request',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'A passenger needs a ride',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _dismiss,
                  child: const Icon(Icons.close, color: Colors.white70, size: 22),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              children: [
                // Pickup address
                _buildAddressRow(
                  color: _primary,
                  icon: Icons.trip_origin,
                  label: 'Pickup',
                  address: req.pickupAddress,
                ),
                if (req.dropoffAddress.isNotEmpty &&
                    req.dropoffAddress != 'Destination') ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 11),
                    child: Column(
                      children: List.generate(
                        3,
                        (_) => Container(
                          width: 2,
                          height: 4,
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          color: Colors.grey[300],
                        ),
                      ),
                    ),
                  ),
                  _buildAddressRow(
                    color: Colors.redAccent,
                    icon: Icons.location_on,
                    label: 'Dropoff',
                    address: req.dropoffAddress,
                  ),
                ],
                const SizedBox(height: 16),

                // Fare & distance chips
                Row(
                  children: [
                    Expanded(child: _buildChip(Icons.payments_outlined, 'Fare', fareStr)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildChip(Icons.straighten, 'Distance', distStr)),
                  ],
                ),
                const SizedBox(height: 20),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _dismiss,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey[400]!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Decline',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: widget.onAccept,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.check_circle_outline,
                              color: Colors.white, size: 20),
                          label: const Text(
                            'Accept Ride',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow({
    required Color color,
    required IconData icon,
    required String label,
    required String address,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Text(
                address,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: _primary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}
