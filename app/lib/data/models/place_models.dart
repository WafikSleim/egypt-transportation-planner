/// Wire models for the OSM place index and the nearby-stop lookup.
///
/// Kept out of `models.dart` on purpose. Everything in that file is transit
/// data under TfC's licence; everything in this one except [NearbyStop] is
/// OpenStreetMap under ODbL, and the two are never to be built from, stored
/// beside or joined to each other. A second file is a small, visible version
/// of the separate database the server keeps.
///
/// [NearbyStop] is transit data and lives here only because it answers the
/// map-pick screen's question; it arrives in its own response with its own
/// attribution and is never merged into a [PlaceResult].
library;

import 'package:equatable/equatable.dart';

import 'models.dart';

T? _as<T>(Object? v) => v is T ? v : null;

int _int(Object? v) => v is num ? v.toInt() : 0;

double _double(Object? v) => v is num ? v.toDouble() : 0;

/// What kind of thing a place is, **already translated by the server** — the
/// same arrangement as [ModeInfo], for the same reason: a category the client
/// had to translate is a category that shows in English on an Arabic screen
/// the first time the server adds one.
class PlaceCategory extends Equatable {
  const PlaceCategory({
    required this.id,
    required this.labelEn,
    required this.labelAr,
  });

  final String id;
  final String labelEn;
  final String labelAr;

  factory PlaceCategory.fromJson(Map<String, dynamic> json) => PlaceCategory(
    id: _as<String>(json['id']) ?? '',
    labelEn: _as<String>(json['label_en']) ?? '',
    labelAr: _as<String>(json['label_ar']) ?? '',
  );

  @override
  List<Object?> get props => [id, labelEn, labelAr];
}

/// One row from `/places` or `/places/reverse`.
///
/// Named like the API's `PlaceResult`, and not to be confused with [Place],
/// which is the end of a transit leg.
class PlaceResult extends Equatable {
  const PlaceResult({
    required this.id,
    required this.name,
    required this.nameLanguage,
    required this.nameIsFallback,
    required this.category,
    required this.lat,
    required this.lon,
    this.nameAr,
    this.nameEn,
    this.area,
    this.distanceM,
    this.source = 'osm',
    this.confidence = 'reported',
  });

  /// `n123` / `w456` — OSM's own id.
  final String id;

  /// What to show, for the language that was requested.
  final String name;

  /// Which language [name] is actually in: `ar` or `en`. Drives text
  /// direction and the "no Arabic name" note — never inferred from the
  /// characters on the client.
  final String nameLanguage;

  /// OSM had no name in the requested language and [name] is the other one.
  final bool nameIsFallback;

  final String? nameAr;
  final String? nameEn;
  final PlaceCategory category;

  /// Containing district, for telling two same-named places apart.
  final String? area;
  final double lat;
  final double lon;

  /// Straight-line metres from the `near` point, when one was sent. Null
  /// otherwise — and then there is nothing to show, not zero.
  final int? distanceM;

  final String source;
  final String confidence;

  factory PlaceResult.fromJson(Map<String, dynamic> json) => PlaceResult(
    id: _as<String>(json['id']) ?? '',
    name: _as<String>(json['name']) ?? '',
    nameLanguage: _as<String>(json['name_language']) ?? 'ar',
    nameIsFallback: _as<bool>(json['name_is_fallback']) ?? false,
    nameAr: _as<String>(json['name_ar']),
    nameEn: _as<String>(json['name_en']),
    category: PlaceCategory.fromJson(
      _as<Map<String, dynamic>>(json['category']) ?? const {},
    ),
    area: _as<String>(json['area']),
    lat: _double(json['lat']),
    lon: _double(json['lon']),
    distanceM: _as<num>(json['distance_m'])?.toInt(),
    source: _as<String>(json['source']) ?? 'osm',
    confidence: _as<String>(json['confidence']) ?? 'reported',
  );

  @override
  List<Object?> get props => [
    id,
    name,
    nameLanguage,
    nameIsFallback,
    nameAr,
    nameEn,
    category,
    area,
    lat,
    lon,
    distanceM,
    source,
    confidence,
  ];
}

class PlacesResponse extends Equatable {
  const PlacesResponse({
    required this.query,
    required this.places,
    required this.attribution,
    this.totalMatches = 0,
    this.truncated = false,
    this.matching = 'substring',
  });

  final String query;
  final List<PlaceResult> places;

  /// OpenStreetMap's credit — **not** the transit data's. Two datasets, two
  /// licences, each credited where it is shown.
  final Attribution attribution;
  final int totalMatches;
  final bool truncated;

  /// `substring` for search, `nearest` for reverse geocoding.
  final String matching;

  factory PlacesResponse.fromJson(Map<String, dynamic> json) => PlacesResponse(
    query: _as<String>(json['query']) ?? '',
    totalMatches: _int(json['total_matches']),
    truncated: _as<bool>(json['truncated']) ?? false,
    matching: _as<String>(json['matching']) ?? 'substring',
    places: (_as<List<dynamic>>(json['places']) ?? const [])
        .map((e) => PlaceResult.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    attribution: Attribution.fromJson(
      _as<Map<String, dynamic>>(json['attribution']) ?? const {},
    ),
  );

  @override
  List<Object?> get props => [
    query,
    places,
    attribution,
    totalMatches,
    truncated,
    matching,
  ];
}

/// A stop and how far it is from a point, from `/stops/nearby`.
class NearbyStop extends Equatable {
  const NearbyStop({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.distanceM,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;

  /// Straight-line metres, not a walking distance.
  final int distanceM;

  factory NearbyStop.fromJson(Map<String, dynamic> json) => NearbyStop(
    id: _as<String>(json['id']) ?? '',
    name: _as<String>(json['name']) ?? '',
    lat: _double(json['lat']),
    lon: _double(json['lon']),
    distanceM: _int(json['distance_m']),
  );

  @override
  List<Object?> get props => [id, name, lat, lon, distanceM];
}

class NearbyStopsResponse extends Equatable {
  const NearbyStopsResponse({required this.stops, required this.attribution});

  /// Nearest first.
  final List<NearbyStop> stops;

  /// The transit data's (TfC) — a different credit from [PlacesResponse]'s.
  final Attribution attribution;

  factory NearbyStopsResponse.fromJson(Map<String, dynamic> json) =>
      NearbyStopsResponse(
        stops: (_as<List<dynamic>>(json['stops']) ?? const [])
            .map((e) => NearbyStop.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        attribution: Attribution.fromJson(
          _as<Map<String, dynamic>>(json['attribution']) ?? const {},
        ),
      );

  @override
  List<Object?> get props => [stops, attribution];
}
