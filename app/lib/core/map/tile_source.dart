/// Where the basemap's bytes come from.
///
/// ### Why self-hosted Protomaps and not a maps API
///
/// Settled 2026-09-22. The transit data is CC BY-NC 4.0, so this app can
/// never carry advertising or a subscription — that is a licence condition,
/// not a preference. Every commercial tile API (Google, Mapbox, MapTiler,
/// HERE) bills per request, which means the one thing the app cannot do is
/// pay for the one thing it does most. A `.pmtiles` archive inverts that: a
/// single static file, read with HTTP range requests, served by the same
/// nginx that will sit in front of the API. Bandwidth is the only cost, and
/// Oracle's Always Free tier gives 10 TB of egress a month.
///
/// **What would change the answer:** an offer of a free, unmetered tile
/// endpoint with a licence that survives the app being free forever. Nothing
/// like that exists today. Note that switching is cheap — a style is JSON and
/// the source URL is one value; the reason to stay is cost, not lock-in.
///
/// ### Where the archive comes from
///
/// Protomaps publishes a daily planet build of the OSM basemap at
/// `https://build.protomaps.com/<YYYYMMDD>.pmtiles`. On 2026-09-22 the planet
/// measured 138 GB over z0–z15 (tileset schema 4.15.2), which is far too much
/// to host and far more than Greater Cairo needs. The archive we ship is an
/// extract of the coverage box this app already declares in
/// `core/config/app_config.dart`:
///
/// ```sh
/// pmtiles extract https://build.protomaps.com/20260922.pmtiles cairo.pmtiles \
///   --bbox=30.846,29.745,31.775,30.352 --maxzoom=14
/// ```
///
/// `pmtiles extract` reads the source over range requests, so this does not
/// download the planet. The box is 86 × 68 tiles at z15 — about 5,850 tiles,
/// plus a third again for the pyramid above it. Expect a few hundred MB at
/// z15 and roughly half that for each zoom level dropped; Protomaps' own
/// guidance is that "each additional zoom level roughly doubles the size of
/// the file". **Measure it rather than quoting this paragraph** — the number
/// has not been measured yet, only bounded.
///
/// z14 is the suggested ceiling because the app never needs individual
/// building footprints, and z15 is where Protomaps switches from merged
/// buildings to individual ones. If map-picking (P-18) later wants a closer
/// zoom, `overzoom` renders z14 tiles past their native zoom without a bigger
/// archive.
///
/// ### How it is served
///
/// As a static file. `nginx` answers range requests on static files with no
/// configuration, which is the entire server side of this. It goes on the
/// same Oracle Always Free ARM instance as OTP — the archive is inert bytes,
/// so it costs disk and egress but no RAM, and OTP's 3.4 GB heap is
/// untouched. **Unresolved:** whether the archive is rebuilt on a schedule
/// (OSM moves, and a year-old basemap shows a year-old Cairo), and whether
/// egress eventually justifies a CDN in front of it.
library;

import '../config/app_config.dart';

/// A basemap's three URLs and the attribution that rides with them.
///
/// Held as a value rather than read from constants at the point of use, so
/// that the temporary source below is one object to replace and the widget
/// never learns a URL.
class MapTileSource {
  const MapTileSource({
    required this.pmtilesUrl,
    required this.glyphsUrl,
    required this.attribution,
    required this.isTemporary,
  });

  /// The plain `https://` URL of the `.pmtiles` archive. The `pmtiles://`
  /// prefix that MapLibre wants is added by [styleSourceUrl].
  final String pmtilesUrl;

  /// `{fontstack}/{range}.pbf`. MapLibre fetches signed-distance-field
  /// glyphs separately from the tiles; a style with no reachable `glyphs`
  /// renders geometry and no labels at all.
  final String glyphsUrl;

  final MapAttribution attribution;

  /// True while the app is pointed at somebody else's server.
  ///
  /// Surfaced in the UI rather than kept as a code comment: a demo source can
  /// disappear without notice, and "the map is blank" should be traceable to
  /// this rather than looking like a bug in the app.
  final bool isTemporary;

  /// MapLibre Native reads `pmtiles://` itself on Android and iOS, with no
  /// plugin and no local proxy — but only when the URL inside it is
  /// absolute. `pmtiles://cairo.pmtiles` silently fails.
  String get styleSourceUrl => 'pmtiles://$pmtilesUrl';

