// lib/Pages/airport_pickup_page.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/features/AirportPickup/AirportModels/Airport_pickup.models.dart';
import 'package:vero360_app/features/AirportPickup/AirportService/airport_pickup_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/features/Auth/AuthServices/user_service.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/AirportPickup/AirportPresenter/airport_pickup_progress_page.dart';

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

  // Vehicles — fare: base (MWK) + perKm (MWK/km). Standard & Executive with realistic rates.
  static const List<_Vehicle> _vehicles = [
    _Vehicle(
      id: 'standard',
      label: 'Standard Car',
      seats: 4,
      base: 5000,
      perKm: 1000,
    ),
    _Vehicle(
      id: 'executive',
      label: 'Executive Car',
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
  bool _submitting = false;

  _Airport? _selectedAirport;
  LatLng? _dropoff;
  _Vehicle _vehicle = _vehicles.first;

  final Set<Marker> _markers = {};
  final Set<Polyline> _routePolylines = {};

  // Form fields
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _destSearchCtrl = TextEditingController();
  final _destAddressCtrl = TextEditingController();

  final _airportService = const AirportPickupService();
  bool _searchingDest = false;

  // Destination search suggestions (debounced) — each has location + human-readable address
  List<_DestSuggestion> _destSuggestions = [];
  bool _loadingSuggestions = false;
  Timer? _suggestDebounce;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadUserData();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUserData());
    // Reload again after a short delay so we pick up name/phone if user just logged in
    Future.delayed(const Duration(milliseconds: 800), () => _loadUserData());
    Future.delayed(const Duration(seconds: 2), () => _loadUserData());
    _destSearchCtrl.addListener(_onDestSearchChanged);
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _destSearchCtrl.removeListener(_onDestSearchChanged);
    _map?.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _destSearchCtrl.dispose();
    _destAddressCtrl.dispose();
    super.dispose();
  }

  void _onDestSearchChanged() {
    _suggestDebounce?.cancel();
    final query = _destSearchCtrl.text.trim();
    if (query.length < 2) {
      setState(() => _destSuggestions = []);
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 450), () {
      _fetchDestSuggestions(query);
    });
  }

  /// Auto-populate name, phone, email (prefs + Firebase + API getMe, like CustomersProfilepage / marketplace).
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    String? name = prefs.getString('fullName') ?? prefs.getString('name');
    String? phone = prefs.getString('phone') ?? prefs.getString('phoneNumber');
    String? email = prefs.getString('email');
    String? address = prefs.getString('address');

    // Fallback to Firebase Auth (like CustomersProfilepage)
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      if ((name == null || name.trim().isEmpty) &&
          (firebaseUser.displayName ?? '').trim().isNotEmpty) {
        name = firebaseUser.displayName!.trim();
        await prefs.setString('fullName', name);
        await prefs.setString('name', name);
      }
      if ((email == null || email.trim().isEmpty) &&
          (firebaseUser.email ?? '').trim().isNotEmpty) {
        email = firebaseUser.email!.trim();
        await prefs.setString('email', email);
      }
      if ((phone == null || phone.trim().isEmpty) &&
          (firebaseUser.phoneNumber ?? '').trim().isNotEmpty) {
        phone = firebaseUser.phoneNumber!.trim();
        await prefs.setString('phone', phone);
      }
    }

    // Fallback to JWT name if still empty
    if ((name == null || name.trim().isEmpty)) {
      name = await AuthStorage.userNameFromToken();
    }

    // Optional: fetch latest from API (like marketplace /users/me) and persist
    try {
      final token = await AuthStorage.readToken();
      if (token != null && token.isNotEmpty) {
        final me = await UserService().getMe();
        final data = me['data'] is Map ? me['data'] as Map : me;
        final user = (data['user'] is Map) ? data['user'] as Map : data;
        final apiName = (user['name'] ?? user['fullName'] ?? user['displayName'] ?? '').toString().trim();
        final apiPhone = (user['phone'] ?? user['phoneNumber'] ?? user['mobile'] ?? '').toString().trim();
        final apiEmail = (user['email'] ?? user['userEmail'] ?? '').toString().trim();
        if (apiName.isNotEmpty) {
          name = apiName;
          await prefs.setString('fullName', apiName);
          await prefs.setString('name', apiName);
        }
        if (apiPhone.isNotEmpty) {
          phone = apiPhone;
          await prefs.setString('phone', apiPhone);
        }
        if (apiEmail.isNotEmpty) {
          email = apiEmail;
          await prefs.setString('email', apiEmail);
        }
      }
    } catch (_) {}

    if (mounted) {
      bool updated = false;
      if (name != null && name.trim().isNotEmpty) {
        _nameCtrl.text = name.trim();
        updated = true;
      }
      if (phone != null && phone.trim().isNotEmpty) {
        _phoneCtrl.text = phone.trim();
        updated = true;
      }
      if (email != null && email.trim().isNotEmpty) {
        _emailCtrl.text = email.trim();
        updated = true;
      }
      if (address != null && address.trim().isNotEmpty && _destAddressCtrl.text.isEmpty) {
        _destAddressCtrl.text = address.trim();
        updated = true;
      }
      if (updated) setState(() {});
    }
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

  /// Reverse geocode dropoff coordinates to get address text.
  Future<void> _reverseGeocodeDropoff(LatLng latLng, {bool forceSet = false}) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final parts = [
          p.street,
          p.locality,
          p.subAdministrativeArea,
          p.administrativeArea,
        ].where((s) => s != null && s.trim().isNotEmpty).map((s) => s!.trim());
        final addr = parts.join(', ');
        if (addr.isNotEmpty && (forceSet || _destAddressCtrl.text.isEmpty)) {
          _destAddressCtrl.text = addr;
        }
      }
    } catch (_) {}
  }

  /// Fetch address suggestions with human-readable text (reverse-geocode each result).
  Future<void> _fetchDestSuggestions(String query) async {
    if (query.trim().length < 2) return;
    setState(() => _loadingSuggestions = true);
    try {
      final locations = await locationFromAddress('$query, Malawi');
      final suggestions = <_DestSuggestion>[];
      for (final loc in locations.take(6)) {
        String address = '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}';
        try {
          final placemarks = await placemarkFromCoordinates(loc.latitude, loc.longitude);
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            final parts = [
              p.street,
              p.locality,
              p.subAdministrativeArea,
              p.administrativeArea,
              p.country,
            ].where((s) => s != null && s.trim().isNotEmpty).map((s) => s!.trim());
            if (parts.isNotEmpty) address = parts.join(', ');
          }
        } catch (_) {}
        suggestions.add(_DestSuggestion(location: loc, address: address));
      }
      if (mounted) {
        setState(() {
          _destSuggestions = suggestions;
          _loadingSuggestions = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
        _destSuggestions = [];
        _loadingSuggestions = false;
      });
      }
    }
  }

  /// When user selects a suggestion, set dropoff and fill address.
  Future<void> _onSelectDestSuggestion(_DestSuggestion suggestion) async {
    final loc = suggestion.location;
    final latLng = LatLng(loc.latitude, loc.longitude);
    setState(() {
      _dropoff = latLng;
      _destSuggestions = [];
    });
    _destAddressCtrl.text = suggestion.address;
    _refreshMarkers();
    await _map?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 14));
  }

  /// Search for destination by address text; set dropoff from first result.
  Future<void> _searchDestination() async {
    final query = _destSearchCtrl.text.trim();
    if (query.isEmpty) {
      ToastHelper.showCustomToast(context, 'Enter an address to search (e.g. area, street, landmark).', isSuccess: false, errorMessage: '');
      return;
    }
    setState(() {
      _searchingDest = true;
      _destSuggestions = [];
    });
    try {
      final locations = await locationFromAddress('$query, Malawi');
      if (locations.isEmpty) {
        ToastHelper.showCustomToast(context, 'No results for "$query". Try a different address.', isSuccess: false, errorMessage: '');
        return;
      }
      final loc = locations.first;
      final latLng = LatLng(loc.latitude, loc.longitude);
      setState(() {
        _dropoff = latLng;
        _searchingDest = false;
      });
      _refreshMarkers();
      await _reverseGeocodeDropoff(latLng, forceSet: true);
      if (_destAddressCtrl.text.isEmpty) _destAddressCtrl.text = query;
      await _map?.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 14),
      );
      ToastHelper.showCustomToast(context, 'Destination set.', isSuccess: true, errorMessage: '');
    } catch (e) {
      if (mounted) setState(() => _searchingDest = false);
      ToastHelper.showCustomToast(context, 'Could not find "$query". Try another address.', isSuccess: false, errorMessage: '');
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

    // Route line between airport and drop-off
    _routePolylines.clear();
    if (_selectedAirport != null && _dropoff != null) {
      _routePolylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: [_selectedAirport!.position, _dropoff!],
          color: _brandOrange,
          width: 5,
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

  /// Returns (distanceKm, base, perKmTotal, total) for fare breakdown. Null if route not set.
  (double, double, double, double)? _fareBreakdown() {
    if (_selectedAirport == null || _dropoff == null) return null;
    final km = _kmBetween(_selectedAirport!.position, _dropoff!);
    final v = _vehicle;
    final perKmTotal = v.perKm * km;
    final total = v.base + perKmTotal;
    return (km, v.base, perKmTotal, total);
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
      ToastHelper.showCustomToast(context, 'Airport Pickup is only available in Lilongwe & Blantyre.', isSuccess: false, errorMessage: '');
      return;
    }
    if (_selectedAirport == null) {
      ToastHelper.showCustomToast(context, 'Select your pickup airport.', isSuccess: false, errorMessage: '');
      return;
    }
    if (_dropoff == null) {
      ToastHelper.showCustomToast(context, 'Search for a destination or tap on the map to set drop-off.', isSuccess: false, errorMessage: '');
      return;
    }

    if (!_formKey.currentState!.validate()) {
      ToastHelper.showCustomToast(context, 'Please fill all required fields.', isSuccess: false, errorMessage: '');
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

      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Pickup booked successfully.',
        isSuccess: true,
        errorMessage: '',
      );
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => AirportPickupProgressPage(booking: booking),
        ),
      );
    } on ApiException catch (e) {
      ToastHelper.showCustomToast(context, e.message, isSuccess: false, errorMessage: e.message);
    } catch (_) {
      ToastHelper.showCustomToast(context, 'Could not book pickup. Please try again.', isSuccess: false, errorMessage: '');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Airport Pickup'),
        centerTitle: true,
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      body: Column(
        children: [
          SizedBox(
            height: 280,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: _initialCamera,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  markers: _markers,
                  polylines: _routePolylines,
                  onMapCreated: _onMapCreated,
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
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '🟠 Airport   🔵 Drop-off',
                        style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 0.5),
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
              ],
            ),
          ),

          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F7),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, -4))],
              ),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(icon: Icons.flight_land_rounded, title: 'Your trip'),
                      const SizedBox(height: 12),
                      _Labeled(label: 'Pickup airport', child: _AirportChips(
                        airports: airportsForCity,
                        selected: airportsForCity.contains(_selectedAirport) ? _selectedAirport : null,
                        onSelected: _onAirportChanged,
                      )),
                      const SizedBox(height: 16),
                      _Labeled(
                        label: 'Destination',
                        child: _DestinationCard(
                          destSearchCtrl: _destSearchCtrl,
                          dropoff: _dropoff,
                          destAddressCtrl: _destAddressCtrl,
                          searchingDest: _searchingDest,
                          suggestions: _destSuggestions,
                          loadingSuggestions: _loadingSuggestions,
                          onSearch: _searchDestination,
                          onSelectSuggestion: _onSelectDestSuggestion,
                          inputDecoration: _inputDecoration(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionHeader(icon: Icons.person_outline_rounded, title: 'Your details'),
                      const SizedBox(height: 12),
                      _ModernTextField(
                        controller: _nameCtrl,
                        label: 'Name',
                        hint: 'Full name',
                        icon: Icons.person_outline_rounded,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      _ModernTextField(
                        controller: _phoneCtrl,
                        label: 'Phone',
                        hint: '+265 99 123 4567',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return 'Required';
                          if (t.length < 7) return 'Valid number required';
                          return null;
                        },
                      ),
                     
                     
                      const SizedBox(height: 20),
                      _SectionHeader(icon: Icons.directions_car_rounded, title: 'Vehicle'),
                      const SizedBox(height: 12),
                      _VehicleCards(
                        vehicles: _vehicles,
                        selected: _vehicle,
                        dropoff: _dropoff,
                        airport: _selectedAirport,
                        kmBetween: _kmBetween,
                        fmtMoney: _fmtMoney,
                        onSelect: (v) => setState(() => _vehicle = v),
                      ),
                      const SizedBox(height: 20),
                      _FareCard(
                        fare: fare,
                        breakdown: _fareBreakdown(),
                        fmtMoney: _fmtMoney,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _brandOrange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          onPressed: _submitting ? null : _bookNow,
                          child: _submitting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                )
                              : const Text('Book pickup'),
                        ),
                      ),
                      if (_serviceCity != null) ...[
                        const SizedBox(height: 8),
                        Text('Service area: $_serviceCity', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                        'Vero Airport Pickup is a service provided by Vero. All rights reserved.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
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
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _AirportpickuppageState._brandOrange),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _AirportChips extends StatelessWidget {
  final List<_Airport> airports;
  final _Airport? selected;
  final void Function(_Airport?) onSelected;

  const _AirportChips({required this.airports, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: airports.map((a) {
        final isSelected = selected?.code == a.code;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(a),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? _AirportpickuppageState._brandSoft : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? _AirportpickuppageState._brandOrange : Colors.grey.shade300,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected ? null : [BoxShadow(color: Colors.black26, blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flight_land_rounded, size: 20, color: isSelected ? _AirportpickuppageState._brandOrange : Colors.grey.shade700),
                  const SizedBox(width: 8),
                  Text(a.code, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: isSelected ? Colors.black87 : Colors.black87)),
                  const SizedBox(width: 4),
                  Text('• ${a.city}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  final TextEditingController destSearchCtrl;
  final LatLng? dropoff;
  final TextEditingController destAddressCtrl;
  final bool searchingDest;
  final List<_DestSuggestion> suggestions;
  final bool loadingSuggestions;
  final VoidCallback onSearch;
  final void Function(_DestSuggestion) onSelectSuggestion;
  final InputDecoration inputDecoration;

  const _DestinationCard({
    required this.destSearchCtrl,
    required this.dropoff,
    required this.destAddressCtrl,
    required this.searchingDest,
    required this.suggestions,
    required this.loadingSuggestions,
    required this.onSearch,
    required this.onSelectSuggestion,
    required this.inputDecoration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: destSearchCtrl,
                  decoration: inputDecoration.copyWith(
                    hintText: 'Search address or landmark',
                    prefixIcon: const Icon(Icons.search_rounded, color: _AirportpickuppageState._brandOrange, size: 22),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  textInputAction: TextInputAction.search,
                  onFieldSubmitted: (_) => onSearch(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _AirportpickuppageState._brandOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onPressed: searchingDest ? null : onSearch,
                icon: searchingDest
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                    : const Icon(Icons.search, size: 20),
                label: Text(searchingDest ? '...' : 'Search'),
              ),
            ],
          ),
          if (loadingSuggestions)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: SizedBox(height: 24, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Material(
              color: Colors.transparent,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final suggestion = suggestions[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined, size: 20, color: _AirportpickuppageState._brandOrange),
                    title: Text(
                      suggestion.address,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('Tap to set as drop-off', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    onTap: () => onSelectSuggestion(suggestion),
                  );
                },
              ),
            ),
          ],
          if (dropoff != null && destAddressCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
                color: _AirportpickuppageState._brandSoft,
              ),
              child: Row(
                children: [
                  const Icon(Icons.place, size: 18, color: _AirportpickuppageState._brandOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      destAddressCtrl.text.trim(),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;

  const _ModernTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 22, color: _AirportpickuppageState._brandOrange),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        validator: validator,
      ),
    );
  }
}

class _VehicleCards extends StatelessWidget {
  final List<_Vehicle> vehicles;
  final _Vehicle selected;
  final LatLng? dropoff;
  final _Airport? airport;
  final double Function(LatLng, LatLng) kmBetween;
  final String Function(double?) fmtMoney;
  final void Function(_Vehicle) onSelect;

  const _VehicleCards({
    required this.vehicles,
    required this.selected,
    required this.dropoff,
    required this.airport,
    required this.kmBetween,
    required this.fmtMoney,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final hasRoute = airport != null && dropoff != null;
    return Row(
      children: vehicles.map((v) {
        final isSelected = v.id == selected.id;
        final estimate = hasRoute ? v.base + v.perKm * kmBetween(airport!.position, dropoff!) : null;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: v.id == vehicles.last.id ? 0 : 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelect(v),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? _AirportpickuppageState._brandSoft : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? _AirportpickuppageState._brandOrange : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.directions_car_rounded, size: 28, color: isSelected ? _AirportpickuppageState._brandOrange : Colors.grey.shade700),
                      const SizedBox(height: 6),
                      Text(v.label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.black87)),
                      Text('${v.seats} seats', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      if (estimate != null) ...[
                        const SizedBox(height: 6),
                        Text('MWK ${fmtMoney(estimate)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.black87)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FareCard extends StatelessWidget {
  final double? fare;
  final (double, double, double, double)? breakdown;
  final String Function(double?) fmtMoney;

  const _FareCard({required this.fare, required this.breakdown, required this.fmtMoney});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFFF8A00).withValues(alpha: 0.12), const Color(0xFFFFE8CC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF8A00).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: _AirportpickuppageState._brandOrange, size: 22),
              const SizedBox(width: 8),
              Text(fare == null ? 'Fare estimate' : 'Fare breakdown', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          if (fare == null)
            const Text('Set airport and destination to see estimate.', style: TextStyle(color: Colors.black54, fontSize: 13))
          else if (breakdown != null) ...[
            Text('Base fare: MWK ${fmtMoney(breakdown!.$2)}', style: const TextStyle(fontSize: 13)),
            Text('${breakdown!.$1.toStringAsFixed(1)} km × rate = MWK ${fmtMoney(breakdown!.$3)}', style: const TextStyle(fontSize: 13)),
            const Divider(height: 16),
            Text('Total (estimate): MWK ${fmtMoney(breakdown!.$4)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ] else
            Text('Estimated fare: MWK ${fmtMoney(fare)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      ),
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

class _DestSuggestion {
  final Location location;
  final String address;
  const _DestSuggestion({required this.location, required this.address});
}
