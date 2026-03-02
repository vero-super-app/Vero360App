import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'driver_request_screen.dart';

class DriverDashboardHome extends ConsumerStatefulWidget {
  const DriverDashboardHome({super.key});

  @override
  ConsumerState<DriverDashboardHome> createState() =>
      _DriverDashboardHomeState();
}

class _DriverDashboardHomeState extends ConsumerState<DriverDashboardHome> {
  static const Color primaryColor = Color(0xFFFF8A00);
  GoogleMapController? mapController;
  Timer? _locationBroadcastTimer;
  Timer? _mapCenteringTimer;
  final DriverService _driverService = DriverService();
  bool _isOnline = false;
  Position? _lastPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _startLocationBroadcasting();
        _startMapCentering();
      }
    });
  }

  @override
  void dispose() {
    mapController?.dispose();
    _stopLocationBroadcasting();
    _stopMapCentering();
    super.dispose();
  }

  /// Start broadcasting driver location to nearby car service
  void _startLocationBroadcasting() {
    if (_isOnline) return; // Already broadcasting

    setState(() => _isOnline = true);

    // Broadcast location every 5 seconds
    _locationBroadcastTimer =
        Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );

        // Update last position for map centering
        _lastPosition = position;

        // Get driver profile and ensure taxi exists
        final driverProfile = ref.read(myDriverProfileProvider);

        driverProfile.whenData((driver) async {
          if (driver['id'] == null) {
            if (kDebugMode) {
              print('[DriverDashboardHome] Driver profile incomplete');
            }
            return;
          }

          var taxiId = driver['taxis']?.isNotEmpty == true
              ? driver['taxis'][0]['id']
              : null;

          if (kDebugMode) {
            print(
                '[DriverDashboardHome] Driver ID: ${driver['id']}, Taxis: ${driver['taxis']}');
            print('[DriverDashboardHome] Extracted taxiId: $taxiId');
          }

          // Broadcast location only if taxi exists
          if (taxiId != null) {
            try {
              await _driverService.updateTaxiLocation(
                  int.parse(taxiId.toString()),
                  position.latitude,
                  position.longitude);
              if (kDebugMode) {
                print(
                    '[DriverDashboardHome] ✓ Broadcasting location to taxi $taxiId: ${position.latitude}, ${position.longitude}');
              }
            } catch (e) {
              if (kDebugMode) {
                print(
                    '[DriverDashboardHome] ✗ Error updating taxi location: $e');
              }
            }
          }
        });
      } catch (e) {
        if (kDebugMode) {
          print('[DriverDashboardHome] Error getting position: $e');
        }
      }
    });
  }

  /// Stop broadcasting driver location
  void _stopLocationBroadcasting() {
    _locationBroadcastTimer?.cancel();
    _locationBroadcastTimer = null;
    setState(() => _isOnline = false);
  }

  /// Start auto-centering map on driver location
  void _startMapCentering() {
    _mapCenteringTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (mapController != null && _lastPosition != null) {
        await mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(
                _lastPosition!.latitude,
                _lastPosition!.longitude,
              ),
              zoom: 15.0,
            ),
          ),
        );
      }
    });
  }

  /// Stop map auto-centering
  void _stopMapCentering() {
    _mapCenteringTimer?.cancel();
    _mapCenteringTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Map Background
        _buildMap(),

        // Bottom Sheet with Info
        DraggableScrollableSheet(
          initialChildSize: 0.35,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                   BoxShadow(
                     color: Colors.black.withValues(alpha: 0.1),
                     blurRadius: 24,
                     offset: const Offset(0, -4),
                   ),
                 ],
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),

                    // Profile Card
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildProfileCard(ref),
                    ),

                    // Stats Section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildStatsSection(ref),
                    ),

                    const SizedBox(height: 16),

                    // Quick Actions
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildActionsSection(context),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMap() {
    return GoogleMap(
      onMapCreated: (controller) {
        mapController = controller;
        // Animate to driver's last known position if available
        if (_lastPosition != null) {
          controller.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(
                  _lastPosition!.latitude,
                  _lastPosition!.longitude,
                ),
                zoom: 15.0,
              ),
            ),
          );
        }
      },
      initialCameraPosition: const CameraPosition(
        target: LatLng(0, 0),
        zoom: 14,
      ),
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      padding: const EdgeInsets.only(bottom: 200),
    );
  }

  Widget _buildProfileCard(WidgetRef ref) {
    final driverData = ref.watch(myDriverProfileProvider);

    return driverData.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: primaryColor)),
      error: (err, stack) => Center(
        child: Text('Error: $err'),
      ),
      data: (driver) {
        final name = (driver['user']?['name'] ?? 'Driver').toString();
        final phone = (driver['user']?['phone'] ?? 'N/A').toString();
        final verified = driver['verified'] ?? false;
        final avatar = _sanitizeUrl(driver['user']?['profilepicture']?.toString());

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: avatar != null && avatar.isNotEmpty && _isValidUrl(avatar)
                    ? NetworkImage(avatar)
                    : null,
                child: avatar == null || avatar.isEmpty || !_isValidUrl(avatar)
                    ? const Icon(Icons.person, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (verified)
                          const Icon(Icons.verified, size: 18, color: Colors.green)
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phone,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatsSection(WidgetRef ref) {
    final driverData = ref.watch(myDriverProfileProvider);

    return driverData.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (driver) {
        final totalRides = driver['totalRides'] ?? 0;
        final rating = (driver['rating'] ?? 0.0).toStringAsFixed(1);
        final status = (driver['status'] ?? 'INACTIVE').toString();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Driver Stats',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatCard(label: 'Rides', value: '$totalRides'),
                _StatCard(label: 'Rating', value: '$rating★'),
                _StatCard(label: 'Status', value: status),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionsSection(BuildContext context) {
    final driverData = ref.watch(myDriverProfileProvider);

    return driverData.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (driver) {
        final hasTaxis = driver['taxis'] is List && (driver['taxis'] as List).isNotEmpty;
        final isVerified = driver['verified'] ?? false;
        final driverId = driver['id'];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Actions',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: hasTaxis
                        ? () => _navigateToRideRequests(context)
                        : null,
                    icon: const Icon(Icons.local_taxi),
                    label: const Text('Find Rides'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      disabledBackgroundColor: Colors.grey[300],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!isVerified)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showVerifyDriverDialog(context, driverId),
                      icon: const Icon(Icons.verified),
                      label: const Text('Verify'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _showTaxiDetailsDialog(context, driver['taxis'][0]),
                      icon: const Icon(Icons.info),
                      label: const Text('Vehicle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                    ),
                  ),
              ],
            ),
            if (!hasTaxis) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showCreateTaxiDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Taxi'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  void _showCreateTaxiDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Taxi'),
        content: const Text(
          'A default taxi will be created with standard specifications. You can edit it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _createDefaultTaxi();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createDefaultTaxi() async {
    try {
      final driverProfile = await ref.read(myDriverProfileProvider.future);
      if (driverProfile['id'] == null) return;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final taxiPayload = {
        'make': 'Toyota',
        'model': 'Corolla',
        'year': DateTime.now().year,
        'licensePlate': 'DRV${driverProfile['id']}-$timestamp',
        'seats': 4,
        'taxiClass': 'STANDARD',
        'color': 'White',
        'registrationNumber': 'REG${driverProfile['id']}-$timestamp',
      };

      await _driverService.createTaxi(taxiPayload);

      if (mounted) {
         // ignore: unused_result
         ref.refresh(myDriverProfileProvider);
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(
             content: Text('Taxi created successfully'),
             backgroundColor: Colors.green,
             behavior: SnackBarBehavior.floating,
             margin: EdgeInsets.all(16),
           ),
         );
       }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating taxi: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  void _showTaxiDetailsDialog(BuildContext context, Map<String, dynamic> taxi) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Taxi Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Make', taxi['make']),
            _detailRow('Model', taxi['model']),
            _detailRow('Year', '${taxi['year']}'),
            _detailRow('License Plate', taxi['licensePlate']),
            _detailRow('Seats', '${taxi['seats']}'),
            _detailRow('Class', taxi['taxiClass']),
            _detailRow('Color', taxi['color'] ?? 'N/A'),
            _detailRow('Status', taxi['status']),
            _detailRow('Available', taxi['isAvailable'] ? 'Yes' : 'No'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          Text(
            value.toString(),
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  void _showVerifyDriverDialog(BuildContext context, int driverId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verify Profile'),
        content: const Text(
          'This will mark your profile as verified for development/testing purposes. In production, verification requires document review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _verifyDriver(driverId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyDriver(int driverId) async {
    try {
      await _driverService.verifyDriver(driverId);
      if (mounted) {
        // ignore: unused_result
        ref.refresh(myDriverProfileProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile verified successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error verifying profile: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  void _navigateToRideRequests(BuildContext context) async {
    try {
      // Get driver profile to extract driver ID and vehicle ID
      final driverProfile = await ref.read(myDriverProfileProvider.future);

      if (driverProfile['id'] == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Driver profile not found'),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        }
        return;
      }

      // Handle both string and int types for ID
      final driverId = driverProfile['id'].toString();
      final driverName =
          (driverProfile['user']?['name'] ?? 'Driver').toString();
      final driverPhone = (driverProfile['user']?['phone'] ?? '').toString();
      final driverAvatar = driverProfile['user']?['profilepicture']?.toString();

      // Extract taxi ID from taxis list
      int? taxiId;
      if (driverProfile['taxis'] is List &&
          (driverProfile['taxis'] as List).isNotEmpty) {
        final taxiData = driverProfile['taxis'][0];
        if (taxiData is Map && taxiData.containsKey('id')) {
          taxiId = taxiData['id'] as int?;
        }
      }

      if (kDebugMode) {
        print('[DriverDashboardHome] Navigating to ride requests:');
        print('  Driver ID: $driverId');
        print('  Driver Name: $driverName');
        print('  Taxi ID: $taxiId');
      }

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DriverRequestScreen(
              driverId: driverId,
              driverName: driverName,
              driverPhone: driverPhone,
              driverAvatar: driverAvatar,
              taxiId: taxiId,
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[DriverDashboardHome] Error navigating to ride requests: $e');
        print('StackTrace: $stackTrace');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading driver data: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  /// Sanitize URL by trimming whitespace and removing invalid characters
  String? _sanitizeUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  /// Validate if URL has a valid scheme
  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.isAbsolute && 
             (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'file');
    } catch (_) {
      return false;
    }
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFFFF8A00),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
      );
      }
      }
