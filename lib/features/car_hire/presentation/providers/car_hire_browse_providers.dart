import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_section_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

/// Message shown inside a section when the server could not resolve it.
const String carHireSectionUnavailableMessage =
    'This part could not load. Tap retry to try again.';

CarHireApiException _asApiException(Object error) {
  if (error is CarHireApiException) return error;
  return CarHireApiException(message: UserFacingError.from(error));
}

// ---------------------------------------------------------------------------
// Section state
// ---------------------------------------------------------------------------

/// Loading, data and error for one independent page section.
///
/// The previous data is deliberately kept when a refresh fails, so the page can
/// keep showing the last good cars (and say so) instead of blanking out.
class CarHireSectionState<T> {
  const CarHireSectionState({
    this.data,
    this.error,
    this.loading = false,
    this.updatedAt,
    this.retryable = true,
  });

  final T? data;
  final CarHireApiException? error;
  final bool loading;
  final DateTime? updatedAt;
  final bool retryable;

  bool get hasData => data != null;

  /// Nothing on screen yet: the section renders its skeleton.
  bool get isInitialLoading => loading && data == null;

  /// Data is on screen while a newer request runs.
  bool get isRefreshing => loading && data != null;

  /// Nothing to show and the last request failed: the section shows a retry.
  bool get isUnavailable => !hasData && error != null && !loading;

  /// Last good data is on screen but the newest request failed.
  bool get showsStaleData => hasData && error != null;

  CarHireSectionState<T> startLoading() => CarHireSectionState<T>(
    data: data,
    loading: true,
    updatedAt: updatedAt,
  );

  CarHireSectionState<T> ready(T value) => CarHireSectionState<T>(
    data: value,
    updatedAt: DateTime.now(),
  );

  CarHireSectionState<T> fail(Object error, {bool retryable = true}) {
    return CarHireSectionState<T>(
      data: data,
      error: _asApiException(error),
      updatedAt: updatedAt,
      retryable: retryable,
    );
  }
}

// ---------------------------------------------------------------------------
// Browse state
// ---------------------------------------------------------------------------

class CarHireBrowseState {
  const CarHireBrowseState({
    this.companies = const CarHireSectionState<List<CarHireCompanyOption>>(),
    this.facets = const CarHireSectionState<CarHireFacets>(),
    this.results = const CarHireSectionState<CarHireSearchResult>(),
    this.loaded = false,
  });

  final CarHireSectionState<List<CarHireCompanyOption>> companies;
  final CarHireSectionState<CarHireFacets> facets;
  final CarHireSectionState<CarHireSearchResult> results;

  /// True once a load has finished (successfully or not).
  final bool loaded;

  CarHireBrowseState copyWith({
    CarHireSectionState<List<CarHireCompanyOption>>? companies,
    CarHireSectionState<CarHireFacets>? facets,
    CarHireSectionState<CarHireSearchResult>? results,
    bool? loaded,
  }) {
    return CarHireBrowseState(
      companies: companies ?? this.companies,
      facets: facets ?? this.facets,
      results: results ?? this.results,
      loaded: loaded ?? this.loaded,
    );
  }
}

/// Drives the browse page one section at a time.
///
/// Every loader catches its own failure and never rethrows: the page always
/// receives a state it can render.
class CarHireBrowseController extends Notifier<CarHireBrowseState> {
  @override
  CarHireBrowseState build() => const CarHireBrowseState();

  CarHireSearchQuery get _search => ref.read(carHireSearchProvider);
  CarHireFilters get _filters => ref.read(carHireFiltersProvider);

  CarHireApiException? get _dateProblem {
    final query = _search;
    if (!query.hasDates) {
      return const CarHireApiException(
        message: 'Choose a pick-up and return date to see available cars.',
        kind: CarHireErrorKind.validation,
      );
    }
    if (!query.isDateRangeValid) {
      return const CarHireApiException(
        message: 'The return date must be after the pick-up date.',
        kind: CarHireErrorKind.validation,
      );
    }
    return null;
  }

