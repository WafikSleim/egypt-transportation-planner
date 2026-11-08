import 'dart:async';

import 'package:egypt_transport/core/network/api_failure.dart';
import 'package:egypt_transport/core/presentation/place_presenter.dart';
import 'package:egypt_transport/core/presentation/trip_presenter.dart';
import 'package:egypt_transport/core/storage/key_value_store.dart';
import 'package:egypt_transport/core/theme/app_theme.dart';
import 'package:egypt_transport/core/widgets/endpoint_mark.dart';
import 'package:egypt_transport/data/models/models.dart';
import 'package:egypt_transport/data/models/place_models.dart';
import 'package:egypt_transport/data/repositories/trip_history.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:egypt_transport/features/picker/view/picker_page.dart';
import 'package:egypt_transport/features/picker/view_model/picker_cubit.dart';
import 'package:egypt_transport/features/picker/view_model/picker_state.dart';
import 'package:egypt_transport/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_places_repository.dart';
import 'fake_repository.dart';
import 'fixtures.dart';

/// The unified picker (#15, #17): one field over stops, places and recents.
void main() {
  const tripPresenter = TripPresenter(languageCode: 'ar');
  const placePresenter = PlacePresenter(languageCode: 'ar');

  PickerCubit build(
    FakeRepository planner,
    FakePlacesRepository places, {
    TripHistory? history,
    GeoPoint? near,
  }) => PickerCubit(
    planner: planner,
    places: places,
    tripPresenter: tripPresenter,
    placePresenter: placePresenter,
    history: history,
    near: near,
    debounce: const Duration(milliseconds: 10),
  );

  FakeRepository stopsRepo() =>
      FakeRepository(stopsResponse: StopsResponse.fromJson(stopsMoneeb));
  FakePlacesRepository placesRepo() =>
      FakePlacesRepository(searchResponse: PlacesResponse.fromJson(placesAr));

  group('PickerCubit', () {
    test('a single letter searches neither index', () async {
      final planner = stopsRepo();
      final places = placesRepo();
      final cubit = build(planner, places)..queryChanged('ا');

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(planner.stopQueries, isEmpty);
      expect(places.queries, isEmpty);
      expect(cubit.state, isA<PickerIdle>());
    });

    test('typing is debounced into one request to each index', () async {
      final planner = stopsRepo();
      final places = placesRepo();
      final cubit = build(planner, places)
        ..queryChanged('ال')
        ..queryChanged('المن')
        ..queryChanged('المنيب');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(planner.stopQueries, ['المنيب']);
      expect(places.queries, ['المنيب']);
      expect(cubit.state, isA<PickerLoaded>());
    });

    test('both indexes answer, and each keeps its own credit', () async {
      final cubit = build(stopsRepo(), placesRepo());
      await cubit.search('المنيب');

      final s = cubit.state as PickerLoaded;
      expect(s.stops, isNotEmpty);
      expect(s.places, hasLength(3));
      expect(s.stopsAttribution!.text, contains('Transport for Cairo'));
      expect(s.placesAttribution!.text, '© OpenStreetMap contributors');
      expect(s.stopsUnavailable, isFalse);
      expect(s.placesUnavailable, isFalse);
    });

    test(
      'the two requests are in flight together, not one after the other',
      () async {
        // If they were serial, the second would not start until the first had
        // finished; with a delay on stops, places is asked for straight away.
        final planner = stopsRepo()
          ..delays['المنيب'] = const Duration(milliseconds: 80);
        final places = placesRepo();
        final cubit = build(planner, places);

        unawaited(cubit.search('المنيب'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(places.queries, ['المنيب']);
        expect(cubit.state, isA<PickerLoading>());
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(cubit.state, isA<PickerLoaded>());
      },
    );

    test(
      'a place index that is down degrades to stops, not to an error',
      () async {
        // The API's own docstring says the client is expected to do exactly
        // this: a 503 from /places must not take stop search down with it.
        final places = FakePlacesRepository(
          error: const ApiFailure(FailureKind.serverDown, status: 503),
        );
        final cubit = build(stopsRepo(), places);
        await cubit.search('المنيب');

        final s = cubit.state as PickerLoaded;
        expect(s.stops, isNotEmpty);
        expect(s.places, isEmpty);
        expect(s.placesUnavailable, isTrue);
        expect(s.stopsUnavailable, isFalse);
        expect(
          s.placesAttribution,
          isNull,
          reason:
              'nothing from OSM is on screen, so there is nothing to credit',
        );
      },
    );

    test('stops being down degrades to places', () async {
      final planner = FakeRepository(
        error: const ApiFailure(FailureKind.offline),
      );
      final cubit = build(planner, placesRepo());
      await cubit.search('كايرو');

      final s = cubit.state as PickerLoaded;
      expect(s.places, hasLength(3));
      expect(s.stopsUnavailable, isTrue);
    });

    test('only when both fail is it an error', () async {
      final planner = FakeRepository(
        error: const ApiFailure(FailureKind.timedOut),
      );
      final places = FakePlacesRepository(
        error: const ApiFailure(FailureKind.timedOut),
      );
      final cubit = build(planner, places);
      await cubit.search('كايرو');

      expect(cubit.state, isA<PickerFailed>());
      expect((cubit.state as PickerFailed).failure.kind, FailureKind.timedOut);
    });

    test('a slow earlier request cannot overwrite a newer answer', () async {
      final planner = stopsRepo()
        ..delays['ال'] = const Duration(milliseconds: 80);
      final places = placesRepo()
        ..delays['ال'] = const Duration(milliseconds: 80);
      final cubit = build(planner, places);

      unawaited(cubit.search('ال'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.search('المنيب');
      expect((cubit.state as PickerLoaded).query, 'المنيب');

      await Future<void>.delayed(const Duration(milliseconds: 140));
      expect(
        (cubit.state as PickerLoaded).query,
        'المنيب',
        reason: 'the stale response must be discarded',
      );
    });

    test('places are ordered from the point it was given, and from none '
        'otherwise', () async {
      final places = placesRepo();
      await build(stopsRepo(), places).search('كايرو');
      expect(places.nearValues.single, isNull);

      const origin = GeoPoint(30.0444, 31.2357);
      final places2 = placesRepo();
      await build(stopsRepo(), places2, near: origin).search('كايرو');
      expect(places2.nearValues.single, origin);
    });

    test('a filter narrows the list without asking again', () async {
      final planner = stopsRepo();
      final places = placesRepo();
      final cubit = build(planner, places);
      await cubit.search('المنيب');

      cubit.setFilter(PickerFilter.places);
      var s = cubit.state as PickerLoaded;
      expect(s.showsStops, isFalse);
      expect(s.showsPlaces, isTrue);
      expect(s.isEmpty, isFalse);

      cubit.setFilter(PickerFilter.stops);
      s = cubit.state as PickerLoaded;
      expect(s.showsPlaces, isFalse);
      expect(planner.stopQueries, hasLength(1));
      expect(places.queries, hasLength(1));
    });

    test('under "all" the two sources are interleaved, not stacked', () async {
      // Twenty prefix matches stacked above the places would push the mall
      // somebody typed off the screen.
      final cubit = build(stopsRepo(), placesRepo());
      await cubit.search('المنيب');

      final entries = (cubit.state as PickerLoaded).entries;
      expect(entries[0], isA<StopEntry>());
      expect(entries[1], isA<PlaceEntry>());
      expect(entries[2], isA<StopEntry>());
      expect(entries[3], isA<PlaceEntry>());
      final loaded = cubit.state as PickerLoaded;
      expect(entries, hasLength(loaded.stops.length + loaded.places.length));

      cubit.setFilter(PickerFilter.places);
      expect(
        (cubit.state as PickerLoaded).entries.every((e) => e is PlaceEntry),
        isTrue,
      );
    });

    test('an empty answer from both is empty, and not a failure', () async {
      final cubit = build(FakeRepository(), FakePlacesRepository());
      await cubit.search('ءءءء');
      final s = cubit.state as PickerLoaded;
      expect(s.isEmpty, isTrue);
      expect(s.stopsUnavailable, isFalse);
      expect(s.placesUnavailable, isFalse);
    });
  });

  group('before anything is typed', () {
    TripEndpoint stop(String id, String name) => TripEndpoint(
      label: name,
      point: const GeoPoint(30.04, 31.23),
      stopId: id,
    );
    TripEndpoint place(String id, String name, double lat) =>
        TripEndpoint(label: name, point: GeoPoint(lat, 31.4), placeId: id);

    test('recents come first, newest first', () async {
      final history = TripHistory(InMemoryStore());
      await history.remember(stop('1', 'المنيب'));
      await history.remember(place('w101', 'كايرو فستيفال', 30.02));

      final idle =
          build(
                FakeRepository(),
                FakePlacesRepository(),
                history: history,
              ).state
              as PickerIdle;
      expect(idle.recents.map((e) => e.label), ['كايرو فستيفال', 'المنيب']);
      expect(idle.recents.first.kind, EndpointKind.place);
    });

    test('saved trips contribute stops and places, once each, and never '
        'the "my location" fix', () async {
      final history = TripHistory(InMemoryStore());
      final home = stop('2:1145', 'المنيب');
      final mall = place('w101', 'كايرو فستيفال', 30.02);
      const here = TripEndpoint(label: 'مكاني', point: GeoPoint(30.05, 31.25));
      await history.save(here, mall);
      await history.save(home, mall);

      final idle =
          build(
                FakeRepository(),
                FakePlacesRepository(),
                history: history,
              ).state
              as PickerIdle;
      expect(idle.saved.map((e) => e.label), ['كايرو فستيفال', 'المنيب']);
      expect(
        idle.saved.where((e) => e.kind == EndpointKind.point),
        isEmpty,
        reason:
            'a my-location fix is true for one morning; offering it back as '
            'somewhere somebody goes would send them from where they were',
      );
    });

    test(
      'an endpoint already in recents is not listed again as saved',
      () async {
        final history = TripHistory(InMemoryStore());
        final mall = place('w101', 'كايرو فستيفال', 30.02);
        await history.save(stop('1', 'المنيب'), mall);
        await history.remember(mall);

        final idle =
            build(
                  FakeRepository(),
                  FakePlacesRepository(),
                  history: history,
                ).state
                as PickerIdle;
        expect(idle.recents.map((e) => e.label), ['كايرو فستيفال']);
        expect(idle.saved.map((e) => e.label), ['المنيب']);
      },
    );

    test('clearing recents empties them', () async {
      final history = TripHistory(InMemoryStore());
      await history.remember(stop('1', 'المنيب'));
      final cubit = build(
        FakeRepository(),
        FakePlacesRepository(),
        history: history,
      );
      await cubit.clearRecents();
      expect((cubit.state as PickerIdle).recents, isEmpty);
    });
  });

  // ------------------------------------------------------------------ widgets

  var pumps = 0;

  Widget host(
    Widget child, {
    Locale locale = const Locale('ar'),
    Brightness brightness = Brightness.light,
  }) => ScreenUtilInit(
    key: ValueKey(pumps++),
    designSize: const Size(390, 844),
    minTextAdapt: true,
    builder: (context, _) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: child,
    ),
  );

  PickerPage page({
    FakeRepository? planner,
    FakePlacesRepository? places,
    TripHistory? history,
    GeoPoint? near,
  }) => PickerPage(
    title: 'رايح فين',
    planner: planner ?? stopsRepo(),
    places: places ?? placesRepo(),
    history: history,
    near: near,
  );

  /// The design frame. At the 800x600 default the note and the field leave
  /// room for three rows, a lazy list builds only those, and a row that is
  /// off-screen is a row that "is not there" to a finder.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  group('the picker screen', () {
    setUp(() {});
    testWidgets('states how the two indexes match, before anyone types', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(page()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('المحطات بتتلاقى من أول الاسم'),
        findsOneWidget,
      );
      expect(find.textContaining('والأماكن بأي جزء منه'), findsOneWidget);
    });

    testWidgets('shows stops and places in one list, with different marks', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(page()));
      await tester.pumpAndSettle();
      await type(tester, 'المنيب');

      final kinds = tester
          .widgetList<EndpointMark>(find.byType(EndpointMark))
          .map((m) => m.kind)
          .toSet();
      expect(kinds, containsAll([EndpointKind.stop, EndpointKind.place]));
      expect(find.textContaining('كايرو فستيفال سيتي مول'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a place with no Arabic name is shown in Latin and says why', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(page()));
      await tester.pumpAndSettle();
      await type(tester, 'كايرو');

      expect(
        find.textContaining('American University in Cairo'),
        findsOneWidget,
      );
      expect(find.text('مافيش اسم عربي في الخريطة'), findsOneWidget);
      // Only the one place lacks an Arabic name: the note is not stamped on
      // the others.
      expect(find.text('مافيش اسم عربي في الخريطة'), findsOneWidget);
    });

    testWidgets('credits both datasets, each from its own response', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(page()));
      await tester.pumpAndSettle();
      await type(tester, 'المنيب');
      await tester.scrollUntilVisible(
        find.textContaining('OpenStreetMap contributors'),
        200,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.textContaining('Transport for Cairo'), findsOneWidget);
      expect(
        find.textContaining('© OpenStreetMap contributors'),
        findsOneWidget,
      );
    });

    testWidgets('a place index that is down leaves stops on screen and says '
        'so quietly', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          page(
            places: FakePlacesRepository(
              error: const ApiFailure(FailureKind.serverDown, status: 503),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await type(tester, 'المنيب');

      expect(find.textContaining('الأماكن مش متاحة دلوقتي'), findsOneWidget);
      expect(find.byType(EndpointMark), findsWidgets);
      expect(find.text('جرّب تاني'), findsNothing);
    });

    testWidgets('says places are ordered from the start point only when they '
        'are', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(page()));
      await tester.pumpAndSettle();
      await type(tester, 'كايرو');
      await tester.scrollUntilVisible(
        find.textContaining('OpenStreetMap contributors'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('مرتّبة حسب القرب'), findsNothing);

      await tester.pumpWidget(
        host(page(near: const GeoPoint(30.0444, 31.2357))),
      );
      await tester.pumpAndSettle();
      await type(tester, 'كايرو');
      await tester.scrollUntilVisible(
        find.textContaining('مرتّبة حسب القرب'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('مرتّبة حسب القرب'), findsOneWidget);
    });

    testWidgets('shows recents and saved places before any typing', (
      tester,
    ) async {
      phone(tester);
      final history = TripHistory(InMemoryStore());
      await history.remember(
        const TripEndpoint(
          label: 'كايرو فستيفال',
          point: GeoPoint(30.02, 31.4),
          placeId: 'w101',
        ),
      );
      await history.save(
        const TripEndpoint(
          label: 'المنيب',
          point: GeoPoint(29.98, 31.21),
          stopId: '2:1145',
        ),
        const TripEndpoint(
          label: 'العتبة',
          point: GeoPoint(30.05, 31.25),
          stopId: '1:att',
        ),
      );

      await tester.pumpWidget(host(page(history: history)));
      await tester.pumpAndSettle();

      expect(find.text('آخر الأماكن'), findsOneWidget);
      expect(find.textContaining('كايرو فستيفال'), findsOneWidget);
      expect(find.text('من مشاويرك المحفوظة'), findsOneWidget);
      expect(find.textContaining('العتبة'), findsOneWidget);
    });

    testWidgets('tapping a place pops a place endpoint', (tester) async {
      phone(tester);
      TripEndpoint? picked;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await Navigator.of(
                  context,
                ).push<TripEndpoint>(MaterialPageRoute(builder: (_) => page()));
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await type(tester, 'كايرو');

      await tester.tap(find.textContaining('كايرو فستيفال سيتي مول'));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
      expect(picked!.kind, EndpointKind.place);
      expect(picked!.placeId, 'w101');
      expect(picked!.point.lat, 30.0287);
    });

    testWidgets('a filter chip narrows the list', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(page()));
      await tester.pumpAndSettle();
      await type(tester, 'المنيب');

      await tester.tap(find.text('أماكن'));
      await tester.pumpAndSettle();
      final kinds = tester
          .widgetList<EndpointMark>(find.byType(EndpointMark))
          .map((m) => m.kind)
          .toSet();
      expect(kinds, {EndpointKind.place});
    });

    for (final brightness in Brightness.values) {
      testWidgets('lays out in English in ${brightness.name}', (tester) async {
        phone(tester);
        // English on purpose: widget tests render a placeholder font whose
        // glyphs are all a full em wide, so the Arabic strings are wider than
        // the screen and cannot tell a broken layout from a working one.
        await tester.pumpWidget(
          host(
            PickerPage(
              title: 'Where to',
              planner: FakeRepository(
                stopsResponse: StopsResponse.fromJson(stopsMoneeb),
              ),
              places: FakePlacesRepository(
                searchResponse: PlacesResponse.fromJson(placesEn),
              ),
            ),
            locale: const Locale('en'),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        await type(tester, 'festival');

        expect(find.textContaining('Cairo Festival City Mall'), findsOneWidget);
        expect(find.text('Stops'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('The map has no English name for this'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(
          find.text('The map has no English name for this'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
