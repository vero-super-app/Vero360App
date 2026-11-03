import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_page.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';

const _access = CompanyAccess(<CompanyMembership>[
  CompanyMembership(
    operatorId: 'op-1',
    companyName: 'Ace Car Hire',
    companyStatus: 'ACTIVE',
    status: 'ACTIVE',
    role: 'OWNER',
  ),
]);

List<FleetUnit> _units() => <FleetUnit>[
      for (var i = 1; i <= 9; i++)
        FleetUnit(
          car: CarListing.fromJson(<String, dynamic>{
            'id': i,
            'make': 'Toyota',
            'model': 'Corolla Altis Long Name $i',
            'dailyRate': 85000,
            'seats': 5,
            'transmission': 'Automatic',
            'fuelType': 'Petrol',
            'isAvailable': i % 5 != 0,
            'imageUrl': '',
          }),
          licensePlate: 'MW 10$i',
        ),
    ];

List<CarHireBooking> _bookings() => <CarHireBooking>[
      CarHireBooking.fromJson(<String, dynamic>{
        'id': 1,
        'bookingStatus': 'ACTIVE',
        'assignedCarId': 1,
        'assignedUnit': <String, dynamic>{'carId': 1, 'licensePlate': 'MW 101'},
        'renterName': 'David Mwale',
        'startAt': '2026-10-18T09:00:00.000Z',
        'endAt': '2026-10-22T18:00:00.000Z',
        'total': 420000,
      }),
      CarHireBooking.fromJson(<String, dynamic>{
        'id': 2,
        'bookingStatus': 'ACTIVE',
        'assignedCarId': 2,
        'assignedUnit': <String, dynamic>{'carId': 2, 'licensePlate': 'MW 102'},
        'renterName': 'Emma Watson',
        'startAt': '2026-10-19T09:00:00.000Z',
        'endAt': '2026-10-24T18:00:00.000Z',
        'total': 420000,
      }),
    ];

final _board = DispatchBoard.fromJson(<String, dynamic>{
  'pickups': <dynamic>[
    <String, dynamic>{
      'id': 11,
      'bookingStatus': 'CONFIRMED',
      'startAt': '2026-10-20T12:45:00.000Z',
      'car': <String, dynamic>{'id': 3, 'make': 'Honda', 'model': 'Fit'},
      'renterName': 'Emma Watson',
    },
  ],
  'returns': <dynamic>[
    <String, dynamic>{
      'id': 12,
      'bookingStatus': 'ACTIVE',
      'endAt': '2026-10-20T16:00:00.000Z',
      'assignedPlate': 'MW 101',
      'renterName': 'David Mwale',
    },
  ],
  'awaitingResponse': <dynamic>[
    <String, dynamic>{
      'id': 13,
      'bookingStatus': 'PENDING',
      'holdExpiresAt': '2026-10-20T13:00:00.000Z',
      'car': <String, dynamic>{'id': 4, 'make': 'Mazda', 'model': 'CX-5'},
      'renterName': 'Grace Banda',
    },
  ],
});

final _analytics = CompanyAnalytics.fromJson(<String, dynamic>{
  'revenue': 1420000,
  'bookings': 18,
  'completed': 12,
  'utilizationRate': 82,
  'periodDays': 30,
  'totalCars': 9,
});

Widget _app() => ProviderScope(
      overrides: [
        companyAccessProvider.overrideWith((ref) async => _access),
        companyFleetProvider.overrideWith((ref) async => _units()),
        companyBookingsProvider.overrideWith((ref, arg) async => _bookings()),
        companyDispatchProvider.overrideWith((ref, arg) async => _board),
        companyAnalyticsProvider.overrideWith((ref) async => _analytics),
      ],
      child: const MaterialApp(home: CarHireCompanyPage(asHome: true)),
    );

void main() {
  for (final size in <Size>[
    const Size(320, 640),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets('dashboard lays out at ${size.width.toInt()}x '
        '${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('Fleet pulse'), findsOneWidget);
      expect(find.text('Ace Car Hire'), findsOneWidget);
      expect(find.text('Add car'), findsOneWidget);
      expect(find.text('Needs you today'), findsOneWidget);
      expect(find.textContaining('On road'), findsWidgets);

      await tester.tap(find.text('On road (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Open booking'), findsWidgets);

      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All (9)'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.textContaining('Block dates'), findsWidgets);
    });
  }
}
