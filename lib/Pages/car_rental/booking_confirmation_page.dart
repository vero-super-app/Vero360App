import 'package:flutter/material.dart';
import 'package:vero360_app/services/car_rental_service.dart';
import 'package:vero360_app/services/car_pricing_service.dart';
import 'package:vero360_app/models/car_model.dart';
import 'package:vero360_app/models/rental_cost_model.dart';
import 'package:vero360_app/toasthelper.dart';

class BookingConfirmationPage extends StatefulWidget {
  final CarModel car;
  final DateTime startDate;
  final DateTime endDate;

  const BookingConfirmationPage({
    required this.car,
    required this.startDate,
    required this.endDate,
    super.key,
  });

  @override
  State<BookingConfirmationPage> createState() =>
      _BookingConfirmationPageState();
}

class _BookingConfirmationPageState extends State<BookingConfirmationPage> {
  late CarRentalService _rentalService;
  late CarPricingService _pricingService;
  late RentalCostModel _costBreakdown;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _rentalService = CarRentalService();
    _pricingService = CarPricingService();

    // Pre-calculate cost
    _costBreakdown = _pricingService.calculateRentalCost(
      dailyRate: widget.car.dailyRate,
      startDate: widget.startDate,
      endDate: widget.endDate,
    );
  }

  Future<void> _confirmBooking() async {
    try {
      setState(() => _loading = true);

      final booking = await _rentalService.createBooking(
        carId: widget.car.id,
        startDate: widget.startDate,
        endDate: widget.endDate,
      );

      // Cache for quick access
      await _rentalService.cacheActiveBooking(booking);

      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Booking confirmed!',
          isSuccess: true,
          errorMessage: '',
        );
        Navigator.pop(context, booking);
      }
    } on CarRentalException catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          e.message,
          isSuccess: false,
          errorMessage: e.message,
        );
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Booking failed: $e',
          isSuccess: false,
          errorMessage: 'Error: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Booking')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Car details
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.car.brand} ${widget.car.model}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('License: ${widget.car.licensePlate}'),
                    const SizedBox(height: 4),
                    Text('Seats: ${widget.car.seats}'),
                    const SizedBox(height: 4),
                    Text('Fuel: ${widget.car.fuelType}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Rental dates
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rental Period',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 20, color: Color(0xFFFF8A00)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${widget.startDate.toString().split(' ')[0]} - '
                            '${widget.endDate.toString().split(' ')[0]}',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.timer,
                            size: 20, color: Color(0xFFFF8A00)),
                        const SizedBox(width: 12),
                        Text(
                          '${_costBreakdown.days} day(s)',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Cost breakdown
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cost Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Daily Rate'),
                        Text(
                          _costBreakdown.dailyRateFormatted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Number of Days'),
                        Text('${_costBreakdown.days}'),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _costBreakdown.totalFormatted,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Color(0xFFFF8A00),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Confirm button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _confirmBooking,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: const Color(0xFFFF8A00),
                  disabledBackgroundColor: Colors.grey,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Confirm & Book',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'By confirming, you agree to our rental terms',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
