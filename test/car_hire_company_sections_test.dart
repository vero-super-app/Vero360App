import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_booking_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_bookings_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_fleet_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_unit_page.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_skeletons.dart';

const _access = CompanyAccess(<CompanyMembership>[
  CompanyMembership(
    operatorId: 'op-1',
    companyName: 'Ace Car Hire',
    companyStatus: 'ACTIVE',
    status: 'ACTIVE',
    role: 'OWNER',
  ),
]);

const _failure = CarHireApiException(
  message: 'The network is offline.',
  statusCode: 503,
);

FleetUnit _unit() => FleetUnit(
  car: CarListing.fromJson(<String, dynamic>{
    'id': 7,
    'make': 'Toyota',
    'model': 'Corolla',
    'dailyRate': 85000,
    'seats': 5,
    'transmission': 'Automatic',
    'fuelType': 'Petrol',
    'isAvailable': true,
    'imageUrl': '',
  }),
  licensePlate: 'MW 107',
);

CarHireBooking _booking() => CarHireBooking.fromJson(<String, dynamic>{
  'id': 42,
  'bookingStatus': 'CONFIRMED',
  'carId': 7,
  'assignedCarId': 7,
  'assignedUnit': <String, dynamic>{'carId': 7, 'licensePlate': 'MW 107'},
  'renterName': 'David Mwale',
  'startAt': '2026-10-21T09:00:00.000Z',
  'endAt': '2026-10-24T18:00:00.000Z',
  'total': 420000,
  'paymentStatus': 'PAID',
});

DispatchBoard _emptyBoard() => DispatchBoard.fromJson(<String, dynamic>{});

Widget _app(Widget home, List<dynamic> overrides) {
  final all = <dynamic>[
    companyAccessProvider.overrideWith((ref) async => _access),
    companyAnalyticsProvider.overrideWith((ref) async => null),
    ...overrides,
  ];
  return ProviderScope(
    overrides: all.cast(),
    child: MaterialApp(home: home),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('dashboard keeps today’s work when the fleet section fails', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        const CarHireCompanyPage(asHome: true),
        [
          companyFleetProvider.overrideWith((ref) async => throw _failure),
          companyBookingsProvider.overrideWith(
            (ref, arg) async => <CarHireBooking>[],
          ),
          companyDispatchProvider.overrideWith(
            (ref, arg) async => _emptyBoard(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ace Car Hire'), findsOneWidget);
    expect(find.text('Fleet numbers unavailable'), findsOneWidget);
    expect(find.text('Fleet unavailable'), findsOneWidget);
    expect(find.text('Needs you today'), findsOneWidget);
    expect(find.text('All clear · nothing due today.'), findsOneWidget);
    expect(find.text('Retry'), findsWidgets);
  });

  testWidgets('dashboard paints section skeletons while the fleet loads', (
    tester,
  ) async {
    _phone(tester);
    final pending = Completer<List<FleetUnit>>();
    addTearDown(() => pending.complete(<FleetUnit>[]));

    await tester.pumpWidget(
      _app(
        const CarHireCompanyPage(asHome: true),
        [
          companyFleetProvider.overrideWith((ref) => pending.future),
          companyBookingsProvider.overrideWith(
            (ref, arg) async => <CarHireBooking>[],
          ),
          companyDispatchProvider.overrideWith(
            (ref, arg) async => _emptyBoard(),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CarHireCompanyPulseSkeleton), findsOneWidget);
    expect(find.byType(CarHireCompanyCarCardSkeleton), findsWidgets);
    expect(find.text('Needs you today'), findsOneWidget);
  });

  testWidgets('fleet page keeps its header and offers a retry', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        const CarHireCompanyFleetPage(),
        [
          companyFleetProvider.overrideWith((ref) async => throw _failure),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fleet'), findsOneWidget);
    expect(find.text('Fleet unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('bookings page keeps filters usable when the queue fails', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        const CarHireCompanyBookingsPage(),
        [
          companyBookingsProvider.overrideWith(
            (ref, arg) async => throw _failure,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Needs action'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Bookings unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('unit page retries the live rental without hiding the car', (
    tester,
  ) async {
    _phone(tester);
    final unit = _unit();
    await tester.pumpWidget(
      _app(
        CarHireCompanyUnitPage(unit: unit, access: _access),
        [
          companyFleetProvider.overrideWith(
            (ref) async => <FleetUnit>[unit],
          ),
          unitActiveBookingProvider.overrideWith(
            (ref, carId) async => throw _failure,
          ),
          companyComplianceProvider.overrideWith(
            (ref, carId) async => const CarCompliance(compliant: true),
          ),
          companyMaintenanceBlocksProvider.overrideWith(
            (ref, carId) async => <MaintenanceBlock>[],
          ),
          companyBranchesProvider.overrideWith(
            (ref, operatorId) async => <CompanyBranch>[],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Toyota Corolla'), findsOneWidget);
    expect(find.text('Live rental not checked'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('company booking keeps the summary when extensions fail', (
    tester,
  ) async {
    _phone(tester);
    final booking = _booking();
    await tester.pumpWidget(
      _app(
        const CarHireCompanyBookingPage(bookingId: 42),
        [
          carHireBookingDetailProvider.overrideWith(
            (ref, id) async => booking,
          ),
          bookingExtensionsProvider.overrideWith(
            (ref, id) async => throw _failure,
          ),
          bookingIncidentsProvider.overrideWith(
            (ref, id) async => <IncidentReport>[],
          ),
          bookingUnitOptionsProvider.overrideWith(
            (ref, id) async => <BookingUnitOption>[],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('David Mwale'), findsOneWidget);
    expect(find.text('Extension requests'), findsOneWidget);
    expect(find.text('Extension requests could not load.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
