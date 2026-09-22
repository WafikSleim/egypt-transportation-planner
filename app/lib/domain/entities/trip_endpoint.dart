import 'package:equatable/equatable.dart';

import '../../data/models/models.dart';

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

/// Somewhere a trip starts or ends.
///
/// Either a transit stop the user picked, or a plain point — from the map,
/// or from their own location. The router takes coordinates either way; the
/// [stopId] is kept so the UI can show the stop's own mark rather than a
/// generic pin.
class TripEndpoint extends Equatable {
  const TripEndpoint({
    required this.label,
    required this.point,
    this.stopId,
    this.modes = const [],
  });

  factory TripEndpoint.fromStop(StopSummary stop) => TripEndpoint(
    label: stop.name,
    point: GeoPoint(stop.lat, stop.lon),
    stopId: stop.id,
    modes: stop.modes,
  );

  final String label;
  final GeoPoint point;
  final String? stopId;
  final List<String> modes;

  bool get isStop => stopId != null;

  @override
  List<Object?> get props => [label, point, stopId, modes];
}
