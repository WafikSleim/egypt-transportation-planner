import 'dart:convert';

import 'package:egypt_transport/core/map/map_view.dart';
import 'package:egypt_transport/core/map/tile_source.dart';
import 'package:egypt_transport/core/theme/app_theme.dart';
import 'package:egypt_transport/features/map/view/coverage_map_page.dart';
import 'package:egypt_transport/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// The map screen, without a map.
///
/// `MapLibreMap` is a platform view and cannot be built on the Dart VM, so
/// `CityMapView` takes a surface builder and these tests pass a stub. What is
/// under test is everything around the renderer — the style the widget hands
/// it, the attribution it is legally obliged to draw, and the copy that says
/// what the map does not know.
void main() {
  const demo = MapTileSource(
    pmtilesUrl: 'https://tiles.example.org/cairo.pmtiles',
    glyphsUrl: 'https://glyphs.example.org/{fontstack}/{range}.pbf',
    attribution: MapAttribution.protomapsOsm,
    isTemporary: true,
  );

  const hosted = MapTileSource(
    pmtilesUrl: 'https://tiles.example.org/cairo.pmtiles',
    glyphsUrl: 'https://glyphs.example.org/{fontstack}/{range}.pbf',
    attribution: MapAttribution.protomapsOsm,
    isTemporary: false,
  );

  // Captures what the widget would have handed MapLibre.
  late List<String> styles;

  Widget stub(BuildContext context, String styleJson) {
    styles.add(styleJson);
    return const SizedBox.expand();
  }

  setUp(() => styles = []);

  // ScreenUtilInit memoises the widget its builder returns, so pumping a
  // second tree of the same shape into the same tester hands back the first
  // one — and a theme or locale change looks like it did nothing. A fresh key
  // per pump forces a new element.
  var pumps = 0;

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

  group('CityMapView', () {
    testWidgets('renders in both themes, with a different style in each', (
      tester,
    ) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          host(
            CityMapView(source: demo, surfaceBuilder: stub),
            brightness: brightness,
          ),
        );
        expect(tester.takeException(), isNull);
      }
      expect(styles, hasLength(2));
      // If these matched, MapPalette was never registered as a theme
      // extension and the dark map would be a light one.
      expect(styles.first, isNot(styles.last));
    });

    testWidgets('asks for labels in the app language, not the platform one', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          CityMapView(source: demo, surfaceBuilder: stub),
          locale: const Locale('en'),
        ),
      );
      expect(styles.single, contains('name:en'));
      expect(styles.single, isNot(contains('name:ar')));
    });

    testWidgets('credits OpenStreetMap on the map itself', (tester) async {
      // ODbL wants the credit where the map is. Losing this is a licence
      // problem, not a layout one — hence a test rather than a comment.
      await tester.pumpWidget(
        host(CityMapView(source: demo, surfaceBuilder: stub)),
      );
      expect(find.textContaining('OpenStreetMap'), findsOneWidget);
    });

    testWidgets('the style it emits is the one the builder produces', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(CityMapView(source: demo, surfaceBuilder: stub)),
      );
      final decoded = jsonDecode(styles.single) as Map<String, Object?>;
      expect(
        ((decoded['sources']! as Map)['basemap']! as Map)['url'],
        demo.styleSourceUrl,
      );
    });
  });

  group('coverage map screen', () {
    testWidgets('builds in both themes and both languages', (tester) async {
      for (final locale in [const Locale('ar'), const Locale('en')]) {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          await tester.pumpWidget(
            host(
              CoverageMapPage(source: demo, surfaceBuilder: stub),
              locale: locale,
              brightness: brightness,
            ),
          );
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('says there are no vehicles on it', (tester) async {
      // Rule 5. The one screen where a user would otherwise assume the dots
      // are missing rather than absent by design.
      await tester.pumpWidget(
        host(CoverageMapPage(source: demo, surfaceBuilder: stub)),
      );
      final l = AppLocalizations.of(
        tester.element(find.byType(CoverageMapPage)),
      );
      expect(find.text(l.mapNoVehicles), findsOneWidget);
    });

    testWidgets('warns while the tiles come from somebody else', (
      tester,
    ) async {
      // The notes are in a ListView, which never builds what is below the
      // fold, so each case has to scroll before it can claim anything.
      Future<bool> hasTemporaryWarning(MapTileSource source) async {
        await tester.pumpWidget(
          host(CoverageMapPage(source: source, surfaceBuilder: stub)),
        );
        final l = AppLocalizations.of(
          tester.element(find.byType(CoverageMapPage)),
        );
        final finder = find.text(l.mapSourceTemporary);
        for (var i = 0; i < 6 && finder.evaluate().isEmpty; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -160));
          await tester.pump();
        }
        return finder.evaluate().isNotEmpty;
      }

      expect(await hasTemporaryWarning(demo), isTrue);
      expect(await hasTemporaryWarning(hosted), isFalse);
    });
  });
}
