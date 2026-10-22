import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';

/// Parsing helpers kept local so the section models stay tolerant of the
/// older payloads the backend shipped before the browse envelope.
Map<String, dynamic> _map(dynamic raw) {
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

String _str(dynamic value) => value == null ? '' : value.toString().trim();

String? _strOrNull(dynamic value) {
  final text = _str(value);
  return text.isEmpty ? null : text;
}

int _int(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(_str(value)) ?? fallback;
}

double _double(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(_str(value)) ?? fallback;
}

bool? _boolOrNull(dynamic value) {
  if (value is bool) return value;
  final text = _str(value).toLowerCase();
  if (text == 'true') return true;
  if (text == 'false') return false;
  return null;
}

// ---------------------------------------------------------------------------
// Section envelope
// ---------------------------------------------------------------------------

enum CarHireSectionStatus { ok, unavailable }

/// One independently degrading part of a car-hire page.
///
/// A section keeps whatever data the server sent. When the server could not
/// resolve it, the section is [CarHireSectionStatus.unavailable] and the UI
/// renders its own retry affordance instead of failing the whole screen.
class CarHireSection<T> {
  const CarHireSection({
    required this.status,
    this.data,
    this.retryable = true,
    this.message,
  });

  const CarHireSection.ok(T value)
    : status = CarHireSectionStatus.ok,
      data = value,
      retryable = false,
      message = null;

  const CarHireSection.unavailable({this.retryable = true, this.message})
    : status = CarHireSectionStatus.unavailable,
      data = null;

  final CarHireSectionStatus status;
  final T? data;
  final bool retryable;

  /// Short, user-safe reason. Never raw backend text.
  final String? message;

  bool get isOk => status == CarHireSectionStatus.ok && data != null;
  bool get isUnavailable => !isOk;

  /// Parses `{ status, data, error }`. A malformed payload degrades to an
  /// unavailable section rather than throwing while building the page.
  static CarHireSection<T> fromJson<T>(
    dynamic raw,
    T Function(dynamic data) parse,
  ) {
    final json = _map(raw);
    final status = _str(json['status']).toLowerCase();
    if (status != 'ok') {
      final error = _map(json['error']);
      return CarHireSection<T>.unavailable(
        retryable: error['retryable'] != false,
        message: _strOrNull(error['message']),
      );
    }
    try {
      return CarHireSection<T>.ok(parse(json['data']));
    } catch (_) {
      return CarHireSection<T>.unavailable();
    }
  }

  /// Local outcome for a call the client made itself (old-backend fallback or
  /// a per-section retry).
  static CarHireSection<T> failed<T>({String? message, bool retryable = true}) {
    return CarHireSection<T>.unavailable(
      retryable: retryable,
      message: message,
    );
  }
}

// ---------------------------------------------------------------------------
// Facets
// ---------------------------------------------------------------------------

class CarHirePriceFacet {
  const CarHirePriceFacet({
    this.min = 0,
    this.median = 0,
    this.max = 0,
  });

  static const empty = CarHirePriceFacet();

  final double min;
  final double median;
  final double max;

  bool get isEmpty => max <= 0;

  factory CarHirePriceFacet.fromJson(dynamic raw) {
    final json = _map(raw);
    return CarHirePriceFacet(
      min: _double(json['min']),
      median: _double(json['median']),
      max: _double(json['max']),
    );
  }
}

class CarHireCategoryCounts {
  const CarHireCategoryCounts({
    this.all = 0,
    this.suv = 0,
    this.luxury = 0,
    this.budget = 0,
    this.sevenSeater = 0,
  });

  static const empty = CarHireCategoryCounts();

  final int all;
  final int suv;
  final int luxury;
  final int budget;
  final int sevenSeater;

  factory CarHireCategoryCounts.fromJson(dynamic raw) {
    final json = _map(raw);
    return CarHireCategoryCounts(
      all: _int(json['all']),
      suv: _int(json['suv']),
      luxury: _int(json['luxury']),
      budget: _int(json['budget']),
      sevenSeater: _int(json['sevenSeater']),
    );
  }
}

/// Chip counts and price spread for the browse filters.
class CarHireFacets {
  const CarHireFacets({
    this.total = 0,
    this.instantCount = 0,
    this.price = CarHirePriceFacet.empty,
    this.categories = CarHireCategoryCounts.empty,
  });

  static const empty = CarHireFacets();

  final int total;
  final int instantCount;
  final CarHirePriceFacet price;
  final CarHireCategoryCounts categories;

  factory CarHireFacets.fromJson(dynamic raw) {
    final json = _map(raw);
    return CarHireFacets(
      total: _int(json['total']),
      instantCount: _int(json['instantCount']),
      price: CarHirePriceFacet.fromJson(json['price']),
      categories: CarHireCategoryCounts.fromJson(json['categories']),
    );
  }
}

// ---------------------------------------------------------------------------
// Date availability
// ---------------------------------------------------------------------------

/// Result of the standalone availability check used by the detail page.
class CarHireAvailability {
  const CarHireAvailability({
    this.carId = 0,
    this.availableForDates,
    this.availableUnits = 0,
    this.unitCount = 0,
    this.startAt,
    this.endAt,
  });

  final int carId;
  final bool? availableForDates;
  final int availableUnits;
  final int unitCount;
  final DateTime? startAt;
  final DateTime? endAt;

  bool get hasDates => startAt != null && endAt != null;

  /// True only when the server confirmed a free unit for the dates.
  bool get isAvailableForDates => availableForDates == true;

  factory CarHireAvailability.fromJson(dynamic raw) {
    final json = _map(raw);
    return CarHireAvailability(
      carId: _int(json['carId'] ?? json['id']),
      availableForDates: _boolOrNull(json['availableForDates']),
      availableUnits: _int(json['availableUnits']),
      unitCount: _int(json['unitCount']),
      startAt: DateTime.tryParse(_str(json['startAt'])),
      endAt: DateTime.tryParse(_str(json['endAt'])),
    );
  }
}

/// Identity of one availability check, used as a provider family key.
class CarHireAvailabilityRequest {
  const CarHireAvailabilityRequest({
    required this.carId,
    required this.startAt,
    required this.endAt,
  });

  final int carId;
  final DateTime startAt;
  final DateTime endAt;

  @override
  bool operator ==(Object other) {
    return other is CarHireAvailabilityRequest &&
        other.carId == carId &&
        other.startAt == startAt &&
        other.endAt == endAt;
  }

  @override
  int get hashCode => Object.hash(carId, startAt, endAt);
}

// ---------------------------------------------------------------------------
// Browse snapshot
// ---------------------------------------------------------------------------

/// The three independently resolved sections of the browse page.
class CarHireBrowseSnapshot {
  const CarHireBrowseSnapshot({
    required this.companies,
    required this.facets,
    required this.results,
    this.degraded = false,
  });

  final CarHireSection<List<CarHireCompanyOption>> companies;
  final CarHireSection<CarHireFacets> facets;
  final CarHireSection<CarHireSearchResult> results;
  final bool degraded;

  factory CarHireBrowseSnapshot.fromJson(dynamic raw) {
    final json = _map(raw);
    final sections = _map(json['sections']);
    final meta = _map(json['meta']);
    return CarHireBrowseSnapshot(
      companies: CarHireSection.fromJson<List<CarHireCompanyOption>>(
        sections['companies'],
        (data) {
          if (data is! List) return const <CarHireCompanyOption>[];
          return data
              .map(CarHireCompanyOption.fromJson)
              .whereType<CarHireCompanyOption>()
              .toList(growable: false);
        },
      ),
      facets: CarHireSection.fromJson<CarHireFacets>(
        sections['facets'],
        CarHireFacets.fromJson,
      ),
      results: CarHireSection.fromJson<CarHireSearchResult>(
        sections['results'],
        CarHireSearchResult.fromJson,
      ),
      degraded: meta['degraded'] == true,
    );
  }
}
