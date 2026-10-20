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

double? _doubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(_str(value));
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
          permissions: _list(
            membership['permissions'],
          ).map(_str).where((item) => item.isNotEmpty).toList(growable: false),
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

/// Where the login's car hire account stands.
enum CarHireAccountState {
  none,
  inReview,
  needsInformation,
  rejected,
  active,
  suspended;

  static CarHireAccountState fromWire(dynamic value) {
    switch (_str(value).toUpperCase()) {
      case 'ACTIVE':
        return CarHireAccountState.active;
      case 'SUSPENDED':
        return CarHireAccountState.suspended;
      case 'NEEDS_INFORMATION':
        return CarHireAccountState.needsInformation;
      case 'REJECTED':
        return CarHireAccountState.rejected;
      case 'IN_REVIEW':
        return CarHireAccountState.inReview;
      default:
        return CarHireAccountState.none;
    }
  }
}

/// The single car hire account behind this login. One login runs one
/// company; renters without a company have [CarHireAccountState.none].
class CarHireAccount {
  const CarHireAccount({
    this.state = CarHireAccountState.none,
    this.companyId,
    this.companyName = '',
    this.companyType = '',
    this.contactPhone,
    this.serviceAreas = const <String>[],
    this.logoUrl,
    this.reviewerNote,
    this.capabilities = const <String>{},
  });

  static const CarHireAccount none = CarHireAccount();

  final CarHireAccountState state;
  final String? companyId;
  final String companyName;

  /// `BUSINESS` or `INDIVIDUAL`.
  final String companyType;
  final String? contactPhone;
  final List<String> serviceAreas;
  final String? logoUrl;
  final String? reviewerNote;
  final Set<String> capabilities;

  bool get isActive => state == CarHireAccountState.active;
  bool get hasProfile => state != CarHireAccountState.none;
  bool get isBusiness => companyType.toUpperCase() == 'BUSINESS';
  bool can(String capability) => capabilities.contains(capability);

  factory CarHireAccount.fromJson(dynamic raw) {
    final json = _map(raw);
    final company = _map(json['company']);
    return CarHireAccount(
      state: CarHireAccountState.fromWire(json['state']),
      companyId: _strOrNull(company['id']),
      companyName: _str(company['displayName']),
      companyType: _str(company['type']).toUpperCase(),
      contactPhone: _strOrNull(company['contactPhone']),
      serviceAreas: _list(
        company['serviceAreas'],
      ).map(_str).where((area) => area.isNotEmpty).toList(growable: false),
      logoUrl: _strOrNull(company['logoUrl']),
      reviewerNote: _strOrNull(company['reviewerNote']),
      capabilities: _list(
        json['capabilities'],
      ).map(_str).where((item) => item.isNotEmpty).toSet(),
    );
  }
}

/// One physical car (registration) in the company fleet.
class FleetUnit {
  const FleetUnit({
    required this.car,
    this.licensePlate,
    this.unitLabel,
    this.listingGroupId,
    this.nextServiceDueAt,
    this.operatorId,
    this.locationId,
    this.tracker,
    this.updatedAt,
  });

  final CarListing car;
  final String? licensePlate;
  final String? unitLabel;
  final String? listingGroupId;
  final DateTime? nextServiceDueAt;

  /// Company that owns the unit, used for branch and team lookups.
  final String? operatorId;

  /// Branch the car is collected from; null when not set.
  final String? locationId;

  /// Paired GPS device, when the unit has one.
  final FleetTracker? tracker;

  final DateTime? updatedAt;

  int get id => car.id;

  String get listingKey => listingGroupId ?? 'car:${car.id}';

  String get plateLabel {
    final plate = licensePlate?.trim();
    final label = unitLabel?.trim();
    final base = plate == null || plate.isEmpty ? 'No plate' : plate;
    return label == null || label.isEmpty ? base : '$base · $label';
  }

  /// Registration only, for compact badges.
  String get plate {
    final value = licensePlate?.trim();
    if (value != null && value.isNotEmpty) return value.toUpperCase();
    final label = unitLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    return 'No plate';
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
      final trackers = _list(row['trackers']);
      out.add(
        FleetUnit(
          car: car,
          licensePlate: _strOrNull(row['licensePlate']),
          unitLabel: _strOrNull(row['unitLabel']),
          listingGroupId: _strOrNull(row['listingGroupId']),
          nextServiceDueAt: service.length >= 10
              ? DateTime.tryParse(service.substring(0, 10))
              : null,
          operatorId: _strOrNull(row['operatorId']),
          locationId: _strOrNull(row['locationId']),
          tracker: trackers.isEmpty
              ? null
              : FleetTracker.fromJson(trackers.first),
          updatedAt: DateTime.tryParse(_str(row['updatedAt'])),
        ),
      );
    }
    return out;
  }
}

/// GPS device paired with a unit. Coordinates are the tracker's last fix.
class FleetTracker {
  const FleetTracker({
    this.deviceId = '',
    this.latitude,
    this.longitude,
    this.speed,
    this.lastUpdate,
  });

  final String deviceId;
  final double? latitude;
  final double? longitude;
  final double? speed;
  final DateTime? lastUpdate;

  bool get hasFix => latitude != null && longitude != null;

  String get deviceLabel => deviceId.trim().isEmpty ? 'Tracker' : deviceId;

