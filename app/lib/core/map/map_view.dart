/// The map surface.
///
/// ### Why MapLibre Native and not `flutter_map`
///
/// Settled 2026-09-22, checked against Flutter 3.44.6 / Dart 3.12.2 rather
/// than from memory.
///
/// The tiles are Protomaps `.pmtiles`, and that is not negotiable: the
/// transit data is CC BY-NC, so the app can never carry revenue, so it can
/// never pay a per-request tile bill. A `.pmtiles` archive is one static file
/// read with HTTP range requests — see `tile_source.dart`. The question is
/// only which Flutter library draws it.
///
/// **`maplibre_gl` 0.27.1** — published 12 days ago, by MapLibre's own
/// organisation, requiring Flutter 3.29+ / Dart 3.7+, wrapping MapLibre
/// Native. MapLibre Native gained `pmtiles://` in Android v11.9.0 / iOS
/// v6.14.0, so on a phone the protocol is handled *inside the renderer*: no
/// plugin, no local proxy, no Dart parsing the archive's directory. It is a
/// GPU vector renderer, which is the point — a vector tile is drawn once per
/// frame from geometry already in memory, so panning costs no network.
///
/// **`flutter_map`** is healthy and pure Dart, but it is a raster tile
/// widget. Raster means someone renders PNGs, and nobody is going to, because
/// a raster tile server is a machine with a CPU budget — exactly the
/// per-request cost the licence forbids us paying. Reaching `.pmtiles`
/// through it means `vector_map_tiles` + `vector_map_tiles_pmtiles`, and
/// those are the reason the answer is no: `vector_map_tiles` last shipped a
/// stable release two years ago against `flutter_map ^6`, the pmtiles bridge
/// 23 months ago, and `flutter_map` is on v8. That is a three-package chain,
/// two of them stale, in front of a renderer that rasterises vector tiles on
/// the CPU through Flutter's canvas — on the cheap Androids this app is for,
/// the slowest available way to do the thing.
///
/// **What would change the answer:** `maplibre_gl` going unmaintained (it is
/// a fork lineage — flutter-mapbox-gl → flutter-maplibre-gl — and has changed
/// hands before), or the `maplibre` package (josxha's FFI/JNI rewrite, 0.3.6)
/// reaching parity with PMTiles support; it is the declared successor and is
/// worth re-checking at v1. Both are MapLibre styles, so a move between them
/// changes this file and nothing in `map_style.dart`.
///
/// ### What this widget deliberately does not do
///
/// **No user-location puck.** `maplibre_gl` will happily run its own location
/// engine via `myLocationEnabled`, and turning it on would quietly change the
/// app's location posture: the README's promise is that location is read on
/// demand and never continuously, and a map that holds a fix open for as long
/// as it is on screen breaks that without anyone editing `LocationService`.
/// If the user's dot is wanted later, push it from the existing service as an
/// annotation.
///
/// **No vehicles, ever.** There is no real-time vehicle feed for Cairo
/// paratransit and none to buy. A moving dot on a map is precisely the lie
/// this product exists not to tell — rule 5 in `docs/design-system.md`.
library;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../theme/tokens.dart';
import 'map_attribution.dart';
import 'map_palette.dart';
import 'map_style.dart';
import 'tile_source.dart';

/// The seam that keeps this testable.
///
/// `MapLibreMap` is a platform view: it needs an Android or iOS host, so it
/// cannot be built in a `flutter test` running on the Dart VM. Tests pass a
/// stub here and assert on the style string the widget computed, which is
/// where every decision in this module actually lives.
typedef MapSurfaceBuilder =
    Widget Function(BuildContext context, String styleJson);

/// Greater Cairo, in the app's own palette and the app's own language.
class CityMapView extends StatelessWidget {
  const CityMapView({
    super.key,
    this.source,
    this.showCoverage = true,
    this.surfaceBuilder,
  });

  /// Defaults to [MapTileSource.fromEnvironment], which is the demo planet
  /// archive until the Cairo extract is hosted.
  final MapTileSource? source;

  /// Draw the box the transit data actually covers.
  final bool showCoverage;

  /// Overridden by tests. Production leaves this null.
  final MapSurfaceBuilder? surfaceBuilder;

  @override
  Widget build(BuildContext context) {
    final tiles = source ?? MapTileSource.fromEnvironment();

    // The palette comes from the theme, and the language from the app's
    // locale rather than the platform's — someone who set the app to Arabic
    // wants Arabic labels whatever the phone is set to.
    final styleJson = encodeMapStyle(
      colors: context.mapColors,
      source: tiles,
      languageCode: Localizations.localeOf(context).languageCode,
      showCoverage: showCoverage,
    );

    return Stack(
      children: [
        Positioned.fill(
          // Keyed on the style so a theme or language change rebuilds the
          // surface. MapLibre reloads a style wholesale; handing the same
          // widget a new string mid-life is the path that leaves half the
          // layers in the old palette. Keyed on the string and not its hash:
          // a collision would silently keep the old surface, and a session
          // only ever produces two or three distinct styles.
          child: KeyedSubtree(
            key: ValueKey(styleJson),
            child: (surfaceBuilder ?? _defaultSurface)(context, styleJson),
          ),
        ),
        // ODbL wants the credit where the map is, not two taps away on an
        // About screen.
        PositionedDirectional(
          start: Insets.sm,
          bottom: Insets.sm,
          child: MapAttributionNote(tiles.attribution),
        ),
      ],
    );
  }

  static Widget _defaultSurface(BuildContext context, String styleJson) {
    return MapLibreMap(
      styleString: styleJson,
      initialCameraPosition: const CameraPosition(
        target: LatLng(MapCamera.cairoLat, MapCamera.cairoLon),
        zoom: MapCamera.cityZoom,
      ),
      // The box the transit data covers, and therefore the box the map is
      // allowed to reach. Panning to Aswan invites a trip request there is no
      // data for.
      cameraTargetBounds: CameraTargetBounds(
        LatLngBounds(
          southwest: const LatLng(MapCamera.southLat, MapCamera.westLon),
          northeast: const LatLng(MapCamera.northLat, MapCamera.eastLon),
        ),
      ),
      minMaxZoomPreference: const MinMaxZoomPreference(
        MapCamera.minZoom,
        MapCamera.maxZoom,
      ),
      // Off on purpose — see the library comment. Not a default being
      // accepted, a decision being made.
      myLocationEnabled: false,
      // A rotated or tilted map costs GPU work every frame and buys a
      // passenger nothing; a north-up city map is also the one people can
      // match against a street sign. Both are off for the cheapest phone in
      // the fleet, which is who this app is for.
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      compassEnabled: false,
      // We draw our own credit above, in the app's type and palette.
      attributionButtonPosition: AttributionButtonPosition.bottomRight,
      // Shown while the first tiles are still in flight, so the map fades in
      // rather than flashing white — which in dark mode is the single loudest
      // thing a screen can do. Android only, per the plugin; iOS and web need
      // their own answer if this ever matters there.
      foregroundLoadColor: context.mapColors.earth,
    );
  }
}
