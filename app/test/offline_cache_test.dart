import 'dart:convert';

import 'package:egypt_transport/core/network/api_client.dart';
import 'package:egypt_transport/core/network/api_failure.dart';
import 'package:egypt_transport/core/presentation/trip_presenter.dart';
import 'package:egypt_transport/core/storage/key_value_store.dart';
import 'package:egypt_transport/data/cache/plan_cache.dart';
import 'package:egypt_transport/data/models/models.dart';
import 'package:egypt_transport/data/repositories/planner_repository_impl.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:egypt_transport/features/results/view_model/results_cubit.dart';
import 'package:egypt_transport/features/results/view_model/results_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_repository.dart';
import 'fixtures.dart';

/// Offline and slow-connection behaviour (issue #26).
///
/// The phone this is aimed at is a low-end Android on patchy data, which in
/// Cairo is the normal case. So the cases below are not edge cases: they are
/// what most sessions look like some of the time.
void main() {
  const from = GeoPoint(29.8490, 31.3340);
  const to = GeoPoint(30.1220, 31.2450);
  final departAt = DateTime(2026, 9, 22, 8);
  final savedAt = DateTime(2026, 9, 22, 8, 15);

  PlanCache cacheAt(DateTime now, [KeyValueStore? store]) =>
      PlanCache(store ?? InMemoryStore(), now: () => now);

  Future<PlanCache> savedCache({
    required KeyValueStore store,
    Map<String, dynamic>? body,
    DateTime? at,
    DateTime? departure,
    String lang = 'ar',
    GeoPoint fromPoint = from,
    GeoPoint toPoint = to,
  }) async {
    final json = body ?? planMetro;
    final cache = cacheAt(at ?? savedAt, store);
    await cache.save(
      from: fromPoint,
      to: toPoint,
      fromLabel: 'حلوان',
      toLabel: 'شبرا الخيمة',
      departAt: departure ?? departAt,
      arriveBy: false,
      lang: lang,
      parsed: PlanResponse.fromJson(json),
      body: json,
    );
    return cache;
  }

  CachedPlan? readAt(
    KeyValueStore store,
    DateTime now, {
    GeoPoint fromPoint = from,
    GeoPoint toPoint = to,
    DateTime? departure,
    String lang = 'ar',
  }) => cacheAt(now, store).read(
    from: fromPoint,
    to: toPoint,
    departAt: departure ?? departAt,
    arriveBy: false,
    lang: lang,
  );

  group('PlanCache', () {
    test('a saved plan comes back as the same plan', () async {
      // The body is stored verbatim and re-read through the same parser the
      // fixtures hold honest, so this is also a check that nothing is lost on
      // the way to storage and back — legs, Arabic names and all.
      final store = InMemoryStore();
      await savedCache(store: store);

      final cached = readAt(store, savedAt.add(const Duration(minutes: 20)))!;
      final live = PlanResponse.fromJson(planMetro);

      expect(cached.response.itineraries.length, live.itineraries.length);
      expect(
        cached.response.itineraries.first.legs.first.from.name,
        live.itineraries.first.legs.first.from.name,
      );
      expect(cached.savedAt, savedAt);
      expect(cached.fromLabel, 'حلوان');
    });

    test('past the age bound it is not offered at all', () async {
      // The bound is the point of the feature as much as the cache is. An
      // itinerary whose times are half a day old is not a worse answer than
      // "no" — it is a different answer to a question nobody asked.
      final store = InMemoryStore();
      await savedCache(store: store);

      expect(
        readAt(
          store,
          savedAt.add(PlanCache.maxAge - const Duration(minutes: 1)),
        ),
        isNotNull,
      );
      expect(
        readAt(
          store,
          savedAt.add(PlanCache.maxAge + const Duration(minutes: 1)),
        ),
        isNull,
      );
    });

    test(
      'a plan for a different departure is not an answer to this one',
      () async {
        // Plan tomorrow's 08:00 trip this afternoon, lose signal an hour later,
        // ask for a trip now: same endpoints, one hour old, and the itinerary
        // is tomorrow morning's. Age alone does not catch this.
        final store = InMemoryStore();
        await savedCache(
          store: store,
          departure: departAt.add(const Duration(days: 1)),
        );

        expect(
          readAt(store, savedAt.add(const Duration(minutes: 30))),
          isNull,
          reason: 'the saved plan departs tomorrow',
        );
      },
    );

    test(
      'a starting point a block away still matches; a district away does not',
      () async {
        // The commonest offline case starts from "my location", and two GPS
        // fixes a minute apart are never the same pair of doubles. An exact
        // match would make the whole feature dead code.
        final store = InMemoryStore();
        await savedCache(store: store);

        final now = savedAt.add(const Duration(minutes: 10));
        expect(
          readAt(store, now, fromPoint: const GeoPoint(29.84955, 31.33410)),
          isNotNull,
          reason: 'about 70 m away, the same walk to the same stop',
        );
        expect(
          readAt(store, now, fromPoint: const GeoPoint(29.8600, 31.3340)),
          isNull,
          reason: 'over a kilometre away is a different question',
        );
      },
    );

    test(
      'a plan fetched in Arabic is not offered on an English screen',
      () async {
        // Stop and route names are localised server-side, so the stored body is
        // in whatever language it was fetched in. Replaying it after a language
        // switch would print Arabic stop names through an English layout.
        final store = InMemoryStore();
        await savedCache(store: store, lang: 'ar');

        expect(
          readAt(store, savedAt.add(const Duration(minutes: 5)), lang: 'en'),
          isNull,
        );
      },
    );

    test('unreadable stored text returns null rather than throwing', () {
      // Same rule as the settings store: data the user can neither see nor
      // clear without reinstalling must never be able to take a screen down.
      for (final junk in [
        'not json at all',
        '{"version": 99, "body": {}}',
        '{"version": 1, "saved_at": "yesterday", "body": {}}',
        '{"version": 1, "saved_at": "2026-09-22T08:15:00.000", '
            '"depart_at": "2026-09-22T08:00:00.000", "from": "x", "to": "y", '
            '"arrive_by": false, "lang": "ar", "body": {}}',
      ]) {
        final store = InMemoryStore({'plan_cache.last': junk});
        expect(() => readAt(store, savedAt), returnsNormally, reason: junk);
        expect(readAt(store, savedAt), isNull, reason: junk);
      }
    });

    test('a plan with nothing in it is not saved', () async {
      // Replaying "no route between these two points" from storage adds
      // nothing a fresh failure does not already say, and it would put the
      // emptiest screen in the app behind a banner calling it a saved answer.
      final store = InMemoryStore();
      await savedCache(store: store, body: planNoCoverage);

      expect(store.contents, isEmpty);
    });

    test('an implausibly large body is not stored', () async {
      // `SharedPreferences` is read synchronously before the first frame, so
      // anything kept here is paid for on every cold start — the thing this
      // issue asks to be measured.
      final store = InMemoryStore();
      final bloated = {
        ...planMetro,
        'note': 'x' * (PlanCache.maxBodyBytes + 1),
      };
      await savedCache(store: store, body: bloated);

      expect(store.contents, isEmpty);
    });
  });

  group('the repository records what it plans', () {
    ApiClient client(Object body, {int status = 200}) => ApiClient(
      baseUrl: 'http://test',
      languageCode: () => 'ar',
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode(body)),
          status,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    test('a successful plan is saved without the screen asking', () async {
      // Saved by the repository for the same reason `lang` is added by
      // ApiClient: there must be no screen that can plan a trip and forget to
      // record it.
      final store = InMemoryStore();
      final repo = PlannerRepositoryImpl(
        client(planMetro),
        cache: PlanCache(store, now: () => savedAt),
      );

      await repo.plan(
        from: from,
        to: to,
        departAt: departAt,
        fromLabel: 'حلوان',
        toLabel: 'شبرا الخيمة',
      );

      final cached = repo.lastPlan(from: from, to: to, departAt: departAt);
      expect(cached, isNotNull);
      expect(cached!.fromLabel, 'حلوان');
    });

    test('a failed request leaves nothing behind', () async {
      final store = InMemoryStore();
      final repo = PlannerRepositoryImpl(
        client({}, status: 503),
        cache: PlanCache(store, now: () => savedAt),
      );

      await expectLater(
        repo.plan(from: from, to: to, departAt: departAt),
        throwsA(isA<ApiFailure>()),
      );
      expect(store.contents, isEmpty);
    });

    test('with no cache at all the repository still works', () {
      // Every phone before its first successful search, and any phone where
      // storage could not be opened.
      final repo = PlannerRepositoryImpl(client(planMetro));
      expect(repo.lastPlan(from: from, to: to, departAt: departAt), isNull);
    });
  });

  group('ResultsCubit when the request fails', () {
    const presenter = TripPresenter(languageCode: 'ar');
    const here = TripEndpoint(label: 'حلوان', point: from);
    const there = TripEndpoint(label: 'شبرا الخيمة', point: to);

    ResultsCubit build(
      FakeRepository repo, {
      Duration slowAfter = const Duration(seconds: 4),
    }) => ResultsCubit(
      repository: repo,
      presenter: presenter,
      from: here,
      to: there,
      departAt: departAt,
      slowAfter: slowAfter,
    );

    CachedPlan saved() => CachedPlan(
      response: PlanResponse.fromJson(planMetro),
      savedAt: savedAt,
      departAt: departAt,
      fromLabel: 'حلوان',
      toLabel: 'شبرا الخيمة',
    );

    test('a saved answer is shown, and marked as one', () async {
      final repo = FakeRepository(error: const ApiFailure(FailureKind.offline))
        ..cached = saved();

      final cubit = build(repo);
      await cubit.load();

      final state = cubit.state as ResultsFromCache;
      expect(state.savedAt, savedAt);
      expect(state.fromLabel, 'حلوان');
      // The mark is on the view models, not only on the state: the detail
      // screen is handed one itinerary and nothing else, so an itinerary that
      // did not carry its own age could be rendered as a live one.
      expect(
        state.plan.itineraries.every((i) => i.cachedAt == savedAt),
        isTrue,
      );
      await cubit.close();
    });

    test('with nothing saved it is an honest error', () async {
      final repo = FakeRepository(
        error: const ApiFailure(FailureKind.timedOut),
      );

      final cubit = build(repo);
      await cubit.load();

      expect(cubit.state, isA<ResultsFailed>());
      expect((cubit.state as ResultsFailed).failure.kind, FailureKind.timedOut);
      await cubit.close();
    });

    test('a live answer is never marked as saved', () async {
      final repo = FakeRepository(
        planResponse: PlanResponse.fromJson(planMetro),
      )..cached = saved();

      final cubit = build(repo);
      await cubit.load();

      final state = cubit.state as ResultsLoaded;
      expect(state.plan.cachedAt, isNull);
      expect(state.plan.itineraries.every((i) => i.cachedAt == null), isTrue);
      await cubit.close();
    });

    test('the endpoint labels are passed down to be recorded', () async {
      // They are not sent to the router. They exist so an offline answer can
      // say which trip it was an answer to, which is what makes a match
      // within 150 m legible rather than silent.
      final repo = FakeRepository(
        planResponse: PlanResponse.fromJson(planMetro),
      );

      final cubit = build(repo);
      await cubit.load();

      expect(repo.recordedFromLabel, 'حلوان');
      expect(repo.recordedToLabel, 'شبرا الخيمة');
      await cubit.close();
    });
  });

  group('the wait has a ceiling', () {
    const presenter = TripPresenter(languageCode: 'ar');

    test('a slow request admits to being slow, then still finishes', () async {
      // "No spinner that never ends" has two halves: the request carries a
      // hard timeout, and the screen stops pretending the wait is going
      // normally before that timeout arrives.
      final repo = FakeRepository(
        planResponse: PlanResponse.fromJson(planMetro),
      )..planDelay = const Duration(milliseconds: 60);

      final cubit = ResultsCubit(
        repository: repo,
        presenter: presenter,
        from: const TripEndpoint(label: 'a', point: from),
        to: const TripEndpoint(label: 'b', point: to),
        departAt: departAt,
        slowAfter: const Duration(milliseconds: 10),
      );

      final seen = <ResultsState>[];
      final sub = cubit.stream.listen(seen.add);
      await cubit.load();
      await sub.cancel();

      expect(
        seen.whereType<ResultsLoading>().any((s) => s.slow),
        isTrue,
        reason: 'the wait says so before the timeout does',
      );
      expect(cubit.state, isA<ResultsLoaded>());
      await cubit.close();
    });

    test('the slow timer does not outlive the screen', () async {
      // A pending timer after the widget tree is gone is both a leak and, in
      // a widget test, a failure.
      final repo = FakeRepository(
        planResponse: PlanResponse.fromJson(planMetro),
      );
      final cubit = ResultsCubit(
        repository: repo,
        presenter: presenter,
        from: const TripEndpoint(label: 'a', point: from),
        to: const TripEndpoint(label: 'b', point: to),
        departAt: departAt,
        slowAfter: const Duration(milliseconds: 5),
      );

      await cubit.load();
      await cubit.close();

      // Long enough for a live timer to have fired into a closed cubit.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cubit.state, isA<ResultsLoaded>());
    });
  });
}
