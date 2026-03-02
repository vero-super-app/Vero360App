// This file is now a simple wrapper that redirects to the new shell
// All functionality has been moved to:
// - driver_dashboard_shell.dart (main container with bottom nav)
// - driver_dashboard_home.dart (home tab content)

import 'package:flutter/material.dart';
import 'driver_dashboard_shell.dart';

class DriverDashboard extends StatelessWidget {
  const DriverDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const DriverDashboardShell();
  }
}
