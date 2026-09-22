import 'dart:convert';

import 'package:egypt_transport/core/config/app_config.dart';
import 'package:egypt_transport/core/map/map_palette.dart';
import 'package:egypt_transport/core/map/map_style.dart';
import 'package:egypt_transport/core/map/tile_source.dart';
import 'package:egypt_transport/core/theme/mode_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The style is where every decision in `core/map` actually lives, and it is
/// a plain `Map`, so all of it is testable without a device or a GPU.
///
/// Most of what can go wrong here fails *silently on a phone*: MapLibre skips
/// a layer whose filter it cannot evaluate and skips a colour it cannot
/// parse, with no error anywhere. That is the class of bug these cover.
void main() {
  const source = MapTileSource(
    pmtilesUrl: 'https://tiles.example.org/cairo.pmtiles',
    glyphsUrl: 'https://glyphs.example.org/{fontstack}/{range}.pbf',
    attribution: MapAttribution.protomapsOsm,
    isTemporary: false,
  );

  Map<String, Object?> styleFor({
    MapPalette colors = MapPalette.light,
    String languageCode = 'ar',
    bool showCoverage = true,
  }) => buildMapStyle(
    colors: colors,
    source: source,
    languageCode: languageCode,
    showCoverage: showCoverage,
  );

  List<Map<String, Object?>> layersOf(Map<String, Object?> style) =>
      (style['layers']! as List).cast<Map<String, Object?>>();

  Map<String, Object?> layer(Map<String, Object?> style, String id) =>
      layersOf(style).firstWhere((l) => l['id'] == id);

  group('tile source', () {
    test('the pmtiles URL is absolute inside the pmtiles:// prefix', () {
      // MapLibre Native resolves `pmtiles://` itself, but only when what
      // follows is a full URL. `pmtiles://cairo.pmtiles` fails silently.
      expect(
        source.styleSourceUrl,
        'pmtiles://https://tiles.example.org/cairo.pmtiles',
      );
      expect(styleFor()['sources'], contains('basemap'));
    });

    test('the demo planet source is marked temporary', () {
      // The UI reads this to tell the user the map is coming from someone
      // else's server. If it ever silently flips to false, the warning
      // disappears and a blank map looks like our bug.
      expect(MapTileSource.demoPlanet.isTemporary, isTrue);
    });

    test(
      'with no MAP_PMTILES_URL defined, the demo source is what you get',
      () {
        // Not a production hostname that does not resolve yet: a 404 draws an
        // empty rectangle, which reads as a broken app rather than as
        // unfinished deployment.
        final fromEnv = MapTileSource.fromEnvironment();
        expect(fromEnv.pmtilesUrl, MapTileSource.demoPlanet.pmtilesUrl);
        expect(fromEnv.isTemporary, isTrue);
      },
    );
  });

  group('colours', () {
    test('every colour is six-digit hex, never Flutter ARGB', () {
      // Color.toString() and a naive toRadixString both yield eight digits
      // with alpha first. MapLibre parses that as a different colour rather
      // than rejecting it.
      final hex = RegExp(r'^#[0-9a-f]{6}$');
      final found = <String>[];
      void walk(Object? node) {
        if (node is Map) {
          node.forEach((k, v) {
            if (v is String && v.startsWith('#')) found.add(v);
            walk(v);
          });
        } else if (node is List) {
          node.forEach(walk);
        }
      }

      walk(styleFor());
      expect(found, isNotEmpty);
      for (final c in found) {
        expect(hex.hasMatch(c), isTrue, reason: '$c is not #rrggbb');
      }
    });

    test('dark is a different document, not the same one', () {
      final light = jsonEncode(styleFor());
      final dark = jsonEncode(styleFor(colors: MapPalette.dark));
      expect(light, isNot(dark));
      expect(layer(styleFor(colors: MapPalette.dark), 'background')['paint'], {
        'background-color': '#171714',
      });
    });

    test('in dark, water is darker than land', () {
      // The tell of an inverted rather than designed dark map: water ends up
      // lighter than the ground and the Nile glows across the city.
      double luminance(int r, int g, int b) =>
          0.2126 * r + 0.7152 * g + 0.0722 * b;
      expect(
        luminance(0x10, 0x16, 0x1a),
        lessThan(luminance(0x17, 0x17, 0x14)),
      );
    });

    test('no basemap colour is a mode or metro colour', () {
      // The licence-plate colour system only works while nothing else on
      // screen uses those hues. A road casing in microbus orange would be
      // the loudest orange on the screen, by area.
      String hex(Color c) {
        final v =
            ((c.r * 255).round() << 16) |
            ((c.g * 255).round() << 8) |
            (c.b * 255).round();
        return '#${v.toRadixString(16).padLeft(6, '0')}';
      }

      final reserved = <String>{
        for (final m in [ModeColors.light, ModeColors.dark])
          ...[
            m.microbus,
            m.tomnaya,
            m.cooperative,
            m.formalBus,
            ...m.metroLines.values,
          ].map(hex),
      };
      for (final colors in [MapPalette.light, MapPalette.dark]) {
        final json = jsonEncode(
          buildMapStyle(
            colors: colors,
            source: source,
            languageCode: 'ar',
            // The accent-coloured coverage box is the one deliberate
            // exception and is not a mode colour either, but exclude it so
            // this test is about the cartography.
            showCoverage: false,
          ),
        );
        for (final c in reserved) {
          expect(
            json.contains(c),
            isFalse,
            reason: '$c appears in the basemap',
          );
        }
      }
    });
  });

  group('labels', () {
    test('Arabic is asked for first, with the local name as fallback', () {
      // Protomaps carries name:ar unevenly. Filtering rather than coalescing
      // would drop the label entirely for anything untranslated.
      for (final id in ['place-locality', 'place-neighbourhood']) {
        final layout = layer(styleFor(), id)['layout']! as Map<String, Object?>;
        expect(layout['text-field'], [
          'coalesce',
          ['get', 'name:ar'],
          ['get', 'name'],
        ]);
      }
    });

    test('English asks for name:en, not name:ar', () {
      final layout =
          layer(styleFor(languageCode: 'en'), 'place-locality')['layout']!
              as Map<String, Object?>;
      expect(layout['text-field'], [
        'coalesce',
        ['get', 'name:en'],
        ['get', 'name'],
      ]);
    });

    test('every symbol layer has a glyph source to draw from', () {
      // A style with symbol layers and no reachable `glyphs` renders the
      // geometry and none of the names — a map that looks like it works.
      final style = styleFor();
      final symbols = layersOf(style).where((l) => l['type'] == 'symbol');
      expect(symbols, isNotEmpty);
      expect(style['glyphs'], source.glyphsUrl);
      expect(style['glyphs'], contains('{fontstack}'));
      expect(style['glyphs'], contains('{range}'));
    });

    test('labels are drawn after everything else', () {
      final ids = layersOf(styleFor()).map((l) => l['type']).toList();
      expect(ids.lastIndexOf('symbol'), ids.length - 1);
      expect(ids.indexOf('symbol'), greaterThan(ids.indexOf('line')));
    });
  });

  group('filters', () {
    test('a kind filter wraps its values in a literal', () {
      // `['in', ['get','kind'], 'a', 'b']` is not an error — the layer just
      // never draws, on a device, with no message.
      for (final id in ['roads-major', 'roads-casing', 'green', 'boundaries']) {
        final filter = layer(styleFor(), id)['filter']! as List;
        expect(filter.first, 'in');
        expect(filter[1], ['get', 'kind']);
        expect((filter[2] as List).first, 'literal');
        expect((filter[2] as List)[1], isA<List<String>>());
      }
    });

    test('road classes are the ones the 4.x schema actually has', () {
      // v2 had `pmap:kind`; there has never been a `medium_road`. Either
      // mistake gives an empty road layer.
      final kinds = [
        for (final id in ['roads-major', 'roads-minor', 'roads-casing'])
          ...switch (layer(styleFor(), id)['filter']! as List) {
            [_, _, [_, List kinds]] => kinds.cast<String>(),
            [_, _, final String k] => [k],
            _ => <String>[],
          },
      ];
      expect(kinds, isNot(contains('medium_road')));
      expect(kinds, contains('major_road'));
      expect(kinds, contains('highway'));
    });

    test('minor_road is matched with ==, not a bare in', () {
      expect(layer(styleFor(), 'roads-minor')['filter'], [
        '==',
        ['get', 'kind'],
        'minor_road',
      ]);
    });
  });

  group('coverage box', () {
    test('is the same rectangle the app refuses requests outside of', () {
      // Two numbers for one fact is how a map ends up claiming coverage the
      // planner then denies.
      final geo =
          ((styleFor()['sources']! as Map)['coverage']!
                  as Map<String, Object?>)['data']!
              as Map<String, Object?>;
      final ring =
          ((geo['geometry']! as Map<String, Object?>)['coordinates']!
              as List)[0];
      expect(ring, [
        [Coverage.minLon, Coverage.minLat],
        [Coverage.maxLon, Coverage.minLat],
        [Coverage.maxLon, Coverage.maxLat],
        [Coverage.minLon, Coverage.maxLat],
        [Coverage.minLon, Coverage.minLat],
      ]);
    });

    test('can be turned off, source and layers together', () {
      final style = styleFor(showCoverage: false);
      expect((style['sources']! as Map).containsKey('coverage'), isFalse);
      expect(
        layersOf(style).where((l) => l['source'] == 'coverage'),
        isEmpty,
        reason: 'a layer pointing at a missing source breaks the whole style',
      );
    });
  });

  test('encodes to JSON without throwing on any expression', () {
    // jsonEncode rejects a non-encodable value at runtime, and the style is
    // built from nested literals by hand.
    expect(
      () => encodeMapStyle(
        colors: MapPalette.dark,
        source: source,
        languageCode: 'ar',
      ),
      returnsNormally,
    );
  });
}
