// lib/Pages/address.dart (or wherever you keep it)
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

// ↓ These two imports are required for the Google Maps + location types
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class Airportpickuppage extends StatefulWidget {
  const Airportpickuppage({super.key});

  @override
  State<Airportpickuppage> createState() => _AirportpickuppageState();
}

class _AirportpickuppageState extends State<Airportpickuppage> {
  // ---- Brand colors (kept orange) ----
  static const _brandOrange = Color(0xFFFF8A00);
  static const _brandSoft = Color(0xFFFFE8CC);

  // ---- City centers + service geofence (km) ----
  static final LatLng _lilongweCenter = LatLng(-13.9626, 33.7741);
  static final LatLng _blantyreCenter = LatLng(-15.7861, 35.0058);
  static const double _cityRadiusKm = 60;

  // ---- Airports (final, not const because LatLng isn’t const) ----
  static final _Airport _kia = _Airport(
    code: 'LLW',
    name: 'Kamuzu International Airport',
    city: 'Lilongwe',
    position: LatLng(-13.7894, 33.7800),
  );

  static final _Airport _chileka = _Airport(
    code: 'BTZ',
    name: 'Chileka International Airport',
    city: 'Blantyre',
    position: LatLng(-15.6740, 34.9730),
  );

  static final List<_Airport> _allAirports = [_kia, _chileka];

  // ---- Vehicle options & simple fare model ----
  static const List<_Vehicle> _vehicles = [
    _Vehicle(id: 'standard', label: 'Standard', seats: 4, base: 5000, perKm: 750),
    _Vehicle(id: 'van', label: 'Van', seats: 6, base: 8000, perKm: 1000),
    _Vehicle(id: 'executive', label: 'Executive', seats: 4, base: 12000, perKm: 1500),
  ];

  // ---- State ----
  GoogleMapController? _map;
  LatLng? _myLatLng;
  String? _serviceCity; // 'Lilongwe' | 'Blantyre' | null (restricted)
  bool _locating = true;
  bool _isPickingDropoff = false;

  _Airport? _selectedAirport;
  LatLng? _dropoff;
  _Vehicle _vehicle = _vehicles.first;

  final Set<Marker> _markers = {};

  static final CameraPosition _initialCamera =
      CameraPosition(target: LatLng(-14.3, 34.3), zoom: 6.8); // Malawi fallback

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setOutsideOrUnknownLocation();
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _setOutsideOrUnknownLocation();
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final current = LatLng(pos.latitude, pos.longitude);

      final inLL = _withinKm(current, _lilongweCenter, _cityRadiusKm);
      final inBT = _withinKm(current, _blantyreCenter, _cityRadiusKm);

      String? city;
      if (inLL) city = 'Lilongwe';
      if (inBT) city = 'Blantyre';
      if (inLL && inBT) {
        final dLL = _kmBetween(current, _lilongweCenter);
        final dBT = _kmBetween(current, _blantyreCenter);
        city = dLL <= dBT ? 'Lilongwe' : 'Blantyre';
      }

      setState(() {
        _myLatLng = current;
        _serviceCity = city;
        _locating = false;
      });

