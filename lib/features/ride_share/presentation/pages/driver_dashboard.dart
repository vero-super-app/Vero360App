import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/settings/Settings.dart';
import 'driver_request_screen.dart';

class DriverDashboard extends ConsumerStatefulWidget {
  const DriverDashboard({super.key});

  @override
  ConsumerState<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends ConsumerState<DriverDashboard> {
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
            if (kDebugMode)
              print('[DriverDashboard] Driver profile incomplete');
            return;
          }

          var taxiId = driver['taxis']?.isNotEmpty == true
              ? driver['taxis'][0]['id']
              : null;

          if (kDebugMode) {
            print(
                '[DriverDashboard] Driver ID: ${driver['id']}, Taxis: ${driver['taxis']}');
            print('[DriverDashboard] Extracted taxiId: $taxiId');
          }

          // If no taxi exists, create one
          if (taxiId == null) {
            if (kDebugMode)
              print('[DriverDashboard] No taxi found, creating default taxi...');
            try {
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final taxiPayload = {
                'make': 'Default',
                'model': 'Vehicle',
                'year': DateTime.now().year,
                'licensePlate': 'DRV${driver['id']}-$timestamp',
                'seats': 4,
                'taxiClass': 'STANDARD',
                'color': 'White',
                'registrationNumber': 'REG${driver['id']}-$timestamp',
              };
              if (kDebugMode)
                print(
                    '[DriverDashboard] Creating taxi with payload: $taxiPayload');

              final newTaxi = await _driverService.createTaxi(taxiPayload);
              taxiId = newTaxi['id'];
              if (kDebugMode)
                print('[DriverDashboard] ✓ Created taxi with ID: $taxiId');
            } catch (e) {
              if (kDebugMode) {
                print('[DriverDashboard] ✗ Error creating taxi: $e');
                print('[DriverDashboard] Error type: ${e.runtimeType}');
                if (e is DioException) {
                  print(
                      '[DriverDashboard] Status code: ${e.response?.statusCode}');
                  print('[DriverDashboard] Response: ${e.response?.data}');
                }
              }
              return;
            }
          }

