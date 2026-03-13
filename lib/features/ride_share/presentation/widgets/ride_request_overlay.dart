import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_ride_requests_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_notification_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_notification_popup.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/driver_request_accept_dialog.dart';
import 'package:vero360_app/GernalServices/driver_request_service.dart';

final _shownRequestIds = <String>{};

class RideRequestOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const RideRequestOverlay({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<RideRequestOverlay> createState() => _RideRequestOverlayState();
}

class _RideRequestOverlayState extends ConsumerState<RideRequestOverlay> {
  DriverRideRequest? _activeRequest;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        try {
          ref.read(driverRideRequestsInitProvider);
        } catch (e) {
          debugPrint('[RideRequestOverlay] Error initializing driver requests: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      driverRideRequestsStreamProvider,
      (prev, next) {
        if (!mounted) return;
        try {
          next.whenData((request) {
            if (!mounted) return;
            final requestId = request.rideId.toString();
            if (!_shownRequestIds.contains(requestId)) {
              _shownRequestIds.add(requestId);
              _handleNewWebSocketRequest(request);
            }
          });
        } catch (e) {
          debugPrint('[RideRequestOverlay] Error handling WebSocket request: $e');
        }
      },
    );

    ref.listen(
      combinedDriverRideRequestsProvider,
      (prev, next) {
        if (!mounted) return;
        try {
          next.whenData((rideList) {
            if (!mounted) return;
            for (final ride in rideList) {
              final status = ride.status.toLowerCase();
              if ((status == 'pending' || status == 'requested') &&
                  !_shownRequestIds.contains(ride.id)) {
                _shownRequestIds.add(ride.id);
                if (mounted) _showNotification(ride);
              }
            }
          });
        } catch (e) {
          debugPrint('[RideRequestOverlay] Error handling ride request: $e');
        }
      },
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (_activeRequest != null)
            RideNotificationPopup(
              key: ValueKey(_activeRequest!.id),
              rideRequest: _activeRequest!,
              ref: ref,
              onDismiss: () {
                if (mounted) setState(() => _activeRequest = null);
              },
              onAccept: () {
                final request = _activeRequest;
                if (mounted) setState(() => _activeRequest = null);
                if (request != null) _openAcceptDialog(request);
              },
            ),
        ],
      ),
    );
  }

  void _handleNewWebSocketRequest(dynamic request) {
    try {
      final driverRequest = DriverRideRequest(
        id: request.rideId?.toString() ?? DateTime.now().toString(),
        passengerId: '',
        passengerName: 'Passenger',
        pickupLat: (request.pickupLatitude as num?)?.toDouble() ?? 0.0,
        pickupLng: (request.pickupLongitude as num?)?.toDouble() ?? 0.0,
        dropoffLat: 0.0,
        dropoffLng: 0.0,
        pickupAddress: request.pickupAddress ?? 'Pickup Location',
        dropoffAddress: 'Destination',
        status: 'pending',
        createdAt: request.timestamp ?? DateTime.now(),
        estimatedTime: 0,
        estimatedDistance: (request.estimatedDistance as num?)?.toDouble() ?? 0.0,
        estimatedFare: (request.estimatedFare as num?)?.toDouble() ?? 0.0,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNotification(driverRequest);
      });
    } catch (e) {
      debugPrint('[RideRequestOverlay] Error processing WebSocket request: $e');
    }
  }

  void _showNotification(DriverRideRequest request) {
    if (!mounted) return;
    try {
      ref.read(rideNotificationServiceProvider).addNotification(request);
      setState(() => _activeRequest = request);
    } catch (e) {
      debugPrint('[RideRequestOverlay] Error showing notification: $e');
    }
  }

  void _openAcceptDialog(DriverRideRequest request) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final navigatorContext = _findNavigatorContext();
      if (navigatorContext == null) return;

      final driverProfile = ref.read(myDriverProfileProvider);
      driverProfile.whenData((driver) {
        if (!mounted) return;

        // Resolve taxiId from the driver's taxis array
        int? taxiId;
        final taxis = driver['taxis'];
        if (taxis is List && taxis.isNotEmpty) {
          taxiId = (taxis[0]['id'] as num?)?.toInt();
        }

        try {
          showDialog(
            context: navigatorContext,
            builder: (_) => DriverRequestAcceptDialog(
              request: request,
              driverId: (driver['id'] ?? '').toString(),
              driverName: driver['user']?['name'] ?? driver['name'] ?? 'Driver',
              driverPhone: driver['user']?['phone'] ?? driver['phone'] ?? '',
              driverAvatar: driver['user']?['profilepicture'] ?? driver['profilepicture'],
              taxiId: taxiId,
              onAccepted: () {
                ref.read(rideNotificationServiceProvider).removeNotification(request.id);
                if (navigatorContext.mounted) {
                  Navigator.pop(navigatorContext);
                }
              },
            ),
          );
        } catch (e) {
          debugPrint('[RideRequestOverlay] Error showing accept dialog: $e');
        }
      });
    });
  }

  BuildContext? _findNavigatorContext() {
    BuildContext? navContext;
    try {
      void visitor(Element element) {
        if (navContext != null) return;
        if (element.widget is Navigator) {
          navContext = element;
          return;
        }
        element.visitChildren(visitor);
      }
      (context as Element).visitChildren(visitor);
    } catch (_) {}
    return navContext;
  }
}
