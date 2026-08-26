import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:intl/intl.dart';

/// Shared Firestore inventory so every guest sees booked nights on Discover + calendar.
///
/// Parent: `accommodation_occupancy/{accommodationId}` with `counts: { yyyy-MM-dd: n }`
/// (Discover reads this for the global "Booked today" badge).
/// Subcollections: `nights/{day}`, `stays/{bookingRef}` (source of truth for locks).
class AccommodationOccupancyService {
  AccommodationOccupancyService({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _db {
    final override = _firestoreOverride;
    if (override != null) return override;
    return FirebaseFirestore.instance;
  }
  static final _dayFmt = DateFormat('yyyy-MM-dd');

  static const statusReserved = 'reserved';
  static const statusPaid = 'paid';
  static const statusReleased = 'released';
  /// Host blocked dates for a guest who booked outside the app (walk-in, phone, etc.).
  static const statusOffline = 'offline';

  static bool _isActiveOccupancyStatus(String status) {
    return status == statusReserved ||
        status == statusPaid ||
        status == statusOffline;
  }

  DocumentReference<Map<String, dynamic>> _root(int accommodationId) =>
      _db.collection('accommodation_occupancy').doc('$accommodationId');

  CollectionReference<Map<String, dynamic>> _nights(int accommodationId) =>
      _root(accommodationId).collection('nights');

  CollectionReference<Map<String, dynamic>> _stays(int accommodationId) =>
      _root(accommodationId).collection('stays');

  /// Firestore doc ids cannot contain `/`.
  static String sanitizeBookingRef(String bookingRef) {
    final t = bookingRef.trim();
    if (t.isEmpty) return t;
    return t.replaceAll(RegExp(r'[\/#\[\]]'), '_');
  }

  static String dayKey(DateTime d) =>
      _dayFmt.format(DateTime(d.year, d.month, d.day));

  /// Slept nights: inclusive check-in, exclusive check-out.
  static List<DateTime> nightsInRange(DateTime checkIn, DateTime checkOut) {
    final start = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final end = DateTime(checkOut.year, checkOut.month, checkOut.day);
    if (!end.isAfter(start)) return const [];
    final out = <DateTime>[];
    for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
      out.add(d);
    }
    return out;
  }

  /// Checkout morning frees the listing (check-out day is not a slept night).
  static bool stayHasCheckedOut(DateTime checkOut, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final out = DateTime(checkOut.year, checkOut.month, checkOut.day);
    return !out.isAfter(today);
  }

  /// Capacity for inventory: single-unit types = 1; hotel/lodge = [roomsAvailable].
  static int capacityForType({
    required String accommodationType,
    required int roomsAvailable,
  }) {
    final t = accommodationType.toLowerCase().trim();
    if (t == 'hotel' || t == 'lodge') {
      return roomsAvailable < 1 ? 1 : roomsAvailable;
    }
    return 1;
  }

  Map<String, int> _parseCountsMap(dynamic raw) {
    if (raw is! Map) return {};
    final out = <String, int>{};
    raw.forEach((k, v) {
      final key = k.toString();
      final n = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      if (key.isNotEmpty && n > 0) out[key] = n;
    });
    return out;
  }

  /// Mirror night totals onto the parent doc so Discover can show "Booked today" globally.
  ///
  /// Nested `counts` must use [FieldValue.delete] for freed nights — a merged
  /// map write does not remove old date keys, which left "Booked" stuck forever.
  void _txWriteParentCounts(
    Transaction tx, {
    required int accommodationId,
    required int capacity,
    required Map<String, int> nightUpdates,
    DocumentSnapshot<Map<String, dynamic>>? parentSnap,
  }) {
    final existing = _parseCountsMap(parentSnap?.data()?['counts']);
    for (final e in nightUpdates.entries) {
      if (e.value <= 0) {
        existing.remove(e.key);
      } else {
        existing[e.key] = e.value;
      }
    }
    final today = dayKey(DateTime.now());
    final tonight = existing[today] ?? 0;
    final cap = capacity < 1 ? 1 : capacity;
    final payload = <String, dynamic>{
      'capacityHint': cap,
      'bookedToday': tonight >= cap,
      'tonightCount': tonight,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    for (final e in nightUpdates.entries) {
      if (e.value <= 0) {
        payload['counts.${e.key}'] = FieldValue.delete();
      } else {
        payload['counts.${e.key}'] = e.value;
      }
    }
    tx.set(
      _root(accommodationId),
      payload,
      SetOptions(merge: true),
    );
  }

  /// Night counts for one listing (parent mirror + nights subcollection merged).
  ///
  /// Set [prune] false for fast calendar opens — pruning walks every stay and
  /// made check-in/out feel like it needed two taps.
  Future<Map<String, int>> fetchNightCounts(
    int accommodationId, {
    bool fromServer = false,
    bool prune = true,
  }) async {
    if (accommodationId <= 0) return {};
    try {
      if (prune) {
        await pruneCompletedStays(accommodationId);
      }
      final getOpts = fromServer
          ? const GetOptions(source: Source.server)
          : const GetOptions(source: Source.serverAndCache);
      final parent = await _root(accommodationId).get(getOpts);
      final merged = _parseCountsMap(parent.data()?['counts']);

      final snap = await _nights(accommodationId).get(getOpts);
      for (final doc in snap.docs) {
        final c = doc.data()['count'];
        final n = c is num ? c.toInt() : int.tryParse('$c') ?? 0;
        if (n <= 0) continue;
        final prev = merged[doc.id] ?? 0;
        if (n > prev) merged[doc.id] = n;
      }
      return merged;
    } catch (e) {
      if (kDebugMode) {
        print('[AccommodationOccupancy] fetchNightCounts($accommodationId): $e');
      }
      return {};
    }
  }

  static int roomsUsedOnNight(Map<String, int> nightCounts, DateTime night) {
    return nightCounts[dayKey(night)] ?? 0;
  }

  static int roomsFreeOnNight({
    required Map<String, int> nightCounts,
    required DateTime night,
    required int capacity,
  }) {
    final cap = capacity < 1 ? 1 : capacity;
    final used = roomsUsedOnNight(nightCounts, night);
    return (cap - used).clamp(0, cap);
  }

  static int minRoomsFreeInRange({
    required Map<String, int> nightCounts,
    required DateTime checkIn,
    required DateTime checkOut,
    required int capacity,
  }) {
    final nights = nightsInRange(checkIn, checkOut);
    if (nights.isEmpty) return capacity < 1 ? 1 : capacity;
    var minFree = capacity < 1 ? 1 : capacity;
    for (final n in nights) {
      final free = roomsFreeOnNight(
        nightCounts: nightCounts,
        night: n,
        capacity: capacity,
      );
      if (free < minFree) minFree = free;
    }
    return minFree;
  }

  static int nightsWithBookingsInRange({
    required Map<String, int> nightCounts,
    required DateTime checkIn,
    required DateTime checkOut,
  }) {
    var count = 0;
    for (final n in nightsInRange(checkIn, checkOut)) {
      if (roomsUsedOnNight(nightCounts, n) > 0) count++;
    }
    return count;
  }

  static bool isNightPartiallyBooked({
    required Map<String, int> nightCounts,
    required DateTime night,
    required int capacity,
  }) {
    final cap = capacity < 1 ? 1 : capacity;
    if (cap <= 1) return false;
    final used = roomsUsedOnNight(nightCounts, night);
    return used > 0 && used < cap;
  }

  /// Guest-facing copy: "6 rooms are free" or "6 of 10 rooms are free".
  static String roomsFreeLabel({
    required int free,
    required int total,
    bool loading = false,
  }) {
    if (loading) return 'Checking availability…';
    final cap = total < 1 ? 1 : total;
    final f = free.clamp(0, cap);
    if (f <= 0) return cap == 1 ? 'Booked' : 'No rooms free';
    if (cap == 1) return '1 room is free';
    if (f >= cap) return '$f rooms are free';
    return '$f of $cap rooms are free';
  }

  /// Tonight's count for many listings — reads parent docs (global Discover badge).
  Future<Map<int, int>> fetchTodayCounts(
    Iterable<int> accommodationIds, {
    bool legacyFallback = true,
  }) async {
    final today = dayKey(DateTime.now());
    final ids = accommodationIds.where((id) => id > 0).toSet().toList();
    if (ids.isEmpty) return {};

    final out = <int, int>{};
    Future<void> readChunk(List<String> docIds, {required bool fromCache}) async {
      try {
        final snap = await _db
            .collection('accommodation_occupancy')
            .where(FieldPath.documentId, whereIn: docIds)
            .get(GetOptions(source: fromCache ? Source.cache : Source.server));
        for (final doc in snap.docs) {
          final id = int.tryParse(doc.id) ?? 0;
          if (id <= 0) continue;
          final data = doc.data();
          final counts = _parseCountsMap(data['counts']);
          var n = counts[today] ?? 0;
          if (n <= 0 && counts.isEmpty) {
            final tc = data['tonightCount'];
            n = tc is num ? tc.toInt() : int.tryParse('$tc') ?? 0;
          }
          if (n > 0) out[id] = n;
        }
      } catch (_) {}
    }

    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += 10) {
      chunks.add(
        ids.sublist(i, min(i + 10, ids.length)).map((id) => '$id').toList(),
      );
    }
    await Future.wait(chunks.map((c) => readChunk(c, fromCache: true)));
    final missingAfterCache = ids.where((id) => !out.containsKey(id)).toList();
    if (missingAfterCache.isNotEmpty) {
      final rest = <List<String>>[];
      for (var i = 0; i < missingAfterCache.length; i += 10) {
        rest.add(
          missingAfterCache
              .sublist(i, min(i + 10, missingAfterCache.length))
              .map((id) => '$id')
              .toList(),
        );
      }
      await Future.wait(rest.map((c) => readChunk(c, fromCache: false)));
    }

    if (!legacyFallback) return out;

    // Fallback for listings with only night subdocs (pre-mirror writes).
    final missing = ids.where((id) => !out.containsKey(id)).toList();
    await Future.wait(missing.map((id) async {
      try {
        final doc = await _nights(id).doc(today).get();
        final c = doc.data()?['count'];
        final n = c is num ? c.toInt() : int.tryParse('$c') ?? 0;
        if (n > 0) out[id] = n;
      } catch (_) {}
    }));
    return out;
  }

  bool isNightFull({
    required Map<String, int> nightCounts,
    required DateTime night,
    required int capacity,
  }) {
    final cap = capacity < 1 ? 1 : capacity;
    final used = nightCounts[dayKey(night)] ?? 0;
    return used >= cap;
  }

  bool isRangeAvailable({
    required Map<String, int> nightCounts,
    required DateTime checkIn,
    required DateTime checkOut,
    required int capacity,
    int rooms = 1,
  }) {
    final cap = capacity < 1 ? 1 : capacity;
    final need = rooms < 1 ? 1 : rooms;
    for (final n in nightsInRange(checkIn, checkOut)) {
      final used = nightCounts[dayKey(n)] ?? 0;
      if (used + need > cap) return false;
    }
    return true;
  }

  Future<void> reserveStay({
    required int accommodationId,
    required String bookingRef,
    required DateTime checkIn,
    required DateTime checkOut,
    required int capacity,
    int rooms = 1,
  }) async {
    final ref = sanitizeBookingRef(bookingRef);
    if (accommodationId <= 0 || ref.isEmpty) {
      throw ArgumentError('Invalid accommodationId or bookingRef');
    }
    final nights = nightsInRange(checkIn, checkOut);
    if (nights.isEmpty) {
      throw ArgumentError('checkOut must be after checkIn');
    }
    final cap = capacity < 1 ? 1 : capacity;
    final need = rooms < 1 ? 1 : rooms;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final stayRef = _stays(accommodationId).doc(ref);
    final nightRefs =
        nights.map((d) => _nights(accommodationId).doc(dayKey(d))).toList();
    final rootRef = _root(accommodationId);

    try {
      await _db.runTransaction((tx) async {
        final existing = await tx.get(stayRef);
        if (existing.exists) {
          final st = (existing.data()?['status'] ?? '').toString();
          if (_isActiveOccupancyStatus(st)) {
            return;
          }
        }

        final parentSnap = await tx.get(rootRef);
        final counts = <String, int>{};
        for (final nr in nightRefs) {
          final snap = await tx.get(nr);
          final c = snap.data()?['count'];
          counts[nr.id] = c is num ? c.toInt() : int.tryParse('$c') ?? 0;
        }

        for (final nr in nightRefs) {
          if ((counts[nr.id] ?? 0) + need > cap) {
            throw OccupancyConflictException(
              'Those dates are already booked.',
            );
          }
        }

        final nightUpdates = <String, int>{};
        for (final nr in nightRefs) {
          final next = (counts[nr.id] ?? 0) + need;
          nightUpdates[nr.id] = next;
          tx.set(
            nr,
            {
              'count': next,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        tx.set(stayRef, {
          'accommodationId': accommodationId,
          'bookingRef': ref,
          'checkIn': dayKey(checkIn),
          'checkOut': dayKey(checkOut),
          'rooms': need,
          'capacity': cap,
          'status': statusReserved,
          'guestUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        _txWriteParentCounts(
          tx,
          accommodationId: accommodationId,
          capacity: cap,
          nightUpdates: nightUpdates,
          parentSnap: parentSnap,
        );
      });
    } on OccupancyConflictException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        print('[AccommodationOccupancy] reserveStay FAILED: $e');
      }
      throw OccupancyConflictException(
        'Could not lock those dates. Check your connection and try again.',
      );
    }
  }

  Future<void> confirmPaid({
    required int accommodationId,
    required String bookingRef,
    required DateTime checkIn,
    required DateTime checkOut,
    required int capacity,
    int rooms = 1,
  }) async {
    final ref = sanitizeBookingRef(bookingRef);
    if (accommodationId <= 0 || ref.isEmpty) return;

    if (stayHasCheckedOut(checkOut)) {
      await releaseCompletedStay(
        accommodationId: accommodationId,
        bookingRef: ref,
      );
      return;
    }

    final nights = nightsInRange(checkIn, checkOut);
    if (nights.isEmpty) return;
    final cap = capacity < 1 ? 1 : capacity;
    final need = rooms < 1 ? 1 : rooms;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final stayRef = _stays(accommodationId).doc(ref);
    final nightRefs =
        nights.map((d) => _nights(accommodationId).doc(dayKey(d))).toList();
    final rootRef = _root(accommodationId);

    try {
      await _db.runTransaction((tx) async {
        final staySnap = await tx.get(stayRef);
        final parentSnap = await tx.get(rootRef);
        final prev = staySnap.data();
        final prevStatus = (prev?['status'] ?? '').toString();

        // All reads first (Firestore transaction rule).
        final nightTotals = <String, int>{};
        for (final nr in nightRefs) {
          final snap = await tx.get(nr);
          final c = snap.data()?['count'];
          nightTotals[nr.id] =
              c is num ? c.toInt() : int.tryParse('$c') ?? 0;
        }

        if (prevStatus == statusPaid) {
          tx.set(stayRef, {
            'status': statusPaid,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          _txWriteParentCounts(
            tx,
            accommodationId: accommodationId,
            capacity: cap,
            nightUpdates: nightTotals,
            parentSnap: parentSnap,
          );
          return;
        }

        if (prevStatus == statusReserved) {
          tx.set(stayRef, {
            'status': statusPaid,
            'checkIn': dayKey(checkIn),
            'checkOut': dayKey(checkOut),
            'rooms': need,
            'capacity': cap,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          _txWriteParentCounts(
            tx,
            accommodationId: accommodationId,
            capacity: cap,
            nightUpdates: nightTotals,
            parentSnap: parentSnap,
          );
          return;
        }

        // Missing or released — restore inventory + parent mirror.
        final nightUpdates = <String, int>{};
        for (final nr in nightRefs) {
          final next = (nightTotals[nr.id] ?? 0) + need;
          nightUpdates[nr.id] = next;
          tx.set(
            nr,
            {
              'count': next,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        tx.set(stayRef, {
          'accommodationId': accommodationId,
          'bookingRef': ref,
          'checkIn': dayKey(checkIn),
          'checkOut': dayKey(checkOut),
          'rooms': need,
          'capacity': cap,
          'status': statusPaid,
          'guestUid': uid.isNotEmpty ? uid : (prev?['guestUid'] ?? ''),
          'createdAt': prev?['createdAt'] ?? FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        _txWriteParentCounts(
          tx,
          accommodationId: accommodationId,
          capacity: cap,
          nightUpdates: nightUpdates,
          parentSnap: parentSnap,
        );
      });
      if (kDebugMode) {
        print(
          '[AccommodationOccupancy] confirmPaid ok acc=$accommodationId ref=$ref',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('[AccommodationOccupancy] confirmPaid FAILED: $e');
      }
      rethrow;
    }
  }

  /// Blocks calendar nights for an offline / walk-in booking (host-entered).
  Future<String> blockOfflineStay({
    required int accommodationId,
    required DateTime checkIn,
    required DateTime checkOut,
    required int capacity,
    int rooms = 1,
    String? guestLabel,
    String? note,
  }) async {
    final ref = 'offline_${DateTime.now().millisecondsSinceEpoch}';
    final nights = nightsInRange(checkIn, checkOut);
    if (accommodationId <= 0) {
      throw ArgumentError('Invalid accommodationId');
    }
    if (nights.isEmpty) {
      throw ArgumentError('checkOut must be after checkIn');
    }
    final cap = capacity < 1 ? 1 : capacity;
    final need = rooms < 1 ? 1 : rooms;
    final merchantUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final stayRef = _stays(accommodationId).doc(ref);
    final nightRefs =
        nights.map((d) => _nights(accommodationId).doc(dayKey(d))).toList();
    final rootRef = _root(accommodationId);

    try {
      await _db.runTransaction((tx) async {
        final parentSnap = await tx.get(rootRef);
        final counts = <String, int>{};
        for (final nr in nightRefs) {
          final snap = await tx.get(nr);
          final c = snap.data()?['count'];
          counts[nr.id] = c is num ? c.toInt() : int.tryParse('$c') ?? 0;
        }

        for (final nr in nightRefs) {
          if ((counts[nr.id] ?? 0) + need > cap) {
            throw OccupancyConflictException(
              'Those dates are already booked on the calendar.',
            );
          }
        }

        final nightUpdates = <String, int>{};
        for (final nr in nightRefs) {
          final next = (counts[nr.id] ?? 0) + need;
          nightUpdates[nr.id] = next;
          tx.set(
            nr,
            {
              'count': next,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        tx.set(stayRef, {
          'accommodationId': accommodationId,
          'bookingRef': ref,
          'checkIn': dayKey(checkIn),
          'checkOut': dayKey(checkOut),
          'rooms': need,
          'capacity': cap,
          'status': statusOffline,
          'source': 'offline',
          'merchantUid': merchantUid,
          if (guestLabel != null && guestLabel.trim().isNotEmpty)
            'guestLabel': guestLabel.trim(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        _txWriteParentCounts(
          tx,
          accommodationId: accommodationId,
          capacity: cap,
          nightUpdates: nightUpdates,
          parentSnap: parentSnap,
        );
      });
      return ref;
    } on OccupancyConflictException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        print('[AccommodationOccupancy] blockOfflineStay FAILED: $e');
      }
      throw OccupancyConflictException(
        'Could not block those dates. Check your connection and try again.',
      );
    }
  }

  /// Active calendar holds for a listing (app bookings + offline blocks).
  Future<List<AccommodationOccupancyStay>> fetchActiveStays(
    int accommodationId,
  ) async {
    if (accommodationId <= 0) return const [];
    try {
      await pruneCompletedStays(accommodationId);
      final snap = await _stays(accommodationId).get();
      final out = <AccommodationOccupancyStay>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final st = (data['status'] ?? '').toString();
        if (!_isActiveOccupancyStatus(st)) continue;
        final cin = _parseDayKey(data['checkIn']?.toString() ?? '');
        var cout = _parseDayKey(data['checkOut']?.toString() ?? '');
        if (cin == null) continue;
        if (cout == null) cout = cin.add(const Duration(days: 1));
        if (stayHasCheckedOut(cout)) continue;
        out.add(
          AccommodationOccupancyStay(
            bookingRef: doc.id,
            checkIn: cin,
            checkOut: cout,
            status: st,
            guestLabel: data['guestLabel']?.toString(),
            note: data['note']?.toString(),
            rooms: data['rooms'] is num
                ? (data['rooms'] as num).toInt()
                : int.tryParse('${data['rooms']}') ?? 1,
          ),
        );
      }
      out.sort((a, b) => a.checkIn.compareTo(b.checkIn));
      return out;
    } catch (e) {
      if (kDebugMode) {
        print('[AccommodationOccupancy] fetchActiveStays: $e');
      }
      return const [];
    }
  }

  Future<void> releaseOfflineBlock({
    required int accommodationId,
    required String bookingRef,
  }) =>
      _releaseStayInternal(
        accommodationId: accommodationId,
        bookingRef: bookingRef,
        allowPaid: false,
        allowOffline: true,
        requireCheckedOut: false,
      );

  Future<void> publishPaidStay({
    required int accommodationId,
    required String bookingRef,
    required DateTime checkIn,
    required DateTime checkOut,
    required int capacity,
    int rooms = 1,
  }) =>
      confirmPaid(
        accommodationId: accommodationId,
        bookingRef: bookingRef,
        checkIn: checkIn,
        checkOut: checkOut,
        capacity: capacity,
        rooms: rooms,
      );

  Future<void> releaseStay({
    required int accommodationId,
    required String bookingRef,
  }) =>
      _releaseStayInternal(
        accommodationId: accommodationId,
        bookingRef: bookingRef,
        allowPaid: false,
        allowOffline: false,
        requireCheckedOut: false,
      );

  /// Frees calendar nights when a paid stay is cancelled / refunded before check-in.
  Future<void> releaseCancelledStay({
    required int accommodationId,
    required String bookingRef,
  }) =>
      _releaseStayInternal(
        accommodationId: accommodationId,
        bookingRef: bookingRef,
        allowPaid: true,
        allowOffline: false,
        requireCheckedOut: false,
      );

  /// Frees calendar nights after the guest's check-out morning (paid stays included).
  Future<void> releaseCompletedStay({
    required int accommodationId,
    required String bookingRef,
  }) =>
      _releaseStayInternal(
        accommodationId: accommodationId,
        bookingRef: bookingRef,
        allowPaid: true,
        allowOffline: true,
        requireCheckedOut: true,
      );

  /// Drops occupancy for stays whose check-out date has arrived, then refreshes
  /// Discover's "Booked today" flags for this listing.
  Future<void> pruneCompletedStays(int accommodationId) async {
    if (accommodationId <= 0) return;
    try {
      final snap = await _stays(accommodationId).get();
      for (final doc in snap.docs) {
        final st = (doc.data()['status'] ?? '').toString();
        if (!_isActiveOccupancyStatus(st)) continue;
        await releaseCompletedStay(
          accommodationId: accommodationId,
          bookingRef: doc.id,
        );
      }
      await _refreshParentTonightFlags(accommodationId);
    } catch (e) {
      if (kDebugMode) {
        print('[AccommodationOccupancy] pruneCompletedStays: $e');
      }
    }
  }

  Future<void> _refreshParentTonightFlags(int accommodationId) async {
    try {
      final staySnap = await _stays(accommodationId).get();
      final aggregated = <String, int>{};
      var cap = 1;
      for (final doc in staySnap.docs) {
        final data = doc.data();
        final st = (data['status'] ?? '').toString();
        if (!_isActiveOccupancyStatus(st)) continue;
        final cin = _parseDayKey(data['checkIn']?.toString() ?? '');
        var cout = _parseDayKey(data['checkOut']?.toString() ?? '');
        if (cin != null && cout == null) {
          cout = cin.add(const Duration(days: 1));
        }
        if (cin == null || cout == null) continue;
        if (stayHasCheckedOut(cout)) continue;
        final roomsRaw = data['rooms'];
        final need = roomsRaw is num
            ? roomsRaw.toInt()
            : int.tryParse('$roomsRaw') ?? 1;
        final capRaw = data['capacity'];
        final stayCap = capRaw is num
            ? capRaw.toInt()
            : int.tryParse('$capRaw') ?? 1;
        if (stayCap > cap) cap = stayCap;
        for (final n in nightsInRange(cin, cout)) {
          final key = dayKey(n);
          aggregated[key] = (aggregated[key] ?? 0) + need;
        }
      }

      final today = dayKey(DateTime.now());
      final kept = <String, int>{};
      for (final e in aggregated.entries) {
        if (e.key.compareTo(today) >= 0 && e.value > 0) {
          kept[e.key] = e.value;
        }
      }
      final safeCap = cap < 1 ? 1 : cap;
      final tonight = kept[today] ?? 0;
      final payload = {
        'capacityHint': safeCap,
        'counts': kept,
        'bookedToday': tonight >= safeCap,
        'tonightCount': tonight,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final parent = await _root(accommodationId).get();
      if (parent.exists) {
        await _root(accommodationId).update(payload);
      } else if (kept.isNotEmpty) {
        await _root(accommodationId).set(payload);
      }
    } catch (e) {
      if (kDebugMode) {
        print('[AccommodationOccupancy] refreshParentTonightFlags: $e');
      }
    }
  }

  DateTime? _parseDayKey(String s) {
    try {
      return _dayFmt.parseStrict(s.trim());
    } catch (_) {
      return null;
    }
  }

  Future<void> _releaseStayInternal({
    required int accommodationId,
    required String bookingRef,
    required bool allowPaid,
    required bool allowOffline,
    required bool requireCheckedOut,
  }) async {
    final ref = sanitizeBookingRef(bookingRef);
    if (accommodationId <= 0 || ref.isEmpty) return;

    final stayRef = _stays(accommodationId).doc(ref);
    final rootRef = _root(accommodationId);

    try {
      await _db.runTransaction((tx) async {
        final staySnap = await tx.get(stayRef);
        if (!staySnap.exists) return;
        final data = staySnap.data() ?? {};
        final st = (data['status'] ?? '').toString();
        if (st == statusReleased) return;
        if (st == statusPaid && !allowPaid) return;
        if (st == statusOffline && !allowOffline) return;
        if (st != statusReserved && st != statusPaid && st != statusOffline) {
          return;
        }

        final checkInRaw = data['checkIn']?.toString() ?? '';
        final checkOutRaw = data['checkOut']?.toString() ?? '';
        final roomsRaw = data['rooms'];
        final need = roomsRaw is num
            ? roomsRaw.toInt()
            : int.tryParse('$roomsRaw') ?? 1;
        final capRaw = data['capacity'];
        final cap = capRaw is num
            ? capRaw.toInt()
            : int.tryParse('$capRaw') ?? 1;

        var cin = _parseDayKey(checkInRaw);
        var cout = _parseDayKey(checkOutRaw);
        if (cin != null && cout == null) {
          cout = cin.add(const Duration(days: 1));
        }
        if (requireCheckedOut) {
          if (cout == null || !stayHasCheckedOut(cout)) return;
        }
        if (cin == null || cout == null) {
          tx.set(stayRef, {
            'status': statusReleased,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return;
        }

        final parentSnap = await tx.get(rootRef);
        final nightUpdates = <String, int>{};
        for (final n in nightsInRange(cin, cout)) {
          final nr = _nights(accommodationId).doc(dayKey(n));
          final snap = await tx.get(nr);
          final c = snap.data()?['count'];
          final cur = c is num ? c.toInt() : int.tryParse('$c') ?? 0;
          final next = cur - need;
          nightUpdates[nr.id] = next < 0 ? 0 : next;
          tx.set(
            nr,
            {
              'count': next < 0 ? 0 : next,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        tx.set(stayRef, {
          'status': statusReleased,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        _txWriteParentCounts(
          tx,
          accommodationId: accommodationId,
          capacity: cap,
          nightUpdates: nightUpdates,
          parentSnap: parentSnap,
        );
      });
    } catch (e) {
      if (kDebugMode) {
        print('[AccommodationOccupancy] releaseStay: $e');
      }
    }
  }
}

class OccupancyConflictException implements Exception {
  final String message;
  OccupancyConflictException(this.message);

  @override
  String toString() => message;
}

class AccommodationOccupancyStay {
  final String bookingRef;
  final DateTime checkIn;
  final DateTime checkOut;
  final String status;
  final String? guestLabel;
  final String? note;
  final int rooms;

  const AccommodationOccupancyStay({
    required this.bookingRef,
    required this.checkIn,
    required this.checkOut,
    required this.status,
    this.guestLabel,
    this.note,
    this.rooms = 1,
  });

  bool get isOffline =>
      status == AccommodationOccupancyService.statusOffline;
}
