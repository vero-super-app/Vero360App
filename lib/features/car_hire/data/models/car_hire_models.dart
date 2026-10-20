import 'package:vero360_app/utils/formatters.dart';

// ---------------------------------------------------------------------------
// Tolerant JSON helpers.
//
// Postgres decimal / bigint columns are serialized as strings by the backend
// (e.g. "45000.00"). Never call `.toDouble()` / `.toInt()` on raw JSON values.
// ---------------------------------------------------------------------------

double _asDouble(dynamic value, {double fallback = 0}) {
  if (value is num) {
    final parsed = value.toDouble();
    return parsed.isFinite ? parsed : fallback;
  }
  if (value is String) {
    final cleaned = value.trim().replaceAll(',', '').replaceAll(' ', '');
    if (cleaned.isEmpty) return fallback;
    final parsed = double.tryParse(cleaned);
    return parsed != null && parsed.isFinite ? parsed : fallback;
  }
  return fallback;
}

double? _asNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is String && value.trim().isEmpty) return null;
  final parsed = _asDouble(value, fallback: double.nan);
  return parsed.isFinite ? parsed : null;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.round() : fallback;
  if (value is String) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return fallback;
    final direct = int.tryParse(cleaned);
    if (direct != null) return direct;
    final parsed = double.tryParse(cleaned.replaceAll(',', ''));
    if (parsed != null && parsed.isFinite) return parsed.round();
  }
  return fallback;
}

int? _asNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is String && value.trim().isEmpty) return null;
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.round() : null;
  if (value is String) {
    final cleaned = value.trim();
    final direct = int.tryParse(cleaned);
    if (direct != null) return direct;
    final parsed = double.tryParse(cleaned.replaceAll(',', ''));
    if (parsed != null && parsed.isFinite) return parsed.round();
  }
  return null;
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String? _asStringOrNull(dynamic value) {
  final text = _asString(value);
  return text.isEmpty ? null : text;
}

/// Returns the first non-null value for a camelCase or snake_case key.
dynamic _pick(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null) return value;
  }
  return null;
}

bool _asBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'y':
        return true;
      case 'false':
      case '0':
      case 'no':
      case 'n':
        return false;
    }
  }
  return fallback;
}

DateTime? _asDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is int) {
    final millis = value.abs() < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  }
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed.toLocal();
    final epoch = int.tryParse(text);
    if (epoch != null) {
      final millis = epoch.abs() < 100000000000 ? epoch * 1000 : epoch;
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
    }
  }
  return null;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

List<dynamic> _asList(dynamic value) {
  if (value is List) return value;
  return const <dynamic>[];
}

const Set<String> _wireAcronyms = <String>{
  'SUV',
  'MPV',
  'AWD',
  'RWD',
  'FWD',
  '4X4',
  'GPS',
  'AC',
};

