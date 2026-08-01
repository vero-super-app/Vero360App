import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/GernalServices/driver_request_service.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/driver_ride_request_sheet.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

/// Incoming ride request overlay — navy premium sheet with countdown timer.
class RideNotificationPopup extends StatefulWidget {
  final DriverRideRequest rideRequest;
  final WidgetRef ref;
  final VoidCallback onDismiss;
  final VoidCallback onAccept;
  final Duration timeout;

  const RideNotificationPopup({
    super.key,
    required this.rideRequest,
    required this.ref,
    required this.onDismiss,
    required this.onAccept,
    this.timeout = const Duration(seconds: 15),
  });

  @override
  State<RideNotificationPopup> createState() => _RideNotificationPopupState();
}

class _RideNotificationPopupState extends State<RideNotificationPopup>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _timerController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  double? _pickupKm;
  int? _pickupMins;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 380),
      vsync: this,
    );
    _timerController = AnimationController(
      duration: widget.timeout,
      vsync: this,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _fadeAnim =
        CurvedAnimation(parent: _slideController, curve: Curves.easeOut);

    _slideController.forward();
    _timerController.forward();
    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _dismiss();
      }
    });

    unawaited(_resolvePickupEta());
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
        widget.rideRequest.pickupLat,
        widget.rideRequest.pickupLng,
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

  Future<void> _dismiss() async {
    await _slideController.reverse();
    if (mounted) widget.onDismiss();
  }

  Future<void> _accept() async {
    _timerController.stop();
    await _slideController.reverse();
    if (mounted) widget.onAccept();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _timerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            GestureDetector(
              onTap: _dismiss,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Container(
                  color:
                      RideShareColors.primaryContainer.withValues(alpha: 0.4),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: _slideAnim,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Material(
                      color: Colors.transparent,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: DriverRideRequestSheet(
                          request: widget.rideRequest,
                          timer: _timerController,
                          pickupKm: _pickupKm,
                          pickupMins: _pickupMins,
                          passengerShort:
                              shortPassengerName(widget.rideRequest.passengerName),
                          onAccept: _accept,
                          onDecline: _dismiss,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
