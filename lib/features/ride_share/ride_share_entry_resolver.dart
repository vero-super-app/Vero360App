import 'package:flutter/material.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/driver_dashboard.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/ride_share_map_screen.dart';

/// Centralizes how the app enters the ride-share feature.
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

  static Widget buildLandingPage({required bool isDriverHome}) {
    return isDriverHome ? const DriverDashboard() : const RideShareMapScreen();
  }

  static void open(BuildContext context, {required bool isDriverHome}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => buildLandingPage(isDriverHome: isDriverHome),
      ),
    );
  }
}
