/// The itinerary, as something the style can draw.
///
/// ### Where the colours get decided
///
/// A [RouteMapVm] carries badges, not colours, because a colour depends on the
/// theme. [MapRouteOverlay.from] is the one place those badges become colours,
/// and it does it through `ModeColors.forBadge` — the same function the badge
/// widget and the leg list use. The map therefore cannot disagree with the
/// card above it, and a mode is never resolved from `route_type` here or
/// anywhere (all 1,011 road routes declare `3`).
///
/// ### Why this is not part of the basemap
///
/// `map_palette.dart` keeps mode colours **out** of the basemap, so that the
/// licence-plate colours mean exactly one thing. Everything in this file is
/// drawn from a source called [routeSourceId] and every layer id starts with
/// `route-`, which is how `test/map_route_test.dart` tells the two apart
/// without loosening the basemap test.
///
/// ### What is not here
///
/// No vehicle, no moving marker, no "arriving" pulse: there is no real-time
/// feed for Cairo paratransit and none to buy. Every feature in the source is
/// a `LineString` (a leg) or a `Point` (a stop on the route), and a test holds
/// that.
library;

import 'package:flutter/material.dart';

import '../presentation/view_models.dart';
import '../theme/contrast.dart';
import '../theme/mode_theme.dart';
import '../theme/tokens.dart';
import 'geo.dart';
import 'map_color.dart';
import 'map_palette.dart';

/// The one source every route layer reads.
const routeSourceId = 'route';

/// Prefix on every layer id this file adds.
const routeLayerPrefix = 'route-';

/// One leg's line, resolved to a colour.
class RouteLine {
  const RouteLine({
    required this.color,
    required this.dashed,
    required this.approximate,
    required this.points,
  });

  final Color color;
  final bool dashed;
  final bool approximate;
  final List<GeoPoint> points;
}

/// One marked stop, resolved to colours.
class RouteMark {
  const RouteMark({
    required this.point,
    required this.role,
    required this.stroke,
    required this.fill,
    required this.radius,
    this.label,
    this.labelColor,
  });

  final GeoPoint point;
  final RouteStopRole role;
  final Color stroke;
  final Color fill;
  final double radius;

  /// `M1`, `M2`, `M3` — set only on a metro boarding, which is drawn as a
  /// disc carrying its line, the same form as the badge. A metro line must
  /// not become a pill on the one screen that is mostly shapes.
  final String? label;
  final Color? labelColor;
}

class MapRouteOverlay {
  const MapRouteOverlay({
    required this.lines,
    required this.marks,
    required this.bounds,
  });

  final List<RouteLine> lines;
  final List<RouteMark> marks;

  /// The box the camera should fit, already padded so a trip that is a single
  /// short walk does not ask MapLibre for a zero-area camera.
  final GeoBounds bounds;

  /// Null when there is nothing to draw — the caller shows no map.
  static MapRouteOverlay? from(
    RouteMapVm route, {
    required ModeColors modes,
    required MapPalette base,
  }) {
    if (!route.hasRoute) return null;
    final raw = route.bounds!;

    final lines = [
      for (final s in route.segments)
        RouteLine(
          color: modes.forBadge(s.badge),
          dashed: s.isWalk,
          approximate: s.approximate,
          points: s.points,
        ),
    ];

    final marks = <RouteMark>[
      for (final s in route.stops) _mark(s, modes, base),
    ];

    const minSpan = 0.004; // ~440 m: about the smallest honest walk.
    final latPad = raw.north - raw.south < minSpan
        ? (minSpan - (raw.north - raw.south)) / 2
        : 0.0;
    final lonPad = raw.east - raw.west < minSpan
        ? (minSpan - (raw.east - raw.west)) / 2
        : 0.0;

    return MapRouteOverlay(
      lines: lines,
      marks: marks,
      bounds: GeoBounds(
        south: raw.south - latPad,
        west: raw.west - lonPad,
        north: raw.north + latPad,
        east: raw.east + lonPad,
      ),
    );
  }

  static RouteMark _mark(RouteStopVm stop, ModeColors modes, MapPalette base) {
    final badge = stop.badge;
    final modeColor = badge == null ? base.label : modes.forBadge(badge);
    switch (stop.role) {
      case RouteStopRole.origin:
        return RouteMark(
          point: stop.point,
          role: stop.role,
          stroke: base.labelHalo,
          fill: base.coverage,
          radius: 6,
        );
      case RouteStopRole.destination:
        return RouteMark(
          point: stop.point,
          role: stop.role,
          stroke: base.labelHalo,
          fill: base.label,
          radius: 6,
        );
      case RouteStopRole.board:
        final isMetro = badge?.shape == ModeBadgeShape.metroCircle;
        if (isMetro) {
          // A disc in the line's colour with the line's name on it — the
          // metro badge, on the map.
          return RouteMark(
            point: stop.point,
            role: stop.role,
            stroke: base.labelHalo,
            fill: modeColor,
            radius: 11,
            label: badge!.metroLine,
            labelColor: legibleOn(
              modeColor,
              dark: Palette.light.ink,
              light: Palette.light.surface,
            ),
          );
        }
        return RouteMark(
          point: stop.point,
          role: stop.role,
          stroke: modeColor,
          fill: base.labelHalo,
          radius: 6,
        );
      case RouteStopRole.alight:
        return RouteMark(
          point: stop.point,
          role: stop.role,
          stroke: modeColor,
          fill: base.labelHalo,
          radius: 4,
        );
    }
  }

