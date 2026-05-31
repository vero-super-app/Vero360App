import 'package:flutter_test/flutter_test.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';

void main() {
  group('Ride.fromJson', () {
    test('parses driver data from the top-level driver payload', () {
      final ride = Ride.fromJson({
        'id': 12,
        'passengerId': 7,
        'pickupLatitude': -13.95,
        'pickupLongitude': 33.79,
        'dropoffLatitude': -13.98,
        'dropoffLongitude': 33.82,
        'estimatedDistance': 4.2,
        'estimatedFare': 3200,
        'status': 'ACCEPTED',
        'createdAt': '2026-05-13T08:00:00.000Z',
        'updatedAt': '2026-05-13T08:05:00.000Z',
        'driver': {
          'id': 5,
          'firstName': 'Maya',
          'lastName': 'Tembo',
          'phone': '+265999000111',
        },
      });

      expect(ride.driver, isNotNull);
      expect(ride.driver!.firstName, 'Maya');
      expect(ride.driver!.lastName, 'Tembo');
      expect(ride.driver!.phone, '+265999000111');
    });

    test(
        'falls back to nested taxi.driver payload when top-level driver is absent',
        () {
      final ride = Ride.fromJson({
        'id': 12,
        'passengerId': 7,
        'pickupLatitude': -13.95,
        'pickupLongitude': 33.79,
        'dropoffLatitude': -13.98,
        'dropoffLongitude': 33.82,
        'estimatedDistance': 4.2,
        'estimatedFare': 3200,
        'status': 'ACCEPTED',
        'createdAt': '2026-05-13T08:00:00.000Z',
        'updatedAt': '2026-05-13T08:05:00.000Z',
        'taxi': {
          'id': 17,
          'driverId': 5,
          'vehicleClass': 'STANDARD',
          'make': 'Toyota',
          'model': 'Vitz',
          'year': 2020,
          'licensePlate': 'NN 1234',
          'seats': 4,
          'isAvailable': true,
          'rating': 4.9,
          'totalRides': 18,
          'driver': {
            'id': 5,
            'latitude': -13.95,
            'longitude': 33.79,
            'user': {
              'name': 'John Phiri',
              'phone': '+265888000111',
              'profilepicture': 'https://example.com/avatar.png',
            },
          },
        },
      });

      expect(ride.driver, isNotNull);
      expect(ride.driver!.firstName, 'John');
      expect(ride.driver!.lastName, 'Phiri');
      expect(ride.driver!.phone, '+265888000111');
      expect(ride.driver!.avatar, 'https://example.com/avatar.png');
    });
  });
}
