import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/driver_dashboard.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/ride_share_map_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';

/// Centralizes how the app enters the ride-share feature.
///
/// Landing page follows the persisted session role (`user_role`), not a
/// stale homepage flag — so a driver/passenger toggle works immediately
/// and still works offline.
class RideShareEntryResolver {
  const RideShareEntryResolver._();

  static bool isRideShareServiceKey(String key) {
    switch (key.trim().toLowerCase()) {
      case 'ride':
      case 'ride_share':
      case 'taxi':
      case 'car_hire':
        return true;
      default:
        return false;
    }
  }

  static Widget buildLandingPage({bool isDriverHome = false}) {
    return _RideShareLandingGate(fallbackDriverHome: isDriverHome);
  }

  static void open(BuildContext context, {bool isDriverHome = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => buildLandingPage(isDriverHome: isDriverHome),
      ),
    );
  }
}

class _RideShareLandingGate extends StatefulWidget {
  const _RideShareLandingGate({required this.fallbackDriverHome});

  final bool fallbackDriverHome;

  @override
  State<_RideShareLandingGate> createState() => _RideShareLandingGateState();
}

class _RideShareLandingGateState extends State<_RideShareLandingGate> {
  bool? _isDriverHome;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    bool driver = widget.fallbackDriverHome;
    try {
      driver = await loadDriverStatusFromPrefs() ?? widget.fallbackDriverHome;
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isDriverHome = driver);
  }

  @override
  Widget build(BuildContext context) {
    final driver = _isDriverHome;
    if (driver == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF8A00)),
        ),
      );
    }
    return driver ? const DriverDashboard() : const RideShareMapScreen();
  }
}
