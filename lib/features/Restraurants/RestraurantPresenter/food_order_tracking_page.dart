import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:vero360_app/features/Restraurants/Models/food_order_model.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/restaurant_service.dart';
import 'package:vero360_app/features/VeroCourier/Model/courier.models.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/courier_widgets.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierService/vero_courier_service.dart';

const Color _veroOrange = Color(0xFFFF8A00);
const Color _ink = Color(0xFF1A1109);

/// Live map + Vero Courier status for a paid food order.
class FoodOrderTrackingPage extends StatefulWidget {
  const FoodOrderTrackingPage({super.key, required this.orderId});

  final String orderId;

  @override
  State<FoodOrderTrackingPage> createState() => _FoodOrderTrackingPageState();
}

class _FoodOrderTrackingPageState extends State<FoodOrderTrackingPage> {
  final _courier = const CourierService();
  GoogleMapController? _map;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _orderSub;
  FoodOrder? _order;
  CourierDelivery? _courierJob;
  Timer? _poll;
  LatLng? _pickup;
  bool _pickupLoaded = false;
  String _lastCourierQuery = '';

  @override
  void initState() {
    super.initState();
    _orderSub = FirebaseFirestore.instance
        .collection('food_orders')
        .doc(widget.orderId)
        .snapshots()
        .listen(_onOrder);
    _poll = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(_refreshCourier());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _orderSub?.cancel();
    _map?.dispose();
    super.dispose();
  }

  void _onOrder(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists) {
      if (mounted) setState(() => _order = null);
      return;
    }
    final order = FoodOrder.fromFirestore(snap);
    setState(() => _order = order);
    if (!_pickupLoaded) {
      _pickupLoaded = true;
      unawaited(_loadPickup(order, snap.data() ?? const {}));
    }
    unawaited(_refreshCourier(order: order));
  }

  Future<void> _loadPickup(
    FoodOrder order,
    Map<String, dynamic> data,
  ) async {
    try {
      final plat = _asDouble(data['pickupLat']);
      final plng = _asDouble(data['pickupLng']);
      if (plat != null && plng != null) {
        if (mounted) setState(() => _pickup = LatLng(plat, plng));
        return;
      }
      final rest = order.restaurantId.trim().isNotEmpty
          ? await RestaurantService().fetchRestaurantById(order.restaurantId)
          : await RestaurantService()
              .fetchRestaurantByOwnerUid(order.merchantId);
      if (!mounted) return;
      if (rest?.latitude != null && rest?.longitude != null) {
        setState(() => _pickup = LatLng(rest!.latitude!, rest.longitude!));
      }
    } catch (_) {}
  }

  Future<void> _refreshCourier({FoodOrder? order}) async {
    final o = order ?? _order;
    final code = (o?.courierTrackingNumber ?? '').trim();
    final id = o?.courierDeliveryId ?? _courierJob?.courierId;
    final query = code.isNotEmpty ? code : '${id ?? ''}';
    if (query.isEmpty) return;
    if (query == _lastCourierQuery && _courierJob != null && order == null) {
      // Timer tick with same code — still refresh for status.
    }
    _lastCourierQuery = query;
    try {
      final latest = code.isNotEmpty
          ? await _courier.getDeliveryByTrackingNumber(code)
          : await _courier.getDeliveryById(id!);
      if (!mounted) return;
      setState(() => _courierJob = latest);
    } catch (_) {}
  }

  Future<void> _fitMap(LatLng? dropoff) async {
    final map = _map;
    if (map == null) return;
    final points = <LatLng>[
      if (dropoff != null) dropoff,
      if (_pickup != null) _pickup!,
    ];
    if (points.isEmpty) return;
    if (points.length == 1) {
      await map.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: points.first, zoom: 17.2),
        ),
      );
      return;
    }
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    await map.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        72,
      ),
    );
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String _statusLine(FoodOrder order) {
    final kitchen = order.status.toLowerCase();
    final courier = _courierJob?.status;
    if (kitchen == 'cancelled') return 'Order cancelled';
    if (kitchen == 'delivered' || kitchen == 'completed') {
      return 'Delivered';
    }
    if (courier == CourierStatus.delivered) return 'Courier marked delivered';
    if (courier == CourierStatus.onTheWay) return 'Vero Courier is on the way';
    if (courier == CourierStatus.accepted) {
      return 'Courier accepted — heading to the kitchen';
    }
    if (kitchen == 'ready') return 'Ready — waiting for Vero Courier';
    if (kitchen == 'preparing') return 'Kitchen is preparing your order';
    return 'Order received';
  }

  String _statusDisplay(CourierStatus status) {
    switch (status) {
      case CourierStatus.accepted:
        return 'Accepted';
      case CourierStatus.onTheWay:
        return 'On the way';
      case CourierStatus.delivered:
        return 'Delivered';
      case CourierStatus.cancelled:
        return 'Cancelled';
      case CourierStatus.pending:
        return 'Looking for a courier';
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    if (order == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _ink,
          elevation: 0,
          title: const Text(
            'Track food',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: _veroOrange),
        ),
      );
    }

    final dropoff =
        (order.deliveryLat != null && order.deliveryLng != null)
            ? LatLng(order.deliveryLat!, order.deliveryLng!)
            : null;
    final markers = <Marker>{
      if (dropoff != null)
        Marker(
          markerId: const MarkerId('dropoff'),
          position: dropoff,
          infoWindow: const InfoWindow(title: 'Your pin'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
        ),
      if (_pickup != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickup!,
          infoWindow: InfoWindow(
            title: order.restaurantName.trim().isEmpty
                ? 'Kitchen'
                : order.restaurantName.trim(),
          ),
        ),
    };
    final mapTarget = dropoff ?? _pickup ?? const LatLng(-15.7861, 35.0058);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text(
          'Track food',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: mapTarget,
                zoom: dropoff != null ? 17.2 : 13,
              ),
              mapType: MapType.hybrid,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
              markers: markers,
              onMapCreated: (c) {
                _map = c;
                unawaited(_fitMap(dropoff));
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              18,
              16,
              18,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 16,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _statusLine(order),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  order.courierTrackingNumber.trim().isEmpty
                      ? 'Vero Courier · tracking appears when the kitchen marks ready'
                      : 'Vero Courier · ${order.courierTrackingNumber.trim()}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _ink.withValues(alpha: 0.6),
                  ),
                ),
                if (_courierJob != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _statusDisplay(_courierJob!.status),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: courierStatusTextColor(
                        _courierJob!.status,
                        Theme.of(context).colorScheme,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  order.deliveryAddress.trim().isEmpty
                      ? 'No address on this order'
                      : order.deliveryAddress.trim(),
                  style: TextStyle(
                    height: 1.35,
                    color: _ink.withValues(alpha: 0.7),
                  ),
                ),
                if (dropoff != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${dropoff.latitude.toStringAsFixed(5)}, ${dropoff.longitude.toStringAsFixed(5)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _ink.withValues(alpha: 0.45),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _fitMap(dropoff),
                    style: FilledButton.styleFrom(
                      backgroundColor: _veroOrange,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.my_location_rounded),
                    label: const Text(
                      'Center on my pin',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
