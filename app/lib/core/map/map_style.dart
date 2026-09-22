/// The map's style, built here rather than vendored.
///
/// ### Why the style is a presenter and not an asset
///
/// A MapLibre style is a JSON document saying which features are drawn and in
/// what colour. Protomaps ship ready-made light and dark themes, and taking
/// one would have been quicker — but a vendored theme's colours are somebody
/// else's, and this app's colours are the product. A map in another palette
/// sitting inside these screens reads as a second application bolted on.
///
/// So the style is **built from [MapPalette] at runtime**, the same way
/// `TripPresenter` builds view models: one place decides, and the widget is
/// handed something finished. That also makes the thing testable — a style is
/// a `Map`, and `test/map_style_test.dart` asserts on it without a device, a
/// GPU or a network.
///
/// It is deliberately small: roughly a dozen layers against the Protomaps
/// basemap schema, not the ~100 a full theme carries. Cairo's value here is
/// water, the road hierarchy, the built-up area and place names. Everything
/// else is detail a passenger checking a microbus route does not read, drawn
/// at a cost paid by the cheapest phone in the fleet.
///
/// **What would change the answer:** needing the full cartography — land use
/// texture, POI icons, house numbers — for a map-first screen. If that comes,
/// vendor a Protomaps theme *and* re-colour it from [MapPalette]; do not keep
/// two palettes.
///
/// ### The schema this is written against
///
/// Protomaps basemap schema **4.x** (the planet build on 2026-09-22 was
/// 4.15.2). Layer and attribute names come from
/// <https://docs.protomaps.com/basemaps/layers>. Two that are easy to get
/// wrong from memory: the road classes are `highway` / `major_road` /
/// `minor_road` (there is no `medium_road`), and v2's `pmap:kind` prefix is
/// gone — it is plain `kind` now. A filter naming a field the tiles do not
/// have does not error; the layer just never draws.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import 'map_palette.dart';
import 'tile_source.dart';

/// The source id every layer hangs off. Only meaningful inside this file.
const _source = 'basemap';

/// Protomaps' own glyph build. `Medium` is the only other weight available
/// there, so the type hierarchy on the map is two weights, not four.
///
/// **These two stacks carry shaped Arabic, and that was checked rather than
/// assumed.** MapLibre does not draw the base Arabic codepoints: it runs the
/// bidi algorithm, substitutes each letter to its joined form in Arabic
/// Presentation Forms-B (U+FE70–FEFF), and asks the glyph server for *those*.
/// A stack with U+0600–06FF and no FE70 block renders every word as
/// disconnected isolated letters — which on a phone looks like a font quirk,
/// not a bug. Decoded from the `.pbf` on 2026-09-22: both stacks carry 254
/// drawn glyphs in 1536–1791 **and 140 in the FE70–FEFF block**, which is the
/// whole assigned set. So the tiles, the shaper and the glyphs line up; what
/// is still unverified is only MapLibre Native's shaping on a real device.
///
/// Note that Protomaps' `pgf:name:*` route — pre-positioned glyphs for
/// scripts MapLibre cannot shape — does **not** cover Arabic. The only pgf
/// stack they publish is `Noto Sans Devanagari Regular v1`. Arabic goes
/// through the renderer's own shaper; there is no `pgf:name:ar` to fall back
/// on.
const _regular = ['Noto Sans Regular'];
const _medium = ['Noto Sans Medium'];

