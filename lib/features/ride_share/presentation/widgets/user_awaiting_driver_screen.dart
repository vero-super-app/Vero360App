import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';

class UserAwaitingDriverScreen extends StatefulWidget {
  final String rideId;
  final String driverName;
  final String vehicleType;
  final String vehiclePlate;
  final double driverRating;
  final int completedRides;
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final double estimatedFare;
  final LatLng? driverLocation;
  final VoidCallback onStartRide;
  final RideShareHttpService? httpService;

  const UserAwaitingDriverScreen({
    required this.rideId,
    required this.driverName,
    required this.vehicleType,
    required this.vehiclePlate,
    required this.driverRating,
    required this.completedRides,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.estimatedFare,
    this.driverLocation,
    required this.onStartRide,
    this.httpService,
  });

  @override
  State<UserAwaitingDriverScreen> createState() => _UserAwaitingDriverScreenState();
}

class _UserAwaitingDriverScreenState extends State<UserAwaitingDriverScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? mapController;
  final Set<Marker> markers = {};
  late AnimationController _pulseController;
  bool _rideStarted = false;
  StreamSubscription<Ride>? _rideUpdateSubscription;

  @override
  void initState() {
    super.initState();
    _setupMapMarkers();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    // Listen to ride status updates
    _listenToRideUpdates();
  }
  
  void _listenToRideUpdates() {
    final httpService = widget.httpService ?? RideShareHttpService();
    _rideUpdateSubscription = httpService.rideUpdateStream.listen((ride) {
      // Ignore updates if widget is already unmounted
      if (!mounted) {
        print('[UserAwaitingDriverScreen] Received update after unmount, ignoring');
        return;
      }

      print('[UserAwaitingDriverScreen] Ride update: status=${ride.status}');
      
      // When driver starts the ride (IN_PROGRESS)
      if (ride.status == RideStatus.inProgress && !_rideStarted) {
        print('[UserAwaitingDriverScreen] Driver started ride! Status is IN_PROGRESS');
        _rideStarted = true;
        // Only call onStartRide if not already navigating away
        if (mounted) {
          widget.onStartRide();
        }
      }
    });
  }

  @override
  void dispose() {
    // Cancel the stream subscription to prevent memory leaks and defunct widget access
    _rideUpdateSubscription?.cancel();
    mapController?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _setupMapMarkers() {
    setState(() {
      markers.clear();

      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(widget.pickupLat, widget.pickupLng),
          infoWindow: const InfoWindow(title: 'Your Pickup Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );

      if (widget.driverLocation != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('driver'),
            position: widget.driverLocation!,
            infoWindow: InfoWindow(title: 'Driver ${widget.driverName}'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          ),
        );
      }
    });
  }

  void _handleStartRide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Start Ride?'),
        content: const Text(
          'Confirm that the driver has arrived and you are ready to start the ride.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _startRideWithBackend();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Yes, Start Ride',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startRideWithBackend() async {
    try {
      print('[UserAwaitingDriverScreen] Calling backend to start ride: ${widget.rideId}');
      
      final httpService = widget.httpService ?? RideShareHttpService();
      final rideIdInt = int.tryParse(widget.rideId) ?? 0;
      
      if (rideIdInt <= 0) {
        throw Exception('Invalid ride ID');
      }

      // Call backend to update ride status to IN_PROGRESS
      final ride = await httpService.startRide(rideIdInt);
      print('[UserAwaitingDriverScreen] Ride started successfully. New status: ${ride.status}');
      
      if (!mounted) {
        print('[UserAwaitingDriverScreen] Widget unmounted, skipping UI updates');
        return;
      }
      
      widget.onStartRide();
    } catch (e) {
      print('[UserAwaitingDriverScreen] Error starting ride: $e');
      if (!mounted) {
        print('[UserAwaitingDriverScreen] Widget unmounted, skipping error display');
        return;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start ride: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
              target: LatLng(widget.pickupLat, widget.pickupLng),
              zoom: 15,
            ),
            markers: markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Top driver info card
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
                    // Status label
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Driver Arriving',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF10B981),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Driver info
                    Row(
                      children: [
                        // Avatar
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.person,
                            color: Colors.grey,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Driver details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.driverName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    size: 16,
                                    color: Colors.amber[500],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${widget.driverRating.toStringAsFixed(1)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${widget.completedRides} rides',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Vehicle info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.directions_car_rounded,
                              color: Color(0xFF3B82F6),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.vehicleType.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.vehiclePlate,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Arriving',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF3B82F6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom action card
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
                  // Pickup location
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Color(0xFF10B981),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pickup Location',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.pickupAddress,
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

                  // Start ride button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _handleStartRide,
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: const Text(
                        'Start Ride',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
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
