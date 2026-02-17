// lib/features/AirportPickup/AirportPresenter/airport_pickup_progress_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/features/AirportPickup/AirportModels/Airport_pickup.models.dart';
import 'package:vero360_app/features/AirportPickup/AirportService/airport_pickup_service.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/utils/toasthelper.dart';

class AirportPickupProgressPage extends StatefulWidget {
  final AirportPickupBooking booking;

  const AirportPickupProgressPage({
    super.key,
    required this.booking,
  });

  @override
  State<AirportPickupProgressPage> createState() =>
      _AirportPickupProgressPageState();
}

class _AirportPickupProgressPageState extends State<AirportPickupProgressPage> {
  static const _brandOrange = Color(0xFFFF8A00);
  static const _brandSoft = Color(0xFFFFE8CC);

  final _airportService = const AirportPickupService();
  late AirportPickupBooking _booking;
  bool _loading = false;
  String? _authToken;
  Timer? _pollTimer;

  /// Statuses where driver has accepted – user can leave without cancelling.
  static const _driverAcceptedStatuses = {
    'accepted', 'on_the_way', 'driver_started', 'eta_30_mins',
    'eta_soon', 'driver_arrived', 'completed',
  };

  bool get _driverHasAccepted {
    final s = _booking.status.toLowerCase().replaceAll(' ', '_');
    return _driverAcceptedStatuses.contains(s);
  }

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
    _loadToken();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fetchLatest());
  }

  Future<void> _fetchLatest() async {
    if (!mounted || _loading) return;
    final s = _booking.status.toLowerCase();
    if (s == 'cancelled' || s == 'completed') {
      _pollTimer?.cancel();
      return;
    }
    final token = _authToken;
    final updated = token != null
        ? await _airportService.getBookingById(_booking.id, authToken: token)
        : await _airportService.getBookingById(_booking.id);
    if (mounted && updated != null) {
      setState(() => _booking = updated);
    }
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ??
        prefs.getString('token') ??
        prefs.getString('jwt');
    if (mounted) setState(() => _authToken = token);
  }

  /// Returns true if cancel succeeded (caller can then pop).
  Future<bool> _cancelRequest() async {
    final token = _authToken;
    if (token == null || token.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Sign in to cancel this pickup.',
        isSuccess: false,
        errorMessage: '',
      );
      return false;
    }
    if (_booking.status.toLowerCase() == 'cancelled') {
      ToastHelper.showCustomToast(
        context,
        'This pickup is already cancelled.',
        isSuccess: false,
        errorMessage: '',
      );
      return true; // already cancelled, safe to leave
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel pickup?'),
        content: const Text(
          'Do you want to cancel this airport pickup request?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return false;

    setState(() => _loading = true);
    try {
      final updated = await _airportService.cancelBooking(
        _booking.id,
        authToken: token,
      );
      if (mounted) {
        setState(() {
          _booking = updated;
          _loading = false;
        });
        ToastHelper.showCustomToast(
          context,
          'Pickup request cancelled.',
          isSuccess: true,
          errorMessage: '',
        );
        return true;
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ToastHelper.showCustomToast(context, e.message, isSuccess: false, errorMessage: e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ToastHelper.showCustomToast(
          context,
          'Could not cancel. Please try again.',
          isSuccess: false,
          errorMessage: '',
        );
      }
    }
    return false;
  }

  Future<void> _onBackPressed() async {
    final isCancelled = _booking.status.toLowerCase() == 'cancelled';
    if (isCancelled || _driverHasAccepted) {
      if (context.mounted) Navigator.of(context).pop(_booking);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this screen?'),
        content: const Text(
          'Leaving will cancel your airport pickup. Are you sure you want to cancel and go back?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, cancel and leave'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    final didCancel = await _cancelRequest();
    if (mounted && didCancel) Navigator.of(context).pop(_booking);
  }

  @override
  Widget build(BuildContext context) {
    final status = _booking.status;
    final canCancel = status.toLowerCase() == 'pending' &&
        _authToken != null &&
        _authToken!.isNotEmpty;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onBackPressed();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF222222),
          elevation: 0,
          title: const Text('Pickup progress'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _onBackPressed();
            },
          ),
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: _brandOrange))
            : RefreshIndicator(
                onRefresh: _fetchLatest,
                color: _brandOrange,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStatusCard(status),
                    const SizedBox(height: 16),
                    _buildJourneyProgressCard(),
                    const SizedBox(height: 16),
                    _buildUserDetailsCard(),
                    const SizedBox(height: 16),
                    _buildTripDetailsCard(),
                    const SizedBox(height: 24),
                    if (canCancel) _buildCancelButton(),
                  ],
                ),
              ),
      ),
    );
  }

  static String _statusLabel(String status) {
    final lower = status.toLowerCase().replaceAll(' ', '_');
    switch (lower) {
      case 'cancelled':
        return 'Cancelled';
      case 'completed':
        return 'Completed';
      case 'driver_arrived':
        return 'Driver arrived';
      case 'eta_soon':
        return 'Almost there';
      case 'eta_30_mins':
        return 'About 30 mins away';
      case 'driver_started':
        return 'Driver started';
      case 'on_the_way':
        return 'On the way';
      case 'accepted':
        return 'Accepted';
      default:
        return 'Pending';
    }
  }

  Widget _buildStatusCard(String status) {
    final lower = status.toLowerCase();
    Color bg;
    IconData icon;
    if (lower == 'cancelled') {
      bg = Colors.red.shade50;
      icon = Icons.cancel_outlined;
    } else if (lower == 'completed') {
      bg = Colors.green.shade50;
      icon = Icons.check_circle_outline;
    } else if (lower == 'driver_arrived' || lower == 'eta_soon') {
      bg = _brandSoft;
      icon = Icons.location_on;
    } else if (lower == 'eta_30_mins' || lower == 'driver_started' || lower == 'on_the_way' || lower == 'accepted') {
      bg = _brandSoft;
      icon = Icons.directions_car;
    } else {
      bg = _brandSoft;
      icon = Icons.schedule;
    }
    final label = _statusLabel(status);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brandOrange.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _brandOrange.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _brandOrange, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF222222),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJourneyProgressCard() {
    final status = _booking.status.toLowerCase().replaceAll(' ', '_');
    final steps = [
      ('pending', 'Booked', Icons.event_available),
      ('accepted', 'Accepted', Icons.thumb_up_outlined),
      ('on_the_way', 'On the way', Icons.directions_car),
      ('driver_started', 'Driver started', Icons.play_arrow),
      ('eta_30_mins', '~30 mins away', Icons.schedule),
      ('eta_soon', 'Almost there', Icons.near_me),
      ('driver_arrived', 'Driver arrived', Icons.location_on),
      ('completed', 'Completed', Icons.check_circle),
    ];
    final completedIndex = status == 'cancelled'
        ? -1
        : steps.indexWhere((s) => s.$1 == status).clamp(-1, steps.length);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route, color: _brandOrange, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Journey progress',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF222222),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (status == 'cancelled') ...[
            Center(
              child: Text(
                'This pickup was cancelled.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ] else ...[
            ...steps.asMap().entries.map((entry) {
              final i = entry.key;
              final (key, label, iconData) = entry.value;
              final isDone = completedIndex >= i;
              final isCurrent = key == status;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isDone
                                ? _brandOrange
                                : (isCurrent ? _brandOrange.withValues(alpha: 0.3) : Colors.grey.shade200),
                            shape: BoxShape.circle,
                            border: isCurrent
                                ? Border.all(color: _brandOrange, width: 2)
                                : null,
                          ),
                          child: Icon(
                            iconData,
                            size: 16,
                            color: isDone || isCurrent ? Colors.white : Colors.grey.shade500,
                          ),
                        ),
                        if (i < steps.length - 1)
                          Container(
                            width: 2,
                            height: 24,
                            color: isDone ? _brandOrange : Colors.grey.shade200,
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                            color: isDone || isCurrent
                                ? const Color(0xFF222222)
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (_booking.journeyMessage != null &&
                _booking.journeyMessage!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _brandSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _brandOrange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.message_outlined, color: _brandOrange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _booking.journeyMessage!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF222222),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildUserDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, color: _brandOrange, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Contact details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF222222),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _detailRow('Name', _booking.customerName ?? '—'),
          const SizedBox(height: 12),
          _detailRow('Phone', _booking.customerPhone ?? '—'),
        ],
      ),
    );
  }

  Widget _buildTripDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flight_takeoff_rounded, color: _brandOrange, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Trip details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF222222),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _detailRow('Airport', '${_booking.airportName} (${_booking.airportCode})'),
          const SizedBox(height: 12),
          _detailRow('City', _booking.serviceCity),
          const SizedBox(height: 12),
          _detailRow('Vehicle', _booking.vehicleLabel),
          const SizedBox(height: 12),
          _detailRow('Distance', '${_booking.distanceKm.toStringAsFixed(1)} km'),
          const SizedBox(height: 12),
          _detailRow('Fare', 'MWK ${_booking.estimatedFare}'),
          if (_booking.dropoffAddressText != null &&
              _booking.dropoffAddressText!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _detailRow('Drop-off', _booking.dropoffAddressText!),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF222222),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _cancelRequest,
        icon: const Icon(Icons.cancel_outlined, size: 20),
        label: const Text('Cancel pickup request'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red.shade700,
          side: BorderSide(color: Colors.red.shade300),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
