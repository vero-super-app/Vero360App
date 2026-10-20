import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

// ---------------------------------------------------------------------------
// Typed errors
// ---------------------------------------------------------------------------

enum CarHireErrorKind {
  validation,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  gone,
  rateLimited,
  server,
  network,
  timeout,
  unknown,
}

/// A car-hire API failure with a message that is safe to show to a renter.
class CarHireApiException implements Exception {
  const CarHireApiException({
    required this.message,
    this.statusCode,
    this.kind = CarHireErrorKind.unknown,
    this.backendMessage,
  });

  final String message;
  final int? statusCode;
  final CarHireErrorKind kind;

  /// Raw backend text for diagnostics only. Never render directly.
  final String? backendMessage;

  bool get requiresLogin => statusCode == 401;

  bool get isNotFound =>
      statusCode == 404 || kind == CarHireErrorKind.notFound;

  /// A 410 from the quote/booking flow means the offer expired.
  bool get isQuoteExpired => statusCode == 410;

  /// A 409 from quote/booking creation means an availability conflict.
  bool get isConflict =>
      statusCode == 409 || kind == CarHireErrorKind.conflict;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// API client
// ---------------------------------------------------------------------------

class CarHireApi {
  static const Duration _timeout = Duration(seconds: 30);
  static const String _carsPath = '/car-rental/cars';
  static const String _quotesPath = '/car-rental/quotes';
  static const String _bookingsPath = '/car-rental/bookings';
  static const String _verificationPath = '/car-rental/verification/me';
  static const String _verificationRequirementsPath =
      '/car-rental/verification/requirements';
  static const String _verificationSubmissionsPath =
      '/car-rental/verification/submissions';

  // -------------------------------------------------------------------------
  // Public inventory
  // -------------------------------------------------------------------------

  /// `GET /car-rental/cars`
  Future<CarHireSearchResult> searchCars({
    String? pickupArea,
    DateTime? startAt,
    DateTime? endAt,
    int? minSeats,
    String? transmission,
    String? fuelType,
    String? bodyType,
    int? page,
    int? limit,
    String? sort,
  }) async {
    final query = <String, String>{};
    final area = pickupArea?.trim();
    if (area != null && area.isNotEmpty) query['pickupArea'] = area;
    if (startAt != null) query['startAt'] = _iso(startAt);
    if (endAt != null) query['endAt'] = _iso(endAt);
    if (minSeats != null && minSeats > 0) query['minSeats'] = '$minSeats';
    if (transmission != null && transmission.trim().isNotEmpty) {
      query['transmission'] = transmission.trim();
    }
    if (fuelType != null && fuelType.trim().isNotEmpty) {
      query['fuelType'] = fuelType.trim();
    }
    if (bodyType != null && bodyType.trim().isNotEmpty) {
      query['bodyType'] = bodyType.trim();
    }
    if (page != null && page > 0) query['page'] = '$page';
    if (limit != null && limit > 0) query['limit'] = '$limit';
    if (sort != null && sort.trim().isNotEmpty) query['sort'] = sort.trim();

    final response = await _send(
      () => ApiClient.get(
        _carsPath,
        queryParameters: query.isEmpty ? null : query,
        timeout: _timeout,
      ),
    );
    return CarHireSearchResult.fromJson(_decode(response));
  }

  /// `GET /car-rental/cars/:id`
  Future<CarListing> getCar(int id) async {
    final response = await _send(
      () => ApiClient.get('$_carsPath/$id', timeout: _timeout),
    );
    final decoded = _decode(response);
    if (decoded is! Map) {
      throw const CarHireApiException(
        message: 'We could not load this vehicle. Please try again.',
        kind: CarHireErrorKind.server,
      );
    }
    final payload = _unwrapMap(
      decoded,
      const <String>['data', 'car'],
    );
    if (payload.isEmpty) {
      throw const CarHireApiException(
        message: 'We could not load this vehicle. Please try again.',
        kind: CarHireErrorKind.server,
      );
    }
    return CarListing.fromJson(payload);
  }

  // -------------------------------------------------------------------------
  // Quotes
  // -------------------------------------------------------------------------

