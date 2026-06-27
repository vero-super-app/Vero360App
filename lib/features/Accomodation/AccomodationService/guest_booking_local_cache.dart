import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/my_Accodation_bookingdata_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/mybookingData_service.dart';

/// Device-local paid stays shown in “My bookings” until `GET /bookings/me` catches up.
class GuestBookingLocalCache {
  GuestBookingLocalCache._();

  static const _prefsKey = 'guest_paid_stay_bookings_v1';
  static const _maxEntries = 20;

  static String _refKey(BookingItem b) {
    final ref = b.displayBookingRef.trim().toLowerCase();
    if (ref.isNotEmpty) return ref;
    return b.id.trim().toLowerCase();
  }

  static bool sameBooking(BookingItem a, BookingItem b) {
    final aId = a.id.trim();
    final bId = b.id.trim();
    if (aId.isNotEmpty && bId.isNotEmpty && aId == bId) return true;
    final aRef = _refKey(a);
    final bRef = _refKey(b);
    return aRef.isNotEmpty && aRef == bRef;
  }

  static Future<List<BookingItem>> loadPaidStays() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => BookingItem.fromJson(Map<String, dynamic>.from(e)))
          .where((b) => b.includeInGuestMyBookings)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> rememberPaidStay(BookingItem item) async {
    if (!item.includeInGuestMyBookings) return;
    final existing = await loadPaidStays();
    final merged = [
      item,
      ...existing.where((b) => !sameBooking(b, item)),
    ];
    if (merged.length > _maxEntries) {
      merged.removeRange(_maxEntries, merged.length);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _prefsKey,
      jsonEncode(merged.map(_toJson).toList()),
    );

    final id = item.id.trim();
    if (id.isNotEmpty) {
      try {
        await MyBookingService().updateStatus(id, BookingStatus.confirmed);
      } catch (_) {}
    }
  }

  static Future<void> pruneIfPresentInApi(List<BookingItem> api) async {
    if (api.isEmpty) return;
    final local = await loadPaidStays();
    if (local.isEmpty) return;
    final remaining =
        local.where((l) => !api.any((a) => sameBooking(a, l))).toList();
    final sp = await SharedPreferences.getInstance();
    if (remaining.isEmpty) {
      await sp.remove(_prefsKey);
      return;
    }
    await sp.setString(
      _prefsKey,
      jsonEncode(remaining.map(_toJson).toList()),
    );
  }

  static BookingItem buildFromCheckout({
    required Map<String, dynamic> bookingDetails,
    required String bookingRef,
    required int accommodationId,
    required String propertyName,
    String? propertyLocation,
    required DateTime checkIn,
    DateTime? checkOut,
    required num totalMwk,
    String? guestName,
    String? guestEmail,
    String? guestPhone,
  }) {
    final m = Map<String, dynamic>.from(bookingDetails);
    final data = m['data'];
    if (data is Map) {
      m.addAll(Map<String, dynamic>.from(data));
    }

    final id = (m['id'] ?? m['bookingId'] ?? m['ID'] ?? bookingRef).toString();

    m['id'] = id;
    m['bookingId'] = id;
    m['bookingNumber'] = bookingRef;
    m['bookingRef'] = bookingRef;
    m['accommodationId'] = accommodationId;
    m['accommodationName'] = propertyName;
    if ((propertyLocation ?? '').trim().isNotEmpty) {
      m['accommodationLocation'] = propertyLocation!.trim();
    }
    m['bookingDate'] = DateFormat('yyyy-MM-dd').format(checkIn);
    if (checkOut != null) {
      m['checkOut'] = DateFormat('yyyy-MM-dd').format(checkOut);
    }
    m['price'] = totalMwk;
    m['bookingFee'] = 0;
    m['status'] = 'booked';
    m['paymentStatus'] = 'paid';
    m['paid'] = true;
    if ((guestName ?? '').trim().isNotEmpty) m['guestName'] = guestName!.trim();
    if ((guestEmail ?? '').trim().isNotEmpty) {
      m['guestEmail'] = guestEmail!.trim();
    }
    if ((guestPhone ?? '').trim().isNotEmpty) {
      m['guestPhone'] = guestPhone!.trim();
    }

    return BookingItem.fromJson(m);
  }

  static Map<String, dynamic> _toJson(BookingItem b) => {
        'id': b.id,
        if (b.bookingDate != null)
          'bookingDate': b.bookingDate!.toIso8601String(),
        'price': b.price,
        'bookingFee': b.bookingFee,
        'status': 'booked',
        'paymentStatus': 'paid',
        'paid': true,
        if (b.accommodationId != null) 'accommodationId': b.accommodationId,
        if (b.accommodationName != null) 'accommodationName': b.accommodationName,
        if (b.accommodationLocation != null)
          'accommodationLocation': b.accommodationLocation,
        if (b.imageUrl != null) 'imageUrl': b.imageUrl,
        if (b.guestName != null) 'guestName': b.guestName,
        if (b.guestEmail != null) 'guestEmail': b.guestEmail,
        if (b.guestPhone != null) 'guestPhone': b.guestPhone,
        if (b.bookingNumber != null) 'bookingNumber': b.bookingNumber,
        if (b.checkOutDate != null)
          'checkOut': b.checkOutDate!.toIso8601String(),
        if (b.nights != null) 'nights': b.nights,
      };
}
