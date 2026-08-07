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
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static final _dayFmt = DateFormat('yyyy-MM-dd');

  static const statusReserved = 'reserved';
  static const statusPaid = 'paid';
  static const statusReleased = 'released';

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
    tx.set(
      _root(accommodationId),
      {
        'capacityHint': cap,
        'counts': existing,
        'bookedToday': tonight >= cap,
        'tonightCount': tonight,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Night counts for one listing (parent mirror, then nights subcollection).
  Future<Map<String, int>> fetchNightCounts(
    int accommodationId, {
    bool fromServer = false,
  }) async {
    if (accommodationId <= 0) return {};
    try {
      final getOpts = fromServer
          ? const GetOptions(source: Source.server)
          : const GetOptions(source: Source.serverAndCache);
      final parent = await _root(accommodationId).get(getOpts);
      final mirrored = _parseCountsMap(parent.data()?['counts']);
      if (mirrored.isNotEmpty) return mirrored;

      final snap = await _nights(accommodationId).get(getOpts);
      final out = <String, int>{};
      for (final doc in snap.docs) {
        final c = doc.data()['count'];
        final n = c is num ? c.toInt() : int.tryParse('$c') ?? 0;
        if (n > 0) out[doc.id] = n;
      }
      return out;
    } catch (e) {
      if (kDebugMode) {
        print('[AccommodationOccupancy] fetchNightCounts($accommodationId): $e');
      }
      return {};
    }
  }

  /// Tonight's count for many listings — reads parent docs (global Discover badge).
  Future<Map<int, int>> fetchTodayCounts(Iterable<int> accommodationIds) async {
    final today = dayKey(DateTime.now());
    final ids = accommodationIds.where((id) => id > 0).toSet().toList();
    if (ids.isEmpty) return {};

    final out = <int, int>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, min(i + 10, ids.length));
      final docIds = chunk.map((id) => '$id').toList();
      try {
        final snap = await _db
            .collection('accommodation_occupancy')
            .where(FieldPath.documentId, whereIn: docIds)
            .get();
        for (final doc in snap.docs) {
          final id = int.tryParse(doc.id) ?? 0;
          if (id <= 0) continue;
          final data = doc.data();
          final counts = _parseCountsMap(data['counts']);
          var n = counts[today] ?? 0;
          if (n <= 0) {
            final tc = data['tonightCount'];
            n = tc is num ? tc.toInt() : int.tryParse('$tc') ?? 0;
          }
          if (n <= 0 && data['bookedToday'] == true) {
            n = 1;
          }
          if (n > 0) out[id] = n;
        }
      } catch (e) {
        if (kDebugMode) {
          print('[AccommodationOccupancy] fetchTodayCounts batch: $e');
        }
      }
    }

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
          if (st == statusPaid || st == statusReserved) {
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
        if (st == statusPaid || st == statusReleased) return;
        if (st != statusReserved) return;

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

        DateTime? parseDay(String s) {
          try {
            return _dayFmt.parseStrict(s.trim());
          } catch (_) {
            return null;
          }
        }

        final cin = parseDay(checkInRaw);
        final cout = parseDay(checkOutRaw);
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