/// Builds the whole style document.
///
/// [languageCode] picks the label language, and is the app's locale rather
/// than the phone's: someone who has set the app to Arabic wants Arabic
/// labels on a phone in English. Tiles carry `name:ar` for many but not all
/// features, so every label coalesces down to the local `name` — which in
/// Egypt is usually Arabic anyway. There is no transliteration step, for the
/// same reason there is none for stop names: a wrong Arabic name is worse
/// than an honest foreign one.
Map<String, Object?> buildMapStyle({
  required MapPalette colors,
  required MapTileSource source,
  required String languageCode,
  bool showCoverage = true,
}) {
  final label = _localisedName(languageCode);

  return <String, Object?>{
    'version': 8,
    'name': 'Masar $languageCode',
    'glyphs': source.glyphsUrl,
    // No sprite. Nothing in this style uses an icon, and a sprite is two more
    // files to host for no drawn pixel.
    'sources': <String, Object?>{
      _source: <String, Object?>{
        'type': 'vector',
        'url': source.styleSourceUrl,
        'attribution': source.attribution.text,
      },
      if (showCoverage) 'coverage': _coverageSource(),
    },
    'layers': <Map<String, Object?>>[
      // Painted before any tile arrives, so a slow connection shows the map's
      // own ground rather than a white or black rectangle that looks broken.
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': _hex(colors.earth)},
      },
      {
        'id': 'earth',
        'type': 'fill',
        'source': _source,
        'source-layer': 'earth',
        'paint': {'fill-color': _hex(colors.earth)},
      },
      // Far out, this is the only thing that says where Cairo is. Faded off
      // once real streets arrive, or it tints the whole city.
      {
        'id': 'built-up',
        'type': 'fill',
        'source': _source,
        'source-layer': 'landcover',
        'filter': [
          '==',
          ['get', 'kind'],
          'urban_area',
        ],
        'maxzoom': 12,
        'paint': {
          'fill-color': _hex(colors.builtUp),
          'fill-opacity': [
            'interpolate',
            ['linear'],
            ['zoom'],
            8,
            1.0,
            12,
            0.0,
          ],
        },
      },
      {
        'id': 'green',
        'type': 'fill',
        'source': _source,
        'source-layer': 'landuse',
        // Kept to the kinds Cairo actually has at a size worth drawing.
        'filter': _kindIn(const [
          'park',
          'garden',
          'cemetery',
          'golf_course',
          'zoo',
        ]),
        'minzoom': 10,
        'paint': {'fill-color': _hex(colors.green)},
      },
      {
        'id': 'water',
        'type': 'fill',
        'source': _source,
        'source-layer': 'water',
        'paint': {'fill-color': _hex(colors.water)},
      },
      {
        'id': 'buildings',
        'type': 'fill',
        'source': _source,
        'source-layer': 'buildings',
        'minzoom': 14,
        'paint': {
          'fill-color': _hex(colors.building),
          // Faded in, because buildings appearing all at once at z14 reads as
          // the map redrawing itself.
          'fill-opacity': [
            'interpolate',
            ['linear'],
            ['zoom'],
            14,
            0.0,
            15.5,
            1.0,
          ],
        },
      },
      // Casing under every road, so two roads crossing read as two roads and
      // not as a single blob. Drawn as one wider line beneath the fill.
      {
        'id': 'roads-casing',
        'type': 'line',
        'source': _source,
        'source-layer': 'roads',
        'filter': _kindIn(const ['highway', 'major_road', 'minor_road']),
        'minzoom': 11,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': _hex(colors.roadCasing),
          'line-width': _roadWidth(casing: true),
        },
      },
      {
        'id': 'roads-minor',
        'type': 'line',
        'source': _source,
        'source-layer': 'roads',
        'filter': [
          '==',
          ['get', 'kind'],
          'minor_road',
        ],
        'minzoom': 12,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': _hex(colors.roadMinor),
          'line-width': _roadWidth(casing: false),
        },
      },
      {
        'id': 'roads-major',
        'type': 'line',
        'source': _source,
        'source-layer': 'roads',
        'filter': _kindIn(const ['highway', 'major_road']),
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': _hex(colors.roadMajor),
          'line-width': _roadWidth(casing: false, major: true),
        },
      },
      {
        'id': 'boundaries',
        'type': 'line',
        'source': _source,
        'source-layer': 'boundaries',
        'filter': _kindIn(const ['country', 'region']),
        'paint': {
          'line-color': _hex(colors.boundary),
          'line-width': 1.0,
          'line-dasharray': [3.0, 2.0],
        },
      },
      if (showCoverage) ..._coverageLayers(colors),
      // Labels last, so nothing is drawn over a place name.
      {
        'id': 'place-neighbourhood',
        'type': 'symbol',
        'source': _source,
        'source-layer': 'places',
        'filter': _kindIn(const ['neighbourhood', 'macrohood']),
        'minzoom': 12,
        'layout': {
          'text-field': label,
          'text-font': _regular,
          'text-size': 12.0,
          'text-max-width': 7.0,
          'text-padding': 4.0,
        },
        'paint': {
          'text-color': _hex(colors.labelMinor),
          'text-halo-color': _hex(colors.labelHalo),
          'text-halo-width': 1.2,
        },
      },
      {
        'id': 'place-locality',
        'type': 'symbol',
        'source': _source,
        'source-layer': 'places',
        'filter': [
          '==',
          ['get', 'kind'],
          'locality',
        ],
        'layout': {
          'text-field': label,
          'text-font': _medium,
          'text-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            8,
            12.0,
            13,
            16.0,
          ],
          'text-max-width': 8.0,
          'text-padding': 6.0,
        },
        'paint': {
          'text-color': _hex(colors.label),
          'text-halo-color': _hex(colors.labelHalo),
          'text-halo-width': 1.4,
        },
      },
    ],
  };
}

