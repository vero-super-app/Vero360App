import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vero360_app/services/car_rental_service.dart';
import 'package:vero360_app/services/trip_tracking_service.dart';
import 'package:vero360_app/models/car_model.dart';
import 'package:vero360_app/models/car_booking_model.dart';
import 'package:vero360_app/models/trip_log_model.dart';
import 'package:vero360_app/toasthelper.dart';
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
  bool _ending = false;

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
  }

  @override
  void dispose() {
    _trackingService.stopTracking();
    _timer.cancel();
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

          // Trip stats
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
                          label: 'Cost',
                          value:
                              'MWK${widget.booking.totalCost.toStringAsFixed(0)}',
                          icon: Icons.attach_money,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

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
