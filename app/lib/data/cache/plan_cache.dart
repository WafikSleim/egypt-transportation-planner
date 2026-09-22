import 'dart:convert';
import 'dart:math' as math;

import '../../core/storage/key_value_store.dart';
import '../../domain/entities/trip_endpoint.dart';
import '../models/models.dart';

/// The last successful plan, kept on the phone so it can be read with no
/// connection.
///
/// ### What is stored, and why it is the raw body
///
/// The server's own JSON goes in unchanged and comes back out through
/// [PlanResponse.fromJson] — the same parser `test/fixtures/` holds honest.
/// Hand-writing a `toJson` for every model would double the wire contract and
/// give it a second place to drift, for no gain: nothing here queries the
/// plan, it is read whole and shown in order. That is also why this sits on
/// [KeyValueStore] rather than justifying a database — see the reasoning at
/// the top of `core/storage/key_value_store.dart`.
///
/// ### One entry
///
/// "The last successful plan", literally. A history of trips is a different
/// feature (saved trips, P-15) with a different promise to the user.
class PlanCache {
  PlanCache(this._store, {DateTime Function() now = DateTime.now})
    : _now = now;

  final KeyValueStore _store;
  final DateTime Function() _now;

  static const _key = 'plan_cache.last';

  /// Bumped when the stored shape changes. An entry written by another
  /// version is dropped rather than parsed — a phone that upgrades mid-week
  /// must not render a body this build no longer understands.
  static const _version = 1;

  /// How old a saved plan may be before it is not offered at all.
  ///
  /// Six hours. The argument for longer is that the *route* — which microbus,
  /// where to change — barely changes month to month. The argument against is
  /// that everything else in a saved plan is a wall-clock time, and those
  /// times stop being recognisable as "this morning" within a few hours: by
  /// the evening the app would be showing a daytime trip to someone asking a
  /// night-time question, which is the very thing the `outside_service_hours`
  /// note exists to say out loud. Service also changes shape across the day
  /// rather than across the week, so six hours is roughly "still the same
  /// part of the same day" — a cache saved in the morning rush is gone by the
  /// evening rush.
  ///
  /// It does not need to reach as far as tomorrow's commute. That is what
  /// saved trips (P-15) are for, and a saved trip is re-planned when it is
  /// opened rather than replayed.
  static const maxAge = Duration(hours: 6);

  /// How far the endpoints may have moved and still count as the same
  /// question.
  ///
  /// Not zero: the commonest offline case starts from "my location", and two
  /// fixes taken a minute apart are never the same pair of doubles. 150 m is
  /// about one Cairo block — close enough that the walk to the first stop is
  /// the same walk. The saved trip's own endpoint names are shown to the user
  /// beside the answer, so a loose match is legible rather than silent.
  static const matchRadiusM = 150.0;

  /// Bodies larger than this are not stored.
  ///
  /// `SharedPreferences` is read **synchronously before the first frame**, so
  /// anything kept here is paid for on every cold start — and cold start on a
  /// low-end phone is the thing this issue is about. A real `/plan` body
  /// measures 10–14 KB; 128 KB is far above that and still nothing next to a
  /// frame budget. A body past it means the response shape changed, and the
  /// honest answer then is no cache rather than a slower launch.
  static const maxBodyBytes = 128 * 1024;

  /// Records a plan, if it is worth recording.
  ///
  /// A plan with nothing in it is not saved. Replaying "no route between
  /// these two points" from storage adds nothing a fresh failure does not
  /// already say, and it would put the emptiest screen in the app behind a
  /// banner claiming it is a saved answer.
  Future<void> save({
    required GeoPoint from,
    required GeoPoint to,
    required String fromLabel,
    required String toLabel,
    required DateTime departAt,
    required bool arriveBy,
    required String lang,
    required PlanResponse parsed,
    required Map<String, dynamic> body,
  }) async {
    // Same rule the presenter applies: a walk-only itinerary is not a result,
    // so a plan of nothing but walks is not an answer worth keeping.
    if (!parsed.itineraries.any((i) => !i.isWalkOnly)) return;

    final entry = {
      'version': _version,
      'saved_at': _now().toIso8601String(),
      'depart_at': departAt.toIso8601String(),
      'from': [from.lat, from.lon],
      'to': [to.lat, to.lon],
      'from_label': fromLabel,
      'to_label': toLabel,
      'arrive_by': arriveBy,
      'lang': lang,
      'body': body,
    };

    // Measured as bytes, not characters: Arabic stop names are two bytes
    // each in UTF-8, so a character count would undercount the Arabic body by
    // roughly half — and the Arabic body is the one almost every phone holds.
    final encoded = jsonEncode(entry);
    if (utf8.encode(encoded).length > maxBodyBytes) return;
    await _store.write(_key, encoded);
  }