      await _map?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: current, zoom: 13.5),
      ));

      if (_serviceCity == 'Lilongwe') _onAirportChanged(_kia);
      if (_serviceCity == 'Blantyre') _onAirportChanged(_chileka);
    } catch (_) {
      _setOutsideOrUnknownLocation();
    }
  }

  void _setOutsideOrUnknownLocation() {
    setState(() {
      _locating = false;
      _myLatLng = null;
      _serviceCity = null; // outside supported cities
    });
  }

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
  static bool _withinKm(LatLng p, LatLng c, double km) => _kmBetween(p, c) <= km;

  void _onMapCreated(GoogleMapController c) => _map = c;

  void _onAirportChanged(_Airport? airport) async {
    setState(() => _selectedAirport = airport);
    _refreshMarkers();
    if (airport != null) {
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(airport.position, 13.5));
    }
  }

  void _onPickDropoffToggle() {
    setState(() => _isPickingDropoff = !_isPickingDropoff);
    if (_isPickingDropoff && _selectedAirport != null) {
      _map?.animateCamera(CameraUpdate.newLatLngZoom(_selectedAirport!.position, 13.5));
    }
  }

  void _onMapTap(LatLng latLng) {
    if (_isPickingDropoff) {
      setState(() {
        _dropoff = latLng;
        _isPickingDropoff = false;
      });
      _refreshMarkers();
    }
  }

  void _refreshMarkers() {
    final markers = <Marker>{};

    if (_myLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('me'),
        position: _myLatLng!,
        infoWindow: const InfoWindow(title: 'You are here'),
      ));
    }

    if (_selectedAirport != null) {
      markers.add(Marker(
        markerId: const MarkerId('airport'),
        position: _selectedAirport!.position,
        infoWindow: InfoWindow(title: _selectedAirport!.name),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ));
    }

    if (_dropoff != null) {
      markers.add(Marker(
        markerId: const MarkerId('dropoff'),
        position: _dropoff!,
        infoWindow: const InfoWindow(title: 'Drop-off'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }

    setState(() {
      _markers
        ..clear()
        ..addAll(markers);
    });
  }

  double? _estimatedFare() {
    if (_selectedAirport == null || _dropoff == null) return null;
    final km = _kmBetween(_selectedAirport!.position, _dropoff!);
    final v = _vehicle;
    return v.base + v.perKm * km;
  }

  void _bookNow() {
    if (_serviceCity == null) {
      _toast("Airport Pickup is only available in Lilongwe & Blantyre.");
      return;
    }
    if (_selectedAirport == null) {
      _toast("Select your pickup airport.");
      return;
    }
    if (_dropoff == null) {
      _toast("Set your drop-off location on the map.");
      return;
    }

    // TODO: call your NestJS backend here
    _toast("Request sent! ${_vehicle.label} from ${_selectedAirport!.code} is on the way.");
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.black87,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final insideService = _serviceCity != null;
    final airportsForCity = switch (_serviceCity) {
      'Lilongwe' => [_kia],
      'Blantyre' => [_chileka],
      _ => _allAirports, // show both if unknown; booking still restricted
    };

    final fare = _estimatedFare();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Airport Pickup'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCamera,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _markers,
            onMapCreated: _onMapCreated,
            onTap: _onMapTap,
            zoomControlsEnabled: false,
            compassEnabled: false,
          ),

          // Top banner
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _ServiceBanner(
                locating: _locating,
                insideService: insideService,
                city: _serviceCity,
              ),
            ),
          ),

          // Bottom controls
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    const SizedBox(height: 12),

                    _Labeled(
                      label: 'Pickup Airport',
                      child: DropdownButtonFormField<_Airport>(
                        value: airportsForCity.contains(_selectedAirport) ? _selectedAirport : null,
                        items: airportsForCity
                            .map((a) => DropdownMenuItem(
                                  value: a,
                                  child: Text('${a.name} (${a.code})'),
                                ))
                            .toList(),
                        decoration: _inputDecoration(),
                        onChanged: _onAirportChanged,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _Labeled(
                      label: 'Drop-off Location',
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 48,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black, width: 1), // black before active
                                color: Colors.white,
                              ),
                              child: Text(
                                _dropoff == null
                                    ? 'Tap "Pick on Map" and place a pin'
                                    : 'Lat: ${_dropoff!.latitude.toStringAsFixed(5)}, Lng: ${_dropoff!.longitude.toStringAsFixed(5)}',
                                style: TextStyle(color: _dropoff == null ? Colors.black54 : Colors.black),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _brandOrange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            onPressed: _onPickDropoffToggle,
                            child: Text(_isPickingDropoff ? 'Cancel' : 'Pick on Map'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

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
                                border: Border.all(color: selected ? _brandOrange : Colors.black, width: 1),
                                color: selected ? _brandSoft : Colors.white,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.directions_car_filled,
                                      size: 18, color: selected ? _brandOrange : Colors.black87),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${v.label} • ${v.seats} seats',
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
                              fare == null
                                  ? 'Fare estimate appears after airport & drop-off are set.'
                                  : 'Estimated fare: MWK ${_fmtMoney(fare)}',
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
                        style: FilledButton.styleFrom(
                          backgroundColor: _brandOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        onPressed: _bookNow,
                        child: const Text('Book Pickup'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_serviceCity != null)
                      Text('Service city: $_serviceCity', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),

          if (_isPickingDropoff)
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
                  child: const Text(
                    'Tap on the map to set your drop-off location',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static InputDecoration _inputDecoration() => InputDecoration(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.black, width: 1), // black border before active
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: _brandOrange, width: 2),
          borderRadius: BorderRadius.circular(12),
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
}

// --- Small widgets + models ---

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

class _ServiceBanner extends StatelessWidget {
  final bool locating;
  final bool insideService;
  final String? city;
  const _ServiceBanner({required this.locating, required this.insideService, required this.city});

  @override
  Widget build(BuildContext context) {
    final ok = insideService;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFE8FFF0) : const Color(0xFFFFEFEF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ok ? const Color(0xFFB8E6C5) : const Color(0xFFFFC9C9)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.info_outline,
              color: ok ? const Color(0xFF1B8F3E) : const Color(0xFFB3261E)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              locating
                  ? 'Detecting your location…'
                  : ok
                      ? 'You’re in $city — Airport Pickup available.'
                      : 'Airport Pickup is only available in Lilongwe & Blantyre.',
              style: TextStyle(
                color: ok ? const Color(0xFF0A5730) : const Color(0xFF7D1410),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Airport {
  final String code;
  final String name;
  final String city;
  final LatLng position;
  const _Airport({required this.code, required this.name, required this.city, required this.position});
}

class _Vehicle {
  final String id;
  final String label;
  final int seats;
  final double base;
  final double perKm;
  const _Vehicle({
    required this.id,
    required this.label,
    required this.seats,
    required this.base,
    required this.perKm,
  });
}
