import 'package:equatable/equatable.dart';

import '../../../core/presentation/place_presenter.dart';
import '../../../data/models/models.dart';
import '../../../data/models/place_models.dart';
import '../../../domain/entities/trip_endpoint.dart';

sealed class MapPickState extends Equatable {
  const MapPickState();

  @override
  List<Object?> get props => const [];
}

/// The map has not reported a position yet.
class MapPickIdle extends MapPickState {
  const MapPickIdle();
}

/// The pin has settled and the two lookups are in flight.
class MapPickLoading extends MapPickState {
  const MapPickLoading(this.point);

  final GeoPoint point;

  @override
  List<Object?> get props => [point];
}

/// The pin is somewhere the app has no data for. Caught before spending a
/// request, as `MyLocationCubit` does — the map is bounded to the coverage box
/// so this is a rounding edge rather than a normal state.
class MapPickOutside extends MapPickState {
  const MapPickOutside(this.point);

  final GeoPoint point;

  @override
  List<Object?> get props => [point];
}

/// Both lookups finished, one way or another.
///
/// The name and the nearest stop are **two datasets** (OSM and TfC) asked for
/// separately and carried separately all the way to the screen. Either can be
/// missing for two different reasons that must not be confused:
///
/// - the lookup *worked* and found nothing ([place] null, [nameUnavailable]
///   false) — a real answer, because much of Greater Cairo has no addressing a
///   stranger could use;
/// - the lookup *failed* ([nameUnavailable] true) — nothing is known.
class MapPickReady extends MapPickState {
  const MapPickReady({
    required this.point,
    required this.place,
    required this.nameUnavailable,
    required this.nearestStop,
    required this.stopUnavailable,
    required this.stopRadiusM,
    this.placesAttribution,
    this.stopsAttribution,
  });

  final GeoPoint point;

  /// The nearest named thing OSM has, or null for "nothing named here".
  final PlaceVm? place;
  final bool nameUnavailable;

  /// The nearest stop within [stopRadiusM], or null for none that close.
  final NearbyStop? nearestStop;
  final bool stopUnavailable;

  /// How far the stop lookup looked, so "no stop nearby" can say how far
  /// nearby was.
  final int stopRadiusM;

  /// OpenStreetMap's credit; null when the name lookup failed.
  final Attribution? placesAttribution;

  /// The transit data's credit; null when the stop lookup failed.
  final Attribution? stopsAttribution;

  @override
  List<Object?> get props => [
    point,
    place,
    nameUnavailable,
    nearestStop,
    stopUnavailable,
    stopRadiusM,
    placesAttribution,
    stopsAttribution,
  ];
}
