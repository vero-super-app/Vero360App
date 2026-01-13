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
          color: const Color(0xFFFF8A00),
          width: 5,
        ),
      );
    });
  }

  void _handleArrived() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Arrived?'),
        content: const Text(
          'Confirm that you have arrived at the pickup location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onArrived();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
            ),
            child: const Text('Yes, Arrived'),
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
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.grey[200],
                            child: const Icon(
                              Icons.person,
                              color: Colors.grey,
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
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.passengerPhone,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
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
                              color: const Color(0xFFFF8A00).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'MK${widget.estimatedFare.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF8A00),
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
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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
                            borderRadius: BorderRadius.circular(8),
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
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _handleArrived,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'I Have Arrived',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
          widget.pickupLat < widget.driverLat ? widget.pickupLat : widget.driverLat,
          widget.pickupLng < widget.driverLng ? widget.pickupLng : widget.driverLng,
        ),
        northeast: LatLng(
          widget.pickupLat > widget.driverLat ? widget.pickupLat : widget.driverLat,
          widget.pickupLng > widget.driverLng ? widget.pickupLng : widget.driverLng,
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
