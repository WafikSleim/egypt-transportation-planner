/// The wire contract, hand-written against `api/models.py`.
///
/// Not generated from `/openapi.json`, on purpose: a generator needs the
/// server live at build time and emits a client shaped to its own
/// conventions. What keeps hand-writing safe instead is `test/fixtures/` —
/// real captured responses that the parse tests assert against, so a change
/// on the server side fails a test rather than a screen.
///
/// These are data holders only. Nothing here decides how anything is shown;
/// that is `core/presentation/trip_presenter.dart`.
library;

import 'package:equatable/equatable.dart';

T? _as<T>(Object? v) => v is T ? v : null;

int _int(Object? v) => v is num ? v.toInt() : 0;

double _double(Object? v) => v is num ? v.toDouble() : 0;

class Attribution extends Equatable {
  const Attribution({
    required this.text,
    required this.licence,
    required this.sourceUrl,
  });

  /// Required **verbatim**, in English, on any screen showing data. This is a
  /// licence condition, not a credit line we may paraphrase or shorten.
  final String text;
  final String licence;
  final String sourceUrl;

  factory Attribution.fromJson(Map<String, dynamic> json) => Attribution(
        text: _as<String>(json['text']) ?? '',
        licence: _as<String>(json['licence']) ?? '',
        sourceUrl: _as<String>(json['source_url']) ?? '',
      );

  @override
  List<Object?> get props => [text, licence, sourceUrl];
}

class Place extends Equatable {
  const Place({
    required this.name,
    required this.lat,
    required this.lon,
    this.stopId,
  });

  /// Already localised by the server. Note that the **metro feed has no
  /// `translations.txt`**, so its 108 stops come back in Latin even when the
  /// rest of the response is Arabic. Render through `bidiIsolate`.
  final String name;
  final double lat;
  final double lon;

  /// Feed-prefixed GTFS id, e.g. `2:1145`. Null for the caller's own origin
  /// or destination.
  final String? stopId;

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        name: _as<String>(json['name']) ?? '',
        lat: _double(json['lat']),
        lon: _double(json['lon']),
        stopId: _as<String>(json['stop_id']),
      );

  @override
  List<Object?> get props => [name, lat, lon, stopId];
}

class ModeInfo extends Equatable {
  const ModeInfo({
    required this.id,
    required this.labelEn,
    required this.labelAr,
    required this.otpMode,
    this.seats,
  });

  /// Stable key — `microbus`, `tomnaya`, `metro`, `walk`. **The server
  /// derived this from `agency_id`.** Never re-derive a mode from
  /// [otpMode] or from a GTFS `route_type`: the road feed types all 1,011 of
  /// its routes as `3`, microbuses included.
  final String id;
  final String labelEn;
  final String labelAr;

  /// Raw OTP mode (`BUS`, `SUBWAY`, `WALK`). Kept for debugging only.
  final String otpMode;

  final int? seats;

  bool get isWalk => id == 'walk';

  factory ModeInfo.fromJson(Map<String, dynamic> json) => ModeInfo(
        id: _as<String>(json['id']) ?? 'transit',
        labelEn: _as<String>(json['label_en']) ?? '',
        labelAr: _as<String>(json['label_ar']) ?? '',
        otpMode: _as<String>(json['otp_mode']) ?? '',
        seats: _as<num>(json['seats'])?.toInt(),
      );

  @override
  List<Object?> get props => [id, labelEn, labelAr, otpMode, seats];
}

class RouteInfo extends Equatable {
  const RouteInfo({
    required this.id,
    required this.displayName,
    required this.hasLineNumber,
    this.shortName,
    this.longName,
    this.operator,
    this.operatorId,
    this.source = 'tfc',
    this.confidence = 'confirmed',
  });

  final String id;

  /// What to show. For a route with no number the server has already built
  /// this from origin and destination.
  final String displayName;

