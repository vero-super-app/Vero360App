import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_add_vehicle_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_unit_page.dart';
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

FleetUnit _unit() => FleetUnit(
      car: CarListing.fromJson(<String, dynamic>{
        'id': 7,
        'make': 'Toyota',
        'model': 'Corolla Altis',
        'year': 2023,
        'dailyRate': 85000,
        'seats': 5,
        'transmission': 'Automatic',
        'fuelType': 'Petrol',
        'bodyType': 'Sedan',
        'isAvailable': true,
        'currency': 'MWK',
        'listingStatus': 'PUBLISHED',
        'images': const <String>[],
        'latitude': -13.9626,
        'longitude': 33.7741,
      }),
      licensePlate: 'MW 107',
      operatorId: 'op-1',
      tracker: const FleetTracker(
        deviceId: 'OBD-8820',
        latitude: -13.9626,
        longitude: 33.7741,
        speed: 34,
      ),
    );

final _booking = CarHireBooking.fromJson(<String, dynamic>{
  'id': 42,
  'bookingStatus': 'ACTIVE',
  'assignedCarId': 7,
  'renterName': 'David Mwale',
  'startAt': '2026-10-18T09:00:00.000Z',
  'endAt': '2026-10-24T18:00:00.000Z',
  'total': 204000,
  'currency': 'MWK',
});

Widget _unitApp() => ProviderScope(
      overrides: [
        companyFleetProvider.overrideWith((ref) async => <FleetUnit>[_unit()]),
        unitActiveBookingProvider.overrideWith((ref, id) async => _booking),
        companyComplianceProvider.overrideWith(
          (ref, id) async => const CarCompliance(
            missing: <String>['INSURANCE'],
            expired: <String>[],
          ),
        ),
        companyMaintenanceBlocksProvider
            .overrideWith((ref, id) async => const <MaintenanceBlock>[]),
        companyBranchesProvider
            .overrideWith((ref, id) async => const <CompanyBranch>[]),
        companyAnalyticsProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        home: CarHireCompanyUnitPage(unit: _unit(), access: _access),
      ),
    );

Widget _addApp() => ProviderScope(
      overrides: [
        companyBranchesProvider
            .overrideWith((ref, id) async => const <CompanyBranch>[]),
      ],
      child: const MaterialApp(
        home: CarHireCompanyAddVehiclePage(access: _access),
      ),
    );

void main() {
  testWidgets('unit workspace shows the live rental and actions at 320px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_unitApp());
    await tester.pumpAndSettle();

    expect(find.text('Toyota Corolla Altis'), findsOneWidget);
    expect(find.text('MW 107'), findsOneWidget);
    expect(find.text('On rent'), findsOneWidget);
    expect(find.textContaining('MWK 85,000'), findsWidgets);
    expect(find.text('Active rental'), findsOneWidget);
    expect(find.text('Open booking'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Pricing & rates'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Service & blocks'), findsOneWidget);
    expect(find.text('Remove vehicle from fleet'), findsOneWidget);
  });

  testWidgets('add vehicle wizard validates before advancing',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_addApp());
    await tester.pumpAndSettle();

    expect(find.text('Add vehicle to fleet'), findsOneWidget);
    expect(find.text('Registration plate'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('Enter the registration plate'),
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
    expect(find.textContaining('Enter the registration plate'),
        findsOneWidget);
  });
}
