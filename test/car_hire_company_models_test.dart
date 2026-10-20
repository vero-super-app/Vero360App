import 'package:flutter_test/flutter_test.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';

void main() {
  group('CarHireCompanyOption', () {
    test('parses a public company and builds initials', () {
      final company = CarHireCompanyOption.fromJson({
        'id': 'op-9',
        'name': 'Blantyre Car Hire',
        'logoUrl': null,
        'listings': 4,
        'instantBook': false,
      })!;
      expect(company.name, 'Blantyre Car Hire');
      expect(company.listings, 4);
      expect(company.instantBook, isFalse);
      expect(company.initials, 'BC');
    });

    test('skips rows without an id or name', () {
      expect(CarHireCompanyOption.fromJson({'id': '', 'name': 'X'}), isNull);
      expect(CarHireCompanyOption.fromJson({'id': 'a', 'name': ' '}), isNull);
      expect(CarHireCompanyOption.fromJson('nope'), isNull);
    });
  });

  group('CarHireFilters', () {
    const company = CarHireCompanyOption(id: 'op-1', name: 'Zed Rentals');

    test('counts sheet filters but not the search text', () {
      const filters = CarHireFilters(
        company: company,
        minSeats: 7,
        instantOnly: true,
        text: 'prado',
      );
      expect(filters.activeCount, 3);
      expect(filters.isEmpty, isFalse);
      expect(const CarHireFilters().isEmpty, isTrue);
      expect(const CarHireFilters(text: 'x').isEmpty, isFalse);
    });

    test('copyWith can clear a single filter', () {
      const filters = CarHireFilters(company: company, transmission: 'MANUAL');
      final cleared = filters.copyWith(company: () => null);
      expect(cleared.company, isNull);
      expect(cleared.transmission, 'MANUAL');
      expect(cleared == filters, isFalse);
    });
  });

  group('CompanyMembership', () {
    final memberships = CompanyMembership.listFromJson(<dynamic>[
      {
        'id': 'op-1',
        'displayName': 'Lilongwe Rentals',
        'status': 'ACTIVE',
        'instantBook': false,
        'membership': {
          'role': 'MEMBER',
          'status': 'ACTIVE',
          'permissions': ['bookings.view'],
        },
      },
      {
        'id': 'op-2',
        'displayName': 'Pending Co',
        'status': 'PENDING_REVIEW',
        'membership': {'role': 'OWNER', 'status': 'ACTIVE'},
      },
    ]);

    test('parses company and member permissions', () {
      final member = memberships.first;
      expect(member.companyName, 'Lilongwe Rentals');
      expect(member.instantBook, isFalse);
      expect(member.isUsable, isTrue);
      expect(member.canViewBookings, isTrue);
      expect(member.canManageBookings, isFalse);
      expect(member.canManageFleet, isFalse);
    });

    test('owners hold every permission but need an approved company', () {
      final owner = memberships.last;
      expect(owner.canManageFleet, isTrue);
      expect(owner.isUsable, isFalse);
    });

    test('access only counts usable memberships', () {
      final access = CompanyAccess(memberships);
      expect(access.hasCompany, isTrue);
      expect(access.title, 'Lilongwe Rentals');
      expect(access.canManageFleet, isFalse);
      expect(const CompanyAccess(<CompanyMembership>[]).hasCompany, isFalse);
    });
  });

  test('FleetUnit groups by listing and flags service due', () {
    final soon = DateTime.now().add(const Duration(days: 3));
    final key =
        '${soon.year}-${soon.month.toString().padLeft(2, '0')}-${soon.day.toString().padLeft(2, '0')}';
    final units = FleetUnit.listFromJson(<String, dynamic>{
      'data': [
        {
          'id': 4,
          'make': 'Toyota',
          'model': 'Axio',
          'licensePlate': 'BT 1234',
          'listingGroupId': 'g-1',
          'nextServiceDueAt': key,
          'isAvailable': false,
        },
        {'id': 5, 'make': 'Honda', 'model': 'Fit'},
      ],
    });
    expect(units, hasLength(2));
    expect(units.first.listingKey, 'g-1');
    expect(units.first.plateLabel, 'BT 1234');
    expect(units.first.serviceDueSoon, isTrue);
    expect(units.first.car.isAvailable, isFalse);
    expect(units.last.listingKey, 'car:5');
    expect(units.last.plateLabel, 'No plate');
  });

  test('BookingUnitOption is selectable only when free or current', () {
    final options = BookingUnitOption.listFromJson(<dynamic>[
      {'carId': 1, 'licensePlate': 'A 1', 'current': true, 'freeForBooking': false},
      {'carId': 2, 'licensePlate': 'A 2', 'freeForBooking': true},
      {'carId': 3, 'licensePlate': 'A 3', 'freeForBooking': true, 'inService': false},
    ]);
    expect(options.map((o) => o.selectable), [true, true, false]);
  });

  test('DispatchBoard parses groups, branch and renter', () {
    final board = DispatchBoard.fromJson(<String, dynamic>{
      'date': '2026-10-20',
      'pickups': [
        {
          'id': 9,
          'bookingStatus': 'CONFIRMED',
          'renterName': 'Chikondi',
          'renterPhone': '0999',
          'branch': {'id': 'b1', 'name': 'Airport'},
          'assignedUnit': {'carId': 4, 'licensePlate': 'BT 1234'},
        },
      ],
      'awaitingResponse': [
        {'id': 10, 'bookingStatus': 'PENDING', 'bookingMode': 'REQUEST'},
      ],
      'serviceDue': [
        {'carId': 4, 'title': 'Toyota Axio', 'nextServiceDueAt': '2026-10-22'},
      ],
    });
    expect(board.pickups.single.renterName, 'Chikondi');
    expect(board.pickups.single.branchName, 'Airport');
    expect(board.pickups.single.assignedCarId, 4);
    expect(board.awaitingResponse.single.isRequest, isTrue);
    expect(board.needsAttention, isTrue);
    expect(board.serviceDue.single.dueDate, '2026-10-22');
    expect(board.isEmpty, isFalse);
  });

  test('extension, inspection and incident keep UUID ids', () {
    const uuid = '3f2a1c4e-9b7d-4e21-8a55-0c6f2d9e1b77';
    expect(BookingExtension.fromJson({'id': uuid}).id, uuid);
    expect(HandoverInspection.fromJson({'id': uuid}).id, uuid);
    expect(IncidentReport.fromJson({'id': uuid}).id, uuid);
    expect(SupportCase.fromJson({'id': uuid}).id, uuid);
  });
}
