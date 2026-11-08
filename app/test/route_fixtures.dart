import 'dart:convert';

import 'package:egypt_transport/core/map/geo.dart';

/// Synthetic leg geometry for the captured fixtures.
///
/// The fixtures in `test/fixtures/` predate the API sending `geometry`, so
/// these helpers add it: a three-point path per leg, built from that leg's own
/// real endpoints plus a midpoint nudged off the straight line. Anything
/// asserting on *shape* needs a recapture from a live API instead; what this
/// is for is testing which legs get drawn, in what colour, and what is
/// admitted when one is missing.

/// The inverse of `decodePolyline`, for building fixtures. Test-only: the
/// app never encodes.
String encodePolyline(List<GeoPoint> points) {
  final out = StringBuffer();
  var pLat = 0;
  var pLon = 0;
  void put(int v) {
    var n = v < 0 ? ~(v << 1) : (v << 1);
    while (n >= 0x20) {
      out.writeCharCode((0x20 | (n & 0x1f)) + 63);
      n >>= 5;
    }
    out.writeCharCode(n + 63);
  }

  for (final p in points) {
    final lat = (p.lat * 1e5).round();
    final lon = (p.lon * 1e5).round();
    put(lat - pLat);
    put(lon - pLon);
    pLat = lat;
    pLon = lon;
  }
  return out.toString();
}

/// A copy of [plan] whose legs carry `geometry`.
///
/// [skip] are leg indexes left without one; [approximate] are indexes the
/// server flags `geometry_approximate`.
Map<String, dynamic> withGeometry(
  Map<String, dynamic> plan, {
  Set<int> skip = const {},
  Set<int> approximate = const {},
}) {
  final copy = jsonDecode(jsonEncode(plan)) as Map<String, dynamic>;
  final legs = (copy['itineraries'] as List).first['legs'] as List;
  for (var i = 0; i < legs.length; i++) {
    final leg = legs[i] as Map<String, dynamic>;
    if (skip.contains(i)) continue;
    final from = leg['from'] as Map<String, dynamic>;
    final to = leg['to'] as Map<String, dynamic>;
    final a = GeoPoint(
      (from['lat'] as num).toDouble(),
      (from['lon'] as num).toDouble(),
    );
    final b = GeoPoint(
      (to['lat'] as num).toDouble(),
      (to['lon'] as num).toDouble(),
    );
    final mid = GeoPoint(
      (a.lat + b.lat) / 2 + 0.002,
      (a.lon + b.lon) / 2 - 0.002,
    );
    leg['geometry'] = encodePolyline([a, mid, b]);
    leg['geometry_approximate'] = approximate.contains(i);
  }
  return copy;
}
