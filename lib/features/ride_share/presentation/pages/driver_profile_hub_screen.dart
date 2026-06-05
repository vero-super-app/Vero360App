import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/create_taxi_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/edit_driver_details_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/edit_taxi_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_skeleton_loaders.dart';

/// Central place for drivers to manage profile, documents, payout info and vehicles.
class DriverProfileHubScreen extends ConsumerStatefulWidget {
  const DriverProfileHubScreen({super.key});

  @override
  ConsumerState<DriverProfileHubScreen> createState() =>
      _DriverProfileHubScreenState();
}

class _DriverProfileHubScreenState extends ConsumerState<DriverProfileHubScreen>
    with SingleTickerProviderStateMixin {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const Color _chipGrey = Color(0xFFF4F5F7);

  final _driverService = DriverService();
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _reload() => ref.invalidate(myDriverProfileProvider);

  bool _bool(dynamic v) {
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    if (v is num) return v != 0;
    return false;
  }

  num _num(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  String _date(dynamic v) {
    if (v == null) return '—';
    final parsed = DateTime.tryParse(v.toString());
    if (parsed == null) return v.toString();
    return DateFormat.yMMMd().format(parsed);
  }

  List<Map<String, dynamic>> _taxisFromDriver(Map<String, dynamic> driver) {
    final raw = driver['taxis'];
    if (raw is! List) return [];
    final all =
        raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    // One vehicle per driver — use the primary (first) record only in UI.
    if (all.isEmpty) return [];
    return [all.first];
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(myDriverProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: AppBar(
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Driver Center',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          tabs: const [
            Tab(text: 'Driver Profile'),
            Tab(text: 'My Vehicle'),
          ],
        ),
      ),
      body: profile.when(
        loading: () => AnimatedBuilder(
          animation: _tabs,
          builder: (_, __) {
            return _tabs.index == 0
                ? const DriverCenterProfileTabSkeleton()
                : const DriverCenterVehicleTabSkeleton();
          },
        ),
        error: (e, _) => _errorState(e.toString()),
        data: (driver) {
          if (driver.isEmpty || driver['id'] == null) {
            return _noProfileState();
          }
          return TabBarView(
            controller: _tabs,
            children: [
              _driverTab(driver),
              _vehiclesTab(driver),
            ],
          );
        },
      ),
    );
  }

  Widget _driverTab(Map<String, dynamic> driver) {
    final user = driver['user'] is Map
        ? Map<String, dynamic>.from(driver['user'] as Map)
        : <String, dynamic>{};
    final isVerified = _bool(driver['isVerified']);
    final taxis = _taxisFromDriver(driver);
    final setupComplete = isVerified && taxis.isNotEmpty;

    return RefreshIndicator(
      color: _brandOrange,
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (!setupComplete) _setupBanner(isVerified, taxis.isNotEmpty),
          _profileHeader(driver, user, isVerified),
          const SizedBox(height: 12),
          _statsRow(driver),
          const SizedBox(height: 16),
          _infoSection(
            title: 'Identity & license',
            icon: Icons.badge_outlined,
            rows: [
              _InfoRow('National ID', (driver['nationalId'] ?? '—').toString()),
              _InfoRow('License', (driver['licenseNumber'] ?? '—').toString()),
              _InfoRow('License expiry', _date(driver['licenseExpiry'])),
              _InfoRow('Status', (driver['status'] ?? '—').toString()),
            ],
          ),
          const SizedBox(height: 12),
          _infoSection(
            title: 'Payout details',
            icon: Icons.account_balance_outlined,
            rows: [
              _InfoRow(
                'Account name',
                (driver['bankAccountName'] ?? 'Not set').toString(),
              ),
              _InfoRow(
                'Account number',
                _maskAccount(driver['bankAccountNumber']),
              ),
              _InfoRow('Bank code', (driver['bankCode'] ?? '—').toString()),
            ],
          ),
          if ((driver['bio'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoSection(
              title: 'Bio',
              icon: Icons.notes_rounded,
              rows: [
                _InfoRow('', (driver['bio'] ?? '').toString(), multiline: true),
              ],
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: () => _openEditDriver(driver),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit driver details'),
              style: FilledButton.styleFrom(
                backgroundColor: _brandOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (!isVerified) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _verifyDriver(driver),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Request verification'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  side: BorderSide(color: Colors.green.shade400),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _vehiclesTab(Map<String, dynamic> driver) {
    final taxis = _taxisFromDriver(driver);

    return RefreshIndicator(
      color: _brandOrange,
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Text(
            'Your registered vehicle',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: _brandNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Each driver can register one vehicle on VeroRide.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          if (taxis.isEmpty)
            _emptyVehicles()
          else ...[
            _vehicleCard(taxis.first),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'To use a different car, edit your vehicle details above.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _setupBanner(bool verified, bool hasTaxi) {
    final steps = <String>[];
    if (!verified) steps.add('Verify your driver profile');
    if (!hasTaxi) steps.add('Register your vehicle');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F4FD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade800, size: 20),
              const SizedBox(width: 8),
              Text(
                'Complete your setup',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...steps.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.radio_button_unchecked,
                      size: 14, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s,
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileHeader(
    Map<String, dynamic> driver,
    Map<String, dynamic> user,
    bool isVerified,
  ) {
    final name = (user['name'] ?? 'Driver').toString();
    final photo = (user['profilepicture'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: _brandOrange.withValues(alpha: 0.12),
            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo.isEmpty
                ? const Icon(Icons.person, color: _brandOrange, size: 32)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: _brandNavy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Driver #${driver['id']}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 8),
                _statusChip(
                  isVerified ? 'Verified driver' : 'Pending verification',
                  isVerified ? Colors.green : _brandOrange,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(Map<String, dynamic> driver) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Row(
        children: [
          _statCell('Rating', '${_num(driver['rating'])}/5'),
          _divider(),
          _statCell('Trips', '${_num(driver['totalRides'])}'),
          _divider(),
          _statCell('Completed', '${_num(driver['completedRides'])}'),
        ],
      ),
    );
  }

  Widget _statCell(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: _brandOrange,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 36,
        color: const Color(0xFFE2E6EF),
      );

  Widget _infoSection({
    required String title,
    required IconData icon,
    required List<_InfoRow> rows,
  }) {
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
          Row(
            children: [
              Icon(icon, size: 18, color: _brandOrange),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _brandNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: r.label.isEmpty
                  ? Text(
                      r.value,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        height: 1.4,
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            r.label,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            r.value,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _brandNavy,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleCard(Map<String, dynamic> taxi) {
    final make = (taxi['make'] ?? '').toString();
    final model = (taxi['model'] ?? '').toString();
    final plate = (taxi['licensePlate'] ?? '').toString();
    final taxiClass = (taxi['taxiClass'] ?? 'STANDARD').toString();
    final isAvailable = _bool(taxi['isAvailable']);
    final isVerified = _bool(taxi['isVerified']);
    final taxiId = int.tryParse('${taxi['id']}');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _chipGrey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.directions_car_filled_outlined,
                    color: _brandOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$make $model'.trim().isEmpty
                            ? 'Vehicle'
                            : '$make $model',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _brandNavy,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plate.isEmpty ? 'No plate' : plate,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusChip(
                  isVerified ? 'Verified' : 'Pending',
                  isVerified ? Colors.green : _brandOrange,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _metaChip(Icons.category_outlined, taxiClass),
                _metaChip(
                  Icons.event_seat_outlined,
                  '${taxi['seats'] ?? '—'} seats',
                ),
                if ((taxi['color'] ?? '').toString().isNotEmpty)
                  _metaChip(
                    Icons.palette_outlined,
                    (taxi['color'] ?? '').toString(),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'Available for rides',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: isAvailable,
                        activeThumbColor: _brandOrange,
                        onChanged: taxiId == null
                            ? null
                            : (v) => _toggleAvailability(taxiId, v),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openEditVehicle(taxi),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(foregroundColor: _brandOrange),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _chipGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 10 : 11,
        ),
      ),
    );
  }

  Widget _emptyVehicles() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Column(
        children: [
          Icon(Icons.directions_car_outlined,
              size: 52, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'No vehicles yet',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: _brandNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Register your taxi or car so passengers can find you on VeroRide. You can add one vehicle per driver account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openAddVehicle,
            icon: const Icon(Icons.add),
            label: const Text('Register my vehicle'),
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _noProfileState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add_alt_1_outlined,
                size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No driver profile',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: _brandNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Contact support to set up your driver account, then return here to manage your details.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: _brandOrange),
            const SizedBox(height: 12),
            const Text(
              'Could not load driver profile',
              style: TextStyle(fontWeight: FontWeight.w800, color: _brandNavy),
            ),
            const SizedBox(height: 8),
            Text(
              message.replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _reload,
              style: FilledButton.styleFrom(backgroundColor: _brandOrange),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  String _maskAccount(dynamic value) {
    final s = (value ?? '').toString();
    if (s.isEmpty) return 'Not set';
    if (s.length <= 4) return s;
    return '•••• ${s.substring(s.length - 4)}';
  }

  Future<void> _openEditDriver(Map<String, dynamic> driver) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditDriverDetailsScreen(driver: driver),
      ),
    );
    if (updated == true) _reload();
  }

  Future<void> _openAddVehicle() async {
    final driver = ref.read(myDriverProfileProvider).value;
    if (driver != null && _taxisFromDriver(driver).isNotEmpty) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'You already have a registered vehicle',
        isSuccess: false,
        errorMessage: 'Edit your existing vehicle instead of adding another.',
      );
      return;
    }

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const CreateTaxiScreen()),
    );
    if (created == true) _reload();
  }

  Future<void> _openEditVehicle(Map<String, dynamic> taxi) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditTaxiScreen(taxi: taxi),
      ),
    );
    if (updated == true) _reload();
  }

  Future<void> _toggleAvailability(int taxiId, bool available) async {
    try {
      await _driverService.setTaxiAvailability(taxiId, available);
      _reload();
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        available ? 'You are now available' : 'You are now offline',
        isSuccess: true,
        errorMessage: '',
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not update availability',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _verifyDriver(Map<String, dynamic> driver) async {
    final id = int.tryParse('${driver['id']}');
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify driver profile'),
        content: const Text(
          'This marks your profile as verified for testing. In production, verification requires document review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _driverService.verifyDriver(id);
      _reload();
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Profile verified',
        isSuccess: true,
        errorMessage: '',
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Verification failed',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }
}

class _InfoRow {
  final String label;
  final String value;
  final bool multiline;

  _InfoRow(this.label, this.value, {this.multiline = false});
}
