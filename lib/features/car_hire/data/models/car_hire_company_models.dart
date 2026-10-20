import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return const <String, dynamic>{};
}

List<dynamic> _list(dynamic value) {
  if (value is List) return value;
  if (value is Map) {
    final data = value['data'];
    if (data is List) return data;
  }
  return const <dynamic>[];
}

String _str(dynamic value) => value == null ? '' : value.toString().trim();

String? _strOrNull(dynamic value) {
  final text = _str(value);
  return text.isEmpty ? null : text;
}

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(_str(value)) ?? 0;
}

/// Permissions a company member can hold (mirrors the backend).
class CompanyPermission {
  CompanyPermission._();

  static const String fleetManage = 'fleet.manage';
  static const String bookingsView = 'bookings.view';
  static const String bookingsManage = 'bookings.manage';
}

/// The signed-in user's membership of one car hire company.
class CompanyMembership {
  const CompanyMembership({
    required this.operatorId,
    required this.companyName,
    this.companyStatus = '',
    this.role = '',
    this.status = '',
    this.permissions = const <String>[],
    this.instantBook = true,
  });

  final String operatorId;
  final String companyName;
  final String companyStatus;
  final String role;
  final String status;
  final List<String> permissions;
  final bool instantBook;

  bool get isOwner => role == 'OWNER';

  /// Only active members of an approved company get company mode.
  bool get isUsable => companyStatus == 'ACTIVE' && status == 'ACTIVE';

  bool can(String permission) => isOwner || permissions.contains(permission);

  bool get canViewBookings =>
      can(CompanyPermission.bookingsView) ||
      can(CompanyPermission.bookingsManage);

  bool get canManageBookings => can(CompanyPermission.bookingsManage);

  bool get canManageFleet => can(CompanyPermission.fleetManage);

  static List<CompanyMembership> listFromJson(dynamic raw) {
    final out = <CompanyMembership>[];
    for (final item in _list(raw)) {
      final row = _map(item);
      final id = _str(row['id']);
      if (id.isEmpty) continue;
      final membership = _map(row['membership']);
      out.add(
        CompanyMembership(
          operatorId: id,
          companyName: _str(row['displayName']).isEmpty
              ? 'Your company'
              : _str(row['displayName']),
          companyStatus: _str(row['status']).toUpperCase(),
          role: _str(membership['role']).toUpperCase(),
          status: _str(membership['status']).toUpperCase(),
          permissions: _list(membership['permissions'])
              .map(_str)
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
          instantBook: row['instantBook'] != false,
        ),
      );
    }
    return out;
  }
}

/// Combined permissions across every company the user actively belongs to.
class CompanyAccess {
  const CompanyAccess(this.memberships);

  final List<CompanyMembership> memberships;

  List<CompanyMembership> get usable =>
      memberships.where((item) => item.isUsable).toList(growable: false);

  bool get hasCompany => usable.isNotEmpty;

  bool get canViewBookings => usable.any((item) => item.canViewBookings);

  bool get canManageBookings => usable.any((item) => item.canManageBookings);

  bool get canManageFleet => usable.any((item) => item.canManageFleet);

  String get title =>
      usable.length == 1 ? usable.first.companyName : 'Your companies';
}

/// One physical car (registration) in the company fleet.
class FleetUnit {
  const FleetUnit({
    required this.car,
    this.licensePlate,
    this.unitLabel,
    this.listingGroupId,
    this.nextServiceDueAt,
  });

  final CarListing car;
  final String? licensePlate;
  final String? unitLabel;
  final String? listingGroupId;
  final DateTime? nextServiceDueAt;

  int get id => car.id;

  String get listingKey => listingGroupId ?? 'car:${car.id}';

  String get plateLabel {
    final plate = licensePlate?.trim();
    final label = unitLabel?.trim();
    final base = plate == null || plate.isEmpty ? 'No plate' : plate;
    return label == null || label.isEmpty ? base : '$base · $label';
  }

  bool get serviceDueSoon {
    final due = nextServiceDueAt;
    if (due == null) return false;
    return due.difference(DateTime.now()).inDays <= 14;
  }

