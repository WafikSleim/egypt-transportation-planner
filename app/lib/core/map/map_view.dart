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
///
/// **An itinerary rides in the style, not on the controller.** [CityMapView]
/// takes an optional `route` (see `route_overlay.dart`) that becomes a GeoJSON
/// source and `route-*` layers inside the style document, so the same
/// stub-surface seam covers it. The only controller call is fitting the
/// camera once the style has loaded. Map picking (P-18/P-19) should extend
/// this widget the same way — an optional input folded into the style, not
/// imperative annotations — so both features share one surface.
library;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../theme/tokens.dart';
import 'map_attribution.dart';
import 'map_palette.dart';
import 'geo.dart';
import 'map_style.dart';
import 'route_overlay.dart';
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
    this.onSettled,
    this.initialCenter,
    this.initialZoom,
    this.route,
  });

  /// Called with the map's centre each time the camera comes to rest — a
  /// pan, a fling or a zoom has finished. Not called for the opening
  /// position (the caller already knows it: it chose [initialCenter]) and not
  /// called while the camera is moving: reverse geocoding every
  /// frame of a drag would be a request per frame on a phone that is already
  /// busy drawing the map.
  ///
  /// This is the whole of what map picking needs from the map. The widget
  /// stays ignorant of why: the pin is the caller's to draw, over the centre.
  /// The coverage map leaves it null and is unchanged.
  final ValueChanged<GeoPoint>? onSettled;

  /// Where the camera opens. Defaults to Tahrir at city zoom.
  final GeoPoint? initialCenter;
  final double? initialZoom;

  /// An itinerary to draw, and to fit the camera to. Null leaves the map
  /// exactly as the coverage map has it: the whole city, no overlay.
  ///
  /// It is part of the style document, not a set of controller calls, so the
  /// same seam covers it: a test reads the style [surfaceBuilder] was handed.
  final MapRouteOverlay? route;

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
      route: route,
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
            // The real map gets `onSettled` and the opening camera through
            // [_LiveMap]'s constructor rather than through
            // [MapSurfaceBuilder], so the typedef every existing test
            // implements did not have to change.
            child: surfaceBuilder != null
                ? surfaceBuilder!(context, styleJson)
                : _LiveMap(
                    styleJson: styleJson,
                    onSettled: onSettled,
                    center: initialCenter,
                    zoom: initialZoom,
                    fit: route?.bounds,
                  ),
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
}

/// The platform view, and the one place MapLibre's own types are used.
class _LiveMap extends StatefulWidget {
  const _LiveMap({
    required this.styleJson,
    this.onSettled,
    this.center,
    this.zoom,
    this.fit,
  });

  final String styleJson;
  final ValueChanged<GeoPoint>? onSettled;
  final GeoPoint? center;
  final double? zoom;

  /// The trip to fit the camera to, once the style is in. Null leaves the
  /// camera at [center] / [zoom].
  final GeoBounds? fit;

  @override
  State<_LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<_LiveMap> {
  MapLibreMapController? _controller;

  void _idle() {
    // The controller's `cameraPosition` is the last one the platform
    // reported, which is exactly the camera that just came to rest. It is
    // null unless `trackCameraPosition` is on.
    final target = _controller?.cameraPosition?.target;
    if (target == null) return;
    widget.onSettled?.call(GeoPoint(target.latitude, target.longitude));
  }

  // Fitted once the style is in, not at creation: a camera move issued
  // before the style loads can be dropped, which would leave the map on the
  // whole of Cairo with the trip somewhere in it. Unverified on hardware.
  // The camera target bounds below still clamp it to the covered box.
  void _fitToRoute() {
    final fit = widget.fit;
    if (fit == null) return;
    _controller?.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(fit.south, fit.west),
          northeast: LatLng(fit.north, fit.east),
        ),
        left: Insets.xl,
        top: Insets.xl,
        right: Insets.xl,
        bottom: Insets.xl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: widget.styleJson,
      onMapCreated: (c) => _controller = c,
      onStyleLoadedCallback: widget.fit == null ? null : _fitToRoute,
      // Only paid for when somebody is listening: tracking makes the platform
      // report every camera change across the channel.
      trackCameraPosition: widget.onSettled != null,
      onCameraIdle: widget.onSettled == null ? null : _idle,
      initialCameraPosition: CameraPosition(
        target: widget.center == null
            ? const LatLng(MapCamera.cairoLat, MapCamera.cairoLon)
            : LatLng(widget.center!.lat, widget.center!.lon),
        zoom: widget.zoom ?? MapCamera.cityZoom,
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
