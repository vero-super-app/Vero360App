import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_account_pages.dart';
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

const _activeAccount = CarHireAccount(
  state: CarHireAccountState.active,
  companyId: 'op-1',
  companyName: 'Ace Car Hire',
  companyType: 'BUSINESS',
);

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

dynamic get _accessGranted =>
    companyAccessProvider.overrideWith((ref) async => _access);

Widget _app(Widget home, List<dynamic> overrides) {
  return ProviderScope(
    // A failing provider should surface its error, not retry silently.
    retry: (_, _) => null,
    overrides: <dynamic>[
      companyAnalyticsProvider.overrideWith((ref) async => null),
      ...overrides,
    ].cast(),
    child: MaterialApp(home: home),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('opening car hire paints one skeleton, then the company home', (
    tester,
  ) async {
    _phone(tester);
    final account = Completer<CarHireAccount>();
    final access = Completer<CompanyAccess>();
    final fleet = Completer<List<FleetUnit>>();
    addTearDown(() {
      if (!account.isCompleted) account.complete(CarHireAccount.none);
      if (!access.isCompleted) access.complete(_access);
      if (!fleet.isCompleted) fleet.complete(<FleetUnit>[]);
    });

    await tester.pumpWidget(
      _app(const CarHireHomePage(), <dynamic>[
        carHireAccountProvider.overrideWith((ref) => account.future),
        companyAccessProvider.overrideWith((ref) => access.future),
        companyFleetProvider.overrideWith((ref) => fleet.future),
        companyBookingsProvider.overrideWith(
          (ref, arg) async => <CarHireBooking>[],
        ),
        companyDispatchProvider.overrideWith((ref, arg) async => _emptyBoard()),
      ]),
    );
    await tester.pump();

    // First paint is a skeleton shell, never a bare spinner.
    expect(find.byType(CarHireEntrySkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Opening car hire…'), findsNothing);

    account.complete(_activeAccount);
    await tester.pump();
    await tester.pump();

    // The account is known, so the wait switches to the dashboard skeleton
    // that matches the page it is about to hand over to.
    expect(find.byType(CarHireEntrySkeleton), findsNothing);
    expect(find.byType(CarHireCompanyDashboardSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    access.complete(_access);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Memberships were warmed by the entry, so the company home goes straight
    // to its own sections without a second loading screen.
    expect(find.byType(CarHireCompanyDashboardSkeleton), findsNothing);
    expect(find.byType(CarHireCompanyPulseSkeleton), findsOneWidget);
    expect(find.byType(CarHireCompanyCarCardSkeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    fleet.complete(<FleetUnit>[]);
    await tester.pumpAndSettle();
    expect(find.text('Fleet pulse'), findsOneWidget);
    expect(find.byType(CarHireCompanyPulseSkeleton), findsNothing);
  });

  testWidgets('entry skeleton lays out on a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CarHireEntrySkeleton())),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.takeException(), isNull);
    expect(find.byType(CarHireEntrySkeleton), findsOneWidget);
  });

  test(
    'entry resolves the marketplace for accounts that are not live',
    () async {
      final container = ProviderContainer.test(
        retry: (_, _) => null,
        overrides: <dynamic>[
          carHireAccountProvider.overrideWith(
            (ref) async => CarHireAccount.none,
          ),
        ].cast(),
      );
      expect(
        await container.read(carHireEntryProvider.future),
        CarHireEntryDestination.marketplace,
      );
    },
  );

  test('entry resolves company and warms the memberships', () async {
    var accessCalls = 0;
    final container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: <dynamic>[
        carHireAccountProvider.overrideWith((ref) async => _activeAccount),
        companyAccessProvider.overrideWith((ref) async {
          accessCalls += 1;
          return _access;
        }),
      ].cast(),
    );
    expect(
      await container.read(carHireEntryProvider.future),
      CarHireEntryDestination.company,
    );
    // The company home reads the same cached membership, so it never shows a
    // second loading state.
    expect(accessCalls, 1);
    expect(
      await container.read(companyAccessProvider.future),
      isA<CompanyAccess>(),
    );
    expect(accessCalls, 1);
  });

  test(
    'entry stays on the marketplace when the account lookup fails',
    () async {
      final container = ProviderContainer.test(
        retry: (_, _) => null,
        overrides: <dynamic>[
          carHireAccountProvider.overrideWith((ref) async => throw _failure),
        ].cast(),
      );
      expect(
        await container.read(carHireEntryProvider.future),
        CarHireEntryDestination.marketplace,
      );
    },
  );

  testWidgets('company page paints its own skeleton instead of a spinner', (
    tester,
  ) async {
    _phone(tester);
    final access = Completer<CompanyAccess>();
    addTearDown(() {
      if (!access.isCompleted) access.complete(_access);
    });

    await tester.pumpWidget(
      _app(const CarHireCompanyPage(asHome: true), <dynamic>[
        companyAccessProvider.overrideWith((ref) => access.future),
        companyFleetProvider.overrideWith((ref) async => <FleetUnit>[]),
        companyBookingsProvider.overrideWith(
          (ref, arg) async => <CarHireBooking>[],
        ),
        companyDispatchProvider.overrideWith((ref, arg) async => _emptyBoard()),
      ]),
    );
    await tester.pump();

    expect(find.byType(CarHireCompanyDashboardSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    access.complete(_access);
    await tester.pumpAndSettle();
    expect(find.text('Fleet pulse'), findsOneWidget);
    expect(find.byType(CarHireCompanyDashboardSkeleton), findsNothing);
  });

  testWidgets('dashboard keeps today’s work when the fleet section fails', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(const CarHireCompanyPage(asHome: true), <dynamic>[
        _accessGranted,
        companyFleetProvider.overrideWith((ref) async => throw _failure),
        companyBookingsProvider.overrideWith(
          (ref, arg) async => <CarHireBooking>[],
        ),
        companyDispatchProvider.overrideWith((ref, arg) async => _emptyBoard()),
      ]),
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
      _app(const CarHireCompanyPage(asHome: true), <dynamic>[
        _accessGranted,
        companyFleetProvider.overrideWith((ref) => pending.future),
        companyBookingsProvider.overrideWith(
          (ref, arg) async => <CarHireBooking>[],
        ),
        companyDispatchProvider.overrideWith((ref, arg) async => _emptyBoard()),
      ]),
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
      _app(const CarHireCompanyFleetPage(), <dynamic>[
        _accessGranted,
        companyFleetProvider.overrideWith((ref) async => throw _failure),
      ]),
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
      _app(const CarHireCompanyBookingsPage(), <dynamic>[
        _accessGranted,
        companyBookingsProvider.overrideWith(
          (ref, arg) async => throw _failure,
        ),
      ]),
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
      _app(CarHireCompanyUnitPage(unit: unit, access: _access), <dynamic>[
        _accessGranted,
        companyFleetProvider.overrideWith((ref) async => <FleetUnit>[unit]),
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
      ]),
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
      _app(const CarHireCompanyBookingPage(bookingId: 42), <dynamic>[
        _accessGranted,
        carHireBookingDetailProvider.overrideWith((ref, id) async => booking),
        bookingExtensionsProvider.overrideWith(
          (ref, id) async => throw _failure,
        ),
        bookingIncidentsProvider.overrideWith(
          (ref, id) async => <IncidentReport>[],
        ),
        bookingUnitOptionsProvider.overrideWith(
          (ref, id) async => <BookingUnitOption>[],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('David Mwale'), findsOneWidget);
    expect(find.text('Extension requests'), findsOneWidget);
    expect(find.text('Extension requests could not load.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