  static List<FleetUnit> listFromJson(dynamic raw) {
    final out = <FleetUnit>[];
    for (final item in _list(raw)) {
      final row = _map(item);
      final car = CarListing.fromJson(row);
      if (car.id <= 0) continue;
      final service = _str(row['nextServiceDueAt']);
      out.add(
        FleetUnit(
          car: car,
          licensePlate: _strOrNull(row['licensePlate']),
          unitLabel: _strOrNull(row['unitLabel']),
          listingGroupId: _strOrNull(row['listingGroupId']),
          nextServiceDueAt: service.length >= 10
              ? DateTime.tryParse(service.substring(0, 10))
              : null,
        ),
      );
    }
    return out;
  }
}

/// A unit of the booked listing that the company could assign.
class BookingUnitOption {
  const BookingUnitOption({
    required this.carId,
    this.licensePlate,
    this.color,
    this.unitLabel,
    this.inService = true,
    this.freeForBooking = false,
    this.current = false,
  });

  final int carId;
  final String? licensePlate;
  final String? color;
  final String? unitLabel;
  final bool inService;
  final bool freeForBooking;
  final bool current;

  bool get selectable => current || (inService && freeForBooking);

  String get label {
    final parts = <String>[
      licensePlate ?? 'Car #$carId',
      ?color,
      ?unitLabel,
    ];
    return parts.join(' · ');
  }

  static List<BookingUnitOption> listFromJson(dynamic raw) {
    final out = <BookingUnitOption>[];
    for (final item in _list(raw)) {
      final row = _map(item);
      final carId = _int(row['carId']);
      if (carId <= 0) continue;
      out.add(
        BookingUnitOption(
          carId: carId,
          licensePlate: _strOrNull(row['licensePlate']),
          color: _strOrNull(row['color']),
          unitLabel: _strOrNull(row['unitLabel']),
          inService: row['inService'] != false,
          freeForBooking: row['freeForBooking'] == true,
          current: row['current'] == true,
        ),
      );
    }
    return out;
  }
}

class ServiceDueItem {
  const ServiceDueItem({
    required this.carId,
    required this.title,
    this.licensePlate,
    this.dueDate = '',
    this.overdue = false,
  });

  final int carId;
  final String title;
  final String? licensePlate;
  final String dueDate;
  final bool overdue;
}

/// One day of company operations.
class DispatchBoard {
  const DispatchBoard({
    this.date = '',
    this.pickups = const <CarHireBooking>[],
    this.returns = const <CarHireBooking>[],
    this.latePickups = const <CarHireBooking>[],
    this.overdueReturns = const <CarHireBooking>[],
    this.awaitingResponse = const <CarHireBooking>[],
    this.serviceDue = const <ServiceDueItem>[],
  });

  final String date;
  final List<CarHireBooking> pickups;
  final List<CarHireBooking> returns;
  final List<CarHireBooking> latePickups;
  final List<CarHireBooking> overdueReturns;
  final List<CarHireBooking> awaitingResponse;
  final List<ServiceDueItem> serviceDue;

  bool get needsAttention =>
      latePickups.isNotEmpty ||
      overdueReturns.isNotEmpty ||
      awaitingResponse.isNotEmpty;

  bool get isEmpty =>
      pickups.isEmpty &&
      returns.isEmpty &&
      !needsAttention &&
      serviceDue.isEmpty;

  factory DispatchBoard.fromJson(dynamic raw) {
    final json = _map(raw);
    List<CarHireBooking> bookings(dynamic value) => _list(value)
        .whereType<Map>()
        .map((item) => CarHireBooking.fromJson(item))
        .where((booking) => booking.id > 0)
        .toList(growable: false);

    return DispatchBoard(
      date: _str(json['date']),
      pickups: bookings(json['pickups']),
      returns: bookings(json['returns']),
      latePickups: bookings(json['latePickups']),
      overdueReturns: bookings(json['overdueReturns']),
      awaitingResponse: bookings(json['awaitingResponse']),
      serviceDue: _list(json['serviceDue'])
          .map((item) {
            final row = _map(item);
            return ServiceDueItem(
              carId: _int(row['carId']),
              title: _str(row['title']),
              licensePlate: _strOrNull(row['licensePlate']),
              dueDate: _str(row['nextServiceDueAt']),
              overdue: row['overdue'] == true,
            );
          })
          .where((item) => item.carId > 0)
          .toList(growable: false),
    );
  }
}
