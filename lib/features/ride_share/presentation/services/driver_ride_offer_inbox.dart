import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/driver_request_service.dart';

/// Bridges FCM / cold-start payloads into the same in-app ride-offer flow as WebSocket.
class DriverRideOfferInbox {
  DriverRideOfferInbox._();
  static final DriverRideOfferInbox instance = DriverRideOfferInbox._();

  static const pendingPrefsKey = 'pending_driver_ride_offer';

  final _controller = StreamController<DriverRideRequest>.broadcast();

  Stream<DriverRideRequest> get offers => _controller.stream;

  /// Publish an offer for [RideRequestOverlay] (dedupe happens in the overlay).
  void publish(DriverRideRequest request) {
    if (request.id.isEmpty) return;
    if (!_controller.isClosed) {
      _controller.add(request);
    }
  }

  /// Resolve FCM/data map → [DriverRideRequest], then publish for in-app UI.
  Future<DriverRideRequest?> ingestFcm(
    Map<String, dynamic> data, {
    bool publishToOverlay = true,
  }) async {
    final request = await resolveFromPayload(data);
    if (request == null) return null;
    if (publishToOverlay) publish(request);
    return request;
  }

  Future<DriverRideRequest?> resolveFromPayload(
    Map<String, dynamic> data,
  ) async {
    final rideId = (data['rideId'] ?? data['id'] ?? '').toString().trim();
    if (rideId.isEmpty) return null;

    try {
      final fetched = await DriverRequestService.getRideRequest(rideId);
      if (fetched != null) {
        final taxiId = _parseInt(data['taxiId'] ?? data['candidateTaxiId']);
        if (taxiId != null && fetched.candidateTaxiId == null) {
          return fetched.copyWith(candidateTaxiId: taxiId);
        }
        return fetched;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DriverRideOfferInbox] fetch ride $rideId failed: $e');
      }
    }

    return fromFcmMap(data);
  }

  static DriverRideRequest? fromFcmMap(Map<String, dynamic> data) {
    final rideId = (data['rideId'] ?? data['id'] ?? '').toString().trim();
    if (rideId.isEmpty) return null;

    double d(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    return DriverRideRequest(
      id: rideId,
      passengerId: (data['passengerId'] ?? '').toString(),
      passengerName: (data['passengerName'] as String?)?.trim().isNotEmpty == true
          ? data['passengerName'].toString()
          : 'Passenger',
      pickupLat: d(data['pickupLatitude'] ?? data['pickupLat']),
      pickupLng: d(data['pickupLongitude'] ?? data['pickupLng']),
      dropoffLat: d(data['dropoffLatitude'] ?? data['dropoffLat']),
      dropoffLng: d(data['dropoffLongitude'] ?? data['dropoffLng']),
      pickupAddress: (data['pickupAddress'] as String?)?.trim().isNotEmpty == true
          ? data['pickupAddress'].toString()
          : 'Pickup Location',
      dropoffAddress: (data['dropoffAddress'] as String?) ?? '',
      status: 'pending',
      createdAt: DateTime.now(),
      estimatedTime: 0,
      estimatedDistance: d(data['estimatedDistance']),
      estimatedFare: d(data['estimatedFare']),
      passengerPhone: data['passengerPhone']?.toString(),
      candidateTaxiId: _parseInt(data['taxiId'] ?? data['candidateTaxiId']),
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  Future<void> persistPendingOffer(Map<String, dynamic> data) async {
    final rideId = (data['rideId'] ?? '').toString().trim();
    if (rideId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(pendingPrefsKey, jsonEncode(data));
    } catch (_) {}
  }

  /// Consume a cold-start / background-stored offer (clears prefs).
  Future<Map<String, dynamic>?> takePendingOffer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(pendingPrefsKey);
      if (raw == null || raw.isEmpty) return null;
      await prefs.remove(pendingPrefsKey);
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }
}
