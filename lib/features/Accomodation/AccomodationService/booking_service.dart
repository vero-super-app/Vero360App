import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_booking_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class BookingService {
  /// `POST /vero/bookings` (ApiClient prefixes `/vero`).
  static const String _bookingsPath = '/bookings';
  static const String _paymentPath = '/payments/pay';

  /// Creates a stay booking via the current backend (`POST /vero/bookings`).
  Future<Map<String, dynamic>> createBooking(
    VeroBookingsCreatePayload payload,
  ) async {
    try {
      final response = await ApiClient.post(
        _bookingsPath,
        body: jsonEncode(payload.toJson()),
      );

      if (kDebugMode) {
        print('Booking POST $_bookingsPath: ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const ApiException(
          message: 'Booking failed: unexpected response.',
        );
      }
      final map = Map<String, dynamic>.from(decoded);

      final ref = _extractBookingRef(map) ??
          'stay-${payload.accommodationId}-${DateTime.now().millisecondsSinceEpoch}';

      return {
        'status': 'success',
        'bookingDetails': map,
        'bookingRef': ref,
      };
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        message: 'Booking failed. Please try again.',
      );
    }
  }

  /// Picks a stable reference for PayChangu / escrow from common API shapes.
  static String? _extractBookingRef(Map<String, dynamic> m) {
    String? pick(Map<String, dynamic> map) {
      for (final k in [
        'bookingNumber',
        'BookingNumber',
        'bookingId',
        'booking_id',
        'id',
        'Id',
        'reference',
        'referenceNumber',
      ]) {
        final v = map[k];
        if (v != null) {
          final s = v.toString().trim();
          if (s.isNotEmpty) return s;
        }
      }
      return null;
    }

    final direct = pick(m);
    if (direct != null) return direct;
    final d = m['data'];
    if (d is Map) {
      return pick(Map<String, dynamic>.from(d));
    }
    return null;
  }

  /// Walks a booking API payload for a Firebase-shaped host uid (Firestore `order_party_alerts`).
  static String? extractHostFirebaseUidFromBookingResponse(dynamic root) {
    String? tryMap(Map<String, dynamic> m) {
      for (final k in [
        'hostMerchantUid',
        'hostUid',
        'merchantFirebaseUid',
        'ownerUid',
        'firebaseUid',
        'merchantId',
        'uid',
      ]) {
        final v = m[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isEmpty) continue;
        if (Accommodation.looksLikeFirebaseAuthUid(s)) return s;
      }
      return null;
    }

    if (root is! Map) return null;
    final queue = <Map<String, dynamic>>[
      Map<String, dynamic>.from(root),
    ];
    var steps = 0;
    while (queue.isNotEmpty && steps++ < 48) {
      final m = queue.removeAt(0);
      final hit = tryMap(m);
      if (hit != null) return hit;
      for (final e in m.values) {
        if (e is Map) {
          queue.add(Map<String, dynamic>.from(e));
        } else if (e is List) {
          for (final x in e) {
            if (x is Map) {
              queue.add(Map<String, dynamic>.from(x));
            }
          }
        }
      }
    }
    return null;
  }

  // Step 2: Initiate payment
  Future<Map<String, dynamic>> initiatePayment({
    required String amount,
    required String currency,
    required String email,
    required String txRef,
    required String phoneNumber,
    required String name,
  }) async {
    try {
      final response = await ApiClient.post(
        _paymentPath,
        headers: {
          'accept': '*/*',
        },
        body: jsonEncode({
          'amount': amount,
          'currency': currency,
          'email': email,
          'tx_ref': txRef,
          'phone_number': phoneNumber,
          'name': name,
        }),
      );

      if (kDebugMode) {
        print('Parsed Payment Response: ${response.body}');
      }

      final responseBody = jsonDecode(response.body);

      if (responseBody['statusCode'] == 200 &&
          responseBody['data'] != null &&
          responseBody['data']['checkout_url'] != null) {
        return {
          'status': 'success',
          'checkout_url': responseBody['data']['checkout_url'],
        };
      } else {
        throw const ApiException(
          message: 'Payment initiation failed. Please try again.',
        );
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        message: 'Payment initiation failed. Please try again.',
      );
    }
  }

  Future<void> cancelOrDelete(String id) async {
    // implement when backend route exists
  }
}
