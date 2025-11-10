// lib/Pages/address.dart  (Vero Courier)
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// ---- Brand (file-level so all widgets can use these) ----
const Color kBrandOrange = Color(0xFFFF8A00);
const Color kBrandSoft   = Color(0xFFFFE8CC);

class UtilityPage extends StatefulWidget {
  const UtilityPage({super.key});

  @override
  State<UtilityPage> createState() => _UtilityPageState();
}

class _UtilityPageState extends State<UtilityPage> {
  // ---- Lilongwe geofence ----
  static final LatLng _lilongweCenter = LatLng(-13.9626, 33.7741);
  static const double _llRadiusKm = 60;

  // ---- Google Map state ----
  GoogleMapController? _map;
  static final CameraPosition _initialCamera =
      const CameraPosition(target: LatLng(-14.3, 34.3), zoom: 6.8); // Malawi fallback

  // ---- Device location banner info ----
  LatLng? _myLatLng;
  bool _locating = true;

  // ---- Local (Lilongwe) mode: pickup + dropoff pins ----
  LatLng? _pickup;
  LatLng? _dropoff;
  bool _pickingPickup = false;
  bool _pickingDropoff = false;

  // Vehicle options for local courier (bike/car/van)
  static const List<_Vehicle> _vehicles = [
    _Vehicle(id: 'bike', label: 'Bike', note: 'Small parcels', base: 2500, perKm: 500),
    _Vehicle(id: 'car', label: 'Car', note: 'Medium loads', base: 4000, perKm: 800),
    _Vehicle(id: 'van', label: 'Van', note: 'Bulk items', base: 7000, perKm: 1200),
  ];
  _Vehicle _vehicle = _vehicles.first;

  // ---- Inter-district mode ----
  final TextEditingController _destDistrictCtrl = TextEditingController();
  final TextEditingController _destAddressCtrl  = TextEditingController();
  String _courier = 'Speed Courier';
  static const List<String> _couriers = [
    'Speed Courier',
    'CTS Courier',
    'Ankolo Courier',
    'VIP Courier',
  ];

  // ---- Mode toggle ----
  _Mode _mode = _Mode.local;

