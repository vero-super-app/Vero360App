import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/services/ride_share_http_service.dart';

class RideInProgressScreen extends StatefulWidget {
  final String rideId;
  final String driverId;
  final String passengerName;
  final String pickupAddress;
  final String dropoffAddress;
  final double estimatedFare;
  final int estimatedTime;
  final VoidCallback onRideCompleted;

  const RideInProgressScreen({
    required this.rideId,
    required this.driverId,
    required this.passengerName,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.estimatedFare,
    required this.estimatedTime,
    required this.onRideCompleted,
  });

  @override
  State<RideInProgressScreen> createState() => _RideInProgressScreenState();
}

class _RideInProgressScreenState extends State<RideInProgressScreen> {
  GoogleMapController? mapController;
  final Set<Marker> markers = {};
  final Set<Polyline> polylines = {};
  LatLng? driverLocation;
  LatLng? userLocation;
  int remainingTime = 0;
  double remainingDistance = 0;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  void _startLocationTracking() {
    final httpService = RideShareHttpService();
    httpService.driverLocationStream.listen((locationData) {
      if (mounted && locationData.isNotEmpty) {
        final lat = locationData['latitude'] as double?;
        final lng = locationData['longitude'] as double?;

        if (lat != null && lng != null) {
          setState(() {
            driverLocation = LatLng(lat, lng);
            remainingTime = _calculateRemainingTime();
            remainingDistance = _calculateRemainingDistance();
          });
          _updateMapMarkers();
        }
      }
    });
  }

  int _calculateRemainingTime() {
    return widget.estimatedTime ~/ 2;
  }

  double _calculateRemainingDistance() {
    return 2.5;
  }

  void _updateMapMarkers() {
    if (driverLocation == null) return;

    setState(() {
      markers.clear();

      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: driverLocation!,
          infoWindow: InfoWindow(
            title: 'Your Position',
            snippet: widget.passengerName,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    });
  }

  void _handleEndRide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Ride?'),
        content: const Text(
          'Are you sure you want to end this ride? You\'ll be taken to the payment screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onRideCompleted();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[500],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'End Ride',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          GoogleMap(
            onMapCreated: (controller) => mapController = controller,
            initialCameraPosition: CameraPosition(
              target: driverLocation ?? const LatLng(0, 0),
              zoom: 15,
            ),
            markers: markers,
            polylines: polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Top status card
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF3B82F6),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Ride in Progress',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF3B82F6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Main info row
                    Row(
                      children: [
                        // ETA and distance
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 16,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${remainingTime} min',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${remainingDistance.toStringAsFixed(1)} km remaining',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Fare card
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8A00).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFFF8A00).withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Fare',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'MK${widget.estimatedFare.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFF8A00),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom destination card
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Route info
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.location_on_rounded,
                          color: Colors.red[500],
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Destination',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.dropoffAddress,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // End ride button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _handleEndRide,
                      icon: const Icon(Icons.stop_circle_rounded, size: 22),
                      label: const Text(
                        'End Ride',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[500],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