  /// Loads every section. Used on first paint and by pull-to-refresh.
  Future<void> loadAll() async {
    state = state.copyWith(
      companies: state.companies.startLoading(),
      facets: state.facets.startLoading(),
      results: state.results.startLoading(),
    );

    final problem = _dateProblem;
    if (problem != null) {
      state = state.copyWith(
        companies: state.companies.fail(problem, retryable: false),
        facets: state.facets.fail(problem, retryable: false),
        results: state.results.fail(problem, retryable: false),
        loaded: true,
      );
      return;
    }

    final query = _search;
    final filters = _filters;
    try {
      final snapshot = await ref
          .read(carHireApiProvider)
          .browse(
            pickupArea: query.pickupArea,
            startAt: query.startAt,
            endAt: query.endAt,
            operatorId: filters.company?.id,
            transmission: filters.transmission,
            fuelType: filters.fuelType,
            minSeats: filters.minSeats,
            maxRate: filters.maxRate,
            instantOnly: filters.instantOnly,
            text: filters.text,
            page: 1,
            limit: 50,
          );
      if (!ref.mounted) return;
      state = CarHireBrowseState(
        companies: _applySection(snapshot.companies, state.companies),
        facets: _applySection(snapshot.facets, state.facets),
        results: _applySection(snapshot.results, state.results),
        loaded: true,
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        companies: state.companies.fail(error),
        facets: state.facets.fail(error),
        results: state.results.fail(error),
        loaded: true,
      );
    }
  }

  /// Re-runs the chip counts and the cards after a filter, sort or date change.
  /// The company rail is untouched.
  Future<void> refreshResults() async {
    final problem = _dateProblem;
    if (problem != null) {
      state = state.copyWith(
        facets: state.facets.fail(problem, retryable: false),
        results: state.results.fail(problem, retryable: false),
        loaded: true,
      );
      return;
    }
    await Future.wait<void>([_loadFacets(), _loadResults()]);
  }

  /// Retry only the chip counts.
  Future<void> refreshFacets() async {
    final problem = _dateProblem;
    if (problem != null) {
      state = state.copyWith(
        facets: state.facets.fail(problem, retryable: false),
      );
      return;
    }
    await _loadFacets();
  }

  /// Retry only the result cards.
  Future<void> refreshResultCards() async {
    final problem = _dateProblem;
    if (problem != null) {
      state = state.copyWith(
        results: state.results.fail(problem, retryable: false),
      );
      return;
    }
    await _loadResults();
  }

  /// Retry only the company rail.
  Future<void> refreshCompanies() async {
    state = state.copyWith(companies: state.companies.startLoading());
    try {
      final companies = await ref.read(carHireApiProvider).getPublicCompanies();
      if (!ref.mounted) return;
      state = state.copyWith(companies: state.companies.ready(companies));
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(companies: state.companies.fail(error));
    }
  }

  Future<void> _loadFacets() async {
    state = state.copyWith(facets: state.facets.startLoading());
    final query = _search;
    final filters = _filters;
    try {
      final facets = await ref
          .read(carHireApiProvider)
          .getFacets(
            pickupArea: query.pickupArea,
            startAt: query.startAt,
            endAt: query.endAt,
            operatorId: filters.company?.id,
            transmission: filters.transmission,
            fuelType: filters.fuelType,
            minSeats: filters.minSeats,
            maxRate: filters.maxRate,
            instantOnly: filters.instantOnly,
            text: filters.text,
          );
      if (!ref.mounted) return;
      state = state.copyWith(facets: state.facets.ready(facets));
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(facets: state.facets.fail(error));
    }
  }

  Future<void> _loadResults() async {
    state = state.copyWith(results: state.results.startLoading());
    final query = _search;
    final filters = _filters;
    try {
      final result = await ref
          .read(carHireApiProvider)
          .searchCars(
            pickupArea: query.pickupArea,
            startAt: query.startAt,
            endAt: query.endAt,
            operatorId: filters.company?.id,
            transmission: filters.transmission,
            fuelType: filters.fuelType,
            minSeats: filters.minSeats,
            maxRate: filters.maxRate,
            instantOnly: filters.instantOnly,
            text: filters.text,
            page: 1,
            limit: 50,
          );
      if (!ref.mounted) return;
      state = state.copyWith(results: state.results.ready(result));
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(results: state.results.fail(error));
    }
  }

  CarHireSectionState<T> _applySection<T>(
    CarHireSection<T> section,
    CarHireSectionState<T> previous,
  ) {
    final data = section.data;
    if (section.isOk && data != null) {
      return previous.ready(data);
    }
    return previous.fail(
      CarHireApiException(
        message: section.message ?? carHireSectionUnavailableMessage,
      ),
      retryable: section.retryable,
    );
  }
}

final carHireBrowseProvider =
    NotifierProvider<CarHireBrowseController, CarHireBrowseState>(
      CarHireBrowseController.new,
    );

// ---------------------------------------------------------------------------
// Detail availability
// ---------------------------------------------------------------------------

/// Date availability for one listing. The detail page watches this separately
/// from the car itself, so a slow or failing calendar never blocks the page.
final carHireAvailabilityProvider =
    FutureProvider.family<CarHireAvailability, CarHireAvailabilityRequest>((
      ref,
      request,
    ) async {
      return ref
          .watch(carHireApiProvider)
          .getCarAvailability(
            carId: request.carId,
            startAt: request.startAt,
            endAt: request.endAt,
          );
    });