  // Markers
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _destDistrictCtrl.dispose();
    _destAddressCtrl.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locating = false);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _locating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final me = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _myLatLng = me;
        _locating = false;
      });
      await _map?.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: me, zoom: 13.5)),
      );
    } catch (_) {
      setState(() => _locating = false);
    }
  }

  // --- Map handlers ---
  void _onMapCreated(GoogleMapController c) => _map = c;

  void _onMapTap(LatLng latLng) {
    if (_mode == _Mode.local) {
      if (_pickingPickup) {
        setState(() {
          _pickup = latLng;
          _pickingPickup = false;
        });
      } else if (_pickingDropoff) {
        setState(() {
          _dropoff = latLng;
          _pickingDropoff = false;
        });
      }
      _refreshMarkers();
    } else {
      // Inter-district: only pickup in Lilongwe
      if (_pickingPickup) {
        setState(() {
          _pickup = latLng;
          _pickingPickup = false;
        });
        _refreshMarkers();
      }
    }
  }

  void _refreshMarkers() {
    final m = <Marker>{};
    if (_myLatLng != null) {
      m.add(Marker(
        markerId: const MarkerId('me'),
        position: _myLatLng!,
        infoWindow: const InfoWindow(title: 'You are here'),
      ));
    }
    if (_pickup != null) {
      m.add(Marker(
        markerId: const MarkerId('pickup'),
        position: _pickup!,
        infoWindow: const InfoWindow(title: 'Pickup'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }
    if (_mode == _Mode.local && _dropoff != null) {
      m.add(Marker(
        markerId: const MarkerId('dropoff'),
        position: _dropoff!,
        infoWindow: const InfoWindow(title: 'Drop-off'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }
    setState(() {
      _markers
        ..clear()
        ..addAll(m);
    });
  }

  // --- Distance helpers (Haversine) ---
  static double _kmBetween(LatLng a, LatLng b) {
    const R = 6371.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLng = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return R * c;
  }

  static double _deg2rad(double d) => d * math.pi / 180.0;
  static bool _withinKm(LatLng p, LatLng center, double km) => _kmBetween(p, center) <= km;

  bool _insideLilongwe(LatLng p) => _withinKm(p, _lilongweCenter, _llRadiusKm);

  // --- Fare for local deliveries ---
  double? _localFare() {
    if (_pickup == null || _dropoff == null) return null;
    if (!(_insideLilongwe(_pickup!) && _insideLilongwe(_dropoff!))) return null;
    final km = _kmBetween(_pickup!, _dropoff!);
    return _vehicle.base + _vehicle.perKm * km;
  }

  // --- Actions ---
  void _bookLocal() {
    if (_pickup == null) return _toast('Set a pickup location (tap Pick on Map).');
    if (_dropoff == null) return _toast('Set a drop-off location (tap Pick on Map).');
    if (!(_insideLilongwe(_pickup!) && _insideLilongwe(_dropoff!))) {
      return _toast('Local Vero Courier is Lilongwe-only. Keep both pins inside Lilongwe.');
    }
    final fare = _localFare();
    // TODO: POST to backend: mode=local, pickupLatLng, dropoffLatLng, vehicleId, fareEstimate
    _toast('Request sent! ${_vehicle.label} booked in Lilongwe'
        '${fare != null ? ' • Est: MWK ${_fmtMoney(fare)}' : ''}.');
  }

  void _bookIntercity() {
    if (_pickup == null) return _toast('Set a pickup location in Lilongwe.');
    if (!_insideLilongwe(_pickup!)) {
      return _toast('Pickup must be within Lilongwe for inter-district shipments.');
    }
    if (_destDistrictCtrl.text.trim().isEmpty) {
      return _toast('Enter the destination district (outside Lilongwe).');
    }
    // TODO: POST to backend: mode=intercity, pickupLatLng, destDistrict, destAddress, courier
    _toast('Inter-district via $_courier submitted to ${_destDistrictCtrl.text.trim()}.');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.black87,
    ));
  }

  // --- Styles/helpers ---
  static ButtonStyle _btnStyle({double padV = 12}) => FilledButton.styleFrom(
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: padV),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      );

  static InputDecoration _inputDecoration() => const InputDecoration(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.black, width: 1), // black before active
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: kBrandOrange, width: 2),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  static String _fmtMoney(double n) {
    final s = n.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final fare = _localFare();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vero Courier'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCamera,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: _onMapCreated,
            onTap: _onMapTap,
            markers: _markers,
            zoomControlsEnabled: false,
          ),

          // Top banner (now defined below)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _ServiceBanner(
                locating: _locating,
                text: 'Local deliveries available in Lilongwe. '
                    'For other districts, use partner couriers.',
                okColor: const Color(0xFFE8FFF0),
              ),
            ),
          ),

          // Bottom sheet controls
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(blurRadius: 20, color: Colors.black26, offset: Offset(0, -6))],
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Grip
                      Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Mode toggle
                      Row(
                        children: [
                          _ModeChip(
                            label: 'Lilongwe (Local)',
                            selected: _mode == _Mode.local,
                            onTap: () => setState(() => _mode = _Mode.local),
                          ),
                          const SizedBox(width: 8),
                          _ModeChip(
                            label: 'Other Districts',
                            selected: _mode == _Mode.intercity,
                            onTap: () => setState(() => _mode = _Mode.intercity),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (_mode == _Mode.local) ...[
                        _Labeled(
                          label: 'Pickup (pin on map)',
                          child: Row(
                            children: [
                              Expanded(
                                child: _PinnedReadout(
                                  value: _pickup == null
                                      ? null
                                      : 'Lat ${_pickup!.latitude.toStringAsFixed(5)}, '
                                        'Lng ${_pickup!.longitude.toStringAsFixed(5)}',
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                style: _btnStyle(),
                                onPressed: () {
                                  setState(() {
                                    _pickingPickup = true;
                                    _pickingDropoff = false;
                                  });
                                  _map?.animateCamera(
                                    CameraUpdate.newLatLngZoom(_lilongweCenter, 13.0),
                                  );
                                },
                                child: Text(_pickingPickup ? 'Cancel' : 'Pick on Map'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        _Labeled(
                          label: 'Drop-off (pin on map)',
                          child: Row(
                            children: [
                              Expanded(
                                child: _PinnedReadout(
                                  value: _dropoff == null
                                      ? null
                                      : 'Lat ${_dropoff!.latitude.toStringAsFixed(5)}, '
                                        'Lng ${_dropoff!.longitude.toStringAsFixed(5)}',
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                style: _btnStyle(),
                                onPressed: () {
                                  setState(() {
                                    _pickingDropoff = true;
                                    _pickingPickup = false;
                                  });
                                  _map?.animateCamera(
                                    CameraUpdate.newLatLngZoom(_lilongweCenter, 13.0),
                                  );
                                },
                                child: Text(_pickingDropoff ? 'Cancel' : 'Pick on Map'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Vehicle selection
                        _Labeled(
                          label: 'Vehicle',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _vehicles.map((v) {
                              final selected = v.id == _vehicle.id;
                              return InkWell(
                                onTap: () => setState(() => _vehicle = v),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected ? kBrandOrange : Colors.black,
                                      width: 1,
                                    ),
                                    color: selected ? kBrandSoft : Colors.white,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.local_shipping,
                                          size: 18,
                                          color: selected ? kBrandOrange : Colors.black87),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${v.label} • ${v.note}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: selected ? Colors.black : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Fare estimate
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                            color: const Color(0xFFF8F8F8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.attach_money_rounded),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  (_pickup == null || _dropoff == null)
                                      ? 'Set pickup & drop-off to see estimate.'
                                      : (_insideLilongwe(_pickup!) &&
                                             _insideLilongwe(_dropoff!) &&
                                             fare != null)
                                        ? 'Estimated fare: MWK ${_fmtMoney(fare)}'
                                        : 'Both locations must be inside Lilongwe.',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: _btnStyle(padV: 14),
                            onPressed: _bookLocal,
                            child: const Text('Book Local Delivery'),
                          ),
                        ),
                      ] else ...[
                        _Labeled(
                          label: 'Pickup in Lilongwe (pin on map)',
                          child: Row(
                            children: [
                              Expanded(
                                child: _PinnedReadout(
                                  value: _pickup == null
                                      ? null
                                      : 'Lat ${_pickup!.latitude.toStringAsFixed(5)}, '
                                        'Lng ${_pickup!.longitude.toStringAsFixed(5)}',
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                style: _btnStyle(),
                                onPressed: () {
                                  setState(() {
                                    _pickingPickup = true;
                                    _pickingDropoff = false;
                                  });
                                  _map?.animateCamera(
                                    CameraUpdate.newLatLngZoom(_lilongweCenter, 13.0),
                                  );
                                },
                                child: Text(_pickingPickup ? 'Cancel' : 'Pick on Map'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        _Labeled(
                          label: 'Destination District (outside Lilongwe)',
                          child: TextField(
                            controller: _destDistrictCtrl,
                            decoration: _inputDecoration().copyWith(
                              hintText: 'e.g., Mzimba, Zomba, Karonga…',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        _Labeled(
                          label: 'Destination Address (optional details)',
                          child: TextField(
                            controller: _destAddressCtrl,
                            decoration: _inputDecoration().copyWith(
                              hintText: 'Street, contact name & phone…',
                            ),
                            maxLines: 2,
                          ),
                        ),
                        const SizedBox(height: 12),

                        _Labeled(
                          label: 'Courier Partner',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _couriers.map((name) {
                              final selected = _courier == name;
                              return InkWell(
                                onTap: () => setState(() => _courier = name),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected ? kBrandOrange : Colors.black,
                                      width: 1,
                                    ),
                                    color: selected ? kBrandSoft : Colors.white,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.local_post_office,
                                          size: 18,
                                          color: selected ? kBrandOrange : Colors.black87),
                                      const SizedBox(width: 6),
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: selected ? Colors.black : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 14),

                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: _btnStyle(padV: 14),
                            onPressed: _bookIntercity,
                            child: const Text('Send to Other District'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Overlay helper when picking on map
          if (_pickingPickup || _pickingDropoff)
            IgnorePointer(
              ignoring: true,
              child: Container(
                alignment: Alignment.topCenter,
                margin: const EdgeInsets.only(top: 90),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _pickingPickup
                        ? 'Tap on the map to set PICKUP (Lilongwe)'
                        : 'Tap on the map to set DROP-OFF (Lilongwe)',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Small widgets & models ---

class _ServiceBanner extends StatelessWidget {
  final bool locating;
  final String text;
  final Color okColor;
  const _ServiceBanner({
    required this.locating,
    required this.text,
    required this.okColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: okColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB8E6C5)),
      ),
      child: Row(
        children: [
          Icon(
            locating ? Icons.my_location : Icons.check_circle,
            color: locating ? Colors.black54 : const Color(0xFF1B8F3E),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              locating ? 'Detecting your location…' : text,
              style: TextStyle(
                color: locating ? Colors.black87 : const Color(0xFF0A5730),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kBrandSoft : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? kBrandOrange : Colors.black,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.black : Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labeled({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _PinnedReadout extends StatelessWidget {
  final String? value;
  const _PinnedReadout({this.value});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
        color: Colors.white,
      ),
      child: Text(
        value ?? 'Tap "Pick on Map" and place a pin',
        style: TextStyle(color: value == null ? Colors.black54 : Colors.black),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _Vehicle {
  final String id;
  final String label;
  final String note;
  final double base;
  final double perKm;
  const _Vehicle({
    required this.id,
    required this.label,
    required this.note,
    required this.base,
    required this.perKm,
  });
}

enum _Mode { local, intercity }