  /// `POST /car-rental/quotes`
  Future<RentalQuote> createQuote({
    required int carId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final response = await _send(
      () => ApiClient.post(
        _quotesPath,
        body: jsonEncode(<String, dynamic>{
          'carId': carId,
          'startAt': _iso(startAt),
          'endAt': _iso(endAt),
        }),
        timeout: _timeout,
      ),
    );
    final decoded = _decode(response);
    if (decoded is! Map) {
      throw const CarHireApiException(
        message: 'We could not prepare a price for these dates. '
            'Please try again.',
        kind: CarHireErrorKind.server,
      );
    }
    return RentalQuote.fromJson(decoded);
  }

  // -------------------------------------------------------------------------
  // Bookings
  // -------------------------------------------------------------------------

  /// `POST /car-rental/bookings`
  ///
  /// Preferred body: `{ quoteId, renterNotes, driverName }`.
  /// Legacy fallback: `{ carId, startDate, endDate, notes }`.
  Future<CarHireBooking> createBooking({
    String? quoteId,
    int? carId,
    DateTime? startDate,
    DateTime? endDate,
    String? renterNotes,
    String? driverName,
    String? idempotencyKey,
  }) async {
    final body = <String, dynamic>{};
    if (quoteId != null && quoteId.trim().isNotEmpty) {
      body['quoteId'] = quoteId.trim();
      if (renterNotes != null && renterNotes.trim().isNotEmpty) {
        body['renterNotes'] = renterNotes.trim();
      }
      if (driverName != null && driverName.trim().isNotEmpty) {
        body['driverName'] = driverName.trim();
      }
    } else {
      if (carId == null || startDate == null || endDate == null) {
        throw const CarHireApiException(
          message: 'Choose your dates before creating a booking.',
          kind: CarHireErrorKind.validation,
        );
      }
      body.addAll(<String, dynamic>{
        'carId': carId,
        'startDate': _iso(startDate),
        'endDate': _iso(endDate),
        if (renterNotes != null && renterNotes.trim().isNotEmpty)
          'notes': renterNotes.trim(),
      });
    }

    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : const Uuid().v4();

    final response = await _send(
      () => ApiClient.post(
        _bookingsPath,
        headers: <String, String>{'Idempotency-Key': key},
        body: jsonEncode(body),
        timeout: _timeout,
      ),
    );
    final decoded = _decode(response);
    if (decoded is! Map) {
      throw const CarHireApiException(
        message: 'We could not confirm your booking. Please try again.',
        kind: CarHireErrorKind.server,
      );
    }
    return CarHireBooking.fromJson(decoded);
  }

  /// `GET /car-rental/bookings/mine` with a legacy `/my-bookings` fallback.
  Future<BookingPage> getMyBookings() async {
    try {
      final response = await _send(
        () => ApiClient.get('$_bookingsPath/mine', timeout: _timeout),
      );
      return BookingPage.fromJson(_decode(response));
    } on CarHireApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      final response = await _send(
        () => ApiClient.get(
          '$_bookingsPath/my-bookings',
          timeout: _timeout,
        ),
      );
      return BookingPage.fromJson(_decode(response));
    }
  }

  /// `GET /car-rental/bookings/:id`
  Future<CarHireBooking> getBooking(int id) async {
    final response = await _send(
      () => ApiClient.get('$_bookingsPath/$id', timeout: _timeout),
    );
    final decoded = _decode(response);
    if (decoded is! Map) {
      throw const CarHireApiException(
        message: 'We could not load this booking. Please try again.',
        kind: CarHireErrorKind.server,
      );
    }
    final payload = _unwrapMap(
      decoded,
      const <String>['data', 'booking'],
    );
    if (payload.isEmpty) {
      throw const CarHireApiException(
        message: 'We could not load this booking. Please try again.',
        kind: CarHireErrorKind.server,
      );
    }
    return CarHireBooking.fromJson(payload);
  }

