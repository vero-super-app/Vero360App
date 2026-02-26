import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';

class DriverRideActiveScreen extends StatefulWidget {
  final String rideId;
  final String passengerName;
  final String pickupAddress;
  final String dropoffAddress;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final double estimatedFare;
  final VoidCallback onRideCompleted;
  final RideShareHttpService? httpService;

  const DriverRideActiveScreen({super.key, 
    required this.rideId,
    required this.passengerName,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.estimatedFare,
    required this.onRideCompleted,
    this.httpService,
  });

  @override
  State<DriverRideActiveScreen> createState() => _DriverRideActiveScreenState();
}

class _DriverRideActiveScreenState extends State<DriverRideActiveScreen> {
  GoogleMapController? mapController;
  final Set<Marker> markers = {};
  final Set<Polyline> polylines = {};
  bool _isCompletingRide = false;
  bool _hasArrived = false;
  bool _rideStarted = false;
  bool _isStartingRide = false;
  static const Color primaryColor = Color(0xFFFF8A00);
  StreamSubscription<Ride>? _rideUpdateSubscription;

  @override
  void initState() {
    super.initState();
    _setupMapMarkers();
    _listenToRideUpdates();
  }

  void _listenToRideUpdates() {
    final httpService = widget.httpService ?? RideShareHttpService();
    _rideUpdateSubscription = httpService.rideUpdateStream.listen((ride) {
      if (!mounted) return;

      setState(() {
        // Update arrival status based on ride status
        _hasArrived = ride.status == RideStatus.driverArrived ||
            ride.status == RideStatus.inProgress ||
            ride.status == RideStatus.completed;
        
        // Update ride started status
        _rideStarted = ride.status == RideStatus.inProgress ||
            ride.status == RideStatus.completed;
      });

      // If passenger started the ride, show the in-progress screen
      if (ride.status == RideStatus.inProgress && !_rideStarted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Passenger started the ride'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _setupMapMarkers() {
    setState(() {
      markers.clear();

      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(widget.pickupLat, widget.pickupLng),
          infoWindow: const InfoWindow(title: 'Pickup Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );

      markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(widget.dropoffLat, widget.dropoffLng),
          infoWindow: const InfoWindow(title: 'Dropoff Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
        ),
      );

      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: [
            LatLng(widget.pickupLat, widget.pickupLng),
            LatLng(widget.dropoffLat, widget.dropoffLng),
          ],
          color: primaryColor,
          width: 5,
          geodesic: true,
        ),
      );
    });
  }

  void _handleMarkArrived() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Arrived at Pickup?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        content: const Text(
          'Confirm that you have arrived at the pickup location.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Not Yet',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _markDriverArrived();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Yes, I\'m Here',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markDriverArrived() async {
    try {
      final httpService = widget.httpService ?? RideShareHttpService();
      final rideIdInt = int.tryParse(widget.rideId) ?? 0;

      if (rideIdInt <= 0) {
        throw Exception('Invalid ride ID');
      }

      await httpService.markDriverArrived(rideIdInt);
      print('[DriverRideActiveScreen] Marked as arrived');

      if (!mounted) return;

      setState(() {
        _hasArrived = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passenger has been notified'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('[DriverRideActiveScreen] Error marking arrived: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to mark as arrived: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleStartRide() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Start Ride?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        content: const Text(
          'Confirm that the passenger is in the vehicle and ready to start.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Not Ready',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startRideWithBackend();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Start Ride',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startRideWithBackend() async {
    try {
      setState(() => _isStartingRide = true);
      final httpService = widget.httpService ?? RideShareHttpService();
      final rideIdInt = int.tryParse(widget.rideId) ?? 0;

      if (rideIdInt <= 0) {
        throw Exception('Invalid ride ID');
      }

      await httpService.startRide(rideIdInt);
      print('[DriverRideActiveScreen] Ride started');

      if (!mounted) return;

      setState(() {
        _isStartingRide = false;
        _rideStarted = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ride in progress'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('[DriverRideActiveScreen] Error starting ride: $e');
      if (!mounted) return;

      setState(() => _isStartingRide = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start ride: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleCompleteRide() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Complete Ride?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        content: const Text(
          'Confirm that the passenger has reached their destination.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Not Yet',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _completeRideWithBackend();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Yes, Complete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _completeRideWithBackend() async {
    try {
      setState(() => _isCompletingRide = true);
      final httpService = widget.httpService ?? RideShareHttpService();
      final rideIdInt = int.tryParse(widget.rideId) ?? 0;

      if (rideIdInt <= 0) {
        throw Exception('Invalid ride ID');
      }

      await httpService.completeRide(rideIdInt);
      print('[DriverRideActiveScreen] Ride completed');

      if (!mounted) return;

      setState(() => _isCompletingRide = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ride completed successfully'),
          duration: Duration(seconds: 2),
        ),
      );

      // Wait a moment before calling the callback
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          widget.onRideCompleted();
        }
      });
    } catch (e) {
      print('[DriverRideActiveScreen] Error completing ride: $e');
      if (!mounted) return;

      setState(() => _isCompletingRide = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to complete ride: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _rideUpdateSubscription?.cancel();
    mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              mapController = controller;
              _fitMarkersOnScreen();
            },
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.pickupLat, widget.pickupLng),
              zoom: 14,
            ),
            markers: markers,
            polylines: polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Top passenger info card
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
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'On Ride',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: primaryColor.withOpacity(0.2),
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: primaryColor.withOpacity(0.1),
                              child: Icon(
                                Icons.person,
                                color: primaryColor,
                                size: 24,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.passengerName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _rideStarted
                                  ? Colors.green.shade50
                                  : _hasArrived
                                      ? Colors.blue.shade50
                                      : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _rideStarted
                                    ? Colors.green.shade200
                                    : _hasArrived
                                        ? Colors.blue.shade200
                                        : Colors.orange.shade200,
                              ),
                            ),
                            child: Text(
                              _rideStarted
                                  ? 'In Progress'
                                  : _hasArrived
                                      ? 'Arrived'
                                      : 'Awaiting Pickup',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _rideStarted
                                    ? Colors.green.shade600
                                    : _hasArrived
                                        ? Colors.blue.shade600
                                        : Colors.orange.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom destination info card
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
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildLocationRow(
                      icon: Icons.location_on,
                      label: 'Pickup',
                      address: widget.pickupAddress,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Container(
                        height: 20,
                        width: 2,
                        color: Colors.grey[300],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildLocationRow(
                      icon: Icons.location_on,
                      label: 'Dropoff',
                      address: widget.dropoffAddress,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    if (!_hasArrived)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _handleMarkArrived,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'I Have Arrived',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    else if (!_rideStarted)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed:
                              _isStartingRide ? null : _handleStartRide,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade600,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            disabledBackgroundColor: Colors.grey[300],
                          ),
                          child: _isStartingRide
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Start Ride',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed:
                              _isCompletingRide ? null : _handleCompleteRide,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            disabledBackgroundColor: Colors.grey[300],
                          ),
                          child: _isCompletingRide
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Complete Ride',
                                  style: TextStyle(
                                    fontSize: 16,
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
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required String label,
    required String address,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
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

  Future<void> _fitMarkersOnScreen() async {
    if (mapController == null) return;

    try {
      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          widget.pickupLat < widget.dropoffLat
              ? widget.pickupLat
              : widget.dropoffLat,
          widget.pickupLng < widget.dropoffLng
              ? widget.pickupLng
              : widget.dropoffLng,
        ),
        northeast: LatLng(
          widget.pickupLat > widget.dropoffLat
              ? widget.pickupLat
              : widget.dropoffLat,
          widget.pickupLng > widget.dropoffLng
              ? widget.pickupLng
              : widget.dropoffLng,
        ),
      );

      CameraUpdate cameraUpdate = CameraUpdate.newLatLngBounds(
        bounds,
        100,
      );

      await mapController!.animateCamera(cameraUpdate);
    } catch (e) {
      debugPrint('Error fitting markers: $e');
    }
  }
}
