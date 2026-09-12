import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/vero_ride_driver_profile_page.dart';

/// Opens a marketplace shop **or** a public Vero Ride driver profile.
///
/// Navigates immediately (no waiting on role lookup). If the account turns out
/// to be a driver-only profile, the route is swapped in place.
Future<void> openMerchantOrDriverProfile(
  BuildContext context, {
  required String profileId,
  required String displayName,
}) async {
  final id = profileId.trim();
  if (id.isEmpty) return;
  if (!context.mounted) return;

  final nav = Navigator.of(context);
  // Instant open — shop is the common case from chat / marketplace.
  unawaited(
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => MerchantProductsPage(
          merchantId: id,
          merchantName: displayName,
        ),
      ),
    ),
  );

  // Soft upgrade for driver-only accounts (does not block first paint).
  try {
    final isDriver = await VeroRideDriverProfilePage.isDriverAccount(id);
    if (!isDriver || !context.mounted) return;
    // Replace the shop page we just opened if still on top.
    nav.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => VeroRideDriverProfilePage(
          firebaseUid: id,
          displayName: displayName,
        ),
      ),
    );
  } catch (_) {}
}
