import 'package:equatable/equatable.dart';

/// A point on the ground, in the app's own type.
///
/// Not `maplibre_gl`'s `LatLng`, on purpose: view models and the style
/// builder are pure Dart and tested without a platform view, and importing the
/// renderer's types there would tie every test to a plugin that cannot load on
/// the VM. The widget that talks to MapLibre is the only place that converts.
class GeoPoint extends Equatable {
  const GeoPoint(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  List<Object?> get props => [lat, lon];

  @override
  String toString() => 'GeoPoint($lat, $lon)';
}

/// A south-west / north-east box.
class GeoBounds extends Equatable {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  /// Null for an empty list — there is no honest box around nothing.
  static GeoBounds? around(Iterable<GeoPoint> points) {
    double? s, w, n, e;
    for (final p in points) {
      s = s == null || p.lat < s ? p.lat : s;
      n = n == null || p.lat > n ? p.lat : n;
      w = w == null || p.lon < w ? p.lon : w;
      e = e == null || p.lon > e ? p.lon : e;
    }
    if (s == null) return null;
    return GeoBounds(south: s, west: w!, north: n!, east: e!);
  }

  @override
  List<Object?> get props => [south, west, north, east];
}

/// Decodes a Google encoded polyline at precision 5, the format OTP's
/// `legGeometry.points` uses and the API passes through untouched.
///
/// Written out rather than taken from a package: it is twenty lines, and a
/// dependency would be a new thing in the release build for no gain.
///
/// **The format is latitude first.** GeoJSON, which is what MapLibre reads, is
/// longitude first. Swapping them puts Cairo in the Indian Ocean and fails
/// silently — the layer simply draws nowhere — so this returns [GeoPoint],
/// which names its fields, and only the style builder flips the order.
///
/// Malformed input (a truncated string, a character outside the alphabet)
/// returns what decoded cleanly before the fault rather than throwing: a
/// corrupt path on one leg must not take the whole itinerary screen down.
List<GeoPoint> decodePolyline(String encoded) {
  final points = <GeoPoint>[];
  var index = 0;
  var lat = 0;
  var lon = 0;

  // Returns null when the string ends or goes out of alphabet mid-value.
  int? nextValue() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (index >= encoded.length) return null;
      final b = encoded.codeUnitAt(index++) - 63;
      if (b < 0 || b > 63) return null;
      result |= (b & 0x1f) << shift;
      shift += 5;
      if (b < 0x20) break;
      if (shift > 35) return null;
    }
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < encoded.length) {
    final dLat = nextValue();
    if (dLat == null) break;
    final dLon = nextValue();
    if (dLon == null) break;
    lat += dLat;
    lon += dLon;
    points.add(GeoPoint(lat / 1e5, lon / 1e5));
  }
  return points;
}
