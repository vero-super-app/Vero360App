import 'package:flutter/material.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/vero_ride_driver_profile_page.dart';

/// Opens a marketplace shop **or** a public Vero Ride driver profile.
Future<void> openMerchantOrDriverProfile(
  BuildContext context, {
  required String profileId,
  required String displayName,
}) async {
  final id = profileId.trim();
  if (id.isEmpty) return;

  final isDriver = await VeroRideDriverProfilePage.isDriverAccount(id);
  if (!context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => isDriver
          ? VeroRideDriverProfilePage(
              firebaseUid: id,
              displayName: displayName,
            )
          : MerchantProductsPage(
              merchantId: id,
              merchantName: displayName,
            ),
    ),
  );
}
