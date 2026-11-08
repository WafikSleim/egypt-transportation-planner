import 'dart:async';

import 'package:egypt_transport/core/network/api_failure.dart';
import 'package:egypt_transport/core/presentation/place_presenter.dart';
import 'package:egypt_transport/core/theme/app_theme.dart';
import 'package:egypt_transport/data/models/place_models.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:egypt_transport/features/map_pick/view/map_pick_page.dart';
import 'package:egypt_transport/features/map_pick/view_model/map_pick_cubit.dart';
import 'package:egypt_transport/features/map_pick/view_model/map_pick_state.dart';
import 'package:egypt_transport/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_places_repository.dart';
import 'fake_repository.dart';
import 'fixtures.dart';

/// Pick a destination on the map (#16, P-18).
///
/// `MapLibreMap` is a platform view and cannot be dragged on the Dart VM, so
/// these drive the ViewModel's `pointSettled` directly — which is the whole of
/// what the map widget hands over — and stub the surface.
void main() {
  const pin = GeoPoint(30.0312, 31.4601);
  const presenter = PlacePresenter(languageCode: 'ar');

  FakeRepository planner({bool near = true}) => FakeRepository(
    nearbyResponse: near ? NearbyStopsResponse.fromJson(stopsNearby) : null,
  );
  FakePlacesRepository places() => FakePlacesRepository(
    reverseResponse: PlacesResponse.fromJson(placesReverse),
  );

  MapPickCubit build(FakeRepository p, FakePlacesRepository pl) =>
      MapPickCubit(places: pl, planner: p, presenter: presenter);

  group('MapPickCubit', () {
    test('asks both services, separately, about the pin', () async {
      final p = planner();
      final pl = places();
      await build(p, pl).pointSettled(pin);

      expect(pl.reverseCalls, [pin]);
      expect(p.nearbyCalls, [pin]);
    });

    test('shows the name and the nearest stop as two things, each with its '
        'own credit', () async {
      final cubit = build(planner(), places());
      await cubit.pointSettled(pin);

      final s = cubit.state as MapPickReady;
      expect(s.place!.name, 'شارع التسعين الجنوبي');
      expect(s.nearestStop!.name, 'المصراوية');
      expect(s.nearestStop!.distanceM, 239);
      expect(s.placesAttribution!.text, '© OpenStreetMap contributors');
      expect(s.stopsAttribution!.text, contains('Transport for Cairo'));
    });

    test('a point with no name is a finding, not a failure', () async {
      final cubit = build(
        planner(),
        FakePlacesRepository(
          reverseResponse: PlacesResponse.fromJson(placesReverseEmpty),
        ),
      );
      await cubit.pointSettled(pin);

      final s = cubit.state as MapPickReady;
      expect(s.place, isNull);
      expect(
        s.nameUnavailable,
        isFalse,
        reason:
            'the lookup worked and found nothing — that is not the same '
            'as the lookup failing',
      );
    });

    test(
      'a failed name lookup is unavailable, and the stop still stands',
      () async {
        final cubit = build(
          planner(),
          FakePlacesRepository(
            error: const ApiFailure(FailureKind.serverDown, status: 503),
          ),
        );
        await cubit.pointSettled(pin);

        final s = cubit.state as MapPickReady;
        expect(s.nameUnavailable, isTrue);
        expect(s.nearestStop, isNotNull);
      },
    );

    test(
      'a failed stop lookup is unavailable, and the name still stands',
      () async {
        // Also the case for a server that predates /stops/nearby: a 404 is the
        // same to this screen as any other reason the answer is not there.
        final cubit = build(
          FakeRepository(
            nearbyError: const ApiFailure(FailureKind.badRequest, status: 404),
          ),
          places(),
        );
        await cubit.pointSettled(pin);

        final s = cubit.state as MapPickReady;
        expect(s.stopUnavailable, isTrue);
        expect(s.place, isNotNull);
      },
    );

    test('no stop within the radius is not "unavailable"', () async {
      final cubit = build(FakeRepository(), places());
      await cubit.pointSettled(pin);

      final s = cubit.state as MapPickReady;
      expect(s.nearestStop, isNull);
      expect(s.stopUnavailable, isFalse);
      expect(s.stopRadiusM, MapPickCubit.stopRadiusM);
    });

    test('a point outside the covered area spends no request', () async {
      final p = planner();
      final pl = places();
      final cubit = build(p, pl);
      await cubit.pointSettled(const GeoPoint(25.7, 32.6)); // Luxor

      expect(cubit.state, isA<MapPickOutside>());
      expect(pl.reverseCalls, isEmpty);
      expect(p.nearbyCalls, isEmpty);
    });

    test('a drag that settled again overtakes the one before it', () async {
      final cubit = build(planner(), places());
      const later = GeoPoint(30.05, 31.3);

      unawaited(cubit.pointSettled(pin));
      await cubit.pointSettled(later);

      expect((cubit.state as MapPickReady).point, later);
    });

    group('confirming', () {
      test('is nothing until there is something to confirm', () {
        expect(
          build(planner(), places()).confirmedEndpoint(unnamedLabel: 'x'),
          isNull,
        );
      });

      test(
        'goes to the pin, not to the coordinates of the named place',
        () async {
          // A street's stored position can be a long way from where somebody
          // pointed. The name is a label; the trip is planned from the pin.
          final cubit = build(planner(), places());
          await cubit.pointSettled(pin);

          final e = cubit.confirmedEndpoint(unnamedLabel: 'x')!;
          expect(e.point, pin);
          expect(e.label, 'شارع التسعين الجنوبي');
          expect(e.kind, EndpointKind.point);
          expect(e.stopId, isNull);
          expect(e.placeId, isNull);
        },
      );

      test(
        'with no name at all, falls back to the label it is given',
        () async {
          final cubit = build(
            FakeRepository(),
            FakePlacesRepository(
              reverseResponse: PlacesResponse.fromJson(placesReverseEmpty),
            ),
          );
          await cubit.pointSettled(pin);

          final e = cubit.confirmedEndpoint(unnamedLabel: 'نقطة (30.0312)')!;
          expect(e.label, 'نقطة (30.0312)');
          expect(e.point, pin);
        },
      );

      test('works when the name lookup failed — the point is enough', () async {
        final cubit = build(
          planner(),
          FakePlacesRepository(error: const ApiFailure(FailureKind.offline)),
        );
        await cubit.pointSettled(pin);
        expect(cubit.confirmedEndpoint(unnamedLabel: 'x'), isNotNull);
      });
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

  MapPickPage page({
    FakeRepository? planner0,
    FakePlacesRepository? places0,
    GeoPoint? center,
  }) => MapPickPage(
    planner: planner0 ?? planner(),
    places: places0 ?? places(),
    initialCenter: center ?? pin,
    surfaceBuilder: (_, _) => const SizedBox.expand(),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('the map-pick screen', () {
    testWidgets('names the place and the nearest stop, and credits both', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(page()));
      await tester.pumpAndSettle();

      expect(find.textContaining('شارع التسعين الجنوبي'), findsOneWidget);
      expect(find.text('أقرب محطة'), findsOneWidget);
      expect(find.textContaining('المصراوية'), findsOneWidget);
      expect(find.textContaining('239 م'), findsOneWidget);
      expect(find.textContaining('OpenStreetMap contributors'), findsWidgets);
      expect(find.textContaining('Transport for Cairo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says the name is OpenStreetMap\'s, not the transit data\'s', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(page()));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.textContaining('مش من بيانات المواصلات'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('OpenStreetMap'), findsWidgets);
      expect(find.textContaining('مش من بيانات المواصلات'), findsOneWidget);
    });

    testWidgets('a point with no name still works, on its coordinates', (
      tester,
    ) async {
      phone(tester);
      TripEndpoint? picked;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await Navigator.of(context).push<TripEndpoint>(
                  MaterialPageRoute(
                    builder: (_) => page(
                      planner0: FakeRepository(),
                      places0: FakePlacesRepository(
                        reverseResponse: PlacesResponse.fromJson(
                          placesReverseEmpty,
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('مافيش اسم للمكان ده على الخريطة'), findsOneWidget);
      // Western digits, whatever the locale.
      expect(find.text('30.0312, 31.4601'), findsOneWidget);
      expect(find.textContaining('مافيش محطة في حدود 1 كم'), findsOneWidget);

      await tester.tap(find.text('أكّد المكان ده'));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
      expect(picked!.point, pin);
      expect(picked!.label, 'نقطة على الخريطة (30.0312, 31.4601)');
    });

    testWidgets('confirming returns the pin and the OSM name as its label', (
      tester,
    ) async {
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
      await tester.tap(find.text('أكّد المكان ده'));
      await tester.pumpAndSettle();

      expect(picked!.point, pin);
      expect(picked!.label, 'شارع التسعين الجنوبي');
      expect(picked!.kind, EndpointKind.point);
    });

    testWidgets('cannot confirm while still looking', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        host(page(places0: FakePlacesRepository()..error = null)),
      );
      // One frame: the lookups have been started and not yet resolved.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      await tester.pumpAndSettle();
    });

    testWidgets('"search by name instead" goes back with nothing', (
      tester,
    ) async {
      phone(tester);
      Object? result = 'untouched';
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(
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
      await tester.scrollUntilVisible(
        find.text('أدوّر بالاسم بدل كده'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('أدوّر بالاسم بدل كده'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('a failed lookup says it is unavailable and offers the point', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          page(
            places0: FakePlacesRepository(
              error: const ApiFailure(FailureKind.serverDown, status: 503),
            ),
            planner0: FakeRepository(
              nearbyError: const ApiFailure(
                FailureKind.badRequest,
                status: 404,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('مش قادرين نجيب اسم المكان دلوقتي'), findsOneWidget);
      expect(find.text('مش قادرين نحسب أقرب محطة دلوقتي'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('lays out in English in ${brightness.name}', (tester) async {
        phone(tester);
        await tester.pumpWidget(
          host(
            MapPickPage(
              planner: planner(),
              places: FakePlacesRepository(
                reverseResponse: PlacesResponse.fromJson(placesReverse),
              ),
              initialCenter: pin,
              surfaceBuilder: (_, _) => const SizedBox.expand(),
            ),
            locale: const Locale('en'),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Move the map to the place'), findsOneWidget);
        expect(find.text('Nearest stop'), findsOneWidget);
        expect(find.textContaining('239 m'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
