import 'package:flutter/material.dart';
import 'car_rental_page.dart';

/// Car List Page - Redirects to Combined Car Rental Page
/// 
/// This page now redirects to the new CarRentalPage which combines
/// map view and list view functionality, showing cars around the user's
/// location with a modern map-first interface.
class CarListPage extends StatelessWidget {
  const CarListPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Redirect to the new combined car rental page
    return const CarRentalPage();
  }
}
