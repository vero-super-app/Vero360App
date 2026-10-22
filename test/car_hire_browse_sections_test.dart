import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_section_models.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_browse_page.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_browse_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_skeletons.dart';

const _company = CarHireCompanyOption(
  id: 'op-1',
  name: 'Ace Car Hire',
  listings: 2,
);

Map<String, dynamic> _carJson({
  required int id,
  required String model,
  required num rate,
  required String body,
  int seats = 5,
}) {
  return <String, dynamic>{
    'id': id,
    'make': 'Toyota',
    'model': model,
    'dailyRate': rate,
    'seats': seats,
    'bodyType': body,
    'isAvailable': true,
    'currency': 'MWK',
    'listingStatus': 'PUBLISHED',
    'images': const <String>[],
    'availableForDates': true,
  };
}

CarHireSearchResult _results(List<Map<String, dynamic>> cars) {
  return CarHireSearchResult.fromJson(<String, dynamic>{
    'data': cars,
    'meta': <String, dynamic>{
      'page': 1,
      'limit': 50,
      'total': cars.length,
      'hasMore': false,
    },
  });
}

CarHireBrowseSnapshot _snapshot({
  CarHireSection<List<CarHireCompanyOption>>? companies,
  CarHireSection<CarHireFacets>? facets,
  CarHireSection<CarHireSearchResult>? results,
}) {
  return CarHireBrowseSnapshot(
    companies:
        companies ?? const CarHireSection.ok(<CarHireCompanyOption>[_company]),
    facets: facets ?? const CarHireSection.ok(CarHireFacets.empty),
    results: results ?? CarHireSection.ok(_results(const [])),
    degraded: false,
  );
}

class _FakeApi extends CarHireApi {
  _FakeApi({this.snapshot, this.pendingBrowse});

  CarHireBrowseSnapshot? snapshot;
  Future<CarHireBrowseSnapshot>? pendingBrowse;

  /// Set later by tests that need the per-section retries to fail.
  Object? searchError;
  Object? facetsError;
  Object? companiesError;

  int browseCalls = 0;
  int searchCalls = 0;
  int facetCalls = 0;
  int companyCalls = 0;

  @override
  Future<CarHireBrowseSnapshot> browse({
    String? pickupArea,
    DateTime? startAt,
    DateTime? endAt,
    int? minSeats,
    String? transmission,
    String? fuelType,
    String? bodyType,
    String? operatorId,
    String? text,
    double? minRate,
    double? maxRate,
    bool instantOnly = false,
    int? page,
    int? limit,
    String? sort,
  }) {
    browseCalls += 1;
    final pending = pendingBrowse;
    if (pending != null) return pending;
    return Future<CarHireBrowseSnapshot>.value(snapshot ?? _snapshot());
  }

  @override
  Future<List<CarHireCompanyOption>> getPublicCompanies() async {
    companyCalls += 1;
    if (companiesError != null) throw companiesError!;
    return const <CarHireCompanyOption>[_company];
  }

  @override
  Future<CarHireFacets> getFacets({
    String? pickupArea,
    DateTime? startAt,
    DateTime? endAt,
    int? minSeats,
    String? transmission,
    String? fuelType,
    String? bodyType,
    String? operatorId,
    String? text,
    double? minRate,
    double? maxRate,
    bool instantOnly = false,
  }) async {
    facetCalls += 1;
    if (facetsError != null) throw facetsError!;
    return CarHireFacets.empty;
  }

  @override
  Future<CarHireSearchResult> searchCars({
    String? pickupArea,
    DateTime? startAt,
    DateTime? endAt,
    int? minSeats,
    String? transmission,
    String? fuelType,
    String? bodyType,
    String? operatorId,
    String? text,
    double? minRate,
    double? maxRate,
    bool instantOnly = false,
    int? page,
    int? limit,
    String? sort,
  }) async {
    searchCalls += 1;
    if (searchError != null) throw searchError!;
    return _results(const []);
  }
}

Widget _app(_FakeApi api) {
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      carHireApiProvider.overrideWithValue(api),
      carHireAccountProvider.overrideWith((ref) async => CarHireAccount.none),
      companyAccessProvider.overrideWith(
        (ref) async => const CompanyAccess(<CompanyMembership>[]),
      ),
    ],
    child: const MaterialApp(home: CarHireBrowsePage()),
  );
}