  /// `POST /car-rental/bookings/:id/cancel`
  Future<CarHireBooking> cancelBooking(int id) async {
    final response = await _send(
      () => ApiClient.post(
        '$_bookingsPath/$id/cancel',
        body: jsonEncode(<String, dynamic>{}),
        timeout: _timeout,
      ),
    );
    final decoded = _decode(response);
    if (decoded is Map) {
      final payload = _unwrapMap(
        decoded,
        const <String>['data', 'booking'],
      );
      if (payload.isNotEmpty && payload['id'] != null) {
        return CarHireBooking.fromJson(payload);
      }
    }
    // Soft-cancel responses are not guaranteed to return the full view.
    // Refresh from the backend rather than inventing a local state.
    return getBooking(id);
  }

  /// `POST /car-rental/bookings/:id/payment`
  Future<PaymentInitiation> initiatePayment(
    int bookingId, {
    String? phoneNumber,
  }) async {
    final body = <String, dynamic>{};
    final phone = phoneNumber?.trim();
    if (phone != null && phone.isNotEmpty) {
      body['phoneNumber'] = phone;
    }

    final response = await _send(
      () => ApiClient.post(
        '$_bookingsPath/$bookingId/payment',
        body: jsonEncode(body),
        timeout: _timeout,
      ),
    );
    final decoded = _decode(response);
    if (decoded is! Map) {
      throw const CarHireApiException(
        message: 'We could not start the payment. Please try again.',
        kind: CarHireErrorKind.server,
      );
    }
    return PaymentInitiation.fromJson(decoded);
  }

  // -------------------------------------------------------------------------
  // Verification
  // -------------------------------------------------------------------------

  /// `GET /car-rental/verification/me`
  Future<CarHireVerification> getVerificationStatus() async {
    final response = await _send(
      () => ApiClient.get(_verificationPath, timeout: _timeout),
    );
    final decoded = _decode(response);
    if (decoded is! Map) {
      return const CarHireVerification();
    }
    final payload = _unwrapMap(
      decoded,
      const <String>['data', 'verification'],
    );
    return CarHireVerification.fromJson(payload);
  }

  // -------------------------------------------------------------------------
  // Extensions
  // -------------------------------------------------------------------------

  /// `POST /car-rental/bookings/:id/extensions`
  Future<BookingExtension> requestExtension(
    int bookingId, {
    required DateTime requestedEndAt,
  }) async {
    final response = await _send(
      () => ApiClient.post(
        '$_bookingsPath/$bookingId/extensions',
        body: jsonEncode(<String, dynamic>{
          'requestedEndAt': _iso(requestedEndAt),
        }),
        timeout: _timeout,
      ),
    );
    final payload = _mapFrom(
      _decode(response),
      const <String>['data', 'extension'],
    );
    final extension = BookingExtension.fromJson(payload);
    if (extension.id.isEmpty) {
      throw const CarHireApiException(
        message: 'We could not confirm the extension request. '
            'Refresh the booking and try again.',
        kind: CarHireErrorKind.server,
      );
    }
    return extension;
  }

