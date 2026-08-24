import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/my_Accodation_bookingdata_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/mybookingData_service.dart';
import 'package:vero360_app/utils/firebase_bootstrap.dart';

/// Device-local paid stays shown in “My bookings” until `GET /bookings/me` catches up.
///
/// Scoped per Firebase uid so logout / account switch cannot leak another user’s stays.
class GuestBookingLocalCache {
  GuestBookingLocalCache._();

  static const _legacyPrefsKey = 'guest_paid_stay_bookings_v1';
  static const _prefsPrefix = 'guest_paid_stay_bookings_v1_';
  static const _maxEntries = 20;

  static String? get _uid {
    try {
      if (Firebase.apps.isEmpty) return null;
      final u = FirebaseAuth.instance.currentUser?.uid.trim();
      return (u == null || u.isEmpty) ? null : u;
    } catch (_) {
      return null;
    }
  }

  static String? _prefsKeyForCurrentUser() {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return null;
    return '$_prefsPrefix$uid';
  }

  static Future<String?> _prefsKeyReady() async {
    await ensureFirebaseApp();
    return _prefsKeyForCurrentUser();
  }

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

  /// Wipe all guest stay caches (legacy + every uid). Call on logout.
  static Future<void> clearOnLogout() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_legacyPrefsKey);
      for (final key in sp.getKeys().toList()) {
        if (key == _legacyPrefsKey || key.startsWith(_prefsPrefix)) {
          await sp.remove(key);
        }
      }
    } catch (_) {}
  }

  /// Remove one stay from the current user’s local cache (e.g. after delete / 404).
  static Future<void> removeStay(BookingItem item) async {
    final key = await _prefsKeyReady();
    if (key == null) return;
    try {
      final existing = await loadPaidStays();
      final remaining =
          existing.where((b) => !sameBooking(b, item)).toList(growable: false);
      final sp = await SharedPreferences.getInstance();
      if (remaining.isEmpty) {
        await sp.remove(key);
        return;
      }
      await sp.setString(
        key,
        jsonEncode(remaining.map(_toJson).toList()),
      );
    } catch (_) {}
  }

  static Future<List<BookingItem>> loadPaidStays() async {
    final key = await _prefsKeyReady();
    if (key == null) return [];
    try {
      final sp = await SharedPreferences.getInstance();
      // Drop legacy unscoped cache so prior-account stays cannot leak.
      if (sp.containsKey(_legacyPrefsKey)) {
        await sp.remove(_legacyPrefsKey);
      }
      final raw = sp.getString(key);
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
    final key = await _prefsKeyReady();
    if (key == null) return;

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
      key,
      jsonEncode(merged.map(_toJson).toList()),
    );

    // Persist PAID on backend so My bookings / host views stop showing UNPAID.
    final id = item.id.trim();
    final ref = (item.bookingNumber ?? '').trim();
    try {
      await MyBookingService().markBookingPaid(
        bookingId: id.isNotEmpty ? id : null,
        bookingNumber: ref.isNotEmpty
            ? ref
            : (item.displayBookingRef.isNotEmpty ? item.displayBookingRef : null),
      );
    } catch (_) {
      // Local cache still shows the stay until API catches up / retry.
    }
  }

  static Future<void> pruneIfPresentInApi(List<BookingItem> api) async {
    if (api.isEmpty) return;
    final key = await _prefsKeyReady();
    if (key == null) return;
    final local = await loadPaidStays();
    if (local.isEmpty) return;
    final remaining =
        local.where((l) => !api.any((a) => sameBooking(a, l))).toList();
    final sp = await SharedPreferences.getInstance();
    if (remaining.isEmpty) {
      await sp.remove(key);
      return;
    }
    await sp.setString(
      key,
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
    m['createdAt'] = DateTime.now().toIso8601String();
    m['transactionDate'] = DateTime.now().toIso8601String();
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
        if (b.transactionDate != null)
          'createdAt': b.transactionDate!.toIso8601String(),
        if (b.transactionDate != null)
          'transactionDate': b.transactionDate!.toIso8601String(),
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
