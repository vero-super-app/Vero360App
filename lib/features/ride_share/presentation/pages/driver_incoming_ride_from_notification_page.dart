import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/features/ride_share/presentation/services/driver_ride_offer_inbox.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/driver_request_accept_dialog.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

/// Full-screen gate opened when the driver taps a `new_ride` push notification.
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
    extends State<DriverIncomingRideFromNotificationPage> {
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadAndShow());
    });
  }

  Future<void> _loadAndShow() async {
    if (!mounted) return;
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      final seed = widget.fcmData ??
          <String, dynamic>{'rideId': widget.rideId, 'type': 'new_ride'};
      final request =
          await DriverRideOfferInbox.instance.resolveFromPayload(seed);
      if (!mounted) return;
      if (request == null) {
        setState(() {
          _error = 'This ride is no longer available.';
          _loading = false;
        });
        return;
      }

      final driver = await DriverService().getMyDriverProfile();
      if (!mounted) return;

      int? taxiId = request.candidateTaxiId;
      if (taxiId == null) {
        final taxis = driver['taxis'];
        if (taxis is List && taxis.isNotEmpty) {
          final first = taxis.first;
          if (first is Map) {
            taxiId = (first['id'] as num?)?.toInt();
          }
        }
      }

      setState(() => _loading = false);

      // Dialog handles accept → execution screen; reject → pop(false).
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DriverRequestAcceptDialog(
          request: request,
          driverId: (driver['id'] ?? '').toString(),
          driverName:
              (driver['user']?['name'] ?? driver['name'] ?? 'Driver').toString(),
          driverPhone:
              (driver['user']?['phone'] ?? driver['phone'] ?? '').toString(),
          driverAvatar: (driver['user']?['profilepicture'] ??
                  driver['profilepicture'])
              ?.toString(),
          taxiId: taxiId,
        ),
      );

      if (!mounted) return;
      if (result == true) {
        // Accept already pushed execution above this gate — remove gate only.
        final route = ModalRoute.of(context);
        if (route != null) {
          Navigator.of(context).removeRoute(route);
        }
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = UserFacingError.from(e, fallback: 'Could not open ride offer');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.55),
      body: SafeArea(
        child: Center(
          child: _error != null
              ? Padding(
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
                      TextButton(
                        onPressed: () => unawaited(_loadAndShow()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _loading
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          'Loading ride offer…',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