  /// `GET /car-rental/bookings/:id/extensions`
  Future<List<BookingExtension>> getExtensions(int bookingId) async {
    final response = await _send(
      () => ApiClient.get(
        '$_bookingsPath/$bookingId/extensions',
        timeout: _timeout,
      ),
    );
    final list = _listFrom(
      _decode(response),
      const <String>['data', 'extensions'],
    );
    return list
        .whereType<Map>()
        .map((item) => BookingExtension.fromJson(item))
        .toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // Handover inspections
  // -------------------------------------------------------------------------

  /// `POST /car-rental/bookings/:id/inspections/pickup|return`
  Future<HandoverInspection> submitInspection(
    int bookingId, {
    required String type,
    int? odometer,
    double? fuelLevel,
    String? condition,
    List<String>? checklist,
    String? notes,
    List<String>? media,
  }) async {
    final normalized = type.trim().toLowerCase();
    if (normalized != 'pickup' && normalized != 'return') {
      throw const CarHireApiException(
        message: 'Choose whether this is the pick-up or return inspection.',
        kind: CarHireErrorKind.validation,
      );
    }

    final body = <String, dynamic>{};
    if (odometer != null) body['odometer'] = odometer;
    if (fuelLevel != null) body['fuelLevel'] = fuelLevel;
    if (condition != null && condition.trim().isNotEmpty) {
      body['condition'] = condition.trim();
    }
    if (checklist != null && checklist.isNotEmpty) {
      body['checklist'] = checklist;
    }
    if (notes != null && notes.trim().isNotEmpty) {
      body['notes'] = notes.trim();
    }
    if (media != null && media.isNotEmpty) {
      body['media'] = media;
    }

    final response = await _send(
      () => ApiClient.post(
        '$_bookingsPath/$bookingId/inspections/$normalized',
        body: jsonEncode(body),
        timeout: _timeout,
      ),
    );
    final payload = _mapFrom(
      _decode(response),
      const <String>['data', 'inspection'],
    );
    final inspection = HandoverInspection.fromJson(payload);
    if (inspection.id.isEmpty) {
      throw const CarHireApiException(
        message: 'We could not confirm the inspection. '
            'Refresh the booking and try again.',
        kind: CarHireErrorKind.server,
      );
    }
    return inspection;
  }

  /// `GET /car-rental/bookings/:id/inspections`
  Future<List<HandoverInspection>> getInspections(int bookingId) async {
    final response = await _send(
      () => ApiClient.get(
        '$_bookingsPath/$bookingId/inspections',
        timeout: _timeout,
      ),
    );
    final list = _listFrom(
      _decode(response),
      const <String>['data', 'inspections'],
    );
    return list
        .whereType<Map>()
        .map((item) => HandoverInspection.fromJson(item))
        .toList(growable: false);
  }

  /// `POST /car-rental/bookings/:id/inspections/:inspectionId/acknowledge`
  Future<HandoverInspection> acknowledgeInspection(
    int bookingId, {
    required String inspectionId,
    required String decision,
    String? note,
  }) async {
    final normalized = decision.trim().toUpperCase();
    if (normalized != 'ACCEPTED' && normalized != 'DECLINED') {
      throw const CarHireApiException(
        message: 'Choose whether to accept or decline the inspection.',
        kind: CarHireErrorKind.validation,
      );
    }

    final body = <String, dynamic>{'decision': normalized};
    if (note != null && note.trim().isNotEmpty) {
      body['note'] = note.trim();
    }

    final response = await _send(
      () => ApiClient.post(
        '$_bookingsPath/$bookingId/inspections/$inspectionId/acknowledge',
        body: jsonEncode(body),
        timeout: _timeout,
      ),
    );
    final decoded = _decode(response);
    final payload = _mapFrom(
      decoded,
      const <String>['data', 'inspection'],
    );
    if (payload['id'] != null) {
      return HandoverInspection.fromJson(payload);
    }

    // Some acknowledgements return an empty body. Refresh rather than
    // inventing a local status.
    final inspections = await getInspections(bookingId);
    for (final inspection in inspections) {
      if (inspection.id == inspectionId) return inspection;
    }
    throw const CarHireApiException(
      message: 'The decision was sent, but we could not reload the '
          'inspection. Refresh the booking.',
      kind: CarHireErrorKind.server,
    );
  }

  // -------------------------------------------------------------------------
  // Incidents + support cases
  // -------------------------------------------------------------------------

  /// `POST /car-rental/bookings/:id/incidents`
  Future<IncidentReport> reportIncident(
    int bookingId, {
    required String type,
    required String description,
    DateTime? occurredAt,
    String? contactPhone,
  }) async {
    final body = <String, dynamic>{
      'type': type.trim().toUpperCase(),
      'description': description.trim(),
    };
    if (occurredAt != null) body['occurredAt'] = _iso(occurredAt);
    final phone = contactPhone?.trim();
    if (phone != null && phone.isNotEmpty) body['contactPhone'] = phone;

    final response = await _send(
      () => ApiClient.post(
        '$_bookingsPath/$bookingId/incidents',
        body: jsonEncode(body),
        timeout: _timeout,
      ),
    );
    final payload = _mapFrom(
      _decode(response),
      const <String>['data', 'incident'],
    );
    final incident = IncidentReport.fromJson(payload);
    if (incident.id.isEmpty) {
      throw const CarHireApiException(
        message: 'We could not confirm the incident report. '
            'Please try again.',
        kind: CarHireErrorKind.server,
      );
    }
    return incident;
  }

  /// `GET /car-rental/bookings/:id/incidents`
  Future<List<IncidentReport>> getIncidents(int bookingId) async {
    final response = await _send(
      () => ApiClient.get(
        '$_bookingsPath/$bookingId/incidents',
        timeout: _timeout,
      ),
    );
    final list = _listFrom(
      _decode(response),
      const <String>['data', 'incidents'],
    );
    return list
        .whereType<Map>()
        .map((item) => IncidentReport.fromJson(item))
        .toList(growable: false);
  }

  /// `POST /car-rental/bookings/:id/support-cases`
  Future<SupportCase> openSupportCase(
    int bookingId, {
    required String category,
    required String subject,
    required String message,
  }) async {
    final response = await _send(
      () => ApiClient.post(
        '$_bookingsPath/$bookingId/support-cases',
        body: jsonEncode(<String, dynamic>{
          'category': category.trim().toUpperCase(),
          'subject': subject.trim(),
          'message': message.trim(),
        }),
        timeout: _timeout,
      ),
    );
    final payload = _mapFrom(
      _decode(response),
      const <String>['data', 'case', 'supportCase'],
    );
    final supportCase = SupportCase.fromJson(payload);
    if (supportCase.id.isEmpty) {
      throw const CarHireApiException(
        message: 'We could not open the support case. Please try again.',
        kind: CarHireErrorKind.server,
      );
    }
    return supportCase;
  }

  /// `GET /car-rental/bookings/:id/support-cases`
  Future<List<SupportCase>> getSupportCases(int bookingId) async {
    final response = await _send(
      () => ApiClient.get(
        '$_bookingsPath/$bookingId/support-cases',
        timeout: _timeout,
      ),
    );
    final list = _listFrom(
      _decode(response),
      const <String>['data', 'cases'],
    );
    return list
        .whereType<Map>()
        .map((item) => SupportCase.fromJson(item))
        .toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // Verification submissions
  // -------------------------------------------------------------------------

  /// `GET /car-rental/verification/requirements`
  Future<CarHireVerification> getVerificationRequirements() async {
    final response = await _send(
      () => ApiClient.get(_verificationRequirementsPath, timeout: _timeout),
    );
    final decoded = _decode(response);
    if (decoded is! Map) return const CarHireVerification();
    return CarHireVerification.fromJson(
      _unwrapMap(
        decoded,
        const <String>['data', 'verification'],
      ),
    );
  }

  /// `POST /car-rental/verification/submissions`
  Future<CarHireVerification> submitVerification(
    List<VerificationEvidence> evidence,
  ) async {
    final usable = evidence
        .where((item) => item.fileReference.trim().isNotEmpty)
        .toList(growable: false);
    if (usable.isEmpty) {
      throw const CarHireApiException(
        message: 'Enter at least one document reference before submitting.',
        kind: CarHireErrorKind.validation,
      );
    }

    final response = await _send(
      () => ApiClient.post(
        _verificationSubmissionsPath,
        body: jsonEncode(<String, dynamic>{
          'evidence': usable.map((item) => item.toJson()).toList(),
        }),
        timeout: _timeout,
      ),
    );

    final decoded = _decode(response);
    if (decoded is Map) {
      final payload = _unwrapMap(
        decoded,
        const <String>['data', 'verification'],
      );
      if (payload['status'] != null || payload['requirements'] != null) {
        return CarHireVerification.fromJson(payload);
      }
    }
    // The submission endpoint is not required to return the full view.
    return getVerificationRequirements();
  }

  // -------------------------------------------------------------------------
  // Company mode (providing company staff)
  // -------------------------------------------------------------------------

  /// `GET /car-rental/operators/mine`
  Future<List<CompanyMembership>> getMyCompanies() async {
    final response = await _send(
      () => ApiClient.get('/car-rental/operators/mine', timeout: _timeout),
    );
    return CompanyMembership.listFromJson(_decode(response));
  }

  /// `GET /car-rental/owner/dispatch?date=YYYY-MM-DD`
  Future<DispatchBoard> getDispatchBoard({String? date}) async {
    final response = await _send(
      () => ApiClient.get(
        '/car-rental/owner/dispatch',
        queryParameters: date == null ? null : <String, String>{'date': date},
        timeout: _timeout,
      ),
    );
    return DispatchBoard.fromJson(_decode(response));
  }

  /// `GET /car-rental/owner/bookings`
  Future<List<CarHireBooking>> getCompanyBookings({String? status}) async {
    final response = await _send(
      () => ApiClient.get(
        '/car-rental/owner/bookings',
        queryParameters: <String, String>{
          'limit': '100',
          if (status != null && status.isNotEmpty) 'status': status,
        },
        timeout: _timeout,
      ),
    );
    return BookingPage.fromJson(_decode(response)).data;
  }

  /// `POST /car-rental/bookings/:id/confirm` (also accepts a request).
  Future<void> confirmBooking(int bookingId) async {
    await _send(
      () => ApiClient.post(
        '$_bookingsPath/$bookingId/confirm',
        body: jsonEncode(<String, dynamic>{}),
        timeout: _timeout,
      ),
    );
  }

  /// `POST /car-rental/bookings/:id/reject`
  Future<void> rejectBooking(int bookingId, {String? reason}) async {
    final trimmed = reason?.trim() ?? '';
    await _send(
      () => ApiClient.post(
        '$_bookingsPath/$bookingId/reject',
        body: jsonEncode(<String, dynamic>{
          if (trimmed.isNotEmpty) 'reason': trimmed,
        }),
        timeout: _timeout,
      ),
    );
  }

  /// `POST /car-rental/bookings/:id/start|complete`
  Future<void> setRentalStage(int bookingId, {required bool start}) async {
    await _send(
      () => ApiClient.post(
        '$_bookingsPath/$bookingId/${start ? 'start' : 'complete'}',
        body: jsonEncode(<String, dynamic>{}),
        timeout: _timeout,
      ),
    );
  }

  /// `GET /car-rental/bookings/:id/units`
  Future<List<BookingUnitOption>> getBookingUnitOptions(int bookingId) async {
    final response = await _send(
      () => ApiClient.get('$_bookingsPath/$bookingId/units', timeout: _timeout),
    );
    return BookingUnitOption.listFromJson(_decode(response));
  }

  /// `POST /car-rental/bookings/:id/assign-unit`
  Future<void> assignBookingUnit(int bookingId, int carId) async {
    await _send(
      () => ApiClient.post(
        '$_bookingsPath/$bookingId/assign-unit',
        body: jsonEncode(<String, dynamic>{'carId': carId}),
        timeout: _timeout,
      ),
    );
  }

  /// `POST /car-rental/bookings/:id/extensions/:extensionId/approve|decline`
  Future<void> decideExtension(
    int bookingId,
    String extensionId, {
    required bool approve,
    String? reason,
  }) async {
    final trimmed = reason?.trim() ?? '';
    await _send(
      () => ApiClient.post(
        '$_bookingsPath/$bookingId/extensions/$extensionId/'
        '${approve ? 'approve' : 'decline'}',
        body: jsonEncode(<String, dynamic>{
          if (!approve && trimmed.isNotEmpty) 'reason': trimmed,
        }),
        timeout: _timeout,
      ),
    );
  }

  /// `POST /car-rental/bookings/:id/incidents/:incidentId/resolve`
  Future<void> resolveIncident(
    int bookingId,
    String incidentId, {
    required String resolution,
    String? remedy,
  }) async {
    await _send(
      () => ApiClient.post(
        '$_bookingsPath/$bookingId/incidents/$incidentId/resolve',
        body: jsonEncode(<String, dynamic>{
          'resolution': resolution.trim(),
          if (remedy != null && remedy.isNotEmpty) 'remedy': remedy,
        }),
        timeout: _timeout,
      ),
    );
  }

  /// `GET /car-rental/cars/owner/fleet`
  Future<List<FleetUnit>> getCompanyFleet() async {
    final response = await _send(
      () => ApiClient.get('$_carsPath/owner/fleet', timeout: _timeout),
    );
    return FleetUnit.listFromJson(_decode(response));
  }

  /// `PATCH /car-rental/cars/:id` with `{ isAvailable }`.
  Future<void> setUnitInService(int carId, bool inService) async {
    await _send(
      () => ApiClient.patch(
        '$_carsPath/$carId',
        body: jsonEncode(<String, dynamic>{'isAvailable': inService}),
        timeout: _timeout,
      ),
    );
  }

  /// `POST /car-rental/cars/:id/maintenance-blocks`
  Future<void> addMaintenanceBlock(
    int carId, {
    required DateTime startAt,
    required DateTime endAt,
    required String category,
    String? reason,
  }) async {
    final trimmed = reason?.trim() ?? '';
    await _send(
      () => ApiClient.post(
        '$_carsPath/$carId/maintenance-blocks',
        body: jsonEncode(<String, dynamic>{
          'startAt': _iso(startAt),
          'endAt': _iso(endAt),
          'category': category,
          if (trimmed.isNotEmpty) 'reason': trimmed,
        }),
        timeout: _timeout,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static List<dynamic> _listFrom(dynamic decoded, List<String> keys) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in keys) {
        final value = decoded[key];
        if (value is List) return value;
      }
    }
    return const <dynamic>[];
  }

  static Map<String, dynamic> _mapFrom(dynamic decoded, List<String> keys) {
    if (decoded is! Map) return const <String, dynamic>{};
    return _unwrapMap(decoded, keys);
  }

  static String _iso(DateTime value) => value.toUtc().toIso8601String();

  Future<http.Response> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request();
    } on ApiException catch (error) {
      throw _mapApiError(error);
    } on CarHireApiException {
      rethrow;
    } catch (error) {
      throw CarHireApiException(
        message: UserFacingError.from(error),
        kind: CarHireErrorKind.unknown,
      );
    }
  }

