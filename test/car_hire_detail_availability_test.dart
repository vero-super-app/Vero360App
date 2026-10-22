import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_section_models.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_detail_page.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';

CarListing _car() {
  return CarListing.fromJson(<String, dynamic>{
    'id': 7,
    'make': 'Toyota',
    'model': 'RAV4',
    'year': 2023,
    'dailyRate': 85000,
    'seats': 5,
    'transmission': 'AUTOMATIC',
    'fuelType': 'PETROL',
    'bodyType': 'SUV',
    'pickupArea': 'Lilongwe',
    'isAvailable': true,
    'currency': 'MWK',
    'listingStatus': 'PUBLISHED',
    'images': const <String>[],
    'minRentalDays': 1,
  });
}

class _AvailabilityApi extends CarHireApi {
  _AvailabilityApi({this.failuresBeforeSuccess = 0});

  int failuresBeforeSuccess;
  int calls = 0;

  @override
  Future<CarHireAvailability> getCarAvailability({
    required int carId,
    DateTime? startAt,
    DateTime? endAt,
  }) async {
    calls += 1;
    if (calls <= failuresBeforeSuccess) {
      throw const CarHireApiException(
        message: 'The network is unavailable.',
        kind: CarHireErrorKind.network,
      );
    }
    return CarHireAvailability(
      carId: carId,
      availableForDates: true,
      availableUnits: 1,
      unitCount: 1,
      startAt: startAt,
      endAt: endAt,
    );
  }
}

Widget _app(_AvailabilityApi api) {
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      carHireApiProvider.overrideWithValue(api),
      // The car itself is cached from the browse card, so the detail request
      // never has to run for these tests.
      carHireDetailProvider.overrideWith((ref, id) async => _car()),
    ],
    child: const MaterialApp(
      home: CarHireDetailPage(carId: 7, initialCar: null),
    ),
  );
}

void main() {
  testWidgets('car renders from cache while availability fails', (
    tester,
  ) async {
    final api = _AvailabilityApi(failuresBeforeSuccess: 100);

    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('Toyota RAV4'), findsOneWidget);
    expect(find.text('Availability not checked'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // A calendar failure must not trap the renter: checkout re-validates.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('retrying availability recovers the status pill', (tester) async {
    final api = _AvailabilityApi(failuresBeforeSuccess: 1);

    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('Availability not checked'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Availability not checked'), findsNothing);
    expect(find.text('Available for your dates'), findsOneWidget);
    expect(api.calls, 2);
  });
}
