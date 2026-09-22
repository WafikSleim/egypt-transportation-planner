import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../core/storage/key_value_store.dart';
import '../../domain/entities/trip_endpoint.dart';

/// A trip the user asked to keep.
///
/// Deliberately a **pair of endpoints, not a saved itinerary.** The itinerary
/// is recomputed for today every time: the one that was on screen when this
/// was saved has departure times in it, and those are wrong by tomorrow.
/// Storing it would mean showing someone a trip that left last Tuesday.
class SavedTrip extends Equatable {
  const SavedTrip({
    required this.from,
    required this.to,
    required this.savedAt,
  });

  final TripEndpoint from;
  final TripEndpoint to;
  final DateTime savedAt;

  /// Stable for the same pair of places, so saving twice replaces rather than
  /// duplicates, and the search screen can tell whether what is in the form
  /// is already saved.
  String get id => '${_key(from)}>${_key(to)}';

  static String _key(TripEndpoint e) =>
      e.stopId ??
      // No stop id means a raw point — from the map, or from "my location".
      // Rounded to about 10 m, so two fixes of the same doorway count as the
      // same place rather than filling the list with near-duplicates.
      '${e.point.lat.toStringAsFixed(4)},${e.point.lon.toStringAsFixed(4)}';

  Map<String, dynamic> toJson() => {
    'from': _endpointToJson(from),
    'to': _endpointToJson(to),
    'saved_at': savedAt.toIso8601String(),
  };

  static SavedTrip? fromJson(Map<String, dynamic> json) {
    final from = _endpointFromJson(json['from']);
    final to = _endpointFromJson(json['to']);
    if (from == null || to == null) return null;
    return SavedTrip(
      from: from,
      to: to,
      savedAt: DateTime.tryParse('${json['saved_at']}') ?? DateTime(2000),
    );
  }

  @override
  List<Object?> get props => [from, to, savedAt];
}

Map<String, dynamic> _endpointToJson(TripEndpoint e) => {
  'label': e.label,
  'lat': e.point.lat,
  'lon': e.point.lon,
  if (e.stopId != null) 'stop_id': e.stopId,
  if (e.modes.isNotEmpty) 'modes': e.modes,
};

TripEndpoint? _endpointFromJson(Object? raw) {
  if (raw is! Map) return null;
  final label = raw['label'];
  final lat = raw['lat'];
  final lon = raw['lon'];
  if (label is! String || lat is! num || lon is! num) return null;
  return TripEndpoint(
    label: label,
    point: GeoPoint(lat.toDouble(), lon.toDouble()),
    stopId: raw['stop_id'] is String ? raw['stop_id'] as String : null,
    modes: (raw['modes'] as List?)?.map((e) => '$e').toList() ?? const [],
  );
}

/// Recents and saved trips.
///
/// **On device only.** There is no account, nothing is uploaded, and nothing
/// here is ever sent with a request. That is not an implementation detail: it
/// is what the app tells the user before it asks for their location, and it
/// stays true only as long as this class does nothing clever.
///
/// Reads are synchronous for the same reason as [KeyValueStore] — the picker
/// has to draw recents in its first frame, and an async read there is a
/// visible flicker on a cheap phone.
class TripHistory {
  TripHistory(this._store);

  static const _recentsKey = 'recent_endpoints';
  static const _savedKey = 'saved_trips';

  /// Enough to cover the places somebody actually goes, short enough to scan
  /// without scrolling. A recents list that needs scrolling has stopped being
  /// a shortcut.
  static const maxRecents = 8;

  final KeyValueStore _store;

  // ---------------------------------------------------------------- recents

  List<TripEndpoint> recents() => _readList(
    _recentsKey,
  ).map(_endpointFromJson).whereType<TripEndpoint>().toList(growable: false);

  /// Most recent first, de-duplicated by place rather than by label — the
  /// same stop reached from the picker and from the map should not appear
  /// twice because one of them spelled it differently.
  Future<void> remember(TripEndpoint endpoint) async {
    final key = SavedTrip._key(endpoint);
    final kept = [
      endpoint,
      ...recents().where((e) => SavedTrip._key(e) != key),
    ].take(maxRecents);

    await _writeList(_recentsKey, kept.map(_endpointToJson).toList());
  }

  Future<void> clearRecents() => _store.remove(_recentsKey);

  // ------------------------------------------------------------------ saved

  List<SavedTrip> saved() {
    final trips = _readList(_savedKey)
        .map((e) => e is Map<String, dynamic> ? SavedTrip.fromJson(e) : null)
        .whereType<SavedTrip>()
        .toList();
    trips.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return List.unmodifiable(trips);
  }

  bool isSaved(TripEndpoint from, TripEndpoint to) {
    final id = SavedTrip(from: from, to: to, savedAt: DateTime(2000)).id;
    return saved().any((t) => t.id == id);
  }

  Future<void> save(TripEndpoint from, TripEndpoint to) async {
    final trip = SavedTrip(from: from, to: to, savedAt: DateTime.now());
    final kept = [trip, ...saved().where((t) => t.id != trip.id)];
    await _writeList(_savedKey, kept.map((t) => t.toJson()).toList());
  }

  Future<void> unsave(String id) async {
    final kept = saved().where((t) => t.id != id);
    await _writeList(_savedKey, kept.map((t) => t.toJson()).toList());
  }

  // ------------------------------------------------------------------ plumbing

  /// Stored as a JSON object with a `items` array rather than a bare array,
  /// because [KeyValueStore.readJson] returns an object and because a version
  /// field can be added beside it later without a migration.
  List<dynamic> _readList(String key) {
    final json = _store.readJson(key);
    final items = json?['items'];
    return items is List ? items : const [];
  }

  Future<void> _writeList(String key, List<Map<String, dynamic>> items) =>
      _store.write(key, jsonEncode({'items': items}));
}
