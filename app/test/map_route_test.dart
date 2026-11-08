import 'dart:convert';

import 'package:egypt_transport/core/config/app_config.dart';
import 'package:egypt_transport/core/map/geo.dart';
import 'package:egypt_transport/core/map/map_palette.dart';
import 'package:egypt_transport/core/map/map_style.dart';
import 'package:egypt_transport/core/map/route_overlay.dart';
import 'package:egypt_transport/core/map/tile_source.dart';
import 'package:egypt_transport/core/presentation/trip_presenter.dart';
import 'package:egypt_transport/core/presentation/view_models.dart';
import 'package:egypt_transport/core/theme/app_theme.dart';
import 'package:egypt_transport/core/theme/mode_theme.dart';
import 'package:egypt_transport/core/widgets/mode_badge.dart';
import 'package:egypt_transport/data/models/models.dart';
import 'package:egypt_transport/features/itinerary/view/itinerary_page.dart';
import 'package:egypt_transport/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'route_fixtures.dart';

/// The itinerary map (#20), without a map.
///
/// **The geometry in these tests is synthetic.** The captured fixtures predate
/// the API sending `geometry`, so `withGeometry` (`route_fixtures.dart`) adds a three-point path to
/// each leg, built from that leg's own real endpoints plus a midpoint nudged
/// off the straight line. What is under test is the derivation — which legs
/// are drawn, in which colour, dashed or not, what is admitted when something
/// is missing — not the shape of any real route. Recapture the fixtures from a
/// live API to test that.
void main() {
  const presenter = TripPresenter(languageCode: 'ar');

  const tiles = MapTileSource(
    pmtilesUrl: 'https://tiles.example.org/cairo.pmtiles',
    glyphsUrl: 'https://glyphs.example.org/{fontstack}/{range}.pbf',
    attribution: MapAttribution.protomapsOsm,
    isTemporary: false,
  );

  // ---------------------------------------------------------------- helpers

  ItineraryVm itineraryOf(Map<String, dynamic> json) =>
      presenter.plan(PlanResponse.fromJson(json)).itineraries.first;

  Map<String, Object?> styleWith(
    ItineraryVm it, {
    MapPalette palette = MapPalette.light,
    ModeColors modes = ModeColors.light,
  }) {
    final overlay = MapRouteOverlay.from(
      it.routeMap,
      modes: modes,
      base: palette,
    )!;
    return buildMapStyle(
      colors: palette,
      source: tiles,
      languageCode: 'ar',
      showCoverage: false,
      route: overlay,
    );
  }

  List<Map<String, Object?>> layersOf(Map<String, Object?> style) =>
      (style['layers']! as List).cast<Map<String, Object?>>();

  // ---------------------------------------------------------------- decoder

  group('decodePolyline', () {
    test('decodes the reference string from the format documentation', () {
      final pts = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(pts, const [
        GeoPoint(38.5, -120.2),
        GeoPoint(40.7, -120.95),
        GeoPoint(43.252, -126.453),
      ]);
    });

    test('is latitude first — a Cairo point does not decode to the ocean', () {
      final pts = decodePolyline(
        encodePolyline(const [GeoPoint(30.0444, 31.2357)]),
      );
      expect(pts.single.lat, closeTo(30.0444, 1e-5));
      expect(pts.single.lon, closeTo(31.2357, 1e-5));
    });

    test('empty and malformed input never throws', () {
      expect(decodePolyline(''), isEmpty);
      // A truncated final value: what decoded cleanly survives.
      final good = encodePolyline(const [GeoPoint(30.0, 31.0)]);
      expect(decodePolyline('$good~'), hasLength(1));
      // Outside the alphabet.
      expect(decodePolyline('   '), isEmpty);
    });
  });

  // ------------------------------------------------------------- presenter

  group('TripPresenter.routeMap', () {
    test('a plan with no geometry has no map, and says nothing is drawn', () {
      // This is every plan cached before the API sent geometry, and the live
      // fixtures as captured. There must be no map and above all no straight
      // line from boarding stop to alighting stop.
      final it = itineraryOf(planMicrobus);
      expect(it.routeMap.hasRoute, isFalse);
      expect(it.routeMap.segments, isEmpty);
      expect(it.routeMap.stops, isEmpty);
      expect(it.routeMap.undrawnLegs, it.legs.length);
      expect(it.legs.every((l) => l.path.isEmpty), isTrue);
    });

    test('every leg with geometry becomes a segment, in order', () {
      final it = itineraryOf(withGeometry(planMicrobus));
      expect(it.routeMap.segments, hasLength(it.legs.length));
      expect(it.routeMap.undrawnLegs, 0);
      for (var i = 0; i < it.legs.length; i++) {
        expect(it.routeMap.segments[i].badge, it.legs[i].badge);
        expect(it.routeMap.segments[i].isWalk, it.legs[i].isWalk);
        expect(it.routeMap.segments[i].points, it.legs[i].path);
      }
    });

    test('walking legs are the dashed ones, transit legs are not', () {
      final it = itineraryOf(withGeometry(planMicrobus));
      for (final s in it.routeMap.segments) {
        expect(s.isWalk, s.badge.modeId == 'walk');
      }
      expect(it.routeMap.segments.where((s) => s.isWalk), isNotEmpty);
      expect(it.routeMap.segments.where((s) => !s.isWalk), isNotEmpty);
    });

    test('a leg without geometry is left out, not joined up', () {
      // Skip the middle microbus leg. The two either side must still draw,
      // and the gap must be counted rather than papered over.
      final json = withGeometry(planMicrobus, skip: {2});
      final it = itineraryOf(json);
      expect(it.routeMap.segments, hasLength(it.legs.length - 1));
      expect(it.routeMap.undrawnLegs, 1);

      final skipped = it.legs[2];
      expect(skipped.path, isEmpty);
      // Nothing on the map is a two-point line between the skipped leg's
      // endpoints.
      for (final s in it.routeMap.segments) {
        expect(s.points.length, greaterThan(2));
      }
      // And there is no marker for a stop on the skipped leg.
      final boards = it.routeMap.stops.where(
        (s) => s.role == RouteStopRole.board,
      );
      expect(boards.map((s) => s.point), isNot(contains(skipped.fromPoint)));
    });

    test('a one-point path is not a path', () {
      final json = withGeometry(planMicrobus);
      final leg =
          ((json['itineraries'] as List).first['legs'] as List).first
              as Map<String, dynamic>;
      leg['geometry'] = encodePolyline(const [GeoPoint(30.0, 31.2)]);
      final it = itineraryOf(json);
      expect(it.legs.first.path, isEmpty);
      expect(it.routeMap.undrawnLegs, 1);
    });

    test('approximate comes from the server flag, never from the feed', () {
      // A microbus flagged approximate is approximate; a metro leg that the
      // server did not flag is not. The client has no list of "our" feeds.
      final json = withGeometry(planMetro, approximate: {3});
      final it = itineraryOf(json);
      expect(it.routeMap.hasApproximate, isTrue);
      expect(it.legs[3].pathApproximate, isTrue);
      expect(it.legs[1].pathApproximate, isFalse);

      final none = itineraryOf(withGeometry(planMetro));
      expect(none.routeMap.hasApproximate, isFalse);
    });

    test('stops: origin first, destination last, a disc for a metro board', () {
      final it = itineraryOf(withGeometry(planMetro));
      final stops = it.routeMap.stops;
      expect(stops.first.role, RouteStopRole.origin);
      expect(stops.last.role, RouteStopRole.destination);

      final boards = stops.where((s) => s.role == RouteStopRole.board);
      expect(boards, hasLength(2));
      for (final b in boards) {
        expect(b.badge!.shape, ModeBadgeShape.metroCircle);
        expect(b.badge!.metroLine, anyOf('M1', 'M2'));
      }
    });

    test('the map model has no place for a vehicle', () {
      // Not a behavioural test so much as a tripwire: if a field that could
      // hold a live position is added to the map's view models, this is the
      // line a reviewer sees.
      const segment = RouteSegmentVm(
        badge: ModeBadgeVm(
          modeId: 'microbus',
          label: 'x',
          shape: ModeBadgeShape.pill,
        ),
        isWalk: false,
        points: [],
        approximate: false,
      );
      expect(segment.props, hasLength(4));
      expect(RouteStopRole.values.map((r) => r.name), [
        'origin',
        'destination',
        'board',
        'alight',
      ]);
    });
  });

  // ---------------------------------------------------------------- colours

  group('colours', () {
    test('forBadge is the one resolver: circle -> line, pill -> plate', () {
      const m = ModeColors.light;
      const metro = ModeBadgeVm(
        modeId: 'metro',
        label: 'مترو',
        shape: ModeBadgeShape.metroCircle,
        metroLine: 'M3',
      );
      const bus = ModeBadgeVm(
        modeId: 'microbus',
        label: 'ميكروباص',
        shape: ModeBadgeShape.pill,
      );
      expect(m.forBadge(metro), m.metroLines['M3']);
      expect(m.forBadge(bus), m.microbus);
    });

    test('each overlay line takes the colour of its leg badge', () {
      for (final modes in [ModeColors.light, ModeColors.dark]) {
        final it = itineraryOf(withGeometry(planMetro));
        final overlay = MapRouteOverlay.from(
          it.routeMap,
          modes: modes,
          base: MapPalette.light,
        )!;
        expect(overlay.lines, hasLength(it.routeMap.segments.length));
        for (var i = 0; i < overlay.lines.length; i++) {
          expect(
            overlay.lines[i].color,
            modes.forBadge(it.routeMap.segments[i].badge),
          );
          expect(overlay.lines[i].dashed, it.routeMap.segments[i].isWalk);
        }
      }
    });

    test('M1 and M2 are their own line colours, not a plate colour', () {
      final it = itineraryOf(withGeometry(planMetro));
      final overlay = MapRouteOverlay.from(
        it.routeMap,
        modes: ModeColors.light,
        base: MapPalette.light,
      )!;
      final transit = overlay.lines.where((l) => !l.dashed).toList();
      expect(transit.first.color, ModeColors.light.metroLines['M1']);
      expect(transit.last.color, ModeColors.light.metroLines['M2']);
    });

    test('microbus legs are plate orange', () {
      final it = itineraryOf(withGeometry(planMicrobus));
      final overlay = MapRouteOverlay.from(
        it.routeMap,
        modes: ModeColors.light,
        base: MapPalette.light,
      )!;
      final transit = overlay.lines.where((l) => !l.dashed);
      expect(transit.every((l) => l.color == ModeColors.light.microbus), true);
    });
  });

  // ------------------------------------------------------------------ style

  group('route in the style', () {
    test('without a route the style has no route source or layers', () {
      final style = buildMapStyle(
        colors: MapPalette.light,
        source: tiles,
        languageCode: 'ar',
      );
      expect((style['sources']! as Map).containsKey(routeSourceId), isFalse);
      expect(
        layersOf(style).where((l) => '${l['id']}'.startsWith(routeLayerPrefix)),
        isEmpty,
      );
    });

    test('every route layer reads the route source, and nothing else does', () {
      final style = styleWith(itineraryOf(withGeometry(planMetro)));
      expect((style['sources']! as Map).containsKey(routeSourceId), isTrue);
      for (final l in layersOf(style)) {
        final isRoute = '${l['id']}'.startsWith(routeLayerPrefix);
        expect(l['source'] == routeSourceId, isRoute, reason: '${l['id']}');
      }
    });

    test('mode colours appear only in route layers and the route source', () {
      // The basemap test keeps the licence-plate colours out of the basemap
      // and stays exactly as strict as it was; this is its counterpart. Every
      // plate and line colour in the document must sit inside the route
      // source — it is the only place they are allowed to be.
      for (final dark in [false, true]) {
        final modes = dark ? ModeColors.dark : ModeColors.light;
        final palette = dark ? MapPalette.dark : MapPalette.light;
        final style = styleWith(
          itineraryOf(withGeometry(planMetro)),
          palette: palette,
          modes: modes,
        );
        final reserved = <Color>[
          modes.microbus,
          modes.tomnaya,
          modes.cooperative,
          modes.formalBus,
          ...modes.metroLines.values,
        ];
        final hexes = reserved.map(_hex).toList();

        final sources = Map<String, Object?>.from(style['sources']! as Map)
          ..remove(routeSourceId);
        final rest = jsonEncode({
          ...style,
          'sources': sources,
          'layers': layersOf(
            style,
          ).where((l) => !'${l['id']}'.startsWith(routeLayerPrefix)).toList(),
        });
        for (final h in hexes) {
          expect(rest.contains(h), isFalse, reason: '$h outside the route');
        }
        // ...and they do appear inside it, or this proves nothing.
        final inside = jsonEncode(
          (style['sources']! as Map)[routeSourceId],
        ).toLowerCase();
        expect(
          hexes.any(inside.contains),
          isTrue,
          reason: 'no mode colour in the route source at all',
        );
      }
    });

    test('walking is its own dashed layer; vehicle legs have no dasharray', () {
      final style = styleWith(itineraryOf(withGeometry(planMicrobus)));
      final byId = {for (final l in layersOf(style)) l['id']: l};
      final walk = byId['${routeLayerPrefix}walk']!;
      final line = byId['${routeLayerPrefix}line']!;
      expect((walk['paint']! as Map).containsKey('line-dasharray'), isTrue);
      expect((line['paint']! as Map).containsKey('line-dasharray'), isFalse);
      // The filters split on the `dashed` property the overlay writes.
      expect(jsonEncode(walk['filter']), contains('dashed'));
      expect(jsonEncode(line['filter']), contains('dashed'));
    });

    test('approximate legs are drawn fainter, not dashed like a walk', () {
      final line = layersOf(
        styleWith(itineraryOf(withGeometry(planMetro, approximate: {1}))),
      ).firstWhere((l) => l['id'] == '${routeLayerPrefix}line');
      final paint = line['paint']! as Map<String, Object?>;
      expect(jsonEncode(paint['line-opacity']), contains('approx'));
      expect(paint.containsKey('line-dasharray'), isFalse);
    });

    test('the style stays valid JSON that round-trips', () {
      final style = styleWith(itineraryOf(withGeometry(planMetro)));
      expect(jsonDecode(jsonEncode(style)), isA<Map>());
    });
  });

  group('GeoJSON', () {
    test('is longitude first, and every point lands inside Cairo', () {
      // A lat/lon swap draws nothing and raises nothing — Cairo as
      // (30.0, 31.2) read the other way is a point off the coast of Somalia.
      final overlay = MapRouteOverlay.from(
        itineraryOf(withGeometry(planMetro)).routeMap,
        modes: ModeColors.light,
        base: MapPalette.light,
      )!;
      final features = overlay.toGeoJson()['features']! as List;
      expect(features, isNotEmpty);

      void check(Object coord) {
        final c = (coord as List).cast<num>();
        expect(
          Coverage.contains(c[1].toDouble(), c[0].toDouble()),
          isTrue,
          reason: '[lon, lat] = $c is outside the covered box',
        );
      }

      for (final f in features.cast<Map<String, dynamic>>()) {
        final g = f['geometry'] as Map<String, dynamic>;
        if (g['type'] == 'Point') {
          check(g['coordinates'] as Object);
        } else {
          for (final c in g['coordinates'] as List) {
            check(c as Object);
          }
        }
      }
    });

    test('contains only lines and points, none of them a vehicle', () {
      final overlay = MapRouteOverlay.from(
        itineraryOf(withGeometry(planMicrobus)).routeMap,
        modes: ModeColors.light,
        base: MapPalette.light,
      )!;
      final features = (overlay.toGeoJson()['features']! as List)
          .cast<Map<String, dynamic>>();
      for (final f in features) {
        expect((f['geometry'] as Map)['type'], anyOf('LineString', 'Point'));
      }
      // Points are stops on the route, by role — origin, destination, a
      // boarding or an alighting. There is no role a vehicle could have.
      final roles = features
          .where((f) => (f['geometry'] as Map)['type'] == 'Point')
          .map((f) => (f['properties'] as Map)['role']);
      expect(
        roles.toSet(),
        everyElement(anyOf('origin', 'destination', 'board', 'alight')),
      );
      expect(
        jsonEncode(overlay.toGeoJson()).toLowerCase(),
        isNot(anyOf(contains('vehicle'), contains('live'), contains('eta'))),
      );
    });

    test('only a metro boarding carries a label, and it is the line name', () {
      final overlay = MapRouteOverlay.from(
        itineraryOf(withGeometry(planMetro)).routeMap,
        modes: ModeColors.light,
        base: MapPalette.light,
      )!;
      final labelled = overlay.marks.where((m) => m.label != null).toList();
      expect(labelled.map((m) => m.label), ['M1', 'M2']);
      expect(labelled.every((m) => m.role == RouteStopRole.board), isTrue);
      // A disc, not a pill: the same radius on both axes by construction —
      // MapLibre's circle layer has no other shape.
      expect(labelled.every((m) => m.radius >= 10), isTrue);

      final bus = MapRouteOverlay.from(
        itineraryOf(withGeometry(planMicrobus)).routeMap,
        modes: ModeColors.light,
        base: MapPalette.light,
      )!;
      expect(bus.marks.where((m) => m.label != null), isEmpty);
    });

    test(
      'bounds are padded so a very short trip is not a zero-area camera',
      () {
        final tiny = RouteMapVm(
          segments: [
            RouteSegmentVm(
              badge: const ModeBadgeVm(
                modeId: 'walk',
                label: 'مشي',
                shape: ModeBadgeShape.pill,
              ),
              isWalk: true,
              points: const [GeoPoint(30.05, 31.23), GeoPoint(30.05, 31.23)],
              approximate: false,
            ),
          ],
        );
        final b = MapRouteOverlay.from(
          tiny,
          modes: ModeColors.light,
          base: MapPalette.light,
        )!.bounds;
        expect(b.north - b.south, greaterThanOrEqualTo(0.004 - 1e-9));
        expect(b.east - b.west, greaterThanOrEqualTo(0.004 - 1e-9));
      },
    );
  });

  // ----------------------------------------------------------------- widget

  group('ItineraryPage with a map', () {
    var pumps = 0;
    late List<String> styles;
    setUp(() => styles = []);

    Widget stub(BuildContext context, String styleJson) {
      styles.add(styleJson);
      return const SizedBox.expand();
    }

    Widget host(
      Widget child, {
      Locale locale = const Locale('ar'),
      Brightness brightness = Brightness.light,
    }) {
      return ScreenUtilInit(
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
    }

    Future<void> open(
      WidgetTester tester,
      Map<String, dynamic> json, {
      Locale locale = const Locale('ar'),
      Brightness brightness = Brightness.light,
    }) async {
      final plan = presenter.plan(PlanResponse.fromJson(json));
      await tester.pumpWidget(
        host(
          ItineraryPage(
            itinerary: plan.itineraries.first,
            attribution: plan.attribution,
            mapSource: tiles,
            mapSurfaceBuilder: stub,
          ),
          locale: locale,
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('no geometry, no map: the surface is never built', (
      tester,
    ) async {
      await open(tester, planMicrobus);
      expect(styles, isEmpty);
      expect(find.text('خريطة المشوار'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with geometry the map gets a style that carries the route', (
      tester,
    ) async {
      await open(tester, withGeometry(planMicrobus));
      expect(styles, isNotEmpty);
      final style = jsonDecode(styles.last) as Map<String, dynamic>;
      expect((style['sources'] as Map).containsKey(routeSourceId), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says the lines are the plan, not where a vehicle is', (
      tester,
    ) async {
      await open(tester, withGeometry(planMicrobus));
      expect(find.textContaining('مش مكان العربيات'), findsOneWidget);

      await open(
        tester,
        withGeometry(planMicrobus),
        locale: const Locale('en'),
      );
      expect(find.textContaining('not where any vehicle is'), findsOneWidget);
    });

    testWidgets('the metro is a circle in the legend, never a pill', (
      tester,
    ) async {
      await open(tester, withGeometry(planMetro));
      final badges = tester
          .widgetList<ModeBadge>(find.byType(ModeBadge))
          .map((w) => w.badge)
          .toList();
      final metro = badges.where((b) => b.modeId == 'metro');
      expect(metro, isNotEmpty);
      expect(
        metro.every((b) => b.shape == ModeBadgeShape.metroCircle),
        isTrue,
        reason: 'a metro badge was handed to ModeBadge as a pill',
      );
      // The legend adds its own compact circles for M1 and M2.
      expect(
        find.byWidgetPredicate((w) => w is ModeBadge && w.compact),
        findsNWidgets(2),
      );
    });

    testWidgets('a walking leg gets a dashed legend entry', (tester) async {
      await open(tester, withGeometry(planMicrobus));
      expect(find.text('مشي'), findsWidgets);
    });

    testWidgets('an approximate leg says its line is approximate', (
      tester,
    ) async {
      await open(tester, withGeometry(planMetro, approximate: {1}));
      expect(find.textContaining('الخط الباهت تقريبي'), findsOneWidget);

      await open(tester, withGeometry(planMetro));
      expect(find.textContaining('الخط الباهت تقريبي'), findsNothing);
    });

    testWidgets('legs left undrawn are admitted, not hidden', (tester) async {
      await open(tester, withGeometry(planMicrobus, skip: {2}));
      expect(find.textContaining('مش مرسومة'), findsOneWidget);

      await open(tester, withGeometry(planMicrobus));
      expect(find.textContaining('مش مرسومة'), findsNothing);
    });

    testWidgets('renders in both themes and both languages', (tester) async {
      for (final locale in [const Locale('ar'), const Locale('en')]) {
        for (final b in [Brightness.light, Brightness.dark]) {
          await open(
            tester,
            withGeometry(planMetro),
            locale: locale,
            brightness: b,
          );
          expect(tester.takeException(), isNull);
        }
      }
      // Light and dark must not produce the same document.
      expect(styles.toSet().length, greaterThan(1));
    });
  });
}

String _hex(Color color) {
  String h(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${h(color.r)}${h(color.g)}${h(color.b)}';
}