  /// The saved plan, if there is one and it answers *this* question.
  ///
  /// Returns null rather than throwing on anything unreadable. Text that is
  /// not JSON, a body from a newer server, a hand-edited file — none of those
  /// may take the screen down, and the caller already has a perfectly good
  /// thing to show instead: the failure.
  CachedPlan? read({
    required GeoPoint from,
    required GeoPoint to,
    required DateTime departAt,
    required bool arriveBy,
    required String lang,
  }) {
    final entry = _store.readJson(_key);
    if (entry == null || entry['version'] != _version) return null;

    final savedAt = _parseTime(entry['saved_at']);
    final savedDepartAt = _parseTime(entry['depart_at']);
    if (savedAt == null || savedDepartAt == null) return null;

    if (_now().difference(savedAt).abs() > maxAge) return null;

    // The departure matters as much as the age. Plan tomorrow's 08:00 trip
    // this afternoon, lose signal an hour later, and without this check the
    // app would answer "how do I get there now?" with tomorrow morning's
    // itinerary — one hour old, same endpoints, and wrong.
    if (departAt.difference(savedDepartAt).abs() > maxAge) return null;

    if (entry['arrive_by'] != arriveBy) return null;

    // Names and route labels are localised server-side, so a plan fetched in
    // Arabic is an Arabic plan. Offering it on an English screen would put
    // Arabic stop names through an English layout.
    if (entry['lang'] != lang) return null;

    final savedFrom = _parsePoint(entry['from']);
    final savedTo = _parsePoint(entry['to']);
    if (savedFrom == null || savedTo == null) return null;
    if (_metresBetween(from, savedFrom) > matchRadiusM) return null;
    if (_metresBetween(to, savedTo) > matchRadiusM) return null;

    final body = entry['body'];
    if (body is! Map<String, dynamic>) return null;

    final PlanResponse response;
    try {
      response = PlanResponse.fromJson(body);
    } catch (_) {
      return null;
    }
    if (response.itineraries.isEmpty) return null;

    return CachedPlan(
      response: response,
      savedAt: savedAt,
      departAt: savedDepartAt,
      fromLabel: entry['from_label']?.toString() ?? '',
      toLabel: entry['to_label']?.toString() ?? '',
    );
  }

  Future<void> clear() => _store.remove(_key);

  static DateTime? _parseTime(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static GeoPoint? _parsePoint(Object? value) {
    if (value is! List || value.length != 2) return null;
    final lat = value[0];
    final lon = value[1];
    if (lat is! num || lon is! num) return null;
    return GeoPoint(lat.toDouble(), lon.toDouble());
  }

  /// Flat-earth distance, which is exact enough at these scales: over 150 m
  /// inside one city the error against a great circle is centimetres.
  static double _metresBetween(GeoPoint a, GeoPoint b) {
    const metresPerDegree = 111320.0;
    final dLat = (a.lat - b.lat) * metresPerDegree;
    final dLon =
        (a.lon - b.lon) * metresPerDegree * math.cos(a.lat * math.pi / 180);
    return math.sqrt(dLat * dLat + dLon * dLon);
  }
}

/// A plan read back off the phone, with everything needed to say so.
///
/// [savedAt] and the two labels exist for one reason: the user has to be able
/// to tell at a glance that this is not a live answer, and which trip it was
/// an answer to.
class CachedPlan {
  const CachedPlan({
    required this.response,
    required this.savedAt,
    required this.departAt,
    required this.fromLabel,
    required this.toLabel,
  });

  final PlanResponse response;

  /// When the server answered — not when the trip starts.
  final DateTime savedAt;

  /// The departure this plan was computed for.
  final DateTime departAt;

  final String fromLabel;
  final String toLabel;
}