          // Broadcast location
          if (taxiId != null) {
            try {
              await _driverService.updateTaxiLocation(
                  int.parse(taxiId.toString()),
                  position.latitude,
                  position.longitude);
              if (kDebugMode) {
                print(
                    '[DriverDashboard] ✓ Broadcasting location to taxi $taxiId: ${position.latitude}, ${position.longitude}');
              }
            } catch (e) {
              if (kDebugMode) {
                print('[DriverDashboard] ✗ Error updating taxi location: $e');
              }
            }
          }
        });
      } catch (e) {
        if (kDebugMode) {
          print('[DriverDashboard] Error getting position: $e');
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
    _mapCenteringTimer =
        Timer.periodic(const Duration(seconds: 5), (_) async {
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: primaryColor,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
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
                      color: Colors.black.withOpacity(0.1),
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
      ),
    );
  }

  Widget _buildMap() {
    return GoogleMap(
      onMapCreated: (controller) {
        mapController = controller;
        // Animate to driver's last known position if available
        if (_lastPosition != null) {
          Future.delayed(const Duration(milliseconds: 300), () {
            mapController?.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: LatLng(_lastPosition!.latitude, _lastPosition!.longitude),
                  zoom: 15.0,
                ),
              ),
            );
          });
        }
      },
      initialCameraPosition: CameraPosition(
        target: _lastPosition != null
            ? LatLng(_lastPosition!.latitude, _lastPosition!.longitude)
            : const LatLng(-13.1939, 34.3015),
        zoom: 15,
      ),
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: true,
      compassEnabled: true,
      mapToolbarEnabled: false,
    );
  }

  Widget _buildProfileCard(WidgetRef ref) {
    final driverProfile = ref.watch(myDriverProfileProvider);

    return driverProfile.when(
      data: (driver) {
        // Check if driver profile is empty or invalid
        if (driver.isEmpty || driver['id'] == null) {
          return _buildNoDriverProfile();
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.grey[200]!,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                        radius: 32,
                        backgroundImage:
                            driver['user']?['profilepicture'] != null &&
                                    driver['user']['profilepicture']
                                        .toString()
                                        .isNotEmpty
                                ? NetworkImage(
                                    driver['user']['profilepicture'].toString())
                                : null,
                        backgroundColor: primaryColor.withOpacity(0.1),
                        child: driver['user']?['profilepicture'] == null ||
                                driver['user']['profilepicture']
                                    .toString()
                                    .isEmpty
                            ? Icon(
                                Icons.person,
                                size: 32,
                                color: primaryColor,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (driver['user']?['name'] ?? 'Driver').toString(),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getBoolValue(driver['isVerified'])
                                  ? Colors.green.shade50
                                  : primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _getBoolValue(driver['isVerified'])
                                    ? Colors.green.shade200
                                    : primaryColor.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getBoolValue(driver['isVerified'])
                                      ? Icons.verified
                                      : Icons.pending_actions,
                                  size: 12,
                                  color: _getBoolValue(driver['isVerified'])
                                      ? Colors.green
                                      : primaryColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _getBoolValue(driver['isVerified'])
                                      ? 'Verified'
                                      : 'Pending',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _getBoolValue(driver['isVerified'])
                                        ? Colors.green
                                        : primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(height: 1, color: Colors.grey[200]),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                        'Rating', '${_getNumericValue(driver['rating'])}/5'),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey[200],
                    ),
                    _buildStatItem(
                        'Rides', '${_getNumericValue(driver['totalRides'])}'),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey[200],
                    ),
                    _buildStatItem('Accepted',
                        '${_getNumericValue(driver['acceptedRides'])}'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
      error: (error, stack) {
        // If driver profile doesn't exist, show create profile option
        final errorStr = error.toString().toLowerCase();
        if (errorStr.contains('404') || errorStr.contains('not found')) {
          return _buildNoDriverProfile();
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
              const SizedBox(height: 8),
              Text(
                'Error loading profile',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                error.toString(),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoDriverProfile() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primaryColor.withOpacity(0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              Icons.person_add_outlined,
              size: 48,
              color: primaryColor,
            ),
            const SizedBox(height: 12),
            const Text(
              'Driver Profile Not Found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You need to create a driver profile to access the driver dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Driver profile creation coming soon! Please contact support to set up your driver account.',
                      ),
                      backgroundColor: primaryColor,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                },
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Contact Support'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Helper to safely get numeric values (handles both int and string)
  dynamic _getNumericValue(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value;
    if (value is String) {
      return num.tryParse(value) ?? 0;
    }
    return 0;
  }

  /// Helper to safely get boolean values (handles various types)
  bool _getBoolValue(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    if (value is num) return value != 0;
    return false;
  }

  Widget _buildStatsSection(WidgetRef ref) {
    final driverProfile = ref.watch(myDriverProfileProvider);

    return driverProfile.when(
      data: (driver) {
        // Handle missing or invalid driver profile
        if (driver.isEmpty || driver['id'] == null) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Performance',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Completed',
                    '${_getNumericValue(driver['completedRides'])}',
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Cancelled',
                    '${_getNumericValue(driver['cancelledRides'])}',
                    Colors.red,
                  ),
                ),
              ],
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection(BuildContext context) {
    final driverProfile = ref.watch(myDriverProfileProvider);

    return driverProfile.when(
      data: (driver) {
        final isVerified = _getBoolValue(driver['isVerified']);
        final hasTaxis = driver['taxis'] is List && (driver['taxis'] as List).isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),

            // Development Section Header
            if (!isVerified || !hasTaxis)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Complete setup to start receiving rides',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Taxi Management Section
            if (!hasTaxis)
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => _showCreateTaxiDialog(context),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Create Taxi'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              )
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => _showTaxiDetailsDialog(context, driver['taxis'][0]),
                      icon: const Icon(Icons.directions_car),
                      label: const Text('Manage Taxi'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),

            // Verification Section
            if (!isVerified)
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => _showVerifyDriverDialog(context, driver['id']),
                      icon: const Icon(Icons.verified_user),
                      label: const Text('Verify Profile'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),

            // Online/Offline Toggle
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (_isOnline) {
                    _stopLocationBroadcasting();
                  } else {
                    _startLocationBroadcasting();
                  }
                },
                icon: Icon(_isOnline ? Icons.cloud_done : Icons.cloud_off),
                label: Text(_isOnline ? 'Go Offline' : 'Go Online'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isOnline ? Colors.green : Colors.grey,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // View Ride Requests Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: isVerified && hasTaxis
                    ? () => _navigateToRideRequests(context)
                    : null,
                icon: const Icon(Icons.local_taxi_outlined),
                label: const Text('View Ride Requests'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: (isVerified && hasTaxis) ? primaryColor : Colors.grey[400],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
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
        ref.refresh(myDriverProfileProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Taxi created successfully'),
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
      if (driverProfile['taxis'] is List && (driverProfile['taxis'] as List).isNotEmpty) {
        final taxiData = driverProfile['taxis'][0];
        if (taxiData is Map && taxiData.containsKey('id')) {
          taxiId = taxiData['id'] as int?;
        }
      }

      if (kDebugMode) {
        print('[DriverDashboard] Navigating to ride requests:');
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
        print('[DriverDashboard] Error navigating to ride requests: $e');
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
}
