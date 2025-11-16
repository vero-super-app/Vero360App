// lib/Pages/airport_pickup_page.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/models/Airport_pickup.models.dart';

import 'package:vero360_app/services/airport_pickup_service.dart';
import 'package:vero360_app/services/api_exception.dart';

class Airportpickuppage extends StatefulWidget {
  const Airportpickuppage({super.key});

  @override
  State<Airportpickuppage> createState() => _AirportpickuppageState();
}

class _AirportpickuppageState extends State<Airportpickuppage> {
  static const _brandOrange = Color(0xFFFF8A00);
  static const _brandSoft = Color(0xFFFFE8CC);

  // City centers + service radius
  static final LatLng _lilongweCenter = LatLng(-13.9626, 33.7741);
  static final LatLng _blantyreCenter = LatLng(-15.7861, 35.0058);
  static const double _cityRadiusKm = 60;

  // Airports
  static final _Airport _kia = _Airport(
    code: 'LLW',
    name: 'Kamuzu International Airport',
    city: 'Lilongwe',
    position: const LatLng(-13.7894, 33.7800),
  );

  static final _Airport _chileka = _Airport(
    code: 'BTZ',
    name: 'Chileka International Airport',
    city: 'Blantyre',
    position: const LatLng(-15.6740, 34.9730),
  );

  static final List<_Airport> _allAirports = [_kia, _chileka];

  // Vehicles
  static const List<_Vehicle> _vehicles = [
    _Vehicle(
      id: 'standard',
      label: 'Standard Car',
      seats: 4,
      base: 5000,
      perKm: 1,
    ),
    _Vehicle(
      id: 'executive',
      label: 'Executive car',
      seats: 4,
      base: 12000,
      perKm: 1500,
    ),
  ];

  // Map + state
  GoogleMapController? _map;
  static final CameraPosition _initialCamera = const CameraPosition(
      target: LatLng(-14.3, 34.3), zoom: 6.8); // Malawi fallback

  LatLng? _myLatLng;
  String? _serviceCity; // Lilongwe / Blantyre / null
  bool _locating = true;
  bool _isPickingDropoff = false;
  bool _submitting = false;

  _Airport? _selectedAirport;
  LatLng? _dropoff;
  _Vehicle _vehicle = _vehicles.first;

  final Set<Marker> _markers = {};

  // Form fields
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _destAddressCtrl = TextEditingController();

  final _airportService = const AirportPickupService();

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _map?.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _destAddressCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Location + service city detection
  // ---------------------------------------------------------------------------
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
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _setOutsideOrUnknownLocation();
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
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

