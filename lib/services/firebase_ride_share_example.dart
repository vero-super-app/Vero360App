import 'package:vero360_app/services/firebase_ride_share_service.dart';
import 'package:flutter/material.dart';

/// EXAMPLE USAGE: Firebase Ride Share Service
/// 
/// This file demonstrates how to use the FirebaseRideShareService
/// for passenger and driver flows.

class RideShareExample {
  // ============== PASSENGER FLOW ==============
  
  /// 1. Passenger initiates a ride request
  static Future<void> passengerRequestRide() async {
    final rideId = await FirebaseRideShareService.createRideRequest(
      passengerId: 'passenger123',
      pickupLat: 6.9271,
      pickupLng: 3.3955, // Lagos, Nigeria
      dropoffLat: 6.5244,
      dropoffLng: 3.3792,
      pickupAddress: 'Victoria Island, Lagos',
      dropoffAddress: 'Ikoyi, Lagos',
      estimatedTime: 25, // minutes
      estimatedDistance: 12.5, // km
      estimatedFare: 5000.0, // NGN
    );
    
    print('Ride request created: $rideId');
  }

  /// 2. Passenger listens to ride status updates
  static Stream<RideRequest?> watchRideStatus(String rideId) {
    return FirebaseRideShareService.getRideRequestStream(rideId);
  }

  /// 3. Passenger sees all their past and current rides
  static Stream<List<RideRequest>> watchMyRides(String passengerId) {
    return FirebaseRideShareService.getPassengerRideRequestsStream(passengerId);
  }

  /// 4. Passenger completes ride and rates driver
  static Future<void> completeRideWithRating({
    required String rideId,
    required double actualFare,
    required int rating, // 1-5 stars
    required String feedback,
  }) async {
    await FirebaseRideShareService.completeRideWithRating(
      rideId: rideId,
      actualFare: actualFare,
      rating: rating,
      feedback: feedback,
    );
    
    // Update passenger rating
    final ride = await FirebaseRideShareService.getRideRequest(rideId);
    if (ride != null) {
      await FirebaseRideShareService.updateUserRating(
        ride.passengerId,
        rating.toDouble(),
      );
    }
  }

  /// 5. Passenger cancels a ride request
  static Future<void> cancelRide(String rideId) async {
    await FirebaseRideShareService.cancelRideRequest(rideId);
  }

  // ============== DRIVER FLOW ==============

  /// 1. Driver comes online and starts monitoring available rides
  static Stream<List<RideRequest>> watchAvailableRides() {
    return FirebaseRideShareService.getPendingRideRequestsStream();
  }

