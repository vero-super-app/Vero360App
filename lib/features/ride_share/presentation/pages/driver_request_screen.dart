import 'package:flutter/material.dart';
import 'package:vero360_app/services/driver_request_service.dart';
import '../widgets/driver_request_accept_dialog.dart';

class DriverRequestScreen extends StatefulWidget {
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String? driverAvatar;

  const DriverRequestScreen({
    super.key,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    this.driverAvatar,
  });

  @override
  State<DriverRequestScreen> createState() => _DriverRequestScreenState();
}

class _DriverRequestScreenState extends State<DriverRequestScreen> {
  late Stream<List<DriverRideRequest>> _requestsStream;
  static const Color primaryColor = Color(0xFFFF8A00);

  @override
  void initState() {
    super.initState();
    _requestsStream = Stream.periodic(
      const Duration(seconds: 3),
      (_) => DriverRequestService.getIncomingRequests(),
    ).asyncExpand((future) => Stream.fromFuture(future));
  }

  void _showRequestDialog(DriverRideRequest request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => DriverRequestAcceptDialog(
        request: request,
        driverId: widget.driverId,
        driverName: widget.driverName,
        driverPhone: widget.driverPhone,
        driverAvatar: widget.driverAvatar,
        onAccepted: () {
          // Show success message or navigate
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    const Text('Ride accepted! Navigate to pickup location.'),
                backgroundColor: Colors.green.shade600,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
              ),
            );
          }
        },
        onRejected: () {
          // Remain on this screen to see next request
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Available Rides'),
        backgroundColor: primaryColor,
        elevation: 0,
        centerTitle: false,
      ),
      body: StreamBuilder<List<DriverRideRequest>>(
        stream: _requestsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error_outline,
                      size: 40,
                      color: Colors.red.shade400,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${snapshot.error}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final requests = snapshot.data ?? [];

          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.inbox,
                      size: 40,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No available rides',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check back soon for ride requests',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              final isNew =
                  DateTime.now().difference(request.createdAt).inMinutes < 1;

              return GestureDetector(
                onTap: () => _showRequestDialog(request),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: isNew
                        ? Border.all(
                            color: primaryColor,
                            width: 2,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.black.withValues(alpha: isNew ? 0.08 : 0.04),
                        blurRadius: isNew ? 16 : 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with passenger name and badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    request.passengerName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'just now',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isNew)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'NEW',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(height: 1, color: Colors.grey[200]),
                        const SizedBox(height: 16),

                        // Route info
                        _buildRouteInfo(
                          icon: Icons.location_on_outlined,
                          label: 'Pickup',
                          address: request.pickupAddress,
                        ),
                        const SizedBox(height: 12),
                        _buildRouteInfo(
                          icon: Icons.location_on,
                          label: 'Dropoff',
                          address: request.dropoffAddress,
                        ),
                        const SizedBox(height: 16),

                        // Fare, Time, Distance row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildMetric(
                              icon: Icons.wallet_outlined,
                              label: 'Fare',
                              value:
                                  'MK${request.estimatedFare.toStringAsFixed(0)}',
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.grey[200],
                            ),
                            _buildMetric(
                              icon: Icons.schedule,
                              label: 'Time',
                              value: '${request.estimatedTime} min',
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.grey[200],
                            ),
                            _buildMetric(
                              icon: Icons.straighten,
                              label: 'Distance',
                              value:
                                  '${request.estimatedDistance.toStringAsFixed(1)} km',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Accept button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () => _showRequestDialog(request),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'View & Accept',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRouteInfo({
    required IconData icon,
    required String label,
    required String address,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: primaryColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
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

  Widget _buildMetric({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: primaryColor),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