      await _map?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: current, zoom: 13.5),
        ),
      );

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
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return R * c;
  }

  static double _deg2rad(double d) => d * math.pi / 180.0;
  static bool _withinKm(LatLng p, LatLng c, double km) =>
      _kmBetween(p, c) <= km;

  void _onMapCreated(GoogleMapController c) => _map = c;

  // ---------------------------------------------------------------------------
  // Map interactions
  // ---------------------------------------------------------------------------
  void _onAirportChanged(_Airport? airport) async {
    setState(() => _selectedAirport = airport);
    _refreshMarkers();
    if (airport != null) {
      await _map?.animateCamera(
        CameraUpdate.newLatLngZoom(airport.position, 13.5),
      );
    }
  }

  void _onPickDropoffToggle() {
    setState(() => _isPickingDropoff = !_isPickingDropoff);
    if (_isPickingDropoff && _selectedAirport != null) {
      _map?.animateCamera(
        CameraUpdate.newLatLngZoom(_selectedAirport!.position, 13.5),
      );
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
      markers.add(
        Marker(
          markerId: const MarkerId('me'),
          position: _myLatLng!,
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
      );
    }

    if (_selectedAirport != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('airport'),
          position: _selectedAirport!.position,
          infoWindow: InfoWindow(title: _selectedAirport!.name),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
        ),
      );
    }

    if (_dropoff != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: _dropoff!,
          infoWindow: const InfoWindow(title: 'Drop-off (Destination)'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
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

  // ---------------------------------------------------------------------------
  // Booking
  // ---------------------------------------------------------------------------
  Future<String?> _readToken() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString('jwt_token') ??
        sp.getString('token') ??
        sp.getString('jwt');
  }

  Future<void> _bookNow() async {
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

    if (!_formKey.currentState!.validate()) {
      _toast('Please fill all required fields.');
      return;
    }

    final token = await _readToken(); // may be null (guest)
    final fare = _estimatedFare();

    final payload = AirportPickupRequestPayload(
      airportCode: _selectedAirport!.code,
      serviceCity: _serviceCity!,
      dropoffLat: _dropoff!.latitude,
      dropoffLng: _dropoff!.longitude,
      vehicleId: _vehicle.id,
      clientFareEstimate: fare,
      dropoffAddressText: _destAddressCtrl.text.trim(),
      customerName: _nameCtrl.text.trim(),
      customerPhone: _phoneCtrl.text.trim(),
    );

    setState(() => _submitting = true);

    try {
      final booking = await _airportService.createBooking(
        payload,
        authToken: token, // optional
      );

      _toast(
        'Pickup booked from ${booking.airportCode} to ${booking.serviceCity}. Status: ${booking.status}',
      );
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not book pickup. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final insideService = _serviceCity != null;
    final airportsForCity = switch (_serviceCity) {
      'Lilongwe' => [_kia],
      'Blantyre' => [_chileka],
      _ => _allAirports,
    };

    final fare = _estimatedFare();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Airport Pickup'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ===================== MAP SECTION (TOP) =====================
          SizedBox(
            height: 260,
            child: Stack(
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
                // Legend
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Orange pin = Airport (Pickup)   •   Blue pin = Drop-off (Destination)',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                // Service banner at top of map
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
                // Hint overlay when choosing drop-off
                if (_isPickingDropoff)
                  IgnorePointer(
                    ignoring: true,
                    child: Container(
                      alignment: Alignment.topCenter,
                      margin: const EdgeInsets.only(top: 70),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
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
          ),

          // ===================== FORM SECTION (BOTTOM) =====================
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 12,
                    color: Colors.black26,
                    offset: Offset(0, -4),
                  )
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SafeArea(
                top: false,
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
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
                            value: airportsForCity.contains(_selectedAirport)
                                ? _selectedAirport
                                : null,
                            items: airportsForCity
                                .map(
                                  (a) => DropdownMenuItem(
                                    value: a,
                                    child: Text('${a.name} (${a.code})'),
                                  ),
                                )
                                .toList(),
                            decoration: _inputDecoration(),
                            onChanged: _onAirportChanged,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Labeled(
                          label: 'Destination on Map (Drop-off)',
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 48,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.black,
                                      width: 1,
                                    ),
                                    color: Colors.white,
                                  ),
                                  child: Text(
                                    _dropoff == null
                                        ? 'Tap "Pick on Map" above, then tap on the map'
                                        : 'Lat: ${_dropoff!.latitude.toStringAsFixed(5)}, '
                                            'Lng: ${_dropoff!.longitude.toStringAsFixed(5)}',
                                    style: TextStyle(
                                      color: _dropoff == null
                                          ? Colors.black54
                                          : Colors.black,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _brandOrange,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                ),
                                onPressed: _onPickDropoffToggle,
                                child: Text(
                                  _isPickingDropoff ? 'Cancel' : 'Pick on Map',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Labeled(
                          label: 'Your Name',
                          child: TextFormField(
                            controller: _nameCtrl,
                            decoration: _inputDecoration().copyWith(
                              hintText: 'Who should the driver ask for?',
                              suffixText: '*',
                              suffixStyle: const TextStyle(color: Colors.red),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Name is required'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Labeled(
                          label: 'Your Phone Number',
                          child: TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: _inputDecoration().copyWith(
                              hintText: 'e.g. +265 99 123 4567',
                              suffixText: '*',
                              suffixStyle: const TextStyle(color: Colors.red),
                            ),
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return 'Phone is required';
                              if (t.length < 7) {
                                return 'Enter a valid phone number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Labeled(
                          label: 'Destination Address (required details)',
                          child: TextFormField(
                            controller: _destAddressCtrl,
                            decoration: _inputDecoration().copyWith(
                              hintText:
                                  'Street / area, landmarks, gate color, etc.',
                              suffixText: '*',
                              suffixStyle: const TextStyle(color: Colors.red),
                            ),
                            maxLines: 2,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'This field is required'
                                : null,
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? _brandOrange
                                          : Colors.black,
                                      width: 1,
                                    ),
                                    color: selected ? _brandSoft : Colors.white,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.directions_car_filled,
                                        size: 18,
                                        color: selected
                                            ? _brandOrange
                                            : Colors.black87,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${v.label} • ${v.seats} seats',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: selected
                                              ? Colors.black
                                              : Colors.black87,
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
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
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: _submitting ? null : _bookNow,
                            child: _submitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text('Book Pickup'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_serviceCity != null)
                          Text(
                            'Service city: $_serviceCity',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        const SizedBox(height: 4),
                        const Text(
                          'You don’t need an account to book. Login for history & faster checkout next time.',
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.black, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: _brandOrange, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
      );

  static String _fmtMoney(double? n) {
    if (n == null) return '';
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

// ---------------------------------------------------------------------------
// Small helper widgets + local models
// ---------------------------------------------------------------------------
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
  const _ServiceBanner({
    required this.locating,
    required this.insideService,
    required this.city,
  });

  @override
  Widget build(BuildContext context) {
    final ok = insideService;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFE8FFF0) : const Color(0xFFFFEFEF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ok ? const Color(0xFFB8E6C5) : const Color(0xFFFFC9C9),
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.info_outline,
            color: ok ? const Color(0xFF1B8F3E) : const Color(0xFFB3261E),
          ),
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
  const _Airport({
    required this.code,
    required this.name,
    required this.city,
    required this.position,
  });
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
