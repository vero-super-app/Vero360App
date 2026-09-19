import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/profile_photo_cache.dart';
import 'package:vero360_app/features/ride_share/core/fleet_date_picker.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/become_driver_page.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/edit_driver_details_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/edit_taxi_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_online_session.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/user_facing_error.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_skeleton_loaders.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Central place for drivers to manage profile, documents, payout info and vehicles.
class DriverProfileHubScreen extends ConsumerStatefulWidget {
  const DriverProfileHubScreen({super.key});

  @override
  ConsumerState<DriverProfileHubScreen> createState() =>
      _DriverProfileHubScreenState();
}

class _DriverProfileHubScreenState extends ConsumerState<DriverProfileHubScreen>
    with SingleTickerProviderStateMixin {
  // Calm HCI palette — orange only as accent / CTA.
  static const Color _accent = Color(0xFFFF8A00);
  static const Color _ink = Color(0xFF162033);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _pageBg = Color(0xFFF5F6F8);
  static const Color _cardBorder = Color(0xFFE8EAEE);
  static const Color _chipGrey = Color(0xFFF3F4F6);

  late final TabController _tabs;
  String _localPhotoUrl = '';
  String? _localPhotoPath;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadLocalPhoto();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadLocalPhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final url = (prefs.getString('profilepicture') ??
            prefs.getString('profilePicture') ??
            '')
        .trim();
    final localPath = url.isEmpty
        ? null
        : await ProfilePhotoCache.peekLocalPath(forRemoteUrl: url);

    if (!mounted) return;
    setState(() {
      _localPhotoUrl = url;
      _localPhotoPath = localPath;
    });

    // Warm disk + memory cache so the avatar is instant next open.
    if (url.startsWith('http')) {
      // ignore: unawaited_futures
      ProfilePhotoCache.ensureCached(url).then((file) {
        if (!mounted || file == null) return;
        if (_localPhotoPath != file.path) {
          setState(() => _localPhotoPath = file.path);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        precacheImage(
          CachedNetworkImageProvider(url, maxWidth: 192, maxHeight: 192),
          context,
        );
      });
    }
  }

  void _reload() => ref.invalidate(myDriverProfileProvider);

  /// Strict admin-verified flag — never treat missing/1/status as verified.
  bool _isTrulyVerified(Map<String, dynamic> source) {
    final v = source['isVerified'] ?? source['verified'];
    if (v == true) return true;
    if (v is String && v.toLowerCase().trim() == 'true') return true;
    return false;
  }

  bool _bool(dynamic v) {
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    if (v is num) return v != 0;
    return false;
  }

  String _photoFrom(Map<String, dynamic> user, Map<String, dynamic> driver) {
    // Prefer already-known account photo first (instant from prefs / cache).
    for (final raw in [
      _localPhotoUrl,
      user['profilepicture'],
      user['profilePicture'],
      user['photoURL'],
      user['photoUrl'],
      user['avatar'],
      driver['profilepicture'],
      driver['profilePicture'],
      driver['photoUrl'],
      driver['avatar'],
    ]) {
      final s = (raw ?? '').toString().trim();
      if (s.isEmpty) continue;
      if (s.startsWith('http') || s.startsWith('file')) return s;
    }
    return '';
  }

  ({String label, Color color}) _verificationChip(
    Map<String, dynamic> driver, {
    required bool isVerified,
  }) {
    final status = (driver['status'] ?? '').toString().toUpperCase().trim();
    if (status.contains('REJECT')) {
      return (label: 'Rejected', color: const Color(0xFFC62828));
    }
    if (status.contains('PENDING') || status.contains('REVIEW')) {
      return (label: 'Pending review', color: const Color(0xFFB45309));
    }
    // Require explicit admin flag + active/verified status (not a soft default).
    if (isVerified && (status == 'ACTIVE' || status == 'VERIFIED')) {
      return (label: 'Verified', color: const Color(0xFF059669));
    }
    return (label: 'Not verified', color: const Color(0xFFB45309));
  }

  num _num(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  String _date(dynamic v) {
    final parsed = tryParseFleetDate(v);
    if (parsed == null || parsed.year <= 1901) return '—';
    return DateFormat.yMMMd().format(parsed);
  }

  List<Map<String, dynamic>> _taxisFromDriver(Map<String, dynamic> driver) {
    final raw = driver['taxis'];
    if (raw is! List) return [];
    final all =
        raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    if (all.isEmpty) return [];
    return [all.first];
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(myDriverProfileProvider);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Driver Center',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.2),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            children: [
              TabBar(
                controller: _tabs,
                indicatorColor: _accent,
                indicatorWeight: 2.5,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: _ink,
                unselectedLabelColor: _muted,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(text: 'Profile'),
                  Tab(text: 'Vehicle'),
                ],
              ),
              const Divider(height: 1, color: _cardBorder),
            ],
          ),
        ),
      ),
      body: profile.when(
        loading: () => AnimatedBuilder(
          animation: _tabs,
          builder: (_, __) {
            if (_tabs.index != 0) {
              return const DriverCenterVehicleTabSkeleton();
            }
            // Cached avatar shows immediately; rest of tab still shimmers.
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _avatarHeaderPlaceholder(),
                ),
                const SizedBox(height: 12),
                const Expanded(
                  child: DriverCenterProfileTabSkeleton(skipProfileHeader: true),
                ),
              ],
            );
          },
        ),
        error: (e, _) => _errorState(e),
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
    final isVerified = _isTrulyVerified(driver);
    final taxis = _taxisFromDriver(driver);
    final chip = _verificationChip(driver, isVerified: isVerified);
    final looksVerified = chip.label == 'Verified';
    final setupComplete = looksVerified && taxis.isNotEmpty;

    return RefreshIndicator(
      color: _accent,
      onRefresh: () async {
        await _loadLocalPhoto();
        _reload();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (!setupComplete) _setupBanner(looksVerified, taxis.isNotEmpty),
          _profileHeader(driver, user, isVerified),
          const SizedBox(height: 12),
          _statsRow(driver),
          const SizedBox(height: 16),
          _infoSection(
            title: 'Driver info',
            icon: Icons.badge_outlined,
            rows: [
              _InfoRow('Date of birth', _date(driver['dateOfBirth'])),
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
            height: 50,
            child: FilledButton.icon(
              onPressed: () => _openEditDriver(driver),
              icon: const Icon(Icons.edit_outlined, size: 20),
              label: const Text('Edit driver details'),
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          if (!looksVerified) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _openVerificationWizard,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Complete verification'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  side: const BorderSide(color: _cardBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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
      color: _accent,
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Text(
            'Your registered vehicle',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Each driver can register one vehicle on VeroRide.',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 14),
          if (taxis.isEmpty)
            _emptyVehicles()
          else ...[
            _vehicleCard(taxis.first),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'To use a different car, edit your vehicle details above.',
                style: TextStyle(color: _muted, fontSize: 12.5, height: 1.35),
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
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _accent.withValues(alpha: 0.18),
            _accent.withValues(alpha: 0.08),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.55), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Finish setup to go online',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF9A4A00),
                    fontSize: 16,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Complete these steps so passengers can find you.',
            style: TextStyle(
              color: _ink.withValues(alpha: 0.72),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...steps.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.radio_button_unchecked,
                    size: 16,
                    color: _accent.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
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

  Widget _avatarHeaderPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        children: [
          _avatar(_localPhotoUrl),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 16,
                  width: 140,
                  decoration: BoxDecoration(
                    color: _chipGrey,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 90,
                  decoration: BoxDecoration(
                    color: _chipGrey,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
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
    final name = (user['name'] ??
            user['fullName'] ??
            user['fullname'] ??
            driver['fullName'] ??
            'Driver')
        .toString()
        .trim();
    final photo = _photoFrom(user, driver);
    final chip = _verificationChip(driver, isVerified: isVerified);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        children: [
          _avatar(photo),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Driver' : name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: _ink,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'VeroRide driver',
                  style: TextStyle(color: _muted, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                _statusChip(chip.label, chip.color),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String photo) {
    const size = 64.0;
    final local = _localPhotoPath;
    final hasLocal = !kIsWeb &&
        local != null &&
        local.isNotEmpty &&
        File(local).existsSync();

    Widget child;
    if (hasLocal) {
      child = Image.file(
        File(local),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) {
          if (photo.isEmpty) {
            return const Icon(Icons.person_rounded, color: _muted, size: 32);
          }
          return ResilientCachedNetworkImage(
            url: photo,
            width: size,
            height: size,
            fit: BoxFit.cover,
            memCacheWidth: 192,
            showSpinner: false,
            placeholderColor: _chipGrey,
          );
        },
      );
    } else if (photo.isNotEmpty) {
      child = ResilientCachedNetworkImage(
        url: photo,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: 192,
        showSpinner: false,
        placeholderColor: _chipGrey,
      );
    } else {
      child = const Icon(Icons.person_rounded, color: _muted, size: 32);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _chipGrey,
        border: Border.all(color: _cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _statsRow(Map<String, dynamic> driver) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
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
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: _ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 36,
        color: _cardBorder,
      );

  Widget _infoSection({
    required String title,
    required IconData icon,
    required List<_InfoRow> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _muted),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: r.label.isEmpty
                  ? Text(
                      r.value,
                      style: const TextStyle(
                        color: _ink,
                        height: 1.45,
                        fontSize: 14,
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 112,
                          child: Text(
                            r.label,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            r.value,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _ink,
                              fontSize: 13.5,
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
    final model = (taxi['model'] ?? '').toString();
    final plate = (taxi['licensePlate'] ?? '').toString();
    final taxiClass = (taxi['taxiClass'] ?? 'STANDARD').toString();
    final isAvailable = _bool(taxi['isAvailable']);
    final isVerified = _isTrulyVerified(taxi);
    final taxiStatus = (taxi['status'] ?? '').toString().toUpperCase();
    final taxiChip = () {
      if (taxiStatus.contains('PENDING') || taxiStatus.contains('REVIEW')) {
        return (label: 'Pending review', color: const Color(0xFFB45309));
      }
      if (isVerified) {
        return (label: 'Verified', color: const Color(0xFF059669));
      }
      return (label: 'Not verified', color: const Color(0xFFB45309));
    }();
    final taxiId = int.tryParse('${taxi['id']}');
    final session = ref.watch(driverOnlineSessionProvider);
    final switchOnline = taxiId != null && session.taxiId == taxiId
        ? session.isOnline
        : isAvailable;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _chipGrey,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.directions_car_filled_outlined,
                    color: _ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.trim().isEmpty ? 'Vehicle' : model,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        plate.isEmpty ? 'No plate' : plate,
                        style: const TextStyle(color: _muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                _statusChip(
                  taxiChip.label,
                  taxiChip.color,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 8),
            const Divider(color: _cardBorder),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Available for rides',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: _ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: switchOnline,
                  activeThumbColor: _accent,
                  onChanged: taxiId == null
                      ? null
                      : (v) => _toggleAvailability(taxiId, v),
                ),
                TextButton(
                  onPressed: () => _openEditVehicle(taxi),
                  style: TextButton.styleFrom(foregroundColor: _ink),
                  child: const Text(
                    'Edit',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _chipGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _muted),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: _ink,
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
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 10.5 : 11.5,
        ),
      ),
    );
  }

  Widget _emptyVehicles() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _chipGrey,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.directions_car_outlined,
              size: 32,
              color: _muted,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No vehicle yet',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Register your taxi or car so passengers can find you. One vehicle per driver account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, height: 1.4, fontSize: 13.5),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _openVerificationWizard,
              icon: const Icon(Icons.add),
              label: const Text('Submit vehicle documents'),
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noProfileState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _chipGrey,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.person_add_alt_1_outlined,
                size: 36,
                color: _muted,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No driver profile',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Submit your license and vehicle documents for review to start driving.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _openVerificationWizard,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Start verification'),
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44, color: _muted),
            const SizedBox(height: 14),
            const Text(
              'Could not load driver profile',
              style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
            ),
            const SizedBox(height: 8),
            Text(
              UserFacingError.from(
                error,
                fallback: 'Check your connection and try again.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _reload,
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
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

  Future<void> _openVerificationWizard() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const BecomeDriverPage()),
    );
    _reload();
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
      final session = ref.read(driverOnlineSessionProvider.notifier);
      if (available) {
        await session.goOnline(taxiId: taxiId);
      } else {
        await session.goOffline();
      }
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
        errorMessage: '',
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
