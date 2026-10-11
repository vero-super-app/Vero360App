import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/GernalServices/driver_messaging_service.dart';
import 'package:vero360_app/GernalServices/driver_request_service.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/driver_ride_execution_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/services/driver_ride_alert_notifications.dart';
import 'package:vero360_app/features/ride_share/presentation/services/driver_ride_offer_inbox.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/driver_ride_request_sheet.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

/// Full-screen accept popup shown from a lock-screen / background ride push.
class DriverIncomingRideFromNotificationPage extends StatefulWidget {
  final String rideId;
  final Map<String, dynamic>? fcmData;

  const DriverIncomingRideFromNotificationPage({
    super.key,
    required this.rideId,
    this.fcmData,
  });

  @override
  State<DriverIncomingRideFromNotificationPage> createState() =>
      _DriverIncomingRideFromNotificationPageState();
}

class _DriverIncomingRideFromNotificationPageState
    extends State<DriverIncomingRideFromNotificationPage>
    with SingleTickerProviderStateMixin {
  String? _error;
  bool _accepting = false;
  bool _declining = false;
  DriverRideRequest? _request;
  Map<String, dynamic>? _driver;
  double? _pickupKm;
  int? _pickupMins;
  late AnimationController _timerController;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    );
    final seeded = DriverRideOfferInbox.fromFcmMap(
      widget.fcmData ??
          <String, dynamic>{'rideId': widget.rideId, 'type': 'new_ride'},
    );
    if (seeded?.hasPickupWindow != true) {
      _timerController.forward();
      _timerController.addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            mounted &&
            !_accepting &&
            !_declining) {
          unawaited(_decline(pop: true));
        }
      });
    }

    final seed = widget.fcmData ??
        <String, dynamic>{'rideId': widget.rideId, 'type': 'new_ride'};
    _request = seeded;
    unawaited(_hydrate(seed));
    unawaited(_resolvePickupEta());
  }

  @override
  void dispose() {
    _timerController.dispose();
    super.dispose();
  }

  Future<void> _hydrate(Map<String, dynamic> seed) async {
    try {
      final fetched =
          await DriverRideOfferInbox.instance.resolveFromPayload(seed);
      final driver = await DriverService().getMyDriverProfile();
      if (!mounted) return;
      setState(() {
        if (fetched != null) _request = fetched;
        _driver = driver;
      });
      if (fetched?.hasPickupWindow == true) {
        _timerController.stop();
      }
    } catch (e) {
      if (!mounted) return;
      if (_request == null) {
        setState(() {
          _error = UserFacingError.from(e, fallback: 'Could not open ride offer');
        });
      }
    }
  }

  Future<void> _resolvePickupEta() async {
    final request = _request;
    if (request == null) return;
    try {
      final pos = await LocationPermissionHelper.getCurrentPositionIfGranted(
        timeLimit: const Duration(seconds: 3),
      );
      if (pos == null || !mounted) return;
      final meters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        request.pickupLat,
        request.pickupLng,
      );
      final km = meters / 1000.0;
      if (!mounted) return;
      setState(() {
        _pickupKm = km;
        _pickupMins = (km * 2.5).ceil().clamp(1, 60);
      });
    } catch (_) {}
  }

  int? _taxiId(DriverRideRequest request) {
    final fromOffer = request.candidateTaxiId;
    if (fromOffer != null) return fromOffer;
    final taxis = _driver?['taxis'];
    if (taxis is List && taxis.isNotEmpty && taxis.first is Map) {
      return (taxis.first['id'] as num?)?.toInt();
    }
    return null;
  }

  Future<void> _offerEta(int minutes) async {
    final request = _request;
    if (request == null || _accepting || _declining) return;
    final taxiId = _taxiId(request);
    if (taxiId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Taxi is not ready to send a pickup time')),
      );
      return;
    }
    setState(() => _accepting = true);
    _timerController.stop();
    try {
      await DriverRequestService.submitPickupOffer(
        rideId: request.id,
        taxiId: taxiId,
        etaMinutes: minutes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Offered a pickup in $minutes min')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _accepting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFacingError.from(e, fallback: 'Could not send pickup time'))),
      );
    }
  }

  Future<void> _accept() async {
    final request = _request;
    if (request == null || _accepting || _declining) return;
    setState(() => _accepting = true);
    _timerController.stop();

    try {
      Map<String, dynamic> driver = _driver ?? {};
      if (driver.isEmpty) {
        driver = await DriverService().getMyDriverProfile();
      }
      final driverId = (driver['id'] ?? '').toString();
      final driverName =
          (driver['user']?['name'] ?? driver['name'] ?? 'Driver').toString();
      final driverPhone =
          (driver['user']?['phone'] ?? driver['phone'] ?? '').toString();
      final driverAvatar = (driver['user']?['profilepicture'] ??
              driver['profilepicture'])
          ?.toString();

      await DriverRequestService.acceptRideRequest(
        rideId: request.id,
        driverId: driverId,
        driverName: driverName,
        driverPhone: driverPhone,
        driverAvatar: driverAvatar,
        taxiId: _taxiId(request),
      );

      try {
        await DriverMessagingService.ensureRideThread(
          rideId: request.id,
          passengerId: request.passengerId,
          driverId: driverId,
          passengerName: request.passengerName,
          driverName: driverName,
          passengerAvatar: null,
          driverAvatar: driverAvatar,
        );
        await DriverMessagingService.sendSystemMessage(
          rideId: request.id,
          message: '$driverName accepted your ride request',
        );
      } catch (_) {}

      await DriverRideAlertNotifications.cancelOffer(request.id);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DriverRideExecutionScreen(
            rideId: int.tryParse(request.id) ?? 0,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _accepting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.from(e, fallback: 'Failed to accept ride')),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _decline({bool pop = true}) async {
    final request = _request;
    if (_declining) return;
    setState(() => _declining = true);
    _timerController.stop();
    try {
      if (request != null) {
        await DriverRequestService.rejectRideRequest(request.id);
        await DriverRideAlertNotifications.cancelOffer(request.id);
      }
    } catch (_) {}
    if (!mounted) return;
    if (pop) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    return Scaffold(
      backgroundColor: const Color(0xFF000613).withValues(alpha: 0.55),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              )
            : request == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: DriverRideRequestSheet(
                          request: request,
                          timer: request.hasPickupWindow ? null : _timerController,
                          pickupKm: _pickupKm,
                          pickupMins: _pickupMins,
                          passengerShort:
                              shortPassengerName(request.passengerName),
                          accepting: _accepting,
                          declining: _declining,
                          onAccept: _accept,
                          onDecline: () => unawaited(_decline()),
                          onOfferEta: (minutes) => unawaited(_offerEta(minutes)),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }
}
