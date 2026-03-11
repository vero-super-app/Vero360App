import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_ride_requests_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_notification_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_notification_popup.dart';
import 'package:vero360_app/GernalServices/driver_request_service.dart';

/// Global key for tracking which requests have been shown
final _shownRequestIds = <String>{};

/// Overlay widget that listens to ride requests and shows notifications
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
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    // Initialize WebSocket on first build
    Future.microtask(() {
      if (mounted) {
        ref.read(driverRideRequestsInitProvider);
      }
    });

    // Listen to WebSocket ride requests
    ref.listen(
      driverRideRequestsStreamProvider,
      (_, AsyncValue rideRequest) {
        rideRequest.whenData((request) {
          if (request != null) {
            final requestId = request.rideId.toString();
            if (!_shownRequestIds.contains(requestId)) {
              _shownRequestIds.add(requestId);
              _handleNewWebSocketRequest(request);
            }
          }
        });
      },
    );

    // Listen to HTTP polling ride requests as fallback
    ref.listen(
      combinedDriverRideRequestsProvider,
      (_, AsyncValue<List<DriverRideRequest>> rides) {
        rides.whenData((rideList) {
          for (final ride in rideList) {
            if (ride.status == 'pending' && !_shownRequestIds.contains(ride.id)) {
              _shownRequestIds.add(ride.id);
              _handleNewRideRequest(ride);
            }
          }
        });
      },
    );

    return widget.child;
  }

  void _handleNewWebSocketRequest(dynamic request) {
    try {
      // Create a DriverRideRequest from WebSocket IncomingRideRequest
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
        estimatedDistance: (request.searchRadiusKm as num?)?.toDouble() ?? 0.0,
        estimatedFare: 0.0,
      );

      // Use post-frame callback to ensure context is available
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showNotification(driverRequest);
        }
      });
    } catch (e) {
      debugPrint('[RideRequestOverlay] Error processing WebSocket request: $e');
    }
  }

  void _handleNewRideRequest(DriverRideRequest request) {
    _showNotification(request);
  }

  void _showNotification(DriverRideRequest request) {
    if (!mounted) return;
    
    // Add to notification service
    ref.read(rideNotificationServiceProvider).addNotification(request);
    
    // Show popup
    showRideRequestNotification(context, request, ref);
  }
}