  /// **Temporary.** The Protomaps daily planet build, read directly.
  ///
  /// This is here so the map renders before the Cairo extract is hosted, and
  /// it is not what ships. Three reasons:
  ///
  /// 1. Protomaps' own downloads page says the build URLs may change and
  ///    advises against linking to them directly. The date key below goes
  ///    stale the day after it is written; the archive for a given day is not
  ///    promised to stay.
  /// 2. It is 138 GB of planet read over somebody else's bandwidth to draw
  ///    one city.
  /// 3. Every pan is a round trip to a server that owes us nothing.
  ///
  /// Replace it by passing the real one at build time:
  ///
  /// ```sh
  /// flutter build apk --dart-define=MAP_PMTILES_URL=https://tiles.example.org/cairo.pmtiles
  /// ```
  static const demoPlanet = MapTileSource(
    pmtilesUrl: 'https://build.protomaps.com/20260922.pmtiles',
    glyphsUrl:
        'https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf',
    attribution: MapAttribution.protomapsOsm,
    isTemporary: true,
  );

  /// Reads `MAP_PMTILES_URL` and `MAP_GLYPHS_URL`, falling back to
  /// [demoPlanet].
  ///
  /// Deliberately not defaulted to a production hostname that does not exist
  /// yet: a URL that 404s draws an empty grey rectangle, which reads as a
  /// broken app rather than as unfinished deployment.
  factory MapTileSource.fromEnvironment() {
    const pmtiles = String.fromEnvironment('MAP_PMTILES_URL');
    const glyphs = String.fromEnvironment('MAP_GLYPHS_URL');
    if (pmtiles.isEmpty) return demoPlanet;
    return MapTileSource(
      pmtilesUrl: pmtiles,
      glyphsUrl: glyphs.isEmpty ? demoPlanet.glyphsUrl : glyphs,
      attribution: MapAttribution.protomapsOsm,
      isTemporary: false,
    );
  }
}

/// The basemap's attribution, which is **not** the transit data's.
///
/// `core/widgets/attribution_note.dart` carries the TfC line, fetched from
/// `/attribution` at runtime. This one is a property of the tile build and is
/// known before the app starts, so it is a constant here rather than another
/// request. Keeping the two apart is the same rule that keeps the `places`
/// table out of the TfC database: ODbL and CC BY-NC cannot be merged into one
/// derived work.
class MapAttribution {
  const MapAttribution({
    required this.text,
    required this.licence,
    required this.sourceUrl,
  });

  /// ODbL requires the credit; the wording below is OSM's own recommended
  /// short form, plus Protomaps, whose build of the OSM data this is.
  static const protomapsOsm = MapAttribution(
    text: '© OpenStreetMap contributors · Protomaps',
    licence: 'ODbL 1.0',
    sourceUrl: 'https://www.openstreetmap.org/copyright',
  );

  final String text;
  final String licence;
  final String sourceUrl;
}

/// Where the map opens, and how far it lets you go.
///
/// The bounds are [Coverage], not a scenic framing of Cairo. A basemap that
/// pans to Aswan invites a trip request we have no data for, and the app
/// would then have to explain itself after the fact rather than before.
class MapCamera {
  /// Roughly Tahrir. Not the centroid of the coverage box, which lands in
  /// farmland south-east of the city and opens the map on nothing.
  static const cairoLat = 30.0444;
  static const cairoLon = 31.2357;

  /// Shows Greater Cairo on a 390-wide frame without the desert either side.
  static const cityZoom = 10.5;

  /// Below this the coverage box no longer fills the frame, which makes the
  /// covered area look smaller than it is.
  static const minZoom = 8.0;

  /// The archive is built to z14 (see the library comment). Past z16 MapLibre
  /// is overzooming z14 tiles and the labels grow without new detail
  /// arriving, which reads as a broken map.
  static const maxZoom = 16.0;

  /// The pan limit, and the rectangle the map draws. Aliased from [Coverage]
  /// rather than retyped: the map must not be able to claim a different
  /// covered area from the one the app refuses requests outside of.
  static const southLat = Coverage.minLat;
  static const westLon = Coverage.minLon;
  static const northLat = Coverage.maxLat;
  static const eastLon = Coverage.maxLon;
}