  /// False for microbus, tomnaya and the rest of the paratransit network —
  /// hundreds of those routes are literally named "Microbus" because real
  /// microbuses in Cairo carry no number. When this is false the UI must not
  /// render a route-number badge.
  final bool hasLineNumber;

  final String? shortName;
  final String? longName;
  final String? operator;
  final String? operatorId;

  /// Present from day one although TfC is still the only source, because
  /// adding them later would mean revising the client as well as the server.
  final String source;
  final String confidence;

  factory RouteInfo.fromJson(Map<String, dynamic> json) => RouteInfo(
        id: _as<String>(json['id']) ?? '',
        displayName: _as<String>(json['display_name']) ?? '',
        hasLineNumber: _as<bool>(json['has_line_number']) ?? false,
        shortName: _as<String>(json['short_name']),
        longName: _as<String>(json['long_name']),
        operator: _as<String>(json['operator']),
        operatorId: _as<String>(json['operator_id']),
        source: _as<String>(json['source']) ?? 'tfc',
        confidence: _as<String>(json['confidence']) ?? 'confirmed',
      );

  @override
  List<Object?> get props =>
      [id, displayName, hasLineNumber, shortName, longName, operator, operatorId, source, confidence];
}

class Leg extends Equatable {
  const Leg({
    required this.mode,
    required this.isTransit,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.distanceM,
    required this.from,
    required this.to,
    this.route,
    this.headsign,
    this.intermediateStops = 0,
  });

  final ModeInfo mode;
  final bool isTransit;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final int distanceM;
  final Place from;
  final Place to;
  final RouteInfo? route;
  final String? headsign;
  final int intermediateStops;

  factory Leg.fromJson(Map<String, dynamic> json) => Leg(
        mode: ModeInfo.fromJson(_as<Map<String, dynamic>>(json['mode']) ?? const {}),
        isTransit: _as<bool>(json['is_transit']) ?? false,
        startTime: DateTime.parse(json['start_time'] as String),
        endTime: DateTime.parse(json['end_time'] as String),
        durationMinutes: _int(json['duration_minutes']),
        distanceM: _int(json['distance_m']),
        // The wire key is `from`, not `from_` — FastAPI serialises by alias.
        from: Place.fromJson(_as<Map<String, dynamic>>(json['from']) ?? const {}),
        to: Place.fromJson(_as<Map<String, dynamic>>(json['to']) ?? const {}),
        route: json['route'] == null
            ? null
            : RouteInfo.fromJson(json['route'] as Map<String, dynamic>),
        headsign: _as<String>(json['headsign']),
        intermediateStops: _int(json['intermediate_stops']),
      );

  @override
  List<Object?> get props => [
        mode, isTransit, startTime, endTime, durationMinutes,
        distanceM, from, to, route, headsign, intermediateStops,
      ];
}

class Itinerary extends Equatable {
  const Itinerary({
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.walkDistanceM,
    required this.transfers,
    required this.isWalkOnly,
    required this.legs,
  });

  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final int walkDistanceM;
  final int transfers;

  /// No transit leg at all. OSM covers the whole country while the transit
  /// feeds cover Greater Cairo only, so the router will cheerfully offer a
  /// two-hour walk for a trip in a city with no data. **This is not an
  /// answer** — see `TripPresenter`.
  final bool isWalkOnly;

  final List<Leg> legs;

  // There is no fare field, and there is no missing one. The feeds' fares
  // are from 2018; the API does not even request them.