  static dynamic _decode(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const CarHireApiException(
        message: "We couldn't read the server response. Please try again.",
        kind: CarHireErrorKind.server,
      );
    }
  }

  static Map<String, dynamic> _unwrapMap(
    Map<dynamic, dynamic> raw,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = raw[key];
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), v));
      }
    }
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  static CarHireApiException _mapApiError(ApiException error) {
    final status = error.statusCode;
    final message = error.message.trim().toLowerCase();

    var kind = CarHireErrorKind.unknown;
    if (status == 400) {
      kind = CarHireErrorKind.validation;
    } else if (status == 401) {
      kind = CarHireErrorKind.unauthorized;
    } else if (status == 403) {
      kind = CarHireErrorKind.forbidden;
    } else if (status == 404) {
      kind = CarHireErrorKind.notFound;
    } else if (status == 409) {
      kind = CarHireErrorKind.conflict;
    } else if (status == 410) {
      kind = CarHireErrorKind.gone;
    } else if (status == 429) {
      kind = CarHireErrorKind.rateLimited;
    } else if (status != null && status >= 500) {
      kind = CarHireErrorKind.server;
    } else if (message.contains('timed out') || message.contains('timeout')) {
      kind = CarHireErrorKind.timeout;
    } else if (message.contains('network') ||
        message.contains('connection') ||
        message.contains('offline')) {
      kind = CarHireErrorKind.network;
    }

    final fallback = switch (kind) {
      CarHireErrorKind.validation =>
        'Some details are invalid. Please check the dates and try again.',
      CarHireErrorKind.unauthorized => 'Please sign in to continue.',
      CarHireErrorKind.forbidden =>
        'You do not have permission to do that.',
      CarHireErrorKind.notFound =>
        "We couldn't find what you were looking for.",
      CarHireErrorKind.conflict =>
        'Those dates are no longer available. Please choose different dates.',
      CarHireErrorKind.gone =>
        'This offer has expired. Please refresh and try again.',
      CarHireErrorKind.rateLimited =>
        'Too many requests. Please wait a moment and try again.',
      CarHireErrorKind.server =>
        'Our servers are busy. Please try again in a moment.',
      CarHireErrorKind.network ||
      CarHireErrorKind.timeout =>
        'Check your connection and try again.',
      CarHireErrorKind.unknown =>
        'Something went wrong. Please try again.',
    };

    final raw = error.message.trim();
    final safe = raw.isEmpty
        ? fallback
        : UserFacingError.sanitize(raw, fallback: fallback);

    return CarHireApiException(
      message: safe,
      statusCode: status,
      kind: kind,
      backendMessage: error.backendMessage,
    );
  }
}