  /// 2. Driver streams their location to Firebase (every 5 seconds)
  static Future<void> updateMyLocation({
    required String driverId,
    required double latitude,
    required double longitude,
  }) async {
    await FirebaseRideShareService.updateDriverLocation(
      driverId: driverId,
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// 3. Driver gets nearby available rides (within 5km)
  static Stream<List<RideRequest>> watchNearbyRides({
    required double currentLat,
    required double currentLng,
  }) {
    // First get pending rides
    return FirebaseRideShareService.getPendingRideRequestsStream();
    
    // Filter client-side by distance (Firebase RTDB has geo-query limitations)
    // TODO: Implement distance filtering on client
  }

  /// 4. Driver accepts a ride request
  static Future<void> acceptRide({
    required String rideId,
    required String driverId,
  }) async {
    await FirebaseRideShareService.acceptRideRequest(
      rideId: rideId,
      driverId: driverId,
    );
    
    // Driver status becomes 'on_ride'
    print('Ride accepted. Status updated to on_ride');
  }

  /// 5. Driver streams their active rides
  static Stream<List<RideRequest>> watchMyActiveRides(String driverId) {
    return FirebaseRideShareService.getDriverRideRequestsStream(driverId);
  }

  /// 6. Driver completes a ride
  static Future<void> completeRide({
    required String rideId,
    required String driverId,
    required double actualFare,
  }) async {
    await FirebaseRideShareService.updateRideRequestStatus(
      rideId,
      'completed',
    );
    
    // Update to reflect actual fare and mark driver as online again
    await FirebaseRideShareService.updateDriverStatus(driverId, 'online');
  }

  /// 7. Driver goes offline
  static Future<void> goOffline(String driverId) async {
    await FirebaseRideShareService.updateDriverStatus(driverId, 'offline');
  }

  /// 8. Driver updates their profile
  static Future<void> updateMyProfile({
    required String driverId,
    required String name,
    required String avatar,
    required String vehicleType, // 'car', 'bike', etc
    required String vehiclePlate,
  }) async {
    await FirebaseRideShareService.updateDriverProfile(
      driverId: driverId,
      name: name,
      avatar: avatar,
      vehicleType: vehicleType,
      vehiclePlate: vehiclePlate,
    );
  }

  /// 9. Driver watches their profile (rating, completed rides)
  static Stream<Driver?> watchMyProfile(String driverId) {
    return FirebaseRideShareService.getDriverProfileStream(driverId);
  }

  // ============== SHARED FLOWS ==============

  /// Get all online drivers
  static Stream<List<Driver>> watchOnlineDrivers() {
    return FirebaseRideShareService.getActiveDriversStream();
  }

  /// Get count of online drivers (useful for demand estimation)
  static Future<int> getOnlineDriverCount() async {
    return await FirebaseRideShareService.getOnlineDriversCount();
  }

  /// User profile management
  static Future<void> createUserProfile({
    required String userId,
    required String name,
    required String email,
    required String phone,
    String userType = 'passenger', // 'passenger', 'driver', 'both'
  }) async {
    await FirebaseRideShareService.createOrUpdateUser(
      userId: userId,
      name: name,
      email: email,
      phone: phone,
      userType: userType,
    );
  }
}

// ============== FLUTTER WIDGET EXAMPLES ==============

/// Example: Passenger UI showing available driver
class AvailableDriverWidget extends StatefulWidget {
  final String passengerId;
  final String rideId;

  const AvailableDriverWidget({
    required this.passengerId,
    required this.rideId,
  });

  @override
  State<AvailableDriverWidget> createState() => _AvailableDriverWidgetState();
}

class _AvailableDriverWidgetState extends State<AvailableDriverWidget> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RideRequest?>(
      stream: FirebaseRideShareService.getRideRequestStream(widget.rideId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final ride = snapshot.data!;

        if (ride.driverId == null) {
          return const Center(child: Text('Finding driver...'));
        }

        return StreamBuilder<Driver?>(
          stream: FirebaseRideShareService.getDriverProfileStream(ride.driverId!),
          builder: (context, driverSnapshot) {
            if (!driverSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final driver = driverSnapshot.data!;

            return Column(
              children: [
                CircleAvatar(
                  backgroundImage: NetworkImage(driver.avatar),
                  radius: 40,
                ),
                const SizedBox(height: 16),
                Text(driver.name, style: const TextStyle(fontSize: 18)),
                Text('${driver.rating} ⭐'),
                Text('${driver.vehicleType} - ${driver.vehiclePlate}'),
                const SizedBox(height: 16),
                if (ride.status == 'completed')
                  ElevatedButton(
                    onPressed: () => RideShareExample.completeRideWithRating(
                      rideId: widget.rideId,
                      actualFare: ride.estimatedFare,
                      rating: 5,
                      feedback: 'Great ride!',
                    ),
                    child: const Text('Rate Driver'),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Example: Driver UI showing available rides
class AvailableRidesWidget extends StatefulWidget {
  @override
  State<AvailableRidesWidget> createState() => _AvailableRidesWidgetState();
}

class _AvailableRidesWidgetState extends State<AvailableRidesWidget> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RideRequest>>(
      stream: FirebaseRideShareService.getPendingRideRequestsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rides = snapshot.data!;

        if (rides.isEmpty) {
          return const Center(child: Text('No rides available'));
        }

        return ListView.builder(
          itemCount: rides.length,
          itemBuilder: (context, index) {
            final ride = rides[index];
            return Card(
              child: ListTile(
                title: Text(ride.pickupAddress),
                subtitle: Text(ride.dropoffAddress),
                trailing: ElevatedButton(
                  onPressed: () => RideShareExample.acceptRide(
                    rideId: ride.id,
                    driverId: 'driver123', // Get from auth
                  ),
                  child: const Text('Accept'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
