import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Public Vero Ride profile: ratings + taxi / business details (not a merchant shop).
class VeroRideDriverProfilePage extends StatefulWidget {
  final String firebaseUid;
  final String displayName;

  const VeroRideDriverProfilePage({
    super.key,
    required this.firebaseUid,
    required this.displayName,
  });

  static Future<bool> isDriverAccount(String firebaseUid) async {
    final id = firebaseUid.trim();
    if (id.isEmpty) return false;
    try {
      final db = FirebaseFirestore.instance;
      final user = await db.collection('users').doc(id).get();
      final data = user.data() ?? {};
      final role = (data['role'] ?? data['user_role'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (role == 'driver') return true;

      final isDriverFlag = data['isDriver'] == true ||
          data['has_driver_profile'] == true ||
          (data['driverId'] != null && data['driverId'].toString().isNotEmpty);
      if (!isDriverFlag) return false;

      final merchant =
          await db.collection('marketplace_merchants').doc(id).get();
      if (merchant.exists) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  State<VeroRideDriverProfilePage> createState() =>
      _VeroRideDriverProfilePageState();
}

class _VeroRideDriverProfilePageState extends State<VeroRideDriverProfilePage> {
  static const _orange = Color(0xFFFF8A00);
  static const _navy = Color(0xFF16284C);
  static const _bg = Color(0xFFF4F6FA);

  final _driverService = DriverService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _driver;
  Map<String, dynamic>? _userDoc;
  List<Map<String, dynamic>> _taxis = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = widget.firebaseUid.trim();
      final userSnap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      _userDoc = userSnap.data();

      Map<String, dynamic>? driver;
      final me = FirebaseAuth.instance.currentUser?.uid;
      if (me != null && me == uid) {
        try {
          driver = await _driverService.getMyDriverProfile();
        } catch (_) {}
      }

      if (driver == null) {
        final nestId = _nestUserId(_userDoc);
        if (nestId != null) {
          try {
            driver = await _driverService.getDriverByUserId(nestId);
          } catch (_) {}
        }
      }

      final taxis = <Map<String, dynamic>>[];
      if (driver != null) {
        final raw = driver['taxis'];
        if (raw is List) {
          for (final t in raw) {
            if (t is Map) taxis.add(Map<String, dynamic>.from(t));
          }
        }
        final driverId = int.tryParse('${driver['id'] ?? ''}');
        if (taxis.isEmpty && driverId != null) {
          try {
            taxis.addAll(await _driverService.getTaxisByDriver(driverId));
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() {
        _driver = driver;
        _taxis = taxis;
        _loading = false;
        if (driver == null && _userDoc == null) {
          _error = 'Driver profile is not available.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load Vero Ride profile.';
      });
    }
  }

  int? _nestUserId(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final key in ['userId', 'user_id', 'backendUserId', 'id']) {
      final v = data[key];
      if (v is int && v > 0) return v;
      final p = int.tryParse(v?.toString() ?? '');
      if (p != null && p > 0) return p;
    }
    return null;
  }

  String get _name {
    final d = _driver;
    final u = _userDoc;
    final fromDriver = [
      d?['fullName'],
      d?['name'],
      [d?['firstName'], d?['lastName']].whereType<Object>().join(' '),
    ].map((e) => e?.toString().trim() ?? '').firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (fromDriver.isNotEmpty) return fromDriver;
    final fromUser = (u?['fullName'] ?? u?['name'] ?? u?['business_name'] ?? '')
        .toString()
        .trim();
    if (fromUser.isNotEmpty) return fromUser;
    return widget.displayName.trim().isEmpty ? 'Vero Ride driver' : widget.displayName;
  }

  String? get _photoUrl {
    final raw = (_driver?['profilePicture'] ??
            _driver?['photoUrl'] ??
            _driver?['avatar'] ??
            _userDoc?['profilepicture'] ??
            _userDoc?['photoURL'] ??
            _userDoc?['profilePicture'] ??
            '')
        .toString()
        .trim();
    return raw.isEmpty ? null : raw;
  }

  double get _rating {
    final v = _driver?['rating'] ?? _driver?['averageRating'] ?? _userDoc?['rating'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  int get _totalTrips {
    final v = _driver?['totalRides'] ??
        _driver?['totalTrips'] ??
        _driver?['completedRides'] ??
        0;
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  int get _completedTrips {
    final v = _driver?['completedRides'] ?? _driver?['completedTrips'] ?? _totalTrips;
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  bool get _verified {
    final v = _driver?['isVerified'] ?? _driver?['verified'] ?? _userDoc?['isVerified'];
    return v == true || v?.toString().toLowerCase() == 'true';
  }

  String get _businessName {
    final t = _taxis.isNotEmpty ? _taxis.first : null;
    final fromTaxi = (t?['businessName'] ?? t?['companyName'] ?? '').toString().trim();
    if (fromTaxi.isNotEmpty) return fromTaxi;
    final fromDriver = (_driver?['businessName'] ??
            _driver?['companyName'] ??
            _userDoc?['business_name'] ??
            '')
        .toString()
        .trim();
    if (fromDriver.isNotEmpty) return fromDriver;
    return 'Vero Ride';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Vero Ride profile'),
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const AppSkeletonListPlaceholder(items: 6)
          : _error != null
              ? _errorBody()
              : RefreshIndicator(
                  color: _orange,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      _headerCard(),
                      const SizedBox(height: 12),
                      _statsRow(),
                      const SizedBox(height: 12),
                      _businessCard(),
                      const SizedBox(height: 12),
                      ..._taxis.map(_taxiCard),
                      if (_taxis.isEmpty) _emptyTaxiCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _errorBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_taxi_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(backgroundColor: _orange),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCard() {
    final photo = _photoUrl;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: Container(
              width: 76,
              height: 76,
              color: _orange.withValues(alpha: 0.12),
              child: photo == null
                  ? const Icon(Icons.local_taxi_rounded, color: _orange, size: 36)
                  : ResilientCachedNetworkImage(
                      url: photo,
                      fit: BoxFit.cover,
                      width: 76,
                      height: 76,
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _businessName,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_verified ? Colors.green : _orange)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    _verified ? 'Verified Vero Ride driver' : 'Vero Ride driver',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _verified ? Colors.green.shade800 : _orange,
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

  Widget _statsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Row(
        children: [
          _stat('Rating', _rating <= 0 ? '—' : '${_rating.toStringAsFixed(1)}/5'),
          _vline(),
          _stat('Trips', '$_totalTrips'),
          _vline(),
          _stat('Completed', '$_completedTrips'),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: _orange,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _vline() =>
      Container(width: 1, height: 36, color: const Color(0xFFE2E6EF));

  Widget _businessCard() {
    final phone = (_driver?['phone'] ??
            _driver?['phoneNumber'] ??
            _userDoc?['phone'] ??
            '')
        .toString()
        .trim();
    final city = (_driver?['city'] ??
            _driver?['baseCity'] ??
            _userDoc?['city'] ??
            _userDoc?['address'] ??
            '')
        .toString()
        .trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.storefront_rounded, size: 18, color: _orange),
              SizedBox(width: 8),
              Text(
                'Taxi business',
                style: TextStyle(fontWeight: FontWeight.w800, color: _navy),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _row('Business', _businessName),
          if (city.isNotEmpty) _row('City / base', city),
          if (phone.isNotEmpty) _row('Phone', phone),
          _row('Service', 'Vero Ride'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, color: _navy),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taxiCard(Map<String, dynamic> taxi) {
    final model = (taxi['model'] ?? '').toString();
    final plate = (taxi['licensePlate'] ?? taxi['plate'] ?? '').toString();
    final taxiClass = (taxi['taxiClass'] ?? taxi['class'] ?? 'STANDARD').toString();
    final color = (taxi['color'] ?? '').toString();
    final seats = taxi['seats'];
    final title = model.trim().isNotEmpty ? model : 'Vehicle';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.directions_car_filled_rounded, color: _orange, size: 18),
              SizedBox(width: 8),
              Text(
                'Vehicle',
                style: TextStyle(fontWeight: FontWeight.w800, color: _navy),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title.isEmpty ? 'Taxi' : title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (plate.isNotEmpty) _chip(Icons.pin_outlined, plate),
              _chip(Icons.category_outlined, taxiClass),
              if (seats != null) _chip(Icons.event_seat_outlined, '$seats seats'),
              if (color.isNotEmpty) _chip(Icons.palette_outlined, color),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyTaxiCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Text(
        'Vehicle details will appear here once registered on Vero Ride.',
        style: TextStyle(color: Colors.grey.shade700, height: 1.4),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E6),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _orange),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
