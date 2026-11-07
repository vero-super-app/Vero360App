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

    test('parses fareBasis, cancellationFee, driverRating, and dispute fields',
        () {
      final ride = Ride.fromJson({
        'id': 99,
        'passengerId': 7,
        'pickupLatitude': -13.95,
        'pickupLongitude': 33.79,
        'dropoffLatitude': -13.98,
        'dropoffLongitude': 33.82,
        'estimatedDistance': 4.2,
        'estimatedFare': 3200,
        'actualFare': 4100,
        'fareBasis': 'actual',
        'cancellationFee': 1500,
        'driverRating': 4,
        'disputeReason': 'Wrong drop-off',
        'disputedAt': '2026-05-13T09:00:00.000Z',
        'status': 'COMPLETED',
        'createdAt': '2026-05-13T08:00:00.000Z',
        'updatedAt': '2026-05-13T09:00:00.000Z',
      });

      expect(ride.fareBasis, 'actual');
      expect(ride.fareBasisLabel, 'Metered');
      expect(ride.cancellationFee, 1500);
      expect(ride.hasCancellationFee, isTrue);
      expect(ride.driverRating, 4);
      expect(ride.disputeReason, 'Wrong drop-off');
      expect(ride.hasDispute, isTrue);
    });

    test('maps estimated fareBasis to Estimated label', () {
      final ride = Ride.fromJson({
        'id': 100,
        'passengerId': 7,
        'pickupLatitude': -13.95,
        'pickupLongitude': 33.79,
        'dropoffLatitude': -13.98,
        'dropoffLongitude': 33.82,
        'estimatedDistance': 2,
        'estimatedFare': 2000,
        'fareBasis': 'estimated',
        'status': 'COMPLETED',
        'createdAt': '2026-05-13T08:00:00.000Z',
        'updatedAt': '2026-05-13T08:30:00.000Z',
      });

      expect(ride.fareBasisLabel, 'Estimated');
      expect(ride.hasCancellationFee, isFalse);
    });
  });
}