void main() {
  testWidgets('results failure leaves the company rail and search usable', (
    tester,
  ) async {
    final api = _FakeApi(
      snapshot: _snapshot(
        results: const CarHireSection<CarHireSearchResult>.unavailable(),
      ),
    );

    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('Ace Car Hire'), findsOneWidget);
    expect(find.text('Cars could not load'), findsOneWidget);
    expect(find.text('Company filters unavailable'), findsNothing);
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('facets failure still shows chips with client-side counts', (
    tester,
  ) async {
    final api = _FakeApi(
      snapshot: _snapshot(
        facets: const CarHireSection<CarHireFacets>.unavailable(),
        results: CarHireSection.ok(
          _results(<Map<String, dynamic>>[
            _carJson(id: 1, model: 'RAV4', rate: 60000, body: 'SUV'),
            _carJson(id: 2, model: 'Corolla', rate: 40000, body: 'Sedan'),
          ]),
        ),
      ),
    );

    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('SUVs · 1'), findsOneWidget);
    expect(find.text('2 cars available'), findsOneWidget);
    // Facets failures are silent: no error strip above the chips.
    expect(find.text('Company filters unavailable'), findsNothing);
  });

  testWidgets('loading shows branded skeletons per section', (tester) async {
    final api = _FakeApi(pendingBrowse: Completer<CarHireBrowseSnapshot>().future);

    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CarHireCompanyRailSkeleton), findsOneWidget);
    expect(find.byType(CarHireFacetChipSkeleton), findsOneWidget);
    expect(find.byType(CarHireListingListSkeleton), findsOneWidget);
  });

  test('stale results stay visible when a refresh fails', () async {
    final api = _FakeApi(
      snapshot: _snapshot(
        results: CarHireSection.ok(
          _results(<Map<String, dynamic>>[
            _carJson(id: 1, model: 'RAV4', rate: 60000, body: 'SUV'),
          ]),
        ),
      ),
    );
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [carHireApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(carHireBrowseProvider.notifier).loadAll();
    expect(container.read(carHireBrowseProvider).results.hasData, isTrue);

    api.searchError = const CarHireApiException(
      message: 'The network is unavailable.',
      kind: CarHireErrorKind.network,
    );
    await container.read(carHireBrowseProvider.notifier).refreshResultCards();

    final state = container.read(carHireBrowseProvider);
    expect(state.results.showsStaleData, isTrue);
    expect(state.results.data, isNotNull);
    expect(state.results.error?.message, 'The network is unavailable.');
    // The company section is untouched by a results retry.
    expect(api.companyCalls, 0);
  });

  test('browse snapshot parses partial and missing sections tolerantly', () {
    final snapshot = CarHireBrowseSnapshot.fromJson(<String, dynamic>{
      'sections': <String, dynamic>{
        'companies': <String, dynamic>{
          'status': 'ok',
          'data': <dynamic>[
            <String, dynamic>{'id': 'op-1', 'name': 'Ace Car Hire'},
          ],
        },
        'facets': <String, dynamic>{
          'status': 'ok',
          'data': <String, dynamic>{
            'total': '2',
            'instantCount': '1',
            'price': <String, dynamic>{
              'min': '45000.00',
              'median': '90000.00',
              'max': '210000.00',
            },
            'categories': <String, dynamic>{'all': 2, 'suv': 1},
          },
        },
        'results': <String, dynamic>{
          'status': 'unavailable',
          'error': <String, dynamic>{
            'code': 'SECTION_UNAVAILABLE',
            'retryable': true,
          },
        },
      },
      'meta': <String, dynamic>{'version': 1, 'degraded': true},
    });

    expect(snapshot.degraded, isTrue);
    expect(snapshot.companies.data?.single.name, 'Ace Car Hire');
    expect(snapshot.facets.data?.categories.suv, 1);
    expect(snapshot.facets.data?.price.median, 90000);
    expect(snapshot.results.isUnavailable, isTrue);
    expect(snapshot.results.retryable, isTrue);
  });
}
