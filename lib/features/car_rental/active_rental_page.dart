import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/car_rental_service.dart';
import 'package:vero360_app/GernalServices/trip_tracking_service.dart';
import 'package:vero360_app/GeneralModels/car_model.dart';
import 'package:vero360_app/GeneralModels/car_booking_model.dart';
import 'package:vero360_app/GeneralModels/trip_log_model.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'rental_complete_page.dart';

class ActiveRentalPage extends StatefulWidget {
  final CarBookingModel booking;
  final CarModel car;

  const ActiveRentalPage({
    required this.booking,
    required this.car,
    super.key,
  });

  @override
  State<ActiveRentalPage> createState() => _ActiveRentalPageState();
}

class _ActiveRentalPageState extends State<ActiveRentalPage> {
  late TripTrackingService _trackingService;
  late CarRentalService _rentalService;
  double _totalDistance = 0;
  int _secondsElapsed = 0;
  late Timer _timer;
  late Timer _costTimer;
  bool _ending = false;
  double _liveCost = 0;
  final double _fuelLevel = 85.0;
  String _currentLocationAddress = 'Loading location...';
  bool _showIssueReport = false;

  @override
  void initState() {
    super.initState();
    _trackingService = TripTrackingService();
    _rentalService = CarRentalService();

    // Start GPS tracking simulation
    _trackingService.simulatePositionUpdates(
      widget.car.id,
      const Duration(seconds: 10),
    );

    // Timer for elapsed time
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _secondsElapsed++);
      }
    });

    // Timer for live cost updates (every minute)
    _costTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        _updateLiveCost();
      }
    });

    // Initial location load
    _loadLocationAddress();
  }

  void _updateLiveCost() {
    // Calculate live cost based on elapsed time
    final hoursPassed = _secondsElapsed / 3600;
    final dailyRate = widget.car.dailyRate;
    setState(() {
      _liveCost = hoursPassed * (dailyRate / 24);
    });
  }

  Future<void> _loadLocationAddress() async {
    // Simulate address lookup from GPS coordinates
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        _currentLocationAddress = 'Lilongwe, Malawi';
      });
    }
  }

  @override
  void dispose() {
    _trackingService.stopTracking();
    _timer.cancel();
    _costTimer.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    final s = duration.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _endRental() async {
    try {
      setState(() => _ending = true);

      await _rentalService.completeRental(widget.booking.id);

      // Calculate total distance
      _totalDistance =
          await _trackingService.getTotalDistance(widget.booking.id);

      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Rental completed!',
          isSuccess: true,
          errorMessage: '',
        );

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RentalCompletePage(
                booking: widget.booking,
                totalDistance: _totalDistance,
                elapsedSeconds: _secondsElapsed,
                car: widget.car,
              ),
            ),
          );
        }
      }
    } on CarRentalException catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          e.message,
          isSuccess: false,
          errorMessage: e.message,
        );
        setState(() => _ending = false);
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Error: $e',
          isSuccess: false,
          errorMessage: 'Error: $e',
        );
        setState(() => _ending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.car.brand} ${widget.car.model}'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Colors.green, size: 8),
                    const SizedBox(width: 6),
                    Text(
                      'Owner Monitoring',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Live location map (placeholder)
          Expanded(
            flex: 2,
            child: StreamBuilder<TripLogModel>(
              stream: _trackingService.positionStream,
              builder: (context, snapshot) {
                return Container(
                  color: Colors.grey[200],
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 80,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        if (snapshot.hasData)
                          Column(
                            children: [
                              Text(
                                'GPS Location',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Lat: ${snapshot.data!.latitude.toStringAsFixed(4)}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                'Lon: ${snapshot.data!.longitude.toStringAsFixed(4)}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              if (snapshot.data!.speed != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Speed: ${snapshot.data!.speed!.toStringAsFixed(1)} km/h',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          )
                        else
                          Column(
                            children: [
                              const Text('Waiting for GPS data...'),
                              const SizedBox(height: 16),
                              const CircularProgressIndicator(),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Trip stats and details
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Stats cards
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatCard(
                          label: 'Time',
                          value: _formatDuration(_secondsElapsed),
                          icon: Icons.timer,
                        ),
                        _StatCard(
                          label: 'Distance',
                          value: '${_totalDistance.toStringAsFixed(1)} km',
                          icon: Icons.location_on,
                        ),
                        _StatCard(
                          label: 'Live Cost',
                          value: 'MWK${_liveCost.toStringAsFixed(0)}',
                          icon: Icons.attach_money,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Trip details section
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Current Location',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                              ),
                              Icon(Icons.location_on, size: 16, color: Colors.blue),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currentLocationAddress,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _fuelLevel / 100,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _fuelLevel > 30 ? Colors.green : Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Fuel: ${_fuelLevel.toStringAsFixed(0)}%',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Report issue button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() => _showIssueReport = !_showIssueReport);
                        },
                        icon: const Icon(Icons.warning),
                        label: const Text('Report Issue'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.orange[700]!),
                        ),
                      ),
                    ),

                    // Issue report form
                    if (_showIssueReport) ...[
                      const SizedBox(height: 12),
                      _buildIssueReportForm(context),
                    ],

                    const SizedBox(height: 16),

                    // End rental button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _ending ? null : _endRental,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.all(16),
                          disabledBackgroundColor: Colors.grey,
                        ),
                        child: _ending
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'End Rental',
                                style: TextStyle(
                                  fontSize: 16,
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

  Widget _buildIssueReportForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Report an Issue',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[900],
                ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: 'Issue Type',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              'Engine Problem',
              'Tire Issue',
              'Brake Problem',
              'Electrical Issue',
              'Other',
            ]
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (value) {},
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Camera access needed')),
                    );
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Add Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Accident report sent to owner'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  },
                  icon: const Icon(Icons.emergency),
                  label: const Text('Accident'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 32, color: const Color(0xFFFF8A00)),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