  factory Itinerary.fromJson(Map<String, dynamic> json) => Itinerary(
        startTime: DateTime.parse(json['start_time'] as String),
        endTime: DateTime.parse(json['end_time'] as String),
        durationMinutes: _int(json['duration_minutes']),
        walkDistanceM: _int(json['walk_distance_m']),
        transfers: _int(json['transfers']),
        isWalkOnly: _as<bool>(json['is_walk_only']) ?? false,
        legs: (_as<List<dynamic>>(json['legs']) ?? const [])
            .map((e) => Leg.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  @override
  List<Object?> get props =>
      [startTime, endTime, durationMinutes, walkDistanceM, transfers, isWalkOnly, legs];
}

/// Why an empty result is empty.
///
/// The server sends this alongside `note` so the client can write its own
/// sentence. `note` is English diagnostic prose carrying detail a code cannot
/// — which endpoint was outside coverage, whether the coordinates look
/// swapped — and showing it to a passenger in Cairo would make the
/// empty-result screen the one place this app stops speaking Arabic.
enum NoteCode {
  outOfCoverage,
  outsideServiceHours,
  noRoute,

  /// A code this build does not know. Fall back to `note`: an English
  /// sentence is worse than Arabic copy, and much better than nothing.
  unknown;

  static NoteCode? parse(String? wire) => switch (wire) {
        null => null,
        'out_of_coverage' => NoteCode.outOfCoverage,
        'outside_service_hours' => NoteCode.outsideServiceHours,
        'no_route' => NoteCode.noRoute,
        _ => NoteCode.unknown,
      };
}

class PlanResponse extends Equatable {
  const PlanResponse({
    required this.itineraries,
    required this.attribution,
    this.note,
    this.noteCode,
  });

  final List<Itinerary> itineraries;
  final Attribution attribution;

  /// English prose from the server. A fallback for display, not the first
  /// choice — see [noteCode].
  final String? note;

  /// Set whenever [note] is.
  final NoteCode? noteCode;

  factory PlanResponse.fromJson(Map<String, dynamic> json) => PlanResponse(
        itineraries: (_as<List<dynamic>>(json['itineraries']) ?? const [])
            .map((e) => Itinerary.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        attribution: Attribution.fromJson(
            _as<Map<String, dynamic>>(json['attribution']) ?? const {}),
        note: _as<String>(json['note']),
        noteCode: NoteCode.parse(_as<String>(json['note_code'])),
      );

  @override
  List<Object?> get props => [itineraries, attribution, note, noteCode];
}

class StopSummary extends Equatable {
  const StopSummary({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.modes = const [],
    this.routeCount = 0,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;

  /// Distinct mode ids served, e.g. `['microbus', 'tomnaya']`.
  final List<String> modes;
  final int routeCount;

  factory StopSummary.fromJson(Map<String, dynamic> json) => StopSummary(
        id: _as<String>(json['id']) ?? '',
        name: _as<String>(json['name']) ?? '',
        lat: _double(json['lat']),
        lon: _double(json['lon']),
        modes: (_as<List<dynamic>>(json['modes']) ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
        routeCount: _int(json['route_count']),
      );

  @override
  List<Object?> get props => [id, name, lat, lon, modes, routeCount];
}

class StopsResponse extends Equatable {
  const StopsResponse({
    required this.query,
    required this.stops,
    required this.attribution,
    this.totalMatches = 0,
    this.truncated = false,
  });

  final String query;
  final List<StopSummary> stops;
  final Attribution attribution;

  /// Matches before `limit` was applied. A broad prefix matches hundreds.
  final int totalMatches;

  /// True when there are more matches than were returned, so the UI can ask
  /// for a longer query rather than imply these are all of them.
  final bool truncated;

  factory StopsResponse.fromJson(Map<String, dynamic> json) => StopsResponse(
        query: _as<String>(json['query']) ?? '',
        stops: (_as<List<dynamic>>(json['stops']) ?? const [])
            .map((e) => StopSummary.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        attribution: Attribution.fromJson(
            _as<Map<String, dynamic>>(json['attribution']) ?? const {}),
        totalMatches: _int(json['total_matches']),
        truncated: _as<bool>(json['truncated']) ?? false,
      );

  @override
  List<Object?> get props => [query, stops, attribution, totalMatches, truncated];
}
