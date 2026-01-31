import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DriverPickupRouteScreen extends StatefulWidget {
  final String rideId;
  final String passengerName;
  final String passengerPhone;
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final double driverLat;
  final double driverLng;
  final double estimatedFare;
  final VoidCallback onArrived;

  const DriverPickupRouteScreen({
    required this.rideId,
    required this.passengerName,
    required this.passengerPhone,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.driverLat,
    required this.driverLng,
    required this.estimatedFare,
    required this.onArrived,
  });

  @override
  State<DriverPickupRouteScreen> createState() =>
      _DriverPickupRouteScreenState();
}

class _DriverPickupRouteScreenState extends State<DriverPickupRouteScreen> {
  GoogleMapController? mapController;
  final Set<Marker> markers = {};
  final Set<Polyline> polylines = {};
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
          markerId: const MarkerId('driver'),
          position: LatLng(widget.driverLat, widget.driverLng),
          infoWindow: const InfoWindow(title: 'Your Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue,
          ),
        ),
      );

      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(widget.pickupLat, widget.pickupLng),
          infoWindow: InfoWindow(
            title: 'Pickup',
            snippet: widget.passengerName,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );

      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: [
            LatLng(widget.driverLat, widget.driverLng),
            LatLng(widget.pickupLat, widget.pickupLng),
          ],
          color: primaryColor,
          width: 5,
        ),
      );
    });
  }

  void _handleArrived() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Mark as Arrived?',
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
            onPressed: () {
              Navigator.pop(context);
              widget.onArrived();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Yes, Arrived',
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
              target: LatLng(widget.driverLat, widget.driverLng),
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
                        'Going to Pickup',
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.passengerName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.passengerPhone,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: primaryColor.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              'MK${widget.estimatedFare.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: primaryColor,
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

          // Bottom pickup location card
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.location_on,
                            color: Colors.green.shade600,
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
                                  color: Colors.black87,
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
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _handleArrived,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
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

  Future<void> _fitMarkersOnScreen() async {
    if (mapController == null) return;

    try {
      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          widget.pickupLat < widget.driverLat
              ? widget.pickupLat
              : widget.driverLat,
          widget.pickupLng < widget.driverLng
              ? widget.pickupLng
              : widget.driverLng,
        ),
        northeast: LatLng(
          widget.pickupLat > widget.driverLat
              ? widget.pickupLat
              : widget.driverLat,
          widget.pickupLng > widget.driverLng
              ? widget.pickupLng
              : widget.driverLng,
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
