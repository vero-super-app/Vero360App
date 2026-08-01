import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/GernalServices/driver_request_service.dart';
import 'package:vero360_app/GernalServices/driver_messaging_service.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/driver_ride_execution_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/driver_ride_request_sheet.dart';

class DriverRequestAcceptDialog extends StatefulWidget {
  final DriverRideRequest request;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String? driverAvatar;
  final int? taxiId;
  final Function()? onAccepted;
  final Function()? onRejected;

  const DriverRequestAcceptDialog({
    super.key,
    required this.request,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    this.driverAvatar,
    this.taxiId,
    this.onAccepted,
    this.onRejected,
  });

  @override
  State<DriverRequestAcceptDialog> createState() =>
      _DriverRequestAcceptDialogState();
}

class _DriverRequestAcceptDialogState extends State<DriverRequestAcceptDialog>
    with SingleTickerProviderStateMixin {
  bool _isAccepting = false;
  bool _isRejecting = false;
  double? _pickupKm;
  int? _pickupMins;
  late AnimationController _timerController;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    )..forward();
    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          mounted &&
          !_isAccepting &&
          !_isRejecting) {
        _dismissRequest();
      }
    });
    unawaited(_resolvePickupEta());
  }

  @override
  void dispose() {
    _timerController.dispose();
    super.dispose();
  }

  Future<void> _resolvePickupEta() async {
    try {
      final pos = await LocationPermissionHelper.getCurrentPositionIfGranted(
        timeLimit: const Duration(seconds: 3),
      );
      if (pos == null || !mounted) return;
      final meters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        widget.request.pickupLat,
        widget.request.pickupLng,
      );
      final km = meters / 1000.0;
      final mins = (km * 2.5).ceil().clamp(1, 60);
      if (!mounted) return;
      setState(() {
        _pickupKm = km;
        _pickupMins = mins;
      });
    } catch (_) {}
  }

  Future<void> _acceptRequest() async {
    setState(() => _isAccepting = true);
    _timerController.stop();

    try {
      await DriverRequestService.acceptRideRequest(
        rideId: widget.request.id,
        driverId: widget.driverId,
        driverName: widget.driverName,
        driverPhone: widget.driverPhone,
        driverAvatar: widget.driverAvatar,
        taxiId: widget.taxiId,
      );

      try {
        await DriverMessagingService.ensureRideThread(
          rideId: widget.request.id,
          passengerId: widget.request.passengerId,
          driverId: widget.driverId,
          passengerName: widget.request.passengerName,
          driverName: widget.driverName,
          passengerAvatar: null,
          driverAvatar: widget.driverAvatar,
        );

        await DriverMessagingService.sendSystemMessage(
          rideId: widget.request.id,
          message: '${widget.driverName} accepted your ride request',
        );
      } catch (e) {
        print('Warning: Failed to create messaging thread: $e');
      }

      if (mounted) {
        Navigator.of(context).pop(true);

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DriverRideExecutionScreen(
              rideId: int.tryParse(widget.request.id) ?? 0,
              onRideEnded: () {
                widget.onAccepted?.call();
              },
            ),
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ride request accepted! Navigate to pickup.'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAccepting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept ride: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  Future<void> _dismissRequest() async {
    setState(() => _isRejecting = true);
    _timerController.stop();

    try {
      await DriverRequestService.rejectRideRequest(widget.request.id);
    } catch (e) {
      // Still dismiss locally — offer is suppressed client-side even if
      // the decline call fails (e.g. offline).
      debugPrint('Decline request failed (dismissing anyway): $e');
    }

    if (!mounted) return;
    Navigator.of(context).pop(false);
    widget.onRejected?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Ride request declined'),
        backgroundColor: Colors.orange.shade600,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      alignment: Alignment.bottomCenter,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: DriverRideRequestSheet(
          request: widget.request,
          timer: _timerController,
          pickupKm: _pickupKm,
          pickupMins: _pickupMins,
          passengerShort: shortPassengerName(widget.request.passengerName),
          accepting: _isAccepting,
          declining: _isRejecting,
          onAccept: _acceptRequest,
          onDecline: _dismissRequest,
        ),
      ),
    );
  }
}