  /// GeoJSON, which is **longitude first**. [GeoPoint] is latitude first and
  /// named; this is the only place the order flips, and `map_route_test.dart`
  /// asserts a known point lands inside Cairo rather than the ocean.
  Map<String, Object?> toGeoJson() => {
    'type': 'FeatureCollection',
    'features': [
      for (final l in lines)
        {
          'type': 'Feature',
          'properties': {
            'color': mapHex(l.color),
            'dashed': l.dashed,
            'approx': l.approximate,
          },
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final p in l.points) [p.lon, p.lat],
            ],
          },
        },
      for (final m in marks)
        {
          'type': 'Feature',
          'properties': {
            'role': m.role.name,
            'stroke': mapHex(m.stroke),
            'fill': mapHex(m.fill),
            'radius': m.radius,
            'label': m.label ?? '',
            'labelColor': mapHex(m.labelColor ?? m.stroke),
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [m.point.lon, m.point.lat],
          },
        },
    ],
  };
}

const _isLine = [
  '==',
  ['geometry-type'],
  'LineString',
];
const _isPoint = [
  '==',
  ['geometry-type'],
  'Point',
];

const _medium = ['Noto Sans Medium'];

/// The source entry for `sources`.
Map<String, Object?> routeSource(MapRouteOverlay route) => {
  'type': 'geojson',
  'data': route.toGeoJson(),
};

/// Layers, appended after the basemap's own, so they draw over everything
/// including place names. A halo under the line keeps it readable over a road
/// of a similar colour.
List<Map<String, Object?>> routeLayers(MapPalette base) => [
  {
    'id': '${routeLayerPrefix}casing',
    'type': 'line',
    'source': routeSourceId,
    'filter': _isLine,
    'layout': {'line-cap': 'round', 'line-join': 'round'},
    'paint': {
      'line-color': mapHex(base.labelHalo),
      'line-width': [
        'interpolate',
        ['linear'],
        ['zoom'],
        10,
        5.0,
        16,
        10.0,
      ],
      'line-opacity': 0.85,
    },
  },
  {
    // Vehicle legs: solid, in the plate or line colour. Faded when the server
    // says the path is stations joined by straight lines.
    'id': '${routeLayerPrefix}line',
    'type': 'line',
    'source': routeSourceId,
    'filter': [
      'all',
      _isLine,
      [
        '!',
        ['get', 'dashed'],
      ],
    ],
    'layout': {'line-cap': 'round', 'line-join': 'round'},
    'paint': {
      'line-color': ['get', 'color'],
      'line-width': [
        'interpolate',
        ['linear'],
        ['zoom'],
        10,
        3.0,
        16,
        6.0,
      ],
      'line-opacity': [
        'case',
        ['get', 'approx'],
        0.6,
        1.0,
      ],
    },
  },
  {
    // Walking: dashed. `line-dasharray` cannot be data-driven, which is why
    // walking is its own layer rather than a property of the one above.
    'id': '${routeLayerPrefix}walk',
    'type': 'line',
    'source': routeSourceId,
    'filter': [
      'all',
      _isLine,
      ['get', 'dashed'],
    ],
    'layout': {'line-cap': 'butt', 'line-join': 'round'},
    'paint': {
      'line-color': ['get', 'color'],
      'line-width': [
        'interpolate',
        ['linear'],
        ['zoom'],
        10,
        2.5,
        16,
        4.0,
      ],
      'line-dasharray': [1.5, 1.5],
    },
  },
  {
    'id': '${routeLayerPrefix}stop',
    'type': 'circle',
    'source': routeSourceId,
    'filter': _isPoint,
    'paint': {
      'circle-radius': ['get', 'radius'],
      'circle-color': ['get', 'fill'],
      'circle-stroke-color': ['get', 'stroke'],
      'circle-stroke-width': 2.5,
      'circle-pitch-alignment': 'map',
    },
  },
  {
    // Only the metro boarding disc has a label, and it is text on a circle,
    // not a pill: the symbol layer has no background shape to draw one with.
    'id': '${routeLayerPrefix}stop-label',
    'type': 'symbol',
    'source': routeSourceId,
    'filter': [
      'all',
      _isPoint,
      [
        '!=',
        ['get', 'label'],
        '',
      ],
    ],
    'layout': {
      'text-field': ['get', 'label'],
      'text-font': _medium,
      'text-size': 11.0,
      'text-allow-overlap': true,
      'text-ignore-placement': true,
    },
    'paint': {
      'text-color': ['get', 'labelColor'],
    },
  },
];