/// The same document, as the string MapLibre's `styleString` wants.
String encodeMapStyle({
  required MapPalette colors,
  required MapTileSource source,
  required String languageCode,
  bool showCoverage = true,
}) => jsonEncode(
  buildMapStyle(
    colors: colors,
    source: source,
    languageCode: languageCode,
    showCoverage: showCoverage,
  ),
);

/// `["in", ["get", "kind"], ["literal", [...]]]`.
///
/// Written once because the `literal` wrapper is the easy thing to forget,
/// and a malformed filter does not throw — the layer simply never draws, on a
/// device, silently.
List<Object> _kindIn(List<String> kinds) => [
  'in',
  ['get', 'kind'],
  [
    'literal',
    [...kinds],
  ],
];

/// `name:ar` where the tiles have it, the local `name` where they do not.
///
/// Protomaps carries `name:ar` for 41 translated languages on labelled
/// features, but coverage is uneven — a Cairo neighbourhood may have only the
/// OSM `name`. Coalescing rather than filtering means a feature with no
/// translation still gets its name on the map instead of vanishing.
///
/// **This is the one place the Latin-fallback rule cannot be honoured as
/// written.** `docs/design-system.md` says a place with no `name:ar` renders
/// its Latin name *next to a note saying the map has no Arabic name for it*.
/// On a list row there is somewhere to put that note; on a map there is not —
/// a label is four words on top of a street, and a per-label caveat would be
/// unreadable at any size that fitted. The rule's intent is served one level
/// up instead: `mapNamesFromOsm` states, once, on the screen, that names come
/// from OpenStreetMap and that some are English-only or missing. What is
/// *not* done, here or anywhere, is transliterating — a wrong Arabic name is
/// worse than an honest foreign one.
List<Object> _localisedName(String languageCode) => [
  'coalesce',
  ['get', 'name:$languageCode'],
  ['get', 'name'],
];

/// One expression for road width so the hierarchy cannot drift between the
/// casing and the fill — the casing is simply wider by a constant.
List<Object> _roadWidth({required bool casing, bool major = false}) {
  final base = major ? 1.6 : 0.8;
  final wide = major ? 9.0 : 4.0;
  final pad = casing ? 1.6 : 0.0;
  return [
    'interpolate',
    ['exponential', 1.4],
    ['zoom'],
    10,
    base + pad,
    16,
    wide + pad,
  ];
}

/// The coverage box, drawn from the same numbers the app refuses requests
/// with.
///
/// Stated on the map rather than only in About: outside this rectangle there
/// is no transit data at all for Egypt, and someone in Tanta should be able
/// to see that before typing a destination, not after.
Map<String, Object?> _coverageSource() {
  const west = MapCamera.westLon;
  const east = MapCamera.eastLon;
  const south = MapCamera.southLat;
  const north = MapCamera.northLat;
  return {
    'type': 'geojson',
    'data': {
      'type': 'Feature',
      'properties': <String, Object?>{},
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          [
            [west, south],
            [east, south],
            [east, north],
            [west, north],
            [west, south],
          ],
        ],
      },
    },
  };
}

List<Map<String, Object?>> _coverageLayers(MapPalette colors) => [
  {
    'id': 'coverage-fill',
    'type': 'fill',
    'source': 'coverage',
    'paint': {
      'fill-color': _hex(colors.coverage),
      // Low enough that the map underneath is still the thing you read.
      'fill-opacity': 0.06,
    },
  },
  {
    'id': 'coverage-outline',
    'type': 'line',
    'source': 'coverage',
    'paint': {
      'line-color': _hex(colors.coverage),
      'line-width': 1.5,
      'line-dasharray': [4.0, 3.0],
    },
  },
];

/// MapLibre wants `#rrggbb`. Flutter's [Color] is ARGB and its alpha would
/// come out as the first pair, which silently produces a nonsense colour
/// rather than an error.
String _hex(Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  return '#'
      '${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';
}
