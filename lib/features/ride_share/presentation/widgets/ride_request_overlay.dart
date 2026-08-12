import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_ride_requests_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_notification_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_notification_popup.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/driver_request_accept_dialog.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/driver_ride_execution_screen.dart';
import 'package:vero360_app/GernalServices/driver_request_service.dart';
import 'package:vero360_app/GernalServices/driver_messaging_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/utils/app_logger.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

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
  final Set<String> _shownRequestIds = <String>{};
  /// Declined locally/server-side — suppress re-showing until request expires.
  final Set<String> _declinedRequestIds = <String>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        try {
          ref.read(driverRideRequestsInitProvider);
        } catch (e) {
          AppLogger.d('[RideRequestOverlay] Error initializing driver requests', e);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rideNotificationsEnabled = ref.watch(driverRideNotificationsEnabledProvider);
    if (rideNotificationsEnabled) {
      // Only initialize ride sockets for driver sessions.
      ref.watch(driverRideRequestsInitProvider);
    }

    ref.listen(
      driverRideRequestsStreamProvider,
      (prev, next) {
        if (!mounted) return;
        if (!rideNotificationsEnabled) return;
        try {
          next.whenData((request) {
            if (!mounted) return;
            final requestId = request.rideId.toString();
            if (_declinedRequestIds.contains(requestId)) return;
            if (!_shownRequestIds.contains(requestId)) {
              _shownRequestIds.add(requestId);
              unawaited(_handleNewWebSocketRequest(request));
            }
          });
        } catch (e) {
          AppLogger.d('[RideRequestOverlay] Error handling WebSocket request', e);
        }
      },
    );

    ref.listen(
      combinedDriverRideRequestsProvider,
      (prev, next) {
        if (!mounted) return;
        if (!rideNotificationsEnabled) return;
        try {
          next.whenData((combined) {
            if (!mounted) return;
            final activePendingIds = combined.rides
                .where((ride) {
                  final status = ride.status.toLowerCase();
                  return status == 'pending' || status == 'requested';
                })
                .map((ride) => ride.id)
                .toSet();
            _shownRequestIds.removeWhere(
              (id) =>
                  id != _activeRequest?.id &&
                  !_declinedRequestIds.contains(id) &&
                  !activePendingIds.contains(id),
            );
            _declinedRequestIds.removeWhere((id) => !activePendingIds.contains(id));
            for (final ride in combined.rides) {
              final status = ride.status.toLowerCase();
              if (status != 'pending' && status != 'requested') {
                _forgetShownRequest(ride.id);
                continue;
              }
              if (_declinedRequestIds.contains(ride.id)) continue;
              if (!_shownRequestIds.contains(ride.id)) {
                _shownRequestIds.add(ride.id);
                if (mounted) _showNotification(ride);
              }
            }
          });
        } catch (e) {
          AppLogger.d('[RideRequestOverlay] Error handling ride request', e);
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
                final request = _activeRequest;
                if (mounted) setState(() => _activeRequest = null);
                if (request != null) {
                  _declinedRequestIds.add(request.id);
                  _forgetShownRequest(request.id);
                  unawaited(_declineRequestQuietly(request.id));
                }
              },
              onAccept: () {
                final request = _activeRequest;
                if (mounted) setState(() => _activeRequest = null);
                if (request != null) {
                  unawaited(_acceptRequestDirectly(request));
                }
              },
            ),
        ],
      ),
    );
  }

  Future<void> _declineRequestQuietly(String rideId) async {
    try {
      await DriverRequestService.rejectRideRequest(rideId);
      ref.read(rideNotificationServiceProvider).removeNotification(rideId);
    } catch (e) {
      AppLogger.d('[RideRequestOverlay] Decline failed', e);
    }
  }

  Future<void> _acceptRequestDirectly(DriverRideRequest request) async {
    final navigatorContext = _findNavigatorContext();
    if (navigatorContext == null) {
      _openAcceptDialog(request);
      return;
    }

    try {
      final driver = await ref.read(myDriverProfileProvider.future);
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
        taxiId: taxiId,
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
      } catch (e) {
        AppLogger.d('[RideRequestOverlay] Messaging setup warning', e);
      }

      ref.read(rideNotificationServiceProvider).removeNotification(request.id);
      _forgetShownRequest(request.id);

      if (!navigatorContext.mounted) return;
      Navigator.of(navigatorContext).push(
        MaterialPageRoute(
          builder: (_) => DriverRideExecutionScreen(
            rideId: int.tryParse(request.id) ?? 0,
          ),
        ),
      );
      ScaffoldMessenger.of(navigatorContext).showSnackBar(
        SnackBar(
          content: const Text('Ride accepted! Navigate to pickup.'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      AppLogger.d('[RideRequestOverlay] Accept failed', e);
      _forgetShownRequest(request.id);
      if (navigatorContext.mounted) {
        ScaffoldMessenger.of(navigatorContext).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.from(e, fallback: 'Failed to accept ride')),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      // Fall back to confirm dialog so the driver can retry.
      _openAcceptDialog(request);
    }
  }

  Future<void> _handleNewWebSocketRequest(IncomingRideRequest request) async {
    try {
      final uid = await AuthStorage.userIdFromToken();
      if (request.passengerId != null &&
          uid != null &&
          request.passengerId == uid) {
        return;
      }

      int? candidateTaxiId;
      try {
        final driverProfile = await ref.read(myDriverProfileProvider.future);
        final driverId = (driverProfile['id'] as num?)?.toInt();
        candidateTaxiId = request.recommendedTaxiIdForDriver(driverId);
      } catch (_) {}

      final driverRequest = DriverRideRequest(
        id: request.rideId.toString(),
        passengerId: request.passengerId?.toString() ?? '',
        passengerName: request.passengerName,
        pickupLat: request.pickupLatitude,
        pickupLng: request.pickupLongitude,
        dropoffLat: request.dropoffLatitude,
        dropoffLng: request.dropoffLongitude,
        pickupAddress: request.pickupAddress ?? 'Pickup Location',
        dropoffAddress: request.dropoffAddress ?? '',
        status: 'pending',
        createdAt: request.timestamp,
        estimatedTime: 0,
        estimatedDistance: request.estimatedDistance,
        estimatedFare: request.estimatedFare,
        passengerPhone: request.passengerPhone,
        candidateTaxiId: candidateTaxiId,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNotification(driverRequest);
      });
    } catch (e) {
      AppLogger.d('[RideRequestOverlay] Error processing WebSocket request', e);
    }
  }

  void _showNotification(DriverRideRequest request) {
    if (!mounted) return;
    try {
      if (!ref.read(driverRideNotificationsEnabledProvider)) return;

      ref.read(rideNotificationServiceProvider).addNotification(request);
      setState(() => _activeRequest = request);
    } catch (e) {
      AppLogger.d('[RideRequestOverlay] Error showing notification', e);
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

        // One vehicle per driver — use the registered vehicle.
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

        try {
          showDialog(
            context: navigatorContext,
            builder: (_) => DriverRequestAcceptDialog(
              request: request,
              driverId: (driver['id'] ?? '').toString(),
              driverName: driver['user']?['name'] ?? driver['name'] ?? 'Driver',
              driverPhone: driver['user']?['phone'] ?? driver['phone'] ?? '',
              driverAvatar:
                  driver['user']?['profilepicture'] ?? driver['profilepicture'],
              taxiId: taxiId,
              onAccepted: () {
                ref
                    .read(rideNotificationServiceProvider)
                    .removeNotification(request.id);
                _forgetShownRequest(request.id);
                if (navigatorContext.mounted) {
                  Navigator.pop(navigatorContext);
                }
              },
              onRejected: () {
                _declinedRequestIds.add(request.id);
                _forgetShownRequest(request.id);
              },
            ),
          );
        } catch (e) {
          AppLogger.d('[RideRequestOverlay] Error showing accept dialog', e);
        }
      });
    });
  }

  void _forgetShownRequest(String requestId) {
    _shownRequestIds.remove(requestId);
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