  factory FleetTracker.fromJson(dynamic raw) {
    final json = _map(raw);
    final id = _str(json['deviceId']).isEmpty
        ? _str(json['traccarDeviceId'])
        : _str(json['deviceId']);
    return FleetTracker(
      deviceId: id,
      latitude: _doubleOrNull(json['lastLatitude']),
      longitude: _doubleOrNull(json['lastLongitude']),
      speed: _doubleOrNull(json['lastSpeed']),
      lastUpdate: DateTime.tryParse(_str(json['lastUpdate'])),
    );
  }
}

/// A company branch cars can be collected from.
class CompanyBranch {
  const CompanyBranch({
    required this.id,
    required this.name,
    this.address,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? address;
  final bool isActive;

  String get label {
    final value = address?.trim();
    return value == null || value.isEmpty ? name : '$name · $value';
  }

  static List<CompanyBranch> listFromJson(dynamic raw) {
    final out = <CompanyBranch>[];
    for (final item in _list(raw)) {
      final row = _map(item);
      final id = _str(row['id']);
      final name = _str(row['name']);
      if (id.isEmpty || name.isEmpty) continue;
      out.add(
        CompanyBranch(
          id: id,
          name: name,
          address: _strOrNull(row['address']),
          isActive: row['isActive'] != false,
        ),
      );
    }
    return out;
  }
}

/// A maintenance, cleaning or safety block on one unit.
class MaintenanceBlock {
  const MaintenanceBlock({
    required this.id,
    required this.startAt,
    required this.endAt,
    this.category = 'MAINTENANCE',
    this.reason,
    this.status = 'ACTIVE',
  });

  final String id;
  final DateTime startAt;
  final DateTime endAt;
  final String category;
  final String? reason;
  final String status;

  bool get isActive => status.toUpperCase() == 'ACTIVE';

  String get categoryLabel => switch (category.toUpperCase()) {
    'CLEANING' => 'Cleaning',
    'SAFETY' => 'Safety',
    _ => 'Maintenance',
  };

  static List<MaintenanceBlock> listFromJson(dynamic raw) {
    final out = <MaintenanceBlock>[];
    for (final item in _list(raw)) {
      final row = _map(item);
      final id = _str(row['id']);
      final start = DateTime.tryParse(_str(row['startAt']));
      final end = DateTime.tryParse(_str(row['endAt']));
      if (id.isEmpty || start == null || end == null) continue;
      out.add(
        MaintenanceBlock(
          id: id,
          startAt: start,
          endAt: end,
          category: _str(row['category']),
          reason: _strOrNull(row['reason']),
          status: _str(row['status']),
        ),
      );
    }
    return out;
  }
}

/// Owner-facing compliance state for one vehicle.
class CarCompliance {
  const CarCompliance({
    this.compliant = false,
    this.missing = const <String>[],
    this.expired = const <String>[],
  });

  final bool compliant;

  /// Required document types with no approved record.
  final List<String> missing;

  /// Required document types whose approved record lapsed.
  final List<String> expired;

  bool get needsAttention => !compliant;

  int get issueCount => missing.length + expired.length;

  static CarCompliance fromJson(dynamic raw) {
    final json = _map(raw);
    List<String> types(dynamic value) => _list(
      value,
    ).map(_str).where((item) => item.isNotEmpty).toList(growable: false);
    return CarCompliance(
      compliant: json['compliant'] == true || json['documentsApproved'] == true,
      missing: types(json['missing']),
      expired: types(json['expired']),
    );
  }
}

/// Human label for a vehicle document type.
String vehicleDocumentLabel(String type) => switch (type.toUpperCase()) {
  'REGISTRATION' => 'Registration',
  'INSURANCE' => 'Insurance',
  'ROADWORTHINESS' => 'Roadworthiness',
  'OWNERSHIP_AUTHORIZATION' => 'Ownership authorisation',
  'PERMIT' => 'Permit',
  _ => type,
};

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
    final parts = <String>[licensePlate ?? 'Car #$carId', ?color, ?unitLabel];
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

/// Owner-scoped performance for a period, used by the fleet pulse card.
class CompanyAnalytics {
  const CompanyAnalytics({
    this.revenue = 0,
    this.bookings = 0,
    this.completed = 0,
    this.cancelled = 0,
    this.utilizationRate = 0,
    this.units = 0,
    this.periodDays = 0,
    this.currency = 'MWK',
  });

  final double revenue;
  final int bookings;
  final int completed;
  final int cancelled;

  /// Percentage of available car-days that were on hire.
  final int utilizationRate;
  final int units;
  final int periodDays;
  final String currency;

  static CompanyAnalytics? fromJson(dynamic raw) {
    final json = _map(raw);
    final data = json['data'] is Map ? _map(json['data']) : json;
    if (data.isEmpty) return null;
    final revenueRaw = data['revenue'] ?? json['revenue'];
    return CompanyAnalytics(
      revenue: revenueRaw is num
          ? revenueRaw.toDouble()
          : double.tryParse(_str(revenueRaw)) ?? 0,
      bookings: _int(data['bookings']),
      completed: _int(data['completed']),
      cancelled: _int(data['cancelled']),
      utilizationRate: _int(data['utilizationRate']),
      units: _int(data['totalCars'] ?? data['units']),
      periodDays: _int(data['periodDays']),
      currency: _str(data['currency']).isEmpty ? 'MWK' : _str(data['currency']),
    );
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
