import 'dart:async';

import 'package:egypt_transport/core/network/api_failure.dart';
import 'package:egypt_transport/core/presentation/trip_presenter.dart';
import 'package:egypt_transport/data/models/models.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:egypt_transport/features/results/view_model/results_cubit.dart';
import 'package:egypt_transport/features/results/view_model/results_state.dart';
import 'package:egypt_transport/features/search/view_model/search_cubit.dart';
import 'package:egypt_transport/features/stops/view_model/stop_search_cubit.dart';
import 'package:egypt_transport/features/stops/view_model/stop_search_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'fixtures.dart';

void main() {
  const presenter = TripPresenter(languageCode: 'ar');

  final here = const TripEndpoint(label: 'A', point: GeoPoint(30.0, 31.2));
  final there = const TripEndpoint(label: 'B', point: GeoPoint(30.1, 31.3));

  group('SearchCubit', () {
    test('cannot search until both ends are chosen', () {
      final cubit = SearchCubit();
      expect(cubit.state.canSearch, isFalse);

      cubit.setFrom(here);
      expect(cubit.state.canSearch, isFalse);

      cubit.setTo(there);
      expect(cubit.state.canSearch, isTrue);
    });

    test('swap exchanges the two ends', () {
      final cubit = SearchCubit()
        ..setFrom(here)
        ..setTo(there)
        ..swap();

      expect(cubit.state.from, there);
      expect(cubit.state.to, here);
    });

    test('"now" is resolved when the search runs, not when it was chosen', () {
      final cubit = SearchCubit();
      final later = DateTime(2026, 9, 21, 18);
      expect(cubit.state.resolvedDeparture(later), later);

      cubit.setDeparture(DateTime(2026, 9, 21, 8));
      expect(cubit.state.resolvedDeparture(later), DateTime(2026, 9, 21, 8));
    });
  });

  group('ResultsCubit', () {
    ResultsCubit build(FakeRepository repo) => ResultsCubit(
          repository: repo,
          presenter: presenter,
          from: here,
          to: there,
          departAt: DateTime(2026, 9, 21, 8),
        );

    test('emits view models, never wire models', () async {
      final repo = FakeRepository(planResponse: PlanResponse.fromJson(planMetro));
      final cubit = build(repo);
      await cubit.load();

      final state = cubit.state as ResultsLoaded;
      expect(state.plan.hasResults, isTrue);
      // Every presentation decision is already made by the time the View
      // sees this.
      expect(state.plan.itineraries.first.legs.first.badge, isNotNull);
    });

    test('an all-walk plan loads successfully with nothing to show', () async {
      // Not a failure: the request worked, and the answer is "there is no
      // route here". The screen needs the note, not an error.
      final repo =
          FakeRepository(planResponse: PlanResponse.fromJson(planNoCoverage));
      final cubit = build(repo);
      await cubit.load();

      final state = cubit.state as ResultsLoaded;
      expect(state.plan.hasResults, isFalse);
      expect(state.plan.note, isNotNull);
    });

    test('a transport failure becomes a failure state, not an exception', () async {
      final repo = FakeRepository(
          error: const ApiFailure(FailureKind.serverDown, status: 503));
      final cubit = build(repo);
      await cubit.load();

      expect(cubit.state, isA<ResultsFailed>());
      expect((cubit.state as ResultsFailed).failure.kind, FailureKind.serverDown);
    });
  });

  group('StopSearchCubit', () {
    StopSearchCubit build(FakeRepository repo,
            {Duration debounce = const Duration(milliseconds: 10)}) =>
        StopSearchCubit(
            repository: repo, presenter: presenter, debounce: debounce);

    test('a single letter searches nothing', () async {
      final repo = FakeRepository();
      final cubit = build(repo)..queryChanged('ا');

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(repo.stopQueries, isEmpty);
      expect(cubit.state, isA<StopSearchIdle>());
    });

    test('typing is debounced into one request', () async {
      final repo = FakeRepository(stopsResponse: StopsResponse.fromJson(stopsMoneeb));
      final cubit = build(repo)
        ..queryChanged('ال')
        ..queryChanged('المن')
        ..queryChanged('المنيب');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(repo.stopQueries, ['المنيب']);
      expect(cubit.state, isA<StopSearchLoaded>());
    });

    test('a slow earlier request cannot overwrite a newer answer', () async {
      // On a weak connection this is not hypothetical: the two-letter query
      // matches hundreds of stops and takes longest, so it is exactly the one
      // that lands last.
      final repo = FakeRepository(stopsResponse: StopsResponse.fromJson(stopsMoneeb))
        ..delays['ال'] = const Duration(milliseconds: 80);
      final cubit = build(repo);

      unawaited(cubit.search('ال'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.search('المنيب');

      final after = cubit.state as StopSearchLoaded;
      expect(after.query, 'المنيب');

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect((cubit.state as StopSearchLoaded).query, 'المنيب',
          reason: 'the stale response must be discarded');
    });

    test('reports that there are more matches than it showed', () async {
      final repo = FakeRepository(stopsResponse: StopsResponse.fromJson(stopsMoneeb));
      final cubit = build(repo);
      await cubit.search('المنيب');

      final state = cubit.state as StopSearchLoaded;
      expect(state.truncated, isTrue);
      expect(state.totalMatches, greaterThan(state.results.length));
    });
  });
}