/// Turns wire values such as `AUTOMATIC` / `NOT_REQUIRED` into
/// `Automatic` / `Not required` for display.
String _humanizeWire(dynamic value) {
  final raw = _asString(value);
  if (raw.isEmpty) return '';
  if (_wireAcronyms.contains(raw.toUpperCase())) return raw.toUpperCase();
  return raw
      .split(RegExp(r'[_\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) {
        if (_wireAcronyms.contains(part.toUpperCase())) {
          return part.toUpperCase();
        }
        final lower = part.toLowerCase();
        return '${lower.substring(0, 1).toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}

/// Formats server amounts the same way the price breakdown does: MWK uses the
/// shared currency formatter, other currencies fall back to a plain code.
String carHireMoney(String currency, double amount) {
  final code = currency.trim().toUpperCase();
  if (code.isEmpty || code == 'MWK') {
    return CarHireFormatters.formatCurrency(amount);
  }
  return '$code ${amount.toStringAsFixed(2)}';
}

List<String> _asChecklist(dynamic value) {
  if (value is List) {
    return value
        .map(_asString)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (value is Map) {
    final items = <String>[];
    value.forEach((key, item) {
      final label = _asString(key);
      if (label.isEmpty) return;
      if (item is bool) {
        if (item) items.add(label);
        return;
      }
      if (item is num) {
        if (item != 0) items.add(label);
        return;
      }
      if (item is List) {
        items.addAll(item.map(_asString).where((entry) => entry.isNotEmpty));
        return;
      }
      final text = _asString(item).toLowerCase();
      if (text.isEmpty || text == 'false' || text == 'no' || text == '0') return;
      items.add(label);
    });
    return items;
  }
  final single = _asString(value);
  if (single.isEmpty) return const <String>[];
  return single
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<String> _asMedia(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item is Map ? _asString(item['url'] ?? item['reference']) : _asString(item))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  final single = _asString(value);
  if (single.isEmpty) return const <String>[];
  return single
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum BookingStatus {
  pending('PENDING', 'Pending'),
  confirmed('CONFIRMED', 'Confirmed'),
  active('ACTIVE', 'Active'),
  completed('COMPLETED', 'Completed'),
  cancelled('CANCELLED', 'Cancelled'),
  expired('EXPIRED', 'Expired'),
  rejected('REJECTED', 'Rejected'),
  incidentReported('INCIDENT_REPORTED', 'Incident reported'),
  unknown('UNKNOWN', 'Unknown');

  const BookingStatus(this.wire, this.label);

  final String wire;
  final String label;

  static BookingStatus fromWire(dynamic value) {
    final normalized = _asString(value).toUpperCase();
    for (final status in BookingStatus.values) {
      if (status.wire == normalized) return status;
    }
    return BookingStatus.unknown;
  }

  bool get isTerminal =>
      this == cancelled ||
      this == completed ||
      this == expired ||
      this == rejected;

  bool get isOpen =>
      this == pending || this == confirmed || this == active;
}

enum PaymentStatus {
  notRequired('NOT_REQUIRED', 'Not required'),
  notStarted('NOT_STARTED', 'Not started'),
  pending('PENDING', 'Pending confirmation'),
  succeeded('SUCCEEDED', 'Paid'),
  failed('FAILED', 'Failed'),
  refunded('REFUNDED', 'Refunded'),
  unknown('UNKNOWN', 'Unknown');

  const PaymentStatus(this.wire, this.label);

  final String wire;
  final String label;

  static PaymentStatus fromWire(dynamic value) {
    final normalized = _asString(value).toUpperCase();
    for (final status in PaymentStatus.values) {
      if (status.wire == normalized) return status;
    }
    return PaymentStatus.unknown;
  }

  bool get isSettled => this == succeeded || this == notRequired;
}

enum ListingStatus {
  draft('DRAFT', 'Draft'),
  pendingReview('PENDING_REVIEW', 'Pending review'),
  published('PUBLISHED', 'Published'),
  suspended('SUSPENDED', 'Suspended'),
  retired('RETIRED', 'Retired'),
  unknown('UNKNOWN', 'Unknown');

  const ListingStatus(this.wire, this.label);

  final String wire;
  final String label;

  static ListingStatus fromWire(dynamic value) {
    final normalized = _asString(value).toUpperCase();
    for (final status in ListingStatus.values) {
      if (status.wire == normalized) return status;
    }
    return ListingStatus.unknown;
  }
}

enum QuoteStatus {
  active('ACTIVE', 'Active'),
  consumed('CONSUMED', 'Used'),
  expired('EXPIRED', 'Expired'),
  unknown('UNKNOWN', 'Unknown');

  const QuoteStatus(this.wire, this.label);

  final String wire;
  final String label;

  static QuoteStatus fromWire(dynamic value) {
    final normalized = _asString(value).toUpperCase();
    for (final status in QuoteStatus.values) {
      if (status.wire == normalized) return status;
    }
    return QuoteStatus.unknown;
  }
}

enum VerificationState {
  notStarted('NOT_STARTED', 'Not started'),
  submitted('SUBMITTED', 'Submitted'),
  underReview('UNDER_REVIEW', 'Under review'),
  verified('VERIFIED', 'Verified'),
  rejected('REJECTED', 'Rejected'),
  expired('EXPIRED', 'Expired'),
  suspended('SUSPENDED', 'Suspended'),
  unknown('UNKNOWN', 'Unknown');

  const VerificationState(this.wire, this.label);

  final String wire;
  final String label;

  static VerificationState fromWire(dynamic value) {
    final normalized = _asString(value).toUpperCase();
    for (final state in VerificationState.values) {
      if (state.wire == normalized) return state;
    }
    return VerificationState.unknown;
  }

  bool get needsAttention =>
      this == submitted ||
      this == underReview ||
      this == rejected ||
      this == expired ||
      this == suspended;
}

enum ExtensionStatus {
  requested('REQUESTED', 'Requested'),
  pending('PENDING', 'Pending'),
  approved('APPROVED', 'Approved'),
  declined('DECLINED', 'Declined'),
  cancelled('CANCELLED', 'Cancelled'),
  expired('EXPIRED', 'Expired'),
  unknown('UNKNOWN', 'Unknown');

  const ExtensionStatus(this.wire, this.label);

  final String wire;
  final String label;

  static ExtensionStatus fromWire(dynamic value) {
    final normalized = _asString(value).toUpperCase();
    for (final status in ExtensionStatus.values) {
      if (status.wire == normalized) return status;
    }
    return ExtensionStatus.unknown;
  }

  bool get isOpen => this == requested || this == pending;

  bool get isDeclined =>
      this == declined || this == cancelled || this == expired;
}

enum InspectionType {
  pickup('PICKUP', 'Pick-up'),
  returnInspection('RETURN', 'Return'),
  unknown('UNKNOWN', 'Inspection');

  const InspectionType(this.wire, this.label);

  final String wire;
  final String label;

  static InspectionType fromWire(dynamic value) {
    final normalized = _asString(value).toUpperCase();
    for (final type in InspectionType.values) {
      if (type.wire == normalized) return type;
    }
    return InspectionType.unknown;
  }
}

enum InspectionActorRole {
  renter('RENTER', 'Renter'),
  owner('OWNER', 'Vehicle provider'),
  admin('ADMIN', 'Vero360 support'),
  unknown('UNKNOWN', 'Unknown');

  const InspectionActorRole(this.wire, this.label);

  final String wire;
  final String label;

  static InspectionActorRole fromWire(dynamic value) {
    final normalized = _asString(value).toUpperCase();
    switch (normalized) {
      case 'RENTER':
      case 'CUSTOMER':
      case 'USER':
        return InspectionActorRole.renter;
      case 'OWNER':
      case 'PROVIDER':
      case 'HOST':
        return InspectionActorRole.owner;
      case 'ADMIN':
      case 'SUPPORT':
        return InspectionActorRole.admin;
    }
    return InspectionActorRole.unknown;
  }
}

enum InspectionStatus {
  pending('PENDING', 'Pending'),
  submitted('SUBMITTED', 'Submitted'),
  acknowledged('ACKNOWLEDGED', 'Acknowledged'),
  declined('DECLINED', 'Declined'),
  disputed('DISPUTED', 'Disputed'),
  unknown('UNKNOWN', 'Unknown');

  const InspectionStatus(this.wire, this.label);

  final String wire;
  final String label;

  static InspectionStatus fromWire(dynamic value) {
    final normalized = _asString(value).toUpperCase();
    for (final status in InspectionStatus.values) {
      if (status.wire == normalized) return status;
    }
    return InspectionStatus.unknown;
  }
}

enum IncidentType {
  accident('ACCIDENT', 'Accident'),
  breakdown('BREAKDOWN', 'Breakdown'),
  theft('THEFT', 'Theft'),
  unsafeVehicle('UNSAFE_VEHICLE', 'Unsafe vehicle'),
  noShow('NO_SHOW', 'Provider no-show'),
  failedPickup('FAILED_PICKUP', 'Failed pick-up'),
  ownerUnavailable('OWNER_UNAVAILABLE', 'Provider unavailable'),
  other('OTHER', 'Other'),
  unknown('UNKNOWN', 'Unknown');

  const IncidentType(this.wire, this.label);

  final String wire;
  final String label;

  static IncidentType fromWire(dynamic value) {
    final normalized = _asString(value).toUpperCase();
    for (final type in IncidentType.values) {
      if (type.wire == normalized) return type;
    }
    return IncidentType.unknown;
  }
}

enum SupportCaseCategory {
  booking('BOOKING', 'Booking'),
  payment('PAYMENT', 'Payment'),
  damage('DAMAGE', 'Damage'),
  handover('HANDOVER', 'Handover'),
  safety('SAFETY', 'Safety'),
  other('OTHER', 'Other'),
  unknown('UNKNOWN', 'Unknown');

  const SupportCaseCategory(this.wire, this.label);

  final String wire;
  final String label;

  static SupportCaseCategory fromWire(dynamic value) {
    final normalized = _asString(value).toUpperCase();
    for (final category in SupportCaseCategory.values) {
      if (category.wire == normalized) return category;
    }
    return SupportCaseCategory.unknown;
  }
}

// ---------------------------------------------------------------------------
// Public vehicle listing (`CarPublicView`)
// ---------------------------------------------------------------------------

/// The company or individual host that provides a listing.
class CarHireProvider {
  const CarHireProvider({
    required this.id,
    required this.name,
    this.type = '',
    this.logoUrl,
  });

  final String id;
  final String name;
  final String type;
  final String? logoUrl;

  bool get isBusiness => type.toUpperCase() == 'BUSINESS';

  static CarHireProvider? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final json = _asMap(raw);
    final id = _asString(json['id']);
    final name = _asString(json['name'] ?? json['displayName']).trim();
    if (id.isEmpty || name.isEmpty) return null;
    return CarHireProvider(
      id: id,
      name: name,
      type: _asString(json['type']),
      logoUrl: _asStringOrNull(json['logoUrl']),
    );
  }
}

class CarListing {
  const CarListing({
    required this.id,
    required this.make,
    required this.model,
    this.year,
    this.color,
    this.dailyRate = 0,
    this.currency = 'MWK',
    this.isAvailable = true,
    this.imageUrl,
    this.images = const <String>[],
    this.description,
    this.seats,
    this.transmission,
    this.fuelType,
    this.bodyType,
    this.pickupArea,
    this.latitude,
    this.longitude,
    this.rating = 0,
    this.reviews = 0,
    this.listingStatus = ListingStatus.published,
    this.availableForDates,
    this.depositAmount = 0,
    this.minRentalDays = 1,
    this.maxRentalDays,
    this.provider,
    this.listingId,
    this.unitCount,
    this.availableUnits,
    this.branchName,
    this.branchAddress,
    this.instantBook = true,
  });

  final int id;
  final String make;
  final String model;
  final int? year;
  final String? color;
  final double dailyRate;
  final String currency;
  final bool isAvailable;
  final String? imageUrl;

  /// Public gallery. Never contains private registration data.
  final List<String> images;
  final String? description;
  final int? seats;
  final String? transmission;
  final String? fuelType;
  final String? bodyType;
  final String? pickupArea;
  final double? latitude;
  final double? longitude;
  final double rating;
  final int reviews;
  final ListingStatus listingStatus;
  final bool? availableForDates;
  final double depositAmount;
  final int minRentalDays;
  final int? maxRentalDays;
  final CarHireProvider? provider;

  /// Shared id of identical units; null for a single-unit listing.
  final String? listingId;

  /// Identical units in service on this listing.
  final int? unitCount;

  /// Units free for the searched dates (or in service when undated).
  final int? availableUnits;

  /// Company branch the car is collected from, when set.
  final String? branchName;
  final String? branchAddress;

  /// False when the company accepts each request before the renter pays.
  final bool instantBook;

  String get bookingModeLabel => instantBook
      ? 'Confirmed instantly after payment'
      : 'Company confirms within 24h, then you pay';

  String? get branchLabel {
    final name = branchName?.trim();
    if (name == null || name.isEmpty) return null;
    final address = branchAddress?.trim();
    return address == null || address.isEmpty ? name : '$name, $address';
  }

  /// "Provided by …" line, empty when the backend did not send a provider.
  String get providerLabel =>
      provider == null ? '' : 'Provided by ${provider!.name}';

  /// "3 left" for multi-unit listings; null when there is nothing to show.
  String? get unitsLeftLabel {
    final total = unitCount ?? 0;
    final free = availableUnits;
    if (total <= 1 || free == null || free <= 0) return null;
    return '$free left';
  }

  factory CarListing.fromJson(dynamic raw) {
    final json = _asMap(raw);
    final images = _asList(json['images'])
        .map((item) => _asString(item))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final imageUrl = _asStringOrNull(json['imageUrl']);
    final minDaysRaw = _asInt(json['minRentalDays'], fallback: 1);
    final location = _asMap(json['location']);

    return CarListing(
      id: _asInt(json['id']),
      // The backend uses `make`; legacy payloads used `brand`.
      make: _asString(json['make'] ?? json['brand']),
      model: _asString(json['model']),
      year: _asNullableInt(json['year']),
      color: _asStringOrNull(json['color']),
      dailyRate: _asDouble(
        json['dailyRate'] ?? json['pricePerDay'] ?? json['price'],
      ),
      currency: _asString(json['currency'], fallback: 'MWK'),
      isAvailable: _asBool(json['isAvailable'], fallback: true),
      imageUrl: imageUrl,
      images: images,
      description: _asStringOrNull(json['description']),
      seats: _asNullableInt(json['seats']),
      transmission: _asStringOrNull(json['transmission']),
      fuelType: _asStringOrNull(json['fuelType']),
      bodyType: _asStringOrNull(json['bodyType']),
      pickupArea: _asStringOrNull(json['pickupArea']),
      latitude: _asNullableDouble(json['latitude']),
      longitude: _asNullableDouble(json['longitude']),
      rating: _asDouble(json['rating']),
      reviews: _asInt(json['reviews'] ?? json['reviewCount']),
      listingStatus: ListingStatus.fromWire(
        _asStringOrNull(json['listingStatus']) ?? 'PUBLISHED',
      ),
      availableForDates: json.containsKey('availableForDates') &&
              json['availableForDates'] != null
          ? _asBool(json['availableForDates'])
          : null,
      depositAmount: _asDouble(json['depositAmount']),
      minRentalDays: minDaysRaw <= 0 ? 1 : minDaysRaw,
      maxRentalDays: _asNullableInt(json['maxRentalDays']),
      provider: CarHireProvider.fromJson(json['operator']),
      listingId: _asStringOrNull(json['listingId']),
      unitCount: _asNullableInt(json['unitCount']),
      availableUnits: _asNullableInt(json['availableUnits']),
      branchName: _asStringOrNull(location['name']),
      branchAddress: _asStringOrNull(location['address']),
      instantBook: _asBool(json['instantBook'], fallback: true),
    );
  }

  static List<CarListing> listFromJson(dynamic raw) {
    final list = raw is List ? raw : _asList(_asMap(raw)['data']);
    return list
        .whereType<Map>()
        .map((item) => CarListing.fromJson(item))
        .toList(growable: false);
  }

  /// `images[]` first, then the single `imageUrl` fallback.
  List<String> get galleryImages {
    if (images.isNotEmpty) return images;
    final single = imageUrl?.trim();
    if (single != null && single.isNotEmpty) return <String>[single];
    return const <String>[];
  }

  String? get primaryImage =>
      galleryImages.isEmpty ? null : galleryImages.first;

  String get title {
    final parts = <String>[
      if (make.trim().isNotEmpty) make.trim(),
      if (model.trim().isNotEmpty) model.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    return id > 0 ? 'Vehicle #$id' : 'Vehicle';
  }

  String get subtitle {
    final parts = <String>[
      if (year != null) '$year',
      if (bodyLabel.isNotEmpty) bodyLabel,
      if (color != null && color!.trim().isNotEmpty) _humanizeWire(color),
    ];
    return parts.join(' · ');
  }

  String get pricePerDayLabel =>
      '${CarHireFormatters.formatCurrency(dailyRate)} / day';

  String get seatsLabel =>
      seats == null ? 'Seats not specified' : '$seats seats';

  String get transmissionLabel {
    final label = _humanizeWire(transmission);
    return label.isEmpty ? 'Transmission not specified' : label;
  }

  String get fuelLabel {
    final label = _humanizeWire(fuelType);
    return label.isEmpty ? 'Fuel not specified' : label;
  }

  String get bodyLabel => _humanizeWire(bodyType);

  String get pickupAreaLabel {
    final area = pickupArea?.trim();
    return area == null || area.isEmpty ? 'Pickup area not specified' : area;
  }

  String get availabilityLabel {
    if (!isAvailable) return 'Currently unavailable';
    if (availableForDates == false) return 'Not available for these dates';
    return 'Available';
  }

  bool get isPublished => listingStatus == ListingStatus.published;

  bool get isBookable =>
      isAvailable && isPublished && availableForDates != false;

  String get rentalWindowLabel {
    if (maxRentalDays == null) {
      return 'Minimum $minRentalDays day${minRentalDays == 1 ? '' : 's'}';
    }
    return 'Minimum $minRentalDays day${minRentalDays == 1 ? '' : 's'} · '
        'Maximum $maxRentalDays day${maxRentalDays == 1 ? '' : 's'}';
  }

  CarListing copyWith({
    bool? isAvailable,
    bool? availableForDates,
    ListingStatus? listingStatus,
  }) {
    return CarListing(
      id: id,
      make: make,
      model: model,
      year: year,
      color: color,
      dailyRate: dailyRate,
      currency: currency,
      isAvailable: isAvailable ?? this.isAvailable,
      imageUrl: imageUrl,
      images: images,
      description: description,
      seats: seats,
      transmission: transmission,
      fuelType: fuelType,
      bodyType: bodyType,
      pickupArea: pickupArea,
      latitude: latitude,
      longitude: longitude,
      rating: rating,
      reviews: reviews,
      listingStatus: listingStatus ?? this.listingStatus,
      availableForDates: availableForDates ?? this.availableForDates,
      depositAmount: depositAmount,
      minRentalDays: minRentalDays,
      maxRentalDays: maxRentalDays,
      provider: provider,
      listingId: listingId,
      unitCount: unitCount,
      availableUnits: availableUnits,
      branchName: branchName,
      branchAddress: branchAddress,
      instantBook: instantBook,
    );
  }
}

/// Public search response: `{ "data": [...], "meta": {...} }`.
class CarHireSearchResult {
  const CarHireSearchResult({
    this.data = const <CarListing>[],
    this.page = 1,
    this.limit = 20,
    this.total = 0,
    this.hasMore = false,
  });

  final List<CarListing> data;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;

  factory CarHireSearchResult.fromJson(dynamic raw) {
    final json = raw is Map ? _asMap(raw) : const <String, dynamic>{};
    final listRaw = raw is List
        ? raw
        : (json['data'] ?? json['cars'] ?? json['items']);
    final meta = _asMap(json['meta']);
    final data = _asList(listRaw)
        .whereType<Map>()
        .map((item) => CarListing.fromJson(item))
        .toList(growable: false);

    return CarHireSearchResult(
      data: data,
      page: _asInt(meta['page'] ?? json['page'], fallback: 1),
      limit: _asInt(meta['limit'] ?? json['limit'], fallback: 20),
      total: _asInt(
        meta['total'] ?? json['total'],
        fallback: data.length,
      ),
      hasMore: _asBool(meta['hasMore'] ?? json['hasMore'], fallback: false),
    );
  }
}

// ---------------------------------------------------------------------------
// Quote
// ---------------------------------------------------------------------------

class QuoteLineItem {
  const QuoteLineItem({
    required this.code,
    required this.label,
    this.amount = 0,
  });

  final String code;
  final String label;
  final double amount;

  factory QuoteLineItem.fromJson(dynamic raw) {
    final json = _asMap(raw);
    return QuoteLineItem(
      code: _asString(json['code']),
      label: _asString(json['label'], fallback: _humanizeWire(json['code'])),
      amount: _asDouble(json['amount']),
    );
  }

  static List<QuoteLineItem> listFromJson(dynamic raw) {
    return _asList(raw)
        .whereType<Map>()
        .map((item) => QuoteLineItem.fromJson(item))
        .toList(growable: false);
  }
}

class QuoteDeposit {
  const QuoteDeposit({this.amount = 0, this.collectionMode = 'none'});

  final double amount;
  final String collectionMode;

  factory QuoteDeposit.fromJson(dynamic raw) {
    if (raw is num || raw is String) {
      return QuoteDeposit(amount: _asDouble(raw));
    }
    final json = _asMap(raw);
    return QuoteDeposit(
      amount: _asDouble(json['amount']),
      collectionMode: _asString(json['collectionMode'], fallback: 'none'),
    );
  }

  bool get hasDeposit => amount > 0;

  String get collectionModeLabel {
    final mode = _humanizeWire(collectionMode);
    return mode.isEmpty ? 'Not specified' : mode;
  }
}

class RentalQuote {
  const RentalQuote({
    required this.quoteId,
    required this.carId,
    this.currency = 'MWK',
    this.startAt,
    this.endAt,
    this.expiresAt,
    this.days = 0,
    this.dailyRate = 0,
    this.lineItems = const <QuoteLineItem>[],
    this.subtotal = 0,
    this.surcharges = 0,
    this.discounts = 0,
    this.insurance = 0,
    this.deposit = const QuoteDeposit(),
    this.totalDueNow = 0,
    this.totalDueLater = 0,
    this.total = 0,
    this.status = QuoteStatus.active,
  });

  final String quoteId;
  final int carId;
  final String currency;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? expiresAt;
  final int days;
  final double dailyRate;
  final List<QuoteLineItem> lineItems;
  final double subtotal;
  final double surcharges;
  final double discounts;
  final double insurance;
  final QuoteDeposit deposit;
  final double totalDueNow;
  final double totalDueLater;
  final double total;
  final QuoteStatus status;

  factory RentalQuote.fromJson(dynamic raw) {
    dynamic payload = raw;
    if (raw is Map) {
      final json = _asMap(raw);
      payload = json['data'] ?? json['quote'] ?? json;
    }
    final json = _asMap(payload);
    final expiresAt = _asDate(json['expiresAt']);
    final status = QuoteStatus.fromWire(
      _asStringOrNull(json['status']) ?? 'ACTIVE',
    );

    return RentalQuote(
      quoteId: _asString(json['quoteId'] ?? json['id']),
      carId: _asInt(json['carId']),
      currency: _asString(json['currency'], fallback: 'MWK'),
      startAt: _asDate(json['startAt'] ?? json['startDate']),
      endAt: _asDate(json['endAt'] ?? json['endDate']),
      expiresAt: expiresAt,
      days: _asInt(json['days']),
      dailyRate: _asDouble(json['dailyRate']),
      lineItems: QuoteLineItem.listFromJson(json['lineItems']),
      subtotal: _asDouble(json['subtotal']),
      surcharges: _asDouble(json['surcharges']),
      discounts: _asDouble(json['discounts']),
      insurance: _asDouble(json['insurance']),
      deposit: QuoteDeposit.fromJson(json['deposit']),
      totalDueNow: _asDouble(json['totalDueNow']),
      totalDueLater: _asDouble(json['totalDueLater']),
      total: _asDouble(
        json['total'] ?? json['totalDueNow'] ?? json['subtotal'],
      ),
      status: status,
    );
  }

  bool get isLocallyExpired {
    final expires = expiresAt;
    if (expires == null) return false;
    return !DateTime.now().isBefore(expires);
  }

  bool get isExpired => status == QuoteStatus.expired || isLocallyExpired;

  bool get isActive => status == QuoteStatus.active && !isExpired;

  Duration? get remaining {
    final expires = expiresAt;
    if (expires == null) return null;
    return expires.difference(DateTime.now());
  }

  String get dailyRateLabel =>
      '${CarHireFormatters.formatCurrency(dailyRate)} / day';

  String get totalLabel => CarHireFormatters.formatCurrency(total);

  String get expiryLabel {
    final expires = expiresAt;
    if (expires == null) return 'Expiry not provided';
    return CarHireFormatters.formatDateTime(expires);
  }
}

// ---------------------------------------------------------------------------
// Booking
// ---------------------------------------------------------------------------

class CarHireBooking {
  const CarHireBooking({
    required this.id,
    this.bookingNumber,
    this.carId,
    this.userId,
    this.startAt,
    this.endAt,
    this.bookingStatus = BookingStatus.unknown,
    this.paymentStatus = PaymentStatus.unknown,
    this.currency = 'MWK',
    this.quoteId,
    this.baseCost = 0,
    this.distanceCost = 0,
    this.surcharges = 0,
    this.discounts = 0,
    this.insurance = 0,
    this.total = 0,
    this.renterNotes,
    this.driverName,
    this.holdExpiresAt,
    this.cancellationReason,
    this.cancelledAt,
    this.createdAt,
    this.updatedAt,
    this.nextAction,
    this.paymentReference,
    this.car,
    this.priceBreakdown = const <QuoteLineItem>[],
    this.assignedPlate,
    this.assignedColor,
  });

  final int id;
  final String? bookingNumber;
  final int? carId;
  final int? userId;
  final DateTime? startAt;
  final DateTime? endAt;
  final BookingStatus bookingStatus;
  final PaymentStatus paymentStatus;
  final String currency;
  final String? quoteId;
  final double baseCost;
  final double distanceCost;
  final double surcharges;
  final double discounts;
  final double insurance;

  /// Server-authoritative total. Never calculated on the client.
  final double total;
  final String? renterNotes;
  final String? driverName;
  final DateTime? holdExpiresAt;
  final String? cancellationReason;
  final DateTime? cancelledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? nextAction;
  final String? paymentReference;
  final CarListing? car;
  final List<QuoteLineItem> priceBreakdown;

  /// Registration of the assigned unit; only sent once the booking is confirmed.
  final String? assignedPlate;
  final String? assignedColor;

  factory CarHireBooking.fromJson(dynamic raw) {
    dynamic payload = raw;
    if (raw is Map) {
      final json = _asMap(raw);
      payload = json['data'] ?? json['booking'] ?? json;
    }
    final json = _asMap(payload);
    final carRaw = json['car'] ?? json['vehicle'];
    final breakdownRaw = json['priceBreakdown'];
    final assignedUnit = _asMap(json['assignedUnit']);

    return CarHireBooking(
      id: _asInt(json['id']),
      bookingNumber: _asStringOrNull(json['bookingNumber']),
      carId: _asNullableInt(json['carId']),
      userId: _asNullableInt(json['userId']),
      startAt: _asDate(json['startAt'] ?? json['startDate']),
      endAt: _asDate(json['endAt'] ?? json['endDate']),
      bookingStatus: BookingStatus.fromWire(
        json['bookingStatus'] ?? json['status'],
      ),
      paymentStatus: PaymentStatus.fromWire(
        _asStringOrNull(json['paymentStatus']) ?? 'NOT_STARTED',
      ),
      currency: _asString(json['currency'], fallback: 'MWK'),
      quoteId: _asStringOrNull(json['quoteId']),
      baseCost: _asDouble(json['baseCost']),
      distanceCost: _asDouble(json['distanceCost']),
      surcharges: _asDouble(json['surcharges']),
      discounts: _asDouble(json['discounts']),
      insurance: _asDouble(json['insurance']),
      // Booking responses carry `total` and the legacy `totalCost`.
      total: _asDouble(
        json['total'] ?? json['totalCost'] ?? json['grandTotal'],
      ),
      renterNotes: _asStringOrNull(json['renterNotes'] ?? json['notes']),
      driverName: _asStringOrNull(json['driverName']),
      holdExpiresAt: _asDate(json['holdExpiresAt']),
      cancellationReason: _asStringOrNull(json['cancellationReason']),
      cancelledAt: _asDate(json['cancelledAt']),
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDate(json['updatedAt']),
      nextAction: _asStringOrNull(json['nextAction']),
      paymentReference: _asStringOrNull(json['paymentReference']),
      car: carRaw is Map ? CarListing.fromJson(carRaw) : null,
      priceBreakdown: breakdownRaw is List
          ? QuoteLineItem.listFromJson(breakdownRaw)
          : QuoteLineItem.listFromJson(_asMap(breakdownRaw)['lineItems']),
      assignedPlate: _asStringOrNull(assignedUnit['licensePlate']),
      assignedColor: _asStringOrNull(assignedUnit['color']),
    );
  }

  String get bookingNumberLabel {
    final number = bookingNumber?.trim();
    if (number != null && number.isNotEmpty) return number;
    return id > 0 ? 'Booking #$id' : 'Booking';
  }

  String get totalLabel => CarHireFormatters.formatCurrency(total);

  String get dateRangeLabel {
    final start = startAt;
    final end = endAt;
    if (start == null && end == null) return 'Dates not confirmed';
    if (start == null) return 'Return ${CarHireFormatters.formatDateTime(end!)}';
    if (end == null) return 'Pick-up ${CarHireFormatters.formatDateTime(start)}';
    return '${CarHireFormatters.formatDateTime(start)} → '
        '${CarHireFormatters.formatDateTime(end)}';
  }

  String get paymentLabel {
    switch (paymentStatus) {
      case PaymentStatus.succeeded:
        return 'Payment received';
      case PaymentStatus.notRequired:
        return 'No payment required';
      case PaymentStatus.pending:
        return 'Payment pending confirmation';
      case PaymentStatus.failed:
        return 'Payment failed';
      case PaymentStatus.refunded:
        return 'Payment refunded';
      case PaymentStatus.notStarted:
        return 'Payment not started';
      case PaymentStatus.unknown:
        return 'Payment status unavailable';
    }
  }

  bool get paymentSucceeded => paymentStatus == PaymentStatus.succeeded;

  bool get isHoldExpired {
    final hold = holdExpiresAt;
    if (hold == null) return false;
    return !DateTime.now().isBefore(hold);
  }

  bool get canCancel =>
      bookingStatus == BookingStatus.pending ||
      bookingStatus == BookingStatus.confirmed;

  bool get canPay {
    if (bookingStatus != BookingStatus.pending &&
        bookingStatus != BookingStatus.confirmed) {
      return false;
    }
    if (paymentStatus == PaymentStatus.succeeded ||
        paymentStatus == PaymentStatus.refunded ||
        paymentStatus == PaymentStatus.notRequired) {
      return false;
    }
    // The server-derived hint tells us when payment is no longer the next step.
    final action = _normalizedNextAction;
    if (action == 'PICKUP_DUE' ||
        action == 'OWNER_REVIEW' ||
        action == 'AWAITING_PROVIDER') {
      return false;
    }
    return true;
  }

  String? get _normalizedNextAction => nextAction
      ?.trim()
      .toUpperCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');

  String? get nextActionLabel {
    switch (_normalizedNextAction) {
      case 'PAYMENT_REQUIRED':
        return 'Payment is required to confirm this booking.';
      case 'PAYMENT_PROCESSING':
        return 'Your payment is being confirmed. Refresh in a moment.';
      case 'OWNER_REVIEW':
        return 'Waiting for the vehicle provider to confirm.';
      case 'AWAITING_PROVIDER':
        return 'Request sent. The company responds within 24 hours; '
            'you pay once they accept.';
      case 'PICKUP_DUE':
        return 'Your pick-up is due. Bring your booking number and licence.';
      case 'RETURN_DUE':
        return 'Your return is due. Please return the vehicle on time.';
      default:
        return null;
    }
  }

  String get holdExpiryLabel {
    final hold = holdExpiresAt;
    if (hold == null) return 'Hold expiry not provided';
    return isHoldExpired
        ? 'Hold expired ${CarHireFormatters.formatDateTime(hold)}'
        : 'Hold expires ${CarHireFormatters.formatDateTime(hold)}';
  }

  CarHireBooking copyWith({
    BookingStatus? bookingStatus,
    PaymentStatus? paymentStatus,
    String? nextAction,
    String? cancellationReason,
    DateTime? cancelledAt,
    DateTime? holdExpiresAt,
    String? paymentReference,
    CarListing? car,
  }) {
    return CarHireBooking(
      id: id,
      bookingNumber: bookingNumber,
      carId: carId,
      userId: userId,
      startAt: startAt,
      endAt: endAt,
      bookingStatus: bookingStatus ?? this.bookingStatus,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      currency: currency,
      quoteId: quoteId,
      baseCost: baseCost,
      distanceCost: distanceCost,
      surcharges: surcharges,
      discounts: discounts,
      insurance: insurance,
      total: total,
      renterNotes: renterNotes,
      driverName: driverName,
      holdExpiresAt: holdExpiresAt ?? this.holdExpiresAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      nextAction: nextAction ?? this.nextAction,
      paymentReference: paymentReference ?? this.paymentReference,
      car: car ?? this.car,
      priceBreakdown: priceBreakdown,
      assignedPlate: assignedPlate,
      assignedColor: assignedColor,
    );
  }
}

/// Booking list envelope: `{ "data": [...], "meta": {...} }`.
class BookingPage {
  const BookingPage({
    this.data = const <CarHireBooking>[],
    this.page = 1,
    this.limit = 20,
    this.total = 0,
    this.hasMore = false,
  });

  final List<CarHireBooking> data;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;

  factory BookingPage.fromJson(dynamic raw) {
    final json = raw is Map ? _asMap(raw) : const <String, dynamic>{};
    final listRaw = raw is List
        ? raw
        : (json['data'] ?? json['bookings'] ?? json['items']);
    final meta = _asMap(json['meta']);
    final data = _asList(listRaw)
        .whereType<Map>()
        .map((item) => CarHireBooking.fromJson(item))
        .toList(growable: false);

    return BookingPage(
      data: data,
      page: _asInt(meta['page'] ?? json['page'], fallback: 1),
      limit: _asInt(meta['limit'] ?? json['limit'], fallback: 20),
      total: _asInt(meta['total'] ?? json['total'], fallback: data.length),
      hasMore: _asBool(meta['hasMore'] ?? json['hasMore'], fallback: false),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment initiation + verification
// ---------------------------------------------------------------------------

class PaymentInitiation {
  const PaymentInitiation({
    this.paymentId,
    this.txRef,
    this.checkoutUrl,
    this.status,
    this.booking,
  });

  final int? paymentId;
  final String? txRef;
  final String? checkoutUrl;
  final String? status;
  final CarHireBooking? booking;

  factory PaymentInitiation.fromJson(dynamic raw) {
    dynamic payload = raw;
    if (raw is Map) {
      final json = _asMap(raw);
      payload = json['data'] ?? json['payment'] ?? json;
    }
    final json = _asMap(payload);
    final bookingRaw = json['booking'];

    return PaymentInitiation(
      paymentId: _asNullableInt(json['paymentId']),
      txRef: _asStringOrNull(json['txRef']),
      checkoutUrl: _asStringOrNull(json['checkoutUrl']),
      status: _asStringOrNull(json['status']),
      booking: bookingRaw is Map ? CarHireBooking.fromJson(bookingRaw) : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 4: extensions, handover inspections, incidents, support, verification
// ---------------------------------------------------------------------------

class BookingExtension {
  const BookingExtension({
    required this.id,
    this.bookingId,
    this.requestedEndAt,
    this.previousEndAt,
    this.status = ExtensionStatus.unknown,
    this.additionalAmount = 0,
    this.currency = 'MWK',
    this.decisionReason,
    this.createdAt,
  });

  final int id;
  final int? bookingId;
  final DateTime? requestedEndAt;
  final DateTime? previousEndAt;
  final ExtensionStatus status;

  /// Server-quoted amount for the extension. Never calculated on the client.
  final double additionalAmount;
  final String currency;
  final String? decisionReason;
  final DateTime? createdAt;

  factory BookingExtension.fromJson(dynamic raw) {
    dynamic payload = raw;
    if (raw is Map) {
      final json = _asMap(raw);
      payload = json['data'] ?? json['extension'] ?? json;
    }
    final json = _asMap(payload);

    return BookingExtension(
      id: _asInt(_pick(json, <String>['id', 'extensionId', 'extension_id'])),
      bookingId: _asNullableInt(
        _pick(json, <String>['bookingId', 'booking_id']),
      ),
      requestedEndAt: _asDate(
        _pick(json, <String>[
          'requestedEndAt',
          'requested_end_at',
          'requestedEnd',
          'requested_end',
          'newEndAt',
          'new_end_at',
        ]),
      ),
      previousEndAt: _asDate(
        _pick(json, <String>[
          'previousEndAt',
          'previous_end_at',
          'previousEnd',
          'previous_end',
          'currentEndAt',
          'current_end_at',
        ]),
      ),
      status: ExtensionStatus.fromWire(json['status']),
      additionalAmount: _asDouble(
        _pick(json, <String>[
          'additionalAmount',
          'additional_amount',
          'amount',
          'quotedAmount',
          'quoted_amount',
        ]),
      ),
      currency: _asString(json['currency'], fallback: 'MWK'),
      decisionReason: _asStringOrNull(
        _pick(json, <String>['decisionReason', 'decision_reason', 'reason']),
      ),
      createdAt: _asDate(_pick(json, <String>['createdAt', 'created_at'])),
    );
  }

  static List<BookingExtension> listFromJson(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map
            ? _asList(_asMap(raw)['data'] ?? _asMap(raw)['extensions'])
            : const <dynamic>[]);
    return list
        .whereType<Map>()
        .map((item) => BookingExtension.fromJson(item))
        .toList(growable: false);
  }

  String get requestedEndLabel => requestedEndAt == null
      ? 'Return date not provided'
      : CarHireFormatters.formatDateTime(requestedEndAt!);

  String get additionalAmountLabel =>
      carHireMoney(currency, additionalAmount);

  bool get hasAdditionalAmount => additionalAmount > 0;
}

class InspectionAcknowledgement {
  const InspectionAcknowledgement({
    this.party = '',
    this.decision = '',
    this.note,
    this.createdAt,
  });

  final String party;

  /// `ACCEPTED` or `DECLINED`.
  final String decision;
  final String? note;
  final DateTime? createdAt;

  factory InspectionAcknowledgement.fromJson(dynamic raw) {
    final json = _asMap(raw);
    return InspectionAcknowledgement(
      party: _asString(
        _pick(json, <String>['party', 'actorRole', 'actor_role']),
      ),
      decision: _asString(
        _pick(json, <String>['decision', 'status']),
      ).toUpperCase(),
      note: _asStringOrNull(
        _pick(json, <String>['note', 'reason', 'disputeReason', 'dispute_reason']),
      ),
      createdAt: _asDate(_pick(json, <String>['createdAt', 'created_at'])),
    );
  }

  bool get accepted => decision == 'ACCEPTED';

  String get partyLabel {
    if (party.trim().isEmpty) return 'Party';
    final role = InspectionActorRole.fromWire(party);
    return role == InspectionActorRole.unknown
        ? _humanizeWire(party)
        : role.label;
  }

  String get decisionLabel => accepted ? 'Accepted' : 'Declined';

  String get createdAtLabel =>
      createdAt == null ? '' : CarHireFormatters.formatDateTime(createdAt!);
}

class HandoverInspection {
  const HandoverInspection({
    required this.id,
    this.bookingId,
    this.type = InspectionType.unknown,
    this.actorRole = InspectionActorRole.unknown,
    this.odometer,
    this.fuelLevel,
    this.condition,
    this.checklist = const <String>[],
    this.notes,
    this.media = const <String>[],
    this.status = InspectionStatus.unknown,
    this.acknowledgedAt,
    this.declinedAt,
    this.disputeReason,
    this.createdAt,
    this.acknowledgements = const <InspectionAcknowledgement>[],
  });

  final int id;
  final int? bookingId;
  final InspectionType type;
  final InspectionActorRole actorRole;
  final int? odometer;
  final double? fuelLevel;
  final String? condition;
  final List<String> checklist;
  final String? notes;
  final List<String> media;
  final InspectionStatus status;
  final DateTime? acknowledgedAt;
  final DateTime? declinedAt;
  final String? disputeReason;
  final DateTime? createdAt;
  final List<InspectionAcknowledgement> acknowledgements;

  factory HandoverInspection.fromJson(dynamic raw) {
    dynamic payload = raw;
    if (raw is Map) {
      final json = _asMap(raw);
      payload = json['data'] ?? json['inspection'] ?? json;
    }
    final json = _asMap(payload);

    return HandoverInspection(
      id: _asInt(_pick(json, <String>['id', 'inspectionId', 'inspection_id'])),
      bookingId: _asNullableInt(
        _pick(json, <String>['bookingId', 'booking_id']),
      ),
      type: InspectionType.fromWire(
        _pick(json, <String>['type', 'inspectionType', 'inspection_type']),
      ),
      actorRole: InspectionActorRole.fromWire(
        _pick(json, <String>['actorRole', 'actor_role']),
      ),
      odometer: _asNullableInt(
        _pick(json, <String>['odometer', 'mileage', 'odometerReading']),
      ),
      fuelLevel: _asNullableDouble(
        _pick(json, <String>['fuelLevel', 'fuel_level', 'fuel']),
      ),
      condition: _asStringOrNull(json['condition']),
      checklist: _asChecklist(json['checklist']),
      notes: _asStringOrNull(json['notes']),
      media: _asMedia(json['media']),
      status: InspectionStatus.fromWire(
        _pick(json, <String>['status', 'inspectionStatus', 'inspection_status']),
      ),
      acknowledgedAt: _asDate(
        _pick(json, <String>['acknowledgedAt', 'acknowledged_at']),
      ),
      declinedAt: _asDate(_pick(json, <String>['declinedAt', 'declined_at'])),
      disputeReason: _asStringOrNull(
        _pick(json, <String>[
          'disputeReason',
          'dispute_reason',
          'declineReason',
          'decline_reason',
        ]),
      ),
      createdAt: _asDate(_pick(json, <String>['createdAt', 'created_at'])),
      acknowledgements: _asList(json['acknowledgements'])
          .whereType<Map>()
          .map((item) => InspectionAcknowledgement.fromJson(item))
          .toList(growable: false),
    );
  }

  static List<HandoverInspection> listFromJson(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map
            ? _asList(_asMap(raw)['data'] ?? _asMap(raw)['inspections'])
            : const <dynamic>[]);
    return list
        .whereType<Map>()
        .map((item) => HandoverInspection.fromJson(item))
        .toList(growable: false);
  }

  bool get renterAcknowledged => acknowledgements.any((entry) {
        final party = entry.party.toUpperCase();
        return party == 'RENTER' || party == 'CUSTOMER' || party == 'USER';
      });

  /// The renter may accept or decline a handover recorded by the provider.
  bool get awaitingRenterDecision =>
      actorRole == InspectionActorRole.owner &&
      !renterAcknowledged &&
      status != InspectionStatus.acknowledged &&
      status != InspectionStatus.declined;

  bool get isDisputed =>
      status == InspectionStatus.disputed || disputeReason != null;

  String get typeLabel => type.label;

  String get actorLabel => actorRole.label;

  String get statusLabel => status.label;

  String get conditionLabel {
    final value = condition?.trim();
    if (value == null || value.isEmpty) return 'Not recorded';
    return _humanizeWire(value);
  }

  String get odometerLabel {
    final value = odometer;
    return value == null ? 'Not recorded' : '${formatMwkInput(value)} km';
  }

  String get fuelLevelLabel {
    final value = fuelLevel;
    return value == null ? 'Not recorded' : '${value.toStringAsFixed(0)}%';
  }

  String get checklistLabel {
    if (checklist.isEmpty) return 'None recorded';
    return checklist.map(_humanizeWire).join(', ');
  }

  String get mediaLabel {
    if (media.isEmpty) return 'None';
    return media.join(', ');
  }

  String get createdAtLabel => createdAt == null
      ? 'Time not provided'
      : CarHireFormatters.formatDateTime(createdAt!);

  String get summaryLabel {
    final buffer = StringBuffer(status.label);
    if (acknowledgedAt != null) {
      buffer.write(' · acknowledged');
    }
    if (declinedAt != null || isDisputed) {
      buffer.write(' · disputed');
    }
    return buffer.toString();
  }
}

class IncidentReport {
  const IncidentReport({
    required this.id,
    this.bookingId,
    this.type = IncidentType.unknown,
    this.description = '',
    this.occurredAt,
    this.contactPhone,
    this.status = '',
    this.createdAt,
  });

  final int id;
  final int? bookingId;
  final IncidentType type;
  final String description;
  final DateTime? occurredAt;
  final String? contactPhone;
  final String status;
  final DateTime? createdAt;

  factory IncidentReport.fromJson(dynamic raw) {
    dynamic payload = raw;
    if (raw is Map) {
      final json = _asMap(raw);
      payload = json['data'] ?? json['incident'] ?? json;
    }
    final json = _asMap(payload);

    return IncidentReport(
      id: _asInt(_pick(json, <String>['id', 'incidentId', 'incident_id'])),
      bookingId: _asNullableInt(
        _pick(json, <String>['bookingId', 'booking_id']),
      ),
      type: IncidentType.fromWire(
        _pick(json, <String>['type', 'incidentType', 'incident_type']),
      ),
      description: _asString(json['description']),
      occurredAt: _asDate(
        _pick(json, <String>['occurredAt', 'occurred_at', 'happenedAt', 'happened_at']),
      ),
      contactPhone: _asStringOrNull(
        _pick(json, <String>['contactPhone', 'contact_phone']),
      ),
      status: _asString(json['status']),
      createdAt: _asDate(_pick(json, <String>['createdAt', 'created_at'])),
    );
  }

  static List<IncidentReport> listFromJson(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map
            ? _asList(_asMap(raw)['data'] ?? _asMap(raw)['incidents'])
            : const <dynamic>[]);
    return list
        .whereType<Map>()
        .map((item) => IncidentReport.fromJson(item))
        .toList(growable: false);
  }

  String get typeLabel => type.label;

  String get statusLabel {
    final value = _humanizeWire(status);
    return value.isEmpty ? 'Reported' : value;
  }

  String get occurredAtLabel => occurredAt == null
      ? 'Time not provided'
      : CarHireFormatters.formatDateTime(occurredAt!);
}

class SupportCase {
  const SupportCase({
    required this.id,
    this.bookingId,
    this.category = SupportCaseCategory.unknown,
    this.subject = '',
    this.message = '',
    this.status = '',
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int? bookingId;
  final SupportCaseCategory category;
  final String subject;
  final String message;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SupportCase.fromJson(dynamic raw) {
    dynamic payload = raw;
    if (raw is Map) {
      final json = _asMap(raw);
      payload = json['data'] ?? json['case'] ?? json['supportCase'] ?? json;
    }
    final json = _asMap(payload);

    return SupportCase(
      id: _asInt(_pick(json, <String>['id', 'caseId', 'case_id'])),
      bookingId: _asNullableInt(
        _pick(json, <String>['bookingId', 'booking_id']),
      ),
      category: SupportCaseCategory.fromWire(
        _pick(json, <String>['category', 'type']),
      ),
      subject: _asString(json['subject']),
      message: _asString(_pick(json, <String>['message', 'description'])),
      status: _asString(json['status']),
      createdAt: _asDate(_pick(json, <String>['createdAt', 'created_at'])),
      updatedAt: _asDate(_pick(json, <String>['updatedAt', 'updated_at'])),
    );
  }

  static List<SupportCase> listFromJson(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map
            ? _asList(_asMap(raw)['data'] ?? _asMap(raw)['cases'])
            : const <dynamic>[]);
    return list
        .whereType<Map>()
        .map((item) => SupportCase.fromJson(item))
        .toList(growable: false);
  }

  String get categoryLabel => category.label;

  String get statusLabel {
    final value = _humanizeWire(status);
    return value.isEmpty ? 'Submitted' : value;
  }

  String get createdAtLabel => createdAt == null
      ? ''
      : CarHireFormatters.formatDateTime(createdAt!);
}

/// One row of the `POST /verification/submissions` payload.
class VerificationEvidence {
  const VerificationEvidence({
    required this.requirement,
    required this.fileReference,
    this.expiresAt,
  });

  final String requirement;
  final String fileReference;
  final DateTime? expiresAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'requirement': requirement,
      'fileReference': fileReference,
      if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    };
  }
}

class CarHireVerification {
  const CarHireVerification({
    this.status = VerificationState.unknown,
    this.requirements = const <String>[],
    this.nextAction,
  });

  final VerificationState status;
  final List<String> requirements;
  final String? nextAction;

  factory CarHireVerification.fromJson(dynamic raw) {
    final json = raw is Map ? _asMap(raw) : const <String, dynamic>{};
    final requirements = _asList(json['requirements'])
        .map((item) {
          if (item is Map) {
            final map = _asMap(item);
            return _asString(
              map['label'] ?? map['name'] ?? map['code'] ?? map['type'],
            );
          }
          return _asString(item);
        })
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    return CarHireVerification(
      status: VerificationState.fromWire(
        _asStringOrNull(json['status']) ?? 'NOT_STARTED',
      ),
      requirements: requirements,
      nextAction: _asStringOrNull(
        _pick(json, <String>['nextAction', 'next_action']),
      ),
    );
  }

  bool get needsAttention => status.needsAttention;

  String get statusLabel => status.label;
}
