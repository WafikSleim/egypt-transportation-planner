import 'package:equatable/equatable.dart';

import '../../data/models/models.dart';
import '../../data/models/place_models.dart';

class GeoPoint extends Equatable {
  const GeoPoint(this.lat, this.lon);

  final double lat;
  final double lon;

  /// The wire form the API expects: `lat,lon`. Note the order — the API
  /// detects a swapped pair and says so, but a swap inside Egypt's bounding
  /// box lands in the Mediterranean and plans a very long walk instead.
  String get wire => '$lat,$lon';

  @override
  List<Object?> get props => [lat, lon];
}

/// Which of the three kinds of thing an endpoint is. They are drawn with
/// different marks because they behave differently: a stop is where a vehicle
/// calls, a place is where you are going, and a point is just a spot.
enum EndpointKind { stop, place, point }

/// Somewhere a trip starts or ends.
///
/// A transit stop, a place from the OSM index, or a plain point — from the
/// map or from the user's own location. The router takes coordinates in every
/// case; [stopId] and [placeId] are kept so the UI can show the right mark
/// (and so a recent can be recognised for what it was). At most one is set.
class TripEndpoint extends Equatable {
  const TripEndpoint({
    required this.label,
    required this.point,
    this.stopId,
    this.placeId,
    this.modes = const [],
  }) : assert(
         stopId == null || placeId == null,
         'An endpoint is a stop or a place, never both — they are two '
         'datasets under two licences.',
       );

  factory TripEndpoint.fromStop(StopSummary stop) => TripEndpoint(
    label: stop.name,
    point: GeoPoint(stop.lat, stop.lon),
    stopId: stop.id,
    modes: stop.modes,
  );

  /// [label] is passed in rather than read off [place]: the view model has
  /// already decided which name the passenger saw, and the recent should
  /// remember that one.
  factory TripEndpoint.fromPlace(PlaceResult place, {required String label}) =>
      TripEndpoint(
        label: label,
        point: GeoPoint(place.lat, place.lon),
        placeId: place.id,
      );

  final String label;
  final GeoPoint point;
  final String? stopId;

  /// OSM id (`n123`, `w456`). Null for stops and plain points.
  final String? placeId;
  final List<String> modes;

  bool get isStop => stopId != null;
  bool get isPlace => placeId != null;

  EndpointKind get kind => stopId != null
      ? EndpointKind.stop
      : placeId != null
      ? EndpointKind.place
      : EndpointKind.point;

  @override
  List<Object?> get props => [label, point, stopId, placeId, modes];
}
