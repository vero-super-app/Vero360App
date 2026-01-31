import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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

  const DriverRideActiveScreen({
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
  });

  @override
  State<DriverRideActiveScreen> createState() => _DriverRideActiveScreenState();
}

class _DriverRideActiveScreenState extends State<DriverRideActiveScreen> {
  GoogleMapController? mapController;
  final Set<Marker> markers = {};
  final Set<Polyline> polylines = {};
  bool _isCompletingRide = false;
  static const Color primaryColor = Color(0xFFFF8A00);

  @override
  void initState() {
    super.initState();
    _setupMapMarkers();
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
              setState(() => _isCompletingRide = true);
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  widget.onRideCompleted();
                }
              });
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
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.green.shade200,
                              ),
                            ),
                            child: Text(
                              'In Progress',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade600,
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
