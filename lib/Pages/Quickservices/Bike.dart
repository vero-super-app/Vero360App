// lib/Pages/Quickservices/vero_ride_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/models/vero_bike.models.dart';
import 'package:vero360_app/services/vero_bike_service.dart';
import 'package:vero360_app/services/api_exception.dart';

class VeroRidePage extends StatefulWidget {
  const VeroRidePage({super.key});

  @override
  State<VeroRidePage> createState() => _VeroRidePageState();
}

class _VeroRidePageState extends State<VeroRidePage> {
  static const _brandOrange = Color(0xFFFF8A00);
  static const _brandSoft = Color(0xFFFFE8CC);

  final _service = const VeroBikeService();

  List<VeroBikeDriver> _drivers = [];
  bool _loading = false;
  String? _error;

  // simple: pick city manually here
  String _city = 'Lilongwe';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _readToken() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString('jwt_token') ??
        sp.getString('token') ??
        sp.getString('jwt');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _readToken();
      final data = await _service.fetchAvailableBikes(
        city: _city,
        authToken: token,
      );
      setState(() {
        _drivers = data;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _error = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _callNumber(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.trim());
    if (!await canLaunchUrl(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the dialer on this device.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await launchUrl(uri);
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ONLINE_AVAILABLE':
        return 'Available now';
      case 'ONLINE_ON_TRIP':
        return 'On a trip';
      case 'OFFLINE':
      default:
        return 'Offline';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ONLINE_AVAILABLE':
        return const Color(0xFF1B8F3E); // green
      case 'ONLINE_ON_TRIP':
        return const Color(0xFFFFA000); // amber
      case 'OFFLINE':
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VeroBike'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // simple city selector
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _city = value);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'Lilongwe',
                child: Text('Lilongwe'),
              ),
              PopupMenuItem(
                value: 'Blantyre',
                child: Text('Blantyre'),
              ),
            ],
            icon: const Icon(Icons.location_city),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _drivers.isEmpty && _error == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null && _drivers.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: _brandOrange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    if (_drivers.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SizedBox(height: 60),
          Icon(Icons.directions_bike, size: 56, color: Colors.black45),
          SizedBox(height: 12),
          Text(
            'No bikes are available right now.\nPlease refresh in a few minutes.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _drivers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final d = _drivers[index];
        final statusColor = _statusColor(d.status);
        final statusText = _statusLabel(d.status);

        final locationText = (d.baseLocationText != null &&
                d.baseLocationText!.trim().isNotEmpty)
            ? d.baseLocationText!
            : d.city;

        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Avatar
                _DriverAvatar(
                  name: d.name,
                  photoUrl: d.photoUrl,
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + status chip
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              d.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: statusColor),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 11,
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 14, color: Colors.black54),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              locationText,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.phone,
                              size: 14, color: Colors.black54),
                          const SizedBox(width: 4),
                          Text(
                            d.phone,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                const SizedBox(height: 16),
                // Mini info card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101010).withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.info_outline_rounded, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('Safe • Fast • Affordable — perfect for quick errands.',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;

  const _DriverAvatar({
    required this.name,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    if (photoUrl != null && photoUrl!.trim().isNotEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundImage: NetworkImage(photoUrl!),
        backgroundColor: Colors.grey.shade200,
      );
    }

    return CircleAvatar(
      radius: 28,
      backgroundColor: Colors.grey.shade300,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
  }
}
